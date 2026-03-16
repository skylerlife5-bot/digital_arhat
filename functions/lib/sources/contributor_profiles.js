"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.createContributorProfile = createContributorProfile;
exports.toContributorPublicView = toContributorPublicView;
exports.applyPenaltyLevel = applyPenaltyLevel;
function maskContact(input) {
    const value = input.replace(/\s+/g, "").trim();
    if (!value)
        return "hidden";
    if (value.length <= 4)
        return `***${value}`;
    return `${value.slice(0, 2)}***${value.slice(-2)}`;
}
function createContributorProfile(draft) {
    const maskedContactRef = (draft.maskedContactRef ?? "").trim() || maskContact(draft.phone ?? "");
    return {
        contributorId: draft.contributorId.trim(),
        displayName: draft.displayName.trim(),
        maskedContactRef,
        city: draft.city.trim(),
        district: draft.district.trim(),
        province: draft.province.trim(),
        contributorType: draft.contributorType,
        verificationStatus: draft.verificationStatus,
        trustScore: 0.5,
        reliabilityScore: 0.5,
        totalSubmissions: 0,
        acceptedSubmissions: 0,
        rejectedSubmissions: 0,
        disputedSubmissions: 0,
        citySpecificReliability: {},
        suspiciousSpikeCount: 0,
        lastSubmissionAt: null,
        penaltyLevel: "none",
        activeStatus: "active",
        metadata: {
            ...(draft.metadata ?? {}),
            profileVersion: "phase_c_v1",
        },
    };
}
function toContributorPublicView(profile) {
    return {
        contributorId: profile.contributorId,
        displayName: profile.displayName,
        maskedContactRef: profile.maskedContactRef,
        city: profile.city,
        district: profile.district,
        province: profile.province,
        contributorType: profile.contributorType,
        verificationStatus: profile.verificationStatus,
        trustScore: profile.trustScore,
        reliabilityScore: profile.reliabilityScore,
        totalSubmissions: profile.totalSubmissions,
        acceptedSubmissions: profile.acceptedSubmissions,
        rejectedSubmissions: profile.rejectedSubmissions,
        disputedSubmissions: profile.disputedSubmissions,
        penaltyLevel: profile.penaltyLevel,
        activeStatus: profile.activeStatus,
        lastSubmissionAt: profile.lastSubmissionAt,
    };
}
function applyPenaltyLevel(profile, penaltyLevel) {
    const activeStatus = penaltyLevel === "suspended"
        ? "suspended"
        : penaltyLevel === "muted"
            ? "muted"
            : "active";
    return {
        ...profile,
        penaltyLevel,
        activeStatus,
    };
}
