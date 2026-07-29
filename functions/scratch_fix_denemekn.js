const admin = require('firebase-admin');

try {
  admin.initializeApp({
    projectId: 'edukn-23036'
  });
} catch (e) {
  console.error('Initialization error:', e);
}

const db = admin.firestore();

async function run() {
  console.log('Querying users with username "omustafa061"...');
  
  const usersByUsername = await db.collection('users')
      .where('username', '==', 'omustafa061')
      .get();
      
  console.log(`Found ${usersByUsername.size} user docs by username:`);
  usersByUsername.docs.forEach(doc => {
    console.log(`ID: ${doc.id} =>`, doc.data());
  });

  const schools = await db.collection('schools')
      .where('institutionId', '==', 'DENEMEKN')
      .get();
      
  console.log(`Found ${schools.size} school docs:`);
  schools.docs.forEach(doc => {
    console.log(`ID: ${doc.id} =>`, doc.data());
  });
}

run().then(() => {
  process.exit(0);
}).catch(err => {
  console.error(err);
  process.exit(1);
});
