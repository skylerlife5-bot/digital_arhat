"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.priorityRankForRecord = priorityRankForRecord;
exports.canPromoteOnHome = canPromoteOnHome;
function isOfficial(record) {
    return record.contributorType == "official" ||
        record.sourceType == "official_aggregator" ||
        record.sourceType == "official_market_committee" ||
        record.sourceType == "official_commissioner";
}
function isVerifiedHuman(record) {
    return record.contributorType == "verified_mandi_reporter" ||
        record.contributorType == "verified_commission_agent" ||
        record.contributorType == "verified_dealer";
}
function isTrustedLocal(record) {
    return record.contributorType == "trusted_local_contributor";
}
function hasStrongCorroboration(record) {
    return (record.corroborationCount ?? 0) >= 2 &&
        (record.confidenceScore >= 0.7 || (record.trustScore ?? 0) >= 0.72);
}
function reviewStatus(record) {
    return record.reviewStatus ?? (record.confidenceScore >= 0.8 ? "accepted" : "needs_review");
}
function priorityRankForRecord(record) {
    if (record.sourceId == "fscpd_official")
        return 1;
    if (record.sourceId == "amis_official")
        return 2;
    if (record.sourceId == "lahore_official_market_rates")
        return 3;
    if (record.sourceId == "karachi_official_price_lists")
        return 4;
    if (record.sourceId == "pbs_spi")
        return 5;
    if (isOfficial(record) && record.verificationStatus == "Official Verified")
        return 6;
    if (isOfficial(record) && record.verificationStatus == "Cross-Checked")
        return 7;
    if (isVerifiedHuman(record) && hasStrongCorroboration(record))
        return 8;
    if (isTrustedLocal(record) && hasStrongCorroboration(record))
        return 9;
    if (!isOfficial(record) && reviewStatus(record) != "rejected")
        return 10;
    return 11;
}
function canPromoteOnHome(record, options) {
    if (reviewStatus(record) == "rejected")
        return false;
    const rank = priorityRankForRecord(record);
    if (rank <= 2)
        return true;
    // Human data is allowed on Home only where official equivalent is weak/missing,
    // or where human corroboration and confidence is clearly strong.
    if (options.hasStrongOfficialEquivalent) {
        return rank <= 4 && (record.confidenceScore >= 0.82 || (record.trustScore ?? 0) >= 0.84);
    }
    return rank <= 4 &&
        record.confidenceScore >= 0.72 &&
        (record.reviewStatus == "accepted" || record.verificationStatus == "Cross-Checked");
}
