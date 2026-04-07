const axios = require('axios');
const cheerio = require('cheerio');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK with Application Default Credentials
if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

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

async function scrapeAmis() {
  console.log("[AMIS] Starting scraper...");

  try {
    // Delete existing documents from this source
    const existingDocs = await db.collection('mandi_rates')
      .where('source', '==', 'amis_lahore_official')
      .get();
    
    const batch = db.batch();
    existingDocs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    console.log(`[AMIS] Deleted ${existingDocs.size} old records.`);

    for (const [id, info] of Object.entries(COMMODITY_MAP)) {
      const url = `http://www.amis.pk/ViewPrices.aspx?searchType=0&commodityId=${id}`;
      try {
        const response = await axios.get(url, { timeout: 15000 });
        const $ = cheerio.load(response.data);
        
        // Find the data table - typically the one with many rows
        // Based on the structure, we look for rows that contain city names
        $('tr').each((i, el) => {
          const cells = $(el).find('td');
          if (cells.length >= 5) {
            const cityText = $(cells[0]).text().trim();
            // Remove numbers from city name like "1 Lahore"
            const cityName = cityText.replace(/^\d+\s*/, '').trim();
            
            if (TARGET_CITIES.includes(cityName)) {
              const fqpPrice = parseFloat($(cells[4]).text().trim());
              
              if (!isNaN(fqpPrice) && fqpPrice > 0) {
                let finalPrice = 0;
                let finalUnit = "";

                if (info.unit === "per_40kg") {
                  finalPrice = (fqpPrice / 100) * 40;
                  finalUnit = "40kg";
                } else if (info.unit === "per_50kg") {
                  finalPrice = (fqpPrice / 100) * 50;
                  finalUnit = "50kg";
                } else if (info.unit === "per_kg") {
                  finalPrice = fqpPrice / 100;
                  finalUnit = "kg";
                }

                const docData = {
                  commodityName: info.name,
                  commodityNameUr: info.ur,
                  city: cityName,
                  district: cityName,
                  province: "Punjab",
                  price: finalPrice,
                  unit: finalUnit,
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
                    seedFallback: false
                  }
                };

                db.collection('mandi_rates').doc(docData.sourceId).set(docData);
                console.log(`[AMIS] ${info.name} ${cityName}: Rs.${finalPrice.toFixed(0)} ✓`);
              }
            }
          }
        });
      } catch (err) {
        console.error(`[AMIS] Error scraping commodity ${id} (${info.name}): ${err.message}`);
      }
    }
    console.log("[AMIS] Scraper finished successfully.");
  } catch (error) {
    console.error(`[AMIS] Fatal error: ${error.message}`);
  }
}

// Export for Cloud Functions or local run
if (require.main === module) {
  scrapeAmis();
} else {
  module.exports = { scrapeAmis };
}
