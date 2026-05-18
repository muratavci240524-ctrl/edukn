const admin = require('firebase-admin');

try {
  admin.initializeApp();
} catch (e) {
  console.error('Initialization error:', e);
}

const db = admin.firestore();

console.log('Querying collectionGroup "questions_pool"...');
db.collectionGroup('questions_pool').get().then(snap => {
  console.log('SUCCESS! Total questions found in pool:', snap.size);
  
  const exams = new Map();
  snap.docs.forEach(doc => {
    const data = doc.data();
    const path = doc.ref.path;
    const examId = data.examId || 'unknown';
    const examName = data.examName || 'unknown';
    const instId = data.institutionId || 'unknown';
    
    if (!exams.has(examId)) {
      exams.set(examId, {
        name: examName,
        institutionId: instId,
        count: 0,
        samplePath: path
      });
    }
    exams.get(examId).count++;
  });
  
  console.log('\n--- Exam Question Counts in Database ---');
  exams.forEach((info, id) => {
    console.log(`Exam ID: ${id}`);
    console.log(`  Name: ${info.name}`);
    console.log(`  Institution ID: ${info.institutionId}`);
    console.log(`  Questions Count: ${info.count}`);
    console.log(`  Sample Path: ${info.samplePath}`);
    console.log('--------------------------------------');
  });
  
}).catch(err => {
  console.error('Query error:', err);
});
