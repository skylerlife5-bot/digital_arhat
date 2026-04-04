"use strict";
/**
 * unit_rules.ts
 *
 * Commodity-specific unit allow-lists for the Market Pulse confidence engine.
 *
 * Hard rules:
 *  - banana / kela → ONLY dozen or crate, never kg
 *  - eggs / anda   → ONLY dozen or tray, never kg
 *  - wheat/rice/pulses → bulk units (40kg / 100kg / 50kg / kg depending on source)
 *  - vegetables    → per-kg or per-40kg
 *  - livestock     → per-head (or per-kg live weight)
 *  - fertilizer    → 50kg bag
 *
 * Any row that violates its commodity's allow-list is flagged as
 * "unit_violation" and its rowConfidence is set to "rejected".
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.checkUnitForCommodity = checkUnitForCommodity;
exports.isCriticalUnitViolation = isCriticalUnitViolation;
exports.detectRawUnitConflict = detectRawUnitConflict;
exports.sanityRejectReason = sanityRejectReason;
// ---------------------------------------------------------------------------
// Internal normalisation
// ---------------------------------------------------------------------------
function normalizeUnitToken(unit) {
    return unit
        .toLowerCase()
        .replace(/\s+/g, "")
        .replace(/rs\.?/g, "pkr")
        .replace(/rupees?/g, "pkr")
        .replace(/per/g, "/")
        .replace(/\//g, "/") // idempotent but explicit
        .replace(/maund|mond|mann/g, "40kg")
        .replace(/dozen|doz\b/g, "dozen")
        .replace(/tray/g, "tray")
        .replace(/\s/g, "")
        .replace(/crate|peti/g, "crate")
        .replace(/head/g, "head")
        .replace(/bag/g, "bag");
}
function hasMissingUnit(unit) {
    return !String(unit ?? "").trim();
}
function hasMixedUnitPhrase(unit) {
    const normalized = normalizeUnitToken(unit);
    const hasKg = normalized.includes("kg");
    const hasDozen = normalized.includes("dozen");
    const hasTray = normalized.includes("tray");
    const hasCrate = normalized.includes("crate");
    const hasHead = normalized.includes("head");
    const counted = [hasKg, hasDozen, hasTray, hasCrate, hasHead].filter(Boolean).length;
    return counted > 1;
}
function hasAmbiguousUnit(unit) {
    const normalized = normalizeUnitToken(unit);
    if (!normalized)
        return true;
    const unitKeywords = ["kg", "dozen", "tray", "crate", "head", "bag"];
    return !unitKeywords.some((token) => normalized.includes(token));
}
// ---------------------------------------------------------------------------
// Allow-lists (keyed by lowercased commodity keyword)
// ---------------------------------------------------------------------------
/**
 * Maps a commodity keyword to its list of accepted normalised unit tokens.
 * If a commodity has no entry, any unit is accepted (open list).
 */
const COMMODITY_UNIT_ALLOW_LIST = {
    // ----- Cereals / grains (bulk only) -----
    wheat: ["pkr/40kg", "pkr/50kg", "pkr/100kg", "pkr/kg"],
    gandum: ["pkr/40kg", "pkr/50kg", "pkr/100kg", "pkr/kg"],
    rice: ["pkr/40kg", "pkr/50kg", "pkr/100kg", "pkr/kg"],
    basmati: ["pkr/40kg", "pkr/50kg", "pkr/100kg", "pkr/kg"],
    irri: ["pkr/40kg", "pkr/50kg", "pkr/100kg", "pkr/kg"],
    paddy: ["pkr/40kg", "pkr/50kg", "pkr/100kg", "pkr/kg"],
    maize: ["pkr/40kg", "pkr/50kg", "pkr/100kg", "pkr/kg"],
    corn: ["pkr/40kg", "pkr/50kg", "pkr/100kg", "pkr/kg"],
    sugarcane: ["pkr/40kg", "pkr/50kg", "pkr/100kg", "pkr/kg"],
    cotton: ["pkr/40kg", "pkr/50kg", "pkr/100kg", "pkr/kg"],
    // ----- Vegetables (per-kg or per-40kg; never per-dozen) -----
    tomato: ["pkr/kg", "pkr/40kg", "pkr/50kg", "pkr/100kg"],
    tamatar: ["pkr/kg", "pkr/40kg", "pkr/50kg", "pkr/100kg"],
    potato: ["pkr/kg", "pkr/40kg", "pkr/50kg", "pkr/100kg"],
    aloo: ["pkr/kg", "pkr/40kg", "pkr/50kg", "pkr/100kg"],
    onion: ["pkr/kg", "pkr/40kg", "pkr/50kg", "pkr/100kg"],
    pyaz: ["pkr/kg", "pkr/40kg", "pkr/50kg", "pkr/100kg"],
    garlic: ["pkr/kg", "pkr/40kg"],
    lehsan: ["pkr/kg", "pkr/40kg"],
    ginger: ["pkr/kg", "pkr/40kg"],
    chilli: ["pkr/kg", "pkr/40kg"],
    chili: ["pkr/kg", "pkr/40kg"],
    mirch: ["pkr/kg", "pkr/40kg"],
    capsicum: ["pkr/kg", "pkr/40kg"],
    spinach: ["pkr/kg", "pkr/40kg"],
    cabbage: ["pkr/kg", "pkr/40kg"],
    cauliflower: ["pkr/kg", "pkr/40kg"],
    carrot: ["pkr/kg", "pkr/40kg"],
    radish: ["pkr/kg", "pkr/40kg"],
    turnip: ["pkr/kg", "pkr/40kg"],
    peas: ["pkr/kg", "pkr/40kg"],
    okra: ["pkr/kg", "pkr/40kg"],
    brinjal: ["pkr/kg", "pkr/40kg"],
    eggplant: ["pkr/kg", "pkr/40kg"],
    "bitter gourd": ["pkr/kg", "pkr/40kg"],
    "bottle gourd": ["pkr/kg", "pkr/40kg"],
    // ----- Fruits (per-kg or per-40kg for most) -----
    mango: ["pkr/kg", "pkr/40kg"],
    apple: ["pkr/kg", "pkr/40kg"],
    orange: ["pkr/kg", "pkr/40kg"],
    kinnow: ["pkr/kg", "pkr/40kg"],
    kinow: ["pkr/kg", "pkr/40kg"],
    guava: ["pkr/kg", "pkr/40kg"],
    grape: ["pkr/kg", "pkr/40kg"],
    grapes: ["pkr/kg", "pkr/40kg"],
    watermelon: ["pkr/kg", "pkr/40kg"],
    melon: ["pkr/kg", "pkr/40kg"],
    pomegranate: ["pkr/kg", "pkr/40kg"],
    // ----- Banana: ONLY dozen or crate — NEVER per-kg -----
    banana: ["pkr/dozen", "pkr/crate"],
    kela: ["pkr/dozen", "pkr/crate"],
    // ----- Eggs: ONLY dozen or tray — NEVER per-kg -----
    egg: ["pkr/dozen", "pkr/tray"],
    eggs: ["pkr/dozen", "pkr/tray"],
    anda: ["pkr/dozen", "pkr/tray"],
    // ----- Pulses (bulk) -----
    chickpea: ["pkr/kg", "pkr/40kg", "pkr/100kg"],
    chana: ["pkr/kg", "pkr/40kg", "pkr/100kg"],
    lentil: ["pkr/kg", "pkr/40kg", "pkr/100kg"],
    masoor: ["pkr/kg", "pkr/40kg", "pkr/100kg"],
    masur: ["pkr/kg", "pkr/40kg", "pkr/100kg"],
    moong: ["pkr/kg", "pkr/40kg", "pkr/100kg"],
    mung: ["pkr/kg", "pkr/40kg", "pkr/100kg"],
    // ----- Spices (bulk) -----
    coriander: ["pkr/kg", "pkr/40kg"],
    turmeric: ["pkr/kg", "pkr/40kg"],
    cumin: ["pkr/kg", "pkr/40kg"],
    zeera: ["pkr/kg", "pkr/40kg"],
    dhania: ["pkr/kg", "pkr/40kg"],
    // ----- Livestock -----
    goat: ["pkr/head", "pkr/kg"],
    bakra: ["pkr/head", "pkr/kg"],
    cow: ["pkr/head", "pkr/kg"],
    gai: ["pkr/head", "pkr/kg"],
    // ----- Fertilizer (50kg bag) -----
    dap: ["pkr/50kg", "pkr/bag"],
    urea: ["pkr/50kg", "pkr/bag"],
};
const CRITICAL_VIOLATIONS = [
    {
        commodityKeywords: ["banana", "kela"],
        forbiddenUnitKeywords: ["kg"],
        reason: "critical_unit_violation:banana_kg",
    },
    {
        commodityKeywords: ["egg", "eggs", "anda"],
        forbiddenUnitKeywords: ["kg"],
        reason: "critical_unit_violation:egg_kg",
    },
    {
        commodityKeywords: ["goat", "bakra", "cow", "gai", "livestock"],
        forbiddenUnitKeywords: ["dozen", "tray", "crate", "doz"],
        reason: "critical_unit_violation:livestock_dozen",
    },
    {
        commodityKeywords: ["wheat", "gandum", "rice", "chawal"],
        forbiddenUnitKeywords: ["dozen", "tray", "crate"],
        reason: "critical_unit_violation:grain_dozen",
    },
];
// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
/**
 * Returns the first matching commodity keyword from the allow-list for a
 * given commodity name, or null if this commodity has no specific rule.
 */
function extractCommodityKey(commodityName) {
    const lower = commodityName.toLowerCase();
    // Sort by length descending so "bitter gourd" matches before "gourd"
    const keys = Object.keys(COMMODITY_UNIT_ALLOW_LIST).sort((a, b) => b.length - a.length);
    for (const key of keys) {
        if (lower.includes(key))
            return key;
    }
    return null;
}
/**
 * Check whether `unit` is valid for `commodityName`.
 *
 * Priority order:
 *  1. Critical violation check (instant reject, overrides allow-list)
 *  2. Allow-list check (commodity has a specific list, unit must be in it)
 *  3. Open pass (commodity has no specific rule)
 */
function checkUnitForCommodity(unit, commodityName) {
    if (hasMissingUnit(unit)) {
        return {
            allowed: false,
            reason: "missing_unit",
            normalizedUnit: "",
        };
    }
    if (hasMixedUnitPhrase(unit)) {
        return {
            allowed: false,
            reason: "mixed_unit_phrase",
            normalizedUnit: normalizeUnitToken(unit),
        };
    }
    if (hasAmbiguousUnit(unit)) {
        return {
            allowed: false,
            reason: "ambiguous_unit",
            normalizedUnit: normalizeUnitToken(unit),
        };
    }
    const normUnit = normalizeUnitToken(unit);
    const normCommodity = commodityName.toLowerCase();
    // 1. Critical violations first
    for (const rule of CRITICAL_VIOLATIONS) {
        const matchesCommodity = rule.commodityKeywords.some((kw) => normCommodity.includes(kw));
        if (!matchesCommodity)
            continue;
        const matchesForbidden = rule.forbiddenUnitKeywords.some((kw) => normUnit.includes(kw));
        if (matchesForbidden) {
            return { allowed: false, reason: rule.reason, normalizedUnit: normUnit };
        }
    }
    // 2. Allow-list check
    const key = extractCommodityKey(commodityName);
    if (key !== null) {
        const allowList = COMMODITY_UNIT_ALLOW_LIST[key] ?? [];
        const normalizedAllowList = allowList.map(normalizeUnitToken);
        if (!normalizedAllowList.includes(normUnit)) {
            return {
                allowed: false,
                reason: `unit_not_in_allowlist:${key}:got=${normUnit}:expected=${allowList.slice(0, 3).join("|")}`,
                normalizedUnit: normUnit,
            };
        }
        return { allowed: true, reason: "unit_allowed", normalizedUnit: normUnit };
    }
    // 3. No specific rule — accept any unit
    return { allowed: true, reason: "no_specific_rule", normalizedUnit: normUnit };
}
/**
 * Returns true if the unit is an impossible combination for the commodity —
 * used as a hard confidence gate to set rowConfidence = "rejected".
 */
function isCriticalUnitViolation(commodityName, unit) {
    const result = checkUnitForCommodity(unit, commodityName);
    return !result.allowed && result.reason.startsWith("critical_unit_violation");
}
function hasUnitToken(source, token) {
    const normalized = normalizeUnitToken(source);
    return normalized.includes(token);
}
function detectRawUnitConflict(normalizedUnit, rawPriceText) {
    const raw = String(rawPriceText ?? "").toLowerCase();
    if (!raw.trim())
        return null;
    const hasBulkSignal = raw.includes("100 kg") || raw.includes("100kg") ||
        raw.includes("50 kg") || raw.includes("50kg") ||
        raw.includes("40 kg") || raw.includes("40kg") ||
        raw.includes("maund") || raw.includes("mann");
    const hasCountSignal = raw.includes("dozen") || raw.includes("doz") || raw.includes("tray") ||
        raw.includes("crate") || raw.includes("peti");
    if (hasBulkSignal && (hasUnitToken(normalizedUnit, "dozen") || hasUnitToken(normalizedUnit, "tray") || hasUnitToken(normalizedUnit, "crate"))) {
        return "raw_unit_conflict_bulk_vs_count";
    }
    if (hasCountSignal && (hasUnitToken(normalizedUnit, "100kg") || hasUnitToken(normalizedUnit, "50kg") || hasUnitToken(normalizedUnit, "40kg") || hasUnitToken(normalizedUnit, "kg"))) {
        return "raw_unit_conflict_count_vs_bulk";
    }
    return null;
}
function sanityRejectReason(commodityName, normalizedUnit, price) {
    const commodity = commodityName.toLowerCase();
    const unit = normalizeUnitToken(normalizedUnit);
    const value = Number(price);
    if (!Number.isFinite(value) || value <= 0)
        return "invalid_price";
    const isBanana = commodity.includes("banana") || commodity.includes("kela");
    const isEggs = commodity.includes("egg") || commodity.includes("anda");
    if (isBanana && unit.includes("dozen") && value > 1500) {
        return "banana_dozen_absurd_price";
    }
    if (isEggs && unit.includes("dozen") && value > 1200) {
        return "eggs_dozen_absurd_price";
    }
    if (isEggs && unit.includes("tray") && value > 3500) {
        return "eggs_tray_absurd_price";
    }
    return null;
}
