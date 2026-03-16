import {getEnabledTopPriorityMandis} from "./top25_mandi_registry";
import {SourceDefinition} from "./types";

export const OFFICIAL_SOURCE_REGISTRY: SourceDefinition[] = [
  {
    sourceId: "amis_official",
    sourceName: "AMIS Official",
    sourceFamily: "official_national_source",
    sourceType: "official_aggregator",
    province: "Punjab",
    cityCoverage: ["Punjab"],
    categoryCoverage: [
      "crops",
      "vegetables",
      "fruits",
      "pulses",
      "spices",
      "fertilizer",
      "seeds",
      "livestock",
    ],
    adapterClass: "AmisOfficialAdapter",
    trustLevel: "high",
    schedulePolicy: "15m",
    enabled: true,
  },
  {
    sourceId: "lahore_official_market_rates",
    sourceName: "Lahore Official Market Rates",
    sourceFamily: "official_city_market_source",
    sourceType: "official_market_committee",
    province: "Punjab",
    cityCoverage: ["Lahore"],
    categoryCoverage: ["fruits", "vegetables", "essentials"],
    adapterClass: "LahoreOfficialAdapter",
    trustLevel: "high",
    schedulePolicy: "hourly",
    enabled: true,
  },
  {
    sourceId: "karachi_official_price_lists",
    sourceName: "Karachi Official Price Lists",
    sourceFamily: "official_commissioner_source",
    sourceType: "official_commissioner",
    province: "Sindh",
    cityCoverage: ["Karachi"],
    categoryCoverage: ["fruits", "vegetables", "essentials"],
    adapterClass: "KarachiOfficialAdapter",
    trustLevel: "high",
    schedulePolicy: "hourly",
    enabled: true,
  },
];

const FUTURE_TOP_CITY_SOURCES: SourceDefinition[] = getEnabledTopPriorityMandis()
  .filter((item) => item.futureReady)
  .map((item) => ({
    sourceId: `future_${item.city.toLowerCase().replace(/[^a-z0-9]+/g, "_")}_source`,
    sourceName: `${item.city} Future Official Source`,
    sourceFamily: item.expectedSourceFamily,
    sourceType: item.expectedSourceFamily,
    province: item.province,
    cityCoverage: [item.city],
    categoryCoverage: ["crops", "fruits", "vegetables", "essentials"],
    adapterClass: "FutureUnimplementedAdapter",
    trustLevel: "medium",
    schedulePolicy: "daily",
    enabled: false,
    futureReady: true,
  }));

export const PHASE_B_SOURCE_REGISTRY: SourceDefinition[] = [
  ...OFFICIAL_SOURCE_REGISTRY,
  ...FUTURE_TOP_CITY_SOURCES,
];

export const HUMAN_CONTRIBUTION_SOURCE_REGISTRY: SourceDefinition[] = [
  {
    sourceId: "human_verified_network",
    sourceName: "Verified Human Contributor Network",
    sourceFamily: "future_verified_trader_source",
    sourceType: "human_verified",
    province: "Pakistan",
    cityCoverage: ["Pakistan"],
    categoryCoverage: ["crops", "fruits", "vegetables", "essentials"],
    adapterClass: "FutureUnimplementedAdapter",
    trustLevel: "medium",
    schedulePolicy: "15m",
    enabled: false,
    futureReady: true,
  },
  {
    sourceId: "human_local_network",
    sourceName: "Trusted Local Contributor Network",
    sourceFamily: "future_verified_dealer_source",
    sourceType: "human_local",
    province: "Pakistan",
    cityCoverage: ["Pakistan"],
    categoryCoverage: ["crops", "fruits", "vegetables", "essentials"],
    adapterClass: "FutureUnimplementedAdapter",
    trustLevel: "low",
    schedulePolicy: "hourly",
    enabled: false,
    futureReady: true,
  },
];

function envEnabled(sourceId: string): boolean {
  const key = `MANDI_SOURCE_${sourceId.toUpperCase().replace(/[^A-Z0-9]/g, "_")}_ENABLED`;
  const raw = String(process.env[key] ?? "").trim().toLowerCase();
  if (!raw) return true;
  return raw === "1" || raw === "true" || raw === "yes";
}

export function getEnabledOfficialSources(): SourceDefinition[] {
  return PHASE_B_SOURCE_REGISTRY.filter((item) => item.enabled && envEnabled(item.sourceId));
}

export function getHumanContributionSources(): SourceDefinition[] {
  return HUMAN_CONTRIBUTION_SOURCE_REGISTRY.filter((item) => item.enabled && envEnabled(item.sourceId));
}
