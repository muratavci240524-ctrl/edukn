import 'package:flutter/material.dart';

/// Uygulama genelinde kullanılacak modüller
/// Yeni modül eklerken buraya ekleyin, tüm sistem otomatik güncellenecektir
class AppModules {
  // Modül tanımları: key -> (displayName, icon, color, subModules)
  static final Map<String, ModuleInfo> modules = {
    // 1. EĞİTİM
    'egitim': ModuleInfo(
      key: 'egitim',
      name: 'Eğitim',
      icon: Icons.school_outlined,
      color: Colors.indigo,
      category: 'Akademik',
      description: 'Ön kayıt, öğrenci kaydı ve okul türleri yönetimi',
      subModules: {
        'on_kayit': 'Ön Kayıt',
        'ogrenci_kaydi': 'Öğrenci Kaydı',
        'okul_turleri': 'Okul Türleri',
      },
    ),

    // 2. REHBERLİK
    'rehberlik': ModuleInfo(
      key: 'rehberlik',
      name: 'Rehberlik İşlemleri',
      icon: Icons.psychology_outlined,
      color: Colors.deepOrange,
      category: 'Rehberlik',
      description: 'Portfolyo, talepler ve rehberlik testleri',
      subModules: {
        'ogrenci_portfolyosu': 'Öğrenci Portfolyosu',
        'talepler': 'Talepler (Yönlendirmeler)',
        'gorusme_kayitlari': 'Görüşme Kayıtları',
        'rehberlik_testleri': 'Rehberlik Testleri',
      },
    ),

    // 3. İNSAN KAYNAKLARI
    'insan_kaynaklari': ModuleInfo(
      key: 'insan_kaynaklari',
      name: 'İnsan Kaynakları',
      icon: Icons.group_outlined,
      color: Colors.purple,
      category: 'Kurumsal',
      description: 'Personel, maaş, bordro ve performans yönetimi',
      subModules: {
        'personel_bilgi': 'Personel Bilgi Yönetimi',
        'devam_mesai_izin': 'Devam – Mesai – İzin',
        'maas_bordro': 'Maaş ve Bordro',
        'performans_yonetimi': 'Performans Yönetimi',
        'egitim_gelisim': 'Eğitim ve Gelişim',
        'sozlesme_evrak': 'Sözleşme ve Evrak',
        'ik_raporlama': 'İK Raporlama',
      },
    ),

    // 4. ÖLÇME DEĞERLENDİRME
    'olcme_degerlendirme': ModuleInfo(
      key: 'olcme_degerlendirme',
      name: 'Ölçme Değerlendirme',
      icon: Icons.assignment_turned_in_outlined,
      color: Colors.teal,
      category: 'Ölçme',
      description: 'Sınav, rapor, deneme ve soru havuzu',
      subModules: {
        'tanimlar': 'Tanımlar',
        'raporlar': 'Raporlar',
        'denemeler': 'Denemeler',
        'sinavlar': 'Sınavlar',
        'hata_kitapcigi': 'Hata Kitapçığı',
        'soru_havuzu': 'Soru Havuzu',
      },
    ),

    // 5. MALİ İŞLER
    'mali_isler': ModuleInfo(
      key: 'mali_isler',
      name: 'Mali İşler',
      icon: Icons.account_balance_wallet_outlined,
      color: Colors.blue,
      category: 'Finans',
      description: 'Gelir, gider, tahsilat ve makbuz işlemleri',
      subModules: {
        'gelir_kaydi': 'Gelir Kaydı',
        'gider_kaydi': 'Gider Kaydı',
        'veli_tahsilat': 'Veli Tahsilat',
        'makbuz_al': 'Makbuz Al',
      },
    ),

    // 6. HİZMETLER
    'hizmetler': ModuleInfo(
      key: 'hizmetler',
      name: 'Hizmetler',
      icon: Icons.support_agent_outlined,
      color: Colors.orange,
      category: 'Operasyon',
      description: 'Yemekhane, servis, depo ve satın alma',
      subModules: {
        'yemekhane_islemleri': 'Yemekhane İşlemleri',
        'servis_islemleri': 'Servis İşlemleri',
        'depo_satin_alma': 'Depo ve Satın Alma',
      },
    ),

    // 7. SİSTEM AYARLARI
    'sistem_ayarlari': ModuleInfo(
      key: 'sistem_ayarlari',
      name: 'Sistem Ayarları',
      icon: Icons.settings_outlined,
      color: Colors.blueGrey,
      category: 'Sistem',
      description: 'Kullanıcı yönetimi, yetkilendirme ve ayarlar',
      subModules: {
        'kullanici_yonetimi': 'Kullanıcı Yönetimi',
        'yetki_tanimlama': 'Yetki Tanımlama',
        'uygulama_ayarlari': 'Uygulama Ayarları',
        'veri_yedekleme': 'Veri Yedekleme',
      },
    ),

    // 8. KİŞİSEL İŞLEMLER
    'kisisel_islemler': ModuleInfo(
      key: 'kisisel_islemler',
      name: 'Kişisel İşlemler',
      icon: Icons.person_outline,
      color: Colors.pink,
      category: 'Kişisel',
      description: 'Kişisel notlar ve ayarlar',
      subModules: {
        'notlarim': 'Notlarım',
      },
    ),

    // 9. HABERLEŞME
    'haberlesme': ModuleInfo(
      key: 'haberlesme',
      name: 'Haberleşme Merkezi',
      icon: Icons.campaign_outlined,
      color: Colors.orange,
      category: 'Kurumsal',
      description: 'Duyurular, sosyal medya ve mesajlaşma',
      subModules: {
        'genel_duyurular': 'Duyurular',
        'sosyal_medya': 'Sosyal Medya',
        'mesajlar': 'Mesajlar',
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

/// Modül bilgisi sınıfı
class ModuleInfo {
  final String key;
  final String name;
  final IconData icon;
  final Color color;
  final String category;
  final String description;
  final Map<String, String> subModules;

  const ModuleInfo({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.category,
    required this.description,
    this.subModules = const {},
  });
}
