#!/usr/bin/env node

const fs = require('node:fs');
const admin = require('firebase-admin');

const TARGETS = new Set([
  'wheat_lahore',
  'wheat_gujranwala',
  'wheat_faisalabad',
  'rice_lahore',
  'rice_gujranwala',
  'broiler_lahore',
  'broiler_faisalabad',
  'potato_lahore',
  'potato_okara',
  'onion_lahore',
  'onion_gujranwala',
  'tomato_lahore',
  'tomato_faisalabad',
]);

async function main() {
  const sa = JSON.parse(fs.readFileSync('./secrets/digital-arhat-service-account.json', 'utf8'));
  admin.initializeApp({credential: admin.credential.cert(sa)});

  const snap = await admin
    .firestore()
    .collection('mandi_rates')
    .orderBy('syncedAt', 'desc')
    .limit(220)
    .get();

  const rows = snap.docs.map((doc) => ({
    id: doc.id,
    commodityName: doc.get('commodityName') || null,
    city: doc.get('city') || null,
    unit: doc.get('unit') || null,
    source: doc.get('source') || null,
    sourceId: doc.get('sourceId') || null,
    sourcePriorityRank: doc.get('sourcePriorityRank') ?? null,
  }));

  const hits = rows.filter((row) => TARGETS.has(row.id));

  console.log(JSON.stringify({total: rows.length, targetHits: hits.length, hits}, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack || error.message : error);
  process.exit(1);
});
