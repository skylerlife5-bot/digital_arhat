export type SourceFamily =
  | "official_national_source"
  | "official_city_market_source"
  | "official_commissioner_source"
  | "future_city_committee_source"
  | "future_verified_trader_source"
  | "future_verified_dealer_source";

export type SourceType =
  | "official_aggregator"
  | "official_market_committee"
  | "official_commissioner"
  | "human_verified"
  | "human_local"
  | SourceFamily;

export type TrustLevel = "high" | "medium" | "low";

export type SchedulePolicy = "15m" | "hourly" | "daily";

export type VerificationStatus =
  | "Official Verified"
  | "Cross-Checked"
  | "Limited Confidence"
  | "Needs Review";

export type ContributorType =
  | "official"
  | "verified_mandi_reporter"
  | "verified_commission_agent"
  | "verified_dealer"
  | "trusted_local_contributor";

export type ContributorVerificationStatus =
  | "verified"
  | "provisional"
  | "pending"
  | "suspended"
  | "revoked";

export type ContributionReviewStatus =
  | "accepted"
  | "limited_confidence"
  | "needs_review"
  | "rejected";

export type ContributorTrustLevel = "high" | "medium" | "low" | "blocked";

export type ContributorPenaltyLevel = "none" | "watch" | "limited" | "muted" | "suspended";

export type ContributorProfile = {
  contributorId: string;
  displayName: string;
  maskedContactRef: string;
  city: string;
  district: string;
  province: string;
  contributorType: ContributorType;
  verificationStatus: ContributorVerificationStatus;
  trustScore: number;
  reliabilityScore: number;
  totalSubmissions: number;
  acceptedSubmissions: number;
  rejectedSubmissions: number;
  disputedSubmissions: number;
  citySpecificReliability: Record<string, number>;
  suspiciousSpikeCount: number;
  lastSubmissionAt: Date | null;
  penaltyLevel: ContributorPenaltyLevel;
  activeStatus: "active" | "muted" | "suspended";
  metadata: Record<string, unknown>;
};

export type HumanContributionSubmission = {
  submissionId: string;
  contributorId: string;
  contributorType: ContributorType;
  verificationStatus: ContributorVerificationStatus;
  commodityName: string;
  commodityNameUr?: string;
  categoryName?: string;
  subCategoryName?: string;
  mandiName: string;
  city: string;
  district?: string;
  province: string;
  price: number;
  previousPrice?: number | null;
  minPrice?: number | null;
  maxPrice?: number | null;
  unit?: string;
  currency?: string;
  latitude?: number | null;
  longitude?: number | null;
  submissionTimestamp: Date;
  metadata?: Record<string, unknown>;
};

export type SourceDefinition = {
  sourceId: string;
  sourceName: string;
  sourceFamily: SourceFamily;
  sourceType: SourceType;
  province: string;
  cityCoverage: string[];
  categoryCoverage: string[];
  adapterClass:
    | "AmisOfficialAdapter"
    | "LahoreOfficialAdapter"
    | "KarachiOfficialAdapter"
    | "FutureUnimplementedAdapter";
  trustLevel: TrustLevel;
  schedulePolicy: SchedulePolicy;
  enabled: boolean;
  futureReady?: boolean;
};

export type RawSourceRow = {
  sourceId: string;
  sourceType: SourceType;
  sourceName: string;
  commodityName: string;
  commodityNameUr?: string;
  categoryName?: string;
  subCategoryName?: string;
  mandiName: string;
  city: string;
  district?: string;
  province: string;
  latitude?: number | null;
  longitude?: number | null;
  price: number;
  previousPrice?: number | null;
  minPrice?: number | null;
  maxPrice?: number | null;
  unit?: string;
  currency?: string;
  trend?: "up" | "down" | "same";
  lastUpdated: Date;
  metadata?: Record<string, unknown>;
};

export type UnifiedMandiRate = {
  id: string;
  commodityName: string;
  commodityNameUr: string;
  categoryName: string;
  subCategoryName: string;
  mandiName: string;
  city: string;
  district: string;
  province: string;
  latitude: number | null;
  longitude: number | null;
  price: number;
  previousPrice: number | null;
  minPrice: number | null;
  maxPrice: number | null;
  unit: string;
  currency: string;
  trend: "up" | "down" | "same";
  source: string;
  sourceId: string;
  sourceType: SourceType;
  lastUpdated: Date;
  syncedAt: Date;
  freshnessStatus: "live" | "recent" | "aging" | "stale";
  confidenceScore: number;
  confidenceReason: string;
  verificationStatus: VerificationStatus;
  contributorType: ContributorType;
  contributorId?: string;
  contributorVerificationStatus?: ContributorVerificationStatus;
  trustScore?: number;
  reliabilityScore?: number;
  trustLevel?: ContributorTrustLevel;
  trustReason?: string;
  reviewStatus?: ContributionReviewStatus;
  corroborationCount?: number;
  disputeCount?: number;
  acceptedBySystem?: boolean;
  acceptedByAdmin?: boolean;
  submissionTimestamp?: Date;
  priorityRank?: number;
  isNearby: boolean;
  isAiCleaned: boolean;
  metadata: Record<string, unknown>;
};

export type SourceRunStats = {
  sourceId: string;
  sourceName?: string;
  sourceType?: SourceType;
  sourceFamily?: SourceFamily;
  startedAtIso: string;
  fetchedRows: number;
  parsedRows: number;
  rejectedRows: number;
  writtenRows: number;
  sourceUrls?: string[];
  sampleCities?: string[];
  sampleCommodities?: string[];
  failed: boolean;
  failReason: string | null;
};

export type AdapterContext = {
  now: Date;
  logger: (event: string, data: Record<string, unknown>) => void;
};

export type OfficialSourceAdapter = {
  fetchRows: (context: AdapterContext) => Promise<RawSourceRow[]>;
};
