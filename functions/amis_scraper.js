const axios = require('axios');
const cheerio = require('cheerio');
const admin = require('firebase-admin');
const fs = require('fs');

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
  console.log('[START] Scraper starting...');
  const db = initFirebaseAdminFromWorkflowSecret();

  try {
    const existingDocs = await db.collection('mandi_rates')
      .where('source', '==', 'amis_lahore_official')
      .get();

    const recordsToWrite = [];

    for (const [id, info] of Object.entries(COMMODITY_MAP)) {
      let rowsFound = 0;
      const url = `http://www.amis.pk/ViewPrices.aspx?searchType=0&commodityId=${id}`;
      try {
        const response = await axios.get(url, { timeout: 15000 });
        const $ = cheerio.load(response.data);

        $('tr').each((i, el) => {
          const cells = $(el).find('td');
          if (cells.length >= 5) {
            const cityText = $(cells[0]).text().trim();
            const cityName = cityText.replace(/^\d+\s*/, '').trim();

            if (TARGET_CITIES.includes(cityName)) {
              const rawPrice = parseFloat($(cells[4]).text().trim());

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

    const totalRecords = recordsToWrite.length;
    if (totalRecords === 0) {
      console.error('[FATAL] totalRecords is 0. Exiting.');
      process.exit(1);
    }

    console.log('[FIREBASE] Writing ' + totalRecords + ' records...');

    const batch = db.batch();
    existingDocs.forEach(doc => batch.delete(doc.ref));
    recordsToWrite.forEach(docData => {
      batch.set(db.collection('mandi_rates').doc(docData.sourceId), docData);
    });

    try {
      await batch.commit();
    } catch (error) {
      console.error('[FIREBASE] Batch commit failed:', error);
      process.exit(1);
    }

    console.log('[SUCCESS] Done!');
  } catch (error) {
    console.error(`[AMIS] Fatal error: ${error.message}`);
    process.exit(1);
  }
}

// Export for Cloud Functions or local run
if (require.main === module) {
  scrapeAmis();
} else {
  module.exports = { scrapeAmis };
}
