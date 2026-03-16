const { scrapeAmisRates } = require('./functions/lib/sources/amis_scraper.js');

const slug = (s) => String(s || '').trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
const normCommodity = (v) => {
  const raw = String(v || '').toLowerCase();
  if (raw.includes('wheat') || raw.includes('gandum') || raw.includes('\u06af\u0646\u062f\u0645')) return 'Wheat';
  if (raw.includes('rice') || raw.includes('chawal') || raw.includes('\u0686\u0627\u0648\u0644') || raw.includes('basmati') || raw.includes('irri')) return 'Rice';
  if (raw.includes('corn') || raw.includes('maize') || raw.includes('makai') || raw.includes('\u0645\u06a9\u0626\u06cc') || raw.includes('\u0645\u06a9\u06cc')) return 'Corn';
  return v;
};

scrapeAmisRates().then((r) => {
  const map = new Map();
  for (const x of r.records) {
    const commodityName = normCommodity(x.commodityName);
    const mandiName = (x.mandiName || x.city || 'Unknown Mandi').trim();
    const city = (x.city || mandiName).trim();
    const district = (x.district || city).trim();
    const province = (x.province || 'Punjab').trim();
    const rateDay = new Date(x.rateDate).toISOString().slice(0, 10);
    const id = [slug('amis_scrape'), slug(commodityName), slug(mandiName), slug(city || district || province || 'pakistan'), slug(rateDay)].join('_');
    const item = {
      id,
      commodityName,
      mandiName,
      city,
      district,
      province,
      price: x.price,
      unit: 'per 100kg',
      rateDate: new Date(x.rateDate).toISOString(),
      source: 'amis_scrape'
    };
    map.set(id, item);
  }

  const vals = Array.from(map.values());
  console.log(JSON.stringify({
    rawRows: r.rawRows,
    normalizedRows: vals.length,
    newestTimestamp: r.newestTimestamp ? new Date(r.newestTimestamp).toISOString() : null,
    sample: vals.slice(0, 5)
  }, null, 2));
}).catch((e) => {
  console.error(String(e && e.message ? e.message : e));
  process.exit(1);
});
