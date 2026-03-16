import {TopPriorityMandiTarget} from "./top25_mandi_registry";
import {BlockedCityEntry} from "./blocked_city_registry";
import {SourceDefinition, SourceRunStats} from "./types";

export type CityCoverageState = "official_live" | "partial_live" | "future_ready" | "blocked" | "not_implemented";

export type CityCoverageStatus = {
  city: string;
  district: string;
  province: string;
  priorityRank: number;
  expectedSourceFamily: string;
  aliases: string[];
  activeSourceIds: string[];
  blockedReasonCode: string | null;
  blockedReason: string | null;
  blockedSeverity: string | null;
  state: CityCoverageState;
  notes: string;
};

export function buildCityCoverageStatus(input: {
  targets: TopPriorityMandiTarget[];
  registry: SourceDefinition[];
  sourceRuns: SourceRunStats[];
  blockedCities?: BlockedCityEntry[];
}): CityCoverageStatus[] {
  const activeRegistry = input.registry.filter((item) => item.enabled);
  const successfulRuns = new Set(
    input.sourceRuns
      .filter((run) => !run.failed && run.writtenRows > 0)
      .map((run) => run.sourceId),
  );
  const blockedByCity = new Map(
    (input.blockedCities ?? []).map((entry) => [entry.city.toLowerCase(), entry]),
  );

  return input.targets.map((target) => {
    const activeSourceIds = activeRegistry
      .filter((source) => source.cityCoverage.some((city) => city.toLowerCase() === target.city.toLowerCase()))
      .map((source) => source.sourceId)
      .filter((sourceId) => successfulRuns.has(sourceId));

    let state: CityCoverageState = "not_implemented";
    let notes = "No successful source mapped for this priority city yet.";
    const blocked = blockedByCity.get(target.city.toLowerCase()) ?? null;

    if (activeSourceIds.length >= 2) {
      state = "official_live";
      notes = "Multiple successful official feeds available.";
    } else if (activeSourceIds.length == 1) {
      state = "partial_live";
      notes = "Single successful official feed available.";
    } else if (blocked) {
      state = "blocked";
      notes = blocked.reason;
    } else if (target.futureReady) {
      state = "future_ready";
      notes = "Registered for future adapter rollout.";
    }

    return {
      city: target.city,
      district: target.district,
      province: target.province,
      priorityRank: target.priorityRank,
      expectedSourceFamily: target.expectedSourceFamily,
      aliases: target.aliases,
      activeSourceIds,
      blockedReasonCode: blocked?.reasonCode ?? null,
      blockedReason: blocked?.reason ?? null,
      blockedSeverity: blocked?.severity ?? null,
      state,
      notes,
    };
  });
}
