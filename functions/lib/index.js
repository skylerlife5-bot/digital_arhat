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
exports.onListingMediaFinalize = exports.onListingCreated = exports.onWatchlistDeleted = exports.onWatchlistCreated = exports.evaluateBidRiskHttp = exports.evaluateBidRisk = exports.getMandiTrendHttp = exports.suggestMarketRateHttp = exports.suggestMarketRate = exports.evaluateListingRiskHttp = exports.evaluateListingRisk = exports.aiExtractCnic = exports.aiSuggestBidRate = exports.aiWeatherAdvisory = exports.weatherCurrentHttp = exports.aiGenerateText = exports.extendAuctionAdmin = exports.cancelAuctionAdmin = exports.resumeAuctionAdmin = exports.pauseAuctionAdmin = exports.startAuctionAdmin = exports.requestListingChangesAdmin = exports.rejectListingAdmin = exports.approveListingAdmin = exports.createListingSecureHttp = exports.createListingSecure = exports.submitMandiContribution = exports.ingestMandiRatesScheduled = exports.ingestMandiRatesOnDemand = void 0;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const storage_1 = require("firebase-functions/v2/storage");
const params_1 = require("firebase-functions/params");
const firestore_2 = require("firebase-admin/firestore");
const fraud_1 = require("./fraud");
const mandi_rates_ingestion_1 = require("./mandi_rates_ingestion");
Object.defineProperty(exports, "ingestMandiRatesOnDemand", { enumerable: true, get: function () { return mandi_rates_ingestion_1.ingestMandiRatesOnDemand; } });
Object.defineProperty(exports, "ingestMandiRatesScheduled", { enumerable: true, get: function () { return mandi_rates_ingestion_1.ingestMandiRatesScheduled; } });
const mandi_human_contributions_1 = require("./mandi_human_contributions");
Object.defineProperty(exports, "submitMandiContribution", { enumerable: true, get: function () { return mandi_human_contributions_1.submitMandiContribution; } });
const utils_1 = require("./utils");
const v2_1 = require("firebase-functions/v2");
(0, v2_1.setGlobalOptions)({ timeoutSeconds: 300 });
console.log("FUNCTIONS ENTRY START");
console.log("FUNCTIONS ENV CHECK DEFERRED");
const GOOGLE_API_KEY = (0, params_1.defineSecret)("GOOGLE_API_KEY");
const OPENWEATHER_API_KEY_SECRET = (0, params_1.defineSecret)("OPENWEATHER_API_KEY");
const GEMINI_STABLE_MODEL = "gemini-1.5-flash";
const AI_RUNTIME_OPTIONS = {
    region: "asia-south1",
    secrets: [GOOGLE_API_KEY, OPENWEATHER_API_KEY_SECRET],
};
const AI_GENERATE_TEXT_RUNTIME_OPTIONS = {
    region: "asia-south1",
    timeoutSeconds: 300,
    memory: "512MiB",
    secrets: [GOOGLE_API_KEY],
};
const AI_EXTRACT_CNIC_RUNTIME_OPTIONS = {
    region: "asia-south1",
    timeoutSeconds: 300,
    memory: "512MiB",
    secrets: [GOOGLE_API_KEY],
};
let cachedDb = null;
function getAdminApp() {
    if (admin.apps.length > 0) {
        return admin.app();
    }
    const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
    return projectId ? admin.initializeApp({ projectId }) : admin.initializeApp();
}
function getDb() {
    if (!cachedDb) {
        cachedDb = getAdminApp().firestore();
    }
    return cachedDb;
}
const db = new Proxy({}, {
    get(_target, prop, receiver) {
        return Reflect.get(getDb(), prop, receiver);
    },
});
function requireString(value, field) {
    const text = (value || "").toString().trim();
    if (!text)
        throw new https_1.HttpsError("invalid-argument", `${field} is required`);
    return text;
}
function requirePositiveNumber(value, field) {
    const n = (0, utils_1.toNumber)(value, NaN);
    if (!Number.isFinite(n) || n <= 0) {
        throw new https_1.HttpsError("invalid-argument", `${field} must be a positive number`);
    }
    return n;
}
const PAKISTAN_LOCATIONS = {
    "Punjab": [
        "Attock",
        "Bahawalnagar",
        "Bahawalpur",
        "Bhakkar",
        "Chakwal",
        "Chiniot",
        "Dera Ghazi Khan",
        "Faisalabad",
        "Gujranwala",
        "Gujrat",
        "Hafizabad",
        "Jhang",
        "Jhelum",
        "Kasur",
        "Khanewal",
        "Khushab",
        "Lahore",
        "Layyah",
        "Lodhran",
        "Mandi Bahauddin",
        "Mianwali",
        "Multan",
        "Muzaffargarh",
        "Narowal",
        "Nankana Sahib",
        "Okara",
        "Pakpattan",
        "Rahim Yar Khan",
        "Rajanpur",
        "Rawalpindi",
        "Sahiwal",
        "Sargodha",
        "Sheikhupura",
        "Sialkot",
        "Toba Tek Singh",
        "Vehari",
    ],
    "Sindh": [
        "Badin",
        "Dadu",
        "Ghotki",
        "Hyderabad",
        "Jacobabad",
        "Jamshoro",
        "Khairpur",
        "Larkana",
        "Mirpurkhas",
        "Naushehro Feroze",
        "Sanghar",
        "Shaheed Benazirabad",
        "Shikarpur",
        "Sujawal",
        "Tando Allahyar",
        "Tando Muhammad Khan",
        "Tharparkar",
        "Thatta",
        "Umerkot",
    ],
    "Khyber Pakhtunkhwa (KPK)": [
        "Abbottabad",
        "Bannu",
        "Charsadda",
        "Dera Ismail Khan",
        "Haripur",
        "Karak",
        "Kohat",
        "Lakki Marwat",
        "Lower Dir",
        "Malakand",
        "Mardan",
        "Nowshera",
        "Peshawar",
        "Shangla",
        "Swabi",
        "Swat",
        "Tank",
        "Upper Dir",
    ],
    "Balochistan": [
        "Barkhan",
        "Gwadar",
        "Jaffarabad",
        "Jhal Magsi",
        "Kachhi",
        "Kalat",
        "Kech",
        "Kharan",
        "Khuzdar",
        "Lasbela",
        "Mastung",
        "Nasirabad",
        "Panjgur",
        "Pishin",
        "Quetta",
        "Sibi",
        "Zhob",
    ],
    "Gilgit-Baltistan": [
        "Astore",
        "Diamer",
        "Ghanche",
        "Ghizer",
        "Gilgit",
        "Hunza",
        "Kharmang",
        "Nagar",
        "Shigar",
        "Skardu",
    ],
    "Azad Jammu & Kashmir (AJK)": [
        "Bagh",
        "Bhimber",
        "Hattian Bala",
        "Haveli",
        "Kotli",
        "Mirpur",
        "Muzaffarabad",
        "Neelum",
        "Poonch",
        "Sudhnoti",
    ],
};
const BLOCKED_KEYWORDS = [
    "whatsapp",
    "call",
    "03",
    "+92",
    "link",
    "urgent",
    "cheap",
];
function clampRisk(value) {
    return Math.max(0, Math.min(100, Math.round(value)));
}
function isUserBannedOrFlagged(userData) {
    const status = String(userData.status || "").toLowerCase();
    return (userData.isBanned === true ||
        userData.isFlagged === true ||
        userData.flagged === true ||
        status === "banned" ||
        status === "flagged");
}
function getRateLimitHourKey(now) {
    const y = now.getUTCFullYear();
    const m = String(now.getUTCMonth() + 1).padStart(2, "0");
    const d = String(now.getUTCDate()).padStart(2, "0");
    const h = String(now.getUTCHours()).padStart(2, "0");
    return `${y}${m}${d}${h}`;
}
function setCorsHeaders(res) {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
}
function readRequestBody(req) {
    if (!req.body || typeof req.body !== "object")
        return {};
    return req.body;
}
async function getUidFromBearerToken(req) {
    const authHeader = String(req.headers.authorization || "").trim();
    if (!authHeader.toLowerCase().startsWith("bearer "))
        return null;
    const token = authHeader.slice(7).trim();
    if (!token)
        return null;
    try {
        const decoded = await getAdminApp().auth().verifyIdToken(token);
        return decoded.uid || null;
    }
    catch (_) {
        return null;
    }
}
async function getDecodedTokenFromBearerToken(req) {
    const authHeader = String(req.headers.authorization || "").trim();
    if (!authHeader.toLowerCase().startsWith("bearer "))
        return null;
    const token = authHeader.slice(7).trim();
    if (!token)
        return null;
    try {
        return await getAdminApp().auth().verifyIdToken(token);
    }
    catch (_) {
        return null;
    }
}
function normalizeCnic(value) {
    const digits = (value || "").replace(/[^0-9]/g, "");
    if (digits.length !== 13)
        return "";
    return `${digits.slice(0, 5)}-${digits.slice(5, 12)}-${digits.slice(12)}`;
}
function normalizeDetectedSide(value) {
    const side = String(value || "").toLowerCase().trim();
    if (side === "front")
        return "front";
    if (side === "back")
        return "back";
    if (side.includes("front") || side.includes("frnt"))
        return "front";
    if (side.includes("back") || side.includes("rear"))
        return "back";
    return "unknown";
}
function extractJsonBlock(rawText) {
    const cleaned = rawText.replace(/```json/gi, "").replace(/```/g, "").trim();
    const match = cleaned.match(/\{[\s\S]*\}/);
    return (match?.[0] || cleaned).trim();
}
function toRiskLevel(score) {
    if (score >= 70)
        return "high";
    if (score >= 40)
        return "medium";
    return "low";
}
function toSuggestedAction(score) {
    if (score >= 80)
        return "reject_suspected";
    if (score >= 45)
        return "review";
    return "approve_ok";
}
function toBidAction(score) {
    if (score >= 92)
        return "hold";
    if (score >= 60)
        return "warn";
    return "allow";
}
function toConfidenceLevel(value) {
    if (value >= 0.75)
        return "high";
    if (value >= 0.5)
        return "medium";
    return "low";
}
function sanitizeReasonList(values, fallback) {
    if (!Array.isArray(values))
        return [fallback];
    const cleaned = values
        .map((item) => String(item || "").trim())
        .filter((item) => item.length > 0)
        .slice(0, 5);
    return cleaned.length > 0 ? (0, utils_1.uniqueStrings)(cleaned) : [fallback];
}
async function enforceAiThrottle(params) {
    const now = new Date();
    const bucket = Math.floor(now.getTime() / (params.windowSeconds * 1000));
    const docId = `${params.scope}_${params.key}_${bucket}`;
    const ref = db.collection("aiGuardThrottle").doc(docId);
    await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const count = (0, utils_1.toNumber)(snap.get("count"), 0);
        if (count >= params.limit) {
            throw new https_1.HttpsError("resource-exhausted", "ai-throttled");
        }
        tx.set(ref, {
            scope: params.scope,
            key: params.key,
            bucket,
            count: count + 1,
            windowSeconds: params.windowSeconds,
            updatedAt: firestore_2.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
}
async function evaluateListingRiskDocument(listingId) {
    const listingRef = db.collection("listings").doc(listingId);
    const listingSnap = await listingRef.get();
    if (!listingSnap.exists) {
        throw new https_1.HttpsError("not-found", "listing-not-found");
    }
    const listing = (listingSnap.data() || {});
    const product = String(listing.product || listing.cropName || listing.itemName || "").trim();
    const price = (0, utils_1.toNumber)(listing.price, 0);
    const quantity = (0, utils_1.toNumber)(listing.quantity, 0);
    const province = String(listing.province || "").trim();
    const district = String(listing.district || "").trim();
    const description = String(listing.description || "").trim();
    const category = String(listing.category || listing.categoryLabel || "").trim();
    const subcategory = String(listing.subcategory || listing.subCategory || listing.subcategoryLabel || "").trim();
    const variety = String(listing.variety || listing.varietyName || "").trim();
    const imageUrls = Array.isArray(listing.imageUrls)
        ? listing.imageUrls.map((v) => String(v || "").trim()).filter((v) => v.length > 0)
        : [];
    const videoUrl = String(listing.videoUrl || listing.verificationVideoUrl || "").trim();
    const hasMedia = imageUrls.length > 0 || videoUrl.length > 0;
    let heuristicScore = 0;
    const heuristicFlags = [];
    const marketAvg = await (0, fraud_1.getMarketAverageRate)(db, product, {
        originalCategory: category,
        originalSubcategory: subcategory,
        originalVariety: variety,
        categoryIdOrKey: String(listing.categoryId || listing.categoryKey || "").trim(),
        subcategoryIdOrKey: String(listing.subcategoryId || listing.subcategoryKey || "").trim(),
        varietyIdOrKey: String(listing.varietyId || listing.varietyKey || "").trim(),
    });
    if (marketAvg && marketAvg > 0 && price > 0) {
        const deviation = Math.abs(price - marketAvg) / marketAvg;
        if (deviation > 0.40) {
            heuristicScore += 35;
            heuristicFlags.push("price_anomaly");
        }
    }
    if (!hasMedia) {
        heuristicScore += 20;
        heuristicFlags.push("low_media");
    }
    if (description.length < 20) {
        heuristicScore += 15;
        heuristicFlags.push("thin_description");
    }
    if (province.length > 0 && district.length > 0) {
        const districts = PAKISTAN_LOCATIONS[province] || [];
        const districtSet = new Set(districts.map((d) => d.toLowerCase()));
        if (!districtSet.has(district.toLowerCase())) {
            heuristicScore += 15;
            heuristicFlags.push("location_mismatch");
        }
    }
    heuristicScore = clampRisk(heuristicScore);
    let result = {
        aiRiskScore: heuristicScore,
        aiRiskLevel: toRiskLevel(heuristicScore),
        aiReasons: heuristicScore >= 45
            ? ["Listing has some unusual patterns. Please review manually."]
            : ["Listing looks mostly normal. Manual review still required."],
        aiReasonsUrdu: heuristicScore >= 45
            ? ["اس لسٹنگ میں کچھ غیر معمولی باتیں ہیں، براہ کرم دستی جائزہ لیں۔"]
            : ["لسٹنگ عمومی لگتی ہے، پھر بھی دستی جائزہ ضروری ہے۔"],
        aiFlags: (0, utils_1.uniqueStrings)(heuristicFlags),
        aiSuggestedAction: toSuggestedAction(heuristicScore),
        aiConfidence: 0.35,
    };
    const prompt = [
        "Return ONLY JSON with schema:",
        "{aiRiskScore:number,aiRiskLevel:'low|medium|high',aiReasons:string[],aiReasonsUrdu:string[],aiFlags:string[],aiSuggestedAction:'review|approve_ok|reject_suspected',aiConfidence:number}",
        "This is a farmer marketplace listing fraud-risk suggestion. Keep language concise and calm.",
        "Do not mention final approval. Admin decides.",
        "Listing:",
        JSON.stringify({
            listingId,
            product,
            price,
            quantity,
            province,
            district,
            description,
            imageCount: imageUrls.length,
            hasVideo: videoUrl.length > 0,
            heuristicScore,
            heuristicFlags,
        }),
    ].join("\n");
    try {
        const raw = await callGeminiText({
            prompt,
            temperature: 0.1,
            responseMimeType: "application/json",
        });
        const parsed = JSON.parse(extractJsonBlock(raw));
        const score = clampRisk((0, utils_1.toNumber)(parsed.aiRiskScore, heuristicScore));
        const levelRaw = String(parsed.aiRiskLevel || toRiskLevel(score)).toLowerCase();
        const level = levelRaw === "high" || levelRaw === "medium" || levelRaw === "low"
            ? levelRaw
            : toRiskLevel(score);
        const actionRaw = String(parsed.aiSuggestedAction || toSuggestedAction(score)).toLowerCase();
        const action = actionRaw === "review" || actionRaw === "approve_ok" || actionRaw === "reject_suspected"
            ? actionRaw
            : toSuggestedAction(score);
        result = {
            aiRiskScore: score,
            aiRiskLevel: level,
            aiReasons: sanitizeReasonList(parsed.aiReasons, "Manual review recommended."),
            aiReasonsUrdu: sanitizeReasonList(parsed.aiReasonsUrdu, "دستی جائزہ تجویز کیا جاتا ہے۔"),
            aiFlags: sanitizeReasonList(parsed.aiFlags, "none"),
            aiSuggestedAction: action,
            aiConfidence: Math.max(0, Math.min(1, (0, utils_1.toNumber)(parsed.aiConfidence, 0.6))),
        };
    }
    catch (_) {
        // Keep heuristic fallback when AI parsing/unavailability fails.
    }
    await listingRef.set({
        ...result,
        aiUpdatedAt: firestore_2.FieldValue.serverTimestamp(),
        updatedAt: firestore_2.FieldValue.serverTimestamp(),
    }, { merge: true });
    return result;
}
async function callGeminiText(params) {
    const resolvedGoogleApiKey = (GOOGLE_API_KEY.value() || "").trim();
    if (!resolvedGoogleApiKey) {
        throw new Error("CRITICAL: GOOGLE_API_KEY secret is missing.");
    }
    const requestedModel = (params.model || "").trim();
    const model = GEMINI_STABLE_MODEL;
    if (requestedModel && requestedModel !== GEMINI_STABLE_MODEL) {
        console.warn("Ignoring requested Gemini model; forcing stable model.", {
            requestedModel,
            forcedModel: GEMINI_STABLE_MODEL,
        });
    }
    const endpoint = `https://generativelanguage.googleapis.com/v1/models/${model}:generateContent`;
    const parts = params.parts && params.parts.length > 0 ? params.parts : [{ text: params.prompt }];
    let response;
    try {
        response = await fetch(endpoint, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "x-goog-api-key": resolvedGoogleApiKey,
            },
            body: JSON.stringify({
                contents: [{ parts: parts }],
                generationConfig: {
                    temperature: params.temperature ?? 0.2,
                    responseMimeType: "application/json",
                },
            }),
        });
    }
    catch (_) {
        throw new Error(`GEMINI_NETWORK_ERROR|model=${model}`);
    }
    if (!response.ok) {
        let upstreamText = "";
        try {
            upstreamText = (await response.text()).trim();
        }
        catch (_) {
            upstreamText = "";
        }
        const upstreamPreview = upstreamText.slice(0, 400);
        const bodyLower = upstreamPreview.toLowerCase();
        const isApiKeyInvalid = bodyLower.includes("api key not valid") || bodyLower.includes("api_key_invalid");
        if (isApiKeyInvalid || response.status === 401 || response.status === 403) {
            throw new Error(`GEMINI_AUTH_REJECTED|status=${response.status}|model=${model}|body=${upstreamPreview}`);
        }
        if (response.status === 429) {
            throw new Error(`GEMINI_QUOTA_EXCEEDED|status=${response.status}|model=${model}|body=${upstreamPreview}`);
        }
        if (response.status >= 500) {
            throw new Error(`GEMINI_UPSTREAM_UNAVAILABLE|status=${response.status}|model=${model}|body=${upstreamPreview}`);
        }
        throw new Error(`GEMINI_HTTP_${response.status}|model=${model}|body=${upstreamPreview}`);
    }
    const body = await response.json();
    const text = (body.candidates?.[0]?.content?.parts?.[0]?.text || "").trim();
    if (!text) {
        throw new Error(`GEMINI_EMPTY_RESPONSE|model=${model}`);
    }
    return text;
}
async function getCurrentWeatherForPakistanDistrict(district) {
    const apiKey = (OPENWEATHER_API_KEY_SECRET.value() || process.env.OPENWEATHER_API_KEY || "").trim();
    if (!apiKey) {
        throw new https_1.HttpsError("failed-precondition", "weather-key-missing");
    }
    const location = district.trim() || "Punjab";
    const url = `https://api.openweathermap.org/data/2.5/weather?q=${encodeURIComponent(location)},PK&units=metric&appid=${encodeURIComponent(apiKey)}`;
    let response;
    try {
        response = await fetch(url, { method: "GET" });
    }
    catch (_) {
        throw new https_1.HttpsError("unavailable", "weather-network-unavailable");
    }
    if (!response.ok) {
        if (response.status === 401 || response.status === 403) {
            throw new https_1.HttpsError("permission-denied", "weather-provider-auth-rejected");
        }
        if (response.status === 404) {
            throw new https_1.HttpsError("not-found", "weather-location-not-found");
        }
        throw new https_1.HttpsError("unavailable", `weather-provider-http-${response.status}`);
    }
    const payload = await response.json();
    const condition = String(payload.weather?.[0]?.main || "Clear").trim() || "Clear";
    const description = String(payload.weather?.[0]?.description || condition).trim() || condition;
    const temp = (0, utils_1.toNumber)(payload.main?.temp, 0);
    const humidity = Math.max(0, Math.round((0, utils_1.toNumber)(payload.main?.humidity, 0)));
    const windSpeed = (0, utils_1.toNumber)(payload.wind?.speed, 0);
    const rainTerms = ["rain", "drizzle", "thunderstorm", "shower"];
    const conditionLower = condition.toLowerCase();
    return {
        temp,
        condition,
        description,
        humidity,
        windSpeed,
        isRainLikely: rainTerms.some((term) => conditionLower.includes(term)),
    };
}
function computeClientPrecheckRisk(params) {
    const { listingData, mediaMetadata, marketAverage } = params;
    let risk = 0;
    const flags = [];
    if (marketAverage != null && marketAverage > 0 && listingData.price > 0) {
        const deviation = Math.abs(listingData.price - marketAverage) / marketAverage;
        if (deviation > 0.35) {
            risk += 35;
            flags.push("price_anomaly");
        }
    }
    const normalizedDescription = listingData.description.trim().toLowerCase();
    if (normalizedDescription.length < 20) {
        risk += 15;
        flags.push("thin_description");
    }
    if (BLOCKED_KEYWORDS.some((keyword) => normalizedDescription.includes(keyword))) {
        risk += 25;
        flags.push("external_contact");
    }
    const hasAudio = mediaMetadata.audioUrl.trim().length > 0;
    if (mediaMetadata.imageUrls.length === 0 && !hasAudio) {
        risk += 10;
        flags.push("low_evidence");
    }
    const province = listingData.province.trim();
    const district = listingData.district.trim();
    if (province.length > 0 && district.length > 0) {
        const districtList = PAKISTAN_LOCATIONS[province] || [];
        const districtSet = new Set(districtList.map((d) => d.toLowerCase()));
        if (!districtSet.has(district.toLowerCase())) {
            risk += 20;
            flags.push("location_mismatch");
        }
    }
    return {
        riskScore: clampRisk(risk),
        flags: (0, utils_1.uniqueStrings)(flags),
    };
}
async function evaluateListingRiskWithGemini(params) {
    const model = GEMINI_STABLE_MODEL;
    console.log("[AI Risk] evaluateListingRiskWithGemini start", {
        model,
    });
    const prompt = [
        "Evaluate if this marketplace listing is suspicious. Return JSON: {riskScore:0-100, flags:[...], summary:'...'}",
        "Use concise flag names.",
        "Do not include markdown.",
        "Listing data:",
        JSON.stringify(params.listingData),
        "Media metadata:",
        JSON.stringify(params.mediaMetadata),
        "Client heuristic risk:",
        JSON.stringify({ riskScore: params.heuristicRiskScore, flags: params.heuristicFlags }),
    ].join("\n");
    try {
        console.log("[AI Risk] request", { requestAttempted: true, model });
        const text = await callGeminiText({
            prompt,
            model,
            temperature: 0.1,
            responseMimeType: "application/json",
        });
        const jsonTextMatch = text.match(/\{[\s\S]*\}/);
        const parsed = JSON.parse((jsonTextMatch?.[0] || "{}"));
        const riskScore = clampRisk((0, utils_1.toNumber)(parsed.riskScore, 0));
        const flags = Array.isArray(parsed.flags) ?
            parsed.flags.map((f) => String(f)).filter((f) => f.trim().length > 0) : [];
        const summary = String(parsed.summary || "AI risk assessment completed.");
        return {
            riskScore,
            flags: (0, utils_1.uniqueStrings)(flags),
            summary,
        };
    }
    catch (error) {
        const errorText = String(error || "");
        const fallbackReason = errorText.includes("GEMINI_AUTH_REJECTED") ? "ai_auth_rejected" :
            errorText.includes("GEMINI_QUOTA_EXCEEDED") ? "ai_quota_exceeded" :
                errorText.includes("GEMINI_NETWORK_ERROR") || errorText.includes("GEMINI_UPSTREAM_UNAVAILABLE") ?
                    "ai_network_unavailable" :
                    errorText.includes("GEMINI_EMPTY_RESPONSE") || errorText.includes("JSON") ?
                        "ai_parse_failed" :
                        "ai_unknown_failure";
        console.log("[AI Risk] fallback", {
            fallbackReason,
            requestAttempted: true,
            responseParsed: false,
        });
        return {
            riskScore: 0,
            flags: [fallbackReason],
            summary: "AI risk check fallback: provider unavailable or response invalid.",
        };
    }
}
function decideListingStatus(riskScore) {
    if (riskScore >= 90)
        return process.env.HIGH_RISK_STATUS || "blocked_or_review";
    return "pending_review";
}
async function createListingSecureInternal(uid, data) {
    console.log("createListingSecureHttp: payload normalize start", { uid });
    const listingData = data.listingData || {};
    const mediaMetadata = data.mediaMetadata || {};
    const verificationVideo = mediaMetadata.verificationVideo || {};
    const verificationTrustPhoto = mediaMetadata.verificationTrustPhoto || {};
    const sellerId = requireString(listingData.sellerId, "listingData.sellerId");
    if (sellerId !== uid) {
        throw new https_1.HttpsError("permission-denied", "sellerId must match authenticated user");
    }
    const product = requireString(listingData.product, "listingData.product");
    const province = requireString(listingData.province, "listingData.province");
    const district = requireString(listingData.district, "listingData.district");
    const village = requireString(listingData.village, "listingData.village");
    const description = requireString(listingData.description, "listingData.description");
    const price = requirePositiveNumber(listingData.price, "listingData.price");
    const quantity = requirePositiveNumber(listingData.quantity, "listingData.quantity");
    const normalizedImageUrls = Array.isArray(mediaMetadata.imageUrls) ?
        mediaMetadata.imageUrls.map((v) => String(v).trim()).filter((v) => v.length > 0) : [];
    if (normalizedImageUrls.length === 0) {
        throw new https_1.HttpsError("invalid-argument", "at least one trust photo is required");
    }
    const trustLat = (0, utils_1.toNumber)(verificationTrustPhoto.lat ?? verificationVideo.lat, NaN);
    const trustLng = (0, utils_1.toNumber)(verificationTrustPhoto.lng ?? verificationVideo.lng, NaN);
    if (!Number.isFinite(trustLat) || !Number.isFinite(trustLng)) {
        throw new https_1.HttpsError("invalid-argument", "trusted listing must include GPS lat and lng");
    }
    const trustCapturedAtDate = (0, utils_1.toDate)(verificationTrustPhoto.capturedAt) ||
        (0, utils_1.toDate)(verificationVideo.capturedAt) ||
        new Date();
    const verificationVideoUrl = String(verificationVideo.url || "").trim();
    let verificationVideoDuration = (0, utils_1.toNumber)(verificationVideo.durationSeconds, 0);
    if (verificationVideoUrl.length > 0) {
        verificationVideoDuration = (0, utils_1.toNumber)(verificationVideo.durationSeconds, NaN);
        if (!Number.isFinite(verificationVideoDuration)) {
            throw new https_1.HttpsError("invalid-argument", "mediaMetadata.verificationVideo.durationSeconds is required when video is uploaded");
        }
        if (verificationVideoDuration < 5 || verificationVideoDuration > 15) {
            throw new https_1.HttpsError("invalid-argument", "verification video duration must be between 5 and 15 seconds");
        }
    }
    const verificationLat = (0, utils_1.toNumber)(verificationVideo.lat, trustLat);
    const verificationLng = (0, utils_1.toNumber)(verificationVideo.lng, trustLng);
    const verificationCapturedAtDate = (0, utils_1.toDate)(verificationVideo.capturedAt) || new Date();
    const normalizedAudioUrl = (mediaMetadata.audioUrl || "").toString().trim();
    const listingDataRecord = listingData;
    const requestedFeaturedListing = listingData.featured === true ||
        listingDataRecord.promotionRequestedFeaturedListing === true;
    const requestedFeaturedAuction = listingData.featuredAuction === true ||
        listingDataRecord.promotionRequestedFeaturedAuction === true;
    const promotionRequested = requestedFeaturedListing || requestedFeaturedAuction;
    const promotionType = requestedFeaturedAuction
        ? "featured_auction"
        : (requestedFeaturedListing ? "featured_listing" : "none");
    const promotionStatusInput = toLower(listingDataRecord.promotionStatus || "");
    const promotionStatus = promotionRequested
        ? (promotionStatusInput === "active" ? "pending_review" : (promotionStatusInput || "pending_review"))
        : "none";
    const requestedPromotionCost = (0, utils_1.toNumber)(listingDataRecord.featuredCost, NaN);
    const featuredCost = Number.isFinite(requestedPromotionCost)
        ? Math.max(0, requestedPromotionCost)
        : (requestedFeaturedAuction ? 150 : (requestedFeaturedListing ? 100 : 0));
    const promotionPaymentReference = String(listingDataRecord.promotionPaymentReference || "").trim();
    const promotionProofUrl = String(listingDataRecord.promotionProofUrl || "").trim();
    const normalizedPromotionRequestedAt = (0, utils_1.toDate)(listingDataRecord.promotionRequestedAt) || new Date();
    const marketAverage = await (0, fraud_1.getMarketAverageRate)(db, product, {
        originalCategory: String(listingData.category || "").trim(),
        originalSubcategory: String(listingDataRecord.subcategory || listingDataRecord.subCategory || "").trim(),
        originalVariety: String(listingDataRecord.variety || listingDataRecord.varietyName || "").trim(),
        categoryIdOrKey: String(listingDataRecord.categoryId || listingDataRecord.categoryKey || "").trim(),
        subcategoryIdOrKey: String(listingDataRecord.subcategoryId || listingDataRecord.subcategoryKey || "").trim(),
        varietyIdOrKey: String(listingDataRecord.varietyId || listingDataRecord.varietyKey || "").trim(),
    });
    const heuristic = computeClientPrecheckRisk({
        listingData: {
            product,
            price,
            quantity,
            province,
            district,
            village,
            description,
        },
        mediaMetadata: {
            imageUrls: normalizedImageUrls,
            audioUrl: normalizedAudioUrl,
        },
        marketAverage,
    });
    const ai = await evaluateListingRiskWithGemini({
        listingData: {
            sellerId,
            product,
            price,
            quantity,
            province,
            district,
            village,
            description,
            mandiType: (listingData.mandiType || "").toString(),
            category: (listingData.category || "").toString(),
            unitType: (listingData.unitType || "").toString(),
            marketAverage,
        },
        mediaMetadata: {
            verificationTrustPhoto: {
                lat: trustLat,
                lng: trustLng,
                capturedAt: trustCapturedAtDate.toISOString(),
                tag: (verificationTrustPhoto.tag || "").toString(),
                fileSizeBytes: (0, utils_1.toNumber)(verificationTrustPhoto.fileSizeBytes, 0),
            },
            verificationVideo: {
                url: verificationVideoUrl,
                lat: verificationLat,
                lng: verificationLng,
                durationSeconds: verificationVideoDuration,
                capturedAt: verificationCapturedAtDate.toISOString(),
                tag: (verificationVideo.tag || "").toString(),
                fileSizeBytes: (0, utils_1.toNumber)(verificationVideo.fileSizeBytes, 0),
            },
            imageUrls: normalizedImageUrls,
            audioUrl: normalizedAudioUrl,
        },
        heuristicRiskScore: heuristic.riskScore,
        heuristicFlags: heuristic.flags,
    });
    const finalRiskScore = clampRisk(Math.max(heuristic.riskScore, ai.riskScore));
    const finalFlags = (0, utils_1.uniqueStrings)([...heuristic.flags, ...ai.flags]);
    const finalSummary = ai.summary || "Risk assessment completed.";
    const status = decideListingStatus(finalRiskScore);
    const listingRef = db.collection("listings").doc();
    const userRef = db.collection("users").doc(uid);
    const now = new Date();
    const hourKey = getRateLimitHourKey(now);
    const rateLimitRef = db.collection("listingRateLimits").doc(`${uid}_${hourKey}`);
    console.log("createListingSecureHttp: firestore write start", {
        listingId: listingRef.id,
        sellerId: uid,
        firestoreDocPath: listingRef.path,
        trustPhotoUrlOrPath: String(verificationTrustPhoto.url ||
            verificationTrustPhoto.path || ""),
        optionalMediaFields: {
            verificationVideoUrl: verificationVideoUrl || null,
            verificationVideoDurationSeconds: verificationVideoDuration,
            audioUrl: normalizedAudioUrl || null,
            imageUrlsCount: normalizedImageUrls.length,
            verificationTrustPhotoTag: String((verificationTrustPhoto.tag || "")).trim() || null,
            verificationTrustPhotoFileSizeBytes: (0, utils_1.toNumber)(verificationTrustPhoto.fileSizeBytes, 0),
        },
    });
    await db.runTransaction(async (tx) => {
        const [userSnap, rateLimitSnap] = await Promise.all([
            tx.get(userRef),
            tx.get(rateLimitRef),
        ]);
        const userData = (userSnap.data() || {});
        if (isUserBannedOrFlagged(userData)) {
            throw new https_1.HttpsError("permission-denied", "User is flagged or banned");
        }
        const usedInCurrentHour = (0, utils_1.toNumber)(rateLimitSnap.get("count"), 0);
        if (usedInCurrentHour >= 5) {
            throw new https_1.HttpsError("resource-exhausted", "Rate limit exceeded: max 5 listings per hour");
        }
        tx.set(listingRef, {
            sellerId: uid,
            product,
            price,
            quantity,
            province,
            district,
            village,
            description,
            mandiType: (listingData.mandiType || "").toString(),
            category: (listingData.category || "").toString(),
            unitType: (listingData.unitType || "").toString(),
            featured: false,
            featuredAuction: false,
            featuredCost,
            promotionType,
            promotionStatus,
            promotionPaymentRequired: promotionRequested,
            promotionRequestedFeaturedListing: requestedFeaturedListing,
            promotionRequestedFeaturedAuction: requestedFeaturedAuction,
            promotionRequestedAt: promotionRequested ? firestore_2.Timestamp.fromDate(normalizedPromotionRequestedAt) : null,
            promotionPaymentReference,
            promotionProofUrl,
            priorityScore: "normal",
            mediaMetadata: {
                verificationTrustPhoto: {
                    lat: trustLat,
                    lng: trustLng,
                    capturedAt: firestore_2.Timestamp.fromDate(trustCapturedAtDate),
                    tag: (verificationTrustPhoto.tag || "").toString(),
                    fileSizeBytes: (0, utils_1.toNumber)(verificationTrustPhoto.fileSizeBytes, 0),
                },
                verificationVideo: {
                    url: verificationVideoUrl,
                    lat: verificationLat,
                    lng: verificationLng,
                    durationSeconds: verificationVideoDuration,
                    capturedAt: firestore_2.Timestamp.fromDate(verificationCapturedAtDate),
                    tag: (verificationVideo.tag || "").toString(),
                    fileSizeBytes: (0, utils_1.toNumber)(verificationVideo.fileSizeBytes, 0),
                },
                imageUrls: normalizedImageUrls,
                audioUrl: normalizedAudioUrl,
            },
            heuristicRiskScore: heuristic.riskScore,
            aiRiskScore: ai.riskScore,
            riskScore: finalRiskScore,
            riskFlags: finalFlags,
            riskSummary: finalSummary,
            status,
            createdAt: firestore_2.FieldValue.serverTimestamp(),
            updatedAt: firestore_2.FieldValue.serverTimestamp(),
        }, { merge: true });
        tx.set(rateLimitRef, {
            uid,
            hourKey,
            count: usedInCurrentHour + 1,
            windowStartedAt: firestore_2.Timestamp.fromDate(new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), now.getUTCHours(), 0, 0))),
            updatedAt: firestore_2.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
    console.log("createListingSecureHttp: firestore write success", {
        listingId: listingRef.id,
        sellerId: uid,
        firestoreDocPath: listingRef.path,
    });
    if (promotionRequested) {
        const promoEventAt = firestore_2.FieldValue.serverTimestamp();
        await db.collection("revenue_ledger").add({
            entryType: "promotion_request",
            sourceListingId: listingRef.id,
            sellerId: uid,
            amount: featuredCost,
            revenueCategory: promotionType,
            status: "pending_review",
            createdAt: promoEventAt,
            approvedAt: null,
            notes: "Promotion request received",
        });
        await db.collection("notifications").add({
            userId: uid,
            type: "promotion_request_received",
            title: "Promotion request received",
            body: "Your promotion request is pending admin finance review.",
            titleUr: "پروموشن درخواست موصول",
            bodyUr: "آپ کی پروموشن درخواست ایڈمن فنانس ریویو کے لیے زیرِ جائزہ ہے۔",
            routeName: "",
            routeParams: {},
            listingId: listingRef.id,
            createdAt: promoEventAt,
            read: false,
            metadata: {
                promotionType,
                featuredCost,
                promotionStatus,
            },
        });
    }
    return {
        listingId: listingRef.id,
        status,
        riskScore: finalRiskScore,
        flags: finalFlags,
        summary: finalSummary,
    };
}
exports.createListingSecure = (0, https_1.onCall)(AI_RUNTIME_OPTIONS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    const data = (request.data || {});
    return createListingSecureInternal(uid, data);
});
exports.createListingSecureHttp = (0, https_1.onRequest)(AI_RUNTIME_OPTIONS, async (req, res) => {
    setCorsHeaders(res);
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ ok: false, error: "method-not-allowed" });
        return;
    }
    console.log("createListingSecureHttp: auth verification start");
    const uid = await getUidFromBearerToken(req);
    if (!uid) {
        res.status(401).json({ ok: false, error: "unauthenticated" });
        return;
    }
    let requestBodyKeys = [];
    let listingId = null;
    let sellerId = null;
    let firestoreDocPath = null;
    let trustPhotoUrlOrPath = null;
    let optionalMediaFields = {};
    try {
        console.log("createListingSecureHttp: request parse start");
        const rawBody = readRequestBody(req);
        requestBodyKeys = Object.keys(rawBody);
        const bodyRecord = rawBody;
        const listingData = bodyRecord.listingData && typeof bodyRecord.listingData === "object" ?
            bodyRecord.listingData :
            {};
        const mediaMetadata = bodyRecord.mediaMetadata && typeof bodyRecord.mediaMetadata === "object" ?
            bodyRecord.mediaMetadata :
            {};
        const verificationTrustPhoto = mediaMetadata.verificationTrustPhoto && typeof mediaMetadata.verificationTrustPhoto === "object" ?
            mediaMetadata.verificationTrustPhoto :
            {};
        const verificationVideo = mediaMetadata.verificationVideo && typeof mediaMetadata.verificationVideo === "object" ?
            mediaMetadata.verificationVideo :
            {};
        listingId = String(bodyRecord.listingId || listingData.listingId || "").trim() || null;
        sellerId = String(listingData.sellerId || "").trim() || null;
        firestoreDocPath = listingId ? `listings/${listingId}` : null;
        const imageUrls = Array.isArray(mediaMetadata.imageUrls) ?
            mediaMetadata.imageUrls.map((v) => String(v).trim()).filter((v) => v.length > 0) :
            [];
        trustPhotoUrlOrPath = String(verificationTrustPhoto.url ||
            verificationTrustPhoto.path ||
            "").trim() || null;
        optionalMediaFields = {
            verificationVideoUrl: String(verificationVideo.url || "").trim() || null,
            verificationVideoDurationSeconds: (0, utils_1.toNumber)(verificationVideo.durationSeconds, 0),
            verificationVideoTag: String(verificationVideo.tag || "").trim() || null,
            verificationVideoFileSizeBytes: (0, utils_1.toNumber)(verificationVideo.fileSizeBytes, 0),
            audioUrl: String(mediaMetadata.audioUrl || "").trim() || null,
            imageUrlsCount: imageUrls.length,
            verificationTrustPhotoTag: String(verificationTrustPhoto.tag || "").trim() || null,
            verificationTrustPhotoFileSizeBytes: (0, utils_1.toNumber)(verificationTrustPhoto.fileSizeBytes, 0),
        };
        const data = rawBody;
        const result = await createListingSecureInternal(uid, data);
        res.status(200).json({ ok: true, ...result });
    }
    catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        const stackTrace = error instanceof Error ? error.stack : undefined;
        console.error("createListingSecureHttp: create-listing-failed diagnostics", {
            errorObject: error,
            errorMessage,
            stackTrace,
            authenticatedUid: uid,
            requestBodyKeys,
            listingId,
            sellerId,
            firestoreDocPath,
            trustPhotoUrlOrPath,
            optionalMediaFields,
        });
        res.status(400).json({ ok: false, error: "create-listing-failed" });
    }
});
function toLower(value) {
    return String(value || "").trim().toLowerCase();
}
function listingStatusFrom(data) {
    return toLower(data.status || data.listingStatus || data.auctionStatus);
}
function auctionStatusFrom(data) {
    return toLower(data.auctionStatus || data.status || data.listingStatus);
}
async function assertAdminUser(uid) {
    const userSnap = await db.collection("users").doc(uid).get();
    const userData = (userSnap.data() || {});
    const role = toLower(userData.role || userData.userRole || userData.userType);
    if (role === "admin")
        return;
    throw new https_1.HttpsError("permission-denied", "admin-access-required");
}
async function assertAdminUserWithClaims(uid, decodedToken) {
    if (decodedToken.admin === true) {
        return;
    }
    const userSnap = await db.collection("users").doc(uid).get();
    const userData = (userSnap.data() || {});
    const role = toLower(userData.role || userData.userRole || userData.userType);
    if (role === "admin")
        return;
    throw new https_1.HttpsError("permission-denied", "admin-access-required");
}
async function writeAdminListingAudit(params) {
    let actionByEmail = "";
    let actionByName = "";
    try {
        const adminUser = await admin.auth().getUser(params.uid);
        actionByEmail = adminUser.email || "";
        actionByName = adminUser.displayName || "";
    }
    catch (error) {
        console.warn("adminAction: unable to resolve admin identity", { uid: params.uid, error });
    }
    await db.collection("admin_action_logs").add({
        entityType: "listing",
        entityId: params.listingId,
        actionType: params.actionType,
        actionBy: params.uid,
        actionByEmail,
        actionByName,
        actionAt: firestore_2.FieldValue.serverTimestamp(),
        notes: params.notes || "",
        targetCollection: "listings",
        targetDocId: params.listingId,
        previousStatus: params.previousStatus,
        previousAuctionStatus: params.previousAuctionStatus,
        newStatus: params.newStatus,
        newAuctionStatus: params.newAuctionStatus,
        reason: params.notes || "",
        previousStateSummary: {
            status: params.previousStatus,
            auctionStatus: params.previousAuctionStatus,
        },
        newStateSummary: {
            status: params.newStatus,
            auctionStatus: params.newAuctionStatus,
        },
        intendedStatus: params.intendedStatus || "",
        intendedAuctionStatus: params.intendedAuctionStatus || "",
        result: "success",
    });
}
function buildAdminListingNotification(actionType, note) {
    switch (actionType) {
        case "approve_listing":
            return {
                notificationType: "listing_approved",
                title: "Listing approved",
                body: "Your listing is now live in the marketplace.",
                titleUr: "لسٹنگ منظور ہو گئی",
                bodyUr: "آپ کی لسٹنگ اب مارکیٹ پلیس میں لائیو ہے۔",
            };
        case "reject_listing":
            return {
                notificationType: "listing_rejected",
                title: "Listing rejected",
                body: note ? `Your listing was rejected: ${note}` : "Your listing was rejected by admin review.",
                titleUr: "لسٹنگ مسترد کر دی گئی",
                bodyUr: note ? `آپ کی لسٹنگ مسترد کر دی گئی: ${note}` : "ایڈمن ریویو کے بعد آپ کی لسٹنگ مسترد کر دی گئی۔",
            };
        case "request_changes":
            return {
                notificationType: "listing_changes_requested",
                title: "Changes requested",
                body: note ? `Please update your listing: ${note}` : "Admin requested updates to your listing.",
                titleUr: "تبدیلیاں درکار ہیں",
                bodyUr: note ? `براہ کرم اپنی لسٹنگ اپڈیٹ کریں: ${note}` : "ایڈمن نے آپ کی لسٹنگ میں تبدیلیاں مانگی ہیں۔",
            };
        case "start_auction":
            return {
                notificationType: "auction_started",
                title: "Auction started",
                body: "Your auction is now live.",
                titleUr: "نیلامی شروع ہو گئی",
                bodyUr: "آپ کی نیلامی اب لائیو ہے۔",
            };
        case "pause_auction":
            return {
                notificationType: "auction_paused",
                title: "Auction paused",
                body: note ? `Your auction was paused: ${note}` : "Your auction was paused by admin.",
                titleUr: "نیلامی روک دی گئی",
                bodyUr: note ? `آپ کی نیلامی روک دی گئی: ${note}` : "ایڈمن کی جانب سے آپ کی نیلامی روک دی گئی ہے۔",
            };
        case "resume_auction":
            return {
                notificationType: "auction_resumed",
                title: "Auction resumed",
                body: "Your auction has resumed and is live again.",
                titleUr: "نیلامی دوبارہ شروع",
                bodyUr: "آپ کی نیلامی دوبارہ شروع ہو گئی اور اب لائیو ہے۔",
            };
        case "cancel_auction":
            return {
                notificationType: "auction_cancelled",
                title: "Auction cancelled",
                body: note ? `Your auction was cancelled: ${note}` : "Your auction was cancelled by admin.",
                titleUr: "نیلامی منسوخ کر دی گئی",
                bodyUr: note ? `آپ کی نیلامی منسوخ کر دی گئی: ${note}` : "ایڈمن نے آپ کی نیلامی منسوخ کر دی ہے۔",
            };
        case "extend_auction":
            return {
                notificationType: "auction_extended",
                title: "Auction extended",
                body: note ? `Your auction was extended (${note}).` : "Your auction duration was extended.",
                titleUr: "نیلامی میں توسیع",
                bodyUr: note ? `آپ کی نیلامی میں توسیع کی گئی (${note})۔` : "آپ کی نیلامی کی مدت بڑھا دی گئی ہے۔",
            };
        default:
            return {
                notificationType: "admin_listing_update",
                title: "Listing updated",
                body: "Your listing was updated by admin.",
                titleUr: "لسٹنگ اپڈیٹ",
                bodyUr: "ایڈمن کی طرف سے آپ کی لسٹنگ اپڈیٹ کی گئی ہے۔",
            };
    }
}
async function notifySellerForAdminAction(listingId, listingData, actionType, note) {
    const sellerId = String(listingData.sellerId ||
        listingData.ownerId ||
        listingData.userId ||
        "").trim();
    if (!sellerId) {
        console.warn("adminAction: missing seller id for notification", { listingId, actionType });
        return;
    }
    const listingTitle = String(listingData.title || listingData.cropType || listingData.productName || "Listing").trim() || "Listing";
    const copy = buildAdminListingNotification(actionType, note);
    await db.collection("notifications").add({
        userId: sellerId,
        type: copy.notificationType,
        title: copy.title,
        body: copy.body,
        titleUr: copy.titleUr,
        bodyUr: copy.bodyUr,
        routeName: "buyer_listing_detail",
        routeParams: { listingId },
        listingId,
        listingTitle,
        createdAt: firestore_2.FieldValue.serverTimestamp(),
        read: false,
        metadata: {
            actionType,
            note,
            source: "admin_command_center",
        },
    });
}
async function executeAdminListingAction(uid, body, buildTransition) {
    const listingId = requireString(body.listingId, "listingId");
    const note = String(body.note || "").trim();
    const extensionHours = Math.max(1, Math.round((0, utils_1.toNumber)(body.extensionHours, 2)));
    console.log("adminAction: received", { uid, listingId });
    await assertAdminUser(uid);
    console.log("adminAction: admin auth validated", { uid });
    const listingRef = db.collection("listings").doc(listingId);
    const listingSnap = await listingRef.get();
    if (!listingSnap.exists) {
        throw new https_1.HttpsError("not-found", "listing-not-found");
    }
    const listingData = (listingSnap.data() || {});
    const previousStatus = listingStatusFrom(listingData);
    const previousAuctionStatus = auctionStatusFrom(listingData);
    console.log("adminAction: listing loaded", {
        listingId,
        previousStatus,
        previousAuctionStatus,
        isApproved: listingData.isApproved === true,
    });
    const transition = buildTransition(uid, listingId, listingData, note, extensionHours);
    console.log("adminAction: payload", {
        listingId,
        actionType: transition.actionType,
        updates: transition.updates,
    });
    await listingRef.set({
        ...transition.updates,
        updatedAt: firestore_2.FieldValue.serverTimestamp(),
    }, { merge: true });
    await listingRef.set({
        lastAdminAction: {
            actionType: transition.actionType,
            actionBy: uid,
            actionAt: firestore_2.FieldValue.serverTimestamp(),
            notes: transition.notes || "",
        },
    }, { merge: true });
    const finalSnap = await listingRef.get();
    const finalData = (finalSnap.data() || {});
    const finalStatus = listingStatusFrom(finalData);
    const finalAuctionStatus = auctionStatusFrom(finalData);
    await writeAdminListingAudit({
        uid,
        listingId,
        actionType: transition.actionType,
        notes: transition.notes,
        previousStatus,
        previousAuctionStatus,
        newStatus: finalStatus,
        newAuctionStatus: finalAuctionStatus,
        intendedStatus: transition.intendedStatus,
        intendedAuctionStatus: transition.intendedAuctionStatus,
    });
    await notifySellerForAdminAction(listingId, listingData, transition.actionType, transition.notes || note);
    console.log("adminAction: write success", {
        listingId,
        actionType: transition.actionType,
        finalStatus,
        finalAuctionStatus,
        finalIsApproved: finalData.isApproved === true,
    });
    return {
        ok: true,
        listingId,
        actionType: transition.actionType,
        status: finalStatus,
        auctionStatus: finalAuctionStatus,
        isApproved: finalData.isApproved === true,
    };
}
function ensurePost(req, res) {
    setCorsHeaders(res);
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return false;
    }
    if (req.method !== "POST") {
        res.status(405).json({ ok: false, error: "method-not-allowed" });
        return false;
    }
    return true;
}
async function executeAdminHttpAction(req, res, buildTransition) {
    if (!ensurePost(req, res))
        return;
    const decoded = await getDecodedTokenFromBearerToken(req);
    if (!decoded?.uid) {
        res.status(401).json({ ok: false, error: "unauthenticated" });
        return;
    }
    const uid = decoded.uid;
    const body = readRequestBody(req);
    try {
        await assertAdminUserWithClaims(uid, decoded);
        const result = await executeAdminListingAction(uid, body, buildTransition);
        res.status(200).json(result);
    }
    catch (error) {
        const message = error instanceof https_1.HttpsError ? error.message : "admin-action-failed";
        console.error("adminAction: failed", { uid, error: message });
        res.status(400).json({ ok: false, error: message });
    }
}
exports.approveListingAdmin = (0, https_1.onRequest)({ region: "asia-south1" }, async (req, res) => {
    await executeAdminHttpAction(req, res, (uid, _listingId, _listingData) => ({
        actionType: "approve_listing",
        updates: {
            isApproved: true,
            status: "active",
            listingStatus: "active",
            adminReviewStatus: "approved",
            approvedAt: firestore_2.FieldValue.serverTimestamp(),
            approvedBy: uid,
        },
        intendedStatus: "active",
        intendedAuctionStatus: "",
    }));
});
exports.rejectListingAdmin = (0, https_1.onRequest)({ region: "asia-south1" }, async (req, res) => {
    await executeAdminHttpAction(req, res, (_uid, _listingId, listingData, note) => {
        if (!note) {
            throw new https_1.HttpsError("invalid-argument", "note-required");
        }
        const status = listingStatusFrom(listingData);
        if (status === "rejected") {
            throw new https_1.HttpsError("failed-precondition", "listing-already-rejected");
        }
        return {
            actionType: "reject_listing",
            updates: {
                isApproved: false,
                status: "rejected",
                listingStatus: "rejected",
                adminReviewStatus: "rejected",
                adminReviewNote: note,
                rejectedAt: firestore_2.FieldValue.serverTimestamp(),
            },
            notes: note,
            intendedStatus: "rejected",
            intendedAuctionStatus: auctionStatusFrom(listingData),
        };
    });
});
exports.requestListingChangesAdmin = (0, https_1.onRequest)({ region: "asia-south1" }, async (req, res) => {
    await executeAdminHttpAction(req, res, (_uid, _listingId, listingData, note) => {
        if (!note) {
            throw new https_1.HttpsError("invalid-argument", "note-required");
        }
        return {
            actionType: "request_changes",
            updates: {
                isApproved: false,
                status: "pending",
                adminReviewStatus: "changes_requested",
                adminChangeRequestNotes: note,
                adminChangeRequestedAt: firestore_2.FieldValue.serverTimestamp(),
            },
            notes: note,
            intendedStatus: "pending",
            intendedAuctionStatus: auctionStatusFrom(listingData),
        };
    });
});
exports.startAuctionAdmin = (0, https_1.onRequest)({ region: "asia-south1" }, async (req, res) => {
    await executeAdminHttpAction(req, res, (uid, _listingId, listingData) => {
        const currentStatus = listingStatusFrom(listingData);
        const currentAuctionStatus = auctionStatusFrom(listingData);
        if (currentStatus === "rejected") {
            throw new https_1.HttpsError("failed-precondition", "cannot-start-auction-for-rejected-listing");
        }
        if (currentAuctionStatus === "live") {
            throw new https_1.HttpsError("failed-precondition", "auction-already-live");
        }
        if (currentAuctionStatus === "cancelled" || currentAuctionStatus === "completed") {
            throw new https_1.HttpsError("failed-precondition", "cannot-restart-cancelled-or-completed-auction");
        }
        const now = new Date();
        const end = new Date(now.getTime() + (24 * 60 * 60 * 1000));
        return {
            actionType: "start_auction",
            updates: {
                isApproved: true,
                status: "active",
                listingStatus: "active",
                auctionStatus: "live",
                adminReviewStatus: "approved",
                approvedAt: firestore_2.FieldValue.serverTimestamp(),
                approvedBy: uid,
                startTime: firestore_2.Timestamp.fromDate(now),
                endTime: firestore_2.Timestamp.fromDate(end),
                bidStartTime: firestore_2.Timestamp.fromDate(now),
                bidExpiryTime: firestore_2.Timestamp.fromDate(end),
                isBidPaused: false,
                isBidForceClosed: false,
            },
            intendedStatus: "active",
            intendedAuctionStatus: "live",
        };
    });
});
exports.pauseAuctionAdmin = (0, https_1.onRequest)({ region: "asia-south1" }, async (req, res) => {
    await executeAdminHttpAction(req, res, (_uid, _listingId, listingData) => {
        const auctionStatus = auctionStatusFrom(listingData);
        if (auctionStatus !== "live") {
            throw new https_1.HttpsError("failed-precondition", `cannot-pause-from-${auctionStatus || "unknown"}`);
        }
        return {
            actionType: "pause_auction",
            updates: {
                auctionStatus: "paused",
                isBidPaused: true,
            },
            intendedStatus: listingStatusFrom(listingData),
            intendedAuctionStatus: "paused",
        };
    });
});
exports.resumeAuctionAdmin = (0, https_1.onRequest)({ region: "asia-south1" }, async (req, res) => {
    await executeAdminHttpAction(req, res, (_uid, _listingId, listingData) => {
        const auctionStatus = auctionStatusFrom(listingData);
        if (auctionStatus !== "paused") {
            throw new https_1.HttpsError("failed-precondition", `cannot-resume-from-${auctionStatus || "unknown"}`);
        }
        return {
            actionType: "resume_auction",
            updates: {
                auctionStatus: "live",
                isBidPaused: false,
            },
            intendedStatus: listingStatusFrom(listingData),
            intendedAuctionStatus: "live",
        };
    });
});
exports.cancelAuctionAdmin = (0, https_1.onRequest)({ region: "asia-south1" }, async (req, res) => {
    await executeAdminHttpAction(req, res, (_uid, _listingId, listingData, note) => {
        if (!note) {
            throw new https_1.HttpsError("invalid-argument", "note-required");
        }
        const auctionStatus = auctionStatusFrom(listingData);
        if (auctionStatus === "cancelled" || auctionStatus === "completed") {
            throw new https_1.HttpsError("failed-precondition", `cannot-cancel-from-${auctionStatus || "unknown"}`);
        }
        return {
            actionType: "cancel_auction",
            updates: {
                auctionStatus: "cancelled",
                isBidForceClosed: true,
                isBidPaused: false,
                bidClosedAt: firestore_2.FieldValue.serverTimestamp(),
            },
            notes: note,
            intendedStatus: listingStatusFrom(listingData),
            intendedAuctionStatus: "cancelled",
        };
    });
});
exports.extendAuctionAdmin = (0, https_1.onRequest)({ region: "asia-south1" }, async (req, res) => {
    await executeAdminHttpAction(req, res, (_uid, _listingId, listingData, _note, extensionHours) => {
        const auctionStatus = auctionStatusFrom(listingData);
        if (auctionStatus !== "live" && auctionStatus !== "paused") {
            throw new https_1.HttpsError("failed-precondition", `cannot-extend-from-${auctionStatus || "unknown"}`);
        }
        const baseDate = (0, utils_1.toDate)(listingData.bidExpiryTime) || (0, utils_1.toDate)(listingData.endTime) || new Date();
        const nextDate = new Date(baseDate.getTime() + (extensionHours * 60 * 60 * 1000));
        return {
            actionType: "extend_auction",
            updates: {
                bidExpiryTime: firestore_2.Timestamp.fromDate(nextDate),
                endTime: firestore_2.Timestamp.fromDate(nextDate),
                auctionStatus: auctionStatus,
            },
            notes: `+${extensionHours}h`,
            intendedStatus: listingStatusFrom(listingData),
            intendedAuctionStatus: auctionStatus,
        };
    });
});
exports.aiGenerateText = (0, https_1.onRequest)(AI_GENERATE_TEXT_RUNTIME_OPTIONS, async (req, res) => {
    setCorsHeaders(res);
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ ok: false, error: "method-not-allowed" });
        return;
    }
    const body = readRequestBody(req);
    const prompt = String(body.prompt || "").trim();
    if (!prompt) {
        res.status(400).json({ ok: false, error: "prompt-required" });
        return;
    }
    try {
        const text = await callGeminiText({
            prompt,
            model: "gemini-1.5-flash",
        });
        res.status(200).json({ ok: true, text });
    }
    catch (error) {
        const errorText = String(error || "unknown").trim() || "unknown";
        console.error("aiGenerateText_failed", {
            error: errorText,
        });
        res.status(503).json({ ok: false, error: "ai-unavailable", errorMessage: errorText });
    }
});
exports.weatherCurrentHttp = (0, https_1.onRequest)(AI_RUNTIME_OPTIONS, async (req, res) => {
    setCorsHeaders(res);
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ ok: false, error: "method-not-allowed" });
        return;
    }
    const body = readRequestBody(req);
    const district = String(body.district || "").trim();
    try {
        const weather = await getCurrentWeatherForPakistanDistrict(district);
        res.status(200).json({ ok: true, success: true, ...weather });
    }
    catch (error) {
        const message = error instanceof https_1.HttpsError ? error.message : "weather-unavailable";
        res.status(503).json({ ok: false, success: false, error: message });
    }
});
exports.aiWeatherAdvisory = (0, https_1.onRequest)(AI_RUNTIME_OPTIONS, async (req, res) => {
    setCorsHeaders(res);
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ ok: false, error: "method-not-allowed" });
        return;
    }
    const body = readRequestBody(req);
    const condition = String(body.condition || "").trim();
    const temperature = (0, utils_1.toNumber)(body.temperature, 0);
    const crop = String(body.crop || "").trim();
    const prompt = `You are a mandi assistant. Give a short Roman-Urdu weather advisory for crop protection. ` +
        `Condition: ${condition || "unknown"}. Temperature C: ${temperature}. Crop: ${crop || "general"}.`;
    try {
        const advisory = await callGeminiText({ prompt });
        res.status(200).json({ ok: true, advisory });
    }
    catch (_) {
        res.status(503).json({ ok: false, error: "ai-unavailable" });
    }
});
exports.aiSuggestBidRate = (0, https_1.onRequest)(AI_RUNTIME_OPTIONS, async (req, res) => {
    setCorsHeaders(res);
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ ok: false, error: "method-not-allowed" });
        return;
    }
    const body = readRequestBody(req);
    const payload = {
        item: String(body.item || "").trim(),
        location: String(body.location || "Pakistan").trim(),
        baseline: (0, utils_1.toNumber)(body.baseline, 0),
        bidSamples: Array.isArray(body.bidSamples) ? body.bidSamples : [],
    };
    if (!payload.item) {
        res.status(400).json({ ok: false, error: "item-required" });
        return;
    }
    const prompt = [
        "Return ONLY JSON with schema {suggestedRate:number,reason:string}.",
        "Use Pakistani mandi context and the supplied recent bid samples.",
        `Item: ${payload.item}`,
        `Location: ${payload.location}`,
        `Baseline: ${payload.baseline}`,
        `BidSamples: ${JSON.stringify(payload.bidSamples)}`,
    ].join("\n");
    try {
        const raw = await callGeminiText({
            prompt,
            temperature: 0.1,
            responseMimeType: "application/json",
        });
        const parsed = JSON.parse(extractJsonBlock(raw));
        const suggestedRate = Math.max(0, (0, utils_1.toNumber)(parsed.suggestedRate, payload.baseline));
        const reason = String(parsed.reason || "AI suggested from recent bids.").trim();
        res.status(200).json({ ok: true, suggestedRate, reason });
    }
    catch (_) {
        res.status(503).json({ ok: false, error: "ai-unavailable" });
    }
});
exports.aiExtractCnic = (0, https_1.onRequest)(AI_EXTRACT_CNIC_RUNTIME_OPTIONS, async (req, res) => {
    setCorsHeaders(res);
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ ok: false, error: "method-not-allowed" });
        return;
    }
    const body = readRequestBody(req);
    const mimeType = String(body.mimeType || "image/jpeg").trim() || "image/jpeg";
    const imageBase64Raw = String(body.imageBase64 || "").trim();
    const imageBase64 = imageBase64Raw.includes(",") ? imageBase64Raw.split(",").pop() || "" : imageBase64Raw;
    if (!imageBase64) {
        res.status(400).json({ ok: false, success: false, errorMessage: "image-required" });
        return;
    }
    const prompt = "You are a strict Pakistani CNIC OCR parser.\n" +
        "Carefully distinguish between Name, Father Name, and CNIC Number fields.\n" +
        "You must first decide whether the image is really a Pakistani CNIC and whether it is the front or back side.\n" +
        "Extract text from both Urdu and English labels on Pakistani CNIC.\n" +
        "If image is blurry, low-resolution, cropped, reflective, or uncertain, DO NOT GUESS.\n" +
        "Return status=error and ask for a clearer photo.\n" +
        "Return ONLY valid JSON with this exact schema:\n" +
        "{\"status\":\"ok|error\",\"error\":\"string\",\"isCnicDocument\":true,\"detectedSide\":\"front|back|unknown\",\"name\":\"string\",\"fatherName\":\"string\",\"cnicNumber\":\"xxxxx-xxxxxxx-x\",\"dateOfBirth\":\"string\",\"expiryDate\":\"string\",\"confidence\":\"high|medium|low\"}";
    try {
        const raw = await callGeminiText({
            prompt,
            model: GEMINI_STABLE_MODEL,
            temperature: 0,
            responseMimeType: "application/json",
            parts: [
                { text: prompt },
                {
                    inlineData: {
                        mimeType: mimeType,
                        data: imageBase64,
                    },
                },
            ],
        });
        const parsed = JSON.parse(extractJsonBlock(raw));
        const status = String(parsed.status || "").toLowerCase().trim();
        const confidence = String(parsed.confidence || "").toLowerCase().trim() || "low";
        const isCnicDocument = parsed.isCnicDocument === true;
        const detectedSide = normalizeDetectedSide(String(parsed.detectedSide || "unknown"));
        const name = String(parsed.name || "").trim();
        const fatherName = String(parsed.fatherName || "").trim();
        const cnicNumber = normalizeCnic(String(parsed.cnicNumber || ""));
        const dateOfBirth = String(parsed.dateOfBirth || "").trim();
        const expiryDate = String(parsed.expiryDate || "").trim();
        const errorMessage = String(parsed.error || "").trim();
        if (status === "error" || !isCnicDocument || detectedSide === "unknown") {
            res.status(200).json({
                ok: true,
                success: false,
                errorMessage: errorMessage || "CNIC image unclear or wrong document. Please upload a clearer CNIC photo.",
                rawResponse: raw,
            });
            return;
        }
        res.status(200).json({
            ok: true,
            success: true,
            isCnicDocument,
            detectedSide,
            name,
            fatherName,
            cnicNumber,
            dateOfBirth,
            expiryDate,
            confidence,
            rawResponse: raw,
        });
    }
    catch (error) {
        const errorText = String(error || "unknown").trim() || "unknown";
        console.error("aiExtractCnic_failed", {
            error: errorText,
        });
        res.status(503).json({
            ok: false,
            success: false,
            errorMessage: `ai-unavailable|${errorText}`,
        });
    }
});
exports.evaluateListingRisk = (0, https_1.onCall)(AI_RUNTIME_OPTIONS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const listingId = String(request.data?.listingId || "").trim();
    if (!listingId) {
        throw new https_1.HttpsError("invalid-argument", "listingId is required");
    }
    await enforceAiThrottle({
        scope: "evaluateListingRisk_uid",
        key: uid,
        limit: 24,
        windowSeconds: 3600,
    });
    await enforceAiThrottle({
        scope: "evaluateListingRisk_listing",
        key: listingId,
        limit: 12,
        windowSeconds: 3600,
    });
    return evaluateListingRiskDocument(listingId);
});
exports.evaluateListingRiskHttp = (0, https_1.onRequest)(AI_RUNTIME_OPTIONS, async (req, res) => {
    setCorsHeaders(res);
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ ok: false, error: "method-not-allowed" });
        return;
    }
    const uid = await getUidFromBearerToken(req);
    if (!uid) {
        res.status(401).json({ ok: false, error: "unauthenticated" });
        return;
    }
    const listingId = String(readRequestBody(req).listingId || "").trim();
    if (!listingId) {
        res.status(400).json({ ok: false, error: "listingId is required" });
        return;
    }
    try {
        await enforceAiThrottle({
            scope: "evaluateListingRisk_uid",
            key: uid,
            limit: 24,
            windowSeconds: 3600,
        });
        await enforceAiThrottle({
            scope: "evaluateListingRisk_listing",
            key: listingId,
            limit: 12,
            windowSeconds: 3600,
        });
        const result = await evaluateListingRiskDocument(listingId);
        res.status(200).json({ ok: true, ...result });
    }
    catch (error) {
        const message = error instanceof https_1.HttpsError ? error.message : "evaluate-listing-risk-failed";
        res.status(400).json({ ok: false, error: message });
    }
});
async function suggestMarketRateInternal(uid, data) {
    await enforceAiThrottle({
        scope: "suggestMarketRate_uid",
        key: uid,
        limit: 50,
        windowSeconds: 3600,
    });
    let itemName = String(data.itemName || "").trim();
    let province = String(data.province || "").trim();
    let district = String(data.district || "").trim();
    let quantity = (0, utils_1.toNumber)(data.quantity, 0);
    let unit = String(data.unit || "").trim();
    const listingId = String(data.listingId || "").trim();
    if (listingId) {
        const listingSnap = await db.collection("listings").doc(listingId).get();
        if (!listingSnap.exists) {
            throw new https_1.HttpsError("not-found", "listing-not-found");
        }
        const listing = (listingSnap.data() || {});
        itemName = String(listing.product || listing.cropName || listing.itemName || itemName).trim();
        province = String(listing.province || province).trim();
        district = String(listing.district || district).trim();
        quantity = (0, utils_1.toNumber)(listing.quantity, quantity);
        unit = String(listing.unit || listing.unitType || unit).trim();
    }
    if (!itemName) {
        throw new https_1.HttpsError("invalid-argument", "itemName or listingId is required");
    }
    const baseline = await (0, fraud_1.getMarketAverageRate)(db, itemName, {
        originalCategory: String(data.category || "").trim(),
        originalSubcategory: String(data.subcategory || data.subCategory || "").trim(),
        originalVariety: String(data.variety || data.varietyName || "").trim(),
        categoryIdOrKey: String(data.categoryId || data.categoryKey || "").trim(),
        subcategoryIdOrKey: String(data.subcategoryId || data.subcategoryKey || "").trim(),
        varietyIdOrKey: String(data.varietyId || data.varietyKey || "").trim(),
    });
    let suggestedMin = Math.max(1, Math.round((baseline || 1) * 0.9));
    let suggestedMax = Math.max(suggestedMin + 1, Math.round((baseline || 1) * 1.1));
    let confidence = baseline && baseline > 0 ? 0.7 : 0.45;
    let reasonEn = "Range based on recent mandi patterns.";
    let reasonUrdu = "یہ رینج حالیہ منڈی رجحان کی بنیاد پر ہے۔";
    const prompt = [
        "Return ONLY JSON: {suggestedMin:number,suggestedMax:number,confidence:number,reasonUrdu:string,reasonEn:string}",
        "Use calm, short advice for a Pakistan mandi app.",
        JSON.stringify({ itemName, province, district, quantity, unit, baseline }),
    ].join("\n");
    try {
        const raw = await callGeminiText({
            prompt,
            temperature: 0.1,
            responseMimeType: "application/json",
        });
        const parsed = JSON.parse(extractJsonBlock(raw));
        const aiMin = Math.round((0, utils_1.toNumber)(parsed.suggestedMin, suggestedMin));
        const aiMax = Math.round((0, utils_1.toNumber)(parsed.suggestedMax, suggestedMax));
        suggestedMin = Math.max(1, Math.min(aiMin, aiMax));
        suggestedMax = Math.max(suggestedMin + 1, Math.max(aiMin, aiMax));
        confidence = Math.max(0, Math.min(1, (0, utils_1.toNumber)(parsed.confidence, confidence)));
        reasonEn = String(parsed.reasonEn || reasonEn).trim() || reasonEn;
        reasonUrdu = String(parsed.reasonUrdu || reasonUrdu).trim() || reasonUrdu;
    }
    catch (_) {
        // Keep deterministic fallback range.
    }
    return {
        suggestedMin,
        suggestedMax,
        confidence,
        suggestedRateMin: suggestedMin,
        suggestedRateMax: suggestedMax,
        confidenceLevel: toConfidenceLevel(confidence),
        reason: reasonEn,
        reasonUrdu,
        reasonEn,
    };
}
exports.suggestMarketRate = (0, https_1.onCall)(AI_RUNTIME_OPTIONS, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const data = (request.data || {});
    return suggestMarketRateInternal(uid, data);
});
exports.suggestMarketRateHttp = (0, https_1.onRequest)(AI_RUNTIME_OPTIONS, async (req, res) => {
    setCorsHeaders(res);
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ ok: false, error: "method-not-allowed" });
        return;
    }
    const uid = await getUidFromBearerToken(req);
    if (!uid) {
        res.status(401).json({ ok: false, error: "unauthenticated" });
        return;
    }
    try {
        const result = await suggestMarketRateInternal(uid, readRequestBody(req));
        res.status(200).json({ ok: true, ...result });
    }
    catch (error) {
        const message = error instanceof https_1.HttpsError ? error.message : "suggest-market-rate-failed";
        res.status(400).json({ ok: false, error: message });
    }
});
function normalizeTrendToken(value) {
    return String(value || "").trim().toLowerCase();
}
function average(values) {
    if (values.length === 0)
        return 0;
    return values.reduce((a, b) => a + b, 0) / values.length;
}
function toTrendDirection(changePercent) {
    if (changePercent > 1)
        return "rising";
    if (changePercent < -1)
        return "falling";
    return "stable";
}
function buildTrendSummary(crop, province, district, direction, changePercent) {
    const cropLabel = crop || "Crop";
    const location = district || province || "Pakistan";
    if (direction === "stable") {
        return `${cropLabel} prices stable in ${location} (0%) over last 24 hours.`;
    }
    const sign = changePercent >= 0 ? "+" : "";
    const pct = `${sign}${changePercent.toFixed(1)}%`;
    return `${cropLabel} prices ${direction} in ${location} (${pct}) over last 24 hours.`;
}
function listingTimestamp(data) {
    return ((0, utils_1.toDate)(data.rateDate) ||
        (0, utils_1.toDate)(data.createdAt) ||
        (0, utils_1.toDate)(data.timestamp) ||
        (0, utils_1.toDate)(data.updatedAt));
}
function listingCrop(data) {
    return String(data.cropType || data.cropName || data.itemName || data.product || "").trim();
}
function trendKey(crop, province, district) {
    return `${normalizeTrendToken(crop)}|${normalizeTrendToken(province)}|${normalizeTrendToken(district)}`;
}
function matchesTrendFilter(crop, province, district, filters) {
    if (filters.crop && !normalizeTrendToken(crop).includes(filters.crop))
        return false;
    if (filters.province && !normalizeTrendToken(province).includes(filters.province))
        return false;
    if (filters.district && !normalizeTrendToken(district).includes(filters.district))
        return false;
    return true;
}
async function buildFallbackTrendMap(filters) {
    const now = Date.now();
    const oneDayMs = 24 * 60 * 60 * 1000;
    const currentStart = now - oneDayMs;
    const previousStart = now - (2 * oneDayMs);
    const trendMap = new Map();
    const listingById = new Map();
    const listingSnap = await db.collection("listings").orderBy("createdAt", "desc").limit(450).get();
    for (const doc of listingSnap.docs) {
        const data = (doc.data() || {});
        const crop = listingCrop(data);
        if (!crop)
            continue;
        const province = String(data.province || "").trim();
        const district = String(data.district || "").trim();
        if (!matchesTrendFilter(crop, province, district, filters))
            continue;
        const key = trendKey(crop, province, district);
        const bucket = trendMap.get(key) || {
            crop,
            province,
            district,
            currentRates: [],
            previousRates: [],
        };
        const ts = listingTimestamp(data)?.getTime();
        const rate = (0, utils_1.toNumber)(data.highestBid, (0, utils_1.toNumber)(data.price, 0));
        if (rate > 0 && ts) {
            if (ts >= currentStart && ts <= now)
                bucket.currentRates.push(rate);
            else if (ts >= previousStart && ts < currentStart)
                bucket.previousRates.push(rate);
        }
        trendMap.set(key, bucket);
        listingById.set(doc.id, { key, crop, province, district });
    }
    const bidsSnap = await db.collectionGroup("bids").limit(700).get();
    for (const doc of bidsSnap.docs) {
        const data = (doc.data() || {});
        const listingId = String(data.listingId || "").trim();
        if (!listingId)
            continue;
        const listing = listingById.get(listingId);
        if (!listing)
            continue;
        const ts = ((0, utils_1.toDate)(data.createdAt) || (0, utils_1.toDate)(data.timestamp))?.getTime();
        const bidRate = (0, utils_1.toNumber)(data.bidAmount, 0);
        if (!ts || bidRate <= 0)
            continue;
        const bucket = trendMap.get(listing.key);
        if (!bucket)
            continue;
        if (ts >= currentStart && ts <= now)
            bucket.currentRates.push(bidRate);
        else if (ts >= previousStart && ts < currentStart)
            bucket.previousRates.push(bidRate);
    }
    return trendMap;
}
async function buildMandiTrendsInternal(data) {
    const now = Date.now();
    const oneDayMs = 24 * 60 * 60 * 1000;
    const currentStart = now - oneDayMs;
    const previousStart = now - (2 * oneDayMs);
    const filters = {
        crop: normalizeTrendToken(data.crop || data.itemName || data.cropName),
        province: normalizeTrendToken(data.province),
        district: normalizeTrendToken(data.district),
    };
    const top = Math.min(40, Math.max(1, Math.round((0, utils_1.toNumber)(data.top, 12))));
    const trendMap = new Map();
    const mandiSnap = await db.collection("mandi_rates").orderBy("rateDate", "desc").limit(1800).get();
    for (const doc of mandiSnap.docs) {
        const item = (doc.data() || {});
        const crop = listingCrop(item);
        if (!crop)
            continue;
        const province = String(item.province || "").trim();
        const district = String(item.district || "").trim();
        if (!matchesTrendFilter(crop, province, district, filters))
            continue;
        const ts = listingTimestamp(item)?.getTime();
        if (!ts || ts < previousStart)
            continue;
        const rate = (0, utils_1.toNumber)(item.averagePrice, (0, utils_1.toNumber)(item.average, (0, utils_1.toNumber)(item.rate, 0)));
        if (rate <= 0)
            continue;
        const key = trendKey(crop, province, district);
        const bucket = trendMap.get(key) || {
            crop,
            province,
            district,
            currentRates: [],
            previousRates: [],
        };
        if (ts >= currentStart && ts <= now) {
            bucket.currentRates.push(rate);
        }
        else if (ts >= previousStart && ts < currentStart) {
            bucket.previousRates.push(rate);
        }
        trendMap.set(key, bucket);
    }
    if (trendMap.size === 0) {
        const fallback = await buildFallbackTrendMap(filters);
        for (const [key, bucket] of fallback.entries()) {
            trendMap.set(key, bucket);
        }
    }
    const trends = [];
    for (const bucket of trendMap.values()) {
        if (bucket.currentRates.length === 0)
            continue;
        let previousAverage = average(bucket.previousRates);
        if (previousAverage <= 0) {
            previousAverage = average(bucket.currentRates);
        }
        const currentAverage = average(bucket.currentRates);
        const changePercent = previousAverage > 0
            ? ((currentAverage - previousAverage) / previousAverage) * 100
            : 0;
        const trendDirection = toTrendDirection(changePercent);
        trends.push({
            crop: bucket.crop,
            province: bucket.province,
            district: bucket.district,
            trendDirection,
            priceChangePercent: Number(changePercent.toFixed(2)),
            marketAverage: Number(currentAverage.toFixed(2)),
            trendSummary: buildTrendSummary(bucket.crop, bucket.province, bucket.district, trendDirection, Number(changePercent.toFixed(2))),
        });
    }
    trends.sort((a, b) => Math.abs((0, utils_1.toNumber)(b.priceChangePercent, 0)) - Math.abs((0, utils_1.toNumber)(a.priceChangePercent, 0)));
    return trends.slice(0, top);
}
exports.getMandiTrendHttp = (0, https_1.onRequest)(AI_RUNTIME_OPTIONS, async (req, res) => {
    setCorsHeaders(res);
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ ok: false, error: "method-not-allowed" });
        return;
    }
    try {
        const trends = await buildMandiTrendsInternal(readRequestBody(req));
        res.status(200).json({
            ok: true,
            trends,
            generatedAt: new Date().toISOString(),
            sourceCollection: "mandi_rates",
        });
    }
    catch (error) {
        const message = error instanceof https_1.HttpsError ? error.message : "get-mandi-trend-failed";
        res.status(400).json({ ok: false, error: message });
    }
});
async function evaluateBidRiskInternal(authUid, data) {
    const listingId = String(data.listingId || "").trim();
    const buyerUid = String(data.buyerUid || authUid).trim();
    const bidRate = (0, utils_1.toNumber)(data.bidRate, 0);
    const quantity = (0, utils_1.toNumber)(data.quantity, 0);
    const unit = String(data.unit || "").trim();
    if (!listingId || bidRate <= 0 || quantity <= 0 || !unit) {
        throw new https_1.HttpsError("invalid-argument", "listingId, bidRate, quantity, unit required");
    }
    if (buyerUid !== authUid) {
        throw new https_1.HttpsError("permission-denied", "buyerUid must match auth uid");
    }
    await enforceAiThrottle({
        scope: "evaluateBidRisk_uid",
        key: buyerUid,
        limit: 80,
        windowSeconds: 3600,
    });
    await enforceAiThrottle({
        scope: "evaluateBidRisk_listing",
        key: listingId,
        limit: 120,
        windowSeconds: 3600,
    });
    const listingSnap = await db.collection("listings").doc(listingId).get();
    if (!listingSnap.exists) {
        throw new https_1.HttpsError("not-found", "listing-not-found");
    }
    const listing = (listingSnap.data() || {});
    const listingUnit = String(listing.unit || listing.unitType || "").trim();
    const listingProduct = String(listing.product || listing.cropName || listing.itemName || "").trim();
    const listingPrice = (0, utils_1.toNumber)(listing.price, 0);
    const tenMinutesAgo = firestore_2.Timestamp.fromDate(new Date(Date.now() - 10 * 60 * 1000));
    const recentBidsSnap = await db.collection("listings")
        .doc(listingId)
        .collection("bids")
        .where("timestamp", ">=", tenMinutesAgo)
        .orderBy("timestamp", "desc")
        .limit(30)
        .get();
    let score = 0;
    const flags = [];
    const recentRates = [];
    let buyerRecentCount = 0;
    for (const doc of recentBidsSnap.docs) {
        const data = doc.data();
        recentRates.push((0, utils_1.toNumber)(data.bidAmount, 0));
        if (String(data.buyerId || "") === buyerUid)
            buyerRecentCount += 1;
    }
    const highestRecent = recentRates.length > 0
        ? Math.max(...recentRates)
        : Math.max(0, (0, utils_1.toNumber)(listing.highestBid, listingPrice));
    if (highestRecent > 0 && bidRate > highestRecent * 1.35) {
        score += 35;
        flags.push("too_high_jump");
    }
    if (buyerRecentCount >= 5) {
        score += 25;
        flags.push("spam_bidding");
    }
    if (listingUnit && listingUnit.toLowerCase() !== unit.toLowerCase()) {
        score += 20;
        flags.push("mismatch_unit");
    }
    const buyerSnap = await db.collection("users").doc(buyerUid).get();
    const buyer = (buyerSnap.data() || {});
    const buyerCreatedAt = (0, utils_1.toDate)(buyer.createdAt);
    if (buyerCreatedAt && (Date.now() - buyerCreatedAt.getTime()) < (3 * 24 * 60 * 60 * 1000)) {
        score += 12;
        flags.push("new_account");
    }
    score = clampRisk(score);
    let bidRiskScore = score;
    let bidFlags = (0, utils_1.uniqueStrings)(flags);
    let bidAdviceEn = score >= 60
        ? "Bid looks unusual. You may continue, but review details carefully."
        : "Bid looks acceptable. Continue with normal caution.";
    let bidAdviceUrdu = score >= 60
        ? "یہ بولی غیر معمولی لگتی ہے، مگر آپ احتیاط سے جاری رکھ سکتے ہیں۔"
        : "یہ بولی مناسب لگتی ہے، معمول کی احتیاط کے ساتھ جاری رکھیں۔";
    const prompt = [
        "Return ONLY JSON with schema:",
        "{bidRiskScore:number,bidRiskLevel:'low|medium|high',bidAdviceUrdu:string,bidAdviceEn:string,bidFlags:string[],recommendedAction:'allow|warn|hold'}",
        "Keep advice short and calm. Default should be allow or warn. Use hold only for extreme risk.",
        JSON.stringify({
            listingId,
            listingProduct,
            listingPrice,
            listingUnit,
            buyerUid,
            bidRate,
            quantity,
            unit,
            highestRecent,
            buyerRecentCount,
            heuristicScore: score,
            heuristicFlags: bidFlags,
        }),
    ].join("\n");
    try {
        const raw = await callGeminiText({
            prompt,
            temperature: 0.1,
            responseMimeType: "application/json",
        });
        const parsed = JSON.parse(extractJsonBlock(raw));
        bidRiskScore = clampRisk((0, utils_1.toNumber)(parsed.bidRiskScore, bidRiskScore));
        bidFlags = sanitizeReasonList(parsed.bidFlags, "none");
        bidAdviceUrdu = String(parsed.bidAdviceUrdu || bidAdviceUrdu).trim() || bidAdviceUrdu;
        bidAdviceEn = String(parsed.bidAdviceEn || bidAdviceEn).trim() || bidAdviceEn;
    }
    catch (_) {
        // Keep deterministic fallback if AI is unavailable.
    }
    const bidRiskLevel = toRiskLevel(bidRiskScore);
    const recommendedAction = toBidAction(bidRiskScore);
    return {
        bidRiskScore,
        bidRiskLevel,
        bidAdviceUrdu,
        bidAdviceEn,
        bidFlags,
        recommendedAction,
        aiBidRiskScore: bidRiskScore,
        aiBidRiskLevel: bidRiskLevel,
        aiBidAdvice: bidAdviceEn,
        aiBidAdviceUrdu: bidAdviceUrdu,
        aiBidFlags: bidFlags,
        aiBidAction: recommendedAction,
    };
}
exports.evaluateBidRisk = (0, https_1.onCall)(AI_RUNTIME_OPTIONS, async (request) => {
    const authUid = request.auth?.uid;
    if (!authUid) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required");
    }
    const data = (request.data || {});
    return evaluateBidRiskInternal(authUid, data);
});
exports.evaluateBidRiskHttp = (0, https_1.onRequest)(AI_RUNTIME_OPTIONS, async (req, res) => {
    setCorsHeaders(res);
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ ok: false, error: "method-not-allowed" });
        return;
    }
    const uid = await getUidFromBearerToken(req);
    if (!uid) {
        res.status(401).json({ ok: false, error: "unauthenticated" });
        return;
    }
    try {
        const result = await evaluateBidRiskInternal(uid, readRequestBody(req));
        res.status(200).json({ ok: true, ...result });
    }
    catch (error) {
        const message = error instanceof https_1.HttpsError ? error.message : "evaluate-bid-risk-failed";
        res.status(400).json({ ok: false, error: message });
    }
});
async function applyWatchersDelta({ listingId, uid, delta, eventId, }) {
    const normalizedListingId = (listingId || "").trim();
    const normalizedUid = (uid || "").trim();
    if (!normalizedListingId || !normalizedUid || !eventId.trim())
        return;
    const markerRef = db.collection("_functionEvents").doc(`watchers_${eventId}`);
    const listingRef = db.collection("listings").doc(normalizedListingId);
    const watchRef = db
        .collection("users")
        .doc(normalizedUid)
        .collection("watchlist")
        .doc(normalizedListingId);
    await db.runTransaction(async (tx) => {
        const markerSnap = await tx.get(markerRef);
        if (markerSnap.exists) {
            return;
        }
        const listingSnap = await tx.get(listingRef);
        if (!listingSnap.exists) {
            tx.set(markerRef, {
                kind: "watchers_delta",
                listingId: normalizedListingId,
                uid: normalizedUid,
                delta,
                applied: false,
                reason: "listing_not_found",
                createdAt: firestore_2.FieldValue.serverTimestamp(),
            });
            return;
        }
        const listing = listingSnap.data();
        const saleType = String(listing.saleType || "").trim().toLowerCase();
        if (saleType !== "auction") {
            tx.set(markerRef, {
                kind: "watchers_delta",
                listingId: normalizedListingId,
                uid: normalizedUid,
                delta,
                applied: false,
                reason: "non_auction_listing",
                createdAt: firestore_2.FieldValue.serverTimestamp(),
            });
            return;
        }
        const sellerId = String(listing.sellerId || "").trim();
        if (sellerId && sellerId === normalizedUid) {
            tx.delete(watchRef);
            tx.set(markerRef, {
                kind: "watchers_delta",
                listingId: normalizedListingId,
                uid: normalizedUid,
                delta,
                applied: false,
                reason: "seller_cannot_watch_own_listing",
                createdAt: firestore_2.FieldValue.serverTimestamp(),
            });
            return;
        }
        const current = (0, utils_1.toNumber)(listing.watchersCount, 0);
        const next = Math.max(0, current + delta);
        tx.set(listingRef, {
            watchersCount: next,
            updatedAt: firestore_2.FieldValue.serverTimestamp(),
        }, { merge: true });
        tx.set(markerRef, {
            kind: "watchers_delta",
            listingId: normalizedListingId,
            uid: normalizedUid,
            delta,
            applied: true,
            nextCount: next,
            createdAt: firestore_2.FieldValue.serverTimestamp(),
        });
    });
}
exports.onWatchlistCreated = (0, firestore_1.onDocumentCreated)({ document: "users/{uid}/watchlist/{listingId}", region: "asia-south1" }, async (event) => {
    const uid = String(event.params.uid || "").trim();
    const listingId = String(event.params.listingId || "").trim();
    await applyWatchersDelta({
        listingId,
        uid,
        delta: 1,
        eventId: event.id,
    });
});
exports.onWatchlistDeleted = (0, firestore_1.onDocumentDeleted)({ document: "users/{uid}/watchlist/{listingId}", region: "asia-south1" }, async (event) => {
    const uid = String(event.params.uid || "").trim();
    const listingId = String(event.params.listingId || "").trim();
    await applyWatchersDelta({
        listingId,
        uid,
        delta: -1,
        eventId: event.id,
    });
});
exports.onListingCreated = (0, firestore_1.onDocumentCreated)({ document: "listings/{listingId}", region: "asia-south1" }, async (event) => {
    const listingId = event.params.listingId;
    const snap = event.data;
    if (!snap)
        return;
    const data = snap.data();
    const sellerId = (data.sellerId || "").toString();
    if (!sellerId)
        return;
    const userSnap = await db.collection("users").doc(sellerId).get();
    const userData = (userSnap.data() || {});
    const fraudInput = {
        sellerId,
        product: (data.product || "").toString(),
        mandiType: (data.mandiType || "").toString(),
        province: (data.province || "").toString(),
        district: (data.district || "").toString(),
        village: (data.village || "").toString(),
        description: (data.description || "").toString(),
        price: (0, utils_1.toNumber)(data.price, 0),
        quantity: (0, utils_1.toNumber)(data.quantity, 0),
        unitType: (data.unitType || "").toString(),
        verificationGeo: {
            lat: (0, utils_1.toNumber)(data.verificationGeo?.lat, 0),
            lng: (0, utils_1.toNumber)(data.verificationGeo?.lng, 0),
        },
        verificationCapturedAt: ((0, utils_1.toDate)(data.verificationCapturedAt) || new Date()).toISOString(),
    };
    const userFraudView = {
        trustScore: typeof userData.trustScore === "number"
            ? userData.trustScore
            : undefined,
        strikes: (0, utils_1.toNumber)(userData.strikes, 0),
        listingsToday: (0, utils_1.toNumber)(userData.listingsToday, 0),
        isBanned: userData.isBanned === true,
        lastKnownGeo: userData.lastKnownGeo &&
            typeof userData.lastKnownGeo.lat === "number" &&
            typeof userData.lastKnownGeo.lng === "number"
            ? {
                lat: userData.lastKnownGeo.lat,
                lng: userData.lastKnownGeo.lng,
            }
            : undefined,
    };
    const fraud = await (0, fraud_1.computeFraudScore)({
        db,
        listing: fraudInput,
        user: userFraudView,
        highFrequency: (0, utils_1.toNumber)(userData.listingsToday, 0) >= 5,
    });
    const imageUrls = Array.isArray(data.imageUrls)
        ? data.imageUrls.filter((v) => typeof v === "string")
        : [];
    const imageHashes = [];
    for (const url of imageUrls) {
        const storagePath = (0, utils_1.storagePathFromUrl)(url);
        if (!storagePath)
            continue;
        try {
            const hash = await (0, fraud_1.computeImageHashFromStoragePath)(storagePath);
            imageHashes.push(hash);
        }
        catch (_) {
            fraud.fraudFlags.push("image_hash_failed");
        }
    }
    let duplicateSameSeller = false;
    let duplicateCrossSeller = false;
    if (imageHashes.length > 0) {
        const thirtyDaysAgo = firestore_2.Timestamp.fromDate(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000));
        const sellerRecentSnap = await db
            .collection("listings")
            .where("sellerId", "==", sellerId)
            .where("createdAt", ">=", thirtyDaysAgo)
            .get();
        for (const doc of sellerRecentSnap.docs) {
            if (doc.id === listingId)
                continue;
            const h = doc.get("imageHashes");
            if (!Array.isArray(h))
                continue;
            const overlap = h.some((v) => imageHashes.includes(String(v)));
            if (overlap) {
                duplicateSameSeller = true;
                break;
            }
        }
        for (const hash of imageHashes) {
            const dupSnap = await db
                .collection("listings")
                .where("imageHashes", "array-contains", hash)
                .limit(25)
                .get();
            for (const doc of dupSnap.docs) {
                if (doc.id === listingId)
                    continue;
                const otherSeller = String(doc.get("sellerId") || "");
                if (otherSeller && otherSeller !== sellerId) {
                    duplicateCrossSeller = true;
                    break;
                }
            }
            if (duplicateCrossSeller)
                break;
        }
    }
    let riskScore = fraud.riskScore;
    const flags = [...fraud.fraudFlags];
    if (duplicateSameSeller) {
        riskScore += 15;
        flags.push("reused_media_same_seller");
    }
    if (duplicateCrossSeller) {
        riskScore += 30;
        flags.push("stolen_media");
    }
    riskScore = Math.max(0, Math.min(100, riskScore));
    const status = riskScore >= 70 ? "review" : String(data.status || "pending");
    await snap.ref.set({
        riskScore,
        fraudFlags: (0, utils_1.uniqueStrings)(flags),
        imageHashes: (0, utils_1.uniqueStrings)(imageHashes),
        status,
        updatedAt: firestore_2.FieldValue.serverTimestamp(),
    }, { merge: true });
    await db.collection("moderationQueue").doc(listingId).set({
        listingId,
        sellerId,
        status,
        reasons: (0, utils_1.uniqueStrings)(flags),
        riskScore,
        createdAt: firestore_2.FieldValue.serverTimestamp(),
    }, { merge: true });
    // Populate suggestion-only AI fields asynchronously. Never auto-approves/rejects.
    try {
        await evaluateListingRiskDocument(listingId);
    }
    catch (_) {
        // Ignore AI failure to avoid breaking listing flow.
    }
});
async function markInvalidMedia(listingId, reason) {
    const ref = db.collection("listings").doc(listingId);
    const snap = await ref.get();
    if (!snap.exists)
        return;
    const existingFlags = Array.isArray(snap.get("fraudFlags"))
        ? snap.get("fraudFlags")
        : [];
    const existingRisk = (0, utils_1.toNumber)(snap.get("riskScore"), 0);
    const updatedFlags = (0, utils_1.uniqueStrings)([...existingFlags, "invalid_media", reason]);
    const updatedRisk = Math.min(100, existingRisk + 25);
    await ref.set({
        fraudFlags: updatedFlags,
        riskScore: updatedRisk,
        status: updatedRisk >= 70 ? "review" : snap.get("status") || "pending",
        updatedAt: firestore_2.FieldValue.serverTimestamp(),
    }, { merge: true });
}
exports.onListingMediaFinalize = (0, storage_1.onObjectFinalized)({ region: "asia-south1", bucket: "digital-arhat.firebasestorage.app" }, async (event) => {
    const object = event.data;
    const filePath = object.name || "";
    if (!filePath.startsWith("listings/"))
        return;
    const parts = filePath.split("/");
    if (parts.length < 3)
        return;
    const listingId = parts[1];
    const mediaType = parts[2];
    const contentType = (object.contentType || "").toLowerCase();
    const sizeBytes = Number(object.size || 0);
    const bucketName = object.bucket;
    const file = getAdminApp().storage().bucket(bucketName).file(filePath);
    let invalid = false;
    const reasons = [];
    if (mediaType === "images") {
        const allowed = contentType === "image/jpeg" || contentType === "image/png";
        if (!allowed) {
            invalid = true;
            reasons.push("invalid_image_content_type");
        }
        if (sizeBytes > 2 * 1024 * 1024) {
            invalid = true;
            reasons.push("image_too_large");
        }
    }
    if (mediaType === "video.mp4" || filePath.endsWith("/video.mp4")) {
        if (contentType !== "video/mp4") {
            invalid = true;
            reasons.push("invalid_video_content_type");
        }
        if (sizeBytes > 10 * 1024 * 1024) {
            invalid = true;
            reasons.push("video_too_large");
        }
    }
    if (invalid) {
        try {
            await file.delete({ ignoreNotFound: true });
        }
        catch (_) {
            // ignore delete errors
        }
        await markInvalidMedia(listingId, reasons.join("|"));
    }
});
console.log("FUNCTIONS EXPORTS READY");
