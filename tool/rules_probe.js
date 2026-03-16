const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const projectId = 'digital-arhat-rules-probe';
const listingId = 'XqRWvNzhZiE9nS6txc4N';
const buyerUid = 'Lwp1pCmn7KTtm3Zk2ZCDjytAaWo2';
const apiKey = 'AIzaSyBtehayun_WzSx3HEhF__QKC-sQi0eOLp4';

function decodeFirestoreValue(value) {
  if ('nullValue' in value) return null;
  if ('booleanValue' in value) return value.booleanValue;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return Number(value.doubleValue);
  if ('timestampValue' in value) return new Date(value.timestampValue);
  if ('arrayValue' in value) {
    const values = value.arrayValue.values || [];
    return values.map(decodeFirestoreValue);
  }
  if ('mapValue' in value) {
    const fields = value.mapValue.fields || {};
    const out = {};
    for (const [key, inner] of Object.entries(fields)) {
      out[key] = decodeFirestoreValue(inner);
    }
    return out;
  }
  return undefined;
}

async function fetchLiveListingSeed() {
  const url = `https://firestore.googleapis.com/v1/projects/digital-arhat/databases/(default)/documents/listings/${listingId}?key=${apiKey}`;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`live_listing_fetch_failed:${response.status}`);
  }
  const json = await response.json();
  const fields = json.fields || {};
  const out = {};
  for (const [key, value] of Object.entries(fields)) {
    out[key] = decodeFirestoreValue(value);
  }
  return out;
}

async function seedListing(testEnv, listingData) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().collection('listings').doc(listingId).set(listingData);
  });
}

async function runCase(db, label, payload, shouldPass) {
  const listingRef = db.collection('listings').doc(listingId);

  try {
    const op = listingRef.update(payload);
    if (shouldPass) {
      await assertSucceeds(op);
      console.log(`[rules-probe] PASS expected PASS: ${label}`);
    } else {
      await assertFails(op);
      console.log(`[rules-probe] FAIL expected FAIL: ${label}`);
    }
  } catch (error) {
    console.log(`[rules-probe] ERROR ${label}: ${error}`);
  }
}

async function main() {
  const rules = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {rules},
  });

  try {
    const liveListingData = await fetchLiveListingSeed();
    console.log(`[rules-probe] live_listing_keys=${Object.keys(liveListingData).sort().join(',')}`);

    const buyerDb = testEnv.authenticatedContext(buyerUid).firestore();
    const now = new Date('2026-03-15T18:45:50.806Z');
    const fullPayload = {
      highestBid: 60,
      highestBidAt: now,
      highestBidStatus: 'pending_verification',
      lastBidderName: 'Buyer',
      lastBidderId: buyerUid,
      lastBidderToken:
        'eLmSPD_vS2m4J7mYV-8n78:APA91bFNxaMZaL9OlyD5TGPr13tqGQPLLw_BgnuKhn0aRwNOpAwPmF3gKkXIV6AVhjiUTRYyamQ5cg2pujMQBGiV15BS93xHnECD1yaZYEP2EpKqzf5ROng',
      bid_count: 1,
      totalBids: 1,
      updatedAt: now,
    };

    const cases = [
      {label: 'full-payload-live-seed', payload: fullPayload, shouldPass: true},
      {
        label: 'without-lastBidderToken-live-seed',
        payload: {
          highestBid: 60,
          highestBidAt: now,
          highestBidStatus: 'pending_verification',
          lastBidderName: 'Buyer',
          lastBidderId: buyerUid,
          bid_count: 1,
          totalBids: 1,
          updatedAt: now,
        },
        shouldPass: true,
      },
      {
        label: 'minimal-two-fields-live-seed',
        payload: {
          highestBid: 60,
          lastBidderId: buyerUid,
        },
        shouldPass: false,
      },
    ];

    for (const entry of cases) {
      await seedListing(testEnv, liveListingData);
      await runCase(buyerDb, entry.label, entry.payload, entry.shouldPass);
    }
  } finally {
    await testEnv.cleanup();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});