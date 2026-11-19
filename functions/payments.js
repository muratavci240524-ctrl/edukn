/**
 * iyzico Hosted Checkout Form entegrasyonu (sanal pos).
 *
 * Kart bilgisi ASLA uygulamaya / sunucumuza girmez: kullanıcı iyzico'nun
 * barındırdığı ödeme sayfasında ödeme yapar (PCI kapsamı dışı).
 *
 * Fonksiyonlar:
 *   - createPaymentSession (callable): ödeme oturumu başlatır, paymentPageUrl döner.
 *   - iyzicoCallback (HTTPS POST): iyzico sonucu geri çağırır; sonuç sunucuda
 *     doğrulanır ve Firestore'a idempotent olarak işlenir.
 *
 * Secrets: IYZICO_API_KEY, IYZICO_SECRET_KEY, IYZICO_BASE_URL
 *   (firebase functions:secrets:set ...)
 */
const { onCall, HttpsError, onRequest } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");
const admin = require("firebase-admin");
const crypto = require("crypto");

const iyzicoApiKey = defineSecret("IYZICO_API_KEY");
const iyzicoSecretKey = defineSecret("IYZICO_SECRET_KEY");
const iyzicoBaseUrl = defineSecret("IYZICO_BASE_URL"); // örn. https://sandbox-api.iyzipay.com
// Opsiyonel: callback URL'ini elle vermek için (varsayılan: cloudfunctions.net adresi)
const iyzicoCallbackUrlParam = defineString("IYZICO_CALLBACK_URL", { default: "" });

const REGION = "us-central1"; // setGlobalOptions'ta bölge verilmediği için varsayılan bölge
const DEFAULT_BASE_URL = "https://sandbox-api.iyzipay.com";
const MIN_TOPUP = 10;
const MAX_TOPUP = 5000;

const db = () => admin.firestore();

// ─── Yardımcılar ──────────────────────────────────────────────────────────────

const toCents = (n) => Math.round(Number(n) * 100);
const fromCents = (c) => c / 100;
const priceStr = (cents) => (cents / 100).toFixed(2);
const up = (s) => String(s || "").trim().toUpperCase();

function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
        "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
    }[c]));
}

function getIyzipayFromCredentials(apiKey, secretKey, baseUrl) {
    const cleanApi = String(apiKey || "").trim();
    const cleanSecret = String(secretKey || "").trim();
    const uri = (String(baseUrl || "").trim() || DEFAULT_BASE_URL).replace(/\/+$/, "");
    if (!cleanApi || !cleanSecret) {
        throw new HttpsError("failed-precondition", "PAYMENT_NOT_CONFIGURED");
    }
    const Iyzipay = require("iyzipay");
    return new Iyzipay({ apiKey: cleanApi, secretKey: cleanSecret, uri });
}

function getDefaultIyzipay() {
    const apiKey = (iyzicoApiKey.value() || "").trim();
    const secretKey = (iyzicoSecretKey.value() || "").trim();
    const uri = ((iyzicoBaseUrl.value() || "").trim() || DEFAULT_BASE_URL).replace(/\/+$/, "");
    return getIyzipayFromCredentials(apiKey, secretKey, uri);
}

function isProfileUsable(prof) {
    return Boolean(
        prof &&
        prof.enabled === true &&
        String(prof.apiKey || "").trim().length > 0 &&
        String(prof.secretKey || "").trim().length > 0
    );
}

/**
 * Kurum ve modül kanalına göre aktif Sanal POS profilini çözümler:
 *   channel: 'canteen' | 'store' | 'hq_store' | 'accounting'
 * Öncelik sırası:
 *   1) pos_configs/{institutionId} -> ilgili modül (custom veya inherit_school -> defaultPos)
 *   2) pos_configs/SUPER_ADMIN -> defaultPos
 *   3) Cloud Functions Secret (IYZICO_API_KEY / IYZICO_SECRET_KEY)
 */
async function resolvePosConfig(institutionId, channel) {
    const inst = up(institutionId || "SUPER_ADMIN");
    const ch = String(channel || "store").trim().toLowerCase();

    let chosenProfile = null;
    let ownerInst = "SUPER_ADMIN";

    if (inst && inst !== "SUPER_ADMIN") {
        const instSnap = await db().collection("pos_configs").doc(inst).get();
        if (instSnap.exists) {
            const cfg = instSnap.data() || {};
            const defaultPos = cfg.defaultPos || {};
            const channelMap =
                ch === "canteen"
                    ? (cfg.canteenPos || {})
                    : ch === "accounting"
                        ? (cfg.accountingPos || {})
                        : (cfg.storePos || {});
            const mode = String(channelMap.mode || "inherit_school").trim();
            if (mode === "custom" && isProfileUsable(channelMap.customProfile)) {
                chosenProfile = channelMap.customProfile;
                ownerInst = inst;
            } else if (mode !== "platform_default" && isProfileUsable(defaultPos)) {
                chosenProfile = defaultPos;
                ownerInst = inst;
            }
        }
    }

    if (!chosenProfile) {
        const hqSnap = await db().collection("pos_configs").doc("SUPER_ADMIN").get();
        if (hqSnap.exists) {
            const hqCfg = hqSnap.data() || {};
            if (isProfileUsable(hqCfg.defaultPos)) {
                chosenProfile = hqCfg.defaultPos;
                ownerInst = "SUPER_ADMIN";
            }
        }
    }

    if (chosenProfile) {
        const envUrl = String(chosenProfile.environment || "") === "production"
            ? "https://api.iyzipay.com"
            : DEFAULT_BASE_URL;
        const baseUrl = String(chosenProfile.baseUrl || "").trim() || envUrl;
        const iyzipay = getIyzipayFromCredentials(
            chosenProfile.apiKey,
            chosenProfile.secretKey,
            baseUrl,
        );
        const allowInst = chosenProfile.allowInstallments !== false;
        const instList = allowInst && Array.isArray(chosenProfile.enabledInstallments) && chosenProfile.enabledInstallments.length > 0
            ? chosenProfile.enabledInstallments.map((n) => Number(n)).filter((n) => Number.isFinite(n) && n >= 1)
            : [1];
        return {
            iyzipay,
            ownerInstitutionId: ownerInst,
            channel: ch,
            merchantTitle: String(chosenProfile.merchantTitle || "").trim() || (ownerInst === "SUPER_ADMIN" ? "Genel Merkez POS" : `${ownerInst} POS`),
            enabledInstallments: instList.length > 0 ? instList : [1],
            subMerchantKey: String(chosenProfile.subMerchantKey || "").trim(),
        };
    }

    // Fallback: Cloud Functions Secret
    const iyzipay = getDefaultIyzipay();
    return {
        iyzipay,
        ownerInstitutionId: "SUPER_ADMIN",
        channel: ch,
        merchantTitle: "Genel Merkez Ortak POS",
        enabledInstallments: ch === "store" || ch === "hq_store" ? [1, 2, 3, 6, 9] : [1],
        subMerchantKey: "",
    };
}

function callbackUrl() {
    const custom = (iyzicoCallbackUrlParam.value() || "").trim();
    if (custom) return custom;
    const project = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
    return `https://${REGION}-${project}.cloudfunctions.net/iyzicoCallback`;
}

function iyzicoCall(fn, request) {
    return new Promise((resolve, reject) => {
        fn(request, (err, result) => (err ? reject(err) : resolve(result)));
    });
}

function splitName(full) {
    const parts = String(full || "").trim().split(/\s+/).filter(Boolean);
    if (parts.length === 0) return { name: "Kullanici", surname: "eduKN" };
    if (parts.length === 1) return { name: parts[0], surname: "-" };
    return { name: parts.slice(0, -1).join(" "), surname: parts[parts.length - 1] };
}

function formatIyzicoDate(d) {
    // "YYYY-MM-DD HH:mm:ss"
    return d.toISOString().replace("T", " ").substring(0, 19);
}

// ─── createPaymentSession ─────────────────────────────────────────────────────

async function resolveCanteenTopup(auth, data) {
    const institutionId = up(data.institutionId);
    const cardNo = String(data.cardNo || "").trim();
    const amount = Number(data.amount);
    if (!institutionId || !cardNo) {
        throw new HttpsError("invalid-argument", "Kurum ve kart numarası gereklidir.");
    }
    if (!Number.isFinite(amount) || amount < MIN_TOPUP || amount > MAX_TOPUP) {
        throw new HttpsError("invalid-argument", `Tutar ${MIN_TOPUP} ile ${MAX_TOPUP} TL arasında olmalıdır.`);
    }
    const cents = toCents(amount);
    const cardSnap = await db().collection("canteen_cards").doc(cardNo).get();
    if (!cardSnap.exists) throw new HttpsError("not-found", "Kart bulunamadı.");
    const card = cardSnap.data() || {};
    if (up(card.institutionId) !== institutionId) {
        throw new HttpsError("permission-denied", "Kart bu kuruma ait değil.");
    }
    const email = String((auth.token && auth.token.email) || "").toLowerCase();
    const parentUids = Array.isArray(card.parentUids) ? card.parentUids : [];
    const isLinkedParentOrStudent =
        parentUids.includes(auth.uid) ||
        (email && String(card.parentEmail || "").toLowerCase() === email) ||
        (card.studentId && card.studentId === auth.uid);
    if (!isLinkedParentOrStudent) {
        // Kurum bazlı kontrol: veli hesaplarında parentUids manuel girilmemiş olabilir;
        // aynı kuruma kayıtlı veli/öğrenci/personel geçerli bir öğrenci kartına bakiye yükleyebilir.
        const uSnap = await db().collection("users").doc(auth.uid).get();
        const uInst = uSnap.exists ? up(uSnap.data().institutionId || uSnap.data().institution_id || "") : "";
        const tokenDomainMatch = email.endsWith(`@${institutionId.toLowerCase()}.edukn`) || email === "superadmin@edukn.com";
        if (uInst && uInst !== "SUPER_ADMIN" && uInst !== institutionId && !tokenDomainMatch) {
            throw new HttpsError("permission-denied", "Bu karta bakiye yükleme yetkiniz yok.");
        }
    }
    return {
        institutionId,
        cents,
        payment: { cardNo },
        basket: [{
            id: `CARD-${cardNo}`.substring(0, 60),
            name: "Kantin Bakiye Yukleme",
            category1: "Kantin",
            itemType: "VIRTUAL",
            price: priceStr(cents),
        }],
        basketId: `TOPUP-${cardNo}`.substring(0, 60),
        enabledInstallments: [1],
    };
}

async function resolveStoreOrder(auth, data) {
    const institutionId = up(data.institutionId);
    const orderIds = Array.isArray(data.orderIds)
        ? [...new Set(data.orderIds.map((x) => String(x)).filter(Boolean))]
        : [];
    if (!institutionId || orderIds.length === 0 || orderIds.length > 10) {
        throw new HttpsError("invalid-argument", "Geçersiz sipariş bilgisi.");
    }
    const snaps = await Promise.all(orderIds.map((id) => db().collection("store_orders").doc(id).get()));
    let cents = 0;
    const basket = [];
    let hasHqOrder = false;
    let hasSchoolOrder = false;
    snaps.forEach((s, i) => {
        if (!s.exists) throw new HttpsError("not-found", "Sipariş bulunamadı.");
        const o = s.data() || {};
        if (o.buyerUid !== auth.uid) {
            throw new HttpsError("permission-denied", "Bu sipariş size ait değil.");
        }
        if (up(o.institutionId) !== institutionId) {
            throw new HttpsError("permission-denied", "Sipariş bu kuruma ait değil.");
        }
        if (o.paymentStatus !== "pending" || o.orderStatus === "iptal") {
            throw new HttpsError("failed-precondition", "Sipariş ödeme beklemiyor.");
        }
        if (o.sellerType === "hq" || up(o.sellerInstitutionId) === "SUPER_ADMIN") {
            hasHqOrder = true;
        } else {
            hasSchoolOrder = true;
        }
        const c = toCents(o.totalAmount);
        if (!(c > 0)) throw new HttpsError("failed-precondition", "Sipariş tutarı geçersiz.");
        cents += c;
        basket.push({
            id: orderIds[i].substring(0, 60),
            name: String(o.orderNo || `Siparis ${i + 1}`).substring(0, 100),
            category1: "Magaza",
            itemType: "PHYSICAL",
            price: priceStr(c),
        });
    });

    // Hangi POS kanalının kullanılacağını belirle:
    // Eğer siparişte sadece Genel Merkez ürünleri varsa veya posChannel === 'hq_store' ise -> SUPER_ADMIN (hq_store)
    // Eğer okul mağazası siparişi ise -> institutionId ('store')
    const explicitChannel = String(data.posChannel || "").trim().toLowerCase();
    const posTargetInst = (explicitChannel === "hq_store" || (hasHqOrder && !hasSchoolOrder))
        ? "SUPER_ADMIN"
        : institutionId;
    const posChannel = posTargetInst === "SUPER_ADMIN" ? "hq_store" : "store";

    return {
        institutionId,
        posTargetInst,
        posChannel,
        cents,
        payment: { orderIds },
        basket,
        basketId: `ORD-${orderIds[0]}`.substring(0, 60),
        enabledInstallments: [1, 2, 3, 6, 9],
    };
}

async function resolveCanteenQr(auth, data) {
    const institutionId = up(data.institutionId);
    const qrSessionId = String(data.qrSessionId || "").trim();
    if (!institutionId || !qrSessionId) {
        throw new HttpsError("invalid-argument", "Karekod oturum bilgisi gereklidir.");
    }
    const snap = await db().collection("canteen_qr_sessions").doc(qrSessionId).get();
    if (!snap.exists) throw new HttpsError("not-found", "Karekod oturumu bulunamadı.");
    const s = snap.data() || {};
    if (up(s.institutionId) !== institutionId) {
        throw new HttpsError("permission-denied", "Karekod bu kuruma ait değil.");
    }
    if (s.status !== "pending") {
        throw new HttpsError("failed-precondition", "Bu karekod artık ödeme beklemiyor.");
    }
    const items = Array.isArray(s.items) ? s.items : [];
    const cents = toCents(s.total);
    if (!(cents > 0) || items.length === 0) {
        throw new HttpsError("failed-precondition", "Karekod tutarı geçersiz.");
    }
    const basket = items.map((it, idx) => ({
        id: String(it.productId || `ITEM-${idx + 1}`).substring(0, 60),
        name: String(it.name || `Kantin Urun ${idx + 1}`).substring(0, 100),
        category1: "Kantin",
        itemType: "PHYSICAL",
        price: priceStr(toCents((Number(it.price) || 0) * (Number(it.qty) || 1))),
    }));
    return {
        institutionId,
        cents,
        payment: { qrSessionId },
        basket,
        basketId: `QR-${qrSessionId}`.substring(0, 60),
        enabledInstallments: [1],
    };
}

exports.createPaymentSession = onCall(
    { secrets: [iyzicoApiKey, iyzicoSecretKey, iyzicoBaseUrl], enforceAppCheck: false },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "Ödeme için giriş yapmalısınız.");
        }
        const auth = request.auth;
        const data = request.data || {};
        const kind = data.kind;
        if (kind !== "canteen_topup" && kind !== "canteen_qr" && kind !== "store_order") {
            throw new HttpsError("invalid-argument", "Geçersiz ödeme türü.");
        }

        const resolved = kind === "canteen_topup"
            ? await resolveCanteenTopup(auth, data)
            : (kind === "canteen_qr"
                ? await resolveCanteenQr(auth, data)
                : await resolveStoreOrder(auth, data));

        const posTargetInst = resolved.posTargetInst || resolved.institutionId;
        const posChannel = resolved.posChannel || (kind === "store_order" ? "store" : "canteen");
        const posResolved = await resolvePosConfig(posTargetInst, posChannel);
        const iyzipay = posResolved.iyzipay;

        const userSnap = await db().collection("users").doc(auth.uid).get();
        const profile = userSnap.exists ? userSnap.data() || {} : {};
        const email = String((auth.token && auth.token.email) || profile.email || "").trim() || "noreply@edukn.com";
        const fullName = profile.fullName || profile.name || profile.displayName || (auth.token && auth.token.name) || "";
        const { name, surname } = splitName(fullName);
        const phoneDigits = String(profile.phone || profile.phoneNumber || "").replace(/\D/g, "");
        const gsm = phoneDigits.length >= 10 ? `+90${phoneDigits.slice(-10)}` : "+905000000000";
        const ip = String((request.rawRequest && (request.rawRequest.headers["x-forwarded-for"] || request.rawRequest.ip)) || "85.34.78.112")
            .split(",")[0].trim();
        const now = new Date();

        const paymentRef = db().collection("payments").doc();
        const paymentId = paymentRef.id;
        const conversationId = crypto.randomUUID();

        await paymentRef.set({
            uid: auth.uid,
            kind,
            institutionId: resolved.institutionId,
            posOwnerInstitutionId: posResolved.ownerInstitutionId,
            posChannel: posResolved.channel,
            posMerchantTitle: posResolved.merchantTitle,
            ...resolved.payment,
            amount: fromCents(resolved.cents),
            currency: "TRY",
            status: "pending",
            conversationId,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const address = {
            contactName: `${name} ${surname}`.trim(),
            city: "Istanbul",
            country: "Turkey",
            address: "Egitim kurumu - Turkiye",
            zipCode: "34000",
        };

        const basketItems = posResolved.subMerchantKey
            ? resolved.basket.map((b) => ({
                ...b,
                subMerchantKey: posResolved.subMerchantKey,
                subMerchantPrice: b.price,
            }))
            : resolved.basket;

        const initRequest = {
            locale: "tr",
            conversationId,
            price: priceStr(resolved.cents),
            paidPrice: priceStr(resolved.cents),
            currency: "TRY",
            basketId: resolved.basketId,
            paymentGroup: "PRODUCT",
            callbackUrl: callbackUrl(),
            enabledInstallments: posResolved.enabledInstallments || resolved.enabledInstallments,
            buyer: {
                id: auth.uid.substring(0, 60),
                name,
                surname,
                gsmNumber: gsm,
                email,
                identityNumber: "11111111111",
                lastLoginDate: formatIyzicoDate(now),
                registrationDate: formatIyzicoDate(now),
                registrationAddress: address.address,
                ip,
                city: address.city,
                country: address.country,
                zipCode: address.zipCode,
            },
            shippingAddress: address,
            billingAddress: address,
            basketItems,
        };

        let result;
        try {
            result = await iyzicoCall(iyzipay.checkoutFormInitialize.create.bind(iyzipay.checkoutFormInitialize), initRequest);
        } catch (e) {
            await paymentRef.update({ status: "failed", failureReason: "iyzico bağlantı hatası" });
            console.error("iyzico init connection error", e && e.message);
            throw new HttpsError("unavailable", "Ödeme sağlayıcısına ulaşılamadı.");
        }
        if (!result || result.status !== "success" || !result.token || !result.paymentPageUrl) {
            const reason = (result && result.errorMessage) || "Ödeme oturumu oluşturulamadı";
            await paymentRef.update({ status: "failed", failureReason: String(reason).substring(0, 300) });
            console.error("iyzico init failed", result && result.errorCode, reason);
            // Hatalı API anahtarı vb. durumunda kullanıcıya yapılandırma mesajı döndür
            if (result && ["1000", "1001", "1002", "1003", "1004"].includes(String(result.errorCode))) {
                throw new HttpsError("failed-precondition", "PAYMENT_NOT_CONFIGURED");
            }
            throw new HttpsError("internal", "Ödeme oturumu oluşturulamadı.");
        }

        await paymentRef.update({ iyzicoToken: result.token });
        return { paymentId, paymentPageUrl: result.paymentPageUrl };
    },
);

// ─── Sonuçların Firestore'a işlenmesi (idempotent) ────────────────────────────

async function applyCanteenTopup(tx, payRef, pay, iyz) {
    const cardRef = db().collection("canteen_cards").doc(pay.cardNo);
    const cardSnap = await tx.get(cardRef);
    if (!cardSnap.exists) {
        tx.update(payRef, {
            status: "failed",
            failureReason: "Kart bulunamadı (ödeme iade edilmeli)",
            refundRequired: true,
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
    }
    const card = cardSnap.data() || {};
    const after = fromCents(toCents(card.balance || 0) + toCents(pay.amount));
    const inst = up(pay.institutionId);
    const FV = admin.firestore.FieldValue;
    tx.update(cardRef, { balance: after });
    tx.set(db().collection("canteen_transactions").doc(), {
        institutionId: inst,
        cardNo: pay.cardNo,
        studentId: card.studentId || "",
        type: "topup",
        method: "online",
        amount: pay.amount,
        items: [],
        balanceAfter: after,
        cashierId: pay.uid,
        paymentId: payRef.id,
        createdAt: FV.serverTimestamp(),
    });
    tx.set(db().collection("canteen_ledger").doc(), {
        institutionId: inst,
        type: "income",
        category: "Bakiye Yükleme",
        amount: pay.amount,
        note: `${card.studentName || ""} (${pay.cardNo}) - online`,
        date: admin.firestore.Timestamp.now(),
        createdAt: FV.serverTimestamp(),
    });
    tx.update(payRef, {
        status: "success",
        iyzicoPaymentId: String(iyz.paymentId || ""),
        completedAt: FV.serverTimestamp(),
    });
}

async function applyStoreSuccess(tx, payRef, pay, iyz) {
    const FV = admin.firestore.FieldValue;
    const refs = pay.orderIds.map((id) => db().collection("store_orders").doc(id));
    const snaps = await Promise.all(refs.map((r) => tx.get(r)));
    let refundRequired = false;
    const cardMasked = iyz.binNumber && iyz.lastFourDigits
        ? `${String(iyz.binNumber).substring(0, 6)}** **** ${iyz.lastFourDigits}`
        : "";
    snaps.forEach((s, i) => {
        if (!s.exists) { refundRequired = true; return; }
        const o = s.data() || {};
        if (o.orderStatus === "iptal" || o.paymentStatus !== "pending") {
            // Kullanıcı ödeme sırasında iptal etmiş: para alındı, iade gerekir
            refundRequired = true;
            return;
        }
        tx.update(refs[i], {
            paymentStatus: "paid",
            paymentRef: String(iyz.paymentId || payRef.id),
            cardMasked,
            installmentCount: Number(iyz.installment) || 1,
            updatedAt: FV.serverTimestamp(),
        });
    });
    tx.update(payRef, {
        status: "success",
        iyzicoPaymentId: String(iyz.paymentId || ""),
        ...(refundRequired ? { refundRequired: true } : {}),
        completedAt: FV.serverTimestamp(),
    });
}

async function applyStoreFailure(tx, payRef, pay, reason) {
    const FV = admin.firestore.FieldValue;
    const refs = pay.orderIds.map((id) => db().collection("store_orders").doc(id));
    const orderSnaps = await Promise.all(refs.map((r) => tx.get(r)));
    // Stok iadesi için ürünleri oku (tüm okumalar yazmalardan önce)
    const toRestore = []; // {ref, qty}
    const qtyByProduct = new Map();
    orderSnaps.forEach((s) => {
        if (!s.exists) return;
        const o = s.data() || {};
        if (o.orderStatus === "iptal" || o.paymentStatus !== "pending") return;
        (Array.isArray(o.items) ? o.items : []).forEach((it) => {
            const pid = String((it && it.productId) || "").trim();
            const q = Number(it && it.quantity) || 0;
            if (pid && q > 0) qtyByProduct.set(pid, (qtyByProduct.get(pid) || 0) + q);
        });
    });
    for (const [pid, qty] of qtyByProduct) {
        const ref = db().collection("store_products").doc(pid);
        toRestore.push({ ref, qty, snap: await tx.get(ref) });
    }
    orderSnaps.forEach((s, i) => {
        if (!s.exists) return;
        const o = s.data() || {};
        if (o.orderStatus === "iptal" || o.paymentStatus !== "pending") return;
        tx.update(refs[i], {
            paymentStatus: "failed",
            orderStatus: "iptal",
            cancelReason: `Ödeme tamamlanamadı: ${reason}`.substring(0, 300),
            updatedAt: FV.serverTimestamp(),
        });
    });
    toRestore.forEach(({ ref, qty, snap }) => {
        if (!snap.exists) return;
        const d = snap.data() || {};
        tx.update(ref, {
            stock: (Number(d.stock) || 0) + qty,
            soldCount: Math.max(0, (Number(d.soldCount) || 0) - qty),
            updatedAt: FV.serverTimestamp(),
        });
    });
    tx.update(payRef, {
        status: "failed",
        failureReason: String(reason).substring(0, 300),
        completedAt: FV.serverTimestamp(),
    });
}

async function applyCanteenQrSuccess(tx, payRef, pay, iyz) {
    const FV = admin.firestore.FieldValue;
    const sRef = db().collection("canteen_qr_sessions").doc(pay.qrSessionId);
    const sSnap = await tx.get(sRef);
    const uSnap = await tx.get(db().collection("users").doc(pay.uid));
    if (!sSnap.exists || (sSnap.data() || {}).status !== "pending") {
        tx.update(payRef, {
            status: "failed",
            failureReason: "Karekod oturumu kapanmış (iade gerekir)",
            refundRequired: true,
            completedAt: FV.serverTimestamp(),
        });
        return;
    }
    const s = sSnap.data() || {};
    const items = Array.isArray(s.items) ? s.items : [];
    const prodSnaps = [];
    for (const it of items) {
        const pRef = db().collection("canteen_products").doc(String(it.productId));
        prodSnaps.push({ it, pRef, snap: await tx.get(pRef) });
    }
    for (const { it, pRef, snap } of prodSnaps) {
        if (!snap.exists) continue;
        const curStock = Number((snap.data() || {}).stock) || 0;
        const nextStock = Math.max(0, curStock - (Number(it.qty) || 0));
        tx.update(pRef, { stock: nextStock, updatedAt: FV.serverTimestamp() });
        tx.set(db().collection("canteen_stock_movements").doc(), {
            institutionId: up(pay.institutionId),
            productId: String(it.productId),
            type: "out",
            qty: Number(it.qty) || 0,
            note: `Mobil QR Online Satış (${payRef.id})`,
            by: pay.uid,
            createdAt: FV.serverTimestamp(),
        });
    }
    const uData = uSnap.exists ? uSnap.data() || {} : {};
    const payerName = String(uData.fullName || uData.name || uData.displayName || "Mobil Kullanıcı");
    const payerRole = String(uData.role || "");
    const tRef = db().collection("canteen_transactions").doc();
    tx.set(tRef, {
        institutionId: up(pay.institutionId),
        cardNo: "",
        studentId: pay.uid,
        type: "sale",
        method: "qr",
        amount: pay.amount,
        items,
        balanceAfter: 0,
        cashierId: s.cashierId || pay.uid,
        qrSessionId: pay.qrSessionId,
        paymentId: payRef.id,
        createdAt: FV.serverTimestamp(),
    });
    tx.set(db().collection("canteen_ledger").doc(), {
        institutionId: up(pay.institutionId),
        type: "income",
        category: "Satış",
        amount: pay.amount,
        note: `Mobil QR Satış ${tRef.id} - ${payerName} (Online Kart)`,
        date: admin.firestore.Timestamp.now(),
        createdAt: FV.serverTimestamp(),
    });
    tx.update(sRef, {
        status: "paid",
        payerUid: pay.uid,
        payerName,
        payerRole,
        cardNo: "",
        payVia: "online",
        transactionId: tRef.id,
        paidAt: FV.serverTimestamp(),
    });
    tx.update(payRef, {
        status: "success",
        iyzicoPaymentId: String(iyz.paymentId || ""),
        completedAt: FV.serverTimestamp(),
    });
}

/**
 * Token ile ödeme sonucunu iyzico'dan doğrular ve idempotent işler.
 * @returns {Promise<{ok: boolean, message: string}>}
 */
async function finalizePayment(token) {
    const q = await db().collection("payments").where("iyzicoToken", "==", token).limit(1).get();
    if (q.empty) return { ok: false, message: "Ödeme kaydı bulunamadı." };
    const payRef = q.docs[0].ref;
    const first = q.docs[0].data();
    if (first.status === "success") return { ok: true, message: "Ödeme alındı." };
    if (first.status === "failed") return { ok: false, message: first.failureReason || "Ödeme başarısız." };

    const posTargetInst = first.posOwnerInstitutionId || first.institutionId || "SUPER_ADMIN";
    const posChannel = first.posChannel || (first.kind === "store_order" ? "store" : "canteen");
    const posResolved = await resolvePosConfig(posTargetInst, posChannel);
    const iyzipay = posResolved.iyzipay;
    let iyz;
    try {
        iyz = await iyzicoCall(iyzipay.checkoutForm.retrieve.bind(iyzipay.checkoutForm), {
            locale: "tr",
            conversationId: first.conversationId,
            token,
        });
    } catch (e) {
        console.error("iyzico retrieve connection error", e && e.message);
        return { ok: false, message: "Ödeme durumu şu an doğrulanamadı. Lütfen uygulamaya dönüp kontrol edin." };
    }

    let success = false;
    let reason = (iyz && iyz.errorMessage) || "Ödeme onaylanmadı";
    if (iyz && iyz.status === "success" && iyz.paymentStatus === "SUCCESS") {
        const paidOk = toCents(iyz.paidPrice) >= toCents(first.amount);
        const priceOk = toCents(iyz.price) === toCents(first.amount);
        const convOk = !iyz.conversationId || iyz.conversationId === first.conversationId;
        if (paidOk && priceOk && convOk) success = true;
        else reason = "Ödeme tutarı doğrulanamadı";
    } else if (iyz && iyz.paymentStatus && iyz.paymentStatus !== "SUCCESS") {
        reason = iyz.errorMessage || "Ödeme başarısız veya iptal edildi";
    }

    await db().runTransaction(async (tx) => {
        const cur = await tx.get(payRef);
        const pay = cur.data() || {};
        if (pay.status !== "pending") return; // idempotent
        if (!success) {
            if (pay.kind === "store_order") return applyStoreFailure(tx, payRef, pay, reason);
            tx.update(payRef, {
                status: "failed",
                failureReason: String(reason).substring(0, 300),
                completedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return;
        }
        if (pay.kind === "canteen_topup") return applyCanteenTopup(tx, payRef, pay, iyz);
        if (pay.kind === "canteen_qr") return applyCanteenQrSuccess(tx, payRef, pay, iyz);
        if (pay.kind === "store_order") return applyStoreSuccess(tx, payRef, pay, iyz);
        tx.update(payRef, { status: "failed", failureReason: "Bilinmeyen ödeme türü" });
    });

    return success
        ? { ok: true, message: "Ödeme alındı." }
        : { ok: false, message: reason };
}

// ─── iyzicoCallback ───────────────────────────────────────────────────────────

function htmlPage(ok, message) {
    const title = ok ? "Ödeme alındı" : "Ödeme tamamlanamadı";
    const body = ok
        ? "Ödeme alındı, bu sekmeyi kapatıp uygulamaya dönebilirsiniz."
        : `Ödeme tamamlanamadı: ${escapeHtml(message)}<br>Bu sekmeyi kapatıp uygulamaya dönebilirsiniz.`;
    return `<!DOCTYPE html><html lang="tr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>body{font-family:Arial,sans-serif;background:#f5f6fa;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.c{background:#fff;border-radius:16px;padding:32px;max-width:420px;margin:16px;text-align:center;box-shadow:0 4px 20px rgba(0,0,0,.08)}
.i{font-size:48px;color:${ok ? "#2e7d32" : "#c62828"}}h1{font-size:20px;color:#1a237e}p{color:#444;line-height:1.5}</style></head>
<body><div class="c"><div class="i">${ok ? "&#10004;" : "&#10006;"}</div><h1>${title}</h1><p>${body}</p></div></body></html>`;
}

exports.iyzicoCallback = onRequest(
    { secrets: [iyzicoApiKey, iyzicoSecretKey, iyzicoBaseUrl], invoker: "public" },
    async (req, res) => {
        res.set("Content-Type", "text/html; charset=utf-8");
        if (req.method !== "POST") {
            res.status(405).send(htmlPage(false, "Geçersiz istek."));
            return;
        }
        const token = req.body && typeof req.body.token === "string" ? req.body.token.trim() : "";
        if (!token || token.length > 200) {
            res.status(400).send(htmlPage(false, "Ödeme belirteci eksik."));
            return;
        }
        try {
            const r = await finalizePayment(token);
            res.status(200).send(htmlPage(r.ok, r.message));
        } catch (e) {
            console.error("iyzicoCallback error", e && e.message);
            res.status(500).send(htmlPage(false, "Beklenmeyen bir hata oluştu."));
        }
    },
);
