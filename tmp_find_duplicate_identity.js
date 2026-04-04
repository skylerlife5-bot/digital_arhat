const admin = require('firebase-admin');
const sa = require('./secrets/digital-arhat-service-account.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });

const ORIGINAL_UID = 'lWoGCBogg7f71bsWmONrz4zBE562';
const PHONE = '+923054158007';
const PHONE_DIGITS = '923054158007';

async function main() {
  let nextPageToken = undefined;
  const matches = [];

  do {
    const page = await admin.auth().listUsers(1000, nextPageToken);
    for (const user of page.users) {
      const email = String(user.email || '');
      const phone = String(user.phoneNumber || '');
      const providers = (user.providerData || []).map((p) => p.providerId).join(',');
      const emailHit = email.includes(PHONE_DIGITS) || email.includes('digitalarhat.app');
      const phoneHit = phone === PHONE;
      if ((emailHit || phoneHit) && user.uid !== ORIGINAL_UID) {
        matches.push({
          uid: user.uid,
          email,
          phone,
          providers,
        });
      }
    }
    nextPageToken = page.pageToken;
  } while (nextPageToken);

  console.log('originalUid', ORIGINAL_UID);
  console.log('duplicateCandidatesCount', matches.length);
  for (const m of matches) {
    console.log('duplicateUid', m.uid);
    console.log('duplicateEmail', m.email);
    console.log('duplicatePhone', m.phone);
    console.log('duplicateProviders', m.providers);
  }
}

main().catch((e) => {
  console.error('fatal', e.code || e.message || String(e));
  process.exit(1);
});
