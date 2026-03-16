import fs from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  increment,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

const projectId = 'digital-arhat-rules-probe';
const listingId = 'XqRWvNzhZiE9nS6txc4N';
const buyerId = 'Lwp1pCmn7KTtm3Zk2ZCDjytAaWo2';
const sellerId = 'QtO69pdz1Sc0ABDa22L8Czi9rqL2';
const bidId = 'fbk2VgvAGFdL4OwNcGtS';

const rules = fs.readFileSync('firestore.rules', 'utf8');

const testEnv = await initializeTestEnvironment({
  projectId,
  firestore: { rules },
});

await testEnv.withSecurityRulesDisabled(async (context) => {
  const db = context.firestore();
  await setDoc(doc(db, 'listings', listingId), {
    auctionStatus: 'live',
    province: 'Punjab',
    approvedBy: 'kyB7ztiRzEWCMtPPW7JnOqb3NtK2',
    promotionProofUrl: '',
    riskFlags: ['ai_unknown_failure'],
    aiReasonsUrdu: ['listing normal placeholder'],
    adminReviewStatus: 'approved',
    unitType: 'Mann',
    sellerId,
    district: 'Kasur',
    endTime: new Date('2026-03-16T09:08:27.450Z'),
    aiRiskScore: 20,
    village: 'Chak 34',
    product: 'Sugarcane / گنا',
    aiReasons: ['Listing looks mostly normal. Manual review still required.'],
    promotionStatus: 'none',
    aiFlags: ['low_media'],
    aiConfidence: 0.35,
    featured: false,
    promotionPaymentReference: '',
    category: 'crops',
    description: 'Achi fassal hai pona kamad hai',
    listingStatus: 'active',
    promotionPaymentRequired: false,
    heuristicRiskScore: 0,
    riskSummary: 'AI risk check fallback: unknown provider error.',
    promotionType: 'none',
    aiSuggestedAction: 'approve_ok',
    riskScore: 0,
    approvedAt: new Date('2026-03-15T09:08:27.639Z'),
    aiUpdatedAt: new Date('2026-03-14T22:09:53.471Z'),
    updatedAt: new Date('2026-03-15T09:08:27.639Z'),
    mandiType: 'CROPS',
    isBidPaused: false,
    bidStartTime: new Date('2026-03-15T09:08:27.450Z'),
    price: 40,
    isBidForceClosed: false,
    aiRiskLevel: 'low',
    createdAt: new Date('2026-03-14T22:09:40.272Z'),
    isApproved: true,
    priorityScore: 'normal',
    bidExpiryTime: new Date('2026-03-16T09:08:27.450Z'),
    featuredAuction: false,
    startTime: new Date('2026-03-15T09:08:27.450Z'),
    featuredCost: 0,
    quantity: 10000,
    status: 'active',
  });
});

const context = testEnv.authenticatedContext(buyerId);
const db = context.firestore();
const listingRef = doc(db, 'listings', listingId);
const bidRef = doc(collection(listingRef, 'bids'), bidId);

const bidPayload = {
  listingId,
  sellerId,
  buyerId,
  currentUserId: buyerId,
  buyerName: 'Buyer',
  buyerPhone: '+923024090114',
  productName: 'Sugarcane / گنا',
  bidAmount: 45.0,
  status: 'pending',
  createdAt: serverTimestamp(),
  isSuspicious: false,
  suspiciousReason: '',
  aiMinRate: null,
  aiMaxRate: null,
  aiAverageRate: null,
  ruleMinRate: null,
  ruleMaxRate: null,
  ruleAverageRate: null,
  fraudCode: 'CLEAR',
  velocityCode: 'VELOCITY_OK',
  route: 'normal',
  aiBidRiskScore: 20,
  aiBidRiskLevel: 'low',
  aiBidAdvice: 'Bid looks acceptable. Continue with normal caution.',
  aiBidAdviceUrdu: 'placeholder',
  aiBidAdviceEn: 'Bid looks acceptable. Continue with normal caution.',
  aiBidFlags: [],
  aiBidUpdatedAt: serverTimestamp(),
  bidReviewStatus: 'ok',
  adminReviewRequired: false,
  timestamp: serverTimestamp(),
  updatedAt: serverTimestamp(),
};

const listingUpdatePayload = {
  highestBid: 45.0,
  highestBidAt: serverTimestamp(),
  highestBidStatus: 'verified',
  lastBidderName: 'Buyer',
  lastBidderId: buyerId,
  lastBidderToken:
    'eLmSPD_vS2m4J7mYV-8n78:APA91bFNxaMZaL9OlyD5TGPr13tqGQPLLw_BgnuKhn0aRwNOpAwPmF3gKkXIV6AVhjiUTRYyamQ5cg2pujMQBGiV15BS93xHnECD1yaZYEP2EpKqzf5ROng',
  bid_count: increment(1),
  totalBids: increment(1),
  updatedAt: serverTimestamp(),
};

async function runCase(label, operation) {
  try {
    await assertSucceeds(operation());
    console.log(`${label}=PASS`);
  } catch (error) {
    console.log(`${label}=FAIL`);
    console.log(String(error));
  }
}

await runCase('bid_create', () => setDoc(bidRef, bidPayload));
await runCase('listing_update', () => updateDoc(listingRef, listingUpdatePayload));
await runCase('batch_write', async () => {
  const batch = writeBatch(db);
  batch.set(bidRef, bidPayload);
  batch.update(listingRef, listingUpdatePayload);
  await batch.commit();
});

await assertFails(updateDoc(listingRef, listingUpdatePayload)).catch(() => {});
await testEnv.cleanup();