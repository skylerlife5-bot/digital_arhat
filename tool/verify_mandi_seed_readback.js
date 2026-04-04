#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');

const COLLECTION = 'mandi_rates';

const TARGET_DOCS = [
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
];

function parseArgs(argv) {
  const args = {
    serviceAccount: null,
    projectId: null,
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

function hasResidue(value) {
  if (value === null || value === undefined) return false;
  if (typeof value === 'string') {
    const s = value.toLowerCase();
    return s.includes('apple') || s.includes('ammre');
  }
  if (Array.isArray(value)) return value.some((v) => hasResidue(v));
  if (typeof value === 'object') return Object.values(value).some((v) => hasResidue(v));
  return false;
}

function bool(v) {
  return v === true;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  initializeAdmin(args);
  const db = admin.firestore();

  const out = [];
  for (const id of TARGET_DOCS) {
    const snap = await db.collection(COLLECTION).doc(id).get();
    if (!snap.exists) {
      out.push({docId: id, exists: false});
      continue;
    }

    const d = snap.data() || {};
    out.push({
      docId: id,
      exists: true,
      commodityName: d.commodityName || null,
      city: d.city || null,
      district: d.district || null,
      mandiName: d.mandiName || null,
      unit: d.unit || null,
      price: Number(d.price || 0),
      averagePrice: Number(d.averagePrice || 0),
      minPrice: Number(d.minPrice || 0),
      maxPrice: Number(d.maxPrice || 0),
      previousPrice: Number(d.previousPrice || 0),
      acceptedBySystem: bool(d.acceptedBySystem),
      acceptedByAdmin: bool(d.acceptedByAdmin),
      reviewStatus: d.reviewStatus || null,
      verificationStatus: d.verificationStatus || null,
      freshnessStatus: d.freshnessStatus || null,
      confidenceScore: Number(d.confidenceScore || 0),
      sourcePriorityRank: Number(d.sourcePriorityRank || 0),
      source: d.source || null,
      sourceId: d.sourceId || null,
      sourceType: d.sourceType || null,
      ingestionSource: d.ingestionSource || null,
      currency: d.currency || null,
      syncedAt: d.syncedAt?.toDate ? d.syncedAt.toDate().toISOString() : null,
      updatedAt: d.updatedAt?.toDate ? d.updatedAt.toDate().toISOString() : null,
      residueFound: hasResidue(d),
      metadata: {
        rawLabel: d.metadata?.rawLabel || null,
        unitLabel: d.metadata?.unitLabel || null,
        unitNorm: d.metadata?.unitNorm || null,
        cityNorm: d.metadata?.cityNorm || null,
        districtNorm: d.metadata?.districtNorm || null,
        mandiNorm: d.metadata?.mandiNorm || null,
        provinceNorm: d.metadata?.provinceNorm || null,
        commodityNorm: d.metadata?.commodityNorm || null,
        categoryNorm: d.metadata?.categoryNorm || null,
        subCategoryNorm: d.metadata?.subCategoryNorm || null,
        commodityId: d.metadata?.commodityId || null,
        commodityRefId: d.metadata?.commodityRefId || null,
        sourceUrl: d.metadata?.sourceUrl || null,
        sourcePage: d.metadata?.sourcePage || null,
        minPrice: Number(d.metadata?.minPrice || 0),
        maxPrice: Number(d.metadata?.maxPrice || 0),
        averagePrice: Number(d.metadata?.averagePrice || 0),
      },
    });
  }

  console.log(JSON.stringify({collection: COLLECTION, count: out.length, docs: out}, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack || error.message : error);
  process.exit(1);
});
