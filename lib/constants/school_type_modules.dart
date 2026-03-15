import 'package:flutter/material.dart';

/// Okul türlerine özel eğitim modülleri
/// Ana modüllerden farklı olarak, bunlar okul türü bazında aktif edilir
class SchoolTypeModules {
  // Modül tanımları
  static final Map<String, SchoolTypeModuleInfo> modules = {
    'duyurular': SchoolTypeModuleInfo(
      key: 'duyurular',
      name: 'Duyurular',
      icon: Icons.announcement,
      color: Colors.orange,
      description: 'Sınıf ve okul duyuruları',
    ),
    'sosyal_ag': SchoolTypeModuleInfo(
      key: 'sosyal_ag',
      name: 'Sosyal Ağ',
      icon: Icons.share,
      color: Colors.blue,
      description: 'Öğrenci ve veli sosyal paylaşım platformu',
    ),
    'mesajlasma': SchoolTypeModuleInfo(
      key: 'mesajlasma',
      name: 'Mesajlaşma',
      icon: Icons.message,
      color: Colors.green,
      description: 'Öğretmen, veli ve öğrenci mesajlaşma',
    ),
    'olcme_degerlendirme': SchoolTypeModuleInfo(
      key: 'olcme_degerlendirme',
      name: 'Ölçme Değerlendirme',
      icon: Icons.assessment,
      color: Colors.purple,
      description: 'Sınav ve quiz yönetimi',
    ),
    'rehberlik': SchoolTypeModuleInfo(
      key: 'rehberlik',
      name: 'Rehberlik',
      icon: Icons.psychology,
      color: Colors.teal,
      description: 'Psikolojik danışmanlık ve rehberlik',
    ),
    'portfolyo': SchoolTypeModuleInfo(
      key: 'portfolyo',
      name: 'Portfolyo',
      icon: Icons.folder_special,
      color: Colors.amber,
      description: 'Öğrenci çalışma portfolyosu',
    ),
    'ders_programi': SchoolTypeModuleInfo(
      key: 'ders_programi',
      name: 'Ders Programı',
      icon: Icons.calendar_month,
      color: Colors.indigo,
      description: 'Haftalık ders programı yönetimi',
    ),
    'odev': SchoolTypeModuleInfo(
      key: 'odev',
      name: 'Ödev',
      icon: Icons.assignment,
      color: Colors.red,
      description: 'Ödev takip ve yönetim sistemi',
    ),
    'etut': SchoolTypeModuleInfo(
      key: 'etut',
      name: 'Etüt',
      icon: Icons.school,
      color: Colors.brown,
      description: 'Etüt programı ve takibi',
    ),
    'karne': SchoolTypeModuleInfo(
      key: 'karne',
      name: 'Karne',
      icon: Icons.grade,
      color: Colors.pink,
      description: 'Dijital karne ve not sistemi',
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

  const SchoolTypeModuleInfo({
    required this.key,
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
  });
}
