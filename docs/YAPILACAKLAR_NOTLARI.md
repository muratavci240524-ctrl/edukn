# 📝 eduKN – Sonra Yapılacaklar Notları

> Bu dosya, konuşup karar verdiğimiz ama **henüz yapmadığımız** işlerin hatırlatma listesidir.
> Bir iş tamamlanınca başına ✅ koyup altına tarihini yazalım.

---

## 1. 🖼️ Soru Görsellerini Cloudflare R2'ye Taşıma + Soru Havuzunu Sayfalı Yükleme

**Durum:** ⏳ Bekliyor (toplu soru yüklemeye başlamadan ÖNCE yapılmalı)
**Not alınma tarihi:** 13.11.2026

### Neden?
- Soru havuzuna **500.000+ soru** yüklemeyi planlıyorum.
- Şu an Tablodan Aktar penceresindeki **"Drive Görsellerini PDF İçin Önbellekle"** seçeneği görselleri
  Firestore'daki soru belgesinin içine (`base64Image`) gömüyor.
  - 500.000 soru × ~200 KB ≈ **~100 GB** → Firestore'da hem depolama hem **okuma/indirme ücreti** pahalı olur.
  - Firestore'da belge başına **1 MB sınırı** var, büyük görseller zaten sığmıyor.
- Ayrıca Soru Havuzu ve Fokus Kitap şu an **tüm havuzu tek seferde** yüklüyor.
  500.000 soruda görseller olmasa bile bu yapı çalışmaz (yavaşlar, tarayıcı çöker, okuma faturası şişer).

### Karar: Cloudflare R2
| | Cloudflare R2 | Firebase Storage |
|---|---|---|
| Ücretsiz | 10 GB + aylık milyonlarca işlem | Sınırlı |
| Sonrası | ~0,015 $ / GB / ay | ~0,026 $ / GB / ay |
| Görsel indirme (trafik) | **Ücretsiz** | Ücretli (~0,12 $ / GB) |

- 500.000 soru ≈ 100 GB ≈ **ayda ~1,5 $** (tahmini, fiyatları yapmadan önce tekrar kontrol et).
- Yedek seçenek: **Backblaze B2** (+ Cloudflare ile ücretsiz trafik).

### Hedef Yapı
```
Google Sheets + Drive ──(aktarımda 1 kez)──> Cloudflare R2 (tam görsel + küçük önizleme)
                                                   │
Firestore (sadece soru bilgisi + R2 görsel linki) ─┘
```
- **Firestore:** konu, alt konu, kazanım, zorluk, cevap, R2 görsel linki (~1 KB / soru).
- **R2:** tam boy görsel + soru kartları için 10–20 KB'lık küçük önizleme.
- **Drive:** sadece kaynak; aktarımda bir kere okunup R2'ye kopyalanır.

### Yapılacaklar Listesi
- [ ] Cloudflare hesabı aç, R2 bucket oluştur, **bütçe uyarısı** kur.
- [ ] R2 erişim anahtarını **uygulamaya KOYMA** → yükleme Cloud Function / Cloudflare Worker üzerinden,
      kısa süreli **imzalı link** ile yapılsın.
- [ ] Görseller herkese açık mı olacak, imzalı (süreli) link mi? (Telifli içerik varsa imzalı link.)
- [ ] Google Tablodan Aktar: görseli Drive'dan alıp R2'ye yükle, Firestore'a sadece linki yaz
      (`base64Image` artık yazılmasın). Küçük önizleme (thumbnail) de üretilsin.
- [ ] Mevcut `base64Image` alanlı soruları R2'ye taşıyan **tek seferlik geçiş (migration)** aracı.
- [ ] Soru Havuzu: **sayfalı yükleme** → konu / alt konu seçilince sadece o konunun soruları, 20'şer 20'şer.
- [ ] Sol listedeki konu / alt konu **soru sayıları** ayrı bir özet belgesinden okunsun (her seferinde saymasın).
- [ ] Soru kartlarında tam görsel yerine **küçük önizleme** gösterilsin.
- [ ] Test PDF'i ve Fokus Kitap üretiminde sadece **seçilen soruların** görselleri R2'den indirilsin.
- [ ] Firebase konsolunda da **bütçe uyarısı** kur.

### İlgili Dosyalar
- `lib/screens/school/assessment/question_pool/google_sheets_pool_import_dialog.dart` (Tablodan Aktar, önbellek seçeneği)
- `lib/screens/school/assessment/question_pool/question_pool_screen.dart` (Soru Havuzu, sol liste)
- `lib/screens/school/assessment/personalized_book/personalized_book_generator_service.dart` (Fokus Kitap havuz yükleme ve görseller)
- `lib/services/assessment_service.dart` (`getGlobalQuestionsPool`)
- `lib/utils/drive_image_helper.dart` (Drive görsel indirme)

> ⚠️ Şimdilik az soru varken (birkaç bin) mevcut önbellek seçeneği sorun çıkarmaz.
> Büyük toplu yüklemeye başlamadan önce bu iş bitmiş olmalı; sonradan taşımak 500.000 soruyu yeniden işlemek demek.

---

## 2. 🔒 Akıllı Tahta Kilit Programı (Fikir Aşaması)

**Durum:** 💡 Fikir – daha sonra konuşulacak
**Not alınma tarihi:** 13.11.2026

- Sınıf akıllı tahtalarına kurulan kilit uygulaması: öğretmen **QR** (eduKN uygulaması) veya **USB anahtar** ile açar.
- İnternet yokken de çalışmalı (okulda yerel sunucu + internetsiz doğrulanan imzalı kodlar).
- Merkezden izleme, uzaktan yönetim, duyuru ve ekran paylaşımı (MeshCentral / WebRTC).
- Tahta tarafı ayrı bir program (Flutter arayüz + Go/Rust servis), yönetim paneli eduKN içinde.
- İlk iş: hedef okullardaki tahtaların **marka ve işletim sistemini** (Pardus / Android / Windows) öğrenmek.
- Önce tek okulda, tek tahta modelinde pilot.

