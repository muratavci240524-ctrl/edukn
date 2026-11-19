import 'package:flutter/material.dart';

/// Okul türlerine özel (Anaokulu, İlkokul, Ortaokul, Lise, Kurs) modüller ve 3 seviyeli alt başlıklar
class SchoolTypeModules {
  static final Map<String, SchoolTypeModuleInfo> modules = {
    'kayit': SchoolTypeModuleInfo(
      key: 'kayit',
      name: 'Öğrenci ve Personel',
      icon: Icons.people_outline,
      color: Colors.blue,
      description:
          'Ön kayıt, öğrenci listesi, personel, şube, ders, kurs/kulüp, derslik ve kitap tanımları',
      subModules: {
        'on_kayit': 'Ön Kayıt İşlemleri',
        'ogrenci_listesi': 'Öğrenci Listesi & Kayıt',
        'personel_listesi': 'Personel Listesi',
        'sube_listesi': 'Şube Listesi & Tanımları',
        'ders_listesi': 'Ders / Müfredat Listesi',
        'kurs_listesi': 'Kurs Listesi (Dinamik Gruplar)',
        'kulup_listesi': 'Kulüp Listesi (Dinamik Gruplar)',
        'derslik_listesi': 'Derslik Listesi & Tanımları',
        'kitap_listesi': 'Kitap / Yayın Listesi',
      },
      nestedSubModules: {
        'on_kayit': {
          'st_on_kayit_ekle': 'Yeni Aday Öğrenci Ön Kaydı',
          'st_on_kayit_gorusme': 'Ön Kayıt Görüşme Notu Ekleme',
          'st_on_kayit_kesin': 'Kesin Kayda Dönüştürme',
          'st_on_kayit_istatistik_sil': 'Ön Kayıt İstatistikleri & Silme',
        },
        'ogrenci_listesi': {
          'ogrenci_liste_goruntule': 'Öğrenci Listesi Görüntüleme & Arama',
          'ogrenci_kayit_duzenle': 'Yeni Öğrenci Kaydı & Bilgileri Düzenleme',
          'ogrenci_veli_bilgi': 'Veli / İletişim Bilgilerini Düzenleme',
          'toplu_veri_yukleme': 'Toplu Öğrenci Yükleme (Excel)',
          'kayit_silme': 'Kayıt Silme / Pasife Alma İşlemleri',
          'sinif_atlatma_nakil': 'Sınıf Atlatma & Okul Türü Nakil',
        },
        'personel_listesi': {
          'st_personel_goruntule': 'Kademe Personel Listesi Görüntüleme',
          'st_personel_duzenle': 'Personel Ekleme & Görev Düzenleme',
        },
        'sube_listesi': {
          'st_sube_goruntule': 'Şube Listesi & Öğrenci Sayılarını Görüntüleme',
          'st_sube_ac_duzenle': 'Yeni Şube Açma & Sınıf Öğretmeni Atama',
          'st_sube_ogrenci_ata': 'Şubeye Öğrenci Atama / Değiştirme',
          'st_sube_pasif_sil': 'Şube Pasife Alma / Silme & Boş Şube Temizleme',
        },
        'ders_listesi': {
          'st_ders_tanimla': 'Ders Ekleme & Haftalık Saat Tanımı',
          'st_ders_ogretmen_ata': 'Derse Öğretmen Atama',
          'st_ders_sil': 'Ders Silme / Pasife Alma',
        },
        'kurs_listesi': {
          'st_kurs_olustur': 'Yeni Kurs Grubu Açma & Öğretmen Atama',
          'st_kurs_ogrenci_yonet': 'Kurs Grubuna Öğrenci Ekleme / Çıkarma',
        },
        'kulup_listesi': {
          'st_kulup_olustur': 'Sosyal Kulüp Açma & Danışman Atama',
          'st_kulup_ogrenci_yonet': 'Kulüp Öğrenci Seçimi & Takibi',
        },
        'derslik_listesi': {
          'st_derslik_tanimla': 'Derslik, Laboratuvar & Kapasite Tanımı',
          'st_derslik_sil': 'Derslik Silme / Pasife Alma',
        },
        'kitap_listesi': {
          'st_kitap_yayin_tanimla': 'Ders Kitabı & Yardımcı Yayın Tanımlama',
          'st_kitap_sil': 'Kitap / Yayın Silme',
        },
      },
    ),

    'egitim': SchoolTypeModuleInfo(
      key: 'egitim',
      name: 'Eğitim İşlemleri',
      icon: Icons.school,
      color: Colors.green,
      description:
          'Günlük karne, çalışma takvimi, ders programı, kazanım takip, anket ve etüt süreçleri',
      subModules: {
        'gunluk_rapor': 'Günlük Rapor (Günlük Karne)',
        'calisma_takvimi': 'Çalışma Takvimi',
        'ders_saatleri': 'Ders Saatleri',
        'ders_programi': 'Ders Programı Hazırlama',
        'sube_programi': 'Şube Ders Programı',
        'ogretmen_programi': 'Öğretmen Ders Programı',
        'kazanimlar': 'Kazanım Takip Sistemi',
        'yoklama_girisi': 'Yoklama İşlemleri',
        'odev_tanimlama': 'Ödev İşlemleri',
        'anketler': 'Anket İşlemleri',
        'etutler': 'Etüt İşlemleri',
      },
      nestedSubModules: {
        'gunluk_rapor': {
          'gunluk_rapor_goruntule': 'Günlük Raporları Görüntüleme & Arama',
          'gunluk_rapor_beslenme': 'Giriş › Beslenme Takibi (Kahvaltı, Öğle, İkindi)',
          'gunluk_rapor_su': 'Giriş › Su Tüketimi Takibi',
          'gunluk_rapor_uyku': 'Giriş › Uyku & Dinlenme Saati',
          'gunluk_rapor_duygu': 'Giriş › Duygu Durumu & Arkadaş Uyumu',
          'gunluk_rapor_etkinlik':
              'Giriş › Etkinlik, Kitap, Gezi & Branş Ders Akışı',
          'gunluk_rapor_ozbakim': 'Giriş › Özbakım & Hijyen Takibi',
          'gunluk_rapor_saglik': 'Giriş › Sağlık & İlaç Gözlem Notu',
          'gunluk_rapor_veli_geri_bildirim':
              'Veli › Emoji Tepkisi & Teşekkür Notu',
          'gunluk_rapor_duzenle_sil':
              'Girilmiş Günlük Raporu Düzenleme & Silme',
          'gunluk_rapor_pdf': 'Günlük Karne PDF Çıktısı & Veliye Gönderim',
        },
        'calisma_takvimi': {
          'takvim_donem': 'Alt Dönem › Yeni Alt Dönem & Tatil Günleri Açma',
          'takvim_donem_duzenle_sil': 'Alt Dönem › Düzenleme & Silme',
          'takvim_plan': 'Plan › Çalışma Planı & Akademik Etkinlik Ekleme',
          'takvim_yillik_plan_sihirbaz':
              'Plan › Yıllık Plan Oluşturma Sihirbazı (Yeni Plan)',
          'ders_plani': 'Plan › Günlük / Haftalık Ders İşleyiş Planları',
          'takvim_sinif_filtre': 'Görünüm › Sınıf Seviyesi Bazlı Filtreleme',
          'takvim_excel_indir': 'Excel › Takvim / Planı Excel Olarak İndirme',
          'takvim_excel_yukle': 'Excel › Excel ile Toplu Plan Yükleme',
          'takvim_yazdir': 'Takvimi Yazdırma',
        },
        'ders_saatleri': {
          'ders_saatleri_goruntule': 'Ders Saatlerini Görüntüleme',
          'ders_saatleri_duzenle':
              'Gün Bazlı Ders & Teneffüs Saati Tanımlama',
          'ders_saatleri_kopyala': 'Bir Günün Saatlerini Başka Güne Kopyalama',
          'ders_saatleri_tumune_uygula':
              'Saat Düzenini Tüm Günlere Uygulama',
        },
        'ders_programi': {
          'ders_programi_donem_olustur':
              'Program Dönemi › Ders Programı Oluşturma & Düzenleme Ekranını Açma',
          // ── OTOMATİK DAĞITIM (ayrı yetki grubu) ──
          'ders_programi_dagitim':
              'Otomatik Dağıtım › Algoritmayı Çalıştırma (Programı Otomatik Dağıt)',
          'dp_oto_ayar_blok':
              'Otomatik Dağıtım › Ayar: Ders Blok Deseni (2+2+1 vb.) & Bölünebilir Ders',
          'dp_oto_ayar_saat_kacin':
              'Otomatik Dağıtım › Ayar: 1. Saatten / Son Saatten Kaçınma',
          'dp_oto_ayar_birlestirme':
              'Otomatik Dağıtım › Ayar: Sınıf Birleştirme (Birleşik Ders Grupları)',
          'dp_oto_ayar_kapali_saat':
              'Otomatik Dağıtım › Ayar: Kapalı Saatler (Sınıf / Öğretmen Müsaitliği)',
          'dp_oto_ayar_ogretmen_max':
              'Otomatik Dağıtım › Ayar: Öğretmen Günlük Maksimum Ders Saati',
          'dp_oto_ayar_yarim_gun':
              'Otomatik Dağıtım › Ayar: Yarım Gün (Sabah / Öğleden Sonra) & Esnek Gün',
          'dp_oto_kilit_koruma':
              'Otomatik Dağıtım › Kilitli Dersleri Koruyarak Dağıtma',
          // ── MANUEL DAĞITIM ──
          'dp_manuel_ders_ata': 'Manuel Dağıtım › Ders Seçerek Hücreye Atama',
          'dp_manuel_atama_kaldir': 'Manuel Dağıtım › Atamayı Kaldırma',
          'dp_manuel_yarim_gun_ata':
              'Manuel Dağıtım › Esnek Yarım Gün Öğretmen Ataması',
          // ── KİLİTLEME ──
          'dp_kilit_ders': 'Kilitleme › Tek Dersi Kilitleme / Açma',
          'dp_kilit_sinif': 'Kilitleme › Sınıfın Tüm Derslerini Kilitleme',
          'dp_kilit_ogretmen':
              'Kilitleme › Öğretmenin Tüm Derslerini Kilitleme',
          'dp_zumre_toplanti':
              'Zümre / Bölüm Toplantı Saatleri Tanımlama & Silme',
          // ── YAYIN ──
          'ders_programi_yayinla':
              'Yayın › Ders Programını Yayınlama & Öğretmene İletme',
          'dp_yayindan_kaldir': 'Yayın › Yayından Kaldırma',
          // ── ÇIKTI & DÖNEM ──
          'dp_cikti_tekli_sinif': 'Çıktı › Tekli Sınıf Programı (PDF / Excel)',
          'dp_cikti_tekli_ogretmen':
              'Çıktı › Tekli Öğretmen Programı (PDF / Excel)',
          'dp_cikti_sinif_carsaf': 'Çıktı › Sınıf Çarşaf Listesi (Toplu Tablo)',
          'dp_cikti_ogretmen_carsaf':
              'Çıktı › Öğretmen Çarşaf Listesi (Toplu Tablo)',
          'dp_donem_kopyala': 'Dönem › Programı Başka Döneme Kopyalama',
          'dp_program_temizle':
              'Dönem › Programı Temizleme (Kilitli Dersler Dahil / Hariç)',
        },
        'sube_programi': {
          'sube_prog_goruntule': 'Şube Ders Programını Görüntüleme',
          'sube_prog_cikti': 'Şube Programı PDF / Excel Çıktısı Alma',
        },
        'ogretmen_programi': {
          'ogr_prog_goruntule': 'Öğretmen Ders Programını Görüntüleme',
          'ogr_prog_cikti': 'Öğretmen Programı PDF / Excel Çıktısı Alma',
        },
        'kazanimlar': {
          'kazanim_ilerleme_analiz': 'Yıllık Plan İlerleme Analizi Görüntüleme',
          'kazanim_sube_ilerleme': 'Şube Bazlı İlerleme Durumları',
          'kazanim_haftalik_plan': 'Haftalık Kazanım Plan Detayları',
          'kazanim_plan_olustur_duzenle':
              'Yeni Yıllık Plan Ekleme & Düzenleme',
          'kazanim_sinif_ders_filtre': 'Sınıf Seviyesi / Dönem / Ders Filtresi',
        },
        'yoklama_girisi': {
          'yoklama_al_duzenle': 'Ders Yoklaması Alma & Düzenleme',
          'yoklama_gecmis_duzenle': 'Geçmiş Tarihli Yoklamayı Düzenleme',
          'yoklama_mazeret_izin': 'Mazeretli / İzinli İşleme',
          'yoklama_veli_sms': 'Devamsızlık Bildirimi Gönderme',
        },
        'odev_tanimlama': {
          'odev_ver_duzenle': 'Yeni Ödev Verme & Düzenleme',
          'odev_sil': 'Ödev Silme',
          'odev_kontrol_degerlendir': 'Ödev Kontrolü & Sonuç İşleme',
          'odev_istatistik': 'Ödev Teslim İstatistiklerini Görüntüleme',
        },
        'anketler': {
          'anket_olustur_duzenle': 'Anket Oluşturma & Düzenleme (Taslak Dahil)',
          'anket_bolum_soru': 'Bölüm & Soru Yönetimi (Kısa/Uzun Yanıt, Tek/Çok Seçim)',
          'anket_hedef_kitle':
              'Hedef Kitle Belirleme (Tüm Kurum / Belirli Sınıflar / Öğretmenler)',
          'anket_yayinla_planla': 'Anketi Hemen Yayınlama / İleri Tarihe Planlama',
          'anket_yayindan_kaldir': 'Anketi Yayından Kaldırma',
          'anket_sonuc_analiz': 'Anket Sonuçları & Gerçek Zamanlı İstatistik',
          'anket_excel_aktar': 'Anket Sonuçlarını Excel Olarak Dışa Aktarma',
        },
        'etutler': {
          'etut_planla_ac': 'Etüt Saati & Kota Tanımlama',
          'etut_olustur': 'Etüt Oluşturma (Şube / Öğrenci / Öğretmen Seçimi)',
          'etut_coklu_ogrenci': 'Çoklu Öğrenci Etüdü Oluşturma',
          'etut_sabit_haftalik': 'Sabit (Her Hafta Tekrarlanan) Etüt Tanımlama',
          'etut_cakisma_devam': 'Ders Programı Çakışma Uyarısına Rağmen Devam Etme',
          'etut_ogrenci_atama': 'Etüt Öğrenci Atama & Yoklama',
          'etut_iptal_hafta': 'İptal › Sabit Etüdü Sadece Bu Hafta İptal Etme',
          'etut_iptal_tamami': 'İptal › Etüdü Tüm Gelecek Haftalar İçin Silme',
          'etut_ogrenci_cikar': 'Etütten Tek Öğrenciyi Çıkarma',
          'etut_ogretmen_notu': 'Etüt Detayı & Öğretmen Notu Girişi',
        },
      },
    ),

    'rehberlik': SchoolTypeModuleInfo(
      key: 'rehberlik',
      name: 'Rehberlik İşlemleri',
      icon: Icons.folder_special,
      color: Colors.purple,
      description:
          'Portfolyo, talepler, görüşmeler, toplu gözlem, mentörlük, envanter ve 360 gelişim raporları',
      subModules: {
        'portfolyo': 'Portfolyo',
        'talepler': 'Talepler (Yönlendirmeler)',
        'gorusmeler': 'Görüşmeler',
        'toplu_gozlem': 'Toplu Gözlem Girişi',
        'mentor_calismalari': 'Mentör Çalışmaları',
        'pdr_ajanda': 'Rehberlik Ajandası',
        'envanterler': 'Envanterler (Rehberlik Testleri)',
        'gelisim_raporlari': '360 Gelişim Raporları',
        'calisma_programi': 'Ders Çalışma Programı',
      },
      nestedSubModules: {
        'portfolyo': {
          'portfolyo_genel_bilgiler': 'Genel Bilgiler',
          'portfolyo_deneme_sinavlari': 'Deneme Sınavları',
          'portfolyo_yazili_sinavlar': 'Yazılı Sınavlar',
          'portfolyo_odevler': 'Ödevler',
          'portfolyo_devamsizlik': 'Devamsızlık',
          'portfolyo_eylem_planlari': 'Eylem Planları',
          'portfolyo_etutler': 'Etütler',
          'portfolyo_kitaplar': 'Kitaplar',
          'portfolyo_gorusmeler': 'Görüşmeler',
          'portfolyo_talepler': 'Talepler',
          'portfolyo_gelisim_raporu': 'Gelişim Raporu',
          'portfolyo_mentor_calismalari': 'Mentör Çalışmaları',
          'portfolyo_rehberlik_testleri': 'Rehberlik Testleri',
          'portfolyo_etkinlik_raporlari': 'Etkinlik Raporları',
        },
        'gorusmeler': {
          'gorusme_goruntule': 'Görüşme Kayıtlarını Görüntüleme',
          'gorusme_ekle': 'Yeni Öğrenci / Veli Görüşmesi Ekleme',
          'gorusme_duzenle_sil': 'Görüşme Kaydını Düzenleme & Silme',
        },
        'talepler': {
          'rh_talep_goruntule': 'Talepleri (Yönlendirmeleri) Görüntüleme',
          'rh_talep_olustur': 'Yeni Yönlendirme / Talep Açma',
          'rh_talep_sonuclandir': 'Talep Atama & Sonuçlandırma',
        },
        'toplu_gozlem': {
          'etkinlikler': 'Gözlem Formlarını Görüntüleme',
          'gozlem_form_doldur': 'Sınıf Bazlı Toplu Gözlem Doldurma',
          'gozlem_form_olustur': 'Yeni Gözlem Kriteri / Formu Tanımlama',
        },
        'mentor_calismalari': {
          'rh_mentor_goruntule': 'Mentör Çalışmalarını Görüntüleme',
          'rh_mentor_yonet': 'Mentör Eşleştirme & Çalışma Kaydı Girme',
        },
        'pdr_ajanda': {
          'rh_ajanda_not': 'Rehberlik Ajandası Not / Randevu Girme',
        },
        'envanterler': {
          'rh_envanter_katalog': 'Envanter Kataloğunu Görüntüleme',
          'rh_envanter_uygula': 'Envanter Atama & Uygulama',
          'rh_envanter_sonuc': 'Envanter Sonuç & Analiz Raporları',
        },
        'gelisim_raporlari': {
          'rh_gelisim_goruntule': '360° Gelişim Raporlarını Görüntüleme',
          'rh_gelisim_degerlendir': 'Gelişim Ölçeklerini Doldurma & Yayınlama',
        },
        'calisma_programi': {
          'rh_calisma_prog_goruntule': 'Öğrenci Ders Çalışma Programını Görüntüleme',
          'rh_calisma_prog_hazirla': 'Ders Çalışma Programı Hazırlama & Düzenleme',
        },
      },
    ),

    'olcme': SchoolTypeModuleInfo(
      key: 'olcme',
      name: 'Ölçme Değerlendirme',
      icon: Icons.analytics,
      color: Colors.orange,
      description:
          'Sınav tanımları, sonuç raporları, denemeler, aktif sınavlar, hata kitapçığı ve soru havuzu',
      subModules: {
        'tanimlar': 'Tanımlar',
        'raporlar': 'Raporlar (Sınav Sonuç Raporları)',
        'denemeler': 'Denemeler',
        'sinavlar': 'Sınavlar (Aktif / Yazılı Sınavlar)',
        'hata_kitapcigi': 'Hata Kitapçığı',
        'fokus_kitap': 'Fokus Kitap (Kişiye Özel Soru Bankası)',
        'soru_havuzu': 'Soru Havuzu',
        'optik_okuma': 'Optik Form ve Okuma',
        'sinav_gorevlendirme': 'Sınav Görevlileri',
        'merkezi_deneme_raporlari': 'Genel Merkez Deneme Raporları',
      },
      nestedSubModules: {
        'tanimlar': {
          'st_olcme_optik_tanim': 'Optik Form & Kitapçık Tanımı',
          'st_olcme_puan_katsayi': 'Puanlama & Katsayı Formülleri',
        },
        'raporlar': {
          'sinav_tekil_liste': 'Tekil Sınav: Sonuç Listesi & Sıralamalar',
          'sinav_tekil_karne': 'Tekil Sınav: Öğrenci Sınav Karnesi',
          'sinav_tekil_ortalama': 'Tekil Sınav: Ders & Puan Ortalamaları',
          'sinav_tekil_basari_belgesi': 'Tekil Sınav: Başarı Belgeleri',
          'sinav_tekil_kazanim': 'Tekil Sınav: Kazanım Analizleri',
          'sinav_tekil_soru': 'Tekil Sınav: Soru / Madde Analizleri',
          'sinav_birlestirilmis_raporlar': 'Birleştirilmiş Sınav Raporları',
          'sinav_guclendirme_programlari': 'Güçlendirme Programları',
          'sinav_agm': 'AGM (Akademik Güçlendirme Merkezi)',
          'sinav_aksiyon_plani': 'Aksiyon Planları',
          'sinav_veli_raporu': 'Veli Bilgilendirme Raporu',
        },
        'denemeler': {
          'st_deneme_olustur': 'Yeni Deneme Sınavı Açma & Cevap Anahtarı',
          'st_deneme_optik_degerlendir': 'Optik Veri Yükleme & Değerlendirme',
          'st_deneme_yayinla': 'Deneme Sonuçlarını Yayınlama & Silme',
        },
        'sinavlar': {
          'not_girisi': 'Not Girişi & Düzenleme',
          'sinav_analizleri': 'Yazılı Sınav Madde Analizi',
        },
        'hata_kitapcigi': {
          'st_hata_kitapcigi_uret': 'Öğrenciye Özel Hata Kitapçığı Üretme',
          'st_hata_kitapcigi_takip': 'Basım & Teslim Takibi',
        },
        'fokus_kitap': {
          'st_fokus_kitap_olustur': 'Kazanım Bazlı Kişiye Özel Kitap Üretme',
          'st_fokus_kitap_kapak': 'Kapak, Ön Söz & İçindekiler Tasarımı',
          'st_fokus_kitap_indir': 'Toplu PDF / ZIP İndirme',
        },
        'soru_havuzu': {
          'st_soru_ekle_duzenle': 'Soru Ekleme & Düzenleme',
          'st_soru_test_uret': 'Yaprak Test & Sınav Kağıdı Oluşturma',
        },
        'optik_okuma': {
          'st_optik_sablon_yonet': 'Optik Form Şablonu & Alan Eşleştirme',
          'st_optik_txt_okuma': 'Optik TXT / DAT Okuma & Eşleştirme',
        },
        'sinav_gorevlendirme': {
          'st_sinav_gozetmen_ata': 'Salon & Gözetmen Öğretmen Atama',
          'st_sinav_gorev_cizelge': 'Sınav Görevlendirme Çizelgesi Yayınlama',
        },
        'merkezi_deneme_raporlari': {
          'st_merkezi_deneme_optik': 'Genel Merkez Denemesi Optik Gönderimi',
          'st_merkezi_deneme_analiz':
              'Türkiye & Kademe Karşılaştırmalı Raporlar',
        },
      },
    ),

    'araclar': SchoolTypeModuleInfo(
      key: 'araclar',
      name: 'Araçlar ve Operasyon Merkezi',
      icon: Icons.build_circle_outlined,
      color: Colors.amber,
      description:
          'Sınıf içi araçlar, kelebek sınav gözetmenlik, akademik simülatör, evrak otomasyonları ve canlı hareket',
      subModules: {
        'sinif_ici_yonetim': 'Sınıf İçi Yönetim ve Etkileşim',
        'sinav_gozetmenlik': 'Sınav ve Gözetmenlik (Kelebek Sistemi)',
        'akademik_olcme': 'Akademik Ölçme ve Başarı Takibi',
        'evrak_sablon': 'Evrak, Liste ve Şablon Otomasyonları',
        'ogrenci_hareket_takip': 'Geç - İzin - Revir - Görüşme (Canlı İzleme)',
        'online_hizmetler': 'Online Hizmetler',
        'notlarim': 'Notlarım',
      },
      nestedSubModules: {
        'sinif_ici_yonetim': {
          'sinif_akilli_tahta': 'Akıllı Beyaz Tahta',
          'sinif_oturma_plani': 'Sınıf Oturma Planı Oluşturucu',
          'sinif_gruplama': 'Homojen / Rastgele Gruplama',
          'sinif_ogrenci_secici': 'Rastgele Öğrenci Seçici',
          'sinif_performans_takibi': 'Hızlı Performans Takibi',
          'sinif_zamanlayici': 'Sınıf Zamanlayıcısı / Kronometre',
          'sinif_termometre': 'Sınıf Termometresi (Gürültü Ölçer)',
        },
        'sinav_gozetmenlik': {
          'sinav_plan_olusturma': 'Yeni Sınav Planı Hazırlama ve Düzenleme',
          'sinav_oturma_yoklama': 'Sınava Özel Oturma Planı ve Sınav Yoklaması',
          'sinav_raporu_alma': 'Sınav Yoklama Raporu Alma',
          'sinav_tamamlama': 'Sınavı Tamamlama / Arşivleme',
          'sinav_yayinlama': 'Sınav Gözetmenliklerini Yayınlama',
          'sinav_optik_kilavuz': 'Optik Form Kodlama Kılavuzu Jeneratörü',
        },
        'akademik_olcme': {
          'akademik_sampiyonlar':
              'LGS / YKS Şampiyonları ve Derece İhtimal Analizi',
          'akademik_hedef_simulator':
              'LGS & YKS Hedef, Puan ve Tercih Simülatörü',
          'akademik_isi_haritasi': 'Kazanım & Branş Başarı Isı Haritası',
          'akademik_risk_erken_uyari':
              '360° Akademik Risk ve Erken Uyarı Sistemi',
          'akademik_devamsizlik_radar': 'Devamsızlık ve Geç Kalma Radar Paneli',
          'akademik_deneme_kocu': 'Bireysel Deneme Gelişim ve Net Trend Koçu',
          'akademik_odev_etut_analiz':
              'Ödev Disiplini ve Etüt Verimlilik Analizi',
          'akademik_not_donusturucu':
              'Hızlı Test Notu, Çan Eğrisi ve Rubrik Dönüştürücü',
          'akademik_madde_analizi':
              'Madde Analizi (Güçlük / Ayırt Edicilik) ve KR-20',
        },
        'evrak_sablon': {
          'evrak_resmi_tutanak': 'Resmi Tutanak, Dilekçe & Disiplin Evrakları',
          'evrak_zumre_kurul': 'Zümre & Kurul Toplantı Şablonları',
          'evrak_sinif_liste': 'Sınıf İmza / Yoklama Çizelgeleri',
        },
        'ogrenci_hareket_takip': {
          'hareket_gec_kalan': 'Geç Kalan Öğrenci İşlemleri',
          'hareket_izin_erken': 'İzin / Erken Çıkış İşlemleri',
          'hareket_revir_gorusme': 'Revir & Görüşme Yönlendirme',
        },
      },
    ),

    'gorev': SchoolTypeModuleInfo(
      key: 'gorev',
      name: 'Görevlendirme ve İzin',
      icon: Icons.assignment_ind,
      color: Colors.teal,
      description:
          'To-Do görevleri, izin yönetimi, geçici öğretmen, nöbet, gezi ve proje görevlendirmeleri',
      subModules: {
        'todo_list': 'To do List (Yapılacaklar)',
        'izin_yonetimi': 'İzin Yönetimi',
        'gecici_ogretmen': 'Geçici Öğretmen (Ders Doldurma)',
        'nobet_islemleri': 'Nöbet İşlemleri & Çizelgesi',
        'gezi_gorev': 'Gezi Görevlendirmeleri',
        'proje_gorev': 'Proje Görevlendirmeleri',
      },
      nestedSubModules: {
        'todo_list': {
          'todo_kendi_gorev': 'Kendi Görevlerini Görüntüleme & Tamamlama',
          'todo_personel_ata': 'Personele / Öğretmene Görev Atama',
          'todo_gorev_sil': 'Atanmış Görevi Düzenleme & Silme',
        },
        'izin_yonetimi': {
          'izin_talep_olustur': 'İzin Talebi Oluşturma',
          'izin_onayla_reddet': 'Personel İzin Talebi Onaylama / Reddetme',
        },
        'gecici_ogretmen': {
          'gecici_ogr_ata': 'Boşalan Derse Geçici Öğretmen Atama',
          'gecici_ogr_rapor': 'Ders Doldurma Kayıtları & Raporu',
        },
        'nobet_islemleri': {
          'nobet_cizelge_hazirla': 'Nöbet Yeri & Nöbet Çizelgesi Hazırlama',
          'nobet_otomatik_dagit': 'Nöbet Çizelgesini Otomatik Dağıtma',
          'nobet_degisim_takip': 'Nöbet Değişikliği & Günlük Kontrol',
        },
        'gezi_gorev': {
          'gezi_olustur': 'Gezi Planı Oluşturma & Öğretmen Görevlendirme',
          'gezi_takip': 'Gezi Katılım & Onay Takibi',
        },
        'proje_gorev': {
          'proje_olustur': 'Proje Görevlendirmesi Oluşturma',
          'proje_takip': 'Proje İlerleme Takibi',
        },
      },
    ),

    'destek': SchoolTypeModuleInfo(
      key: 'destek',
      name: 'Destek Hizmetleri',
      icon: Icons.support_agent,
      color: Colors.cyan,
      description:
          'Yemekhane, servis, güvenlik kapı, sağlık (revir), kütüphane, temizlik, depo ve satın alma',
      subModules: {
        'yemekhane': 'Yemekhane İşlemleri',
        'servis': 'Servis İşlemleri',
        'guvenlik': 'Güvenlik Kapı & Misafir Giriş-Çıkış',
        'saglik': 'Sağlık İşlemleri (Revir)',
        'kutuphane': 'Kütüphane İşlemleri',
        'temizlik': 'Temizlik İşlemleri',
        'depo_satin_alma': 'Depo ve Stok Yönetimi',
        'satin_alma': 'Satın Alma ve Malzeme Talepleri',
        'envanter_takibi': 'Okul Envanteri',
      },
      nestedSubModules: {
        'yemekhane': {
          'st_yemekhane_menu': 'Aylık / Haftalık Yemek Menüsü Tanımlama',
          'st_yemekhane_ogun_takip': 'Öğün & Katılım Yoklaması',
        },
        'servis': {
          'st_servis_arac_guzergah': 'Araç, Şoför & Güzergah Tanımları',
          'st_servis_ogrenci_atama': 'Öğrenci Servis Atama & Biniş/İniş Yoklama',
        },
        'saglik': {
          'st_saglik_muayene': 'Revir Muayene & Müdahale Kaydı',
          'st_saglik_ilac': 'Öğrenci Alerji & İlaç Takibi',
        },
        'kutuphane': {
          'st_kutuphane_katalog': 'Kitap Kataloğu & Barkod Tanımlama',
          'st_kutuphane_odunc': 'Ödünç Verme & İade Takibi',
        },
        'temizlik': {
          'st_temizlik_gorev': 'Bölge & Personel Görev Çizelgesi',
          'st_temizlik_denetim': 'Günlük Temizlik Denetim & Onay',
        },
        'guvenlik': {
          'st_guvenlik_ziyaretci': 'Misafir Giriş-Çıkış Kaydı',
          'st_guvenlik_erken_teslim': 'Öğrenci Erken Teslim Onayı',
        },
        'depo_satin_alma': {
          'st_depo_stok_girisi': 'Depo Malzeme & Stok Girişi',
          'st_depo_teslim_et': 'Onaylı Talebi Teslim Etme & Stoktan Düşme',
          'st_depo_mal_kabul': 'Satın Alınan Malzemeyi Depoya Kabul Etme',
          'st_depo_hareketler': 'Stok Hareket Geçmişi',
        },
        'satin_alma': {
          'st_satinalma_talep': 'Malzeme Talebi Açma',
          'st_satinalma_amir_onay': '1. Amir Onayı Verme',
          'st_satinalma_ust_onay': 'Üst Yetkili Oluru & Teklif Onayı',
          'st_satinalma_teklif': 'Tedarikçi Tekliflerini Girme',
        },
        'envanter_takibi': {
          'st_envanter_goruntule': 'Okul Envanterini Görüntüleme',
          'st_envanter_duzenle': 'Envanter / Demirbaş Ekleme & Düzenleme',
        },
      },
    ),

    'raporlar': SchoolTypeModuleInfo(
      key: 'raporlar',
      name: 'Raporlar İşlemleri',
      icon: Icons.analytics_outlined,
      color: Colors.indigo,
      description: 'Yoklama, ödev, ölçme ve gelişim istatistik raporları',
      subModules: {
        'yoklama_raporlari': 'Yoklama Raporları',
        'yoklama_istatistik': 'Yoklama İstatistikleri',
        'odev_raporlari': 'Ödev Raporları',
        'olcme_raporlari': 'Ölçme Raporları',
        'gelisim_istatistik': 'Gelişim İstatistikleri',
      },
      nestedSubModules: {
        'yoklama_raporlari': {
          'st_rapor_yoklama_gunluk': 'Günlük & Tarih Aralıklı Devamsızlık',
          'st_rapor_yoklama_sinif': 'Sınıf & Öğrenci Bazlı Yoklama Dökümü',
        },
        'odev_raporlari': {
          'st_rapor_odev_teslim': 'Ödev Teslim & Başarı İstatistikleri',
        },
        'olcme_raporlari': {
          'st_rapor_olcme_genel': 'Kademe Geneli Sınav & Deneme Analizi',
        },
      },
    ),

    'haberlesme': SchoolTypeModuleInfo(
      key: 'haberlesme',
      name: 'İletişim Merkezi',
      icon: Icons.forum_rounded,
      color: Colors.deepPurple,
      description: 'Kademe duyuruları, sosyal medya akışı ve mesajlaşma',
      subModules: {
        'duyuru_islemleri': 'Duyuru İşlemleri',
        'sosyal_medya': 'Sosyal Medya / Akış',
        'mesajlar': 'Mesajlaşma (Chat)',
      },
      nestedSubModules: {
        'duyuru_islemleri': {
          'st_duyuru_oku': 'Görüntüleme › Duyuruları Görüntüleme',
          'st_duyuru_gelen_ara': 'Görüntüleme › Gelen Duyurularda Arama & Filtre',
          'st_duyuru_gonderilen':
              'Görüntüleme › Gönderilen Duyurular (Alıcı / Tarih / Tür Filtreli)',
          'st_duyuru_paylas': 'Oluşturma › Yeni Duyuru Oluşturma',
          'st_duyuru_hedef_kitle':
              'Oluşturma › Alıcı / Hedef Kitle Seçimi (Okul Türü, Sınıf, Şube, Kişi)',
          'st_duyuru_anonim':
              'Oluşturma › Anonim / Kurum Adıyla Paylaşım Seçimi',
          'st_duyuru_planli':
              'Oluşturma › Yayını İleri Tarihe Planlama & Hatırlatma',
          'st_duyuru_sms': 'Oluşturma › Duyuruyla Birlikte SMS Gönderme',
          'st_duyuru_ek_baglanti': 'Oluşturma › Dosya Eki & Bağlantı Ekleme',
          'st_duyuru_duzenle': 'Yönetim › Yayınlanmış Duyuruyu Düzenleme',
          'st_duyuru_sil': 'Yönetim › Duyuru Silme',
          'st_duyuru_onayla': 'Yönetim › Bekleyen Öğretmen Duyurularını Onaylama',
          'st_duyuru_ogretmen_ayar':
              'Yönetim › Öğretmen Duyuru İzni (Onaylı / Doğrudan / Kapalı) Ayarı',
        },
        'sosyal_medya': {
          'st_sosyal_goruntule': 'Akış › Akışı Görüntüleme & Beğenme',
          'st_sosyal_genel_akis': 'Akış › Genel Paylaşımlar (Tüm Kurum)',
          'st_sosyal_okul_turu_akis': 'Akış › Okul Türüne Özel Paylaşımlar',
          'st_sosyal_ara': 'Akış › Medya Paylaşımlarında Arama',
          'st_sosyal_paylas': 'Paylaşım › Etkinlik & Fotoğraf Gönderisi Paylaşma',
          'st_sosyal_medya_ekle':
              'Paylaşım › Görsel Galeri & YouTube Video Bağlantısı Ekleme',
          'st_sosyal_hedef_kitle':
              'Paylaşım › Hedef Kitle (Okul Türü, Sınıf, Kullanıcı Grubu) Seçimi',
          'st_sosyal_duzenle': 'Yönetim › Paylaşımı Düzenleme',
          'st_sosyal_sabitle': 'Yönetim › Gönderiyi Sabitleme / Sabitlemeyi Kaldırma',
          'st_sosyal_sil': 'Yönetim › Gönderiyi Silme',
        },
        'mesajlar': {
          'st_mesaj_birebir_grup': 'Sohbet › Birebir & Grup Mesajlaşma',
          'st_mesaj_yeni_sohbet': 'Sohbet › Yeni Sohbet Başlatma & Kişi Arama',
          'st_mesaj_grup_yonet': 'Sohbet › Grup Oluşturma & Üye Yönetimi',
          'st_mesaj_medya': 'Sohbet › Medya & Dosya Gönderme',
          'st_mesaj_veli_ogrenci': 'Sohbet › Veli & Öğrenciyle Mesajlaşma',
          'st_mesaj_toplu': 'Yönetim › Toplu Mesaj Gönderme (Çoklu Alıcı)',
          'st_mesaj_izle': 'Yönetim › Mesajları İzleme (Denetim)',
          'st_mesaj_yildizli_arsiv': 'Kişisel › Yıldızlı Mesajlar & Arşivlenmiş Sohbetler',
          'st_mesaj_gizlilik': 'Kişisel › Engelleme, Son Görülme & Duvar Kağıdı Ayarları',
        },
      },
    ),

    'ayarlar': SchoolTypeModuleInfo(
      key: 'ayarlar',
      name: 'Sistem Ayarları',
      icon: Icons.settings,
      color: Colors.blueGrey,
      description:
          'Yetki tanımlama, kullanıcı yetkilendirme ve kademe ayarları',
      subModules: {
        'yetki_tanimlama': 'Yetki Tanımlama',
        'kullanici_yetki': 'Kullanıcı Yetkilendirme',
        'uygulama_ayarlari': 'Uygulama Ayarları',
        'okul_bilgileri': 'Okul Genel Bilgileri',
      },
      nestedSubModules: {
        'yetki_tanimlama': {
          'st_rol_sablon_duzenle': 'Rol Şablonlarını Düzenleme',
          'st_ozel_rol_olustur': 'Yeni Özel Görev / Rol Tanımlama',
        },
        'kullanici_yetki': {
          'st_kullanici_yetki_ata': 'Kullanıcıya Özel Yetki Atama',
          'st_kullanici_ekle_duzenle': 'Kullanıcı Ekleme & Bilgi Düzenleme',
          'st_kullanici_sifre_durum': 'Şifre Değiştirme & Hesap Aktif / Pasif',
        },
        'uygulama_ayarlari': {
          'st_uyg_modul_ac_kapat': 'Kademe Modül & Alt Başlıklarını Açma / Kapatma',
          'st_uyg_gunluk_rapor_ayar': 'Günlük Rapor Kademe Ayarı',
        },
        'okul_bilgileri': {
          'st_okul_bilgi_duzenle': 'Okul Genel Bilgilerini Düzenleme',
        },
      },
    ),

    'kisisel': SchoolTypeModuleInfo(
      key: 'kisisel',
      name: 'Kişisel İşlemler',
      icon: Icons.person,
      color: Colors.pink,
      description: 'Bireysel notlar ve kişisel ajanda',
      subModules: {'notlarim': 'Notlarım', 'ajanda': 'Kişisel Ajanda'},
    ),

    'magaza': SchoolTypeModuleInfo(
      key: 'magaza',
      name: 'Mağaza & Online Satış',
      icon: Icons.storefront_rounded,
      color: Colors.deepOrange,
      description:
          'Genel Merkez ve kademe mağaza ürünleri, online alışveriş, zorunlu ürün, teslimat ve sipariş yönetimi',
      subModules: {
        'magaza_alisveris': 'Mağaza Vitrini & Online Alışveriş',
        'magaza_urun_yonetimi': 'Ürün & Stok Yönetimi',
        'magaza_siparis_yonetimi': 'Sipariş & Teslimat Yönetimi',
        'magaza_ayarlari': 'Mağaza & Sanal POS Ayarları',
      },
      nestedSubModules: {
        'magaza_alisveris': {
          'st_magaza_vitrin_satin_al':
              'Mağaza Vitrini Görüntüleme & Online Alışveriş',
          'st_magaza_siparislerim': 'Siparişlerim & Teslimat Takibi',
        },
        'magaza_urun_yonetimi': {
          'st_magaza_urun_ekle_duzenle':
              'Ürün Ekleme, Fiyat, Varyant & Görsel Yönetimi',
          'st_magaza_hedef_kitle':
              'Sınıf Seviyesi, Şube, Okul Türü & Rol Hedefleme',
          'st_magaza_teslimat_zorunlu':
              'Okuldan Teslim / Adrese Kargo & Zorunlu Ürün Ayarı',
          'st_magaza_urun_sil': 'Ürün Silme & Yayından Kaldırma',
        },
        'magaza_siparis_yonetimi': {
          'st_magaza_siparis_onay': 'Sipariş Onaylama & Hazırlama',
          'st_magaza_kargo_teslim': 'Kargo & Okuldan Teslim Durumu Güncelleme',
          'st_magaza_siparis_iptal': 'Sipariş İptal & İade İşlemi',
          'st_magaza_ciro_rapor': 'Mağaza Ciro & Satış Raporları',
        },
        'magaza_ayarlari': {
          'st_magaza_genel_ayar': 'Mağaza Açma/Kapama & Kargo Limiti Ayarı',
          'st_magaza_pos_ayar': 'Mağaza Sanal POS Yapılandırması',
        },
      },
    ),

    'kantin': SchoolTypeModuleInfo(
      key: 'kantin',
      name: 'Kantin Yönetimi',
      icon: Icons.restaurant_rounded,
      color: Colors.pink,
      description:
          'Okul kantini: kartlı/QR/POS/nakit satış, kart tanımlama, bakiye, stok, muhasebe, rapor ve veli kontrolü',
      subModules: {
        'kantin_satis': 'Kantin Satış (POS)',
        'kantin_kart': 'Kart & QR Tanımlama',
        'kantin_bakiye': 'Bakiye & Kart Hareketleri',
        'kantin_stok': 'Ürün, Stok & Depo Yönetimi',
        'kantin_muhasebe': 'Kantin Muhasebe & Kasa',
        'kantin_rapor': 'Kantin Raporları & Analiz',
        'kantin_veli': 'Veli / Öğrenci Kantin Cüzdanı',
      },
      nestedSubModules: {
        'kantin_satis': {
          'st_kantin_satis_kart': 'Kantin Kartı (Cüzdan) ile Satış Yapma',
          'st_kantin_satis_qr': 'Mobil QR Karekod Üretme & Tahsilat',
          'st_kantin_satis_pos': 'Banka / Kredi Kartı (POS) ile Satış Yapma',
          'st_kantin_satis_nakit': 'Nakit Satış Yapma',
          'st_kantin_satis_iade':
              'Alışveriş / Ürün-Parça İade ve Bakiye Geri Aktarım Yetkisi',
          'st_kantin_pos_ayarlari': 'Kantin Sanal POS Ayarlarını Yapılandırma',
        },
        'kantin_kart': {
          'st_kantin_kart_tanimla': 'Yeni Öğrenci / Personel Kartı Tanımlama',
          'st_kantin_kart_durum': 'Kart Aktif / Pasif (Bloke) Durumu Değiştirme',
          'st_kantin_kart_limit_kisit':
              'Günlük Harcama Limiti & Ürün/Kategori Kısıtlama',
          'st_kantin_kart_sil': 'Kantin Kartı Silme',
        },
        'kantin_bakiye': {
          'st_kantin_bakiye_yukle': 'Nakit / POS ile Bakiye Yükleme',
          'st_kantin_kart_hareket_iade':
              'Kart Hareketleri Üzerinden Tam veya Parça Parça Ürün İadesi & Bakiye Geri Aktarma',
          'st_kantin_bakiye_duzelt': 'Bakiye İade & Düzeltme İşlemi',
          'st_kantin_kart_hareketleri':
              'Kartın Tüm Hareketlerini Görüntüleme & Arama',
        },
        'kantin_stok': {
          'st_kantin_urun_ekle_duzenle':
              'Kantin Ürünü Ekleme, Fiyat, Barkod & Görsel Düzenleme',
          'st_kantin_urun_sil': 'Kantin Ürünü Silme / Satışa Kapatma',
          'st_kantin_stok_giris_cikis':
              'Stok Giriş / Çıkış, Fire & Sayım Düzeltme',
          'st_kantin_depo_yonetimi': 'Kantin Depoları Tanımlama & Yönetme',
        },
        'kantin_muhasebe': {
          'st_kantin_gelir_gider': 'Kantin Gelir & Gider Kaydı İşleme',
          'st_kantin_kasa_izle': 'Kantin Kasa, Ciro & Net Bakiye İzleme',
          'st_kantin_muhasebe_sil': 'Muhasebe Kaydı Düzenleme & Silme',
        },
        'kantin_rapor': {
          'st_kantin_rapor_ciro': 'Günlük & Tarih Aralıklı Ciro Analizi',
          'st_kantin_rapor_urun':
              'En Çok Satan Ürünler & Ödeme Yöntemi Dağılımı',
        },
        'kantin_veli': {
          'st_kantin_veli_yukle_qr':
              'Online Bakiye Yükleme & Mobil QR ile Ödeme',
          'st_kantin_veli_limit_kisit':
              'Öğrenci Günlük Limit & Ürün/Kategori Kısıtlama',
        },
      },
    ),
  };

  /// Tüm modüllerin key'lerini liste olarak döner
  static List<String> get allModuleKeys => modules.keys.toList();

  /// Modül ismini key'den döner
  static String getModuleName(String key) {
    return modules[key]?.name ?? key;
  }

  /// Modül bilgisini döner
  static SchoolTypeModuleInfo? getModule(String key) {
    return modules[key];
  }
}

/// Okul türü modülü bilgisi sınıfı (3 Seviye Hiyerarşi destekli)
class SchoolTypeModuleInfo {
  final String key;
  final String name;
  final IconData icon;
  final Color color;
  final String description;
  final Map<String, String> subModules;
  final Map<String, Map<String, String>> nestedSubModules;

  const SchoolTypeModuleInfo({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
    this.subModules = const {},
    this.nestedSubModules = const {},
  });

  Map<String, String> childrenOf(String subModuleKey) =>
      nestedSubModules[subModuleKey] ?? const {};

  Map<String, String> get allSubAndNestedModules {
    final out = <String, String>{...subModules};
    for (final entry in nestedSubModules.entries) {
      out.addAll(entry.value);
    }
    return out;
  }
}
