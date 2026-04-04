#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');

const COLLECTION = 'mandi_rates';

const TARGET_ROWS = [
  {key: 'wheat', commodityName: 'Wheat', commodityNameUr: 'گندم', price: 3600, previousPrice: 3520},
  {key: 'rice', commodityName: 'Rice', commodityNameUr: 'چاول', price: 6200, previousPrice: 6100},
  {key: 'broiler', commodityName: 'Broiler', commodityNameUr: 'برائلر', price: 540, previousPrice: 530},
  {key: 'potato', commodityName: 'Potato', commodityNameUr: 'آلو', price: 170, previousPrice: 160},
  {key: 'onion', commodityName: 'Onion', commodityNameUr: 'پیاز', price: 240, previousPrice: 228},
  {key: 'tomato', commodityName: 'Tomato', commodityNameUr: 'ٹماٹر', price: 190, previousPrice: 205},
];

function usage() {
  console.log('Usage:');
  console.log('  node tool/seed_mandi_rates.js [--serviceAccount ./service-account.json] [--projectId <id>] [--dryRun]');
}

function parseArgs(argv) {
  const args = {
    serviceAccount: null,
    projectId: null,
    dryRun: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--serviceAccount') {
      args.serviceAccount = argv[i + 1] || null;
      i += 1;
      continue;
    }
    if (token === '--projectId') {
      args.projectId = argv[i + 1] || null;
      i += 1;
      continue;
    }
    if (token === '--dryRun') {
      args.dryRun = true;
      continue;
    }
    if (token === '--help' || token === '-h') {
      usage();
      process.exit(0);
    }
  }

  return args;
}

function initializeAdmin({serviceAccount, projectId}) {
  if (admin.apps.length > 0) return admin.app();

  if (serviceAccount) {
    const credentialPath = path.resolve(process.cwd(), serviceAccount);
    if (!fs.existsSync(credentialPath)) {
      throw new Error(`service_account_not_found:${credentialPath}`);
    }
    const json = JSON.parse(fs.readFileSync(credentialPath, 'utf8'));
    return admin.initializeApp({
      credential: admin.credential.cert(json),
      ...(projectId ? {projectId} : {}),
    });
  }

  return admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    ...(projectId ? {projectId} : {}),
  });
}

function normalizeCommodity(value) {
  return String(value || '')
    .trim()
    .toLowerCase();
}

function commodityFromDoc(data) {
  return normalizeCommodity(
    data.commodityName ||
      data.cropType ||
      data.cropName ||
      data.itemName ||
      data.product,
  );
}

function inspectDocs(rows) {
  const keyCounts = new Map();

  for (const row of rows) {
    for (const key of Object.keys(row.data)) {
      keyCounts.set(key, (keyCounts.get(key) || 0) + 1);
    }
  }

  const ranked = Array.from(keyCounts.entries())
    .sort((a, b) => b[1] - a[1])
    .map(([key, count]) => `${key}:${count}`);

  console.log(`inspect.total_docs=${rows.length}`);
  console.log(`inspect.collection=${COLLECTION}`);
  console.log(`inspect.keys_by_frequency=${ranked.join(',')}`);
}

function pickTrustedTemplate(rows, commodityKey) {
  const exact = rows.filter((row) => {
    const c = commodityFromDoc(row.data);
    return c.includes(commodityKey);
  });

  const pool = exact.length > 0 ? exact : rows;

  const scored = pool
    .map((row) => {
      const d = row.data;
      let score = 0;
      const review = String(d.reviewStatus || '').toLowerCase();
      const verify = String(d.verificationStatus || '').toLowerCase();
      const rowConfidence = String(d.rowConfidence || '').toLowerCase();
      const sourceReliability = String(d.sourceReliabilityLevel || '').toLowerCase();
      const sourceType = String(d.sourceType || d.ingestionSource || '').toLowerCase();
      const source = String(d.source || '').toLowerCase();

      if (review === 'accepted') score += 4;
      if (verify.includes('verified')) score += 3;
      if (d.acceptedBySystem === true) score += 2;
      if (d.acceptedByAdmin === true) score += 2;
      if (rowConfidence === 'high') score += 3;
      if (sourceReliability === 'high') score += 3;
      if (sourceType.includes('official')) score += 3;
      if (source.includes('official') || source.includes('amis')) score += 2;

      return {row, score};
    })
    .sort((a, b) => b.score - a.score);

  return scored.length > 0 ? scored[0].row : null;
}

function setIfExists(obj, key, value) {
  if (Object.prototype.hasOwnProperty.call(obj, key)) {
    obj[key] = value;
  }
}

function setTimestampIfExists(obj, key, value) {
  if (Object.prototype.hasOwnProperty.call(obj, key)) {
    obj[key] = value;
  }
}

function nextTrend(price, previousPrice) {
  if (price > previousPrice) return 'up';
  if (price < previousPrice) return 'down';
  return 'same';
}

function buildSeedPayload(templateData, target, docId) {
  const payload = JSON.parse(JSON.stringify(templateData));
  const nowTs = admin.firestore.Timestamp.now();
  const trend = nextTrend(target.price, target.previousPrice);

  setIfExists(payload, 'id', docId);

  setIfExists(payload, 'commodityName', target.commodityName);
  setIfExists(payload, 'cropType', target.commodityName);
  setIfExists(payload, 'commodityNameUr', target.commodityNameUr);

  setIfExists(payload, 'price', target.price);
  setIfExists(payload, 'averagePrice', target.price);
  setIfExists(payload, 'previousPrice', target.previousPrice);

  if (Object.prototype.hasOwnProperty.call(payload, 'minPrice') && typeof payload.minPrice === 'number') {
    payload.minPrice = Math.max(1, target.price - Math.round(target.price * 0.04));
  }
  if (Object.prototype.hasOwnProperty.call(payload, 'maxPrice') && typeof payload.maxPrice === 'number') {
    payload.maxPrice = target.price + Math.round(target.price * 0.04);
  }

  setIfExists(payload, 'trend', trend);
  setIfExists(payload, 'freshnessStatus', 'live');
  setIfExists(payload, 'reviewStatus', 'accepted');
  setIfExists(payload, 'verificationStatus', 'verified');
  setIfExists(payload, 'acceptedBySystem', true);
  setIfExists(payload, 'acceptedByAdmin', true);
  setIfExists(payload, 'rowConfidence', 'high');
  setIfExists(payload, 'sourceReliabilityLevel', 'high');

  setTimestampIfExists(payload, 'lastUpdated', nowTs);
  setTimestampIfExists(payload, 'rateDate', nowTs);
  setTimestampIfExists(payload, 'submissionTimestamp', nowTs);
  setTimestampIfExists(payload, 'syncedAt', admin.firestore.FieldValue.serverTimestamp());
  setTimestampIfExists(payload, 'updatedAt', admin.firestore.FieldValue.serverTimestamp());

  return payload;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  initializeAdmin(args);
  const db = admin.firestore();

  const snap = await db.collection(COLLECTION).limit(500).get();
  if (snap.empty) {
    throw new Error(`no_existing_docs_in_collection:${COLLECTION}`);
  }

  const rows = snap.docs.map((doc) => ({id: doc.id, data: doc.data()}));
  inspectDocs(rows);

  const batch = db.batch();
  const planned = [];

  for (const target of TARGET_ROWS) {
    const template = pickTrustedTemplate(rows, target.key);
    if (!template) {
      throw new Error(`no_template_found_for:${target.key}`);
    }

    const seedDocId = `trusted_seed_${target.key}`;
    const payload = buildSeedPayload(template.data, target, seedDocId);
    planned.push({
      docId: seedDocId,
      templateDocId: template.id,
      commodityName: target.commodityName,
      keys: Object.keys(payload).length,
    });

    const ref = db.collection(COLLECTION).doc(seedDocId);
    batch.set(ref, payload, {merge: false});
  }

  for (const item of planned) {
    console.log(
      `plan.doc=${item.docId} template=${item.templateDocId} commodity=${item.commodityName} keyCount=${item.keys}`,
    );
  }

  if (args.dryRun) {
    console.log('dry_run=true no_writes_performed');
    return;
  }

  await batch.commit();
  console.log(`seed.completed count=${planned.length}`);
}

main().catch((error) => {
  console.error('seed.failed');
  console.error(error instanceof Error ? error.stack || error.message : error);
  process.exit(1);
});
