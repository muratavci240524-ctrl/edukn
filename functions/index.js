const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

// Firebase admin panelini başlat
admin.initializeApp();

// Firestore veritabanına erişim
const db = admin.firestore();

/**
 * 'createSchool' adında çağrılabilir (callable) bir bulut fonksiyonu.
 */
exports.createSchool = onCall(async (request) => {
    const {data, auth} = request;
    // --- 1. Güvenlik Kontrolü ---
    if (!auth) {
      throw new HttpsError(
        "unauthenticated",
        "Bu işlemi yapmak için giriş yapmış olmalısınız."
      );
    }

    // --- 2. Gelen Verileri Al ---
    const { schoolName, adminEmail, adminPassword, activeModules } = data;

    if (!schoolName || !adminEmail || !adminPassword || !activeModules) {
      throw new HttpsError(
        "invalid-argument",
        "Eksik bilgi gönderildi."
      );
    }

    try {
      // --- 3. Okul Yöneticisi Hesabını Oluştur (Auth) ---
      const userRecord = await admin.auth().createUser({
        email: adminEmail,
        password: adminPassword,
        displayName: `${schoolName} Yöneticisi`,
      });

      // --- 4. Lisans Bitiş Tarihini Hesapla (Otomatik 1 Ay) ---
      const now = new Date();
      const licenseExpiresAt = new Date(now.setDate(now.getDate() + 30));

      // --- 5. Okul Belgesini Firestore'a Kaydet ---
      const schoolData = {
        schoolName: schoolName,
        adminEmail: adminEmail,
        adminUserId: userRecord.uid,
        activeModules: activeModules,
        isActive: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        licenseExpiresAt: admin.firestore.Timestamp.fromDate(licenseExpiresAt),
      };

      // 'schools' koleksiyonuna *belge ID'si olarak adminUserId* kullanarak ekle
      await db.collection("schools").doc(userRecord.uid).set(schoolData);

      // --- 6. Başarı Mesajı Gönder ---
      return {
        status: "success",
        message: `${schoolName} başarıyla oluşturuldu.`,
        schoolId: userRecord.uid,
      };
    } catch (error) {
      console.error("Okul oluşturulurken hata oluştu:", error);
      throw new HttpsError(
        "internal",
        error.message || "Bilinmeyen bir sunucu hatası oluştu."
      );
    }
});

/**
 * 'extendLicense' adında çağrılabilir (callable) bir bulut fonksiyonu.
 * Bir okulun lisans süresini uzatır.
 */
exports.extendLicense = onCall(async (request) => {
    const {data, auth} = request;
    // 1. Güvenlik Kontrolü
    if (!auth) {
      throw new HttpsError(
        "unauthenticated",
        "Bu işlemi yapmak için giriş yapmış olmalısınız."
      );
    }

    // 2. Verileri Al
    const { schoolId, daysToAdd } = data;
    if (!schoolId || !daysToAdd) {
      throw new HttpsError(
        "invalid-argument",
        "Eksik bilgi: 'schoolId' ve 'daysToAdd' gereklidir."
      );
    }

    try {
      // 3. Okul belgesini bul
      const schoolRef = db.collection("schools").doc(schoolId);
      const schoolDoc = await schoolRef.get();

      if (!schoolDoc.exists) {
        throw new HttpsError("not-found", "Okul bulunamadı.");
      }

      // 4. Yeni Lisans Tarihini Hesapla
      const schoolData = schoolDoc.data();
      const currentExpiresAt = schoolData.licenseExpiresAt
        ? schoolData.licenseExpiresAt.toDate()
        : new Date(); // Eğer hiç tarih yoksa, bugünden başlat

      const now = new Date();
      let newExpiresAt;

      if (currentExpiresAt < now) {
        // Eğer lisans süresi dolmuşsa, 'bugünden' itibaren gün ekle
        newExpiresAt = new Date(now.setDate(now.getDate() + daysToAdd));
      } else {
        // Eğer lisans hala geçerliyse, 'mevcut bitiş tarihinden' itibaren ekle
        newExpiresAt = new Date(
          currentExpiresAt.setDate(currentExpiresAt.getDate() + daysToAdd)
        );
      }

      // 5. Veritabanını Güncelle
      await schoolRef.update({
        licenseExpiresAt: admin.firestore.Timestamp.fromDate(newExpiresAt),
        isActive: true, // Lisansı yenilenen okulu (yeniden) aktif et
      });

      // 6. Başarı Mesajı Gönder
      return {
        status: "success",
        message: `Lisans ${daysToAdd} gün başarıyla uzatıldı.`,
      };
    } catch (error) {
      console.error("Lisans uzatılırken hata oluştu:", error);
      throw new HttpsError(
        "internal",
        error.message || "Bilinmeyen bir sunucu hatası oluştu."
      );
    }
});

// --- YENİ FONKSİYON: MODÜL GÜNCELLEME ---

/**
 * 'updateSchoolModules' adında çağrılabilir bir bulut fonksiyonu.
 * Bir okulun aktif modül listesini günceller.
 *
 * Gerekli veriler (data):
 * - schoolId (String)
 * - activeModules (List<String>)
 */
exports.updateSchoolModules = onCall(async (request) => {
    const {data, auth} = request;
    // 1. Güvenlik Kontrolü
    if (!auth) {
      throw new HttpsError(
        "unauthenticated",
        "Bu işlemi yapmak için giriş yapmış olmalısınız."
      );
    }

    // 2. Verileri Al
    const { schoolId, activeModules } = data;
    if (!schoolId || activeModules == null) {
      throw new HttpsError(
        "invalid-argument",
        "Eksik bilgi: 'schoolId' ve 'activeModules' gereklidir."
      );
    }

    try {
      // 3. Okul belgesini bul ve güncelle
      const schoolRef = db.collection("schools").doc(schoolId);
      await schoolRef.update({
        activeModules: activeModules,
      });

      // 4. Başarı Mesajı Gönder
      return {
        status: "success",
        message: "Okul modülleri başarıyla güncellendi.",
      };
    } catch (error) {
      console.error("Modüller güncellenirken hata oluştu:", error);
      throw new HttpsError(
        "internal",
        error.message || "Bilinmeyen bir sunucu hatası oluştu."
      );
    }
});

/**
 * 'deleteSchoolAndAdmin' adında çağrılabilir bir bulut fonksiyonu.
 * Bir okulu ve yönetici hesabını siler.
 *
 * Gerekli veriler (data):
 * - schoolId (String)
 */
exports.deleteSchoolAndAdmin = onCall(async (request) => {
    const {data, auth} = request;
    // 1. Güvenlik Kontrolü
    if (!auth) {
      throw new HttpsError(
        "unauthenticated",
        "Bu işlemi yapmak için giriş yapmış olmalısınız."
      );
    }

    // 2. Verileri Al
    const { schoolId } = data;
    if (!schoolId) {
      throw new HttpsError(
        "invalid-argument",
        "Eksik bilgi: 'schoolId' gereklidir."
      );
    }

    try {
      // 3. Yönetici hesabını sil (Auth)
      try {
        await admin.auth().deleteUser(schoolId);
        console.log(`Yönetici hesabı silindi: ${schoolId}`);
      } catch (authError) {
        console.warn(`Yönetici hesabı silinemedi: ${authError.message}`);
        // Devam et, okul belgesi zaten silinmiş olabilir
      }

      // 4. Okul belgesini sil (Firestore)
      await db.collection("schools").doc(schoolId).delete();
      console.log(`Okul belgesi silindi: ${schoolId}`);

      // 5. Başarı Mesajı Gönder
      return {
        status: "success",
        message: "Okul ve yönetici hesabı başarıyla silindi.",
      };
    } catch (error) {
      console.error("Okul silinirken hata oluştu:", error);
      throw new HttpsError(
        "internal",
        error.message || "Bilinmeyen bir sunucu hatası oluştu."
      );
    }
});

