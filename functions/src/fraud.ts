import * as admin from "firebase-admin";
import {Firestore} from "firebase-admin/firestore";
import {
  GeoPointLike,
  haversineDistanceKm,
  isWithinPakistanBounds,
  normalizeProductKey,
  toNumber,
  uniqueStrings,
} from "./utils";

export type ListingForFraud = {
  sellerId: string;
  product: string;
  mandiType?: string;
  province: string;
  district: string;
  village: string;
  description: string;
  price: number;
  quantity: number;
  unitType?: string;
  verificationGeo: GeoPointLike;
  verificationCapturedAt: string;
};

export type UserForFraud = {
  trustScore?: number;
  strikes?: number;
  lastKnownGeo?: GeoPointLike;
  listingsToday?: number;
  isBanned?: boolean;
};

export type FraudResult = {
  riskScore: number;
  fraudFlags: string[];
};

type MarketRateLookupContext = {
  productIdOrKey?: string;
  productEnglish?: string;
  originalCategory?: string;
  originalSubcategory?: string;
  originalVariety?: string;
  categoryIdOrKey?: string;
  subcategoryIdOrKey?: string;
  varietyIdOrKey?: string;
  categoryEnglish?: string;
  subcategoryEnglish?: string;
  varietyEnglish?: string;
};

export async function computeFraudScore(params: {
  db: Firestore;
  listing: ListingForFraud;
  user: UserForFraud;
  highFrequency: boolean;
}): Promise<FraudResult> {
  const {db, listing, user, highFrequency} = params;
  let score = 0;
  const flags: string[] = [];

  const marketAvg = await getMarketAverageRate(db, listing.product);
  if (marketAvg && marketAvg > 0) {
    const deviation = Math.abs(listing.price - marketAvg) / marketAvg;
    if (deviation > 0.5) {
      score += 35;
      flags.push("price_anomaly");
    }
  }

  if (!isWithinPakistanBounds(listing.verificationGeo)) {
    score += 35;
    flags.push("geo_outside_pakistan");
  }

  if (user.lastKnownGeo) {
    const distance = haversineDistanceKm(user.lastKnownGeo, listing.verificationGeo);
    if (distance > 150) {
      score += 25;
      flags.push("geo_mismatch");
    }
  }

  if (hasSpamText(listing.description)) {
    score += 25;
    flags.push("spam_text");
  }

  if (listing.description.trim().length < 20) {
    score += 20;
    flags.push("low_quality_description");
  }

  if (listing.village.trim().length < 2) {
    score += 15;
    flags.push("village_missing_or_short");
  }

  if (highFrequency || toNumber(user.listingsToday, 0) >= 10) {
    score += 25;
    flags.push("high_frequency_seller");
  }

  const trustScore = toNumber(user.trustScore, -1);
  if (trustScore < 0 || trustScore < 40) {
    score += 10;
    flags.push("low_trust_seller");
  }

  const strikes = toNumber(user.strikes, 0);
  if (strikes > 0) {
    score += Math.min(20, strikes * 5);
    flags.push("seller_has_strikes");
  }

  if (toNumber(user.isBanned ? 1 : 0, 0) > 0) {
    score = 100;
    flags.push("seller_banned");
  }

  score = Math.max(0, Math.min(100, score));
  return {
    riskScore: score,
    fraudFlags: uniqueStrings(flags),
  };
}

export function hasSpamText(text: string): boolean {
  const value = (text || "").toLowerCase();
  const phoneRegex = /(\+?\d[\d\s\-]{8,}\d)/;
  const whatsappRegex = /whatsapp|wa\.me|contact me|call me/;
  const linkRegex = /(https?:\/\/|www\.)/;
  return phoneRegex.test(value) || whatsappRegex.test(value) || linkRegex.test(value);
}

export async function getMarketAverageRate(
  db: Firestore,
  product: string,
  context?: MarketRateLookupContext,
): Promise<number | null> {
  const lookup = buildMarketRateLookupCandidates(product, context);
  if (lookup.keys.length === 0) return null;

  console.log("marketRates lookup", {
    marketRateLookupKey: lookup.primaryKey,
    originalCategory: context?.originalCategory || null,
    originalSubcategory: context?.originalSubcategory || null,
    originalVariety: context?.originalVariety || null,
    fallbackKeys: lookup.keys,
  });

  const mandiAverage = await getMarketAverageRateFromMandiRates(db, lookup.keys);
  if (mandiAverage != null && mandiAverage > 0) {
    return mandiAverage;
  }

  // Backward-compatible fallback for legacy deployments still using marketRates docs.
  let snap: FirebaseFirestore.DocumentSnapshot<FirebaseFirestore.DocumentData> | null = null;
  for (const key of lookup.keys) {
    const current = await db.collection("marketRates").doc(key).get();
    if (current.exists) {
      snap = current;
      break;
    }
  }

  if (!snap || !snap.exists) return null;

  const data = snap.data() || {};
  const avg =
    toNumber(data.average, 0) ||
    toNumber(data.avg, 0) ||
    toNumber(data.rate, 0) ||
    toNumber(data.price, 0);

  return avg > 0 ? avg : null;
}

async function getMarketAverageRateFromMandiRates(
  db: Firestore,
  lookupKeys: string[],
): Promise<number | null> {
  const normalizedKeys = new Set(
    lookupKeys
      .map((key) => normalizeMandiCropToken(key))
      .filter((key) => key.length > 0),
  );
  if (normalizedKeys.size === 0) return null;

  const snap = await db
    .collection("mandi_rates")
    .orderBy("rateDate", "desc")
    .limit(200)
    .get();

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const cropToken = normalizeMandiCropToken(
      String(data.cropType || data.cropName || data.itemName || ""),
    );
    if (!cropToken || !normalizedKeys.has(cropToken)) continue;

    const avg =
      toNumber(data.averagePrice, 0) ||
      toNumber(data.average, 0) ||
      toNumber(data.avg, 0) ||
      toNumber(data.rate, 0) ||
      toNumber(data.price, 0);
    if (avg > 0) return avg;
  }

  return null;
}

function normalizeMandiCropToken(value: string): string {
  return normalizeLookupToken(value)
    .replace(/__+/g, "_")
    .replace(/-+/g, "_")
    .trim();
}

function buildMarketRateLookupCandidates(
  product: string,
  context?: MarketRateLookupContext,
): {primaryKey: string | null; keys: string[]} {
  const originalCategory = normalizeLookupToken(
    chooseSafeLookupToken({
      idOrKey: context?.categoryIdOrKey,
      englishLabel: context?.categoryEnglish,
      bilingualLabel: context?.originalCategory,
    }),
  );
  const originalSubcategory = normalizeLookupToken(
    chooseSafeLookupToken({
      idOrKey: context?.subcategoryIdOrKey,
      englishLabel: context?.subcategoryEnglish,
      bilingualLabel: context?.originalSubcategory,
    }),
  );
  const originalVariety = normalizeLookupToken(
    chooseSafeLookupToken({
      idOrKey: context?.varietyIdOrKey,
      englishLabel: context?.varietyEnglish,
      bilingualLabel: context?.originalVariety,
    }),
  );
  const productToken = normalizeLookupToken(
    chooseSafeLookupToken({
      idOrKey: context?.productIdOrKey,
      englishLabel: context?.productEnglish,
      bilingualLabel: product,
    }),
  );

  const hierarchicalKey = [
    originalCategory,
    originalSubcategory,
    originalVariety,
    productToken,
  ].filter((v) => v.length > 0).join("__");

  const legacyKey = normalizeLookupToken(normalizeProductKey(product));
  const allKeys = uniqueStrings([hierarchicalKey, productToken, legacyKey]).filter((k) => k.length > 0);

  return {
    primaryKey: allKeys[0] || null,
    keys: allKeys,
  };
}

function chooseSafeLookupToken(params: {
  idOrKey?: string;
  englishLabel?: string;
  bilingualLabel?: string;
}): string {
  const idOrKey = (params.idOrKey || "").trim();
  if (idOrKey.length > 0) {
    return idOrKey;
  }

  const englishLabel = (params.englishLabel || "").trim() || extractEnglishSegment(params.bilingualLabel || "");
  if (englishLabel.length > 0) {
    return englishLabel;
  }

  return (params.bilingualLabel || "").trim();
}

function extractEnglishSegment(value: string): string {
  const raw = (value || "").trim();
  if (!raw) return "";
  const parts = raw.split(/[\/|]/g).map((p) => p.trim()).filter((p) => p.length > 0);
  for (const part of parts) {
    if (/[A-Za-z0-9]/.test(part)) {
      return part;
    }
  }
  return "";
}

function normalizeLookupToken(value: string): string {
  return (value || "")
    .trim()
    .toLowerCase()
    .replace(/[\\/]+/g, "-")
    .replace(/\s+/g, "_")
    .replace(/[_-]{2,}/g, "_")
    .replace(/^[_-]+|[_-]+$/g, "");
}

export async function computeImageHashFromStoragePath(
  storagePath: string,
): Promise<string> {
  const bucket = admin.storage().bucket();
  const [buffer] = await bucket.file(storagePath).download();
  const {hashBufferSha256} = await import("./utils");
  return hashBufferSha256(buffer);
}
