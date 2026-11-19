# eduKN — Sanal POS (iyzico) Kurulum ve Canlıya Alma Rehberi

Bu proje hem **Mağaza Modülü** hem de **Kantin Online Bakiye Yükleme** işlemleri için **iyzico Barındırılan Ödeme Formu (Hosted Checkout Form)** kullanır.

- Kart bilgileri (kart numarası, son kullanma tarihi, CVV) **asla uygulamaya veya sunucunuza girmez**; müşteri ödemeyi doğrudan iyzico'nun 3D Secure destekli güvenli ödeme sayfasında tamamlar (PCI-DSS uyumlu).
- Ödeme sonucu iyzico tarafından sunucudaki `iyzicoCallback` uç noktasına bildirilir; tutar ve durum sunucuda doğrulandıktan sonra bakiye yüklemesi veya sipariş onayı **idempotent** (tekil ve güvenli) olarak Firestore'a işlenir.

---

## 1. iyzico API Anahtarlarını Alma

1. **Test (Sandbox) için:** https://sandbox-merchant.iyzipay.com adresinden ücretsiz test hesabı açın ve **Ayarlar → Firma Ayarları** bölümünden `API Anahtarı` ve `Güvenlik Anahtarı` değerlerini kopyalayın.
2. **Canlı (Production) için:** https://merchant.iyzipay.com üye işyeri panelinizden canlı `API Anahtarı` ve `Güvenlik Anahtarı` değerlerini alın.

---

## 2. Firebase Cloud Functions Bağımlılıkları ve Gizli Anahtarlar (Secrets)

Proje kök dizininde terminali açıp önce `functions` bağımlılıklarını kurun:

```powershell
cd functions
npm install
cd ..
```

Ardından Firebase Secret Manager ile iyzico anahtarlarınızı tanımlayın:

```powershell
firebase functions:secrets:set IYZICO_API_KEY
firebase functions:secrets:set IYZICO_SECRET_KEY
firebase functions:secrets:set IYZICO_BASE_URL
```

- **Test ortamı için `IYZICO_BASE_URL`:** `https://sandbox-api.iyzipay.com`
- **Canlı ortam için `IYZICO_BASE_URL`:** `https://api.iyzipay.com`

---

## 3. Kuralları ve Fonksiyonları Yayınlama (Deploy)

Aşağıdaki komutla hem **Firestore / Storage güvenlik kurallarını** hem de **ödeme fonksiyonlarını** canlıya gönderin:

```powershell
firebase deploy --only firestore:rules,storage,functions:createPaymentSession,functions:iyzicoCallback
```

---

## 4. Test Kartları (Sandbox)

`IYZICO_BASE_URL` değeri `https://sandbox-api.iyzipay.com` iken iyzico'nun resmi test kartlarıyla (ör. `5528 7900 0000 0008`, son kullanma `12/30`, CVC `000`, 3D SMS kodu `283126`) gerçek para çekilmeden uçtan uca bakiye yükleme ve mağaza siparişi testi yapabilirsiniz.

---

## 5. Mimari Not (Tekil Üye İşyeri)

Mevcut entegrasyonda tüm online tahsilatlar tanımlanan **Genel Merkez iyzico üye işyeri** hesabına aktarılır; siparişler ve kantin bakiye hareketleri Firestore'da ilgili okulun `institutionId` koduyla ayrıştırılır. Okul bazlı otomatik banka hakediş dağılımı (iyzico Pazaryeri / Alt Üye İşyeri) istenirse iyzico Pazaryeri sözleşmesi sonrasında `subMerchantKey` alanı eklenerek genişletilebilir.

