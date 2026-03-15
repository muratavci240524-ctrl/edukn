# 🎯 Okul Dashboard Özellikleri

## ✅ Tamamlanan Özellikler

### 📊 Dashboard Ana Ekran
- ✅ Hoş geldin kartı (yönetici adıyla)
- ✅ Okul durumu göstergesi (Aktif/Pasif)
- ✅ Lisans süresi takibi (kalan gün sayısı)
- ✅ Öğrenci kotası görüntüleme (**246/1100** formatında + yüzde gösterimi)
- ✅ Kurum ID gösterimi
- ✅ Gerçek zamanlı öğrenci sayısı (Firestore'dan çekiliyor)

### 🎨 Hızlı Erişim Menüsü
1. **Hesap Düzenle** - Yöneticinin kendi bilgilerini güncellemesi
2. **Kullanıcı Ekle** - Yeni personel ekleme ve yetkilendirme
3. **Okul Türleri** - Anaokulu, İlkokul, Ortaokul, Lise türleri yönetimi
4. **Duyuru Yap** - Genel duyuru oluşturma

### 📑 Yan Menü (Drawer)
Kategorize edilmiş menü yapısı:

#### YÖNETİM
- Kullanıcı Yönetimi
- Okul Türleri

#### EĞİTİM
- Öğrenci Yönetimi
- Devamsızlık Takibi
- Not Sistemi

#### İLETİŞİM
- Duyurular

---

## 🚧 Yapılacak Özellikler

### 1️⃣ Hesap Düzenleme Ekranı
**Dosya:** `lib/screens/school/account_settings_screen.dart`

Özellikler:
- Yönetici adı, email, telefon güncelleme
- Şifre değiştirme
- Profil fotoğrafı yükleme
- Okul bilgileri görüntüleme (salt okunur)

---

### 2️⃣ Kullanıcı Yönetimi Ekranı
**Dosya:** `lib/screens/school/user_management_screen.dart`

Özellikler:
- Kullanıcı listesi (tablo görünümü)
- Yeni kullanıcı ekleme formu
- Kullanıcı düzenleme/silme
- Yetki rolleri:
  - **Genel Müdür** - Tüm yetkilere erişim
  - **Muhasebe** - Finansal işlemler
  - **Satın Alma** - Tedarik yönetimi
  - **İnsan Kaynakları** - Personel yönetimi
  - **Öğretmen** - Not girişi, devamsızlık
  - **Özel Yetkiler** - Modül bazlı özelleştirme

Firestore Koleksiyonu:
```
users/
  ├─ {userId}
      ├─ fullName: string
      ├─ email: string
      ├─ phone: string
      ├─ role: string (general_manager, accounting, hr, teacher, etc.)
      ├─ institutionId: string
      ├─ permissions: array<string>
      ├─ isActive: boolean
      ├─ createdAt: timestamp
      └─ lastLogin: timestamp
```

---

### 3️⃣ Okul Türleri Yönetimi Ekranı
**Dosya:** `lib/screens/school/school_types_screen.dart`

Özellikler:
- Okul türü listesi (kart görünümü)
- Yeni okul türü ekleme
- Okul türüne özel isim verme
- Okul türü düzenleme/silme
- Her okul türü için:
  - Öğrenci sayısı
  - Aktif sınıf sayısı
  - Öğretmen sayısı

Önceden tanımlı türler:
- Anaokulu
- İlkokul
- Ortaokul
- Anadolu Lisesi
- Fen Lisesi
- Kurs/Etüt Merkezi

Firestore Koleksiyonu:
```
schoolTypes/
  ├─ {typeId}
      ├─ institutionId: string
      ├─ typeName: string (anaokulu, ilkokul, ortaokul, etc.)
      ├─ customName: string (ör: "Bilge Koleji İlkokulu")
      ├─ studentCount: number
      ├─ classCount: number
      ├─ teacherCount: number
      ├─ isActive: boolean
      ├─ color: string (hex renk kodu)
      └─ createdAt: timestamp
```

---

### 4️⃣ Duyuru Oluşturma Ekranı
**Dosya:** `lib/screens/school/announcements_screen.dart`

Özellikler:
- Duyuru listesi
- Yeni duyuru oluşturma formu
- Hedef kitle seçimi:
  - Tüm okul
  - Belirli okul türü
  - Belirli sınıf
  - Belirli öğrenci grubu
- Öncelik seviyesi (Normal, Önemli, Acil)
- Dosya ekleme (PDF, resim)
- Yayın tarihi planlama

Firestore Koleksiyonu:
```
announcements/
  ├─ {announcementId}
      ├─ institutionId: string
      ├─ title: string
      ├─ content: string
      ├─ priority: string (normal, important, urgent)
      ├─ targetAudience: array<string>
      ├─ schoolTypes: array<string>
      ├─ attachments: array<string> (URLs)
      ├─ publishDate: timestamp
      ├─ expiryDate: timestamp
      ├─ isActive: boolean
      ├─ createdBy: string
      └─ createdAt: timestamp
```

---

## 🎨 Tasarım Prensipleri

### Renk Paleti
- **Birincil:** Indigo (#3F51B5)
- **İkincil:** Blue (#2196F3)
- **Başarı:** Green (#4CAF50)
- **Uyarı:** Orange (#FF9800)
- **Hata:** Red (#F44336)
- **Bilgi:** Purple (#9C27B0)
- **Nötr:** Teal (#009688)

### UI Bileşenleri
- **Kartlar:** Yuvarlatılma 12px, elevation 2
- **Butonlar:** Yuvarlatılma 12px, yükseklik 50px
- **Form Alanları:** Outlined style, yuvarlatılma 12px
- **İkonlar:** Material Icons, boyut 24-48px
- **Fontlar:** Google Fonts - Inter

### Responsive Tasarım
- Mobile: Tek sütun layout
- Tablet: İki sütun grid
- Desktop: Üç-dört sütun grid

---

## 📱 Navigasyon Yapısı

```
/school-login
  └─ /school-dashboard (Ana ekran)
      ├─ /account-settings (Hesap ayarları)
      ├─ /user-management (Kullanıcı yönetimi)
      ├─ /school-types (Okul türleri)
      ├─ /announcements (Duyurular)
      ├─ /student-management (Öğrenci yönetimi)
      ├─ /attendance (Devamsızlık)
      └─ /grades (Not sistemi)
```

---

## 🔐 Güvenlik Notları

1. **Firebase Authentication** - Tüm kullanıcılar için email/password
2. **Firestore Security Rules** - institutionId bazlı erişim kontrolü
3. **Role-Based Access** - Yetki bazlı ekran ve işlem kontrolü
4. **Input Validation** - Tüm form girişleri doğrulanmalı
5. **Session Management** - Otomatik çıkış ve token yenileme

---

## 📦 Gerekli Paketler

```yaml
dependencies:
  firebase_core: latest
  firebase_auth: latest
  cloud_firestore: latest
  firebase_storage: latest # Dosya yükleme için
  image_picker: latest # Profil fotoğrafı için
  file_picker: latest # Dosya ekleme için
  intl: latest # Tarih formatlama
  provider: latest # State management
```

---

## 🚀 Geliştirme Sırası Önerisi

1. **Hesap Düzenleme** (En basit, temel CRUD)
2. **Kullanıcı Yönetimi** (Kompleks yetkilendirme)
3. **Okul Türleri** (Orta seviye, liste yönetimi)
4. **Duyuru Sistemi** (Dosya yükleme içerir)

Her özellik için ayrı branch açılması önerilir.
