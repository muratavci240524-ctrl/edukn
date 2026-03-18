import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/shift_service.dart';

class ShiftManagementScreen extends StatefulWidget {
  const ShiftManagementScreen({super.key});

  @override
  State<ShiftManagementScreen> createState() => _ShiftManagementScreenState();
}

class _ShiftManagementScreenState extends State<ShiftManagementScreen>
    with SingleTickerProviderStateMixin {
  final ShiftService _service = ShiftService();
  late TabController _tabController;

  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;
  String? _myInstitutionId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadTemplates();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() => _loading = true);
    try {
      if (_myInstitutionId == null) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.email != null) {
          final domain = user.email!.split('@')[1];
          _myInstitutionId = domain.split('.')[0].toUpperCase();
        }
      }
      
      if (_myInstitutionId != null) {
        final templates = await _service.getShiftTemplates(_myInstitutionId!);
        setState(() => _templates = templates);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesai ve Vardiya Yönetimi'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Vardiya Şablonları'),
            Tab(text: 'Personel Atama'),
            Tab(text: 'Fazla Mesai'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTemplatesTab(),
          _buildAssignmentTab(),
          _buildOvertimeTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: _showAddTemplateDialog,
              child: const Icon(Icons.add),
              tooltip: 'Yeni Vardiya Şablonu',
            )
          : null,
    );
  }

  // ==================== TAB 1: VARDIYA ŞABLONLARI ====================
  Widget _buildTemplatesTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_templates.isEmpty) {
      return const Center(child: Text('Henüz vardiya şablonu eklenmedi.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _templates.length,
      itemBuilder: (context, index) {
        final template = _templates[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.orange.shade100,
              child: const Icon(Icons.schedule, color: Colors.orange),
            ),
            title: Text(template['name']),
            subtitle: Text(
              '${template['startTime']} - ${template['endTime']} (Mola: ${template['breakDuration']} dk)',
            ),
            trailing: PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                const PopupMenuItem(value: 'delete', child: Text('Sil')),
              ],
              onSelected: (value) {
                if (value == 'delete') {
                  _deleteTemplate(template['id']);
                } else if (value == 'edit') {
                  _showEditTemplateDialog(template);
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _showAddTemplateDialog() {
    final nameController = TextEditingController();
    final startController = TextEditingController(text: '08:00');
    final endController = TextEditingController(text: '17:00');
    final breakController = TextEditingController(text: '60');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Vardiya Şablonu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Şablon Adı (örn: Gündüz Vardiyası)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: startController,
              decoration: const InputDecoration(
                labelText: 'Başlangıç Saati (HH:MM)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: endController,
              decoration: const InputDecoration(
                labelText: 'Bitiş Saati (HH:MM)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: breakController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Mola Süresi (dakika)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _service.createShiftTemplate(
                  name: nameController.text,
                  startTime: startController.text,
                  endTime: endController.text,
                  breakDuration: int.parse(breakController.text),
                  institutionId: _myInstitutionId!,
                );
                Navigator.pop(context);
                _loadTemplates();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vardiya şablonu oluşturuldu')),
                );
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Hata: $e')));
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _showEditTemplateDialog(Map<String, dynamic> template) {
    final nameController = TextEditingController(text: template['name']);
    final startController = TextEditingController(text: template['startTime']);
    final endController = TextEditingController(text: template['endTime']);
    final breakController = TextEditingController(
      text: template['breakDuration'].toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vardiya Düzenle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Şablon Adı'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: startController,
              decoration: const InputDecoration(labelText: 'Başlangıç'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: endController,
              decoration: const InputDecoration(labelText: 'Bitiş'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: breakController,
              decoration: const InputDecoration(labelText: 'Mola (dk)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _service.updateShiftTemplate(template['id'], {
                  'name': nameController.text,
                  'startTime': startController.text,
                  'endTime': endController.text,
                  'breakDuration': int.parse(breakController.text),
                });
                Navigator.pop(context);
                _loadTemplates();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Güncellendi')));
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Hata: $e')));
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTemplate(String id) async {
    try {
      await _service.deleteShiftTemplate(id);
      _loadTemplates();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Silindi')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  // ==================== TAB 2: PERSONEL ATAMA ====================
  Widget _buildAssignmentTab() {
    return const Center(
      child: Text('Personel atama özelliği geliştiriliyor...'),
    );
  }

  // ==================== TAB 3: FAZLA MESAİ ====================
  Widget _buildOvertimeTab() {
    return const Center(child: Text('Fazla mesai raporu geliştiriliyor...'));
  }
}
