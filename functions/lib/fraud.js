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
exports.computeFraudScore = computeFraudScore;
exports.hasSpamText = hasSpamText;
exports.getMarketAverageRate = getMarketAverageRate;
exports.computeImageHashFromStoragePath = computeImageHashFromStoragePath;
const admin = __importStar(require("firebase-admin"));
const utils_1 = require("./utils");
async function computeFraudScore(params) {
    const { db, listing, user, highFrequency } = params;
    let score = 0;
    const flags = [];
    const marketAvg = await getMarketAverageRate(db, listing.product);
    if (marketAvg && marketAvg > 0) {
        const deviation = Math.abs(listing.price - marketAvg) / marketAvg;
        if (deviation > 0.5) {
            score += 35;
            flags.push("price_anomaly");
        }
    }
    if (!(0, utils_1.isWithinPakistanBounds)(listing.verificationGeo)) {
        score += 35;
        flags.push("geo_outside_pakistan");
    }
    if (user.lastKnownGeo) {
        const distance = (0, utils_1.haversineDistanceKm)(user.lastKnownGeo, listing.verificationGeo);
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
    if (highFrequency || (0, utils_1.toNumber)(user.listingsToday, 0) >= 10) {
        score += 25;
        flags.push("high_frequency_seller");
    }
    const trustScore = (0, utils_1.toNumber)(user.trustScore, -1);
    if (trustScore < 0 || trustScore < 40) {
        score += 10;
        flags.push("low_trust_seller");
    }
    const strikes = (0, utils_1.toNumber)(user.strikes, 0);
    if (strikes > 0) {
        score += Math.min(20, strikes * 5);
        flags.push("seller_has_strikes");
    }
    if ((0, utils_1.toNumber)(user.isBanned ? 1 : 0, 0) > 0) {
        score = 100;
        flags.push("seller_banned");
    }
    score = Math.max(0, Math.min(100, score));
    return {
        riskScore: score,
        fraudFlags: (0, utils_1.uniqueStrings)(flags),
    };
}
function hasSpamText(text) {
    const value = (text || "").toLowerCase();
    const phoneRegex = /(\+?\d[\d\s\-]{8,}\d)/;
    const whatsappRegex = /whatsapp|wa\.me|contact me|call me/;
    const linkRegex = /(https?:\/\/|www\.)/;
    return phoneRegex.test(value) || whatsappRegex.test(value) || linkRegex.test(value);
}
async function getMarketAverageRate(db, product, context) {
    const lookup = buildMarketRateLookupCandidates(product, context);
    if (lookup.keys.length === 0)
        return null;
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
    let snap = null;
    for (const key of lookup.keys) {
        const current = await db.collection("marketRates").doc(key).get();
        if (current.exists) {
            snap = current;
            break;
        }
    }
    if (!snap || !snap.exists)
        return null;
    const data = snap.data() || {};
    const avg = (0, utils_1.toNumber)(data.average, 0) ||
        (0, utils_1.toNumber)(data.avg, 0) ||
        (0, utils_1.toNumber)(data.rate, 0) ||
        (0, utils_1.toNumber)(data.price, 0);
    return avg > 0 ? avg : null;
}
async function getMarketAverageRateFromMandiRates(db, lookupKeys) {
    const normalizedKeys = new Set(lookupKeys
        .map((key) => normalizeMandiCropToken(key))
        .filter((key) => key.length > 0));
    if (normalizedKeys.size === 0)
        return null;
    const snap = await db
        .collection("mandi_rates")
        .orderBy("rateDate", "desc")
        .limit(200)
        .get();
    for (const doc of snap.docs) {
        const data = doc.data() || {};
        const cropToken = normalizeMandiCropToken(String(data.cropType || data.cropName || data.itemName || ""));
        if (!cropToken || !normalizedKeys.has(cropToken))
            continue;
        const avg = (0, utils_1.toNumber)(data.averagePrice, 0) ||
            (0, utils_1.toNumber)(data.average, 0) ||
            (0, utils_1.toNumber)(data.avg, 0) ||
            (0, utils_1.toNumber)(data.rate, 0) ||
            (0, utils_1.toNumber)(data.price, 0);
        if (avg > 0)
            return avg;
    }
    return null;
}
function normalizeMandiCropToken(value) {
    return normalizeLookupToken(value)
        .replace(/__+/g, "_")
        .replace(/-+/g, "_")
        .trim();
}
function buildMarketRateLookupCandidates(product, context) {
    const originalCategory = normalizeLookupToken(chooseSafeLookupToken({
        idOrKey: context?.categoryIdOrKey,
        englishLabel: context?.categoryEnglish,
        bilingualLabel: context?.originalCategory,
    }));
    const originalSubcategory = normalizeLookupToken(chooseSafeLookupToken({
        idOrKey: context?.subcategoryIdOrKey,
        englishLabel: context?.subcategoryEnglish,
        bilingualLabel: context?.originalSubcategory,
    }));
    const originalVariety = normalizeLookupToken(chooseSafeLookupToken({
        idOrKey: context?.varietyIdOrKey,
        englishLabel: context?.varietyEnglish,
        bilingualLabel: context?.originalVariety,
    }));
    const productToken = normalizeLookupToken(chooseSafeLookupToken({
        idOrKey: context?.productIdOrKey,
        englishLabel: context?.productEnglish,
        bilingualLabel: product,
    }));
    const hierarchicalKey = [
        originalCategory,
        originalSubcategory,
        originalVariety,
        productToken,
    ].filter((v) => v.length > 0).join("__");
    const legacyKey = normalizeLookupToken((0, utils_1.normalizeProductKey)(product));
    const allKeys = (0, utils_1.uniqueStrings)([hierarchicalKey, productToken, legacyKey]).filter((k) => k.length > 0);
    return {
        primaryKey: allKeys[0] || null,
        keys: allKeys,
    };
}
function chooseSafeLookupToken(params) {
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
function extractEnglishSegment(value) {
    const raw = (value || "").trim();
    if (!raw)
        return "";
    const parts = raw.split(/[\/|]/g).map((p) => p.trim()).filter((p) => p.length > 0);
    for (const part of parts) {
        if (/[A-Za-z0-9]/.test(part)) {
            return part;
        }
    }
    return "";
}
function normalizeLookupToken(value) {
    return (value || "")
        .trim()
        .toLowerCase()
        .replace(/[\\/]+/g, "-")
        .replace(/\s+/g, "_")
        .replace(/[_-]{2,}/g, "_")
        .replace(/^[_-]+|[_-]+$/g, "");
}
async function computeImageHashFromStoragePath(storagePath) {
    const bucket = admin.storage().bucket();
    const [buffer] = await bucket.file(storagePath).download();
    const { hashBufferSha256 } = await Promise.resolve().then(() => __importStar(require("./utils")));
    return hashBufferSha256(buffer);
}
