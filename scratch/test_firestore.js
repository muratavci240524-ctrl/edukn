const admin = require('firebase-admin');
admin.initializeApp({
  projectId: 'edukn-23036'
});
const db = admin.firestore();
db.collection('trial_exams').limit(5).get().then(snap => {
  console.log('Total exams loaded:', snap.size);
  snap.docs.forEach(doc => {
    console.log(doc.id, '=>', doc.data().name);
  });
}).catch(err => {
  console.error('Error querying Firestore:', err);
});
