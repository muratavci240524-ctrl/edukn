const admin = require('firebase-admin');

try {
  admin.initializeApp({
    projectId: 'edukn-23036'
  });
} catch (e) {
  console.error('Initialization error:', e);
}

const db = admin.firestore();
const auth = admin.auth();

async function run() {
  const uid = '0CevCiMYgNbkwZwBHXZYsMDcDb52';
  const targetEmail = 'mustafaozyurtt@gmail.com';
  
  // Get temp password from Firestore
  const userDoc = await db.collection('users').doc(uid).get();
  if (!userDoc.exists) {
    console.error('❌ User doc not found in Firestore!');
    return;
  }
  
  const userData = userDoc.data();
  const tempPassword = userData._tempPassword;
  
  if (!tempPassword) {
    console.error('❌ No temp password found in Firestore user document.');
    return;
  }
  
  console.log(`Updating Auth User ${uid}: email=${targetEmail}, password=${tempPassword}...`);
  try {
    await auth.updateUser(uid, {
      email: targetEmail,
      password: tempPassword,
      emailVerified: true
    });
    console.log('✅ Successfully updated Firebase Auth user email and password!');
    
    // Clean up _tempPassword from Firestore since it has been applied to Auth
    await db.collection('users').doc(uid).update({
      _tempPassword: admin.firestore.FieldValue.delete()
    });
    console.log('🧹 Cleaned up _tempPassword from Firestore.');
  } catch (e) {
    console.error('❌ Error updating Auth user:', e.message);
  }
}

run().then(() => {
  process.exit(0);
}).catch(err => {
  console.error(err);
  process.exit(1);
});
