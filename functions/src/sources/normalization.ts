import {RawSourceRow, UnifiedMandiRate} from "./types";

function text(value: unknown, fallback = ""): string {
  const out = String(value ?? "").trim();
  return out || fallback;
}

function slug(input: string): string {
  return input
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

const LOCATION_ALIAS_TO_EN: Record<string, string> = {
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

const CANONICAL_COMMODITY_IDS = new Set<string>([
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
  // Meats
  "live_chicken",
  "chicken_meat",
  "chicken",
  "beef",
  "mutton",
  // Daily essentials
  "flour",
  "milk",
  "cooking_oil",
  "ghee",
  // Extra vegetables
  "cauliflower",
  "cabbage",
  "carrot",
  "spinach",
  "okra",
  "ginger",
  "peas",
  // Extra fruits
  "guava",
  "grapes",
  "pomegranate",
  // Extra pulses
  "mash",
  "black_gram",
]);

const COMMODITY_ALIAS_TO_EN: Record<string, string> = {
  // Urdu
  "گندم": "Wheat",
  "گندم دانہ": "Wheat",
  "چاول": "Rice",
  "چاول باسمتی": "Basmati Rice",
  "چاول اری": "Irri Rice",
  "چینی": "Sugar",
  // Meats
  "live chicken": "Live Chicken",
  "chicken live": "Live Chicken",
  "poultry live": "Live Chicken",
  "live poultry": "Live Chicken",
  "broiler": "Live Chicken",
  "broiler live": "Live Chicken",
  "live_chicken": "Live Chicken",
  "zinda murgi": "Live Chicken",
  "زندہ مرغی": "Live Chicken",
  "مرغی زندہ": "Live Chicken",
  "murgi": "Chicken",
  "مرغی": "Chicken",
  "chicken meat": "Chicken",
  "broiler meat": "Chicken",
  "murghi gosht": "Chicken",
  "مرغی گوشت": "Chicken",
  "beef": "Beef",
  "بڑا گوشت": "Beef",
  "bada gosht": "Beef",
  "mutton": "Mutton",
  "chota gosht": "Mutton",
  "چھوٹا گوشت": "Mutton",
  "bakra gosht": "Mutton",
  // Daily essentials
  "flour": "Flour",
  "atta": "Flour",
  "آٹا": "Flour",
  "wheat flour": "Flour",
  "milk": "Milk",
  "doodh": "Milk",
  "دودھ": "Milk",
  "cooking oil": "Cooking Oil",
  "cooking oils": "Cooking Oil",
  "sunflower oil": "Cooking Oil",
  "edible oil": "Cooking Oil",
  "vegetable oil": "Cooking Oil",
  "refined oil": "Cooking Oil",
  "تیل": "Cooking Oil",
  "ghee": "Ghee",
  "desi ghee": "Ghee",
  "گھی": "Ghee",
  "dalda": "Ghee",
  "پیاز": "Onion",
  "آلو": "Potato",
  "آلو نئی": "Potato",
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
  "سبز مٹر": "Peas",
  "گاجر": "Carrot",
  "مولی": "Radish",
  "پالک": "Spinach",
  "آم": "Mango",
  "سیب": "Apple",
  "امرود": "Guava",
  "انگور": "Grapes",
  "انار": "Pomegranate",
  "مالٹا": "Orange",
  "چنا": "Chickpea",
  "مسور": "Lentil",
  "مونگ": "Mung Bean",
  // Roman Urdu / field variants
  "maize": "Maize",
  "corn": "Maize",
  "aaloo": "Potato",
  "aloo": "Potato",
  "potato": "Potato",
  "potatoes": "Potato",
  "pyaz": "Onion",
  "onion": "Onion",
  "onions": "Onion",
  "tamatar": "Tomato",
  "tomato": "Tomato",
  "tomatoes": "Tomato",
  "chaawal": "Rice",
  "chawal": "Rice",
  "rice": "Rice",
  "gandum": "Wheat",
  "wheat": "Wheat",
  "kinnow": "Kinnow",
  "kinow": "Kinnow",
  "kela": "Banana",
  "banana": "Banana",
  "anda": "Egg",
  "anday": "Eggs",
  "lehsan": "Garlic",
  "adrak": "Ginger",
  "mirch": "Chilli",
  "chilli": "Chilli",
  "chilies": "Chilli",
  "chillies": "Chilli",
  "chili": "Chilli",
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
  "phool gobhi": "Cauliflower",
  "cauliflower": "Cauliflower",
  "band gobhi": "Cabbage",
  "cabbage": "Cabbage",
  "aam": "Mango",
  "mango": "Mango",
  "seb": "Apple",
  "apple": "Apple",
  "amrood": "Guava",
  "guava": "Guava",
  "angoor": "Grapes",
  "grapes": "Grapes",
  "tarbuz": "Watermelon",
  "kharboza": "Melon",
  "anaar": "Pomegranate",
  "pomegranate": "Pomegranate",
  "khajoor": "Dates",
  "chana": "Chickpea",
  "moong": "Mung Bean",
  "mung": "Mung Bean",
  "masoor": "Lentil",
  "urad": "Black Gram",
  "basmati": "Basmati Rice",
  "basmati rice": "Basmati Rice",
  "irri": "Irri Rice",
  "irri rice": "Irri Rice",
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

const COMMODITY_FUZZY_KEYWORDS: Array<{id: string; keywords: string[]}> = [
  {id: "wheat", keywords: ["wheat", "gandum", "gandam", "گندم"]},
  {id: "basmati_rice", keywords: ["basmati", "باسمتی"]},
  {id: "irri_rice", keywords: ["irri", "اری"]},
  {id: "rice", keywords: ["rice", "chawal", "chaawal", "چاول"]},
  {id: "sugar", keywords: ["sugar", "cheeni", "چینی"]},
  {id: "flour", keywords: ["flour", "atta", "wheat flour", "آٹا"]},
  {id: "onion", keywords: ["onion", "onions", "pyaz", "پیاز"]},
  {id: "potato", keywords: ["potato", "potatoes", "aloo", "aaloo", "آلو"]},
  {id: "tomato", keywords: ["tomato", "tomatoes", "tamatar", "ٹماٹر"]},
  {id: "garlic", keywords: ["garlic", "lehsan", "لہسن"]},
  {id: "ginger", keywords: ["ginger", "adrak", "ادرک"]},
  {id: "chilli", keywords: ["chilli", "chilies", "chillies", "chili", "mirch", "مرچ"]},
  {id: "capsicum", keywords: ["capsicum", "shimla mirch", "شملہ مرچ"]},
  {id: "peas", keywords: ["peas", "matar", "مٹر"]},
  {id: "carrot", keywords: ["carrot", "carrots", "gajar", "گاجر"]},
  {id: "spinach", keywords: ["spinach", "palak", "پالک"]},
  {id: "okra", keywords: ["okra", "bhindi", "ladyfinger", "lady finger", "بھنڈی"]},
  {id: "cauliflower", keywords: ["cauliflower", "phool gobhi", "gobhi phool", "پھول گوبھی"]},
  {id: "cabbage", keywords: ["cabbage", "band gobhi", "بند گوبھی"]},
  {id: "apple", keywords: ["apple", "seb", "سیب"]},
  {id: "banana", keywords: ["banana", "kela", "کیلا"]},
  {id: "mango", keywords: ["mango", "aam", "آم"]},
  {id: "orange", keywords: ["orange", "kinnow", "kino", "مالٹا", "کینو"]},
  {id: "guava", keywords: ["guava", "amrood", "امرود"]},
  {id: "grapes", keywords: ["grape", "grapes", "angoor", "انگور"]},
  {id: "pomegranate", keywords: ["pomegranate", "anar", "anaar", "انار"]},
  {id: "lentil", keywords: ["lentil", "masoor", "مسور"]},
  {id: "chickpea", keywords: ["chickpea", "gram", "chana", "چنا"]},
  {id: "mung_bean", keywords: ["mung", "moong", "mung bean", "moong dal", "مونگ"]},
  {id: "mash", keywords: ["mash", "urad", "black gram", "ماش"]},
  {id: "live_chicken", keywords: ["live chicken", "chicken live", "poultry live", "live poultry", "broiler", "zinda murgi", "زندہ مرغی"]},
  {id: "chicken_meat", keywords: ["chicken meat", "murghi gosht", "مرغی گوشت", "dressed chicken"]},
  {id: "beef", keywords: ["beef", "bada gosht", "بڑا گوشت"]},
  {id: "mutton", keywords: ["mutton", "chota gosht", "bakra gosht", "چھوٹا گوشت"]},
  {id: "eggs", keywords: ["egg", "eggs", "anda", "anday", "انڈا", "انڈے"]},
  {id: "milk", keywords: ["milk", "doodh", "دودھ"]},
  {id: "cooking_oil", keywords: ["cooking oil", "edible oil", "vegetable oil", "refined oil", "تیل"]},
  {id: "ghee", keywords: ["ghee", "desi ghee", "dalda", "گھی"]},
];

function normalizeCommodityLookupText(input: string): string {
  return input
    .toLowerCase()
    .replace(/<[^>]+>/g, " ")
    .replace(/[\u2010-\u2015]/g, " ")
    .replace(/[-_/\\]+/g, " ")
    .replace(/[\u064b-\u065f\u0670]/g, "")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\b(tomatoes|potatoes|onions|chilies|chillies|carrots|grapes)\b/g, (word: string) => {
      if (word === "tomatoes") return "tomato";
      if (word === "potatoes") return "potato";
      if (word === "onions") return "onion";
      if (word === "chilies" || word === "chillies") return "chilli";
      if (word === "carrots") return "carrot";
      if (word === "grapes") return "grape";
      return word;
    })
    .replace(/\s+/g, " ")
    .trim();
}

function fuzzyCommodityIdFromText(normalizedInput: string): string | null {
  if (!normalizedInput) return null;
  const collapsed = normalizedInput.replace(/\s+/g, "");
  for (const rule of COMMODITY_FUZZY_KEYWORDS) {
    for (const keyword of rule.keywords) {
      const normKeyword = normalizeCommodityLookupText(keyword);
      if (!normKeyword) continue;
      if (normalizedInput.includes(normKeyword)) return rule.id;
      if (collapsed.includes(normKeyword.replace(/\s+/g, ""))) return rule.id;
    }
  }
  return null;
}

const COMMODITY_EN_TO_UR: Record<string, string> = {
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
  // Meats
  "live chicken": "زندہ مرغی",
  live_chicken: "زندہ مرغی",
  chicken: "مرغی",
  chicken_meat: "مرغی كا گوشت",
  beef: "بڑا گوشت",
  mutton: "چھوٹا گوشت",
  // Daily essentials
  flour: "آٹا",
  milk: "دودھ",
  "cooking oil": "كکنگ آئل",
  cooking_oil: "كکنگ آئل",
  ghee: "دیسی گھی",
  // Pulses
  mash: "ماش",
  black_gram: "ماش دال",
};

const CATEGORY_ALIAS_TO_EN: Record<string, string> = {
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

const SUBCATEGORY_ALIAS_TO_EN: Record<string, string> = {
  official_list: "official_list",
  "official list": "official_list",
  other: "other",
};

function canonicalLocation(value: string): string {
  const raw = text(value);
  if (!raw) return "";
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

function normalizeCategoryName(value: string): string {
  const raw = text(value).toLowerCase();
  if (!raw) return "crops";
  return CATEGORY_ALIAS_TO_EN[raw] ?? raw.replace(/\s+/g, "_");
}

function normalizeSubcategoryName(value: string): string {
  const raw = text(value).toLowerCase();
  if (!raw) return "other";
  return SUBCATEGORY_ALIAS_TO_EN[raw] ?? raw.replace(/\s+/g, "_");
}

export function normalizeLocationToken(value: string): string {
  const mapped = canonicalLocation(value);
  if (!mapped) return "";
  return mapped.toLowerCase().replace(/\s+/g, " ").trim();
}

export function normalizeCommodityName(value: string): string {
  const input = text(value);
  if (!input) return "unknown";

  const cleanInput = normalizeCommodityLookupText(input);

  if (!cleanInput) return "unknown";

  const mapped = (COMMODITY_ALIAS_TO_EN[input] ??
    COMMODITY_ALIAS_TO_EN[cleanInput] ??
    cleanInput)
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();

  const normalized = mapped
    .replace(/\begg\b/g, "eggs")
    .replace(/\bchicken_live\b/g, "live_chicken")
    .replace(/\bcooking_oil_5l\b/g, "cooking_oil")
    .replace(/\bdesi_ghee_1kg\b/g, "ghee")
    .replace(/\bblack_gram\b/g, "mash")
    .replace(/\s+/g, "_")
    .replace(/[^a-z_]/g, "")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");

  if (CANONICAL_COMMODITY_IDS.has(normalized)) {
    return normalized;
  }

  const fuzzyMatched = fuzzyCommodityIdFromText(cleanInput);
  if (fuzzyMatched && CANONICAL_COMMODITY_IDS.has(fuzzyMatched)) {
    return fuzzyMatched;
  }

  return "unknown";
}

export function toUrduCommodityLabel(english: string): string {
  const key = text(english).toLowerCase();
  return COMMODITY_EN_TO_UR[key] ?? "";
}

export function normalizeUnit(value: string): string {
  const raw = text(value).toLowerCase();
  if (!raw) return "PKR/100kg";
  if (raw.includes("mon") || raw.includes("maund") || raw.includes("mann") || raw.includes("40 kg") || raw.match(/\b40kg\b/)) return "PKR/40kg";
  if (raw.includes("100") && raw.includes("kg")) return "PKR/100kg";
  if (raw.includes("40") && raw.includes("kg")) return "PKR/40kg";
  if (raw.includes("50") && raw.includes("kg")) return "PKR/50kg";
  if (raw.includes("dozen") || raw.includes("doz")) return "PKR/dozen";
  if (raw.includes("tray")) return "PKR/tray";
  if (raw.includes("crate") || raw.includes("peti")) return "PKR/crate";
  if (raw.includes("head")) return "PKR/head";
  if (raw.includes("bag")) return "PKR/bag";
  if (raw === "kg" || raw === "per kg" || raw === "perkg" || raw === "pkr/kg" || raw === "rs/kg") return "PKR/kg";
  if (raw.includes("kg")) return "PKR/kg";
  return raw.toUpperCase();
}

export function normalizePriceText(value: unknown): string {
  const raw = text(value);
  if (!raw) return "";
  return raw
    .toLowerCase()
    .replace(/rs\.?|pkr|rupees?/g, "")
    .replace(/,/g, "")
    .replace(/[^0-9.\-]/g, "")
    .trim();
}

export function normalizeTrend(price: number, previous: number | null, trend: string): "up" | "down" | "same" {
  const raw = text(trend).toLowerCase();
  if (raw === "up" || raw.includes("rise")) return "up";
  if (raw === "down" || raw.includes("fall")) return "down";
  if (previous != null && previous > 0) {
    if (price > previous) return "up";
    if (price < previous) return "down";
  }
  return "same";
}

export function freshnessStatus(lastUpdated: Date, now: Date): "live" | "recent" | "aging" | "stale" {
  const ageMs = now.getTime() - lastUpdated.getTime();
  if (ageMs <= 30 * 60 * 1000) return "live";
  if (ageMs <= 6 * 60 * 60 * 1000) return "recent";
  if (ageMs <= 24 * 60 * 60 * 1000) return "aging";
  return "stale";
}

export function deterministicIdForRow(row: RawSourceRow): string {
  const day = row.lastUpdated.toISOString().slice(0, 10);
  const sourceKey = slug(row.sourceId);
  const commodityKey = slug(normalizeCommodityName(row.commodityName));
  const mandiKey = slug(row.mandiName || row.city);
  const cityKey = slug(row.city);
  const ref = String(row.metadata?.commodityRefId ?? row.metadata?.commodityId ?? "").trim();
  const refKey = ref ? slug(ref) : "";
  return [sourceKey, commodityKey, refKey, mandiKey, cityKey, day].filter((item) => item).join("_");
}

export function toUnifiedBase(row: RawSourceRow, now: Date): UnifiedMandiRate {
  const commodityName = normalizeCommodityName(row.commodityName);
  const unit = normalizeUnit(row.unit ?? "PKR/100kg");
  const normalizedPriceText = normalizePriceText(
    row.metadata?.rawPriceText ?? row.metadata?.priceText ?? String(row.price),
  );
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
