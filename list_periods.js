const admin = require('firebase-admin');
var serviceAccount = require("./serviceAccountKey.json");

if (admin.apps.length === 0) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}

const db = admin.firestore();

async function listPeriods() {
    console.log('Listing all workPeriods...');
    const snapshot = await db.collection('workPeriods').get();

    if (snapshot.empty) {
        console.log('No workPeriods found.');
        return;
    }

    console.log(`Found ${snapshot.size} periods:`);
    console.log('---------------------------------------------------');
    snapshot.forEach(doc => {
        const data = doc.data();
        console.log(`ID: ${doc.id}`);
        console.log(`Name: ${data.name}`);
        console.log(`IsActive: ${data.isActive}`);
        console.log(`SchoolType: ${data.schoolTypeId}`);
        console.log(`Institution: ${data.institutionId}`);
        console.log('---------------------------------------------------');
    });
}

listPeriods().then(() => {
    // process.exit(0); // Optional
}).catch(e => console.error(e));
