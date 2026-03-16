import {scrapeAmisRates} from "./amis_scraper";
import {AdapterContext, OfficialSourceAdapter, RawSourceRow} from "./types";

const SOURCE_ID = "amis_official";

export class AmisOfficialAdapter implements OfficialSourceAdapter {
  async fetchRows(context: AdapterContext): Promise<RawSourceRow[]> {
    const result = await scrapeAmisRates();
    context.logger("source_fetched", {
      sourceId: SOURCE_ID,
      rawRows: result.rawRows,
      newestTimestamp: result.newestTimestamp?.toISOString() ?? null,
      sourceUrl: result.sourceUrl,
    });

    return result.records
      .map((item): RawSourceRow | null => {
        const commodity = String(item.commodityName ?? "").trim();
        const mandiName = String(item.mandiName ?? item.city ?? "").trim();
        const city = String(item.city ?? "").trim();
        const price = Number(item.price ?? 0);
        if (!commodity || !mandiName || !city || !Number.isFinite(price) || price <= 0) {
          return null;
        }

        const avgPriceRaw = Number(item.metadata["averagePrice"] ?? item.metadata["average"] ?? 0);
        const minPriceRaw = Number(item.metadata["minPrice"] ?? 0);
        const maxPriceRaw = Number(item.metadata["maxPrice"] ?? 0);

        return {
          sourceId: SOURCE_ID,
          sourceType: "official_aggregator",
          sourceName: "AMIS Official",
          commodityName: commodity,
          categoryName: "crops",
          subCategoryName: "other",
          mandiName,
          city,
          district: String(item.district ?? city),
          province: String(item.province ?? "Punjab"),
          price,
          previousPrice: null,
          minPrice: Number.isFinite(minPriceRaw) && minPriceRaw > 0 ? minPriceRaw : null,
          maxPrice: Number.isFinite(maxPriceRaw) && maxPriceRaw > 0 ? maxPriceRaw : null,
          unit: String(item.unit ?? "PKR/100kg"),
          currency: "PKR",
          trend: "same",
          lastUpdated: item.rateDate instanceof Date ? item.rateDate : context.now,
          metadata: {
            ...item.metadata,
            sourceUrl: result.sourceUrl,
            sourceColumns: result.columns,
            commodityRefId: item.commodityId,
            averagePrice: Number.isFinite(avgPriceRaw) && avgPriceRaw > 0 ? avgPriceRaw : null,
          },
        };
      })
      .filter((item): item is RawSourceRow => item != null);
  }
}
