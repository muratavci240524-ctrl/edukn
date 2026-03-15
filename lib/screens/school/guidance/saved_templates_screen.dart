import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../models/guidance/study_template_model.dart';
import '../../../services/guidance_service.dart';

class SavedTemplatesScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const SavedTemplatesScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<SavedTemplatesScreen> createState() => _SavedTemplatesScreenState();
}

class _SavedTemplatesScreenState extends State<SavedTemplatesScreen> {
  final GuidanceService _guidanceService = GuidanceService();

  void _confirmDelete(StudyTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Şablonu Sil'),
        content: Text(
          '${template.name} şablonunu silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _guidanceService.deleteStudyTemplate(
        widget.institutionId,
        template.id,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Şablon silindi.')));
    }
  }

  void _showAssignmentOptions(StudyTemplate template) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Şablon Ata: ${template.name}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.person, color: Colors.orange),
              title: Text('Öğrenciye Ata'),
              onTap: () {
                Navigator.pop(ctx);
                _showStudentSelectionDialog(template);
              },
            ),
            ListTile(
              leading: Icon(Icons.class_, color: Colors.blue),
              title: Text('Şubeye Ata'),
              onTap: () {
                Navigator.pop(ctx);
                _showClassSelectionDialog(template);
              },
            ),
            ListTile(
              leading: Icon(Icons.people, color: Colors.red),
              title: Text('Tüm Okula Ata'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmAssignAll(template);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- Assignment Logic (Duplicated/Adapted from Creation Screen) ---

  Future<void> _assignStudents(
    StudyTemplate template,
    List<String> studentIds,
  ) async {
    try {
      await _guidanceService.assignTemplateToStudents(
        widget.institutionId,
        template.id,
        template.name,
        studentIds,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Şablon öğrencilere atandı.')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _assignClasses(
    StudyTemplate template,
    List<String> classNames,
  ) async {
    try {
      int successCount = 0;
      for (var className in classNames) {
        await _guidanceService.assignTemplateToClass(
          widget.institutionId,
          widget.schoolTypeId,
          template.id,
          template.name,
          className,
        );
        successCount++;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Şablon $successCount şubeye atandı.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _assignAll(StudyTemplate template) async {
    try {
      await _guidanceService.assignTemplateToAll(
        widget.institutionId,
        widget.schoolTypeId,
        template.id,
        template.name,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Şablon tüm okula atandı.')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  // --- Dialogs ---

  void _showStudentSelectionDialog(StudyTemplate template) {
    showDialog(
      context: context,
      builder: (ctx) => StudentSelectorDialog(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        onConfirm: (ids) => _assignStudents(template, ids),
      ),
    );
  }

  void _showClassSelectionDialog(StudyTemplate template) async {
    // Fetch classes
    final query = await FirebaseFirestore.instance
        .collection('students')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('isActive', isEqualTo: true)
        .get();

    final classes =
        query.docs
            .map((d) => d['className'] as String? ?? '')
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    showDialog(
      context: context,
      builder: (ctx) => _ClassSelectorDialog(
        classes: classes,
        onConfirm: (selectedClasses) {
          _assignClasses(template, selectedClasses);
        },
      ),
    );
  }

  void _confirmAssignAll(StudyTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tüm Okula Ata'),
        content: Text(
          'Bu şablonu TÜM öğrencilere atamak istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Onayla', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _assignAll(template);
    }
  }

  void _showSchedulePreview(StudyTemplate template) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(template.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: template.schedule.entries.map((e) {
              if (e.value.isEmpty) return SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.key, style: TextStyle(fontWeight: FontWeight.bold)),
                    Wrap(
                      spacing: 4,
                      children: e.value
                          .map(
                            (s) => Chip(
                              label: Text(s, style: TextStyle(fontSize: 10)),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Kapat')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Kayıtlı Şablonlar', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<StudyTemplate>>(
        stream: _guidanceService.getStudyTemplates(widget.institutionId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
          }
          final templates = snapshot.data ?? [];

          if (templates.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_open,
                    size: 80,
                    color: Colors.grey.shade300,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Henüz kayıtlı şablon yok.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.all(16),
            itemCount: templates.length,
            separatorBuilder: (context, index) => SizedBox(height: 12),
            itemBuilder: (context, index) {
              final t = templates[index];
              final dateStr = DateFormat(
                'dd.MM.yyyy HH:mm',
              ).format(t.createdAt);

              return Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.assignment, color: Colors.indigo),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.name,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Oluşturulma: $dateStr',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _confirmDelete(t),
                          ),
                        ],
                      ),
                      Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            icon: Icon(Icons.visibility_outlined),
                            label: Text('İçeriği Gör'),
                            onPressed: () => _showSchedulePreview(t),
                          ),
                          ElevatedButton.icon(
                            icon: Icon(Icons.send),
                            label: Text('Şablonu Ata'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _showAssignmentOptions(t),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class StudentSelectorDialog extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final Function(List<String>) onConfirm;

  const StudentSelectorDialog({
    required this.institutionId,
    required this.schoolTypeId,
    required this.onConfirm,
  });

  @override
  State<StudentSelectorDialog> createState() => _StudentSelectorDialogState();
}

class _StudentSelectorDialogState extends State<StudentSelectorDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _filtered = [];
  Set<String> _selected = {};
  String _search = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final q = await FirebaseFirestore.instance
        .collection('students')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('isActive', isEqualTo: true)
        .get();

    final list = q.docs.map((d) {
      final name =
          d['fullName'] ?? '${d['name'] ?? ''} ${d['surname'] ?? ''}'.trim();
      return {'id': d.id, 'name': name, 'class': d['className'] ?? ''};
    }).toList();

    list.sort((a, b) => a['class'].compareTo(b['class']));

    if (mounted) {
      setState(() {
        _allStudents = list;
        _filtered = list;
        _loading = false;
      });
    }
  }

  void _filter() {
    setState(() {
      _filtered = _allStudents
          .where((s) => s['name'].toLowerCase().contains(_search.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Öğrenci Seç'),
      content: Container(
        width: 400,
        height: 500,
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Ara...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) {
                _search = v;
                _filter();
              },
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_selected.length}/${_allStudents.length} Seçildi'),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selected.length == _filtered.length)
                        _selected.clear();
                      else
                        _selected = _filtered
                            .map((e) => e['id'] as String)
                            .toSet();
                    });
                  },
                  child: Text('Tümünü Seç/Sil'),
                ),
              ],
            ),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (c, i) {
                        final s = _filtered[i];
                        final sel = _selected.contains(s['id']);
                        return CheckboxListTile(
                          value: sel,
                          title: Text(s['name']),
                          subtitle: Text(s['class']),
                          dense: true,
                          onChanged: (v) {
                            setState(() {
                              if (v == true)
                                _selected.add(s['id']);
                              else
                                _selected.remove(s['id']);
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('İptal'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onConfirm(_selected.toList());
            Navigator.pop(context);
          },
          child: Text('Ata'),
        ),
      ],
    );
  }
}

class _ClassSelectorDialog extends StatefulWidget {
  final List<String> classes;
  final Function(List<String>) onConfirm;

  const _ClassSelectorDialog({required this.classes, required this.onConfirm});

  @override
  State<_ClassSelectorDialog> createState() => _ClassSelectorDialogState();
}

class _ClassSelectorDialogState extends State<_ClassSelectorDialog> {
  Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Şube Seçiniz'),
      content: Container(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selected.length == widget.classes.length) {
                        _selected.clear();
                      } else {
                        _selected = Set.from(widget.classes);
                      }
                    });
                  },
                  child: Text('Tümünü Seç/Kaldır'),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: widget.classes.length,
                itemBuilder: (c, i) {
                  final className = widget.classes[i];
                  final isSelected = _selected.contains(className);
                  return CheckboxListTile(
                    title: Text(className),
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selected.add(className);
                        } else {
                          _selected.remove(className);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('İptal'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onConfirm(_selected.toList());
            Navigator.pop(context);
          },
          child: Text('Ata'),
        ),
      ],
    );
  }
}
