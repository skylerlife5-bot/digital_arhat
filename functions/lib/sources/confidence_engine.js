"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.scoreConfidence = scoreConfidence;
function clamp01(value) {
    if (value < 0)
        return 0;
    if (value > 1)
        return 1;
    return value;
}
function freshnessBonus(status) {
    if (status === "live")
        return 0.2;
    if (status === "recent")
        return 0.14;
    if (status === "aging")
        return 0.06;
    return -0.15;
}
function officialSourceBonus(sourceId) {
    if (sourceId === "amis_official")
        return 0.22;
    if (sourceId === "lahore_official_market_rates")
        return 0.24;
    if (sourceId === "karachi_official_price_lists")
        return 0.24;
    return 0;
}
function multiSourceBonus(count) {
    if (count >= 3)
        return 0.14;
    if (count == 2)
        return 0.09;
    return 0;
}
function sameCityBonus(count) {
    if (count >= 4)
        return 0.1;
    if (count >= 2)
        return 0.06;
    return 0;
}
function toVerificationStatus(score, corroborationCount) {
    if (score >= 0.85)
        return "Official Verified";
    if (score >= 0.7 && corroborationCount > 1)
        return "Cross-Checked";
    if (score >= 0.5)
        return "Limited Confidence";
    return "Needs Review";
}
function scoreConfidence(record, input) {
    let score = 0.45;
    score += officialSourceBonus(record.sourceId);
    score += freshnessBonus(record.freshnessStatus);
    score += input.sourceReliability;
    if (input.corroborationCount > 1) {
        score += Math.min(0.14, (input.corroborationCount - 1) * 0.05);
    }
    score += sameCityBonus(input.sameCityCorroboration);
    score += multiSourceBonus(input.multiSourceCorroboration);
    score += Math.max(-0.12, Math.min(0.12, (input.duplicateAgreement - 0.5) * 0.24));
    if (input.suspiciousSpike) {
        score -= 0.26;
    }
    if (input.sparseData) {
        score -= 0.12;
    }
    if (input.incompleteMetadata) {
        score -= 0.08;
    }
    const finalScore = Number(clamp01(score).toFixed(3));
    const status = toVerificationStatus(finalScore, input.corroborationCount);
    const reasonParts = [
        `source=${record.sourceId}`,
        `freshness=${record.freshnessStatus}`,
        `corroboration=${input.corroborationCount}`,
        `sameCity=${input.sameCityCorroboration}`,
        `multiSource=${input.multiSourceCorroboration}`,
        `agreement=${input.duplicateAgreement.toFixed(3)}`,
        `spike=${input.suspiciousSpike ? "yes" : "no"}`,
        `sparse=${input.sparseData ? "yes" : "no"}`,
        `incomplete=${input.incompleteMetadata ? "yes" : "no"}`,
    ];
    return {
        score: finalScore,
        reason: reasonParts.join(";"),
        verificationStatus: status,
    };
}
