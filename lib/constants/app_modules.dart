import 'package:flutter/material.dart';

/// Uygulama genelinde kullanılacak kurum ana modülleri (3 seviyeli hiyerarşi destekli:
/// Modül -> Alt Başlık -> Alt Başlığın Altı)
class AppModules {
  static final Map<String, ModuleInfo> modules = {
    // 1. EĞİTİM
    'egitim': ModuleInfo(
      key: 'egitim',
      name: 'Eğitim',
      icon: Icons.school_outlined,
      color: Colors.indigo,
      category: 'Akademik',
      description:
          'Ön kayıt, öğrenci kaydı, günlük karne, hareket takibi ve okul türleri yönetimi',
      subModules: {
        'on_kayit': 'Ön Kayıt',
        'ogrenci_kaydi': 'Öğrenci Kaydı',
        'okul_turleri': 'Okul Türleri',
        'gunluk_rapor': 'Günlük Rapor (Günlük Karne)',
        'ogrenci_hareket_takip': 'Geç - İzin - Erken - Revir - Görüşme Merkezi',
        'sinif_atlatma': 'Sınıf Atlatma İşlemleri',
        'nakil_islemleri': 'Nakil İşlemleri',
      },
      nestedSubModules: {
        'on_kayit': {
          'on_kayit_olustur': 'Yeni Ön Kayıt & Görüşme Ekleme',
          'on_kayit_kesinlestir': 'Kesin Kayda Aktarma',
          'on_kayit_rapor': 'Ön Kayıt İstatistik & Silme',
        },
        'ogrenci_kaydi': {
          'ogrenci_yeni_kayit': 'Yeni Öğrenci Kaydı & Düzenleme',
          'ogrenci_toplu_excel': 'Excel ile Toplu Öğrenci Yükleme',
          'ogrenci_silme_pasif': 'Kayıt Silme / Pasife Alma',
        },
        'okul_turleri': {
          'okul_turu_tanim': 'Okul Türü Ekleme & Düzenleme',
          'donem_yonetimi': 'Eğitim Dönemi Yönetimi',
        },
        'gunluk_rapor': {
          'gunluk_rapor_beslenme': 'Beslenme Takibi (Kahvaltı, Öğle, İkindi)',
          'gunluk_rapor_su': 'Su Tüketimi Takibi',
          'gunluk_rapor_uyku': 'Uyku & Dinlenme Saati',
          'gunluk_rapor_duygu': 'Duygu Durumu & Arkadaş Uyumu',
          'gunluk_rapor_etkinlik': 'Etkinlik, Kitap, Gezi & Branş Ders Akışı',
          'gunluk_rapor_ozbakim': 'Özbakım & Hijyen Takibi',
          'gunluk_rapor_saglik': 'Sağlık & İlaç Gözlem Notu',
          'gunluk_rapor_veli_geri_bildirim':
              'Veli Emoji Tepkisi & Teşekkür Notu',
        },
        'ogrenci_hareket_takip': {
          'hareket_gec_kalan': 'Geç Kalan Öğrenci Girişi',
          'hareket_izin_erken': 'İzin / Erken Çıkış & Veli Teslim',
          'hareket_revir_sevk': 'Revir Sevk & Takip',
          'hareket_canli_izleme': 'Canlı Hareket İzleme Ekranı',
        },
        'sinif_atlatma': {
          'sinif_atlatma_toplu': 'Toplu Sınıf & Şube Atlatma İşlemi',
          'sinif_atlatma_mezun': 'Mezuniyet & Dönem Sonu Aktarımı',
          'sinif_atlatma_bos_sube_temizle':
              'Mükerrer / Boş Şubeleri Birleştirme & Temizleme',
        },
        'nakil_islemleri': {
          'nakil_kademe_aktarim': 'Okul Türleri Arası Nakil & Şube Atama',
          'nakil_dis_kurum': 'Kurum Dışı Nakil Giden / Gelen Kaydı',
        },
      },
    ),

    // 2. REHBERLİK
    'rehberlik': ModuleInfo(
      key: 'rehberlik',
      name: 'Rehberlik İşlemleri',
      icon: Icons.psychology_outlined,
      color: Colors.deepOrange,
      category: 'Rehberlik',
      description: 'Portfolyo, talepler, görüşmeler ve rehberlik envanterleri',
      subModules: {
        'ogrenci_portfolyosu': 'Öğrenci Portfolyosu',
        'talepler': 'Talepler (Yönlendirmeler)',
        'gorusme_kayitlari': 'Görüşme Kayıtları',
        'rehberlik_testleri': 'Rehberlik Testleri & Envanterler',
        'gelisim_raporlari': '360 Gelişim Raporları',
      },
      nestedSubModules: {
        'ogrenci_portfolyosu': {
          'portfolyo_genel_bilgiler': 'Genel Bilgiler Sekmesi',
          'portfolyo_deneme_sinavlari': 'Deneme Sınavları Sekmesi',
          'portfolyo_yazili_sinavlar': 'Yazılı Sınavlar Sekmesi',
          'portfolyo_odevler': 'Ödevler Sekmesi',
          'portfolyo_devamsizlik': 'Devamsızlık Sekmesi',
          'portfolyo_eylem_planlari': 'Eylem Planları Sekmesi',
          'portfolyo_etutler': 'Etütler Sekmesi',
          'portfolyo_kitaplar': 'Kitaplar Sekmesi',
          'portfolyo_gorusmeler': 'Görüşmeler Sekmesi',
          'portfolyo_talepler': 'Talepler Sekmesi',
          'portfolyo_gelisim_raporu': 'Gelişim Raporu Sekmesi',
          'portfolyo_mentor_calismalari': 'Mentör Çalışmaları Sekmesi',
          'portfolyo_rehberlik_testleri': 'Rehberlik Testleri Sekmesi',
          'portfolyo_etkinlik_raporlari': 'Etkinlik Raporları Sekmesi',
        },
        'talepler': {
          'talep_olustur': 'Yeni Yönlendirme / Talep Açma',
          'talep_yonet': 'Talep Atama & Sonuçlandırma',
          'talep_analiz': 'Kurum Geneli Rehberlik Analizi',
        },
        'gorusme_kayitlari': {
          'gorusme_goruntule': 'Görüşme Geçmişi Görüntüleme',
          'gorusme_ekle': 'Yeni Görüşme Kaydı Oluşturma',
        },
        'rehberlik_testleri': {
          'test_atama_uygulama': 'Envanter Atama & Uygulama',
          'test_sonuc_analiz': 'Envanter Sonuç & Analiz Raporları',
        },
        'gelisim_raporlari': {
          'gelisim_360_goruntule': '360° Gelişim Raporlarını Görüntüleme',
          'gelisim_360_degerlendir': 'Gelişim Ölçeklerini Doldurma & Yayınlama',
        },
      },
    ),

    // 3. İNSAN KAYNAKLARI
    'insan_kaynaklari': ModuleInfo(
      key: 'insan_kaynaklari',
      name: 'İnsan Kaynakları',
      icon: Icons.group_outlined,
      color: Colors.purple,
      category: 'Kurumsal',
      description: 'Personel, devam/izin, maaş, bordro ve performans yönetimi',
      subModules: {
        'personel_bilgi': 'Personel Bilgi Yönetimi',
        'devam_mesai_izin': 'Devam – Mesai – İzin',
        'maas_bordro': 'Maaş ve Bordro',
        'performans_yonetimi': 'Performans Yönetimi',
        'egitim_gelisim': 'Eğitim ve Gelişim',
        'sozlesme_evrak': 'Sözleşme ve Evrak',
        'ik_raporlama': 'İK Raporlama',
      },
      nestedSubModules: {
        'personel_bilgi': {
          'personel_ekle_duzenle': 'Personel Kaydı Açma & Özlük Düzenleme',
          'personel_zimmet_evrak': 'Zimmet & Özlük Dosyası Yönetimi',
          'personel_ayrilis': 'İşten Ayrılış / Pasife Alma',
        },
        'devam_mesai_izin': {
          'ik_qr_puantaj': 'QR Giriş-Çıkış & Puantaj Takibi',
          'ik_izin_onay': 'İzin Talepleri & Onay Yönetimi',
          'ik_ek_ders_mesai': 'Fazla Mesai & Ek Ders Hesaplama',
        },
        'maas_bordro': {
          'ik_maas_tanim': 'Maaş & Ücret Parametreleri',
          'ik_bordro_tahakkuk': 'Aylık Bordro & Avans Ödemeleri',
        },
        'performans_yonetimi': {
          'ik_performans_donem': 'Performans Dönemi & Kriter Tanımlama',
          'ik_performans_degerlendir': 'Personel Performans Değerlendirmesi',
        },
        'egitim_gelisim': {
          'ik_hizmetici_egitim': 'Hizmet İçi Eğitim & Seminer Planlama',
          'ik_sertifika_takip': 'Sertifika & Katılım Takibi',
        },
        'sozlesme_evrak': {
          'ik_sozlesme_yenile': 'İş Sözleşmesi Hazırlama & Yenileme',
          'ik_evrak_arsiv': 'Resmi İK Evrak Arşivi Yönetimi',
        },
        'ik_raporlama': {
          'ik_maliyet_rapor': 'Personel Maliyet & Bordro İcmalleri',
          'ik_devam_analiz': 'Devam, İzin & Devir Hızı Analizleri',
        },
      },
    ),

    // 4. ÖLÇME DEĞERLENDİRME
    'olcme_degerlendirme': ModuleInfo(
      key: 'olcme_degerlendirme',
      name: 'Ölçme Değerlendirme',
      icon: Icons.assignment_turned_in_outlined,
      color: Colors.teal,
      category: 'Ölçme',
      description:
          'Sınav, rapor, deneme, AGM, hata kitapçığı, Fokus Kitap ve soru havuzu',
      subModules: {
        'tanimlar': 'Tanımlar',
        'raporlar': 'Raporlar',
        'denemeler': 'Denemeler',
        'sinavlar': 'Sınavlar',
        'hata_kitapcigi': 'Hata Kitapçığı',
        'fokus_kitap': 'Fokus Kitap (Kişiye Özel Soru Bankası)',
        'soru_havuzu': 'Soru Havuzu',
        'dis_katilimli_sinav': 'Dış Katılımlı Sınav',
        'merkezi_deneme_raporlari': 'Genel Merkez Deneme Raporları',
      },
      nestedSubModules: {
        'tanimlar': {
          'olcme_optik_tanim': 'Optik Form Tanımları',
          'olcme_puan_katsayi': 'Puanlama & Katsayı Formülleri',
          'olcme_kazanim_agaci': 'Ders & Kazanım Ağacı Tanımları',
        },
        'fokus_kitap': {
          'fokus_kitap_olustur': 'Kazanım Bazlı Kişiye Özel Kitap Üretme',
          'fokus_kitap_kapak_ayar': 'Kapak, Ön Söz & İçindekiler Tasarımı',
          'fokus_kitap_toplu_indir': 'Toplu PDF / ZIP İndirme',
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
          'deneme_olustur': 'Deneme Sınavı Açma & Cevap Anahtarı',
          'deneme_optik_okuma': 'Optik Veri Yükleme & Değerlendirme',
          'deneme_yayinla_sil': 'Sonuç Yayınlama & Silme',
        },
        'sinavlar': {
          'yazili_sinav_tanim': 'Yazılı / Aktif Sınav Oluşturma',
          'yazili_not_girisi': 'Not Girişi & Düzenleme',
        },
        'hata_kitapcigi': {
          'hata_kitapcigi_uret': 'Öğrenciye Özel Hata Kitapçığı Üretme',
          'hata_kitapcigi_arsiv': 'Basım & Teslim Takibi',
        },
        'soru_havuzu': {
          'soru_ekle_duzenle': 'Soru Ekleme & Düzenleme',
          'soru_test_uret': 'Yaprak Test / Sınav Kağıdı Oluşturma',
        },
        'dis_katilimli_sinav': {
          'dis_sinav_basvuru': 'Başvuru Formu & Seans Yönetimi',
          'dis_sinav_yoklama': 'Giriş Belgesi & Sınav Yoklaması',
        },
        'merkezi_deneme_raporlari': {
          'merkezi_deneme_optik_yukle':
              'Genel Merkez Denemesi Optik Veri Gönderme',
          'merkezi_deneme_analiz_goruntule':
              'Türkiye & Kurum Geneli Karşılaştırmalı Raporlar',
          'merkezi_deneme_karne_indir':
              'Merkezi Deneme Öğrenci Karnesi & Excel Döküm',
        },
      },
    ),

    // 5. MALİ İŞLER
    'mali_isler': ModuleInfo(
      key: 'mali_isler',
      name: 'Mali İşler',
      icon: Icons.account_balance_wallet_outlined,
      color: Colors.blue,
      category: 'Finans',
      description:
          'Öğrenci taksitleri, kasa, geciken ödemeler, sanal POS ve finansal raporlar',
      subModules: {
        'genel_finans_ozeti': 'Genel Finans Özeti',
        'ogrenci_taksit_takibi': 'Öğrenci Taksit Takibi',
        'geciken_taksitler': 'Geciken Taksitler',
        'kasa_hareketler': 'Kasa & Hareketler',
        'sanal_pos_ayarlari': 'Sanal POS Yapılandırması',
      },
      nestedSubModules: {
        'genel_finans_ozeti': {
          'mali_ciro_tahsilat_ozet': 'Toplam Ciro, Tahsilat & Bekleyen Alacak',
          'mali_nakit_akis_grafik': 'Aylık Nakit Akışı & Karşılaştırma Analizi',
        },
        'ogrenci_taksit_takibi': {
          'mali_sozlesme_taksit': 'Öğrenci Kayıt Sözleşmesi & Taksit Planı',
          'mali_tahsilat_makbuz': 'Tahsilat Alma & Makbuz Kesme',
          'mali_indirim_iptal': 'İndirim, İade & Plan Yenileme',
        },
        'geciken_taksitler': {
          'mali_odeme_hatirlatma': 'Veli Ödeme Hatırlatma & Takip Notu',
          'mali_gecikme_raporu': 'Vadesi Geçen Alacak Listesi & Dışa Aktarım',
        },
        'kasa_hareketler': {
          'mali_gelir_girisi': 'Gelir İşleme',
          'mali_gider_girisi': 'Gider & Fatura İşleme',
          'mali_kasa_dokum': 'Kasa / Banka Dökümü & Raporlama',
        },
        'sanal_pos_ayarlari': {
          'mali_kurum_ana_pos': 'Kurum Ana Sanal POS Tanımlama (Iyzico/PayTR)',
          'mali_magaza_pos_ayar': 'Okul Mağazası Özel Sanal POS Tanımlama',
          'mali_kantin_pos_ayar': 'Kantin Özel Sanal POS Tanımlama',
        },
      },
    ),

    // 6. HİZMETLER
    'hizmetler': ModuleInfo(
      key: 'hizmetler',
      name: 'Hizmetler',
      icon: Icons.support_agent_outlined,
      color: Colors.orange,
      category: 'Operasyon',
      description:
          'Sağlık (Revir), Güvenlik Kapı, Yemekhane, Servis, Depo ve Satın Alma',
      subModules: {
        'saglik_islemleri': 'Sağlık İşlemleri (Revir)',
        'guvenlik_kapi': 'Güvenlik Kapı & Misafir Giriş-Çıkış',
        'yemekhane_islemleri': 'Yemekhane İşlemleri',
        'servis_islemleri': 'Servis İşlemleri',
        'kutuphane_islemleri': 'Kütüphane İşlemleri',
        'temizlik_islemleri': 'Temizlik İşlemleri',
        'depo_satin_alma': 'Depo Yönetimi ve Stok Takibi',
        'satin_alma_islemleri': 'Satın Alma ve Teklif Yönetimi',
      },
      nestedSubModules: {
        'saglik_islemleri': {
          'saglik_muayene_kayit': 'Revir Muayene & Müdahale Kaydı',
          'saglik_kronik_ilac': 'Kronik Rahatsızlık, Alerji & İlaç Takibi',
          'saglik_veli_bilgi': 'Veli Sağlık Bilgilendirmesi',
        },
        'guvenlik_kapi': {
          'guvenlik_ziyaretci_kayit': 'Misafir / Ziyaretçi Giriş-Çıkış Kaydı',
          'guvenlik_erken_teslim': 'Öğrenci Erken Alma & Veli Teslim Onayı',
        },
        'yemekhane_islemleri': {
          'yemekhane_menu_plan': 'Aylık / Haftalık Yemek Menüsü Tanımlama',
          'yemekhane_ogun_takip': 'Öğün & Katılım Yoklaması',
        },
        'servis_islemleri': {
          'servis_arac_guzergah': 'Araç, Şoför, Hostes & Güzergah Tanımları',
          'servis_ogrenci_atama': 'Öğrenci Servis Atama & Biniş/İniş Yoklama',
        },
        'kutuphane_islemleri': {
          'kutuphane_demirbas': 'Kitap Kataloğu & Barkod Tanımlama',
          'kutuphane_odunc_iade': 'Ödünç Verme & İade Takibi',
        },
        'temizlik_islemleri': {
          'temizlik_alan_gorev': 'Bölge & Personel Görev Çizelgesi',
          'temizlik_gunluk_onay': 'Günlük Temizlik Denetim & Onay',
        },
        'depo_satin_alma': {
          'depo_stok_tanim': 'Depo & Malzeme Stok Girişi',
          'depo_teslimat': 'Talep Malzeme Teslimi & Stoktan Düşüm',
          'depo_mal_kabul': 'Satın Alınan Ürün Mal Kabul Onayı',
          'depo_hareket_gecmisi': 'Stok Hareket Geçmişi İzleme',
          'depo_ayarlar': 'Depo Tanımları & Onay Yetkilisi Ayarları',
        },
        'satin_alma_islemleri': {
          'satinalma_talep_ac': 'Malzeme Talebi Oluşturma',
          'satinalma_amir_onay': '1. Kademe Amir Onayı Verme',
          'satinalma_ust_onay': '2. Kademe Üst Yetkili Satın Alma Oluru',
          'satinalma_teklif_gir': 'Tedarikçi Tekliflerini Sisteme Girme',
          'satinalma_teklif_onay': 'Kazanan Teklif Seçimi & Alım Onayı',
        },
      },
    ),

    // 7. HABERLEŞME
    'haberlesme': ModuleInfo(
      key: 'haberlesme',
      name: 'Haberleşme Merkezi',
      icon: Icons.campaign_outlined,
      color: Colors.deepPurple,
      category: 'Kurumsal',
      description: 'Duyurular, sosyal medya akışı ve kurum içi mesajlaşma',
      subModules: {
        'genel_duyurular': 'Duyurular',
        'sosyal_medya': 'Sosyal Medya / Okul Akışı',
        'mesajlar': 'Mesajlaşma (Chat)',
      },
      nestedSubModules: {
        'genel_duyurular': {
          'duyuru_goruntule': 'Görüntüleme › Duyuruları Görüntüleme',
          'duyuru_gelen_ara': 'Görüntüleme › Gelen Duyurularda Arama & Filtre',
          'duyuru_gonderilen':
              'Görüntüleme › Gönderilen Duyurular (Alıcı / Tarih / Tür Filtreli)',
          'duyuru_olustur': 'Oluşturma › Yeni Duyuru Oluşturma',
          'duyuru_hedef_kitle':
              'Oluşturma › Alıcı / Hedef Kitle Seçimi (Okul Türü, Sınıf, Şube, Kişi)',
          'duyuru_anonim': 'Oluşturma › Anonim / Kurum Adıyla Paylaşım Seçimi',
          'duyuru_planli': 'Oluşturma › Yayını İleri Tarihe Planlama & Hatırlatma',
          'duyuru_sms': 'Oluşturma › Duyuruyla Birlikte SMS Gönderme',
          'duyuru_ek_baglanti': 'Oluşturma › Dosya Eki & Bağlantı Ekleme',
          'duyuru_duzenle': 'Yönetim › Yayınlanmış Duyuruyu Düzenleme',
          'duyuru_sil': 'Yönetim › Duyuru Silme',
          'duyuru_onayla_yayinla':
              'Yönetim › Öğretmen Duyurularını Onaylama / Silme',
          'duyuru_ogretmen_ayar':
              'Yönetim › Öğretmen Duyuru İzni (Onaylı / Doğrudan / Kapalı) Ayarı',
        },
        'sosyal_medya': {
          'sosyal_akis_izle': 'Akış › Akış Görüntüleme & Etkileşim',
          'sosyal_genel_akis': 'Akış › Genel Paylaşımlar (Tüm Kurum)',
          'sosyal_okul_turu_akis': 'Akış › Okul Türüne Özel Paylaşımlar',
          'sosyal_ara': 'Akış › Medya Paylaşımlarında Arama',
          'sosyal_gonderi_paylas':
              'Paylaşım › Fotoğraf / Etkinlik Gönderisi Paylaşma',
          'sosyal_medya_ekle':
              'Paylaşım › Görsel Galeri & YouTube Video Bağlantısı Ekleme',
          'sosyal_hedef_kitle':
              'Paylaşım › Hedef Kitle (Okul Türü, Sınıf, Kullanıcı Grubu) Seçimi',
          'sosyal_duzenle': 'Yönetim › Paylaşımı Düzenleme',
          'sosyal_sabitle': 'Yönetim › Gönderiyi Sabitleme / Sabitlemeyi Kaldırma',
          'sosyal_sil': 'Yönetim › Gönderiyi Silme',
        },
        'mesajlar': {
          'mesaj_birebir': 'Sohbet › Birebir Mesajlaşma',
          'mesaj_yeni_sohbet': 'Sohbet › Yeni Sohbet Başlatma & Kişi Arama',
          'mesaj_grup_yonet': 'Sohbet › Grup Sohbeti Oluşturma & Üye Yönetimi',
          'mesaj_medya': 'Sohbet › Medya & Dosya Gönderme',
          'mesaj_veli_ogrenci': 'Sohbet › Veli & Öğrenciyle Mesajlaşma',
          'mesaj_toplu': 'Yönetim › Toplu Mesaj Gönderme (Çoklu Alıcı)',
          'mesaj_izle': 'Yönetim › Mesajları İzleme (Denetim)',
          'mesaj_yildizli_arsiv':
              'Kişisel › Yıldızlı Mesajlar & Arşivlenmiş Sohbetler',
          'mesaj_gizlilik':
              'Kişisel › Engelleme, Son Görülme & Duvar Kağıdı Ayarları',
        },
      },
    ),

    // 8. ONLİNE HİZMETLER (LinGoKN)
    'online_hizmetler': ModuleInfo(
      key: 'online_hizmetler',
      name: 'Online Hizmetler (LinGoKN)',
      icon: Icons.translate_rounded,
      color: Colors.teal,
      category: 'Operasyon',
      description:
          'LinGoKN dil platformu geçişi ve sınıf bazlı erişim izinleri',
      subModules: {
        'lingokn_portal': 'LinGoKN Portalına Geçiş',
        'lingokn_izin_yonetimi': 'LinGoKN Erişim & İzin Yönetimi',
      },
      nestedSubModules: {
        'lingokn_portal': {
          'lingokn_sso_gecis': 'LinGoKN Platformuna Tek Tıkla (SSO) Geçiş',
          'lingokn_rapor_izleme': 'Dil Gelişim & Aktivite Raporlarını İzleme',
        },
        'lingokn_izin_yonetimi': {
          'lingokn_sinif_erisim': 'Sınıf & Şube Bazlı Erişim Yetkisi Açma',
          'lingokn_ogrenci_lisans': 'Öğrenci & Öğretmen Lisans Tanımlama',
        },
      },
    ),

    // 9. MAĞAZA & ONLİNE SATIŞ
    'magaza': ModuleInfo(
      key: 'magaza',
      name: 'Mağaza & Online Satış',
      icon: Icons.storefront_rounded,
      color: Colors.deepOrange,
      category: 'Mağaza',
      description:
          'Genel Merkez ve okul mağazası ürünleri, online kartlı alışveriş, zorunlu ürün, teslimat ve sipariş takibi',
      subModules: {
        'magaza_alisveris': 'Mağaza Vitrini & Online Alışveriş',
        'magaza_urun_yonetimi': 'Okul Ürün & Stok Yönetimi',
        'magaza_siparis_yonetimi': 'Sipariş & Teslimat Yönetimi',
        'magaza_ayarlari': 'Mağaza & Sanal POS Ayarları',
      },
      nestedSubModules: {
        'magaza_alisveris': {
          'magaza_vitrin_goruntule': 'Mağaza Vitrinini & Ürünleri Görüntüleme',
          'magaza_online_satin_al':
              'Sepet Oluşturma & Online Kartla Sipariş Verme',
          'magaza_siparislerim_takip': 'Siparişlerim & Teslimat Durumu Takibi',
        },
        'magaza_urun_yonetimi': {
          'magaza_urun_ekle_duzenle':
              'Okula Özel Ürün Ekleme, Fiyat & Görsel Yönetimi',
          'magaza_stok_takip': 'Stok & Varyant (Beden/Seviye/Paket) Yönetimi',
          'magaza_hedef_kitle_secimi':
              'Hedef Kitle (Okul Türü, Sınıf Seviyesi, Şube & Rol) Belirleme',
          'magaza_teslimat_zorunlu_ayar':
              'Okuldan Teslim / Adrese Kargo & İlk Alışverişte Zorunlu Ürün Ayarı',
          'magaza_urun_sil_pasif': 'Ürün Silme & Satışa Açma / Kapatma',
        },
        'magaza_siparis_yonetimi': {
          'magaza_siparis_onay': 'Gelen Siparişleri Onaylama & Hazırlama',
          'magaza_teslimat_takip':
              'Okuldan Teslim & Adrese Kargo Durumu Güncelleme',
          'magaza_siparis_iptal_iade':
              'Sipariş İptali & Stok/Ödeme İadesi İşleme',
          'magaza_ciro_rapor': 'Mağaza Ciro, Tahsilat & Satış Analitiği İzleme',
        },
        'magaza_ayarlari': {
          'magaza_genel_yapilandirma':
              'Okul Mağazası Açma/Kapama, Kargo Ücreti & Duyuru Bandı Ayarı',
          'magaza_sanal_pos_tanimlama':
              'Okul Mağazası Özel Sanal POS Yapılandırması',
        },
      },
    ),

    // KANTİN
    'kantin': ModuleInfo(
      key: 'kantin',
      name: 'Kantin Yönetimi',
      icon: Icons.restaurant_rounded,
      color: Colors.pink,
      category: 'Kantin',
      description:
          'Okul kantini: kartlı/QR/POS/nakit satış, kart tanımlama, bakiye yükleme, stok, muhasebe ve raporlar',
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
          'kantin_satis_kart': 'Kantin Kartı (Cüzdan) ile Satış Yapma',
          'kantin_satis_qr': 'Mobil QR Karekod Üretme & Tahsilat',
          'kantin_satis_pos': 'Banka / Kredi Kartı (POS) ile Satış Yapma',
          'kantin_satis_nakit': 'Nakit Satış Yapma',
          'kantin_satis_iptal_iade':
              'Alışveriş / Ürün-Parça İade ve Bakiye Geri Aktarım Yetkisi',
          'kantin_pos_ayarlari': 'Kantin Sanal POS Ayarlarını Yapılandırma',
        },
        'kantin_kart': {
          'kantin_kart_tanimla':
              'Yeni Öğrenci / Personel Kartı Tanımlama & Eşleştirme',
          'kantin_kart_duzenle_durum':
              'Kart Bilgisi Düzenleme & Aktif / Pasif (Bloke) Yapma',
          'kantin_kart_limit_kisit':
              'Günlük Harcama Limiti & Kategori / Ürün Kısıtlama',
          'kantin_kart_sil': 'Kantin Kartı Silme',
        },
        'kantin_bakiye': {
          'kantin_bakiye_yukle':
              'Nakit veya Kredi/Banka Kartı (POS) ile Bakiye Yükleme',
          'kantin_kart_hareket_iade':
              'Kart Hareketleri Üzerinden Tam veya Parça Parça Ürün İadesi & Bakiye Geri Aktarma',
          'kantin_bakiye_iade_duzelt': 'Bakiye İade & Düzeltme İşlemi',
          'kantin_kart_hareketleri_tumu':
              'Seçili Kartın Tüm Hareketlerini Görüntüleme & Arama',
        },
        'kantin_stok': {
          'kantin_urun_ekle_duzenle':
              'Kantin Ürünü Ekleme, Fiyat, Barkod & Görsel Düzenleme',
          'kantin_urun_sil_pasif': 'Kantin Ürünü Silme / Satışa Kapatma',
          'kantin_stok_giris_cikis':
              'Stok Giriş / Çıkış, Fire & Sayım Düzeltme',
          'kantin_depo_yonetimi': 'Kantin Depoları Tanımlama & Yönetme',
        },
        'kantin_muhasebe': {
          'kantin_gelir_gider_ekle': 'Kantin Gelir & Gider Kaydı İşleme',
          'kantin_kasa_net_bakiye': 'Kantin Kasa, Ciro & Net Bakiye İzleme',
          'kantin_muhasebe_duzenle_sil': 'Muhasebe Kaydı Düzenleme & Silme',
        },
        'kantin_rapor': {
          'kantin_rapor_gunluk_ciro':
              'Günlük & Tarih Aralıklı Satış / Ciro Analizi',
          'kantin_rapor_urun_odeme':
              'En Çok Satan Ürünler & Ödeme Yöntemi Dağılımı',
          'kantin_rapor_disa_aktar': 'Kantin Raporlarını Dışa Aktarma',
        },
        'kantin_veli': {
          'kantin_veli_bakiye_yukle':
              'Online Kart ile Cüzdana Bakiye Yükleme & QR Ödeme',
          'kantin_veli_limit_kisit':
              'Öğrenci Günlük Harcama Limiti & Ürün/Kategori Kısıtlama',
          'kantin_veli_harcama_takip':
              'Kart Hareketlerini & Tüm Harcama Geçmişini İnceleme',
        },
      },
    ),

    // 10. SİSTEM AYARLARI
    'sistem_ayarlari': ModuleInfo(
      key: 'sistem_ayarlari',
      name: 'Sistem Ayarları',
      icon: Icons.settings_outlined,
      color: Colors.blueGrey,
      category: 'Sistem',
      description:
          'Kullanıcı yönetimi, rol yetki tanımlama ve uygulama ayarları',
      subModules: {
        'kullanici_yonetimi': 'Kullanıcı Yönetimi & Yetkilendirme',
        'yetki_tanimlama': 'Yetki Tanımlama (Rol Şablonları)',
        'uygulama_ayarlari': 'Uygulama Ayarları',
        'veri_yedekleme': 'Veri Yedekleme',
        'sms_entegrasyonu': 'SMS Entegrasyonu',
      },
      nestedSubModules: {
        'kullanici_yonetimi': {
          'kullanici_ekle_duzenle': 'Kullanıcı Ekleme & Bilgileri Düzenleme',
          'kullanici_bireysel_yetki': 'Kişiye Özel Modül Yetkisi Tanımlama',
          'kullanici_sifre_durum': 'Şifre Değiştirme & Hesap Aktif/Pasif',
        },
        'yetki_tanimlama': {
          'rol_sablon_duzenle': 'Varsayılan Rol Yetkilerini Düzenleme',
          'ozel_rol_olustur': 'Yeni Özel Görev / Kullanıcı Türü Açma',
        },
        'uygulama_ayarlari': {
          'ayar_kurum_profil': 'Kurum Bilgileri, Logo & Tema Yapılandırması',
          'ayar_bildirim_tercih': 'Sistem & Bildirim Tercihlerini Yönetme',
        },
        'veri_yedekleme': {
          'yedek_olustur_indir': 'Veritabanı Yedeği Oluşturma & İndirme',
          'yedek_geri_yukle': 'Yedekten Veri Geri Yükleme',
        },
        'sms_entegrasyonu': {
          'sms_api_yapilandir': 'SMS Sağlayıcı (NetGSM / İletiMerkezi) Ayarı',
          'sms_sablon_kota': 'SMS Başlıkları, Şablonlar & Bakiye Kontrolü',
        },
      },
    ),
  };

  /// Tüm modüllerin key'lerini liste olarak döner
  static List<String> get allModuleKeys => modules.keys.toList();

  /// Belirli bir kategorideki modülleri döner
  static Map<String, ModuleInfo> getModulesByCategory(String category) {
    return Map.fromEntries(
      modules.entries.where((e) => e.value.category == category),
    );
  }

  /// Tüm kategorileri döner
  static List<String> get allCategories {
    return modules.values.map((m) => m.category).toSet().toList();
  }

  /// Modül ismini key'den döner
  static String getModuleName(String key) {
    return modules[key]?.name ?? key;
  }

  /// Modül bilgisini döner
  static ModuleInfo? getModule(String key) {
    return modules[key];
  }
}

/// Modül bilgisi sınıfı (3 Seviye Hiyerarşi: Modül -> subModules -> nestedSubModules)
class ModuleInfo {
  final String key;
  final String name;
  final IconData icon;
  final Color color;
  final String category;
  final String description;
  final Map<String, String> subModules;
  final Map<String, Map<String, String>> nestedSubModules;

  const ModuleInfo({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.category,
    required this.description,
    this.subModules = const {},
    this.nestedSubModules = const {},
  });

  /// Belirli bir alt başlığın altındaki 3. seviye öğeleri döner
  Map<String, String> childrenOf(String subModuleKey) =>
      nestedSubModules[subModuleKey] ?? const {};

  /// Hem 2. seviye hem 3. seviye tüm anahtarları tek düz haritada döner (Rol şablonları için)
  Map<String, String> get allSubAndNestedModules {
    final out = <String, String>{...subModules};
    for (final entry in nestedSubModules.entries) {
      out.addAll(entry.value);
    }
    return out;
  }
}
