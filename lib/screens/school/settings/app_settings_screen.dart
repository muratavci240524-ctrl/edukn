import 'package:flutter/material.dart';
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
          if (appSettings != null && appSettings['disabledModules'] != null) {
            _disabledModules = List<String>.from(appSettings['disabledModules']);
          }
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
    try {
      await FirebaseFirestore.instance.collection('schools').doc(_schoolId).set({
        'appSettings': {
          'disabledModules': _disabledModules,
        }
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ayarlar başarıyla kaydedildi.'), backgroundColor: Colors.green),
        );
        // Otomatik olarak bir önceki sayfaya dön
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving app settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ayarlar kaydedilirken hata oluştu.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      appBar: AppBar(
        title: const Text('Uygulama Ayarları'),
        elevation: 0,
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
      itemCount: modules.length,
      itemBuilder: (context, index) {
        final module = modules[index];
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
}
