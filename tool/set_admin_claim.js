#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const admin = require('firebase-admin');

function printUsage() {
  console.log('Usage:');
  console.log('  node tool/set_admin_claim.js <UID> [serviceAccountPath]');
  console.log('');
  console.log('Examples:');
  console.log('  node tool/set_admin_claim.js abc123 ./service-account.json');
  console.log('  node tool/set_admin_claim.js abc123');
  console.log('');
  console.log('If serviceAccountPath is omitted, GOOGLE_APPLICATION_CREDENTIALS will be used.');
}

function resolveCredentialPath(optionalPathArg) {
  if (optionalPathArg && optionalPathArg.trim().length > 0) {
    return path.resolve(process.cwd(), optionalPathArg);
  }

  const envPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (envPath && envPath.trim().length > 0) {
    return path.resolve(process.cwd(), envPath);
  }

  return null;
}

function initializeAdmin(credentialPath) {
  if (credentialPath) {
    if (!fs.existsSync(credentialPath)) {
      throw new Error(`Service account file not found: ${credentialPath}`);
    }

    const serviceAccount = require(credentialPath);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    return;
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });
}

async function main() {
  const uid = process.argv[2];
  const serviceAccountPathArg = process.argv[3];

  if (!uid) {
    printUsage();
    process.exit(1);
  }

  const credentialPath = resolveCredentialPath(serviceAccountPathArg);

  try {
    initializeAdmin(credentialPath);

    const userRecord = await admin.auth().getUser(uid);
    const existingClaims = userRecord.customClaims || {};
    const updatedClaims = {
      ...existingClaims,
      role: 'admin',
    };

    await admin.auth().setCustomUserClaims(uid, updatedClaims);

    console.log('✅ Admin claim applied successfully.');
    console.log(`UID: ${uid}`);
    console.log(`Claims: ${JSON.stringify(updatedClaims)}`);
    console.log('ℹ️ Ask the user to sign out and sign in again (or refresh ID token) to receive updated claims.');
  } catch (error) {
    console.error('❌ Failed to set admin claim.');
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  }
}

main();
