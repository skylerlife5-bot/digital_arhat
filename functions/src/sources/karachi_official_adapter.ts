import {AdapterContext, OfficialSourceAdapter, RawSourceRow} from "./types";

const SOURCE_ID = "karachi_official_price_lists";
const DEFAULT_URL = "https://commissionerkarachi.gos.pk/karachi/pricelist";

function cleanCell(input: string): string {
  return input
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/\s+/g, " ")
    .trim();
}

function toFinite(value: string): number | null {
  const parsed = Number.parseFloat(
    value
      .replace(/,/g, "")
      .replace(/rs\.?/gi, "")
      .replace(/pkr/gi, "")
      .replace(/[^\d.+-]/g, ""),
  );
  return Number.isFinite(parsed) ? parsed : null;
}

function parseRows(html: string, now: Date): RawSourceRow[] {
  const out: RawSourceRow[] = [];
  const trRegex = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
  let trMatch: RegExpExecArray | null;
  while ((trMatch = trRegex.exec(html)) != null) {
    const rowHtml = trMatch[1];
    const tdRegex = /<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi;
    const cells: string[] = [];
    let tdMatch: RegExpExecArray | null;
    while ((tdMatch = tdRegex.exec(rowHtml)) != null) {
      cells.push(cleanCell(tdMatch[1]));
    }
    if (cells.length < 2) continue;

    const commodity = cells[0];
    const price = cells
      .map((cell) => toFinite(cell))
      .find((num) => num != null && num > 0) ?? null;

    if (!commodity || price == null) continue;

    out.push({
      sourceId: SOURCE_ID,
      sourceType: "official_commissioner",
      sourceName: "Karachi Official Price Lists",
      commodityName: commodity,
      categoryName: "fruits_vegetables_essentials",
      subCategoryName: "official_list",
      mandiName: "Karachi Commissioner Price List",
      city: "Karachi",
      district: "Karachi",
      province: "Sindh",
      price,
      previousPrice: null,
      unit: "PKR/kg",
      currency: "PKR",
      trend: "same",
      lastUpdated: now,
      metadata: {
        parser: "html_table_scan",
      },
    });
  }

  return out;
}

export class KarachiOfficialAdapter implements OfficialSourceAdapter {
  async fetchRows(context: AdapterContext): Promise<RawSourceRow[]> {
    const sourceUrl = String(process.env.KARACHI_OFFICIAL_SOURCE_URL ?? DEFAULT_URL).trim();
    const response = await fetch(sourceUrl, {
      method: "GET",
      headers: {
        "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "user-agent": "digital-arhat-functions/1.0",
      },
    });
    if (!response.ok) {
      throw new Error(`karachi_official_http_${response.status}`);
    }

    const html = await response.text();
    const underConstruction = /website\s+is\s+under\s+construction/i.test(html);
    const rows = parseRows(html, context.now).map((item) => ({
      ...item,
      metadata: {
        ...(item.metadata ?? {}),
        sourceUrl,
      },
    }));

    if (rows.length === 0 && underConstruction) {
      throw new Error("karachi_official_source_under_construction");
    }

    context.logger("source_fetched", {
      sourceId: SOURCE_ID,
      rawRows: rows.length,
      sourceUrl,
      underConstruction,
    });

    return rows;
  }
}
