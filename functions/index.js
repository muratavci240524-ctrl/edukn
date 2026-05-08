const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

// Firebase admin panelini başlat
admin.initializeApp();

// Firestore veritabanına erişim
const db = admin.firestore();

// Gmail SMTP Yapılandırması
const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
        user: "muratavci2405@gmail.com",
        pass: "tntmukfryhpxlkis"
    }
});

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

/**
 * 'updateUserCredentials' adında çağrılabilir bir bulut fonksiyonu.
 * Bir kullanıcının e-posta (kullanıcı adı) ve/veya şifresini günceller.
 *
 * Gerekli veriler (data):
 * - uid (String): Kullanıcının Firebase Auth ID'si
 * - newEmail (String, Opsiyonel): Yeni e-posta adresi
 * - newPassword (String, Opsiyonel): Yeni şifre
 */
exports.updateUserCredentials = onCall(async (request) => {
    const {data, auth} = request;
    // 1. Güvenlik Kontrolü
    if (!auth) {
      throw new HttpsError(
        "unauthenticated",
        "Bu işlemi yapmak için giriş yapmış olmalısınız."
      );
    }

    // 2. Verileri Al
    const { uid, newEmail, newPassword } = data;
    if (!uid) {
      throw new HttpsError(
        "invalid-argument",
        "Eksik bilgi: 'uid' gereklidir."
      );
    }

    try {
      const updateData = {};
      if (newEmail) updateData.email = newEmail;
      if (newPassword) updateData.password = newPassword;

      if (Object.keys(updateData).length === 0) {
         return { status: "no-change", message: "Güncellenecek veri gönderilmedi." };
      }

      // 3. Firebase Auth üzerinden kullanıcıyı güncelle
      await admin.auth().updateUser(uid, updateData);

      // 4. Başarı Mesajı Gönder
      return {
        status: "success",
        message: "Kullanıcı bilgileri başarıyla güncellendi.",
      };
    } catch (error) {
      console.error("Kullanıcı güncellenirken hata oluştu:", error);
      // Hatanın detaylarını (özellikle Auth hatalarını) istemciye daha net ilet
      throw new HttpsError(
        "internal",
        `Auth Hatası: ${error.message} (${error.code || 'unknown'})`
      );
    }
});
/**
 * 'sendPasswordResetCode' adında çağrılabilir bir bulut fonksiyonu.
 * Kullanıcı için 6 haneli bir kod üretir ve e-posta gönderir.
 */
exports.sendPasswordResetCode = onCall(async (request) => {
    const { data } = request;
    const { institutionId, username } = data;

    if (!institutionId || !username) {
        throw new HttpsError("invalid-argument", "Kurum ID ve kullanıcı adı gereklidir.");
    }

    try {
        // 1. Kullanıcıyı bul
        const userQuery = await db.collection("users")
            .where("institutionId", "==", institutionId.toUpperCase())
            .where("username", "==", username.toLowerCase())
            .limit(1)
            .get();

        if (userQuery.empty) {
            throw new HttpsError("not-found", "Bu bilgilerle eşleşen bir kullanıcı bulunamadı.");
        }

        const userData = userQuery.docs[0].data();
        const userEmail = userData.email;
        const uid = userQuery.docs[0].id;

        if (!userEmail) {
            throw new HttpsError("failed-precondition", "Kullanıcının kayıtlı bir e-posta adresi yok.");
        }

        // 2. 6 haneli kod üret
        const resetCode = Math.floor(100000 + Math.random() * 900000).toString();
        const expiresAt = new Date();
        expiresAt.setMinutes(expiresAt.getMinutes() + 10); // 10 dakika geçerli

        // 3. Firestore'a kaydet
        await db.collection("passwordResetCodes").doc(userEmail).set({
            code: resetCode,
            uid: uid,
            expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        });

        // 4. E-posta Gönder (Gerçek Gönderim)
        const mailOptions = {
            from: '"eduKN Destek" <muratavci2405@gmail.com>',
            to: userEmail,
            subject: `Şifre Sıfırlama Kodu: ${resetCode}`,
            html: `
                <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 500px; margin: 0 auto; padding: 20px; border: 1px solid #eee; border-radius: 15px; background-color: #fcfcfc;">
                    <div style="text-align: center; margin-bottom: 30px;">
                        <h1 style="color: #4C59BC; margin: 0;">eduKN</h1>
                        <p style="color: #666; font-size: 14px; margin-top: 5px;">Daha Planlı, Daha Hızlı</p>
                    </div>
                    <div style="background-color: #fff; padding: 25px; border-radius: 12px; box-shadow: 0 4px 10px rgba(0,0,0,0.03);">
                        <h2 style="color: #1E2661; margin-top: 0; font-size: 18px; text-align: center;">Şifre Sıfırlama İsteği</h2>
                        <p style="color: #555; font-size: 14px; line-height: 1.6; text-align: center;">
                            Hesabınız için şifre sıfırlama talebinde bulundunuz. Aşağıdaki kodu uygulamadaki ilgili alana girerek şifrenizi güncelleyebilirsiniz:
                        </p>
                        <div style="background-color: #f3f5ff; border: 1px dashed #4C59BC; padding: 15px; text-align: center; margin: 25px 0; border-radius: 10px;">
                            <span style="font-size: 32px; font-weight: bold; color: #4C59BC; letter-spacing: 5px;">${resetCode}</span>
                        </div>
                        <p style="color: #999; font-size: 12px; text-align: center; margin-bottom: 0;">
                            Bu kod <b>10 dakika</b> süreyle geçerlidir. Eğer bu isteği siz yapmadıysanız lütfen bu e-postayı dikkate almayın.
                        </p>
                    </div>
                    <div style="text-align: center; margin-top: 30px; color: #bbb; font-size: 12px;">
                        © 2024 eduKN. Tüm hakları saklıdır.
                    </div>
                </div>
            `
        };

        await transporter.sendMail(mailOptions);

        return {
            status: "success",
            message: "Sıfırlama kodu e-posta adresinize gönderildi.",
            email: userEmail
        };

    } catch (error) {
        console.error("Sıfırlama kodu gönderilirken hata:", error);
        throw new HttpsError("internal", error.message);
    }
});

/**
 * 'verifyCodeAndResetPassword' adında çağrılabilir bir bulut fonksiyonu.
 * Kodu doğrular ve yeni şifreyi ayarlar.
 */
exports.verifyCodeAndResetPassword = onCall(async (request) => {
    const { data } = request;
    const { email, code, newPassword } = data;

    if (!email || !code || !newPassword) {
        throw new HttpsError("invalid-argument", "Eksik bilgi: email, kod ve yeni şifre gereklidir.");
    }

    try {
        // 1. Kodu kontrol et
        const codeDoc = await db.collection("passwordResetCodes").doc(email).get();

        if (!codeDoc.exists) {
            throw new HttpsError("not-found", "Geçersiz veya süresi dolmuş kod.");
        }

        const codeData = codeDoc.data();
        
        // Kod kontrolü
        if (codeData.code !== code) {
            throw new HttpsError("permission-denied", "Girdiğiniz kod hatalı.");
        }

        // Süre kontrolü
        if (codeData.expiresAt.toDate() < new Date()) {
            await db.collection("passwordResetCodes").doc(email).delete();
            throw new HttpsError("deadline-exceeded", "Kodun süresi dolmuş. Lütfen yeni bir kod isteyin.");
        }

        // 2. Şifreyi Güncelle (Admin SDK)
        await admin.auth().updateUser(codeData.uid, {
            password: newPassword
        });

        // 3. Kodu sil
        await db.collection("passwordResetCodes").doc(email).delete();

        return {
            status: "success",
            message: "Şifreniz başarıyla güncellendi."
        };

    } catch (error) {
        console.error("Şifre sıfırlanırken hata:", error);
        throw new HttpsError("internal", error.message);
    }
});
