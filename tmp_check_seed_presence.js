const admin = require('firebase-admin');
const fs = require('fs');
const sa = JSON.parse(fs.readFileSync('./secrets/digital-arhat-service-account.json', 'utf8'));
admin.initializeApp({ credential: admin.credential.cert(sa) });
(async () => {
  const db = admin.firestore();
  const snap = await db.collection('mandi_rates').orderBy('syncedAt', 'desc').limit(220).get();
  const docs = snap.docs.map((d) => ({ id: d.id, commodity: d.get('commodityName'), city: d.get('city'), unit: d.get('unit'), sourceId: d.get('sourceId'), source: d.get('source'), rank: d.get('sourcePriorityRank') }));
  const targets = docs.filter((d) => ['wheat_lahore','wheat_gujranwala','wheat_faisalabad','rice_lahore','rice_gujranwala','broiler_lahore','broiler_faisalabad','potato_lahore','potato_okara','onion_lahore','onion_gujranwala','tomato_lahore','tomato_faisalabad'].includes(d.id));
  console.log(JSON.stringify({ total: docs.length, targetHits: targets.length, targets }, null, 2));
  process.exit(0);
})().catch((e)=>{ console.error(e); process.exit(1); });
