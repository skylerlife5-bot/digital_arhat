const admin = require('firebase-admin');
const sa = require('./secrets/digital-arhat-service-account.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });

const ORIGINAL_UID = 'lWoGCBogg7f71bsWmONrz4zBE562';
const CANONICAL_EMAIL = 'u_923054158007@digitalarhat.app';

async function main() {
  const db = admin.firestore();

  const userDoc = await db.collection('users').doc(ORIGINAL_UID).get();
  const adminDoc = await db.collection('admins').doc(ORIGINAL_UID).get();

  console.log('originalUid', ORIGINAL_UID);
  console.log('usersDocExists', userDoc.exists);
  console.log('adminsDocExists', adminDoc.exists);

  const usersData = userDoc.data() || {};
  console.log('usersPhone', usersData.phone || '');
  console.log('usersRole', usersData.role || usersData.userRole || usersData.userType || '');

  const originalAuth = await admin.auth().getUser(ORIGINAL_UID);
  console.log('originalAuthExists', true);
  console.log('originalAuthEmail', originalAuth.email || '');
  console.log('originalProviders', (originalAuth.providerData || []).map((p) => p.providerId).join(','));

  let duplicateUid = '';
  try {
    const emailUser = await admin.auth().getUserByEmail(CANONICAL_EMAIL);
    if (emailUser.uid !== ORIGINAL_UID) {
      duplicateUid = emailUser.uid;
    }
    console.log('canonicalEmailOwnerUid', emailUser.uid);
  } catch (e) {
    if (e && e.code === 'auth/user-not-found') {
      console.log('canonicalEmailOwnerUid', '');
    } else {
      console.log('canonicalEmailLookupError', e.code || e.message || String(e));
    }
  }

  console.log('duplicateUidFound', duplicateUid ? 'true' : 'false');
  console.log('duplicateUid', duplicateUid);
}

main().catch((e) => {
  console.error('fatal', e.code || e.message || String(e));
  process.exit(1);
});
