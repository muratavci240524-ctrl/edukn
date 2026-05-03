import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants/app_modules.dart';
import '../constants/school_type_modules.dart';

class RolePermissionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String collectionName = 'roleTemplates';

  /// Built-in role keys (cannot be deleted)
  static const Map<String, String> builtInRoles = {
    'genel_mudur': 'Genel Müdür',
    'mudur': 'Müdür',
    'mudur_yardimcisi': 'Müdür Yardımcısı',
    'ogretmen': 'Öğretmen',
    'rehber_ogretmen': 'Rehber Öğretmen',
    'ogrenci': 'Öğrenci',
    'veli': 'Veli',
    'personel': 'Personel',
  };

  /// Kept for backward compatibility – merges built-in + custom roles loaded from Firestore
  static Map<String, String> get standardRoles => Map.unmodifiable(builtInRoles);

  /// Get icon for role
  static IconData getRoleIcon(String roleKey) {
    switch (roleKey) {
      case 'genel_mudur': return Icons.admin_panel_settings;
      case 'mudur': return Icons.person_pin;
      case 'mudur_yardimcisi': return Icons.person_outline;
      case 'ogretmen': return Icons.school;
      case 'rehber_ogretmen': return Icons.psychology;
      case 'ogrenci': return Icons.face;
      case 'veli': return Icons.family_restroom;
      case 'personel': return Icons.badge;
      default: return Icons.person;
    }
  }

  /// Get color for role
  static Color getRoleColor(String roleKey) {
    switch (roleKey) {
      case 'genel_mudur': return Colors.indigo;
      case 'mudur': return Colors.blue;
      case 'mudur_yardimcisi': return Colors.lightBlue;
      case 'ogretmen': return Colors.green;
      case 'rehber_ogretmen': return Colors.teal;
      case 'ogrenci': return Colors.orange;
      case 'veli': return Colors.pink;
      case 'personel': return Colors.blueGrey;
      default: return Colors.deepPurple;
    }
  }  /// Get default permissions for a role
  static Map<String, dynamic> getDefaultPermissions(String roleKey) {
    Map<String, dynamic> perms = {};
    
    for (var moduleKey in AppModules.allModuleKeys) {
      final moduleInfo = AppModules.getModule(moduleKey)!;
      bool enabled = false;
      String level = 'viewer';

      if (roleKey == 'genel_mudur' || roleKey == 'mudur') {
        enabled = true;
        level = 'editor';
      } else if (roleKey == 'mudur_yardimcisi') {
        enabled = true;
        level = (moduleKey == 'sistem_ayarlari' || moduleKey == 'mali_isler') ? 'viewer' : 'editor';
      }

      // Sub-modules permissions
      Map<String, Map<String, dynamic>> subPerms = {};
      moduleInfo.subModules.forEach((subKey, subName) {
        subPerms[subKey] = {'enabled': enabled, 'level': level};
      });

      perms[moduleKey] = {
        'enabled': enabled, 
        'level': level,
        'subModules': subPerms,
      };
    }

    return perms;
  }

  /// Get default school type permissions for a role
  static Map<String, dynamic> getDefaultSchoolTypePermissions(String roleKey) {
    Map<String, dynamic> perms = {};
    
    for (var moduleKey in SchoolTypeModules.allModuleKeys) {
      final moduleInfo = SchoolTypeModules.getModule(moduleKey)!;
      bool enabled = false;
      String level = 'viewer';

      if (['genel_mudur', 'mudur', 'mudur_yardimcisi', 'ogretmen', 'rehber_ogretmen'].contains(roleKey)) {
        enabled = true;
        level = 'editor';
      }

      // Sub-modules permissions
      Map<String, Map<String, dynamic>> subPerms = {};
      moduleInfo.subModules.forEach((subKey, subName) {
        subPerms[subKey] = {'enabled': enabled, 'level': level};
      });

      perms[moduleKey] = {
        'enabled': enabled, 
        'level': level,
        'subModules': subPerms,
      };
    }

    return perms;
  }

  // ─── CRUD ────────────────────────────────────────────────

  /// Save / update a role template
  Future<void> saveRoleTemplate(String institutionId, String roleKey, Map<String, dynamic> data) async {
    await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection(collectionName)
        .doc(roleKey)
        .set({
          ...data,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Load a single role template
  Future<Map<String, dynamic>?> loadRoleTemplate(String institutionId, String roleKey) async {
    final doc = await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection(collectionName)
        .doc(roleKey)
        .get();
    
    return doc.exists ? doc.data() : null;
  }

  /// Get all role templates for an institution
  Future<Map<String, Map<String, dynamic>>> getAllTemplates(String institutionId) async {
    final query = await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection(collectionName)
        .get();
    
    Map<String, Map<String, dynamic>> templates = {};
    for (var doc in query.docs) {
      templates[doc.id] = doc.data();
    }
    return templates;
  }

  /// Delete a custom role template (built-in roles cannot be deleted, only reset)
  Future<void> deleteRoleTemplate(String institutionId, String roleKey) async {
    await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection(collectionName)
        .doc(roleKey)
        .delete();
  }

  /// Check if a role key is built-in
  static bool isBuiltIn(String roleKey) => builtInRoles.containsKey(roleKey);
}
