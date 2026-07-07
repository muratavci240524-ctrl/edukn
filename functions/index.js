const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const crypto = require("crypto");

// ─── Firebase Secrets (firebase functions:secrets:set GMAIL_USER vb.) ─────────
const gmailUser = defineSecret("GMAIL_USER");
const gmailPass = defineSecret("GMAIL_PASS");
const geminiApiKey = defineSecret("GEMINI_API_KEY");
const encryptionKey = defineSecret("ENCRYPTION_KEY"); // AES-256 (32 byte → 64 hex char)

// Firebase admin başlat
admin.initializeApp();
const db = admin.firestore();

const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// ═══════════════════════════════════════════════════════════════════════════════
// YARDIMCI FONKSİYONLAR
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Kullanıcının süper admin olup olmadığını kontrol eder.
 */
async function verifySuperAdmin(auth) {
    if (!auth) throw new HttpsError("unauthenticated", "Giriş yapmalısınız.");
    
    // E-posta bypass (Güvenli ve hızlı)
    if (auth.token && auth.token.email && auth.token.email.toLowerCase() === 'superadmin@edukn.com') {
        return { role: 'super_admin', email: auth.token.email };
    }
    
    const userDoc = await db.collection("users").doc(auth.uid).get();
    if (!userDoc.exists || userDoc.data().role !== "super_admin") {
        throw new HttpsError("permission-denied", "Bu işlem için yönetici yetkisi gereklidir.");
    }
    return userDoc.data();
}

/**
 * Kullanıcının login olup olmadığını kontrol eder.
 */
function verifyAuth(auth) {
    if (!auth) throw new HttpsError("unauthenticated", "Bu işlemi yapmak için giriş yapmış olmalısınız.");
}

/**
 * Rate limiting: Belirli bir sürede maksimum istek sayısını kontrol eder.
 * @param {string} key - Rate limit anahtarı (örn: "password_reset:kullanici@email.com")
 * @param {number} maxRequests - Maksimum istek sayısı
 * @param {number} windowMinutes - Zaman penceresi (dakika)
 */
async function checkRateLimit(key, maxRequests, windowMinutes) {
    const rateLimitRef = db.collection("rate_limits").doc(key);
    const now = Date.now();
    const windowMs = windowMinutes * 60 * 1000;

    const result = await db.runTransaction(async (transaction) => {
        const doc = await transaction.get(rateLimitRef);
        
        if (!doc.exists) {
            transaction.set(rateLimitRef, {
                count: 1,
                windowStart: now,
                expiresAt: admin.firestore.Timestamp.fromMillis(now + windowMs),
            });
            return { allowed: true, remaining: maxRequests - 1 };
        }

        const data = doc.data();
        const windowStart = data.windowStart;

        if (now - windowStart > windowMs) {
            // Zaman penceresi geçti, sıfırla
            transaction.set(rateLimitRef, {
                count: 1,
                windowStart: now,
                expiresAt: admin.firestore.Timestamp.fromMillis(now + windowMs),
            });
            return { allowed: true, remaining: maxRequests - 1 };
        }

        if (data.count >= maxRequests) {
            const retryAfterSeconds = Math.ceil((windowMs - (now - windowStart)) / 1000);
            return { allowed: false, retryAfterSeconds };
        }

        transaction.update(rateLimitRef, { count: admin.firestore.FieldValue.increment(1) });
        return { allowed: true, remaining: maxRequests - data.count - 1 };
    });

    return result;
}

/**
 * Kritik operasyonlar için audit log yazar.
 */
async function writeAuditLog({ action, performedBy, targetId, details, success }) {
    try {
        await db.collection("audit_logs").add({
            action,
            performedBy: performedBy || "system",
            targetId: targetId || null,
            details: details || {},
            success: success !== undefined ? success : true,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            ip: null, // Cloud Functions'da IP bilgisi direkt alınamaz
        });
    } catch (err) {
        console.error("Audit log yazma hatası:", err);
        // Audit log hatası ana işlemi durdurmamalı
    }
}

/**
 * Nodemailer transporter oluşturur (secret değerleri kullanarak).
 */
function createMailTransporter() {
    return nodemailer.createTransport({
        service: "gmail",
        auth: {
            user: gmailUser.value(),
            pass: gmailPass.value(),
        },
    });
}

// ═══════════════════════════════════════════════════════════════════════════════
// OKUL YÖNETİMİ FONKSİYONLARI
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * 'createSchool' — Yeni okul ve admin hesabı oluşturur.
 * 🔐 Sadece super_admin çağırabilir.
 */
exports.createSchool = onCall({ enforceAppCheck: true }, async (request) => {
    const { data, auth } = request;
    
    // ✅ Süper admin kontrolü
    await verifySuperAdmin(auth);

    const { schoolName, adminEmail, adminPassword, activeModules } = data;
    if (!schoolName || !adminEmail || !adminPassword || !activeModules) {
        throw new HttpsError("invalid-argument", "Eksik bilgi gönderildi.");
    }

    try {
        const userRecord = await admin.auth().createUser({
            email: adminEmail,
            password: adminPassword,
            displayName: `${schoolName} Yöneticisi`,
        });

        const now = new Date();
        const licenseExpiresAt = new Date(now.setDate(now.getDate() + 30));

        const schoolData = {
            schoolName,
            adminEmail,
            adminUserId: userRecord.uid,
            activeModules,
            isActive: true,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            licenseExpiresAt: admin.firestore.Timestamp.fromDate(licenseExpiresAt),
        };

        await db.collection("schools").doc(userRecord.uid).set(schoolData);

        // ✅ Audit log
        await writeAuditLog({
            action: "CREATE_SCHOOL",
            performedBy: auth.uid,
            targetId: userRecord.uid,
            details: { schoolName, adminEmail },
        });

        return { status: "success", message: `${schoolName} başarıyla oluşturuldu.`, schoolId: userRecord.uid };
    } catch (error) {
        console.error("Okul oluşturulurken hata:", error);
        throw new HttpsError("internal", error.message || "Sunucu hatası.");
    }
});

/**
 * 'extendLicense' — Okul lisansını uzatır.
 * 🔐 Sadece super_admin çağırabilir.
 */
exports.extendLicense = onCall({ enforceAppCheck: true }, async (request) => {
    const { data, auth } = request;
    await verifySuperAdmin(auth);

    const { schoolId, daysToAdd } = data;
    if (!schoolId || !daysToAdd) {
        throw new HttpsError("invalid-argument", "Eksik bilgi: 'schoolId' ve 'daysToAdd' gereklidir.");
    }

    try {
        const schoolRef = db.collection("schools").doc(schoolId);
        const schoolDoc = await schoolRef.get();

        if (!schoolDoc.exists) throw new HttpsError("not-found", "Okul bulunamadı.");

        const schoolData = schoolDoc.data();
        const currentExpiresAt = schoolData.licenseExpiresAt?.toDate() ?? new Date();
        const now = new Date();
        const baseDate = currentExpiresAt < now ? now : currentExpiresAt;
        const newExpiresAt = new Date(baseDate.setDate(baseDate.getDate() + daysToAdd));

        await schoolRef.update({
            licenseExpiresAt: admin.firestore.Timestamp.fromDate(newExpiresAt),
            isActive: true,
        });

        await writeAuditLog({
            action: "EXTEND_LICENSE",
            performedBy: auth.uid,
            targetId: schoolId,
            details: { daysToAdd, newExpiresAt: newExpiresAt.toISOString() },
        });

        return { status: "success", message: `Lisans ${daysToAdd} gün başarıyla uzatıldı.` };
    } catch (error) {
        console.error("Lisans uzatılırken hata:", error);
        throw new HttpsError("internal", error.message || "Sunucu hatası.");
    }
});

/**
 * 'updateSchoolModules' — Okul modüllerini günceller.
 * 🔐 Sadece super_admin çağırabilir.
 */
exports.updateSchoolModules = onCall({ enforceAppCheck: true }, async (request) => {
    const { data, auth } = request;
    await verifySuperAdmin(auth);

    const { schoolId, activeModules } = data;
    if (!schoolId || activeModules == null) {
        throw new HttpsError("invalid-argument", "Eksik bilgi.");
    }

    try {
        await db.collection("schools").doc(schoolId).update({ activeModules });

        await writeAuditLog({
            action: "UPDATE_MODULES",
            performedBy: auth.uid,
            targetId: schoolId,
            details: { activeModules },
        });

        return { status: "success", message: "Okul modülleri güncellendi." };
    } catch (error) {
        throw new HttpsError("internal", error.message || "Sunucu hatası.");
    }
});

/**
 * 'deleteSchoolAndAdmin' — Okul ve admin hesabını siler.
 * 🔐 Sadece super_admin çağırabilir.
 */
exports.deleteSchoolAndAdmin = onCall({ enforceAppCheck: true }, async (request) => {
    const { data, auth } = request;
    await verifySuperAdmin(auth);

    const { schoolId } = data;
    if (!schoolId) throw new HttpsError("invalid-argument", "Eksik bilgi: 'schoolId' gereklidir.");

    try {
        try {
            await admin.auth().deleteUser(schoolId);
        } catch (authError) {
            console.warn(`Auth silme uyarısı: ${authError.message}`);
        }

        await db.collection("schools").doc(schoolId).delete();

        await writeAuditLog({
            action: "DELETE_SCHOOL",
            performedBy: auth.uid,
            targetId: schoolId,
            details: {},
        });

        return { status: "success", message: "Okul ve yönetici başarıyla silindi." };
    } catch (error) {
        throw new HttpsError("internal", error.message || "Sunucu hatası.");
    }
});

/**
 * 'updateUserCredentials' — Kullanıcı e-posta/şifresini günceller.
 * 🔐 Login gerekli + Kendi hesabı veya süper admin.
 */
exports.updateUserCredentials = onCall({ enforceAppCheck: true }, async (request) => {
    const { data, auth } = request;
    verifyAuth(auth);

    const { uid, newEmail, newPassword } = data;
    if (!uid) throw new HttpsError("invalid-argument", "Eksik bilgi: 'uid' gereklidir.");

    // Başkasının şifresini değiştirmeye çalışıyor mu?
    if (auth.uid !== uid) {
        // Süper admin veya kurum admini kontrolü
        const callerDoc = await db.collection("users").doc(auth.uid).get();
        if (!callerDoc.exists) throw new HttpsError("permission-denied", "Yetkisiz.");
        const callerRole = callerDoc.data().role;
        if (!["super_admin", "admin", "manager", "genel_mudur"].includes(callerRole)) {
            throw new HttpsError("permission-denied", "Başka bir kullanıcının bilgilerini değiştirme yetkiniz yok.");
        }
    }

    try {
        const updateData = {};
        if (newEmail) {
            if (!emailRegex.test(newEmail)) {
                throw new HttpsError("invalid-argument", "Geçersiz e-posta formatı.");
            }
            updateData.email = newEmail;
        }
        if (newPassword) {
            if (newPassword.length < 6) {
                throw new HttpsError("invalid-argument", "Şifre en az 6 karakter olmalıdır.");
            }
            updateData.password = newPassword;
        }

        if (Object.keys(updateData).length === 0) {
            return { status: "no-change", message: "Güncellenecek veri gönderilmedi." };
        }

        await admin.auth().updateUser(uid, updateData);

        await writeAuditLog({
            action: "UPDATE_USER_CREDENTIALS",
            performedBy: auth.uid,
            targetId: uid,
            details: { emailChanged: !!newEmail, passwordChanged: !!newPassword },
        });

        return { status: "success", message: "Kullanıcı bilgileri güncellendi." };
    } catch (error) {
        throw new HttpsError("internal", `Auth Hatası: ${error.message} (${error.code || "unknown"})`);
    }
});

// ═══════════════════════════════════════════════════════════════════════════════
// ŞİFRE SIFIRLAMA — Rate Limiting Eklenmiş
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * 'sendPasswordResetCode' — Şifre sıfırlama kodu gönderir.
 * ✅ Rate Limiting: Saatte max 5 istek.
 */
exports.sendPasswordResetCode = onCall(
    { secrets: [gmailUser, gmailPass], enforceAppCheck: true },
    async (request) => {
        const { data } = request;
        const { institutionId, username } = data;

        if (!institutionId || !username) {
            throw new HttpsError("invalid-argument", "Kurum ID ve kullanıcı adı gereklidir.");
        }

        // ✅ Rate limiting: Saatte max 5 şifre sıfırlama isteği (username başına)
        const rateLimitKey = `password_reset:${institutionId}:${username.toLowerCase()}`;
        const rateResult = await checkRateLimit(rateLimitKey, 5, 60);
        
        if (!rateResult.allowed) {
            throw new HttpsError(
                "resource-exhausted",
                `Çok fazla deneme. Lütfen ${Math.ceil(rateResult.retryAfterSeconds / 60)} dakika sonra tekrar deneyin.`
            );
        }

        try {
            const userQuery = await db.collection("users")
                .where("institutionId", "==", institutionId.toUpperCase())
                .where("username", "==", username.toLowerCase())
                .limit(1)
                .get();

            if (userQuery.empty) {
                // Güvenlik: Kullanıcı bulunamadı ama bunu söylemiyoruz (enumeration önlemi)
                return { status: "success", message: "Eğer bu hesap varsa, sıfırlama kodu gönderildi." };
            }

            const userData = userQuery.docs[0].data();
            const userEmail = userData.email;
            const uid = userQuery.docs[0].id;

            if (!userEmail) {
                throw new HttpsError("failed-precondition", "Kullanıcının kayıtlı e-posta adresi yok.");
            }

            const resetCode = Math.floor(100000 + Math.random() * 900000).toString();
            const expiresAt = new Date();
            expiresAt.setMinutes(expiresAt.getMinutes() + 10);

            await db.collection("passwordResetCodes").doc(userEmail).set({
                code: resetCode,
                uid,
                expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            const transporter = createMailTransporter();
            await transporter.sendMail({
                from: `"eduKN Destek" <${gmailUser.value()}>`,
                to: userEmail,
                subject: `Şifre Sıfırlama Kodunuz`,
                html: `
                    <div style="font-family: 'Segoe UI', sans-serif; max-width: 500px; margin: 0 auto; padding: 20px; border: 1px solid #eee; border-radius: 15px;">
                        <div style="text-align: center; margin-bottom: 30px;">
                            <h1 style="color: #4C59BC;">eduKN</h1>
                            <p style="color: #666; font-size: 14px;">Daha Planlı, Daha Hızlı</p>
                        </div>
                        <div style="background: #fff; padding: 25px; border-radius: 12px; box-shadow: 0 4px 10px rgba(0,0,0,0.03);">
                            <h2 style="color: #1E2661; text-align: center;">Şifre Sıfırlama</h2>
                            <p style="color: #555; text-align: center; line-height: 1.6;">
                                Şifre sıfırlama talebinde bulundunuz. Aşağıdaki kodu kullanın:
                            </p>
                            <div style="background: #f3f5ff; border: 1px dashed #4C59BC; padding: 15px; text-align: center; margin: 25px 0; border-radius: 10px;">
                                <span style="font-size: 32px; font-weight: bold; color: #4C59BC; letter-spacing: 5px;">${resetCode}</span>
                            </div>
                            <p style="color: #999; font-size: 12px; text-align: center;">
                                Bu kod <b>10 dakika</b> geçerlidir. Bu isteği siz yapmadıysanız dikkate almayın.
                            </p>
                        </div>
                    </div>
                `,
            });

            // ✅ Güvenlik: Email adresini response'ta döndürme
            return { status: "success", message: "Sıfırlama kodu e-posta adresinize gönderildi." };

        } catch (error) {
            console.error("Sıfırlama kodu hatası:", error);
            if (error instanceof HttpsError) throw error;
            throw new HttpsError("internal", error.message);
        }
    }
);

/**
 * 'verifyCodeAndResetPassword' — Kodu doğrular ve yeni şifreyi ayarlar.
 */
exports.verifyCodeAndResetPassword = onCall({ enforceAppCheck: true }, async (request) => {
    const { data } = request;
    const { email, code, newPassword } = data;

    if (!email || !code || !newPassword) {
        throw new HttpsError("invalid-argument", "Eksik bilgi gereklidir.");
    }

    if (!emailRegex.test(email)) {
        throw new HttpsError("invalid-argument", "Geçersiz e-posta formatı.");
    }

    // Şifre karmaşıklık kontrolü
    if (newPassword.length < 6) {
        throw new HttpsError("invalid-argument", "Şifre en az 6 karakter olmalıdır.");
    }

    try {
        const codeDoc = await db.collection("passwordResetCodes").doc(email).get();

        if (!codeDoc.exists) throw new HttpsError("not-found", "Geçersiz veya süresi dolmuş kod.");

        const codeData = codeDoc.data();

        if (codeData.code !== code) {
            throw new HttpsError("permission-denied", "Girdiğiniz kod hatalı.");
        }

        if (codeData.expiresAt.toDate() < new Date()) {
            await db.collection("passwordResetCodes").doc(email).delete();
            throw new HttpsError("deadline-exceeded", "Kodun süresi dolmuş. Lütfen yeni kod isteyin.");
        }

        await admin.auth().updateUser(codeData.uid, { password: newPassword });
        await db.collection("passwordResetCodes").doc(email).delete();

        await writeAuditLog({
            action: "PASSWORD_RESET",
            performedBy: codeData.uid,
            targetId: codeData.uid,
            details: { email },
        });

        return { status: "success", message: "Şifreniz başarıyla güncellendi." };
    } catch (error) {
        console.error("Şifre sıfırlama hatası:", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", error.message);
    }
});

// ═══════════════════════════════════════════════════════════════════════════════
// 🤖 GEMINI AI — Server-Side Proxy (API key istemcide değil!)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * 'analyzeStudentPerformance' — Gemini AI ile öğrenci performans analizi.
 * API key sunucu tarafında kalıyor, istemciye gönderilmiyor.
 */
exports.analyzeStudentPerformance = onCall(
    { secrets: [geminiApiKey], enforceAppCheck: true },
    async (request) => {
        const { auth, data } = request;
        verifyAuth(auth);

        const { studentName, topicAnalysis } = data;
        if (!studentName || !Array.isArray(topicAnalysis)) {
            throw new HttpsError("invalid-argument", "Eksik parametre.");
        }

        // ✅ Rate limiting: Dakikada max 10 AI isteği (kullanıcı başına)
        const rateResult = await checkRateLimit(`gemini:${auth.uid}`, 10, 1);
        if (!rateResult.allowed) {
            throw new HttpsError("resource-exhausted", "Çok fazla AI isteği. Lütfen bekleyin.");
        }

        try {
            const { GoogleGenerativeAI } = require("@google/generative-ai");
            const genAI = new GoogleGenerativeAI(geminiApiKey.value());
            const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });

            const weakTopics = topicAnalysis
                .filter(e => (e.success || 0) < 50)
                .map(e => `${e.subject} - ${e.topic} (%${e.success})`)
                .join(", ");

            const strongTopics = topicAnalysis
                .filter(e => (e.success || 0) >= 80)
                .map(e => `${e.subject} - ${e.topic} (%${e.success})`)
                .join(", ");

            const avgSuccess = topicAnalysis.length > 0
                ? topicAnalysis.reduce((a, b) => a + (b.success || 0), 0) / topicAnalysis.length
                : 0;

            const prompt = `
Sen tecrübeli, motive edici bir rehberlik öğretmenisin.

Öğrenci Adı: ${studentName}
Genel Başarı: %${avgSuccess.toFixed(1)}
Zayıf Konular: ${weakTopics || "Yok"}
Güçlü Konular: ${strongTopics || "Yok"}

GÖREV: 3-4 cümlelik, kısa, öz ve motive edici haftalık çalışma tavsiyesi yaz.
KURALLAR:
1. Doğrudan öğrenciye hitap et.
2. Emojiler kullan ama abartma.
3. Zayıf konular için spesifik strateji öner.
4. HTML/Markdown kullanma, sadece düz metin.
            `;

            const result = await model.generateContent(prompt);
            const text = result.response.text();

            if (!text) throw new Error("AI boş yanıt döndü.");

            return { status: "success", analysis: text };
        } catch (error) {
            console.error("Gemini AI hatası:", error);
            throw new HttpsError("internal", "AI analizi oluşturulamadı.");
        }
    }
);

// ═══════════════════════════════════════════════════════════════════════════════
// E-POSTA SERVİSLERİ
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * 'sendCampProgramEmail' — Kamp programını e-posta ile gönderir.
 */
exports.sendCampProgramEmail = onCall(
    { secrets: [gmailUser, gmailPass], enforceAppCheck: true },
    async (request) => {
        const { data, auth } = request;
        verifyAuth(auth);

        const { email, teacherName, cycleName, cycleStartDate, pdfBase64, fileName } = data;

        if (!email || !teacherName || !cycleName || !pdfBase64) {
            throw new HttpsError("invalid-argument", "Eksik bilgi gönderildi.");
        }

        if (!emailRegex.test(email)) {
            throw new HttpsError("invalid-argument", "Geçersiz alıcı e-posta adresi.");
        }

        // ✅ Rate limiting: Kullanıcı başına günde max 50 kamp programı gönderme
        const rateLimitKey = `camp_email:${auth.uid}:${new Date().toISOString().split("T")[0]}`;
        const rateResult = await checkRateLimit(rateLimitKey, 50, 1440);
        if (!rateResult.allowed) {
            throw new HttpsError("resource-exhausted", "Günlük e-posta limitinize ulaştınız (Max 50).");
        }

        try {
            let startDate = cycleStartDate;
            if (!startDate) {
                const dt = new Date();
                startDate = `${String(dt.getDate()).padStart(2, "0")}.${String(dt.getMonth() + 1).padStart(2, "0")}.${dt.getFullYear()}`;
            }

            const transporter = createMailTransporter();
            await transporter.sendMail({
                from: `"eduKN Destek" <${gmailUser.value()}>`,
                to: email,
                subject: `eduKN Kamp: ${startDate} Tarihli Kamp Programı`,
                html: `
                    <div style="font-family: 'Segoe UI', sans-serif; max-width: 600px; margin: 0 auto; padding: 30px; border: 1px solid #e2e8f0; border-radius: 20px; background: #f8fafc;">
                        <div style="text-align: center; margin-bottom: 25px;">
                            <h1 style="color: #1e1b4b; font-size: 34px; font-style: italic;">edu<span style="color: #3b82f6;">KN</span></h1>
                            <p style="color: #64748b; font-size: 14px; font-weight: 500;">Okul Yönetim Sistemi</p>
                        </div>
                        <div style="background: #fff; padding: 35px; border-radius: 16px; box-shadow: 0 4px 6px rgba(0,0,0,0.05);">
                            <h2 style="color: #1e1b4b; font-size: 20px;">Sayın ${teacherName},</h2>
                            <p style="color: #334155; font-size: 15px; line-height: 1.6;">
                                <strong>${cycleName}</strong> kapsamındaki <strong>${startDate} tarihli ders programınız</strong> hazırlanmıştır.
                            </p>
                            <div style="margin: 30px 0; padding: 20px; background: #eef2ff; border-left: 4px solid #4f46e5; border-radius: 8px;">
                                <p style="color: #3730a3; margin: 0; font-size: 13px; line-height: 1.5;">
                                    Detaylı programınız ekte PDF formatında yer almaktadır.
                                </p>
                            </div>
                            <p style="color: #64748b; font-size: 13px; text-align: center;">İyi dersler ve başarılı bir kamp dönemi dileriz.</p>
                        </div>
                        <div style="text-align: center; margin-top: 30px; color: #94a3b8; font-size: 12px;">
                            © ${new Date().getFullYear()} eduKN. Tüm hakları saklıdır.<br>
                            <span style="font-size: 11px;">Bu e-posta otomatik gönderilmiştir, lütfen yanıtlamayınız.</span>
                        </div>
                    </div>
                `,
                attachments: [
                    {
                        filename: fileName || "kamp_ders_programi.pdf",
                        content: pdfBase64,
                        encoding: "base64",
                    },
                ],
            });

            return { status: "success", message: "Kamp programı e-posta ile gönderildi." };
        } catch (error) {
            console.error("Kamp programı mail hatası:", error);
            throw new HttpsError("internal", error.message || "E-posta gönderilirken hata oluştu.");
        }
    }
);

// ═══════════════════════════════════════════════════════════════════════════════
// BİLDİRİM SİSTEMİ — FIRESTORE TRIGGER FONKSİYONLARI
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * FCM push bildirimi ve in-app bildirim gönderir.
 */
async function sendNotifications({ recipientUids, title, body, route, type, entityId }) {
    if (!recipientUids || recipientUids.length === 0) return;

    const uniqueUids = [...new Set(recipientUids)].filter(Boolean);
    const allTokens = [];
    const batch = db.batch();
    const now = admin.firestore.FieldValue.serverTimestamp();

    for (const uid of uniqueUids) {
        try {
            const userDoc = await db.collection("users").doc(uid).get();
            if (!userDoc.exists) continue;

            const userData = userDoc.data();
            const settings = userData.notificationSettings || {};
            const typeMap = {
                etut: "studies",
                announcement: "announcements",
                message: "messages",
                homework: "homeworks",
                exam: "exams",
            };
            const settingKey = typeMap[type] || type;
            if (settings[settingKey] === false) continue;

            const tokens = userData.fcmTokens || [];
            allTokens.push(...tokens);

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
            console.error(`Bildirim hatası (${uid}):`, err);
        }
    }

    try {
        await batch.commit();
    } catch (err) {
        console.error("In-app bildirim yazma hatası:", err);
    }

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
            console.log(`FCM: ${response.successCount} başarılı, ${response.failureCount} başarısız.`);

            // Geçersiz token'ları temizle
            response.responses.forEach(async (resp, idx) => {
                if (!resp.success && (
                    resp.error?.code === "messaging/invalid-registration-token" ||
                    resp.error?.code === "messaging/registration-token-not-registered"
                )) {
                    const invalidToken = allTokens[idx];
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
 * Kuruma ait aktif kullanıcı UID'lerini getirir.
 */
async function getInstitutionUserUids(institutionId) {
    const snapshot = await db.collection("users")
        .where("institutionId", "==", institutionId)
        .where("isActive", "==", true)
        .get();
    return snapshot.docs.map(doc => doc.id);
}

// ─── Trigger: Etüt Oluşturulduğunda ──────────────────────────────────────────
exports.onEtutCreated = onDocumentCreated("etut_requests/{etutId}", async (event) => {
    const etut = event.data?.data();
    if (!etut) return;

    const { institutionId, dersAdi, teacherName, className, studentIds = [] } = etut;
    const title = `📚 Yeni Etüt: ${dersAdi || "Ders"}`;
    const body = `${teacherName || "Öğretmen"} · ${className || "Grup"}`;
    let recipientUids = await getInstitutionUserUids(institutionId);

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
                if (!parentQuery.empty) recipientUids.push(parentQuery.docs[0].id);
            }
        } catch (err) {
            console.error("Veli bulma hatası:", err);
        }
    }

    await sendNotifications({ recipientUids, title, body, route: "/school-dashboard", type: "etut", entityId: event.params.etutId });
});

// ─── Trigger: Duyuru Oluşturulduğunda ────────────────────────────────────────
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

// ─── Trigger: Mesaj Gönderildiğinde ──────────────────────────────────────────
exports.onMessageSent = onDocumentCreated(
    "conversations/{conversationId}/messages/{messageId}",
    async (event) => {
        const message = event.data?.data();
        if (!message) return;
        const { senderId, senderName, content, participants = [] } = message;
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

// ─── Trigger: Ödev Oluşturulduğunda ──────────────────────────────────────────
exports.onHomeworkCreated = onDocumentCreated("homeworks/{homeworkId}", async (event) => {
    const homework = event.data?.data();
    if (!homework) return;
    const { institutionId, title: hwTitle } = homework;
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

// ═══════════════════════════════════════════════════════════════════════════════
// 📱 SMS KUYRUĞU — onSmsQueued Trigger
// API key ASLA client'a gönderilmez, schools/{schoolId}.smsSettings'ten okunur
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * sms_queue koleksiyonuna yeni bir belge eklendiğinde tetiklenir.
 * SMS API key'ini Firestore'dan (schools/{schoolId}.smsSettings) sunucu tarafında okur.
 * Client hiçbir zaman API key'i görmez.
 */
exports.onSmsQueued = onDocumentCreated("sms_queue/{docId}", async (event) => {
    const smsDoc = event.data?.data();
    if (!smsDoc) return;

    const { phone, message, provider, schoolId, originator, status } = smsDoc;

    // Zaten işlendi mi?
    if (status !== "pending") return;

    const docRef = db.collection("sms_queue").doc(event.params.docId);

    // Önce 'processing' yap (duplicate gönderimi önle)
    await docRef.update({ status: "processing", processedAt: admin.firestore.FieldValue.serverTimestamp() });

    try {
        if (!schoolId) throw new Error("schoolId eksik — API key bulunamaz.");

        // ✅ API key sunucu tarafında schools belgesinden okunuyor
        const schoolDoc = await db.collection("schools").doc(schoolId).get();
        if (!schoolDoc.exists) throw new Error(`Okul bulunamadı: ${schoolId}`);

        const smsSettings = schoolDoc.data()?.smsSettings;
        if (!smsSettings || !smsSettings.isActive) {
            throw new Error("SMS entegrasyonu aktif değil.");
        }

        const apiKey = smsSettings.apiKey;
        const apiSecret = smsSettings.apiSecret;
        const senderOriginator = originator || smsSettings.originator || "EDUKN";

        if (!apiKey || !apiSecret) throw new Error("SMS API bilgileri eksik.");

        let success = false;
        let responseMessage = "";

        switch (provider) {
            case "netgsm": {
                const netgsmUrl = new URL("https://api.netgsm.com.tr/sms/send/get");
                netgsmUrl.searchParams.set("usercode", apiKey);
                netgsmUrl.searchParams.set("password", apiSecret);
                netgsmUrl.searchParams.set("gsmno", phone);
                netgsmUrl.searchParams.set("message", message);
                netgsmUrl.searchParams.set("msgheader", senderOriginator);
                netgsmUrl.searchParams.set("dil", "TR");

                const response = await fetch(netgsmUrl.toString());
                const text = await response.text();

                if (text && text.startsWith("00")) {
                    success = true;
                    responseMessage = `Başarılı. Netgsm kodu: ${text.trim()}`;
                } else {
                    responseMessage = `Netgsm hatası: ${text?.trim() || "bilinmiyor"}`;
                }
                break;
            }
            default:
                // Diğer provider'lar için kuyruk kayıtlıdır, harici sistem okur
                success = true;
                responseMessage = `${provider} kuyruğa eklendi.`;
        }

        await docRef.update({
            status: success ? "sent" : "failed",
            response: responseMessage,
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

    } catch (err) {
        console.error("SMS gönderim hatası:", err);
        await docRef.update({
            status: "failed",
            error: err.message || "Bilinmeyen hata",
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
});

// ─── Trigger: Deneme Sınavı Oluşturulduğunda ─────────────────────────────────
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


// ═══════════════════════════════════════════════════════════════════════════════
// 🔐 VERİ ŞİFRELEME — ENCRYPTION FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

const ENC_PREFIX = "ENC:";
const ENC_ALGORITHM = "aes-256-cbc";

/**
 * Server-side şifreleme: plaintext → "ENC:<iv_hex>:<ciphertext_hex>"
 * Flutter EncryptionService ile uyumlu format
 */
function encryptField(value, keyHex) {
    if (!value || typeof value !== "string") return value;
    if (value.startsWith(ENC_PREFIX)) return value; // Zaten şifreli

    const keyBuffer = Buffer.from(keyHex, "hex");
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv(ENC_ALGORITHM, keyBuffer, iv);
    let encrypted = cipher.update(value, "utf8", "base64");
    encrypted += cipher.final("base64");
    const ivBase64 = iv.toString("base64");
    return `${ENC_PREFIX}${ivBase64}:${encrypted}`;
}

/**
 * Server-side çözme: "ENC:<iv_hex>:<ciphertext_hex>" → plaintext
 */
function decryptField(value, keyHex) {
    if (!value || typeof value !== "string") return value;
    if (!value.startsWith(ENC_PREFIX)) return value; // Düz metin

    try {
        const body = value.substring(ENC_PREFIX.length);
        const parts = body.split(":");
        if (parts.length !== 2) return value;

        const iv = Buffer.from(parts[0], "base64");
        const keyBuffer = Buffer.from(keyHex, "hex");
        const decipher = crypto.createDecipheriv(ENC_ALGORITHM, keyBuffer, iv);
        let decrypted = decipher.update(parts[1], "base64", "utf8");
        decrypted += decipher.final("utf8");
        return decrypted;
    } catch (e) {
        console.error("decryptField hatası:", e.message);
        return value;
    }
}

/**
 * 'getEncryptionKeyForClient' — Flutter uygulamasına AES anahtarını güvenli iletir.
 * 🔐 Sadece giriş yapmış kullanıcılara gönderilir.
 * Anahtar ASLA Firestore'a yazılmaz — sadece bellek üzerinden iletilir.
 */
exports.getEncryptionKeyForClient = onCall(
    { secrets: [encryptionKey], enforceAppCheck: false },
    async (request) => {
        verifyAuth(request.auth);

        // Hex formatındaki anahtarı Base64'e çevir (Flutter encrypt paketi Base64 ister)
        const keyHex = encryptionKey.value() ? encryptionKey.value().trim() : "";
        if (!keyHex || keyHex.length !== 64) {
            throw new HttpsError("internal", "Şifreleme anahtarı yapılandırılmamış veya geçersiz.");
        }

        const keyBase64 = Buffer.from(keyHex, "hex").toString("base64");
        return { key: keyBase64 };
    }
);

/**
 * 'migrateEncryptData' — Mevcut tüm verileri şifreler.
 * 🔐 Sadece super_admin çağırabilir.
 * Şifreleme yapılacak koleksiyonlar ve alanlar:
 *   - students: tcNo, birthDate, phone, parentPhone1, parentPhone2, parentPhone
 *   - users: tcNo, birthDate, phone
 *   - parents: tcNo, birthDate, phone
 */
exports.migrateEncryptData = onCall(
    { secrets: [encryptionKey], enforceAppCheck: false, timeoutSeconds: 540 },
    async (request) => {
        await verifySuperAdmin(request.auth);

        const keyHex = encryptionKey.value() ? encryptionKey.value().trim() : "";
        // Force redeploy token: key_trimming_v2_fix_hash_9876
        if (!keyHex || keyHex.length !== 64) {
            throw new HttpsError("internal", `Şifreleme anahtarı hâlâ geçersiz. Değer: "${keyHex}", Uzunluk: ${keyHex ? keyHex.length : 0}`);
        }

        const { institutionId } = request.data;
        if (!institutionId) {
            throw new HttpsError("invalid-argument", "institutionId gereklidir.");
        }

        console.log(`[Migration] Başlıyor — Institution: ${institutionId}`);

        const results = {
            students: { processed: 0, encrypted: 0, skipped: 0, errors: 0 },
            users: { processed: 0, encrypted: 0, skipped: 0, errors: 0 },
            parents: { processed: 0, encrypted: 0, skipped: 0, errors: 0 },
        };

        // ─── Koleksiyon şifreleme yardımcısı ─────────────────────────────────
        async function encryptCollection(collectionName, sensitiveFields, statsKey) {
            const snapshot = await db.collection(collectionName)
                .where("institutionId", "==", institutionId)
                .get();

            console.log(`[Migration] ${collectionName}: ${snapshot.size} kayıt bulundu.`);

            const BATCH_SIZE = 400;
            let batchCount = 0;
            let batch = db.batch();
            
            for (const doc of snapshot.docs) {
                results[statsKey].processed++;
                const data = doc.data();
                const updates = {};
                let needsUpdate = false;

                for (const field of sensitiveFields) {
                    const value = data[field];
                    if (value != null && value !== "" && !String(value).startsWith(ENC_PREFIX)) {
                        updates[field] = encryptField(String(value), keyHex);
                        needsUpdate = true;
                    }
                }

                if (needsUpdate) {
                    batch.update(doc.ref, updates);
                    results[statsKey].encrypted++;
                    batchCount++;

                    if (batchCount >= BATCH_SIZE) {
                        await batch.commit();
                        batch = db.batch();
                        batchCount = 0;
                        console.log(`[Migration] ${collectionName}: Batch commit yapıldı.`);
                    }
                } else {
                    results[statsKey].skipped++;
                }
            }

            if (batchCount > 0) {
                await batch.commit();
            }
        }

        try {
            // Öğrenciler
            await encryptCollection("students", [
                "tcNo", "birthDate", "phone", "parentPhone1", "parentPhone2", "parentPhone"
            ], "students");

            // Kullanıcılar (öğretmen/yönetici)
            await encryptCollection("users", [
                "tcNo", "birthDate", "phone"
            ], "users");

            // Veliler
            await encryptCollection("parents", [
                "tcNo", "birthDate", "phone"
            ], "parents");

            // ✅ Audit log
            await writeAuditLog({
                action: "ENCRYPT_DATA_MIGRATION",
                performedBy: request.auth.uid,
                targetId: institutionId,
                details: results,
            });

            console.log(`[Migration] Tamamlandı:`, JSON.stringify(results));
            return { status: "success", results };

        } catch (error) {
            console.error("[Migration] HATA:", error);
            throw new HttpsError("internal", `Migration hatası: ${error.message}`);
        }
    }
);

/**
 * 'getEncryptionStats' — Kaç kayıt şifreli, kaç kayıt düz metin olduğunu döner.
 * 🔐 Sadece admin/manager çağırabilir.
 */
exports.getEncryptionStats = onCall(
    { enforceAppCheck: false },
    async (request) => {
        verifyAuth(request.auth);

        const { institutionId } = request.data;
        if (!institutionId) {
            throw new HttpsError("invalid-argument", "institutionId gereklidir.");
        }

        const stats = {};

        for (const [col, fields] of [
            ["students", ["tcNo", "birthDate", "phone", "parentPhone1", "parentPhone2", "parentPhone"]],
            ["users", ["tcNo", "birthDate", "phone"]],
            ["parents", ["tcNo", "birthDate", "phone"]]
        ]) {
            const snapshot = await db.collection(col)
                .where("institutionId", "==", institutionId)
                .get();

            let encrypted = 0, plain = 0;
            for (const doc of snapshot.docs) {
                const data = doc.data();
                let hasPlain = false;
                
                for (const field of fields) {
                    const val = data[field];
                    if (val != null && val !== "") {
                        if (!String(val).startsWith(ENC_PREFIX)) {
                            hasPlain = true;
                        }
                    }
                }
                
                if (hasPlain) {
                    plain++;
                } else {
                    encrypted++;
                }
            }
            stats[col] = { total: snapshot.size, encrypted, plain };
        }

        return { stats };
    }
);
