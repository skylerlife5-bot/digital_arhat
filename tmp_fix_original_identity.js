const admin = require('firebase-admin');
const sa = require('./secrets/digital-arhat-service-account.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });

const ORIGINAL_UID = 'lWoGCBogg7f71bsWmONrz4zBE562';
const PHONE = '+923054158007';
const PASSWORD = 'Amir1140';
const CANONICAL_EMAIL = 'u_923054158007@digitalarhat.app';

async function main() {
  const auth = admin.auth();

  let duplicateUid = '';
  try {
    const emailOwner = await auth.getUserByEmail(CANONICAL_EMAIL);
    if (emailOwner.uid !== ORIGINAL_UID) {
      duplicateUid = emailOwner.uid;
      const archivedEmail = `archived_${emailOwner.uid}_${Date.now()}@digitalarhat.app`;
      await auth.updateUser(emailOwner.uid, { email: archivedEmail });
      console.log('duplicateUidArchived', emailOwner.uid);
      console.log('duplicateOldEmail', CANONICAL_EMAIL);
      console.log('duplicateNewEmail', archivedEmail);
    }
  } catch (e) {
    if (!(e && e.code === 'auth/user-not-found')) {
      throw e;
    }
  }

  await auth.updateUser(ORIGINAL_UID, {
    phoneNumber: PHONE,
    email: CANONICAL_EMAIL,
    password: PASSWORD,
  });

  const original = await auth.getUser(ORIGINAL_UID);
  console.log('originalUid', ORIGINAL_UID);
  console.log('canonicalEmail', original.email || '');
  console.log('originalProviders', (original.providerData || []).map((p) => p.providerId).join(','));
  console.log('duplicateUidFound', duplicateUid ? 'true' : 'false');
  console.log('duplicateUid', duplicateUid);
}

main().catch((e) => {
  console.error('fatal', e.code || e.message || String(e));
  process.exit(1);
});
