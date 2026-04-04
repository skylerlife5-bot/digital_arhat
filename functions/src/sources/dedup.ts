import {UnifiedMandiRate} from "./types";
import {normalizeCommodityName, normalizeLocationToken, normalizeUnit} from "./normalization";

export type DedupedRate = UnifiedMandiRate & {
  corroborationCount: number;
  sameCityCorroboration: number;
  sameMandiCorroboration: number;
  multiSourceCorroboration: number;
  duplicateAgreement: number;
  sparseData: boolean;
  suspiciousSpike: boolean;
  incompleteMetadata: boolean;
};

const SOURCE_PRIORITY: Record<string, number> = {
  // Primary: FS&CPD official district notified rates
  fscpd_official: 5,
  // Secondary: Punjab AMIS
  amis_official: 4,
  // Valid city official lists
  lahore_official_market_rates: 3,
  karachi_official_price_lists: 2,
  // Fallback trend-only source
  pbs_spi: 1,
};

function confidenceRank(item: UnifiedMandiRate): number {
  const direct = Number(item.confidenceScore ?? 0);
  if (Number.isFinite(direct) && direct > 0) return direct;
  const fromMeta = Number(item.metadata?.sourceConfidence ?? item.metadata?.confidence ?? 0);
  if (Number.isFinite(fromMeta) && fromMeta > 0) return fromMeta;
  return 0;
}

function freshnessRank(status: UnifiedMandiRate["freshnessStatus"]): number {
  if (status === "live") return 4;
  if (status === "recent") return 3;
  if (status === "aging") return 2;
  return 1;
}

function chooseBetter(a: UnifiedMandiRate, b: UnifiedMandiRate): UnifiedMandiRate {
  const priorityA = SOURCE_PRIORITY[a.sourceId] ?? 1;
  const priorityB = SOURCE_PRIORITY[b.sourceId] ?? 1;
  if (priorityA !== priorityB) return priorityA > priorityB ? a : b;

  const freshnessA = freshnessRank(a.freshnessStatus);
  const freshnessB = freshnessRank(b.freshnessStatus);
  if (freshnessA !== freshnessB) return freshnessA > freshnessB ? a : b;

  const confidenceA = confidenceRank(a);
  const confidenceB = confidenceRank(b);
  if (confidenceA !== confidenceB) return confidenceA > confidenceB ? a : b;

  if (a.lastUpdated.getTime() !== b.lastUpdated.getTime()) {
    return a.lastUpdated > b.lastUpdated ? a : b;
  }

  return a;
}

function comparableKey(item: UnifiedMandiRate): string {
  return [
    normalizeCommodityName(item.commodityName).toLowerCase(),
    normalizeUnit(item.unit),
    (item.categoryName || "").toLowerCase(),
    (item.subCategoryName || "").toLowerCase(),
    normalizeLocationToken(item.city),
    normalizeLocationToken(item.mandiName),
  ].join("|");
}

function cityCommodityKey(item: UnifiedMandiRate): string {
  return [
    normalizeCommodityName(item.commodityName).toLowerCase(),
    normalizeUnit(item.unit),
    normalizeLocationToken(item.city),
  ].join("|");
}

function mandiCommodityKey(item: UnifiedMandiRate): string {
  return [
    normalizeCommodityName(item.commodityName).toLowerCase(),
    normalizeUnit(item.unit),
    normalizeLocationToken(item.mandiName),
  ].join("|");
}

function metadataIncomplete(item: UnifiedMandiRate): boolean {
  return !item.city.trim() ||
    !item.mandiName.trim() ||
    !item.categoryName.trim() ||
    !item.subCategoryName.trim() ||
    !item.unit.trim();
}

export function dedupeAndAnnotate(input: UnifiedMandiRate[]): DedupedRate[] {
  const grouped = new Map<string, UnifiedMandiRate[]>();
  const cityGrouped = new Map<string, UnifiedMandiRate[]>();
  const mandiGrouped = new Map<string, UnifiedMandiRate[]>();
  for (const item of input) {
    const key = comparableKey(item);
    const arr = grouped.get(key) ?? [];
    arr.push(item);
    grouped.set(key, arr);

    const cityKey = cityCommodityKey(item);
    const cityArr = cityGrouped.get(cityKey) ?? [];
    cityArr.push(item);
    cityGrouped.set(cityKey, cityArr);

    const mandiKey = mandiCommodityKey(item);
    const mandiArr = mandiGrouped.get(mandiKey) ?? [];
    mandiArr.push(item);
    mandiGrouped.set(mandiKey, mandiArr);
  }

  const out: DedupedRate[] = [];
  for (const rates of grouped.values()) {
    if (rates.length === 0) continue;
    const selected = rates.reduce((best, next) => chooseBetter(best, next));
    const corroborationCount = rates.length;
    const sameCityCorroboration = cityGrouped.get(cityCommodityKey(selected))?.length ?? 1;
    const sameMandiCorroboration = mandiGrouped.get(mandiCommodityKey(selected))?.length ?? 1;
    const uniqueSourceIds = new Set(rates.map((item) => item.sourceId).filter((item) => item.trim()));
    const multiSourceCorroboration = uniqueSourceIds.size;

    const prices = rates.map((item) => item.price).filter((value) => value > 0);
    const avg = prices.reduce((sum, value) => sum + value, 0) / (prices.length || 1);
    const deviation = avg > 0 ? Math.abs(selected.price - avg) / avg : 0;
    const duplicateAgreement = Math.max(0, 1 - Math.min(1, deviation));
    const incompleteMetadata = metadataIncomplete(selected);

    out.push({
      ...selected,
      corroborationCount,
      sameCityCorroboration,
      sameMandiCorroboration,
      multiSourceCorroboration,
      duplicateAgreement: Number(duplicateAgreement.toFixed(3)),
      sparseData: rates.length < 2 || uniqueSourceIds.size < 1,
      suspiciousSpike: deviation > 0.6,
      incompleteMetadata,
      metadata: {
        ...selected.metadata,
        comparableBucketSize: rates.length,
        sameCityBucketSize: sameCityCorroboration,
        sameMandiBucketSize: sameMandiCorroboration,
        multiSourceBucketSize: multiSourceCorroboration,
        duplicateAgreement: Number(duplicateAgreement.toFixed(3)),
        incompleteMetadata,
        comparableAvgPrice: Number(avg.toFixed(2)),
        comparableDeviation: Number(deviation.toFixed(3)),
      },
    });
  }

  return out;
}
