"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.submitMandiContribution = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const human_contribution_intake_1 = require("./sources/human_contribution_intake");
const contributor_profiles_1 = require("./sources/contributor_profiles");
const CONTRIBUTOR_COLLECTION = "mandi_contributors";
const CONTRIBUTION_COLLECTION = "mandi_rate_contributions";
const LIVE_RATES_COLLECTION = "mandi_rates";
const PAKISTAN_PROVINCES = new Set([
    "punjab",
    "sindh",
    "balochistan",
    "khyber pakhtunkhwa",
    "kpk",
    "gilgit baltistan",
    "azad kashmir",
    "islamabad",
]);
function getApp() {
    if (admin.apps.length > 0)
        return admin.app();
    const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
    return projectId ? admin.initializeApp({ projectId }) : admin.initializeApp();
}
function getDb() {
    return getApp().firestore();
}
function mustString(value, field) {
    const out = String(value ?? "").trim();
    if (!out)
        throw new https_1.HttpsError("invalid-argument", `${field} is required`);
    return out;
}
function mustPositiveNumber(value, field) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed <= 0) {
        throw new https_1.HttpsError("invalid-argument", `${field} must be a positive number`);
    }
    return parsed;
}
function parseDate(value) {
    if (value instanceof Date)
        return value;
    if (value instanceof firestore_1.Timestamp)
        return value.toDate();
    const parsed = new Date(String(value ?? ""));
    if (Number.isNaN(parsed.getTime()))
        return new Date();
    return parsed;
}
function toPayload(record) {
    return {
        ...record,
        lastUpdated: firestore_1.Timestamp.fromDate(record.lastUpdated),
        syncedAt: firestore_1.FieldValue.serverTimestamp(),
        submissionTimestamp: record.submissionTimestamp ? firestore_1.Timestamp.fromDate(record.submissionTimestamp) : null,
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    };
}
async function loadContributorProfile(db, contributorId) {
    const snap = await db.collection(CONTRIBUTOR_COLLECTION).doc(contributorId).get();
    if (!snap.exists) {
        throw new https_1.HttpsError("failed-precondition", "contributor_profile_not_found");
    }
    const data = snap.data();
    const lastSubmissionAtRaw = data.lastSubmissionAt;
    const profile = {
        contributorId,
        displayName: String(data.displayName ?? "Contributor").trim(),
        maskedContactRef: String(data.maskedContactRef ?? "hidden").trim(),
        city: String(data.city ?? "").trim(),
        district: String(data.district ?? "").trim(),
        province: String(data.province ?? "").trim(),
        contributorType: String(data.contributorType ?? "trusted_local_contributor"),
        verificationStatus: String(data.verificationStatus ?? "pending"),
        trustScore: Number(data.trustScore ?? 0.5),
        reliabilityScore: Number(data.reliabilityScore ?? 0.5),
        totalSubmissions: Number(data.totalSubmissions ?? 0),
        acceptedSubmissions: Number(data.acceptedSubmissions ?? 0),
        rejectedSubmissions: Number(data.rejectedSubmissions ?? 0),
        disputedSubmissions: Number(data.disputedSubmissions ?? 0),
        citySpecificReliability: (data.citySpecificReliability ?? {}),
        suspiciousSpikeCount: Number(data.suspiciousSpikeCount ?? 0),
        lastSubmissionAt: lastSubmissionAtRaw instanceof firestore_1.Timestamp
            ? lastSubmissionAtRaw.toDate()
            : lastSubmissionAtRaw instanceof Date
                ? lastSubmissionAtRaw
                : null,
        penaltyLevel: String(data.penaltyLevel ?? "none"),
        activeStatus: String(data.activeStatus ?? "active"),
        metadata: (data.metadata ?? {}),
    };
    if (profile.activeStatus === "suspended" || profile.verificationStatus === "suspended") {
        throw new https_1.HttpsError("permission-denied", "contributor_suspended");
    }
    return profile;
}
async function loadComparableRates(db, city, commodityName) {
    const snapshot = await db
        .collection(LIVE_RATES_COLLECTION)
        .where("city", "==", city)
        .where("commodityName", "==", commodityName)
        .limit(60)
        .get();
    const official = [];
    const trustedHuman = [];
    for (const doc of snapshot.docs) {
        const map = doc.data();
        const contributorType = String(map.contributorType ?? "official").trim().toLowerCase();
        const verificationStatus = String(map.verificationStatus ?? "").trim();
        const confidenceScore = Number(map.confidenceScore ?? 0);
        const rate = {
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
            trend: String(map.trend ?? "same"),
            source: String(map.source ?? "").trim(),
            sourceId: String(map.sourceId ?? "").trim(),
            sourceType: String(map.sourceType ?? "official_aggregator"),
            lastUpdated: map.lastUpdated instanceof firestore_1.Timestamp ? map.lastUpdated.toDate() : new Date(),
            syncedAt: new Date(),
            freshnessStatus: String(map.freshnessStatus ?? "aging"),
            confidenceScore,
            confidenceReason: String(map.confidenceReason ?? "").trim(),
            verificationStatus: verificationStatus,
            contributorType: contributorType,
            isNearby: map.isNearby === true,
            isAiCleaned: map.isAiCleaned === true,
            metadata: (map.metadata ?? {}),
        };
        if (contributorType === "official") {
            official.push(rate);
        }
        else if ((contributorType === "verified_mandi_reporter" ||
            contributorType === "verified_commission_agent" ||
            contributorType === "verified_dealer" ||
            contributorType === "trusted_local_contributor") &&
            confidenceScore >= 0.68) {
            trustedHuman.push(rate);
        }
    }
    const hasStrongOfficial = official.some((item) => (item.verificationStatus === "Official Verified" || item.verificationStatus === "Cross-Checked") &&
        item.confidenceScore >= 0.7);
    return { official, trustedHuman, hasStrongOfficial };
}
exports.submitMandiContribution = (0, https_1.onCall)({
    region: "asia-south1",
    timeoutSeconds: 60,
    memory: "512MiB",
}, async (request) => {
    if (!request.auth?.uid) {
        throw new https_1.HttpsError("unauthenticated", "auth_required");
    }
    const db = getDb();
    const payload = (request.data ?? {});
    const contributorId = mustString(payload.contributorId, "contributorId");
    const profile = await loadContributorProfile(db, contributorId);
    if (request.auth.uid !== contributorId) {
        throw new https_1.HttpsError("permission-denied", "contributor_identity_mismatch");
    }
    const province = mustString(payload.province, "province");
    if (!PAKISTAN_PROVINCES.has(province.toLowerCase())) {
        throw new https_1.HttpsError("invalid-argument", "pakistan_only_submission");
    }
    const submission = {
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
    const outcome = (0, human_contribution_intake_1.evaluateHumanContributionSubmission)({
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
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        contributorPublic: (0, contributor_profiles_1.toContributorPublicView)(profile),
    }, { merge: true });
    if (outcome.decision.acceptedBySystem && outcome.decision.reviewStatus !== "rejected") {
        await db.collection(LIVE_RATES_COLLECTION).doc(outcome.record.id).set(toPayload(outcome.record), {
            merge: true,
        });
    }
    await db.collection(CONTRIBUTOR_COLLECTION).doc(contributorId).set({
        totalSubmissions: firestore_1.FieldValue.increment(1),
        acceptedSubmissions: firestore_1.FieldValue.increment(outcome.decision.reviewStatus === "accepted" ? 1 : 0),
        rejectedSubmissions: firestore_1.FieldValue.increment(outcome.decision.reviewStatus === "rejected" ? 1 : 0),
        lastSubmissionAt: firestore_1.FieldValue.serverTimestamp(),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
        ok: true,
        submissionId: submission.submissionId,
        recordId: outcome.record.id,
        decision: outcome.decision,
    };
});
