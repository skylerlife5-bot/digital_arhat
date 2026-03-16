"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.assessContributionPenalty = assessContributionPenalty;
function scorePenaltySignals(input) {
    let score = 0;
    if (input.reviewStatus === "rejected")
        score += 3;
    if (input.reviewStatus === "needs_review")
        score += 1;
    if (input.suspiciousOutlier)
        score += 2;
    if (input.consensusContradiction)
        score += 2;
    if (input.spammyRateBehavior)
        score += 2;
    if (input.lowQualityMetadata)
        score += 1;
    if (input.profile.penaltyLevel === "watch")
        score += 1;
    if (input.profile.penaltyLevel === "limited")
        score += 2;
    if (input.profile.penaltyLevel === "muted")
        score += 3;
    return score;
}
function assessContributionPenalty(input) {
    const score = scorePenaltySignals(input);
    let penaltyLevel = "none";
    let trustPenalty = 0;
    let shouldMuteTemporarily = false;
    let shouldSuspend = false;
    if (score >= 8) {
        penaltyLevel = "suspended";
        trustPenalty = 0.3;
        shouldSuspend = true;
    }
    else if (score >= 6) {
        penaltyLevel = "muted";
        trustPenalty = 0.2;
        shouldMuteTemporarily = true;
    }
    else if (score >= 4) {
        penaltyLevel = "limited";
        trustPenalty = 0.12;
    }
    else if (score >= 2) {
        penaltyLevel = "watch";
        trustPenalty = 0.06;
    }
    return {
        penaltyLevel,
        trustPenalty,
        shouldMuteTemporarily,
        shouldSuspend,
        blockHomePromotion: score >= 3,
        reason: [
            `score=${score}`,
            `reviewStatus=${input.reviewStatus}`,
            `outlier=${input.suspiciousOutlier ? "yes" : "no"}`,
            `contradiction=${input.consensusContradiction ? "yes" : "no"}`,
            `spam=${input.spammyRateBehavior ? "yes" : "no"}`,
            `metadataLow=${input.lowQualityMetadata ? "yes" : "no"}`,
        ].join(";"),
    };
}
