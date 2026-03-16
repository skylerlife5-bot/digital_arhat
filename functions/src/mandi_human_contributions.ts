import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {
  ContributorProfile,
  HumanContributionSubmission,
  UnifiedMandiRate,
} from "./sources/types";
import {evaluateHumanContributionSubmission} from "./sources/human_contribution_intake";
import {toContributorPublicView} from "./sources/contributor_profiles";

const CONTRIBUTOR_COLLECTION = "mandi_contributors";
const CONTRIBUTION_COLLECTION = "mandi_rate_contributions";
const LIVE_RATES_COLLECTION = "mandi_rates";

const PAKISTAN_PROVINCES = new Set<string>([
  "punjab",
  "sindh",
  "balochistan",
  "khyber pakhtunkhwa",
  "kpk",
  "gilgit baltistan",
  "azad kashmir",
  "islamabad",
]);

function getApp(): admin.app.App {
  if (admin.apps.length > 0) return admin.app();
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  return projectId ? admin.initializeApp({projectId}) : admin.initializeApp();
}

function getDb(): FirebaseFirestore.Firestore {
  return getApp().firestore();
}

function mustString(value: unknown, field: string): string {
  const out = String(value ?? "").trim();
  if (!out) throw new HttpsError("invalid-argument", `${field} is required`);
  return out;
}

function mustPositiveNumber(value: unknown, field: string): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new HttpsError("invalid-argument", `${field} must be a positive number`);
  }
  return parsed;
}

function parseDate(value: unknown): Date {
  if (value instanceof Date) return value;
  if (value instanceof Timestamp) return value.toDate();
  const parsed = new Date(String(value ?? ""));
  if (Number.isNaN(parsed.getTime())) return new Date();
  return parsed;
}

function toPayload(record: UnifiedMandiRate): Record<string, unknown> {
  return {
    ...record,
    lastUpdated: Timestamp.fromDate(record.lastUpdated),
    syncedAt: FieldValue.serverTimestamp(),
    submissionTimestamp: record.submissionTimestamp ? Timestamp.fromDate(record.submissionTimestamp) : null,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function loadContributorProfile(
  db: FirebaseFirestore.Firestore,
  contributorId: string,
): Promise<ContributorProfile> {
  const snap = await db.collection(CONTRIBUTOR_COLLECTION).doc(contributorId).get();
  if (!snap.exists) {
    throw new HttpsError("failed-precondition", "contributor_profile_not_found");
  }

  const data = snap.data() as Record<string, unknown>;
  const lastSubmissionAtRaw = data.lastSubmissionAt;

  const profile: ContributorProfile = {
    contributorId,
    displayName: String(data.displayName ?? "Contributor").trim(),
    maskedContactRef: String(data.maskedContactRef ?? "hidden").trim(),
    city: String(data.city ?? "").trim(),
    district: String(data.district ?? "").trim(),
    province: String(data.province ?? "").trim(),
    contributorType: String(data.contributorType ?? "trusted_local_contributor") as ContributorProfile["contributorType"],
    verificationStatus: String(data.verificationStatus ?? "pending") as ContributorProfile["verificationStatus"],
    trustScore: Number(data.trustScore ?? 0.5),
    reliabilityScore: Number(data.reliabilityScore ?? 0.5),
    totalSubmissions: Number(data.totalSubmissions ?? 0),
    acceptedSubmissions: Number(data.acceptedSubmissions ?? 0),
    rejectedSubmissions: Number(data.rejectedSubmissions ?? 0),
    disputedSubmissions: Number(data.disputedSubmissions ?? 0),
    citySpecificReliability: (data.citySpecificReliability ?? {}) as Record<string, number>,
    suspiciousSpikeCount: Number(data.suspiciousSpikeCount ?? 0),
    lastSubmissionAt: lastSubmissionAtRaw instanceof Timestamp
      ? lastSubmissionAtRaw.toDate()
      : lastSubmissionAtRaw instanceof Date
        ? lastSubmissionAtRaw
        : null,
    penaltyLevel: String(data.penaltyLevel ?? "none") as ContributorProfile["penaltyLevel"],
    activeStatus: String(data.activeStatus ?? "active") as ContributorProfile["activeStatus"],
    metadata: (data.metadata ?? {}) as Record<string, unknown>,
  };

  if (profile.activeStatus === "suspended" || profile.verificationStatus === "suspended") {
    throw new HttpsError("permission-denied", "contributor_suspended");
  }

  return profile;
}

async function loadComparableRates(
  db: FirebaseFirestore.Firestore,
  city: string,
  commodityName: string,
): Promise<{official: UnifiedMandiRate[]; trustedHuman: UnifiedMandiRate[]; hasStrongOfficial: boolean}> {
  const snapshot = await db
    .collection(LIVE_RATES_COLLECTION)
    .where("city", "==", city)
    .where("commodityName", "==", commodityName)
    .limit(60)
    .get();

  const official: UnifiedMandiRate[] = [];
  const trustedHuman: UnifiedMandiRate[] = [];

  for (const doc of snapshot.docs) {
    const map = doc.data();
    const contributorType = String(map.contributorType ?? "official").trim().toLowerCase();
    const verificationStatus = String(map.verificationStatus ?? "").trim();
    const confidenceScore = Number(map.confidenceScore ?? 0);
    const rate: UnifiedMandiRate = {
      id: String(map.id ?? doc.id),
      commodityName: String(map.commodityName ?? "").trim(),
      commodityNameUr: String(map.commodityNameUr ?? "").trim(),
      categoryName: String(map.categoryName ?? "crops").trim(),
      subCategoryName: String(map.subCategoryName ?? "other").trim(),
      mandiName: String(map.mandiName ?? "").trim(),
      city: String(map.city ?? "").trim(),
      district: String(map.district ?? "").trim(),
      province: String(map.province ?? "").trim(),
      latitude: typeof map.latitude === "number" ? map.latitude : null,
      longitude: typeof map.longitude === "number" ? map.longitude : null,
      price: Number(map.price ?? 0),
      previousPrice: typeof map.previousPrice === "number" ? map.previousPrice : null,
      minPrice: typeof map.minPrice === "number" ? map.minPrice : null,
      maxPrice: typeof map.maxPrice === "number" ? map.maxPrice : null,
      unit: String(map.unit ?? "PKR/100kg").trim(),
      currency: String(map.currency ?? "PKR").trim(),
      trend: (String(map.trend ?? "same") as "up" | "down" | "same"),
      source: String(map.source ?? "").trim(),
      sourceId: String(map.sourceId ?? "").trim(),
      sourceType: String(map.sourceType ?? "official_aggregator") as UnifiedMandiRate["sourceType"],
      lastUpdated: map.lastUpdated instanceof Timestamp ? map.lastUpdated.toDate() : new Date(),
      syncedAt: new Date(),
      freshnessStatus: String(map.freshnessStatus ?? "aging") as UnifiedMandiRate["freshnessStatus"],
      confidenceScore,
      confidenceReason: String(map.confidenceReason ?? "").trim(),
      verificationStatus: verificationStatus as UnifiedMandiRate["verificationStatus"],
      contributorType: contributorType as UnifiedMandiRate["contributorType"],
      isNearby: map.isNearby === true,
      isAiCleaned: map.isAiCleaned === true,
      metadata: (map.metadata ?? {}) as Record<string, unknown>,
    };

    if (contributorType === "official") {
      official.push(rate);
    } else if (
      (contributorType === "verified_mandi_reporter" ||
        contributorType === "verified_commission_agent" ||
        contributorType === "verified_dealer" ||
        contributorType === "trusted_local_contributor") &&
      confidenceScore >= 0.68
    ) {
      trustedHuman.push(rate);
    }
  }

  const hasStrongOfficial = official.some((item) =>
    (item.verificationStatus === "Official Verified" || item.verificationStatus === "Cross-Checked") &&
    item.confidenceScore >= 0.7,
  );

  return {official, trustedHuman, hasStrongOfficial};
}

export const submitMandiContribution = onCall(
  {
    region: "asia-south1",
    timeoutSeconds: 60,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "auth_required");
    }

    const db = getDb();
    const payload = (request.data ?? {}) as Record<string, unknown>;

    const contributorId = mustString(payload.contributorId, "contributorId");
    const profile = await loadContributorProfile(db, contributorId);

    if (request.auth.uid !== contributorId) {
      throw new HttpsError("permission-denied", "contributor_identity_mismatch");
    }

    const province = mustString(payload.province, "province");
    if (!PAKISTAN_PROVINCES.has(province.toLowerCase())) {
      throw new HttpsError("invalid-argument", "pakistan_only_submission");
    }

    const submission: HumanContributionSubmission = {
      submissionId: String(payload.submissionId ?? `sub_${Date.now()}`),
      contributorId,
      contributorType: profile.contributorType,
      verificationStatus: profile.verificationStatus,
      commodityName: mustString(payload.commodityName, "commodityName"),
      commodityNameUr: String(payload.commodityNameUr ?? "").trim() || undefined,
      categoryName: String(payload.categoryName ?? "").trim() || undefined,
      subCategoryName: String(payload.subCategoryName ?? "").trim() || undefined,
      mandiName: mustString(payload.mandiName, "mandiName"),
      city: mustString(payload.city, "city"),
      district: String(payload.district ?? "").trim() || undefined,
      province,
      price: mustPositiveNumber(payload.price, "price"),
      previousPrice: payload.previousPrice == null ? null : Number(payload.previousPrice),
      minPrice: payload.minPrice == null ? null : Number(payload.minPrice),
      maxPrice: payload.maxPrice == null ? null : Number(payload.maxPrice),
      unit: String(payload.unit ?? "").trim() || undefined,
      currency: String(payload.currency ?? "PKR").trim(),
      latitude: payload.latitude == null ? null : Number(payload.latitude),
      longitude: payload.longitude == null ? null : Number(payload.longitude),
      submissionTimestamp: parseDate(payload.submissionTimestamp),
      metadata: {
        appVersion: String(payload.appVersion ?? "").trim(),
      },
    };

    const comparable = await loadComparableRates(db, submission.city, submission.commodityName);

    const outcome = evaluateHumanContributionSubmission({
      profile,
      submission,
      comparable: {
        officialComparable: comparable.official,
        trustedHumanComparable: comparable.trustedHuman,
        hasStrongOfficialEquivalent: comparable.hasStrongOfficial,
      },
      now: new Date(),
    });

    const contributionDocRef = db.collection(CONTRIBUTION_COLLECTION).doc(outcome.record.id);
    await contributionDocRef.set({
      ...toPayload(outcome.record),
      createdAt: FieldValue.serverTimestamp(),
      contributorPublic: toContributorPublicView(profile),
    }, {merge: true});

    if (outcome.decision.acceptedBySystem && outcome.decision.reviewStatus !== "rejected") {
      await db.collection(LIVE_RATES_COLLECTION).doc(outcome.record.id).set(toPayload(outcome.record), {
        merge: true,
      });
    }

    await db.collection(CONTRIBUTOR_COLLECTION).doc(contributorId).set({
      totalSubmissions: FieldValue.increment(1),
      acceptedSubmissions: FieldValue.increment(outcome.decision.reviewStatus === "accepted" ? 1 : 0),
      rejectedSubmissions: FieldValue.increment(outcome.decision.reviewStatus === "rejected" ? 1 : 0),
      lastSubmissionAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      ok: true,
      submissionId: submission.submissionId,
      recordId: outcome.record.id,
      decision: outcome.decision,
    };
  },
);
