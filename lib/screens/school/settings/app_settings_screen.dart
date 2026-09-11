import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../constants/app_modules.dart';
import '../../../services/user_permission_service.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({Key? key}) : super(key: key);

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _isLoading = true;
  String? _schoolId;
  String? _institutionId;
  List<String> _disabledModules = [];
  String _teacherAnnouncementMode = 'approval_required';
  bool _notifyTeacherMissingAttendance = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final userData = await UserPermissionService.loadUserData();
      final instId = await UserPermissionService.resolveInstitutionId(user.email!, userData: userData);
      
      if (instId.isNotEmpty) {
        final schoolQuery = await FirebaseFirestore.instance
            .collection('schools')
            .where('institutionId', isEqualTo: instId)
            .limit(1)
            .get();

        if (schoolQuery.docs.isNotEmpty) {
          final doc = schoolQuery.docs.first;
          final data = doc.data();
          _schoolId = doc.id;
          _institutionId = instId;
          
          final appSettings = data['appSettings'] as Map<String, dynamic>?;
          if (appSettings != null) {
            if (appSettings['disabledModules'] != null) {
              _disabledModules = List<String>.from(appSettings['disabledModules']);
            }
            if (appSettings['notifyTeacherMissingAttendance'] != null) {
              _notifyTeacherMissingAttendance = appSettings['notifyTeacherMissingAttendance'] == true;
            }
            if (appSettings['teacherAnnouncementMode'] != null) {
              _teacherAnnouncementMode = appSettings['teacherAnnouncementMode'].toString();
            }
          }

          // Öğretmen duyuru yetkisi (alt koleksiyondan kontrol, varsa öncelikli)
          try {
            final annSettingsDoc = await FirebaseFirestore.instance
                .collection('schools')
                .doc(_schoolId)
                .collection('settings')
                .doc('announcements')
                .get();
            if (annSettingsDoc.exists) {
              _teacherAnnouncementMode = annSettingsDoc.data()?['teacherAnnouncementMode'] ?? _teacherAnnouncementMode;
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error loading app settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (_schoolId == null) return;
    
    setState(() => _isLoading = true);
    bool mainSaved = false;
    Object? saveError;

    // 1. Ana okul belgesindeki appSettings'i kaydet
    try {
      await FirebaseFirestore.instance.collection('schools').doc(_schoolId).set({
        'appSettings': {
          'disabledModules': _disabledModules,
          'notifyTeacherMissingAttendance': _notifyTeacherMissingAttendance,
          'teacherAnnouncementMode': _teacherAnnouncementMode,
        }
      }, SetOptions(merge: true));
      mainSaved = true;
    } catch (e) {
      debugPrint('Error saving appSettings with set: $e');
      try {
        await FirebaseFirestore.instance.collection('schools').doc(_schoolId).update({
          'appSettings.disabledModules': _disabledModules,
          'appSettings.notifyTeacherMissingAttendance': _notifyTeacherMissingAttendance,
          'appSettings.teacherAnnouncementMode': _teacherAnnouncementMode,
        });
        mainSaved = true;
      } catch (e2) {
        debugPrint('Error saving appSettings with update: $e2');
        saveError = e2;
      }
    }

    // 2. Alt koleksiyon (settings/announcements) - bağımsız kayıt
    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(_schoolId)
          .collection('settings')
          .doc('announcements')
          .set({
        'teacherAnnouncementMode': _teacherAnnouncementMode,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (annErr) {
      debugPrint('Notice: settings/announcements subcollection save skipped: $annErr');
    }

    if (mounted) {
      setState(() => _isLoading = false);
      if (mainSaved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ayarlar başarıyla kaydedildi.'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      } else {
        debugPrint('Error saving app settings: $saveError');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saveError != null && saveError.toString().contains('permission-denied')
                ? 'Yetki hatası: Bu ayarları kaydetmek için yönetici yetkisi gerekmektedir.'
                : 'Ayarlar kaydedilirken hata oluştu.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _toggleModule(String moduleKey, bool isEnabled) {
    setState(() {
      if (isEnabled) {
        _disabledModules.remove(moduleKey);
      } else {
        if (!_disabledModules.contains(moduleKey)) {
          _disabledModules.add(moduleKey);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EduknAppBar(
        title: 'Uygulama Ayarları',
        actions: [
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save),
                label: const Text('Kaydet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.indigo,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _schoolId == null
              ? const Center(child: Text('Kurum bilgisi bulunamadı.'))
              : _buildModulesList(),
    );
  }

  Widget _buildModulesList() {
    final modules = AppModules.modules.values.toList();
    final isMobile = MediaQuery.of(context).size.width < 768;
    
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 24),
      itemCount: modules.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildTeacherAnnouncementSetting();
        }
        final module = modules[index - 1];
        // Sistem ayarları kapatılamaz
        if (module.key == 'sistem_ayarlari') return const SizedBox.shrink();
        
        final isModuleEnabled = !_disabledModules.contains(module.key);
        
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
            border: Border.all(color: isModuleEnabled ? module.color.withOpacity(0.3) : Colors.grey.shade300, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isModuleEnabled ? module.color.withOpacity(0.05) : Colors.grey.shade50,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isModuleEnabled ? module.color.withOpacity(0.2) : Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(module.icon, color: isModuleEnabled ? module.color : Colors.grey.shade600, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            module.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: isModuleEnabled ? Colors.indigo.shade900 : Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            module.description,
                            style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Transform.scale(
                      scale: 1.1,
                      child: Switch(
                        value: isModuleEnabled,
                        activeColor: module.color,
                        onChanged: (val) => _toggleModule(module.key, val),
                      ),
                    ),
                  ],
                ),
              ),
              
              // DIVIDER
              Divider(height: 1, color: Colors.grey.shade200),
              
              // SUB-MODULES LIST
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: module.subModules.entries.map((subModule) {
                    final subModuleKey = '${module.key}.${subModule.key}';
                    final isSubModuleEnabled = !_disabledModules.contains(subModuleKey);
                    
                    return Opacity(
                      opacity: isModuleEnabled ? 1.0 : 0.5,
                      child: InkWell(
                        onTap: isModuleEnabled ? () => _toggleModule(subModuleKey, !isSubModuleEnabled) : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              // Ağaç çizgisi ve nokta (Tree structure)
                              Container(
                                width: 20,
                                height: 2,
                                color: Colors.grey.shade300,
                                margin: const EdgeInsets.only(right: 12),
                              ),
                              Expanded(
                                child: Text(
                                  subModule.value,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: isSubModuleEnabled ? FontWeight.w600 : FontWeight.normal,
                                    color: isSubModuleEnabled ? Colors.black87 : Colors.grey.shade500,
                                  ),
                                ),
                              ),
                              Transform.scale(
                                scale: 0.85,
                                child: Switch(
                                  value: isSubModuleEnabled,
                                  activeColor: module.color,
                                  onChanged: isModuleEnabled ? (val) => _toggleModule(subModuleKey, val) : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  Widget _buildTeacherAnnouncementSetting() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.campaign, color: Colors.blue.shade700, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ÖĞRETMEN DUYURU YETKİSİ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Öğretmenlerin duyuru oluşturma yetkisi',
                        style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _teacherAnnouncementMode,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'direct',
                  child: Text('Onaysız Paylaşabilir (Direkt Yayınlanır)'),
                ),
                DropdownMenuItem(
                  value: 'approval_required',
                  child: Text('Yönetici Onayına Düşsün (Onay ile Yayınlanır)'),
                ),
                DropdownMenuItem(
                  value: 'disabled',
                  child: Text('Kapalı (Duyuru Oluşturamaz)'),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _teacherAnnouncementMode = val);
                }
              },
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.event_busy_rounded, color: Colors.amber.shade800, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOKLAMA ALINMADIĞINDA BİLDİRİM GİTSİN',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Öğretmen derse girdikten 5 dakika sonra yoklama almamışsa sistem otomatik yoklama uyarısı bildirimi gönderir.',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _notifyTeacherMissingAttendance,
                  activeColor: Colors.indigo,
                  onChanged: (val) {
                    setState(() => _notifyTeacherMissingAttendance = val);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
