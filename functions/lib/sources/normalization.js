"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.normalizeLocationToken = normalizeLocationToken;
exports.normalizeCommodityName = normalizeCommodityName;
exports.toUrduCommodityLabel = toUrduCommodityLabel;
exports.normalizeUnit = normalizeUnit;
exports.normalizePriceText = normalizePriceText;
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
    // Urdu city/district names
    "لاہور": "Lahore",
    "کراچی": "Karachi",
    "اسلام آباد": "Islamabad",
    "راولپنڈی": "Rawalpindi",
    "گوجرانوالہ": "Gujranwala",
    "گوجرانوالا": "Gujranwala",
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
    // Roman Urdu / common misspellings
    "faislabad": "Faisalabad",
    "faisalbad": "Faisalabad",
    "faisal abad": "Faisalabad",
    "dg khan": "D.G. Khan",
    "d.g. khan": "D.G. Khan",
    "dera ghazi khan": "D.G. Khan",
    "deraghazikhan": "D.G. Khan",
    // New Punjab districts for FS&CPD coverage
    "sialkot": "Sialkot",
    "sheikhupura": "Sheikhupura",
    "kasur": "Kasur",
    "nankana sahib": "Nankana Sahib",
    "mandi bahauddin": "Mandi Bahauddin",
    "hafizabad": "Hafizabad",
    "chakwal": "Chakwal",
    "attock": "Attock",
    "khushab": "Khushab",
    "pakpattan": "Pakpattan",
    "toba tek singh": "Toba Tek Singh",
    "tobateksingh": "Toba Tek Singh",
    "muzaffargarh": "Muzaffargarh",
    "layyah": "Layyah",
    "rajanpur": "Rajanpur",
    "rahim yar khan": "Rahim Yar Khan",
    "rahimyarkhan": "Rahim Yar Khan",
};
const CANONICAL_COMMODITY_IDS = new Set([
    "wheat",
    "rice",
    "basmati_rice",
    "irri_rice",
    "paddy",
    "maize",
    "sugar",
    "potato",
    "onion",
    "tomato",
    "banana",
    "eggs",
    "garlic",
    "ginger",
    "chilli",
    "capsicum",
    "peas",
    "carrot",
    "radish",
    "turnip",
    "spinach",
    "okra",
    "cauliflower",
    "cabbage",
    "mango",
    "apple",
    "orange",
    "guava",
    "grapes",
    "watermelon",
    "melon",
    "pomegranate",
    "dates",
    "chickpea",
    "lentil",
    "mung_bean",
    "black_gram",
    "sugarcane",
    "cotton",
    "dap",
    "urea",
    "goat",
    "cow",
]);
const COMMODITY_ALIAS_TO_EN = {
    // Urdu
    "گندم": "Wheat",
    "چاول": "Rice",
    "چینی": "Sugar",
    "پیاز": "Onion",
    "آلو": "Potato",
    "ٹماٹر": "Tomato",
    "مکئی": "Maize",
    "کارن": "Maize",
    "بھنڈی": "Okra",
    "کینو": "Kinnow",
    "کیلا": "Banana",
    "انڈا": "Egg",
    "انڈے": "Eggs",
    "لہسن": "Garlic",
    "ادرک": "Ginger",
    "مرچ": "Chilli",
    "مٹر": "Peas",
    "گاجر": "Carrot",
    "مولی": "Radish",
    "پالک": "Spinach",
    "آم": "Mango",
    "سیب": "Apple",
    "امرود": "Guava",
    "مالٹا": "Orange",
    "چنا": "Chickpea",
    "مسور": "Lentil",
    "مونگ": "Mung Bean",
    // Roman Urdu / field variants
    "maize": "Maize",
    "corn": "Maize",
    "aaloo": "Potato",
    "aloo": "Potato",
    "pyaz": "Onion",
    "tamatar": "Tomato",
    "chaawal": "Rice",
    "chawal": "Rice",
    "gandum": "Wheat",
    "kinnow": "Kinnow",
    "kinow": "Kinnow",
    "kela": "Banana",
    "banana": "Banana",
    "anda": "Egg",
    "anday": "Eggs",
    "lehsan": "Garlic",
    "adrak": "Ginger",
    "mirch": "Chilli",
    "shimla mirch": "Capsicum",
    "capsicum": "Capsicum",
    "bhindi": "Okra",
    "okra": "Okra",
    "tinda": "Round Gourd",
    "karela": "Bitter Gourd",
    "lauki": "Bottle Gourd",
    "tori": "Ridge Gourd",
    "baingan": "Brinjal",
    "matar": "Peas",
    "gajar": "Carrot",
    "mooli": "Radish",
    "shalgam": "Turnip",
    "palak": "Spinach",
    "gobhi": "Cauliflower",
    "band gobhi": "Cabbage",
    "aam": "Mango",
    "seb": "Apple",
    "amrood": "Guava",
    "angoor": "Grapes",
    "tarbuz": "Watermelon",
    "kharboza": "Melon",
    "anaar": "Pomegranate",
    "khajoor": "Dates",
    "chana": "Chickpea",
    "moong": "Mung Bean",
    "mung": "Mung Bean",
    "masoor": "Lentil",
    "urad": "Black Gram",
    "basmati": "Basmati Rice",
    "irri": "Irri Rice",
    "dhan": "Paddy",
    "paddy": "Paddy",
    "ganna": "Sugarcane",
    "sugarcane": "Sugarcane",
    "kapas": "Cotton",
    "cotton": "Cotton",
    "dap": "DAP",
    "urea": "Urea",
    "bakra": "Goat",
    "goat": "Goat",
    "gai": "Cow",
    "cow": "Cow",
};
const COMMODITY_EN_TO_UR = {
    wheat: "گندم",
    rice: "چاول",
    "basmati rice": "بسمتی چاول",
    "irri rice": "عرفی چاول",
    paddy: "دھان",
    sugar: "چینی",
    onion: "پیاز",
    potato: "آلو",
    tomato: "ٹماٹر",
    maize: "مکئی",
    okra: "بھنڈی",
    kinnow: "کینو",
    mango: "آم",
    banana: "کیلا",
    apple: "سیب",
    orange: "مالٹا",
    guava: "امرود",
    grapes: "انگور",
    watermelon: "تربوز",
    melon: "خربوزہ",
    pomegranate: "انار",
    dates: "کھجور",
    garlic: "لہسن",
    ginger: "ادرک",
    chilli: "مرچ",
    capsicum: "شملہ مرچ",
    spinach: "پالک",
    carrot: "گاجر",
    radish: "مولی",
    turnip: "شلجم",
    peas: "مٹر",
    cauliflower: "پھول گوبھی",
    cabbage: "بند گوبھی",
    brinjal: "بینگن",
    "bitter gourd": "کریلا",
    "bottle gourd": "لوکی",
    chickpea: "چنا",
    lentil: "مسور",
    "mung bean": "مونگ",
    sugarcane: "گنا",
    cotton: "کپاس",
    egg: "انڈا",
    eggs: "انڈے",
    goat: "بکرا",
    cow: "گائے",
    dap: "ڈی اے پی",
    urea: "یوریا",
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
        .replace(/\./g, " ")
        .toLowerCase()
        .replace(/\s+/g, " ")
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
        return "unknown";
    const cleanInput = input
        .toLowerCase()
        .replace(/<[^>]+>/g, " ")
        .replace(/[^\p{L}\p{N}\s]/gu, " ")
        .replace(/\s+/g, " ")
        .trim();
    if (!cleanInput)
        return "unknown";
    const mapped = (COMMODITY_ALIAS_TO_EN[input] ??
        COMMODITY_ALIAS_TO_EN[cleanInput] ??
        cleanInput)
        .toLowerCase()
        .replace(/\s+/g, " ")
        .trim();
    const normalized = mapped
        .replace(/\begg\b/g, "eggs")
        .replace(/\s+/g, "_")
        .replace(/[^a-z_]/g, "")
        .replace(/_+/g, "_")
        .replace(/^_+|_+$/g, "");
    return CANONICAL_COMMODITY_IDS.has(normalized) ? normalized : "unknown";
}
function toUrduCommodityLabel(english) {
    const key = text(english).toLowerCase();
    return COMMODITY_EN_TO_UR[key] ?? "";
}
function normalizeUnit(value) {
    const raw = text(value).toLowerCase();
    if (!raw)
        return "PKR/100kg";
    if (raw.includes("mon") || raw.includes("maund") || raw.includes("mann") || raw.includes("40 kg") || raw.match(/\b40kg\b/))
        return "PKR/40kg";
    if (raw.includes("100") && raw.includes("kg"))
        return "PKR/100kg";
    if (raw.includes("40") && raw.includes("kg"))
        return "PKR/40kg";
    if (raw.includes("50") && raw.includes("kg"))
        return "PKR/50kg";
    if (raw.includes("dozen") || raw.includes("doz"))
        return "PKR/dozen";
    if (raw.includes("tray"))
        return "PKR/tray";
    if (raw.includes("crate") || raw.includes("peti"))
        return "PKR/crate";
    if (raw.includes("head"))
        return "PKR/head";
    if (raw.includes("bag"))
        return "PKR/bag";
    if (raw === "kg" || raw === "per kg" || raw === "perkg" || raw === "pkr/kg" || raw === "rs/kg")
        return "PKR/kg";
    if (raw.includes("kg"))
        return "PKR/kg";
    return raw.toUpperCase();
}
function normalizePriceText(value) {
    const raw = text(value);
    if (!raw)
        return "";
    return raw
        .toLowerCase()
        .replace(/rs\.?|pkr|rupees?/g, "")
        .replace(/,/g, "")
        .replace(/[^0-9.\-]/g, "")
        .trim();
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
    const normalizedPriceText = normalizePriceText(row.metadata?.rawPriceText ?? row.metadata?.priceText ?? String(row.price));
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
            normalizedPriceText,
        },
    };
}
