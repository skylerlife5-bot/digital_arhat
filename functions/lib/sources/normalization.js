"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeLocationToken = normalizeLocationToken;
exports.normalizeCommodityName = normalizeCommodityName;
exports.toUrduCommodityLabel = toUrduCommodityLabel;
exports.normalizeUnit = normalizeUnit;
exports.normalizeTrend = normalizeTrend;
exports.freshnessStatus = freshnessStatus;
exports.deterministicIdForRow = deterministicIdForRow;
exports.toUnifiedBase = toUnifiedBase;
function text(value, fallback = "") {
    const out = String(value ?? "").trim();
    return out || fallback;
}
function slug(input) {
    return input
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "_")
        .replace(/^_+|_+$/g, "");
}
const LOCATION_ALIAS_TO_EN = {
    "لاہور": "Lahore",
    "کراچی": "Karachi",
    "اسلام آباد": "Islamabad",
    "راولپنڈی": "Rawalpindi",
    "گوجرانوالہ": "Gujranwala",
    "ڈیرہ غازی خان": "D.G. Khan",
    "ڈی جی خان": "D.G. Khan",
    "ڈی۔جی۔خان": "D.G. Khan",
    "حیدرآباد": "Hyderabad",
    "فیصل آباد": "Faisalabad",
    "ملتان": "Multan",
    "رحیم یار خان": "Rahim Yar Khan",
    "وہاڑی": "Vehari",
    "ساہیوال": "Sahiwal",
    "اوکاڑہ": "Okara",
    "گجرات": "Gujrat",
    "سرگودھا": "Sargodha",
    "چنیوٹ": "Chiniot",
    "جہلم": "Jhelum",
    "میانوالی": "Mianwali",
    "بھکر": "Bhakkar",
    "خانیوال": "Khanewal",
    "لودھراں": "Lodhran",
    "ٹوبہ ٹیک سنگھ": "Toba Tek Singh",
    "کبیروالا": "Kabirwala",
    "چیچہ وطنی": "Chichawatni",
    "مظفرگڑھ": "Muzaffargarh",
    "لیہ": "Layyah",
    "بہاولپور": "Bahawalpur",
    "faislabad": "Faisalabad",
    "faisalbad": "Faisalabad",
    "faisal abad": "Faisalabad",
    "dg khan": "D.G. Khan",
    "d.g. khan": "D.G. Khan",
    "dera ghazi khan": "D.G. Khan",
};
const COMMODITY_ALIAS_TO_EN = {
    "گندم": "Wheat",
    "چاول": "Rice",
    "چینی": "Sugar",
    "پیاز": "Onion",
    "آلو": "Potato",
    "ٹماٹر": "Tomato",
    "مکئی": "Maize",
    "کارن": "Maize",
    "maize": "Maize",
    "corn": "Maize",
    "بھنڈی": "Okra",
    "okra": "Okra",
    "کینو": "Kinnow",
    "kinnow": "Kinnow",
    "aaloo": "Potato",
    "pyaz": "Onion",
    "tamatar": "Tomato",
    "chaawal": "Rice",
    "gandum": "Wheat",
};
const COMMODITY_EN_TO_UR = {
    wheat: "گندم",
    rice: "چاول",
    sugar: "چینی",
    onion: "پیاز",
    potato: "آلو",
    tomato: "ٹماٹر",
    maize: "مکئی",
    okra: "بھِنڈی",
    kinnow: "کینو",
    mango: "آم",
    banana: "کیلا",
};
const CATEGORY_ALIAS_TO_EN = {
    crops: "crops",
    crop: "crops",
    "غلہ": "crops",
    fruits: "fruits",
    fruit: "fruits",
    "پھل": "fruits",
    vegetables: "vegetables",
    vegetable: "vegetables",
    "سبزی": "vegetables",
    essentials: "essentials",
    essential: "essentials",
    grocery: "essentials",
};
const SUBCATEGORY_ALIAS_TO_EN = {
    official_list: "official_list",
    "official list": "official_list",
    other: "other",
};
function canonicalLocation(value) {
    const raw = text(value);
    if (!raw)
        return "";
    const mapped = LOCATION_ALIAS_TO_EN[raw] ?? LOCATION_ALIAS_TO_EN[raw.toLowerCase()] ?? raw;
    return mapped
        .replace(/\s+district$/i, "")
        .replace(/\s+city$/i, "")
        .replace(/\s+mandi$/i, "")
        .trim();
}
function normalizeCategoryName(value) {
    const raw = text(value).toLowerCase();
    if (!raw)
        return "crops";
    return CATEGORY_ALIAS_TO_EN[raw] ?? raw.replace(/\s+/g, "_");
}
function normalizeSubcategoryName(value) {
    const raw = text(value).toLowerCase();
    if (!raw)
        return "other";
    return SUBCATEGORY_ALIAS_TO_EN[raw] ?? raw.replace(/\s+/g, "_");
}
function normalizeLocationToken(value) {
    const mapped = canonicalLocation(value);
    if (!mapped)
        return "";
    return mapped.toLowerCase().replace(/\s+/g, " ").trim();
}
function normalizeCommodityName(value) {
    const input = text(value);
    if (!input)
        return "Unknown";
    const mapped = COMMODITY_ALIAS_TO_EN[input] ?? input;
    return mapped
        .split(/\s+/)
        .filter((item) => item)
        .map((part) => part[0].toUpperCase() + part.slice(1).toLowerCase())
        .join(" ");
}
function toUrduCommodityLabel(english) {
    const key = text(english).toLowerCase();
    return COMMODITY_EN_TO_UR[key] ?? "";
}
function normalizeUnit(value) {
    const raw = text(value).toLowerCase();
    if (!raw)
        return "PKR/100kg";
    if (raw.includes("mon") || raw.includes("maund") || raw.includes("40 kg"))
        return "PKR/40kg";
    if (raw.includes("100") && raw.includes("kg"))
        return "PKR/100kg";
    if (raw.includes("40") && raw.includes("kg"))
        return "PKR/40kg";
    if (raw.includes("50") && raw.includes("kg"))
        return "PKR/50kg";
    if (raw.includes("kg"))
        return "PKR/kg";
    if (raw.includes("doz") || raw.includes("dozen"))
        return "PKR/dozen";
    if (raw.includes("head"))
        return "PKR/head";
    return raw.toUpperCase();
}
function normalizeTrend(price, previous, trend) {
    const raw = text(trend).toLowerCase();
    if (raw === "up" || raw.includes("rise"))
        return "up";
    if (raw === "down" || raw.includes("fall"))
        return "down";
    if (previous != null && previous > 0) {
        if (price > previous)
            return "up";
        if (price < previous)
            return "down";
    }
    return "same";
}
function freshnessStatus(lastUpdated, now) {
    const ageMs = now.getTime() - lastUpdated.getTime();
    if (ageMs <= 30 * 60 * 1000)
        return "live";
    if (ageMs <= 6 * 60 * 60 * 1000)
        return "recent";
    if (ageMs <= 24 * 60 * 60 * 1000)
        return "aging";
    return "stale";
}
function deterministicIdForRow(row) {
    const day = row.lastUpdated.toISOString().slice(0, 10);
    const sourceKey = slug(row.sourceId);
    const commodityKey = slug(normalizeCommodityName(row.commodityName));
    const mandiKey = slug(row.mandiName || row.city);
    const cityKey = slug(row.city);
    const ref = String(row.metadata?.commodityRefId ?? row.metadata?.commodityId ?? "").trim();
    const refKey = ref ? slug(ref) : "";
    return [sourceKey, commodityKey, refKey, mandiKey, cityKey, day].filter((item) => item).join("_");
}
function toUnifiedBase(row, now) {
    const commodityName = normalizeCommodityName(row.commodityName);
    const unit = normalizeUnit(row.unit ?? "PKR/100kg");
    const previousPrice = row.previousPrice ?? null;
    const trend = normalizeTrend(row.price, previousPrice, row.trend ?? "same");
    const city = canonicalLocation(text(row.city, row.mandiName));
    const district = canonicalLocation(text(row.district, city));
    const province = canonicalLocation(text(row.province, "Punjab"));
    const mandiName = canonicalLocation(text(row.mandiName, city));
    const categoryName = normalizeCategoryName(row.categoryName ?? "crops");
    const subCategoryName = normalizeSubcategoryName(row.subCategoryName ?? "other");
    return {
        id: deterministicIdForRow(row),
        commodityName,
        commodityNameUr: text(row.commodityNameUr) || toUrduCommodityLabel(commodityName),
        categoryName,
        subCategoryName,
        mandiName,
        city,
        district,
        province,
        latitude: row.latitude ?? null,
        longitude: row.longitude ?? null,
        price: row.price,
        previousPrice,
        minPrice: row.minPrice ?? null,
        maxPrice: row.maxPrice ?? null,
        unit,
        currency: text(row.currency, "PKR"),
        trend,
        source: row.sourceName,
        sourceId: row.sourceId,
        sourceType: row.sourceType,
        lastUpdated: row.lastUpdated,
        syncedAt: now,
        freshnessStatus: freshnessStatus(row.lastUpdated, now),
        confidenceScore: 0,
        confidenceReason: "pending",
        verificationStatus: "Needs Review",
        contributorType: "official",
        isNearby: false,
        isAiCleaned: false,
        metadata: {
            ...(row.metadata ?? {}),
            cityNorm: normalizeLocationToken(city),
            districtNorm: normalizeLocationToken(district),
            provinceNorm: normalizeLocationToken(province),
            mandiNorm: normalizeLocationToken(mandiName),
            categoryNorm: categoryName,
            subCategoryNorm: subCategoryName,
            commodityNorm: normalizeCommodityName(commodityName).toLowerCase(),
            unitNorm: unit.toLowerCase(),
        },
    };
}
