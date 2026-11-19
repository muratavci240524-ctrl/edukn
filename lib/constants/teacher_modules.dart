import 'package:flutter/material.dart';

/// Öğretmen arayüzü modül, alt başlık ve 3. seviye alt işlem tanımları
class TeacherModuleInfo {
  final String key;
  final String name;
  final IconData icon;
  final Color color;
  final String description;
  final Map<String, String> subModules;
  final Map<String, Map<String, String>> nestedSubModules;

  const TeacherModuleInfo({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
    required this.subModules,
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

class TeacherModules {
  static final Map<String, TeacherModuleInfo> modules = {
    // 1. EĞİTİM İŞLEMLERİ
    'egitim_islemleri': const TeacherModuleInfo(
      key: 'egitim_islemleri',
      name: 'Eğitim İşlemleri',
      icon: Icons.school,
      color: Colors.orange,
      description:
          'Günlük karne, ders programı, öğrenci listesi, yoklama, ödev ve sınav raporları',
      subModules: {
        'gunluk_rapor': 'Günlük Rapor (Günlük Karne)',
        'ders_programi': 'Ders Programı',
        'tanimli_ogrencilerim': 'Tanımlı Öğrencilerim',
        'ders_isleyis_plani': 'Ders İşleyiş Planı & Kazanım Takip',
        'yoklama_istatistikleri': 'Yoklama Girişi & İstatistikleri',
        'odev_istatistikleri': 'Ödev Verme & İstatistikleri',
        'etut_islemleri': 'Etüt İşlemleri',
        'anket_islemleri': 'Anket İşlemleri',
        'sinav_raporlari': 'Sınav Raporları',
      },
      nestedSubModules: {
        'gunluk_rapor': {
          'gunluk_rapor_toplu_sinif': 'Tüm Sınıfa Toplu Günlük Karne İşleme',
          'gunluk_rapor_bireysel': 'Öğrenci Bazlı Bireysel Karne Düzenleme',
          'gunluk_rapor_etkinlik_foto':
              'Etkinlik / Ders Akışı & Fotoğraf Ekleme',
        },
        'yoklama_istatistikleri': {
          't_yoklama_girisi': 'Ders Yoklaması Alma',
          't_yoklama_analiz': 'Sınıf Devamsızlık İstatistiklerini Görme',
        },
        'odev_istatistikleri': {
          't_odev_tanimla': 'Yeni Ödev Tanımlama',
          't_odev_kontrol': 'Ödev Teslim & Kontrol Değerlendirmesi',
        },
        'sinav_raporlari': {
          'sinav_tekil_liste': 'Tekil Sınav: Sonuç Listesi & Sıralamalar',
          'sinav_tekil_karne': 'Tekil Sınav: Öğrenci Sınav Karnesi',
          'sinav_tekil_ortalama': 'Tekil Sınav: Ders & Puan Ortalamaları',
          'sinav_tekil_basari_belgesi': 'Tekil Sınav: Başarı Belgeleri',
          'sinav_tekil_kazanim': 'Tekil Sınav: Kazanım Analizleri',
          'sinav_tekil_soru': 'Tekil Sınav: Soru / Madde Analizleri',
          'sinav_birlestirilmis_raporlar': 'Birleştirilmiş Sınav Raporları',
          'sinav_guclendirme_programlari': 'Güçlendirme Programları',
          'sinav_agm': 'AGM (Akademik Güçlendirme)',
          'sinav_aksiyon_plani': 'Aksiyon Planları',
          'sinav_veli_raporu': 'Veli Bilgilendirme Raporu',
        },
      },
    ),

    // 2. REHBERLİK İŞLEMLERİ
    'rehberlik_islemleri': const TeacherModuleInfo(
      key: 'rehberlik_islemleri',
      name: 'Rehberlik İşlemleri',
      icon: Icons.folder_special,
      color: Colors.deepPurple,
      description: 'Portfolyo, görüşmeler, etkinlikler ve gelişim raporları',
      subModules: {
        'ogrenci_portfolyolari': 'Öğrenci Portfolyoları',
        'gorusmeler': 'Görüşmeler',
        'gozlem_ve_etkinlik': 'Gözlem ve Etkinlik İşlemleri',
        'ders_calisma_programi': 'Ders Çalışma Programı',
        'rehberlik_envanterleri': 'Rehberlik Envanterleri',
        'rehberlik_kutuphanesi': 'Rehberlik Kütüphanesi',
        'gelisim_raporlari': '360 Gelişim Raporları',
      },
      nestedSubModules: {
        'ogrenci_portfolyolari': {
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
          't_gorusme_goruntule': 'Görüşme Kayıtlarını Görüntüleme',
          't_gorusme_ekle': 'Yeni Görüşme Kaydı Ekleme',
        },
        'gozlem_ve_etkinlik': {
          'gozlem_etkinlik_goruntule': 'Formları Görüntüle',
          'gozlem_etkinlik_form_doldur': 'Form Doldurma / Değerlendirme',
          'gozlem_etkinlik_yeni_form': 'Yeni Form Açma / Düzenleme',
        },
      },
    ),

    // 3. GÖREVLENDİRME VE İZİN
    'gorevlendirme_ve_izin': const TeacherModuleInfo(
      key: 'gorevlendirme_ve_izin',
      name: 'Görevlendirme ve İzin',
      icon: Icons.assignment_ind,
      color: Colors.brown,
      description: 'Nöbetler, izinler, yapılacaklar ve gezi görevlendirmeleri',
      subModules: {
        'nobetlerim': 'Nöbetlerim',
        'izin_islemleri': 'İzin İşlemleri',
        'yapilacaklar': 'Yapılacaklar (To-Do)',
        'giris_cikis_qr': 'Giriş-Çıkış (QR)',
        'gezi_gorevlendirmeleri': 'Gezi Görevlendirmeleri',
      },
      nestedSubModules: {
        'izin_islemleri': {
          't_izin_talep_ac': 'Yeni İzin Talebi Oluşturma',
          't_izin_gecmis': 'İzin Geçmişi & Kalan İzin Görüntüleme',
        },
      },
    ),

    // 4. DESTEK BİRİMİ
    'destek_birimi': const TeacherModuleInfo(
      key: 'destek_birimi',
      name: 'Destek Birimi',
      icon: Icons.support_agent_rounded,
      color: Color(0xFF0D9488),
      description: 'Malzeme talebi ve destek birimi işlemleri',
      subModules: {'malzeme_talep': 'Malzeme Talep'},
      nestedSubModules: {
        'malzeme_talep': {
          't_malzeme_talep_olustur': 'Yeni Malzeme Talebi Oluşturma',
          't_malzeme_talep_izle': 'Kendi Malzeme Taleplerini İzleme',
        },
      },
    ),

    // 5. ARAÇLAR
    'araclar': const TeacherModuleInfo(
      key: 'araclar',
      name: 'Araçlar',
      icon: Icons.build_circle_outlined,
      color: Color(0xFFD97706),
      description:
          'Sınıf içi yönetim, sınav, ölçme, evrak araçları, mağaza, kantin ve kişisel notlar',
      subModules: {
        'sinif_ici_yonetim': 'Sınıf İçi Yönetim ve Etkileşim',
        'sinav_gozetmenlik': 'Sınav ve Gözetmenlik',
        'akademik_olcme': 'Akademik Ölçme ve Başarı Takibi',
        'fokus_kitap': 'Fokus Kitap (Kişiye Özel Soru Bankası)',
        'evrak_sablon': 'Resmi Evrak ve Matbu Şablon Merkezi',
        'ogrenci_hareket_takip': 'Geç - İzin - Revir - Görüşme ve Canlı İzleme',
        'online_hizmetler': 'Online Hizmetler',
        'magaza_alisveris': 'Okul & Genel Merkez Mağazası',
        'kantin_cuzdan': 'Kantin Cüzdanı & QR Ödeme',
        'notlarim': 'Kişisel Notlarım',
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
        'fokus_kitap': {
          't_fokus_kitap_olustur': 'Kazanım Bazlı Kişiye Özel Kitap Üretme',
          't_fokus_kitap_indir': 'Öğrenci Kitapçığı PDF / ZIP İndirme',
        },
        'evrak_sablon': {
          't_evrak_zumre': 'Zümre & Kurul Tutanakları Üretme',
          't_evrak_veli_tutanak': 'Veli Görüşme & Tutanak Şablonları',
          't_evrak_sinif_liste': 'Sınıf Kontrol & İmza Listeleri',
        },
        'magaza_alisveris': {
          't_magaza_vitrin_satin_al': 'Mağaza Vitrini & Online Alışveriş',
          't_magaza_siparis_takip': 'Siparişlerim & Teslimat Takibi',
        },
        'kantin_cuzdan': {
          't_kantin_bakiye_qr': 'Kantin Cüzdanına Bakiye Yükleme & QR Ödeme',
          't_kantin_hareketler': 'Kantin Harcama Geçmişini Görüntüleme',
        },
      },
    ),

    // 6. HABERLEŞME & İLETİŞİM
    'iletisim_haberlesme': const TeacherModuleInfo(
      key: 'iletisim_haberlesme',
      name: 'Haberleşme & İletişim',
      icon: Icons.chat_bubble_outline,
      color: Colors.blue,
      description: 'Mesajlaşma, duyurular ve sosyal medya paylaşımları',
      subModules: {
        'mesajlar': 'Mesajlar / Sohbet',
        'duyurular': 'Duyurular',
        'sosyal_medya': 'Sosyal Medya / Akış',
      },
      nestedSubModules: {
        'mesajlar': {
          't_mesaj_birebir': 'Birebir Mesajlaşma',
          't_mesaj_grup': 'Grup Sohbeti Oluşturma & Yönetme',
          't_mesaj_veli_ogrenci': 'Veli & Öğrenciyle Mesajlaşma',
          't_mesaj_medya': 'Medya & Dosya Gönderme',
        },
        'duyurular': {
          't_duyuru_goruntule': 'Kurum Duyurularını Görüntüleme',
          't_duyuru_olustur': 'Yeni Duyuru Oluşturma',
          't_duyuru_hedef_kitle': 'Duyuru Alıcı / Hedef Kitle Seçimi',
          't_duyuru_planli_ek': 'Duyuruyu Planlama, Dosya Eki & Bağlantı Ekleme',
          't_duyuru_gonderilen': 'Gönderdiğim Duyuruları Görüntüleme & Düzenleme',
        },
        'sosyal_medya': {
          't_sosyal_goruntule': 'Akışı Görüntüleme & Beğenme',
          't_sosyal_paylas': 'Sınıf / Etkinlik Gönderisi Paylaşma',
          't_sosyal_duzenle_sil': 'Kendi Gönderisini Düzenleme & Silme',
        },
      },
    ),

    // 7. GÖSTERGE PANELİ (DASHBOARD)
    'gosterge_paneli': const TeacherModuleInfo(
      key: 'gosterge_paneli',
      name: 'Gösterge Paneli (Dashboard)',
      icon: Icons.dashboard_outlined,
      color: Colors.teal,
      description: 'Öğretmen ana sayfasındaki bildirimler ve haftalık takvim',
      subModules: {
        'bildirim_akisi': 'Bildirim Akışı & Hatırlatıcılar',
        'takvim_ders_programi': 'Haftalık Ders Takvimi & Programı',
      },
    ),
  };

  static List<String> get allModuleKeys => modules.keys.toList();
  static TeacherModuleInfo? getModule(String key) => modules[key];
}
