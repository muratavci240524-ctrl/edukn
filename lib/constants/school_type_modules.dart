import 'package:flutter/material.dart';

/// Okul türlerine özel eğitim modülleri
/// Ana modüllerden farklı olarak, bunlar okul türü bazında aktif edilir
class SchoolTypeModules {
  // Modül tanımları
  static final Map<String, SchoolTypeModuleInfo> modules = {
    'kayit': SchoolTypeModuleInfo(
      key: 'kayit',
      name: 'Öğrenci ve Personel',
      icon: Icons.people_outline,
      color: Colors.blue,
      description: 'Öğrenci, personel ve sınıf yönetimi',
      subModules: {
        'ogrenci_listesi': 'Öğrenci Listesi',
        'personel_listesi': 'Personel Listesi',
        'sube_listesi': 'Şube Tanımları',
        'ders_listesi': 'Müfredat / Ders Tanımları',
        'derslik_listesi': 'Derslik Tanımları',
        'kitap_listesi': 'Kitap / Yayın Listesi',
        'ogrenci_kayit_duzenle': 'Yeni Öğrenci Kaydı / Düzenleme',
        'toplu_veri_yukleme': 'Toplu Öğrenci Yükleme (Excel)',
        'kayit_silme': 'Kayıt Silme / Pasifleme İşlemleri',
      },
    ),
    'egitim': SchoolTypeModuleInfo(
      key: 'egitim',
      name: 'Eğitim İşlemleri',
      icon: Icons.school,
      color: Colors.green,
      description: 'Akademik süreçler ve ders programı',
      subModules: {
        'takvim_donem': 'Çalışma Takvimi (Alt Dönem Açma)',
        'takvim_plan': 'Çalışma Takvimi (Plan Oluşturma)',
        'ders_saatleri': 'Ders Saatleri Tanımlama',
        'ders_programi': 'Ders Programı Hazırlama',
        'sube_programi': 'Şube Programı Görüntüleme',
        'ogretmen_programi': 'Öğretmen Programı Görüntüleme',
        'yoklama_girisi': 'Yoklama Girişi',
        'odev_tanimlama': 'Ödev Tanımlama',
        'anketler': 'Anket ve Form İşlemleri',
        'etutler': 'Etüt ve Ek Ders İşlemleri',
        'ders_plani': 'Günlük/Haftalık Ders Planları',
        'kazanimlar': 'Kazanım Takip Sistemi',
      },
    ),
    'rehberlik': SchoolTypeModuleInfo(
      key: 'rehberlik',
      name: 'Rehberlik İşlemleri',
      icon: Icons.folder_special,
      color: Colors.purple,
      description: 'PDR ve öğrenci gelişim takibi',
      subModules: {
        'portfolyo': 'Öğrenci Portfolyosu',
        'talepler': 'Talepler (Yönlendirmeler)',
        'gorusmeler': 'Görüşme Kayıtları',
        'gorusme_ekle': 'Yeni Görüşme Kaydı',
        'etkinlikler': 'Gözlem ve Etkinlikler',
        'calisma_programi': 'Çalışma Programı',
        'envanterler': 'Rehberlik Envanterleri',
        'gelisim_raporlari': '360 Gelişim Raporları',
        'toplu_gozlem': 'Toplu Gözlem Girişi',
        'pdr_ajanda': 'Rehberlik Ajandası',
      },
    ),
    'olcme': SchoolTypeModuleInfo(
      key: 'olcme',
      name: 'Ölçme Değerlendirme',
      icon: Icons.analytics,
      color: Colors.orange,
      description: 'Sınav, rapor ve analiz yönetimi',
      subModules: {
        'tanimlar': 'Sınav Tanımlama',
        'raporlar': 'Sınav Sonuç Raporları',
        'denemeler': 'Deneme Sınavları',
        'sinavlar': 'Aktif Sınavlar',
        'not_girisi': 'Not Girişi',
        'sinav_analizleri': 'Sınav Analizleri',
        'hata_kitapcigi': 'Hata Kitapçığı',
        'soru_havuzu': 'Soru Havuzu',
        'optik_okuma': 'Optik Form ve Okuma',
        'sinav_gorevlendirme': 'Sınav Görevlileri',
      },
    ),
    'gorev': SchoolTypeModuleInfo(
      key: 'gorev',
      name: 'Görevlendirme ve İzin',
      icon: Icons.assignment_ind,
      color: Colors.teal,
      description: 'Görev, nöbet ve izin yönetimi',
      subModules: {
        'todo_list': 'To do List',
        'izin_yonetimi': 'İzin Yönetimi',
        'gecici_ogretmen': 'Geçici Öğretmen',
        'nobet_islemleri': 'Nöbet İşlemleri',
        'gezi_gorev': 'Gezi Görevlendirmeleri',
        'proje_gorev': 'Proje Görevlendirmeleri',
        'personel_nobet_cizelgesi': 'Nöbet Çizelgesi',
      },
    ),
    'destek': SchoolTypeModuleInfo(
      key: 'destek',
      name: 'Destek Hizmetleri',
      icon: Icons.support_agent,
      color: Colors.cyan,
      description: 'Yemekhane, servis ve lojistik',
      subModules: {
        'yemekhane': 'Yemekhane İşlemleri',
        'servis': 'Servis İşlemleri',
        'saglik': 'Sağlık İşlemleri',
        'kutuphane': 'Kütüphane İşlemleri',
        'temizlik': 'Temizlik İşlemleri',
        'depo_satin_alma': 'Depo ve Satın Alma',
        'envanter_takibi': 'Okul Envanteri',
      },
    ),
    'raporlar': SchoolTypeModuleInfo(
      key: 'raporlar',
      name: 'Raporlar ve İstatistik',
      icon: Icons.analytics_outlined,
      color: Colors.indigo,
      description: 'Genel durum ve yoklama istatistikleri',
      subModules: {
        'yoklama_raporlari': 'Yoklama Raporları',
        'yoklama_istatistik': 'Yoklama İstatistikleri',
        'odev_raporlari': 'Ödev Raporları',
        'olcme_raporlari': 'Ölçme Raporları',
        'gelisim_istatistik': 'Gelişim İstatistikleri',
      },
    ),
    'ayarlar': SchoolTypeModuleInfo(
      key: 'ayarlar',
      name: 'Sistem Ayarları',
      icon: Icons.settings,
      color: Colors.blueGrey,
      description: 'Yetki ve uygulama konfigürasyonu',
      subModules: {
        'yetki_tanimlama': 'Yetki Tanımlama',
        'kullanici_yetki': 'Kullanıcı Yetkilendirme',
        'uygulama_ayarlari': 'Uygulama Ayarları',
        'okul_bilgileri': 'Okul Genel Bilgileri',
      },
    ),
    'kisisel': SchoolTypeModuleInfo(
      key: 'kisisel',
      name: 'Kişisel İşlemler',
      icon: Icons.person,
      color: Colors.pink,
      description: 'Bireysel notlar ve ajanda',
      subModules: {
        'notlarim': 'Notlarım',
        'ajanda': 'Kişisel Ajanda',
      },
    ),
    'haberlesme': SchoolTypeModuleInfo(
      key: 'haberlesme',
      name: 'İletişim Merkezi',
      icon: Icons.forum_rounded,
      color: Colors.deepPurple,
      description: 'Duyuru, sosyal medya ve mesajlaşma',
      subModules: {
        'duyuru_islemleri': 'Duyuru İşlemleri',
        'sosyal_medya': 'Sosyal Medya',
        'mesajlar': 'Mesajlaşma (Chat)',
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

/// Okul türü modülü bilgisi sınıfı
class SchoolTypeModuleInfo {
  final String key;
  final String name;
  final IconData icon;
  final Color color;
  final String description;
  final Map<String, String> subModules;

  const SchoolTypeModuleInfo({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
    this.subModules = const {},
  });
}
