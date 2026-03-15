# Yetki Yönetimi Sistemi Planı

## Genel Bakış
Sistemde farklı rollere sahip kullanıcılar için detaylı yetki yönetimi yapılacak.

## Kullanıcı Rolleri
1. **Genel Müdür** - En üst düzey yönetici
2. **Müdür** - Okul müdürü
3. **Müdür Yardımcısı** - Müdür yardımcısı
4. **Yönetici** - Genel yönetici
5. **Rehber Öğretmen** - Rehberlik servisi
6. **Öğretmen** - Eğitim personeli
7. **Personel** - Diğer çalışanlar

## Yetki Kategorileri

### 1. Öğrenci Yönetimi
- Öğrenci ekleme/düzenleme/silme
- Öğrenci bilgilerini görüntüleme
- Öğrenci notlarını görüntüleme/düzenleme
- Devam durumu takibi

### 2. Personel Yönetimi
- Personel ekleme/düzenleme/silme
- Personel bilgilerini görüntüleme
- Maaş bilgilerini görüntüleme/düzenleme
- Performans değerlendirme

### 3. Akademik İşlemler
- Ders programı oluşturma/düzenleme
- Not girişi
- Sınav oluşturma
- Müfredat yönetimi

### 4. Finansal İşlemler
- Ödeme takibi
- Bordro yönetimi
- Bütçe görüntüleme
- Raporlama

### 5. Sistem Yönetimi
- Kullanıcı yönetimi
- Yetki dağıtımı
- Sistem ayarları
- Backup/Restore

## Veritabanı Yapısı

### permissions koleksiyonu
```json
{
  "roleId": "genel_mudur",
  "roleName": "Genel Müdür",
  "permissions": {
    "student_management": {
      "view": true,
      "create": true,
      "edit": true,
      "delete": true
    },
    "staff_management": {
      "view": true,
      "create": true,
      "edit": true,
      "delete": true
    },
    "academic": {
      "view": true,
      "create": true,
      "edit": true,
      "delete": true
    },
    "financial": {
      "view": true,
      "create": true,
      "edit": true,
      "delete": true
    },
    "system": {
      "view": true,
      "create": true,
      "edit": true,
      "delete": true
    }
  }
}
```

### user_permissions koleksiyonu (Özel yetkiler için)
```json
{
  "userId": "user123",
  "customPermissions": {
    "student_management": {
      "view": true,
      "create": false,
      "edit": true,
      "delete": false
    }
  },
  "overrideRole": false
}
```

## Yetki Yönetimi Ekranı Tasarımı

### Ana Sayfa
- Sol tarafta roller listesi
- Sağ tarafta seçili rolün yetkileri
- Her yetki kategorisi için genişletilebilir kartlar

### Özellikler
1. **Rol Bazlı Yetkilendirme**
   - Her rol için varsayılan yetkiler
   - Toplu yetki verme/kaldırma
   
2. **Kullanıcı Bazlı Özel Yetkiler**
   - Belirli kullanıcılara özel yetkiler
   - Rol yetkilerini override etme
   
3. **Yetki Şablonları**
   - Hazır yetki şablonları
   - Özel şablon oluşturma
   
4. **Yetki Geçmişi**
   - Yetki değişikliklerinin loglanması
   - Kim, ne zaman, hangi yetkiyi değiştirdi

## Uygulama Dosyaları

### Oluşturulacak Dosyalar
1. `lib/screens/admin/permission_management_screen.dart` - Ana yetki yönetimi ekranı
2. `lib/services/permission_service.dart` - Yetki kontrol servisi
3. `lib/models/permission_model.dart` - Yetki modeli
4. `lib/models/role_model.dart` - Rol modeli
5. `lib/widgets/permission_card.dart` - Yetki kartı widget'ı

### Örnek Kullanım
```dart
// Yetki kontrolü
final permissionService = PermissionService();
final canEdit = await permissionService.checkPermission(
  userId: currentUser.id,
  module: 'student_management',
  action: 'edit',
);

if (canEdit) {
  // İşlemi gerçekleştir
}
```

## Varsayılan Yetki Dağılımı

### Genel Müdür
- Tüm modüllerde tam yetki

### Müdür
- Öğrenci yönetimi: Tam yetki
- Personel yönetimi: Görüntüleme ve düzenleme
- Akademik: Tam yetki
- Finansal: Görüntüleme
- Sistem: Kısıtlı

### Müdür Yardımcısı
- Öğrenci yönetimi: Görüntüleme ve düzenleme
- Personel yönetimi: Görüntüleme
- Akademik: Görüntüleme ve düzenleme
- Finansal: Yok
- Sistem: Yok

### Yönetici
- Öğrenci yönetimi: Görüntüleme ve düzenleme
- Personel yönetimi: Görüntüleme
- Akademik: Görüntüleme
- Finansal: Yok
- Sistem: Yok

### Rehber Öğretmen
- Öğrenci yönetimi: Görüntüleme ve düzenleme (rehberlik bilgileri)
- Personel yönetimi: Yok
- Akademik: Görüntüleme
- Finansal: Yok
- Sistem: Yok

### Öğretmen
- Öğrenci yönetimi: Görüntüleme (kendi öğrencileri)
- Personel yönetimi: Yok
- Akademik: Kendi dersleri için tam yetki
- Finansal: Yok
- Sistem: Yok

### Personel
- Öğrenci yönetimi: Yok
- Personel yönetimi: Yok
- Akademik: Yok
- Finansal: Yok
- Sistem: Yok

## Geliştirme Aşamaları

### Faz 1: Temel Altyapı (1-2 hafta)
- [ ] Permission modeli oluşturma
- [ ] Role modeli oluşturma
- [ ] PermissionService implementasyonu
- [ ] Firestore koleksiyonları oluşturma
- [ ] Varsayılan rol yetkilerini tanımlama

### Faz 2: Yönetim Ekranı (2-3 hafta)
- [ ] Permission management screen tasarımı
- [ ] Rol listesi ve detay görünümü
- [ ] Yetki düzenleme arayüzü
- [ ] Kullanıcı bazlı özel yetki ataması
- [ ] Yetki şablonları

### Faz 3: Entegrasyon (1-2 hafta)
- [ ] Mevcut ekranlara yetki kontrolü ekleme
- [ ] Widget'larda yetki bazlı görünürlük
- [ ] API çağrılarında yetki kontrolü
- [ ] Test ve hata düzeltme

### Faz 4: Gelişmiş Özellikler (2-3 hafta)
- [ ] Yetki geçmişi loglama
- [ ] Yetki raporlama
- [ ] Toplu yetki işlemleri
- [ ] Yetki şablonları import/export

## Güvenlik Önlemleri
1. Backend'de de yetki kontrolü yapılmalı (Firestore Security Rules)
2. Hassas işlemler için ek doğrulama
3. Yetki değişikliklerinin loglanması
4. Kritik yetkilerin iki faktörlü onayı

## Notlar
- Bu sistem modüler olarak geliştirilecek
- İlk etapta temel yetkiler tanımlanacak
- Zamanla yeni yetki kategorileri eklenebilir
- Her modül kendi yetki kontrolünü yapacak
