import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants/app_modules.dart';
import '../constants/school_type_modules.dart';
import '../constants/teacher_modules.dart';

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
    'muhasebe': 'Muhasebe Sorumlusu',
    'kantin_personeli': 'Kantin Sorumlusu / Kasiyer',
    'magaza_sorumlusu': 'Mağaza Sorumlusu',
    'saglik_personeli': 'Sağlık Personeli',
    'guvenlik': 'Güvenlik Görevlisi',
    'depo': 'Depo Sorumlusu',
    'satin_alma': 'Satın Alma Sorumlusu',
    'ogrenci': 'Öğrenci',
    'veli': 'Veli',
    'personel': 'Personel',
  };

  /// Kept for backward compatibility – merges built-in + custom roles loaded from Firestore
  static Map<String, String> get standardRoles =>
      Map.unmodifiable(builtInRoles);

  /// Get icon for role
  static IconData getRoleIcon(String roleKey) {
    switch (roleKey) {
      case 'genel_mudur':
        return Icons.admin_panel_settings;
      case 'mudur':
        return Icons.person_pin;
      case 'mudur_yardimcisi':
        return Icons.person_outline;
      case 'ogretmen':
        return Icons.school;
      case 'rehber_ogretmen':
        return Icons.psychology;
      case 'muhasebe':
        return Icons.account_balance_wallet_rounded;
      case 'kantin_personeli':
        return Icons.restaurant_rounded;
      case 'magaza_sorumlusu':
        return Icons.storefront_rounded;
      case 'saglik_personeli':
        return Icons.medical_services_rounded;
      case 'guvenlik':
        return Icons.shield_rounded;
      case 'depo':
        return Icons.inventory_2_rounded;
      case 'satin_alma':
        return Icons.request_quote_rounded;
      case 'ogrenci':
        return Icons.face;
      case 'veli':
        return Icons.family_restroom;
      case 'personel':
        return Icons.badge;
      default:
        return Icons.person;
    }
  }

  /// Get color for role
  static Color getRoleColor(String roleKey) {
    switch (roleKey) {
      case 'genel_mudur':
        return Colors.indigo;
      case 'mudur':
        return Colors.blue;
      case 'mudur_yardimcisi':
        return Colors.lightBlue;
      case 'ogretmen':
        return Colors.green;
      case 'rehber_ogretmen':
        return Colors.teal;
      case 'muhasebe':
        return const Color(0xFF2563EB);
      case 'kantin_personeli':
        return const Color(0xFFDB2777);
      case 'magaza_sorumlusu':
        return const Color(0xFFEA580C);
      case 'saglik_personeli':
        return const Color(0xFFDC2626);
      case 'guvenlik':
        return const Color(0xFF0284C7);
      case 'depo':
        return const Color(0xFF0D9488);
      case 'satin_alma':
        return const Color(0xFF4F46E5);
      case 'ogrenci':
        return Colors.orange;
      case 'veli':
        return Colors.pink;
      case 'personel':
        return Colors.blueGrey;
      default:
        return Colors.deepPurple;
    }
  }

  /// Get default permissions for a role
  static Map<String, dynamic> getDefaultAppPermissions(String roleKey) =>
      getDefaultPermissions(roleKey);

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
        level = (moduleKey == 'sistem_ayarlari' || moduleKey == 'mali_isler')
            ? 'viewer'
            : 'editor';
      } else if (roleKey == 'muhasebe' &&
          (moduleKey == 'mali_isler' ||
              moduleKey == 'magaza' ||
              moduleKey == 'kantin')) {
        enabled = true;
        level = 'editor';
      } else if (roleKey == 'kantin_personeli' && moduleKey == 'kantin') {
        enabled = true;
        level = 'editor';
      } else if (roleKey == 'magaza_sorumlusu' && moduleKey == 'magaza') {
        enabled = true;
        level = 'editor';
      } else if ((roleKey == 'depo' || roleKey == 'satin_alma') &&
          moduleKey == 'hizmetler') {
        enabled = true;
        level = 'editor';
      } else if (roleKey == 'saglik_personeli' && moduleKey == 'hizmetler') {
        enabled = true;
        level = 'editor';
      } else if (roleKey == 'guvenlik' && moduleKey == 'hizmetler') {
        enabled = true;
        level = 'editor';
      }

      // Sub-modules + 3rd-level nested permissions
      Map<String, Map<String, dynamic>> subPerms = {};
      moduleInfo.subModules.forEach((subKey, subName) {
        bool subEnabled = enabled;
        String subLevel = level;
        if (roleKey == 'saglik_personeli' && moduleKey == 'hizmetler') {
          subEnabled = subKey == 'saglik_islemleri';
          subLevel = subEnabled ? 'editor' : 'viewer';
        } else if (roleKey == 'guvenlik' && moduleKey == 'hizmetler') {
          subEnabled = subKey == 'guvenlik_kapi';
          subLevel = subEnabled ? 'editor' : 'viewer';
        } else if (roleKey == 'depo' && moduleKey == 'hizmetler') {
          subEnabled = subKey == 'depo_satin_alma';
          subLevel = subEnabled ? 'editor' : 'viewer';
        } else if (roleKey == 'satin_alma' && moduleKey == 'hizmetler') {
          subEnabled = subKey == 'satin_alma_islemleri';
          subLevel = subEnabled ? 'editor' : 'viewer';
        }
        subPerms[subKey] = {'enabled': subEnabled, 'level': subLevel};
        moduleInfo.childrenOf(subKey).forEach((childKey, _) {
          subPerms[childKey] = {'enabled': subEnabled, 'level': subLevel};
        });
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

      if ([
        'genel_mudur',
        'mudur',
        'mudur_yardimcisi',
        'ogretmen',
        'rehber_ogretmen',
      ].contains(roleKey)) {
        enabled = true;
        level = 'editor';
      } else if (roleKey == 'muhasebe' &&
          (moduleKey == 'magaza' || moduleKey == 'kantin')) {
        enabled = true;
        level = 'editor';
      } else if (roleKey == 'kantin_personeli' && moduleKey == 'kantin') {
        enabled = true;
        level = 'editor';
      } else if (roleKey == 'magaza_sorumlusu' && moduleKey == 'magaza') {
        enabled = true;
        level = 'editor';
      } else if ((roleKey == 'depo' || roleKey == 'satin_alma') &&
          moduleKey == 'destek') {
        enabled = true;
        level = 'editor';
      } else if (roleKey == 'saglik_personeli' && moduleKey == 'destek') {
        enabled = true;
        level = 'editor';
      } else if (roleKey == 'guvenlik' && moduleKey == 'destek') {
        enabled = true;
        level = 'editor';
      }

      // Sub-modules + 3rd-level nested permissions
      Map<String, Map<String, dynamic>> subPerms = {};
      moduleInfo.subModules.forEach((subKey, subName) {
        bool subEnabled = enabled;
        String subLevel = level;
        if (roleKey == 'saglik_personeli' && moduleKey == 'destek') {
          subEnabled = subKey == 'saglik';
          subLevel = subEnabled ? 'editor' : 'viewer';
        } else if (roleKey == 'guvenlik' && moduleKey == 'destek') {
          subEnabled = subKey == 'guvenlik';
          subLevel = subEnabled ? 'editor' : 'viewer';
        } else if (roleKey == 'depo' && moduleKey == 'destek') {
          subEnabled = subKey == 'depo_satin_alma';
          subLevel = subEnabled ? 'editor' : 'viewer';
        } else if (roleKey == 'satin_alma' && moduleKey == 'destek') {
          subEnabled = subKey == 'satin_alma';
          subLevel = subEnabled ? 'editor' : 'viewer';
        } else if ((roleKey == 'ogretmen' || roleKey == 'rehber_ogretmen') &&
            moduleKey == 'destek' &&
            (subKey == 'depo_satin_alma' || subKey == 'satin_alma')) {
          subEnabled = false;
          subLevel = 'viewer';
        }
        subPerms[subKey] = {'enabled': subEnabled, 'level': subLevel};
        moduleInfo.childrenOf(subKey).forEach((childKey, _) {
          bool childEnabled = subEnabled;
          if (roleKey == 'ogretmen' &&
              moduleKey == 'araclar' &&
              (childKey == 'sinav_plan_olusturma' ||
                  childKey == 'sinav_raporu_alma' ||
                  childKey == 'sinav_tamamlama' ||
                  childKey == 'sinav_yayinlama')) {
            childEnabled = false;
          }
          subPerms[childKey] = {'enabled': childEnabled, 'level': subLevel};
        });
      });

      perms[moduleKey] = {
        'enabled': enabled,
        'level': level,
        'subModules': subPerms,
      };
    }

    return perms;
  }

  /// Get default teacher permissions for a role
  static Map<String, dynamic> getDefaultTeacherPermissions(String roleKey) {
    Map<String, dynamic> perms = {};

    for (var moduleKey in TeacherModules.allModuleKeys) {
      final moduleInfo = TeacherModules.getModule(moduleKey)!;
      bool enabled = false;
      String level = 'viewer';

      if ([
        'genel_mudur',
        'mudur',
        'mudur_yardimcisi',
        'ogretmen',
        'rehber_ogretmen',
      ].contains(roleKey)) {
        enabled = true;
        level = 'editor';
      }

      // Sub-modules + 3rd-level nested permissions
      Map<String, Map<String, dynamic>> subPerms = {};
      moduleInfo.subModules.forEach((subKey, subName) {
        subPerms[subKey] = {'enabled': enabled, 'level': level};
        moduleInfo.childrenOf(subKey).forEach((childKey, _) {
          bool childEnabled = enabled;
          if (roleKey == 'ogretmen' &&
              moduleKey == 'araclar' &&
              (childKey == 'sinav_plan_olusturma' ||
                  childKey == 'sinav_raporu_alma' ||
                  childKey == 'sinav_tamamlama' ||
                  childKey == 'sinav_yayinlama')) {
            childEnabled = false;
          }
          subPerms[childKey] = {'enabled': childEnabled, 'level': level};
        });
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

  /// Save / update a role template and sync to existing users of this role
  Future<void> saveRoleTemplate(
    String institutionId,
    String roleKey,
    Map<String, dynamic> data,
  ) async {
    await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection(collectionName)
        .doc(roleKey)
        .set({
          ...data,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    await syncRoleTemplateToUsers(institutionId, roleKey, data);
  }

  /// Sync updated role template permissions to all users with this role
  Future<void> syncRoleTemplateToUsers(
    String institutionId,
    String roleKey,
    Map<String, dynamic> templateData,
  ) async {
    try {
      final appPerms = templateData['appPermissions'] as Map<String, dynamic>?;
      final stPerms =
          templateData['schoolTypePermissions'] as Map<String, dynamic>?;
      final tpPerms =
          templateData['teacherPermissions'] as Map<String, dynamic>?;
      if (appPerms == null && stPerms == null && tpPerms == null) return;

      final roleSnap = await _firestore
          .collection('users')
          .where('institutionId', isEqualTo: institutionId)
          .where('role', isEqualTo: roleKey)
          .get();

      final titleSnap = await _firestore
          .collection('users')
          .where('institutionId', isEqualTo: institutionId)
          .where('title', isEqualTo: roleKey)
          .get();

      final allDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final d in roleSnap.docs) {
        allDocs[d.id] = d;
      }
      for (final d in titleSnap.docs) {
        allDocs[d.id] = d;
      }

      if (allDocs.isEmpty) return;

      WriteBatch batch = _firestore.batch();
      int count = 0;
      for (final doc in allDocs.values) {
        final userData = doc.data();
        if (userData['hasCustomPermissions'] == true) continue;

        final updates = <String, dynamic>{
          'role': roleKey,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (appPerms != null) updates['modulePermissions'] = appPerms;
        if (stPerms != null) updates['schoolTypeModulePermissions'] = stPerms;
        if (tpPerms != null) updates['teacherModulePermissions'] = tpPerms;

        batch.update(doc.reference, updates);
        count++;
        if (count >= 400) {
          await batch.commit();
          batch = _firestore.batch();
          count = 0;
        }
      }
      if (count > 0) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error syncing role template to users ($roleKey): $e');
    }
  }

  /// Load a single role template
  Future<Map<String, dynamic>?> loadRoleTemplate(
    String institutionId,
    String roleKey,
  ) async {
    final doc = await _firestore
        .collection('institutions')
        .doc(institutionId)
        .collection(collectionName)
        .doc(roleKey)
        .get();

    return doc.exists ? doc.data() : null;
  }

  /// Get all role templates for an institution
  Future<Map<String, Map<String, dynamic>>> getAllTemplates(
    String institutionId,
  ) async {
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
