/**
 * Migration Script: temporaryTeacherAssignments -> aktif döneme geçir
 * 
 * Çalıştırma: node migrate_substitute_termid.js
 * Gereksinim: firebase-admin (npm install firebase-admin)
 */

const admin = require('firebase-admin');
const serviceAccount = require('./service-account-key.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function migrateSubstituteAssignments() {
  // 1. Aktif dönemi bul
  const termsSnap = await db.collection('terms')
    .where('isActive', '==', true)
    .limit(1)
    .get();

  if (termsSnap.empty) {
    console.error('❌ Aktif dönem bulunamadı!');
    process.exit(1);
  }

  const activeTermId = termsSnap.docs[0].id;
  const activeTermName = termsSnap.docs[0].data().name ?? activeTermId;
  console.log(`✅ Aktif dönem: ${activeTermName} (${activeTermId})`);

  // 2. termId olmayan geçici görevlendirmeleri bul
  const assignmentsSnap = await db.collection('temporaryTeacherAssignments').get();

  const toMigrate = assignmentsSnap.docs.filter(doc => !doc.data().termId);
  console.log(`📋 Toplam kayıt: ${assignmentsSnap.size}, Migrate edilecek: ${toMigrate.length}`);

  if (toMigrate.length === 0) {
    console.log('ℹ️ Migrate edilecek kayıt yok.');
    process.exit(0);
  }

  // 3. Batch ile güncelle (Firestore batch max 500)
  const batchSize = 400;
  let migrated = 0;

  for (let i = 0; i < toMigrate.length; i += batchSize) {
    const batch = db.batch();
    const chunk = toMigrate.slice(i, i + batchSize);

    for (const doc of chunk) {
      batch.update(doc.ref, { termId: activeTermId });
    }

    await batch.commit();
    migrated += chunk.length;
    console.log(`✅ ${migrated}/${toMigrate.length} kayıt güncellendi...`);
  }

  console.log(`\n🎉 Migrasyon tamamlandı! ${migrated} kayıt aktif döneme (${activeTermName}) taşındı.`);
  process.exit(0);
}

migrateSubstituteAssignments().catch(err => {
  console.error('❌ Hata:', err);
  process.exit(1);
});
