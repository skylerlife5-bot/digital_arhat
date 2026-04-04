#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');

const COLLECTION = 'mandi_rates';

const COMMON_SOURCE = {
  source: 'Punjab Official',
  sourceId: 'punjab_amis',
  sourceType: 'official',
  ingestionSource: 'official',
  sourcePriorityRank: 5,
  freshnessStatus: 'live',
  confidenceScore: 1,
  confidenceReason: 'Official Punjab seeded core commodity baseline (v2)',
  acceptedByAdmin: true,
  acceptedBySystem: true,
  reviewStatus: 'accepted',
  verificationStatus: 'verified',
  currency: 'PKR',
};

const TARGET_ROWS = [
  {
    docId: 'wheat_lahore',
    key: 'wheat',
    commodityName: 'Wheat',
    commodityNameUr: 'گندم',
    cropType: 'Wheat',
    categoryName: 'Crops',
    subCategoryName: 'Grains',
    city: 'Lahore',
    district: 'Lahore',
    mandiName: 'Lahore',
    province: 'Punjab',
    unit: '40 kg',
    price: 3950,
    averagePrice: 3950,
    minPrice: 3800,
    maxPrice: 4000,
    previousPrice: 3900,
  },
  {
    docId: 'wheat_gujranwala',
    key: 'wheat',
    commodityName: 'Wheat',
    commodityNameUr: 'گندم',
    cropType: 'Wheat',
    categoryName: 'Crops',
    subCategoryName: 'Grains',
    city: 'Gujranwala',
    district: 'Gujranwala',
    mandiName: 'Gujranwala',
    province: 'Punjab',
    unit: '40 kg',
    price: 3900,
    averagePrice: 3900,
    minPrice: 3800,
    maxPrice: 4000,
    previousPrice: 3850,
  },
  {
    docId: 'wheat_faisalabad',
    key: 'wheat',
    commodityName: 'Wheat',
    commodityNameUr: 'گندم',
    cropType: 'Wheat',
    categoryName: 'Crops',
    subCategoryName: 'Grains',
    city: 'Faisalabad',
    district: 'Faisalabad',
    mandiName: 'Faisalabad',
    province: 'Punjab',
    unit: '40 kg',
    price: 3880,
    averagePrice: 3880,
    minPrice: 3780,
    maxPrice: 3980,
    previousPrice: 3840,
  },
  {
    docId: 'rice_lahore',
    key: 'rice',
    commodityName: 'Rice',
    commodityNameUr: 'چاول',
    cropType: 'Rice',
    categoryName: 'Crops',
    subCategoryName: 'Grains',
    city: 'Lahore',
    district: 'Lahore',
    mandiName: 'Lahore',
    province: 'Punjab',
    unit: '40 kg',
    price: 6400,
    averagePrice: 6400,
    minPrice: 6200,
    maxPrice: 6600,
    previousPrice: 6320,
  },
  {
    docId: 'rice_gujranwala',
    key: 'rice',
    commodityName: 'Rice',
    commodityNameUr: 'چاول',
    cropType: 'Rice',
    categoryName: 'Crops',
    subCategoryName: 'Grains',
    city: 'Gujranwala',
    district: 'Gujranwala',
    mandiName: 'Gujranwala',
    province: 'Punjab',
    unit: '40 kg',
    price: 6280,
    averagePrice: 6280,
    minPrice: 6120,
    maxPrice: 6450,
    previousPrice: 6200,
  },
  {
    docId: 'broiler_lahore',
    key: 'broiler',
    commodityName: 'Broiler',
    commodityNameUr: 'برائلر',
    cropType: 'Broiler',
    categoryName: 'Livestock',
    subCategoryName: 'Poultry',
    city: 'Lahore',
    district: 'Lahore',
    mandiName: 'Lahore',
    province: 'Punjab',
    unit: 'kg',
    price: 572,
    averagePrice: 572,
    minPrice: 556,
    maxPrice: 585,
    previousPrice: 564,
  },
  {
    docId: 'broiler_faisalabad',
    key: 'broiler',
    commodityName: 'Broiler',
    commodityNameUr: 'برائلر',
    cropType: 'Broiler',
    categoryName: 'Livestock',
    subCategoryName: 'Poultry',
    city: 'Faisalabad',
    district: 'Faisalabad',
    mandiName: 'Faisalabad',
    province: 'Punjab',
    unit: 'kg',
    price: 560,
    averagePrice: 560,
    minPrice: 540,
    maxPrice: 575,
    previousPrice: 548,
  },
  {
    docId: 'potato_lahore',
    key: 'potato',
    commodityName: 'Potato',
    commodityNameUr: 'آلو',
    cropType: 'Potato',
    categoryName: 'Vegetables',
    subCategoryName: 'Root',
    city: 'Lahore',
    district: 'Lahore',
    mandiName: 'Lahore',
    province: 'Punjab',
    unit: '100 kg',
    price: 16700,
    averagePrice: 16700,
    minPrice: 16000,
    maxPrice: 17500,
    previousPrice: 16200,
  },
  {
    docId: 'potato_okara',
    key: 'potato',
    commodityName: 'Potato',
    commodityNameUr: 'آلو',
    cropType: 'Potato',
    categoryName: 'Vegetables',
    subCategoryName: 'Root',
    city: 'Okara',
    district: 'Okara',
    mandiName: 'Okara',
    province: 'Punjab',
    unit: '100 kg',
    price: 16500,
    averagePrice: 16500,
    minPrice: 15000,
    maxPrice: 18000,
    previousPrice: 15800,
  },
  {
    docId: 'onion_lahore',
    key: 'onion',
    commodityName: 'Onion',
    commodityNameUr: 'پیاز',
    cropType: 'Onion',
    categoryName: 'Vegetables',
    subCategoryName: 'Bulb',
    city: 'Lahore',
    district: 'Lahore',
    mandiName: 'Lahore',
    province: 'Punjab',
    unit: '100 kg',
    price: 24200,
    averagePrice: 24200,
    minPrice: 23000,
    maxPrice: 25500,
    previousPrice: 23600,
  },
  {
    docId: 'onion_gujranwala',
    key: 'onion',
    commodityName: 'Onion',
    commodityNameUr: 'پیاز',
    cropType: 'Onion',
    categoryName: 'Vegetables',
    subCategoryName: 'Bulb',
    city: 'Gujranwala',
    district: 'Gujranwala',
    mandiName: 'Gujranwala',
    province: 'Punjab',
    unit: '100 kg',
    price: 23500,
    averagePrice: 23500,
    minPrice: 22000,
    maxPrice: 25000,
    previousPrice: 22800,
  },
  {
    docId: 'tomato_lahore',
    key: 'tomato',
    commodityName: 'Tomato',
    commodityNameUr: 'ٹماٹر',
    cropType: 'Tomato',
    categoryName: 'Vegetables',
    subCategoryName: 'Fruit Vegetable',
    city: 'Lahore',
    district: 'Lahore',
    mandiName: 'Lahore',
    province: 'Punjab',
    unit: '100 kg',
    price: 18500,
    averagePrice: 18500,
    minPrice: 17000,
    maxPrice: 20000,
    previousPrice: 19200,
  },
  {
    docId: 'tomato_faisalabad',
    key: 'tomato',
    commodityName: 'Tomato',
    commodityNameUr: 'ٹماٹر',
    cropType: 'Tomato',
    categoryName: 'Vegetables',
    subCategoryName: 'Fruit Vegetable',
    city: 'Faisalabad',
    district: 'Faisalabad',
    mandiName: 'Faisalabad',
    province: 'Punjab',
    unit: '100 kg',
    price: 17800,
    averagePrice: 17800,
    minPrice: 16500,
    maxPrice: 19200,
    previousPrice: 18400,
  },
];

function usage() {
  console.log('Usage:');
  console.log('  node tool/seed_mandi_rates_v2.js [--serviceAccount ./service-account.json] [--projectId <id>] [--dryRun]');
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

function normalizeToken(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_');
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
      data.product ||
      data.metadata?.commodityNorm ||
      data.metadata?.rawLabel,
  );
}

function computeSchema(rows) {
  const topLevel = new Set();
  const metadata = new Set();

  for (const row of rows) {
    for (const key of Object.keys(row.data || {})) {
      topLevel.add(key);
    }
    const md = row.data?.metadata;
    if (md && typeof md === 'object' && !Array.isArray(md)) {
      for (const key of Object.keys(md)) {
        metadata.add(key);
      }
    }
  }

  return {topLevel, metadata};
}

function scoreTemplate(data) {
  const review = String(data.reviewStatus || '').toLowerCase();
  const verify = String(data.verificationStatus || '').toLowerCase();
  const rowConfidence = String(data.rowConfidence || '').toLowerCase();
  const sourceReliability = String(data.sourceReliabilityLevel || '').toLowerCase();
  const sourceType = String(data.sourceType || data.ingestionSource || '').toLowerCase();
  const source = String(data.source || '').toLowerCase();
  const freshness = String(data.freshnessStatus || '').toLowerCase();

  let score = 0;
  if (review === 'accepted') score += 4;
  if (verify.includes('verified')) score += 3;
  if (data.acceptedBySystem === true) score += 2;
  if (data.acceptedByAdmin === true) score += 2;
  if (rowConfidence === 'high') score += 3;
  if (sourceReliability === 'high') score += 3;
  if (freshness === 'live') score += 2;
  if (sourceType.includes('official')) score += 3;
  if (source.includes('official') || source.includes('amis')) score += 2;

  if (typeof data.sourcePriorityRank === 'number') {
    score += Math.max(0, 7 - Math.min(6, data.sourcePriorityRank));
  }

  return score;
}

function pickTrustedTemplate(rows, commodityKey) {
  const exact = rows.filter((row) => commodityFromDoc(row.data).includes(commodityKey));
  const pool = exact.length > 0 ? exact : rows;

  const scored = pool
    .map((row) => ({row, score: scoreTemplate(row.data)}))
    .sort((a, b) => b.score - a.score);

  if (scored.length === 0) return null;

  return {
    row: scored[0].row,
    exactMatchUsed: exact.length > 0,
  };
}

async function fetchExactTemplateRows(db, target) {
  const byCommodityName = await db
    .collection(COLLECTION)
    .where('commodityName', '==', target.commodityName)
    .limit(80)
    .get();

  const byCropType = await db
    .collection(COLLECTION)
    .where('cropType', '==', target.cropType)
    .limit(80)
    .get();

  const map = new Map();
  for (const doc of byCommodityName.docs) {
    map.set(doc.id, {id: doc.id, data: doc.data()});
  }
  for (const doc of byCropType.docs) {
    map.set(doc.id, {id: doc.id, data: doc.data()});
  }

  return Array.from(map.values());
}

function deepClone(value) {
  if (value === null || value === undefined) return value;
  if (Array.isArray(value)) return value.map((item) => deepClone(item));
  if (value instanceof Date) return new Date(value.getTime());
  if (value instanceof admin.firestore.Timestamp) return value;
  if (typeof value === 'object') {
    const out = {};
    for (const key of Object.keys(value)) {
      out[key] = deepClone(value[key]);
    }
    return out;
  }
  return value;
}

function setIfInSchema(schemaKeys, obj, key, value) {
  if (!obj || typeof obj !== 'object') return;
  if (Object.prototype.hasOwnProperty.call(obj, key) || schemaKeys.has(key)) {
    obj[key] = value;
  }
}

function nextTrend(price, previousPrice) {
  if (price > previousPrice) return 'up';
  if (price < previousPrice) return 'down';
  return 'same';
}

function applyCoreOverrides(payload, target, schema) {
  const nowTs = admin.firestore.Timestamp.now();
  const top = schema.topLevel;
  const trend = nextTrend(target.price, target.previousPrice);

  setIfInSchema(top, payload, 'id', target.docId);
  setIfInSchema(top, payload, 'commodityName', target.commodityName);
  setIfInSchema(top, payload, 'commodityNameUr', target.commodityNameUr);
  setIfInSchema(top, payload, 'cropType', target.cropType);
  setIfInSchema(top, payload, 'categoryName', target.categoryName);
  setIfInSchema(top, payload, 'subCategoryName', target.subCategoryName);

  setIfInSchema(top, payload, 'city', target.city);
  setIfInSchema(top, payload, 'district', target.district);
  setIfInSchema(top, payload, 'mandiName', target.mandiName);
  setIfInSchema(top, payload, 'province', target.province);

  setIfInSchema(top, payload, 'price', target.price);
  setIfInSchema(top, payload, 'averagePrice', target.averagePrice);
  setIfInSchema(top, payload, 'minPrice', target.minPrice);
  setIfInSchema(top, payload, 'maxPrice', target.maxPrice);
  setIfInSchema(top, payload, 'previousPrice', target.previousPrice);

  setIfInSchema(top, payload, 'unit', target.unit);
  setIfInSchema(top, payload, 'currency', COMMON_SOURCE.currency);

  setIfInSchema(top, payload, 'trend', trend);
  setIfInSchema(top, payload, 'acceptedByAdmin', COMMON_SOURCE.acceptedByAdmin);
  setIfInSchema(top, payload, 'acceptedBySystem', COMMON_SOURCE.acceptedBySystem);
  setIfInSchema(top, payload, 'reviewStatus', COMMON_SOURCE.reviewStatus);
  setIfInSchema(top, payload, 'verificationStatus', COMMON_SOURCE.verificationStatus);
  setIfInSchema(top, payload, 'freshnessStatus', COMMON_SOURCE.freshnessStatus);
  setIfInSchema(top, payload, 'confidenceScore', COMMON_SOURCE.confidenceScore);
  setIfInSchema(top, payload, 'confidenceReason', COMMON_SOURCE.confidenceReason);
  setIfInSchema(top, payload, 'source', COMMON_SOURCE.source);
  setIfInSchema(top, payload, 'sourceId', COMMON_SOURCE.sourceId);
  setIfInSchema(top, payload, 'sourceType', COMMON_SOURCE.sourceType);
  setIfInSchema(top, payload, 'ingestionSource', COMMON_SOURCE.ingestionSource);
  setIfInSchema(top, payload, 'sourcePriorityRank', COMMON_SOURCE.sourcePriorityRank);

  setIfInSchema(top, payload, 'commodityRefId', target.key);
  setIfInSchema(top, payload, 'rowConfidence', 'high');
  setIfInSchema(top, payload, 'sourceReliabilityLevel', 'high');
  setIfInSchema(top, payload, 'displayPriceSource', 'average');

  setIfInSchema(top, payload, 'lastUpdated', nowTs);
  setIfInSchema(top, payload, 'rateDate', nowTs);
  setIfInSchema(top, payload, 'submissionTimestamp', nowTs);
  setIfInSchema(top, payload, 'updatedAt', admin.firestore.FieldValue.serverTimestamp());
  setIfInSchema(top, payload, 'syncedAt', admin.firestore.FieldValue.serverTimestamp());
}

function applyMetadataOverrides(payload, target, schema) {
  if (!payload.metadata || typeof payload.metadata !== 'object' || Array.isArray(payload.metadata)) {
    if (!schema.topLevel.has('metadata')) return;
    payload.metadata = {};
  }

  const md = payload.metadata;
  const keys = schema.metadata;

  setIfInSchema(keys, md, 'rawLabel', target.commodityName);
  setIfInSchema(keys, md, 'unitLabel', target.unit);
  setIfInSchema(keys, md, 'unitNorm', normalizeToken(target.unit));
  setIfInSchema(keys, md, 'cityNorm', normalizeToken(target.city));
  setIfInSchema(keys, md, 'districtNorm', normalizeToken(target.district));
  setIfInSchema(keys, md, 'mandiNorm', normalizeToken(target.mandiName));
  setIfInSchema(keys, md, 'provinceNorm', normalizeToken(target.province));
  setIfInSchema(keys, md, 'commodityNorm', target.key);
  setIfInSchema(keys, md, 'categoryNorm', normalizeToken(target.categoryName));
  setIfInSchema(keys, md, 'subCategoryNorm', normalizeToken(target.subCategoryName));
  setIfInSchema(keys, md, 'commodityId', target.key);
  setIfInSchema(keys, md, 'commodityRefId', target.key);
  setIfInSchema(keys, md, 'sourceUrl', '');
  setIfInSchema(keys, md, 'sourcePage', COMMON_SOURCE.sourceId);
  setIfInSchema(keys, md, 'minPrice', target.minPrice);
  setIfInSchema(keys, md, 'maxPrice', target.maxPrice);
  setIfInSchema(keys, md, 'averagePrice', target.averagePrice);
}

function stripAppleResidue(payload) {
  const banned = ['apple', 'ammre'];

  function scrub(value) {
    if (typeof value !== 'string') return value;
    let result = value;
    for (const token of banned) {
      const re = new RegExp(token, 'ig');
      result = result.replace(re, '');
    }
    return result;
  }

  function walk(node) {
    if (!node || typeof node !== 'object') return;
    for (const key of Object.keys(node)) {
      const current = node[key];
      if (typeof current === 'string') {
        node[key] = scrub(current).trim();
      } else if (current && typeof current === 'object') {
        walk(current);
      }
    }
  }

  walk(payload);
}

function containsAppleResidue(payload) {
  const banned = ['apple', 'ammre'];

  function walk(node) {
    if (node === null || node === undefined) return false;
    if (typeof node === 'string') {
      const normalized = node.toLowerCase();
      return banned.some((token) => normalized.includes(token));
    }
    if (Array.isArray(node)) return node.some((item) => walk(item));
    if (typeof node === 'object') {
      return Object.values(node).some((value) => walk(value));
    }
    return false;
  }

  return walk(payload);
}

function verifyReadback(docId, data, target) {
  const failures = [];

  function assertEq(field, actual, expected) {
    if (actual !== expected) {
      failures.push(`${field}:expected=${expected}:actual=${actual}`);
    }
  }

  assertEq('commodityName', String(data.commodityName || ''), target.commodityName);
  assertEq('commodityNameUr', String(data.commodityNameUr || ''), target.commodityNameUr);
  assertEq('city', String(data.city || ''), target.city);
  assertEq('district', String(data.district || ''), target.district);
  assertEq('mandiName', String(data.mandiName || ''), target.mandiName);
  assertEq('unit', String(data.unit || ''), target.unit);
  assertEq('sourcePriorityRank', Number(data.sourcePriorityRank || 0), COMMON_SOURCE.sourcePriorityRank);
  assertEq('freshnessStatus', String(data.freshnessStatus || ''), COMMON_SOURCE.freshnessStatus);
  assertEq('confidenceScore', Number(data.confidenceScore || 0), COMMON_SOURCE.confidenceScore);
  assertEq('source', String(data.source || ''), COMMON_SOURCE.source);
  assertEq('sourceId', String(data.sourceId || ''), COMMON_SOURCE.sourceId);
  assertEq('sourceType', String(data.sourceType || ''), COMMON_SOURCE.sourceType);
  assertEq('ingestionSource', String(data.ingestionSource || ''), COMMON_SOURCE.ingestionSource);
  assertEq('reviewStatus', String(data.reviewStatus || ''), COMMON_SOURCE.reviewStatus);
  assertEq('verificationStatus', String(data.verificationStatus || ''), COMMON_SOURCE.verificationStatus);
  assertEq('acceptedByAdmin', data.acceptedByAdmin === true, true);
  assertEq('acceptedBySystem', data.acceptedBySystem === true, true);
  assertEq('currency', String(data.currency || ''), COMMON_SOURCE.currency);

  assertEq('price', Number(data.price || 0), target.price);
  assertEq('averagePrice', Number(data.averagePrice || 0), target.averagePrice);
  assertEq('minPrice', Number(data.minPrice || 0), target.minPrice);
  assertEq('maxPrice', Number(data.maxPrice || 0), target.maxPrice);
  assertEq('previousPrice', Number(data.previousPrice || 0), target.previousPrice);

  if (containsAppleResidue(data)) {
    failures.push('apple_residue_detected');
  }

  const md = data.metadata && typeof data.metadata === 'object' ? data.metadata : null;
  if (md) {
    assertEq('metadata.rawLabel', String(md.rawLabel || ''), target.commodityName);
    assertEq('metadata.unitLabel', String(md.unitLabel || ''), target.unit);
    assertEq('metadata.unitNorm', String(md.unitNorm || ''), normalizeToken(target.unit));
    assertEq('metadata.cityNorm', String(md.cityNorm || ''), normalizeToken(target.city));
    assertEq('metadata.districtNorm', String(md.districtNorm || ''), normalizeToken(target.district));
    assertEq('metadata.mandiNorm', String(md.mandiNorm || ''), normalizeToken(target.mandiName));
    assertEq('metadata.provinceNorm', String(md.provinceNorm || ''), normalizeToken(target.province));
    assertEq('metadata.commodityNorm', String(md.commodityNorm || ''), target.key);
    assertEq('metadata.categoryNorm', String(md.categoryNorm || ''), normalizeToken(target.categoryName));
    assertEq('metadata.subCategoryNorm', String(md.subCategoryNorm || ''), normalizeToken(target.subCategoryName));
    assertEq('metadata.commodityId', String(md.commodityId || ''), target.key);
    assertEq('metadata.commodityRefId', String(md.commodityRefId || ''), target.key);
    assertEq('metadata.sourcePage', String(md.sourcePage || ''), COMMON_SOURCE.sourceId);
    assertEq('metadata.sourceUrl', String(md.sourceUrl || ''), '');
    assertEq('metadata.minPrice', Number(md.minPrice || 0), target.minPrice);
    assertEq('metadata.maxPrice', Number(md.maxPrice || 0), target.maxPrice);
    assertEq('metadata.averagePrice', Number(md.averagePrice || 0), target.averagePrice);

    const mdCommodityNorm = String(md.commodityNorm || '').toLowerCase();
    if (mdCommodityNorm && mdCommodityNorm !== target.key) {
      failures.push(`metadata.commodityNorm:expected=${target.key}:actual=${mdCommodityNorm}`);
    }

    const mdRaw = String(md.rawLabel || '').toLowerCase();
    if (mdRaw.includes('apple') || mdRaw.includes('ammre')) {
      failures.push(`metadata.rawLabel_residue:${md.rawLabel}`);
    }

    const mdSourcePage = String(md.sourcePage || '').toLowerCase();
    if (mdSourcePage.includes('apple') || mdSourcePage.includes('ammre')) {
      failures.push(`metadata.sourcePage_residue:${md.sourcePage}`);
    }

    const mdSourceUrl = String(md.sourceUrl || '').toLowerCase();
    if (mdSourceUrl.includes('apple') || mdSourceUrl.includes('ammre')) {
      failures.push(`metadata.sourceUrl_residue:${md.sourceUrl}`);
    }
  }

  return {
    docId,
    pass: failures.length === 0,
    failures,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  initializeAdmin(args);
  const db = admin.firestore();

  const snap = await db.collection(COLLECTION).limit(1500).get();
  if (snap.empty) {
    throw new Error(`no_existing_docs_in_collection:${COLLECTION}`);
  }

  const rows = snap.docs.map((doc) => ({id: doc.id, data: doc.data()}));
  const schema = computeSchema(rows);

  console.log(`seed_v2.inspect.collection=${COLLECTION}`);
  console.log(`seed_v2.inspect.total_docs=${rows.length}`);
  console.log(`seed_v2.inspect.top_level_keys=${Array.from(schema.topLevel).sort().join(',')}`);
  console.log(`seed_v2.inspect.metadata_keys=${Array.from(schema.metadata).sort().join(',')}`);

  const plan = [];
  const batch = db.batch();

  for (const target of TARGET_ROWS) {
    const exactRows = await fetchExactTemplateRows(db, target);
    const selected = pickTrustedTemplate(exactRows.length > 0 ? exactRows : rows, target.key);
    if (!selected) {
      throw new Error(`template_not_found_for:${target.key}`);
    }

    const payload = deepClone(selected.row.data);
    applyCoreOverrides(payload, target, schema);
    applyMetadataOverrides(payload, target, schema);
    stripAppleResidue(payload);

    plan.push({
      docId: target.docId,
      commodityKey: target.key,
      templateDocId: selected.row.id,
      exactTemplate: selected.exactMatchUsed,
      city: target.city,
      unit: target.unit,
      sourcePriorityRank: COMMON_SOURCE.sourcePriorityRank,
      freshnessStatus: COMMON_SOURCE.freshnessStatus,
      confidenceScore: COMMON_SOURCE.confidenceScore,
    });

    if (!args.dryRun) {
      const ref = db.collection(COLLECTION).doc(target.docId);
      batch.set(ref, payload, {merge: false});
    }
  }

  console.log(`seed_v2.collection=${COLLECTION}`);
  console.log(`seed_v2.total=${plan.length}`);
  for (const item of plan) {
    console.log(
      `seed_v2.plan doc=${item.docId} commodity=${item.commodityKey} template=${item.templateDocId} exactTemplate=${item.exactTemplate} city=${item.city} unit=${item.unit} rank=${item.sourcePriorityRank} freshness=${item.freshnessStatus} confidence=${item.confidenceScore}`,
    );
  }

  if (args.dryRun) {
    console.log('seed_v2.dryRun=true no_writes_performed');
    return;
  }

  await batch.commit();
  console.log(`seed_v2.write_committed count=${plan.length}`);

  const verification = [];
  for (const target of TARGET_ROWS) {
    const snapDoc = await db.collection(COLLECTION).doc(target.docId).get();
    if (!snapDoc.exists) {
      verification.push({docId: target.docId, pass: false, failures: ['missing_after_write']});
      continue;
    }
    const result = verifyReadback(target.docId, snapDoc.data() || {}, target);
    verification.push(result);

    console.log(
      `seed_v2.verify doc=${result.docId} status=${result.pass ? 'PASS' : 'FAIL'} city=${target.city} unit=${target.unit} rank=${COMMON_SOURCE.sourcePriorityRank} freshness=${COMMON_SOURCE.freshnessStatus} confidence=${COMMON_SOURCE.confidenceScore} appleResidue=${result.failures.includes('apple_residue_detected') ? 'yes' : 'no'}`,
    );

    if (!result.pass) {
      console.log(`seed_v2.verify_failures doc=${result.docId} details=${result.failures.join('|')}`);
    }
  }

  const failed = verification.filter((item) => !item.pass);
  if (failed.length > 0) {
    throw new Error(`seed_v2_verification_failed count=${failed.length}`);
  }

  console.log('seed_v2.verification=PASS');
}

main().catch((error) => {
  console.error('seed_v2.failed');
  console.error(error instanceof Error ? error.stack || error.message : error);
  process.exit(1);
});
