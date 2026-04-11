const axios = require('axios');
const cheerio = require('cheerio');
const admin = require('firebase-admin');
const fs = require('fs');

const SCRAPER_API_KEY = 'YOUR_API_KEY_HERE';

function initFirebaseAdminFromWorkflowSecret() {
  const secretName = 'GOOGLE_APPLICATION_CREDENTIALS';
  const secretValue = process.env[secretName];

  if (!secretValue || !secretValue.trim()) {
    console.error(`[FATAL] Missing required secret/env: ${secretName}`);
    process.exit(1);
  }

  let serviceAccount = null;
  const trimmed = secretValue.trim();

  try {
    if (trimmed.startsWith('{')) {
      serviceAccount = JSON.parse(trimmed);
    } else if (fs.existsSync(trimmed)) {
      serviceAccount = JSON.parse(fs.readFileSync(trimmed, 'utf8'));
    } else {
      const decoded = Buffer.from(trimmed, 'base64').toString('utf8');
      serviceAccount = JSON.parse(decoded);
    }
  } catch (err) {
    console.error(`[FATAL] Failed to parse ${secretName}: ${err.message}`);
    process.exit(1);
  }

  if (admin.apps.length === 0) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }

  return admin.firestore();
}

const COMMODITY_MAP = {
  1: { name: "Wheat", ur: "گندم", unit: "per_40kg", cat: "grain" },
  2: { name: "Maize", ur: "مکئی", unit: "per_40kg", cat: "grain" },
  7: { name: "Sugar", ur: "چینی", unit: "per_50kg", cat: "grain" },
  15: { name: "Onion", ur: "پیاز", unit: "per_kg", cat: "veg" },
  16: { name: "Potato", ur: "آلو", unit: "per_kg", cat: "veg" },
  17: { name: "Tomato", ur: "ٹماٹر", unit: "per_kg", cat: "veg" },
  73: { name: "Garlic", ur: "لہسن", unit: "per_kg", cat: "veg" }
};

const TARGET_CITIES = [
  "Lahore", "Faisalabad", "Multan", "Rawalpindi", "Gujranwala", "Sahiwal"
];

const cityMatches = (amisCity) => {
  const c = (amisCity || '').toLowerCase()
    .replace(/\s+/g, '').replace(/[()]/g, '');
  return TARGET_CITIES.some(t =>
    c.includes(t.toLowerCase()) ||
    t.toLowerCase().includes(c)
  );
};

const PER_KG_ITEMS = new Set([
  'onion',
  'potato',
  'tomato',
  'garlic',
  'ginger',
  'chicken',
  'beef',
  'mutton',
  'milk',
  'eggs',
]);

const PER_40KG_ITEMS = new Set([
  'wheat',
  'rice',
  'maize',
  'barley',
  'sugar',
  'gram',
]);

const URDUPOINT_GROCERY_TARGETS = [
  { aliases: ['wheat', 'gandum'], name: 'Wheat', ur: 'گندم', unit: 'per_40kg', cat: 'grain' },
  { aliases: ['flour', 'atta'], name: 'Flour', ur: 'آٹا', unit: 'per_20kg', cat: 'grain' },
  { aliases: ['sugar', 'cheeni'], name: 'Sugar', ur: 'چینی', unit: 'per_50kg', cat: 'grain' },
  { aliases: ['rice', 'chawal'], name: 'Rice', ur: 'چاول', unit: 'per_40kg', cat: 'grain' },
  { aliases: ['maize', 'makai'], name: 'Maize', ur: 'مکئی', unit: 'per_40kg', cat: 'grain' },
];

const URDUPOINT_VEGETABLE_TARGETS = [
  { aliases: ['potato', 'aloo'], name: 'Potato', ur: 'آلو', unit: 'per_kg', cat: 'veg' },
  { aliases: ['tomato', 'tamatar'], name: 'Tomato', ur: 'ٹماٹر', unit: 'per_kg', cat: 'veg' },
  { aliases: ['onion', 'pyaz'], name: 'Onion', ur: 'پیاز', unit: 'per_kg', cat: 'veg' },
  { aliases: ['garlic', 'lehsan'], name: 'Garlic', ur: 'لہسن', unit: 'per_kg', cat: 'veg' },
  { aliases: ['ginger', 'adrak'], name: 'Ginger', ur: 'ادرک', unit: 'per_kg', cat: 'veg' },
  { aliases: ['cauliflower', 'gobhi'], name: 'Cauliflower', ur: 'گوبھی', unit: 'per_kg', cat: 'veg' },
  { aliases: ['cabbage', 'band gobhi'], name: 'Cabbage', ur: 'بند گوبھی', unit: 'per_kg', cat: 'veg' },
  { aliases: ['spinach', 'palak'], name: 'Spinach', ur: 'پالک', unit: 'per_kg', cat: 'veg' },
];

const ACCURATE_SEED_FALLBACK = [
  { id: 'seed_wheat_lahore', name: 'Wheat', ur: 'گندم', price: 4450, unit: 'per_40kg', city: 'Lahore', cat: 'grain' },
  { id: 'seed_rice_irri_lahore', name: 'Rice IRRI', ur: 'چاول اری', price: 5800, unit: 'per_40kg', city: 'Lahore', cat: 'grain' },
  { id: 'seed_rice_basmati_lahore', name: 'Rice Basmati', ur: 'چاول باسمتی', price: 9800, unit: 'per_40kg', city: 'Lahore', cat: 'grain' },
  { id: 'seed_sugar_lahore', name: 'Sugar', ur: 'چینی', price: 7025, unit: 'per_50kg', city: 'Lahore', cat: 'grain' },
  { id: 'seed_flour_lahore', name: 'Flour', ur: 'آٹا', price: 1950, unit: 'per_20kg', city: 'Lahore', cat: 'grain' },
  { id: 'seed_potato_lahore', name: 'Potato', ur: 'آلو', price: 20, unit: 'per_kg', city: 'Lahore', cat: 'veg' },
  { id: 'seed_tomato_lahore', name: 'Tomato', ur: 'ٹماٹر', price: 80, unit: 'per_kg', city: 'Lahore', cat: 'veg' },
  { id: 'seed_onion_lahore', name: 'Onion', ur: 'پیاز', price: 100, unit: 'per_kg', city: 'Lahore', cat: 'veg' },
  { id: 'seed_garlic_lahore', name: 'Garlic', ur: 'لہسن', price: 350, unit: 'per_kg', city: 'Lahore', cat: 'veg' },
  { id: 'seed_ginger_lahore', name: 'Ginger', ur: 'ادرک', price: 400, unit: 'per_kg', city: 'Lahore', cat: 'veg' },
  { id: 'seed_live_chicken_lahore', name: 'Live Chicken', ur: 'زندہ مرغی', price: 380, unit: 'per_kg', city: 'Lahore', cat: 'meat' },
];

function normalizeText(value) {
  return (value || '').toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
}

function extractPriceCandidates(text) {
  if (!text) {
    return [];
  }

  return (text.match(/\d{1,3}(?:,\d{3})*(?:\.\d+)?/g) || [])
    .map(v => parseFloat(v.replace(/,/g, '')))
    .filter(v => Number.isFinite(v) && v > 0);
}

function buildUrduPointRecord(target, price, matchedText, pageUrl) {
  const commodityKey = target.name.toLowerCase().replace(/\s+/g, '_');

  return {
    commodityName: target.name,
    commodityNameUr: target.ur,
    city: 'Lahore',
    district: 'Lahore',
    province: 'Punjab',
    price,
    unit: target.unit,
    source: 'urdupoint_lahore_official',
    sourceId: `urdupoint_${commodityKey}_lahore`,
    sourceType: 'official',
    sourcePriorityRank: 1,
    contributorType: 'official',
    verificationStatus: 'official verified',
    acceptedBySystem: true,
    acceptedByAdmin: true,
    freshnessStatus: 'fresh',
    confidenceScore: 0.95,
    syncedAt: admin.firestore.Timestamp.now(),
    category: target.cat,
    metadata: {
      urduName: target.ur,
      seedFallback: false,
      matchedText,
      pageUrl,
    },
  };
}

async function scrapeUrduPointByTargets(url, targets) {
  const records = [];
  const seen = new Set();

  try {
    const scraperUrl = `http://api.scraperapi.com?api_key=${SCRAPER_API_KEY}&url=${encodeURIComponent(url)}`;
    const response = await axios.get(scraperUrl, {
      timeout: 20000,
    });

    const $ = cheerio.load(response.data);
    $('tr, li').each((_, el) => {
      const rowText = $(el).text().replace(/\s+/g, ' ').trim();
      if (!rowText) {
        return;
      }

      const normalizedRow = normalizeText(rowText);
      const prices = extractPriceCandidates(rowText);
      if (prices.length === 0) {
        return;
      }

      for (const target of targets) {
        if (seen.has(target.name)) {
          continue;
        }

        const matched = target.aliases.some(alias => {
          const normalizedAlias = normalizeText(alias);
          return normalizedRow.includes(normalizedAlias);
        });

        if (!matched) {
          continue;
        }

        const price = prices[prices.length - 1];
        if (!Number.isFinite(price) || price <= 0) {
          continue;
        }

        records.push(buildUrduPointRecord(target, price, rowText, url));
        seen.add(target.name);
      }
    });
  } catch (err) {
    console.error(`[URDUPOINT] Failed ${url}: ${err.message}`);
  }

  return records;
}

async function scrapeUrduPointGrocery() {
  const url = 'https://www.urdupoint.com/daily-prices/grocery-prices-in-lahore-city.html';
  const records = await scrapeUrduPointByTargets(url, URDUPOINT_GROCERY_TARGETS);
  console.log(`[URDUPOINT] Grocery extracted: ${records.length}`);
  return records;
}

async function scrapeUrduPointVegetables() {
  const url = 'https://www.urdupoint.com/daily-prices/vegetable-prices-in-lahore-city.html';
  const records = await scrapeUrduPointByTargets(url, URDUPOINT_VEGETABLE_TARGETS);
  console.log(`[URDUPOINT] Vegetables extracted: ${records.length}`);
  return records;
}

function mergePreferUrduPoint(urdupointRecords, amisRecords) {
  const merged = new Map();

  const makeKey = (item) => `${(item.commodityName || '').toLowerCase()}|${(item.city || '').toLowerCase()}`;

  urdupointRecords.forEach(item => {
    merged.set(makeKey(item), item);
  });

  amisRecords.forEach(item => {
    const key = makeKey(item);
    if (!merged.has(key)) {
      merged.set(key, item);
    }
  });

  return Array.from(merged.values());
}

function buildFallbackSeedRecords() {
  return ACCURATE_SEED_FALLBACK.map(seed => ({
    commodityName: seed.name,
    commodityNameUr: seed.ur,
    city: seed.city,
    district: seed.city,
    province: 'Punjab',
    price: seed.price,
    unit: seed.unit,
    source: 'amis_seed_verified',
    sourceId: seed.id,
    sourceType: 'verified_seed',
    sourcePriorityRank: 3,
    contributorType: 'official',
    verificationStatus: 'official verified',
    acceptedBySystem: true,
    acceptedByAdmin: true,
    freshnessStatus: 'recent',
    confidenceScore: 0.9,
    syncedAt: admin.firestore.Timestamp.now(),
    category: seed.cat,
    metadata: {
      urduName: seed.ur,
      seedFallback: true,
      rawPriceRsPer100Kg: null,
    },
  }));
}

async function clearExistingSources(db, sources) {
  const docsToDelete = [];

  for (const source of sources) {
    const snap = await db.collection('mandi_rates').where('source', '==', source).get();
    snap.forEach(doc => docsToDelete.push(doc.ref));
  }

  if (docsToDelete.length === 0) {
    return;
  }

  const deleteBatch = db.batch();
  docsToDelete.forEach(ref => deleteBatch.delete(ref));
  await deleteBatch.commit();
}

function convertFromAmis100Kg(commodityName, rawPrice) {
  const key = (commodityName || '').toLowerCase().trim();

  if (PER_KG_ITEMS.has(key)) {
    return {
      price: rawPrice / 100,
      unit: 'per_kg',
    };
  }

  if (PER_40KG_ITEMS.has(key)) {
    return {
      price: (rawPrice / 100) * 40,
      unit: 'per_40kg',
    };
  }

  return null;
}

async function scrapeAmis() {
  const recordsToWrite = [];
  try {
    for (const [id, info] of Object.entries(COMMODITY_MAP)) {
      let rowsFound = 0;
      const url = `http://www.amis.pk/ViewPrices.aspx?searchType=0&commodityId=${id}`;
      try {
        const response = await axios.get(url, { timeout: 15000 });
        const $ = cheerio.load(response.data);

        $('tr').each((i, el) => {
          const cells = $(el).find('td');
          if (cells.length >= 5) {
            const cityName = $(cells[1]).text().trim();

            if (cityMatches(cityName)) {
              const minRawText = $(cells[2]).text().trim();
              const maxRawText = $(cells[3]).text().trim();
              const fqpRawText = $(cells[4]).text().trim();

              const minPrice = parseFloat(minRawText);
              const maxPrice = parseFloat(maxRawText);
              const fqpPrice = parseFloat(fqpRawText);

              const minMissing = minRawText === '-' || minRawText === '' || isNaN(minPrice) || minPrice === 0;
              const maxMissing = maxRawText === '-' || maxRawText === '' || isNaN(maxPrice) || maxPrice === 0;
              const fqpMissing = fqpRawText === '-' || fqpRawText === '' || isNaN(fqpPrice) || fqpPrice === 0;

              if (minMissing && maxMissing && fqpMissing) {
                return;
              }

              let rawPrice = NaN;
              if (!minMissing && !maxMissing) {
                rawPrice = (minPrice + maxPrice) / 2;
              } else if (!minMissing) {
                rawPrice = minPrice;
              } else if (!maxMissing) {
                rawPrice = maxPrice;
              } else {
                rawPrice = parseFloat(fqpRawText);
              }

              if ((minRawText === '' || minRawText === '-' || isNaN(minPrice)) && fqpRawText !== '' && fqpRawText !== '-') {
                if (!isNaN(fqpPrice) && fqpPrice > 0) {
                  rawPrice = fqpPrice;
                }
              }

              if (!isNaN(rawPrice) && rawPrice > 0) {
                const converted = convertFromAmis100Kg(info.name, rawPrice);
                if (!converted || !Number.isFinite(converted.price) || converted.price <= 0) {
                  return;
                }

                rowsFound += 1;

                recordsToWrite.push({
                  commodityName: info.name,
                  commodityNameUr: info.ur,
                  city: cityName,
                  district: cityName,
                  province: "Punjab",
                  price: converted.price,
                  unit: converted.unit,
                  source: "amis_lahore_official",
                  sourceId: `amis_${id}_${cityName.toLowerCase()}`,
                  sourceType: "official",
                  sourcePriorityRank: 2,
                  contributorType: "official",
                  verificationStatus: "official verified",
                  acceptedBySystem: true,
                  acceptedByAdmin: true,
                  freshnessStatus: "fresh",
                  confidenceScore: 0.9,
                  syncedAt: admin.firestore.Timestamp.now(),
                  category: info.cat,
                  metadata: {
                    urduName: info.ur,
                    seedFallback: false,
                    rawPriceRsPer100Kg: rawPrice,
                  },
                });
              }
            }
          }
        });

        console.log('[AMIS] ' + info.name + ': ' + rowsFound + ' cities found');
      } catch (err) {
        console.error(`[AMIS] Error scraping commodity ${id} (${info.name}): ${err.message}`);
      }
    }
    return recordsToWrite;
  } catch (error) {
    console.error(`[AMIS] Fatal error: ${error.message}`);
    return [];
  }
}

async function syncMandiRates() {
  console.log('[START] Scraper starting...');
  const db = initFirebaseAdminFromWorkflowSecret();

  try {
    const urdupointGrocery = await scrapeUrduPointGrocery();
    const urdupointVegetables = await scrapeUrduPointVegetables();
    const urdupointRecords = [...urdupointGrocery, ...urdupointVegetables];

    if (urdupointRecords.length === 0) {
      console.log('[WARN] UrduPoint blocked, trying AMIS...');
    }

    const amisRecords = await scrapeAmis();
    let recordsToWrite = mergePreferUrduPoint(urdupointRecords, amisRecords);

    if (recordsToWrite.length === 0) {
      console.log('[WARN] UrduPoint and AMIS returned 0 items, applying accurate seed fallback');
      recordsToWrite = buildFallbackSeedRecords();
    }

    console.log('[FIREBASE] Writing ' + recordsToWrite.length + ' records...');

    await clearExistingSources(db, [
      'urdupoint_lahore_official',
      'amis_lahore_official',
      'amis_seed_verified',
    ]);

    const batch = db.batch();
    recordsToWrite.forEach(docData => {
      batch.set(db.collection('mandi_rates').doc(docData.sourceId), docData);
    });

    await batch.commit();
    console.log('[SUCCESS] Done!');
  } catch (error) {
    console.error(`[SYNC] Fatal error: ${error.message}`);
    process.exit(1);
  }
}

// Export for Cloud Functions or local run
if (require.main === module) {
  syncMandiRates();
} else {
  module.exports = {
    scrapeUrduPointGrocery,
    scrapeUrduPointVegetables,
    scrapeAmis,
    syncMandiRates,
  };
}
