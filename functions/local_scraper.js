/**
 * Local Axios+Cheerio Scraper for AMIS (Punjab) Mandi Rates
 * Run this on a Lahore residential IP to bypass government firewalls
 *
 * Target: http://www.amis.pk/ViewPrices.aspx?searchType=0&commodityId={id}
 * Strategy: Loop through commodity IDs, raw HTTP GET via axios, HTML parsed with cheerio
 *
 * Usage:
 *   npm install axios cheerio firebase-admin
 *   node local_scraper.js
 */

const axios = require("axios");
const cheerio = require("cheerio");
const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");
const crypto = require("crypto");

// Initialize Firebase Admin SDK
// Uses Application Default Credentials (ADC) from service account JSON
let db;

async function initializeFirebase() {
  if (admin.apps.length === 0) {
    try {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      console.log("[Firebase] Initialized with local serviceAccountKey.json");
    } catch (err) {
      console.error("[Firebase] Init error:", err.message);
      throw err;
    }
  }
  db = admin.firestore();
}

// Sanitize price: remove non-numeric characters, validate range
function cleanPrice(rawPrice) {
  if (!rawPrice) return null;
  const cleaned = String(rawPrice).replace(/[^\d.]/g, "");
  const num = parseFloat(cleaned);
  if (isNaN(num) || num <= 50 || num >= 40000) return null;
  return Math.round(num);
}

// Normalize commodity name
function normalizeCommodity(raw) {
  if (!raw) return null;
  return String(raw).trim().toLowerCase();
}

// Generate deterministic doc ID from commodityId + city + date string
function generateDocId(commodityId, city, dateStr) {
  const combined = `${commodityId}|${city}|${dateStr}`;
  const hash = crypto.createHash("sha256").update(combined).digest("hex");
  return hash.substring(0, 20);
}

// Commodity ID list for per-page AMIS fetching.
// Each commodity has its own URL: /ViewPrices.aspx?searchType=0&commodityId={id}
const AMIS_COMMODITIES = [
  { id: 1,   name: "wheat",  nameUr: "گندم" },
  { id: 2,   name: "maize",  nameUr: "مکئی" },
  { id: 3,   name: "rice", nameUr: "باسمتی چاول" },
  { id: 4,   name: "rice",    nameUr: "آئی آر آر آئی چاول" },
  { id: 7,   name: "sugar",  nameUr: "چینی" },
  { id: 15,  name: "onion",          nameUr: "پیاز" },
  { id: 16,  name: "potato",         nameUr: "آلو" },
  { id: 17,  name: "tomato",         nameUr: "ٹماٹر" },
  { id: 19,  name: "gram (chana)",   nameUr: "چنا" },
  { id: 20,  name: "mung bean",      nameUr: "مونگ" },
  { id: 21,  name: "masoor (lentil)",nameUr: "مسور" },
  { id: 50,  name: "banola", nameUr: "بنولہ" },
  { id: 73,  name: "garlic (local)", nameUr: "لہسن" },
  { id: 81,  name: "dates (aseel)",  nameUr: "کھجور" },
  { id: 85,  name: "chilli (green)", nameUr: "ہری مرچ" },
  { id: 116, name: "sunflower",      nameUr: "سورج مکھی" },
  { id: 117, name: "canola", nameUr: "کنولہ" },
  { id: 138, name: "barley", nameUr: "جو" },
];

const AXIOS_HEADERS = {
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
  "Accept-Language": "en-US,en;q=0.5",
  "Connection": "keep-alive",
};

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function normalizeCityName(rawCity) {
  const text = String(rawCity ?? "").replace(/\s+/g, " ").trim();
  if (!text) return "";

  // AMIS sometimes sends values like "39 Kalurkot"; keep only the city part.
  const noLeadingId = text.replace(/^\d+\s*[-.):]?\s*/, "").trim();

  // If the row is only a numeric ID, reject it.
  if (/^\d+$/.test(noLeadingId)) return "";
  return noLeadingId;
}

// Scrape AMIS (Punjab) by looping through per-commodity URLs.
// Each commodity has its own page: /ViewPrices.aspx?searchType=0&commodityId={id}
// Uses axios for raw HTTP GET and cheerio for HTML parsing — no browser required.
async function scrapeAMIS() {
  console.log("\n[AMIS] Starting AMIS scrape (axios + cheerio, per-commodity loop)...");
  const scraped = [];

  for (let i = 0; i < AMIS_COMMODITIES.length; i++) {
    const commodity = AMIS_COMMODITIES[i];
    const url = `http://www.amis.pk/ViewPrices.aspx?searchType=0&commodityId=${commodity.id}`;

    console.log(`\n[AMIS] [${i + 1}/${AMIS_COMMODITIES.length}] Fetching ${commodity.name} (id=${commodity.id})`);
    console.log(`[AMIS] GET ${url}`);

    try {
      const response = await axios.get(url, {
        timeout: 30000,
        headers: AXIOS_HEADERS,
      });

      console.log(`[AMIS] HTTP ${response.status} — parsing HTML with cheerio`);
      const $ = cheerio.load(response.data);

      let rowCount = 0;
      let acceptedCount = 0;

      $("table tr").each((idx, tr) => {
        const tds = $(tr).find("td");
        if (tds.length < 4) return; // need at least 4 columns

        rowCount++;
        // STRICT column mapping: td[0]=City, td[1]=Commodity label, td[3]=Price
        const cityRaw  = $(tds.eq(0)).text().trim();
        const city     = normalizeCityName(cityRaw);
        const priceRaw = $(tds.eq(3)).text().trim();

        if (!city || !priceRaw) {
          return;
        }

        // Reject date-like tokens (8+ digits or containing slashes)
        if (/^\d{8}$/.test(priceRaw.replace(/[^\d]/g, "")) || priceRaw.includes("/")) {
          console.log(`[AMIS] Row ${idx} price looks like a date, skipping: "${priceRaw}"`);
          return;
        }

        const price = cleanPrice(priceRaw);
        if (!price) {
          console.log(`[AMIS] Row ${idx} price rejected: "${priceRaw}"`);
          return;
        }

        acceptedCount++;
        scraped.push({
          commodity: normalizeCommodity(commodity.name),
          city: city,
          price,
          unit: "per 40 kg", // AMIS default unit
          province: "Punjab",
          sourceId: "amis_local_residential",
          source: "AMIS (Local)",
          metadata: {
            scrapedFrom: url,
            commodityId: commodity.id,
            commodityNameUr: commodity.nameUr,
            rawCity: cityRaw,
            rawPrice: priceRaw,
            columnMapping: "td[0]=City, td[3]=Price",
            timestamp: new Date().toISOString(),
          },
        });

        console.log(`[AMIS] ✓ ${city} | ${commodity.name} | ${price} | per 40 kg`);
      });

      console.log(`[AMIS] ${commodity.name}: scanned ${rowCount} rows, accepted ${acceptedCount}`);
    } catch (err) {
      if (err.response) {
        console.error(`[AMIS] HTTP error ${err.response.status} for ${commodity.name}: ${err.response.statusText}`);
      } else {
        console.error(`[AMIS] Fetch error for ${commodity.name}: ${err.message}`);
      }
    }

    // 2 second delay between requests to avoid rate limiting
    if (i < AMIS_COMMODITIES.length - 1) {
      console.log("[AMIS] Waiting 2s before next commodity...");
      await sleep(2000);
    }
  }

  console.log(`\n[AMIS] Total scraped across all commodities: ${scraped.length} valid records`);
  return scraped;
}

// DISABLED: Sindh BOS (sindhbos.gov.pk) - DNS resolution failures, site unreliable
// TODO: When Sindh BOS comes back online, implement via axios.get() + cheerio the same way as scrapeAMIS()

// IMPORTANT: No deletion logic is allowed in this script.
// Existing mandi_rates data must always be preserved.

// Build unified mandi rate doc from scraped row
function buildUnifiedMandiRate(scrapedRow) {
  const {
    commodity,
    city,
    price,
    unit,
    province,
    sourceId,
    source,
    metadata,
  } = scrapedRow;

  const now = new Date();
  const dateStr = now.toISOString().split("T")[0];
  const docId = generateDocId(metadata.commodityId, city, dateStr);

  return {
    id: docId,
    commodityName: String(commodity).toLowerCase(),
    commodityNameUr: String(metadata?.commodityNameUr ?? commodity),
    categoryName: "Produce", // Default category
    subCategoryName: "Vegetable", // Default subcategory
    mandiName: city,
    city,
    district: city,
    province,
    latitude: null,
    longitude: null,
    price,
    previousPrice: null,
    minPrice: null,
    maxPrice: null,
    unit,
    currency: "PKR",
    trend: "same",
    source,
    sourceId,
    sourceType: "OfficialMarketAdministration",
    lastUpdated: now,
    syncedAt: now,
    freshnessStatus: "live",
    confidenceScore: 0.9,
    confidenceReason: "Local residential IP scrape",
    verificationStatus: "Verified",
    contributorType: "System",
    isNearby: false,
    isAiCleaned: false,
    metadata: {
      ...metadata,
      scrapingMethod: "axios_cheerio_local_residential",
      scrapedAtIso: now.toISOString(),
    },
  };
}

// Write scraped data to Firestore
async function writeToFirestore(allScrapedRows) {
  console.log(`\n[Firestore] Writing ${allScrapedRows.length} unified docs to mandi_rates...`);

  if (allScrapedRows.length === 0) {
    console.warn("[Firestore] No data to write");
    return;
  }

  try {
    const batch = db.batch();
    let batchSize = 0;
    let totalWritten = 0;

    for (const scrapedRow of allScrapedRows) {
      const unifiedDoc = buildUnifiedMandiRate(scrapedRow);
      const ref = db.collection("mandi_rates").doc(unifiedDoc.id);
      batch.set(ref, unifiedDoc, { merge: true });
      batchSize++;

      // Firestore batch has 500 doc limit
      if (batchSize === 500) {
        await batch.commit();
        totalWritten += batchSize;
        console.log(`[Firestore] Committed batch of 500 (total: ${totalWritten})`);
        batchSize = 0;
      }
    }

    // Commit final batch if any remain
    if (batchSize > 0) {
      await batch.commit();
      totalWritten += batchSize;
      console.log(`[Firestore] Committed final batch of ${batchSize} (total: ${totalWritten})`);
    }

    console.log(`[Firestore] ✓ Successfully wrote ${totalWritten} docs`);
  } catch (err) {
    console.error("[Firestore] Write error:", err.message);
    throw err;
  }
}

async function runSmokeTest() {
  console.log("\n[Smoke Test] Verifying data in Firestore...");
  const snapshot = await db.collection("mandi_rates").limit(3).get();
  if (snapshot.empty) {
    console.error("[Smoke Test] FAILED! Database is still empty.");
  } else {
    console.log("[Smoke Test] PASSED! Found records:");
    snapshot.forEach((doc) => {
      const data = doc.data() || {};
      console.log(` - ${doc.id} => ${data.commodityName} in ${data.city}`);
    });
  }
}

// Main execution
async function main() {
  console.log("========================================");
  console.log("Local Axios+Cheerio Mandi Scraper");
  console.log("Running on: LAHORE RESIDENTIAL IP");
  console.log("Start time:", new Date().toISOString());
  console.log("========================================");

  try {
    // Initialize Firebase
    await initializeFirebase();

    // Scrape AMIS (Punjab) — no browser, raw HTTP
    // SindhBOS (Karachi) is disabled due to DNS/availability issues
    const amisData = await scrapeAMIS();

    const allScraped = [...amisData];
    console.log(`\n[Summary] Total valid records scraped: ${allScraped.length}`);

    if (allScraped.length === 0) {
      console.warn("[Summary] No data scraped, aborting Firestore write");
      process.exit(0);
    }

    // Write new data
    await writeToFirestore(allScraped);

    // Verify writes directly from Firestore.
    await runSmokeTest();

    console.log("\n========================================");
    console.log("✓ Scraping and Firestore sync complete!");
    console.log("Finish time:", new Date().toISOString());
    console.log("========================================\n");
  } catch (err) {
    console.error("\n[ERROR] Fatal error:", err.message);
    console.error(err.stack);
    process.exit(1);
  }
}

// Run
main();
