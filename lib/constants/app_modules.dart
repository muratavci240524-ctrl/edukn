import 'package:flutter/material.dart';

/// Uygulama genelinde kullanılacak modüller
/// Yeni modül eklerken buraya ekleyin, tüm sistem otomatik güncellenecektir
class AppModules {
  // Modül tanımları: key -> (displayName, icon, color)
  // NOT: LinkedHashMap kullanıldığı için sıralama korunur
  static final Map<String, ModuleInfo> modules = {
    // 1. GENEL DUYURULAR
    'genel_duyurular': ModuleInfo(
      key: 'genel_duyurular',
      name: 'Genel Duyurular',
      icon: Icons.campaign,
      color: Colors.purple,
      category: 'İletişim',
      description: 'Duyuru oluştur ve paylaş',
    ),

    // 2. ÖĞRENCİ KAYIT
    'ogrenci_kayit': ModuleInfo(
      key: 'ogrenci_kayit',
      name: 'Öğrenci Kayıt',
      icon: Icons.person_add,
      color: Colors.blue,
      category: 'Eğitim',
      description: 'Öğrenci kayıt ve yönetimi',
    ),

    // 3. OKUL TÜRLERİ
    'okul_turleri': ModuleInfo(
      key: 'okul_turleri',
      name: 'Okul Türleri',
      icon: Icons.school_outlined,
      color: Colors.teal,
      category: 'Yönetim',
      description: 'Anaokulu, İlkokul, Lise vb. yönetimi',
    ),

    // 4. KULLANICI YÖNETİMİ
    'kullanici_yonetimi': ModuleInfo(
      key: 'kullanici_yonetimi',
      name: 'Kullanıcı Yönetimi',
      icon: Icons.person_add_alt_1,
      color: Colors.deepPurple,
      category: 'Yönetim',
      description: 'Kullanıcı ekleme, düzenleme ve yetkilendirme',
    ),

    // 5. İNSAN KAYNAKLARI
    'insan_kaynaklari': ModuleInfo(
      key: 'insan_kaynaklari',
      name: 'İnsan Kaynakları',
      icon: Icons.group,
      color: Colors.indigo,
      category: 'Yönetim',
      description: 'Personel yönetimi ve işlemler',
    ),

    // 6. MUHASEBE
    'muhasebe': ModuleInfo(
      key: 'muhasebe',
      name: 'Muhasebe',
      icon: Icons.account_balance,
      color: Colors.green,
      category: 'Mali İşler',
      description: 'Mali işlemler ve raporlama',
    ),

    // 7. SATIN ALMA
    'satin_alma': ModuleInfo(
      key: 'satin_alma',
      name: 'Satın Alma',
      icon: Icons.shopping_cart,
      color: Colors.orange,
      category: 'Mali İşler',
      description: 'Tedarik ve alım işlemleri',
    ),

    // 8. DEPO
    'depo': ModuleInfo(
      key: 'depo',
      name: 'Depo Yönetimi',
      icon: Icons.inventory,
      color: Colors.brown,
      category: 'Mali İşler',
      description: 'Stok takibi ve envanter yönetimi',
    ),

    // 9. DESTEK HİZMETLERİ
    'destek_hizmetleri': ModuleInfo(
      key: 'destek_hizmetleri',
      name: 'Destek Hizmetleri',
      icon: Icons.support_agent,
      color: Colors.cyan,
      category: 'Hizmetler',
      description: 'Teknik destek ve yardım',
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

  const ModuleInfo({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.category,
    required this.description,
  });
}
