#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');

const COLLECTION = 'mandi_rates';
const BATCH_SIZE = 400;

function usage() {
  console.log('Usage:');
  console.log('  node tool/delete_karachi_mandi_rates.js [--serviceAccount ./functions/serviceAccountKey.json] [--projectId <id>] [--dryRun]');
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
  if (admin.apps.length > 0) {
    return admin.app();
  }

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

function isKarachiCity(value) {
  const city = String(value || '').trim().toLowerCase();
  return city === 'karachi' || city === 'کراچی';
}

async function run() {
  const args = parseArgs(process.argv.slice(2));
  initializeAdmin(args);

  const db = admin.firestore();
  let cursor = null;
  let scanned = 0;
  let matched = 0;
  let deleted = 0;

  while (true) {
    let query = db.collection(COLLECTION).orderBy(admin.firestore.FieldPath.documentId()).limit(BATCH_SIZE);
    if (cursor) {
      query = query.startAfter(cursor);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      break;
    }

    scanned += snapshot.docs.length;
    const karachiDocs = snapshot.docs.filter((doc) => isKarachiCity(doc.data().city));
    matched += karachiDocs.length;

    if (!args.dryRun && karachiDocs.length > 0) {
      const batch = db.batch();
      for (const doc of karachiDocs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      deleted += karachiDocs.length;
    }

    cursor = snapshot.docs[snapshot.docs.length - 1];
    console.log(`scanned=${scanned} matched=${matched} deleted=${deleted} dryRun=${args.dryRun}`);
  }

  console.log(`done collection=${COLLECTION} scanned=${scanned} matched=${matched} deleted=${deleted} dryRun=${args.dryRun}`);
}

run().catch((error) => {
  console.error(error);
  process.exit(1);
});