const admin = require('firebase-admin');
const sa = require('./secrets/digital-arhat-service-account.json');
admin.initializeApp({ credential: admin.credential.cert(sa) });
const uid = 'lWoGCBogg7f71bsWmONrz4zBE562';
(async () => {
  const db = admin.firestore();
  const userDoc = await db.collection('users').doc(uid).get();
  console.log('usersDocExists', userDoc.exists);
  if (userDoc.exists) {
    const d = userDoc.data() || {};
    console.log('userPhone', d.phone || '');
    console.log('password', d.password || '');
    console.log('hasPasswordField', typeof d.password === 'string' && d.password.length > 0);
    console.log('hasPasswordHash', typeof d.passwordHash === 'string' && d.passwordHash.length > 0);
    console.log('role', d.role || d.userRole || d.userType || '');
  }
  try {
    const au = await admin.auth().getUser(uid);
    console.log('authUserExists', true);
    console.log('authEmail', au.email || '');
    console.log('providerIds', (au.providerData || []).map((p) => p.providerId).join(','));
  } catch (e) {
    if (e && e.code === 'auth/user-not-found') {
      console.log('authUserExists', false);
    } else {
      console.log('authLookupError', (e && (e.code || e.message)) || String(e));
    }
  }

  try {
    const body = {
      phone: '+923054158007',
      password: 'Amir1140',
      expectedUid: uid,
    };
    const response = await fetch(
      'https://asia-south1-digital-arhat.cloudfunctions.net/establishCustomSession',
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      },
    );
    const text = await response.text();
    console.log('customSessionStatus', response.status);
    console.log('customSessionBody', text);
  } catch (e) {
    console.log('customSessionError', (e && (e.code || e.message)) || String(e));
  }
})();
