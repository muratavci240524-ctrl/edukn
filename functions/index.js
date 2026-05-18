const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
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

// ─────────────────────────────────────────────────────────────────────────────
// BİLDİRİM SİSTEMİ — FIRESTORE TRIGGER FONKSİYONLARI
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Hedef kullanıcı ID'lerini al, FCM token'larını Firestore'dan çek,
 * FCM bildirimi gönder ve Firestore'a in-app bildirim yaz.
 */
async function sendNotifications({ recipientUids, title, body, route, type, entityId }) {
    if (!recipientUids || recipientUids.length === 0) return;

    const uniqueUids = [...new Set(recipientUids)].filter(Boolean);

    // Tüm kullanıcıların token'larını topla
    const allTokens = [];
    const batch = db.batch();
    const now = admin.firestore.FieldValue.serverTimestamp();

    for (const uid of uniqueUids) {
        try {
            const userDoc = await db.collection("users").doc(uid).get();
            if (!userDoc.exists) continue;

            const userData = userDoc.data();
            
            // Bildirim ayarlarını kontrol et
            const settings = userData.notificationSettings || {};
            const typeMap = {
                'etut': 'studies',
                'announcement': 'announcements',
                'message': 'messages',
                'homework': 'homeworks',
                'exam': 'exams'
            };
            const settingKey = typeMap[type] || type;
            if (settings[settingKey] === false) {
                console.log(`ℹ️ Kullanıcı ${uid} için ${type} bildirimi kapalı, atlanıyor.`);
                continue;
            }

            const tokens = userData.fcmTokens || [];
            allTokens.push(...tokens);

            // In-app bildirim yaz
            const notifRef = db.collection("notifications").doc(uid).collection("items").doc();
            batch.set(notifRef, {
                title,
                body,
                route: route || "/school-dashboard",
                type: type || "general",
                entityId: entityId || null,
                isRead: false,
                createdAt: now,
            });
        } catch (err) {
            console.error(`Kullanıcı ${uid} için bildirim hazırlanamadı:`, err);
        }
    }

    // In-app bildirimleri toplu kaydet
    try {
        await batch.commit();
        console.log(`✅ ${uniqueUids.length} kullanıcıya in-app bildirim yazıldı.`);
    } catch (err) {
        console.error("In-app bildirim yazma hatası:", err);
    }

    // FCM Push Gönder
    if (allTokens.length > 0) {
        const message = {
            notification: { title, body },
            data: { route: route || "/school-dashboard", entityId: entityId || "", type: type || "general" },
            tokens: allTokens,
            webpush: {
                notification: {
                    icon: "/icons/Icon-192.png",
                    badge: "/icons/Icon-192.png",
                    click_action: route || "/school-dashboard",
                },
            },
        };

        try {
            const response = await admin.messaging().sendEachForMulticast(message);
            console.log(`✅ FCM: ${response.successCount} başarılı, ${response.failureCount} başarısız.`);

            // Geçersiz token'ları temizle
            response.responses.forEach(async (resp, idx) => {
                if (!resp.success && (resp.error?.code === "messaging/invalid-registration-token" ||
                    resp.error?.code === "messaging/registration-token-not-registered")) {
                    const invalidToken = allTokens[idx];
                    // Token'ı tüm kullanıcılardan kaldır
                    for (const uid of uniqueUids) {
                        await db.collection("users").doc(uid).update({
                            fcmTokens: admin.firestore.FieldValue.arrayRemove(invalidToken),
                        }).catch(() => {});
                    }
                }
            });
        } catch (err) {
            console.error("FCM gönderme hatası:", err);
        }
    }
}

/**
 * Kurum ID'sine göre tüm aktif kullanıcıların UID'lerini getirir.
 */
async function getInstitutionUserUids(institutionId) {
    const snapshot = await db.collection("users")
        .where("institutionId", "==", institutionId)
        .where("isActive", "==", true)
        .get();
    return snapshot.docs.map(doc => doc.id);
}

// ─── 1. ETÜTLERe BİLDİRİM ────────────────────────────────────────────────────
exports.onEtutCreated = onDocumentCreated("etut_requests/{etutId}", async (event) => {
    const etut = event.data?.data();
    if (!etut) return;

    const { institutionId, dersAdi, teacherName, className, studentIds = [] } = etut;

    const title = `📚 Yeni Etüt: ${dersAdi || "Ders"}`;
    const body = `${teacherName || "Öğretmen"} · ${className || "Grup"}`;

    // Hedefler: atanan öğrencilerin velileri + kurum yöneticileri
    let recipientUids = [];

    // Kurum yöneticilerini ekle
    const adminUids = await getInstitutionUserUids(institutionId);
    recipientUids.push(...adminUids);

    // Öğrencilerin velilerini bul
    for (const studentId of studentIds) {
        try {
            const studentDoc = await db.collection("students").doc(studentId).get();
            if (!studentDoc.exists) continue;
            const student = studentDoc.data();
            const parentTcNos = student.parentTcNos || [];
            for (const tcNo of parentTcNos) {
                const parentQuery = await db.collection("users")
                    .where("tcNo", "==", tcNo)
                    .where("role", "==", "parent")
                    .limit(1).get();
                if (!parentQuery.empty) {
                    recipientUids.push(parentQuery.docs[0].id);
                }
            }
        } catch (err) {
            console.error("Veli bulma hatası:", err);
        }
    }

    await sendNotifications({
        recipientUids,
        title,
        body,
        route: "/school-dashboard",
        type: "etut",
        entityId: event.params.etutId,
    });
});

// ─── 2. DUYURULARA BİLDİRİM ──────────────────────────────────────────────────
exports.onAnnouncementCreated = onDocumentCreated(
    "schools/{schoolId}/announcements/{announcementId}",
    async (event) => {
        const announcement = event.data?.data();
        if (!announcement) return;

        const { institutionId, title: annTitle, content } = announcement;
        if (!institutionId) return;

        const recipientUids = await getInstitutionUserUids(institutionId);

        await sendNotifications({
            recipientUids,
            title: `📢 Duyuru: ${annTitle || "Yeni Duyuru"}`,
            body: (content || "").substring(0, 100),
            route: "/announcements",
            type: "announcement",
            entityId: event.params.announcementId,
        });
    }
);

// ─── 3. MESAJLARA BİLDİRİM ───────────────────────────────────────────────────
exports.onMessageSent = onDocumentCreated(
    "conversations/{conversationId}/messages/{messageId}",
    async (event) => {
        const message = event.data?.data();
        if (!message) return;

        const { senderId, senderName, content, participants = [] } = message;

        // Gönderici hariç katılımcılara bildir
        const recipientUids = participants.filter(uid => uid !== senderId);
        if (recipientUids.length === 0) return;

        await sendNotifications({
            recipientUids,
            title: `💬 ${senderName || "Yeni Mesaj"}`,
            body: (content || "").substring(0, 100),
            route: "/school-dashboard",
            type: "message",
            entityId: event.params.conversationId,
        });
    }
);

// ─── 4. ÖDEVLERE BİLDİRİM ────────────────────────────────────────────────────
exports.onHomeworkCreated = onDocumentCreated("homeworks/{homeworkId}", async (event) => {
    const homework = event.data?.data();
    if (!homework) return;

    const { institutionId, title: hwTitle, schoolTypeId } = homework;
    if (!institutionId) return;

    const recipientUids = await getInstitutionUserUids(institutionId);

    await sendNotifications({
        recipientUids,
        title: `📝 Yeni Ödev: ${hwTitle || "Ödev"}`,
        body: "Öğretmen tarafından yeni ödev eklendi.",
        route: "/school-dashboard",
        type: "homework",
        entityId: event.params.homeworkId,
    });
});

// ─── 5. DENEME SINAVI YÜKLENDİĞİNDE BİLDİRİM ─────────────────────────────────
exports.onTrialExamCreated = onDocumentCreated("trial_exams/{examId}", async (event) => {
    const exam = event.data?.data();
    if (!exam) return;

    const { institutionId, examName } = exam;
    if (!institutionId) return;

    const recipientUids = await getInstitutionUserUids(institutionId);

    await sendNotifications({
        recipientUids,
        title: `📊 Deneme Yüklendi: ${examName || "Yeni Deneme"}`,
        body: "Yeni deneme sınavı sonuçları sisteme yüklendi.",
        route: "/school-dashboard",
        type: "exam",
        entityId: event.params.examId,
    });
});

// ─── 6. KAMP ÖĞRETMEN HAFTALIK DERS PROGRAMI E-POSTA GÖNDERİMİ ───────────────
exports.sendCampProgramEmail = onCall(async (request) => {
    const { data, auth } = request;
    
    // 1. Güvenlik Kontrolü
    if (!auth) {
        throw new HttpsError(
            "unauthenticated",
            "Bu işlemi yapmak için giriş yapmış olmalısınız."
        );
    }

    const { email, teacherName, cycleName, cycleStartDate, pdfBase64, fileName } = data;

    if (!email || !teacherName || !cycleName || !pdfBase64) {
        throw new HttpsError(
            "invalid-argument",
            "Eksik bilgi gönderildi. 'email', 'teacherName', 'cycleName' ve 'pdfBase64' alanları zorunludur."
        );
    }

    try {
        let startDate = cycleStartDate;
        if (!startDate) {
            const dt = new Date();
            const d = String(dt.getDate()).padStart(2, '0');
            const m = String(dt.getMonth() + 1).padStart(2, '0');
            const y = dt.getFullYear();
            startDate = `${d}.${m}.${y}`;
        }

        const mailOptions = {
            from: '"eduKN Destek" <muratavci2405@gmail.com>',
            to: email,
            subject: `eduKN Kamp: ${startDate} Tarihli Kamp Programı`,
            html: `
                <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto; padding: 30px; border: 1px solid #e2e8f0; border-radius: 20px; background-color: #f8fafc;">
                    <div style="text-align: center; margin-bottom: 25px;">
                        <div style="display: inline-block; vertical-align: middle;">
                            <table cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto;">
                                <tr>
                                    <td style="vertical-align: middle; padding-right: 10px;">
                                        <svg width="45" height="38" viewBox="0 0 120 100" style="display: block;">
                                            <g transform="skewX(-15) translate(15, 0)">
                                                <path d="M0,15 L35,15 L55,40 L35,65 L0,65 L20,40 Z" fill="url(#grad1)" />
                                                <path d="M25,15 L60,15 L80,40 L60,65 L25,65 L45,40 Z" fill="url(#grad2)" />
                                                <path d="M50,15 L85,15 L105,40 L85,65 L50,65 L70,40 Z" fill="#60A5FA" />
                                            </g>
                                            <defs>
                                                <linearGradient id="grad1" x1="0%" y1="0%" x2="100%" y2="100%">
                                                    <stop offset="0%" stop-color="#1E3A8A" stop-opacity="0.9" />
                                                    <stop offset="100%" stop-color="#2563EB" stop-opacity="0.9" />
                                                </linearGradient>
                                                <linearGradient id="grad2" x1="0%" y1="0%" x2="100%" y2="100%">
                                                    <stop offset="0%" stop-color="#2563EB" stop-opacity="0.9" />
                                                    <stop offset="100%" stop-color="#60A5FA" stop-opacity="0.9" />
                                                </linearGradient>
                                            </defs>
                                        </svg>
                                    </td>
                                    <td style="vertical-align: middle;">
                                        <span style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; font-size: 34px; font-weight: 900; font-style: italic; letter-spacing: -1.5px; color: #1e1b4b; line-height: 1;">
                                            edu<span style="color: #3b82f6;">KN</span>
                                        </span>
                                    </td>
                                </tr>
                            </table>
                        </div>
                        <p style="color: #64748b; font-size: 14px; margin-top: 8px; font-weight: 500;">Okul Yönetim Sistemi</p>
                    </div>
                    <div style="background-color: #ffffff; padding: 35px; border-radius: 16px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.05), 0 2px 4px -1px rgba(0,0,0,0.03);">
                        <h2 style="color: #1e1b4b; margin-top: 0; font-size: 20px; font-weight: 700;">Sayın ${teacherName},</h2>
                        <p style="color: #334155; font-size: 15px; line-height: 1.6; margin-top: 15px;">
                            Kurumunuz tarafından düzenlenen <strong>${cycleName}</strong> kapsamındaki <strong>${startDate} tarihli ders ve soru çözüm programınız</strong> hazırlanmıştır.
                        </p>
                        <p style="color: #334155; font-size: 15px; line-height: 1.6;">
                            Size özel olarak oluşturulan detaylı programınız, derslikleriniz, ders saatleriniz ve öğrenci listeleriniz bu e-postanın ekinde PDF formatında yer almaktadır.
                        </p>
                        <div style="margin: 30px 0; padding: 20px; background-color: #eef2ff; border-left: 4px solid #4f46e5; border-radius: 8px;">
                            <h3 style="color: #4338ca; margin: 0 0 8px 0; font-size: 14px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px;">Bilgilendirme</h3>
                            <p style="color: #3730a3; margin: 0; font-size: 13px; line-height: 1.5;">
                                Kamp süresince başarı oranı %95 ve üzeri olan öğrenci gruplarında sistem tarafından otomatik olarak <strong>Soru Çözümü</strong> çalışması planlanmıştır. Program detaylarına ekteki belgeden ulaşabilirsiniz.
                            </p>
                        </div>
                        <p style="color: #64748b; font-size: 13px; line-height: 1.6; margin-bottom: 0; text-align: center;">
                            İyi dersler ve başarılı bir kamp dönemi dileriz.
                        </p>
                    </div>
                    <div style="text-align: center; margin-top: 30px; color: #94a3b8; font-size: 12px; font-weight: 500;">
                        © ${new Date().getFullYear()} eduKN. Tüm hakları saklıdır.<br>
                        <span style="color: #94a3b8; font-size: 11px;">Bu e-posta otomatik olarak gönderilmiştir, lütfen yanıtlamayınız.</span>
                    </div>
                </div>
            `,
            attachments: [
                {
                    filename: fileName || 'kamp_ders_programi.pdf',
                    content: pdfBase64,
                    encoding: 'base64'
                }
            ]
        };

        await transporter.sendMail(mailOptions);

        return {
            status: "success",
            message: "Kamp programı e-posta ile başarıyla gönderildi."
        };

    } catch (error) {
        console.error("Kamp programı mail gönderim hatası:", error);
        throw new HttpsError("internal", error.message || "E-posta gönderilirken sunucu hatası oluştu.");
    }
});

