const admin = require('firebase-admin');

try {
  admin.initializeApp({ projectId: 'edukn-23036' });
} catch (e) {}

const db = admin.firestore();

async function run() {
  const superAdminUid = 'Hpm7yVvI8CPsRS4nmlS4oJzOomX2';
  const doc = await db.collection('users').doc(superAdminUid).get();
  console.log('Super Admin user doc in Firestore:');
  if (doc.exists) {
    console.log(doc.data());
  } else {
    console.log('❌ Doc does NOT exist for super admin UID', superAdminUid);
  }
}

run().then(() => process.exit(0)).catch(err => { console.error(err); process.exit(1); });
