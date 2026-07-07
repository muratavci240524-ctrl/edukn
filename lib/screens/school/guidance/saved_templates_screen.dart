import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
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
  String _searchQuery = '';

  void _confirmDelete(StudyTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                'Şablonu Sil',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              Text(
                '${template.name} şablonunu silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Evet, Sil', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true) {
      await _guidanceService.deleteStudyTemplate(
        widget.institutionId,
        template.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Şablon silindi.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  void _showAssignmentOptions(StudyTemplate template) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Şablon Ata',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
              ),
              Text(
                '${template.name} şablonunu hedef kitleye tanımlayın.',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.person, color: Colors.orange),
                ),
                title: Text('Öğrenciye Ata', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('Seçili öğrencilere özel ders programı atar.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  _showStudentSelectionDialog(template);
                },
              ),
              const Divider(height: 12, indent: 48),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.class_, color: Colors.blue),
                ),
                title: Text('Şubeye Ata', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('Belirli şubelerdeki tüm öğrencilere atar.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  _showClassSelectionDialog(template);
                },
              ),
              const Divider(height: 12, indent: 48),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.people, color: Colors.red),
                ),
                title: Text('Tüm Okula Ata', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('Bu okul türündeki tüm aktif öğrencilere atar.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmAssignAll(template);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _assignStudents(StudyTemplate template, List<String> studentIds) async {
    try {
      await _guidanceService.assignTemplateToStudents(
        widget.institutionId,
        template.id,
        template.name,
        studentIds,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Şablon öğrencilere atandı.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            backgroundColor: Colors.teal.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e', style: GoogleFonts.inter(fontWeight: FontWeight.w600)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _assignClasses(StudyTemplate template, List<String> classNames) async {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Şablon $successCount şubeye başarıyla atandı.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            backgroundColor: Colors.teal.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e', style: GoogleFonts.inter(fontWeight: FontWeight.w600)), backgroundColor: Colors.red),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Şablon tüm okula başarıyla atandı.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            backgroundColor: Colors.teal.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e', style: GoogleFonts.inter(fontWeight: FontWeight.w600)), backgroundColor: Colors.red),
        );
      }
    }
  }

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
    final query = await FirebaseFirestore.instance
        .collection('students')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('isActive', isEqualTo: true)
        .get();

    final classes = query.docs
        .map((d) => d['className'] as String? ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    if (mounted) {
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
  }

  void _confirmAssignAll(StudyTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.people_alt_rounded, color: Colors.red, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                'Tüm Okula Ata',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              Text(
                'Bu şablonu bu okul türündeki TÜM öğrencilere atamak istediğinize emin misiniz? Bu işlem toplu bir işlemdir.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Onayla', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true) {
      await _assignAll(template);
    }
  }

  void _showSchedulePreview(StudyTemplate template) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxHeight: 500, maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.date_range_rounded, color: Colors.indigo),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.name,
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo.shade900),
                        ),
                        Text(
                          'Haftalık Ders Planı Önizleme',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: template.schedule.entries.map((e) {
                      if (e.value.isEmpty) return const SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.indigo.shade100, borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                e.key.substring(0, 3),
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.indigo.shade900),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: e.value
                                    .map(
                                      (s) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(color: Colors.grey.shade300),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          s,
                                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Kapat', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(
          'Kayıtlı Şablonlar',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.white,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Şablonlarda Ara...',
                prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.indigo, width: 2),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<List<StudyTemplate>>(
              stream: _guidanceService.getStudyTemplates(widget.institutionId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.indigo));
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Hata: ${snapshot.error}', style: GoogleFonts.inter(color: Colors.red)));
                }
                final allTemplates = snapshot.data ?? [];
                final templates = allTemplates.where((t) {
                  return t.name.toLowerCase().contains(_searchQuery.toLowerCase());
                }).toList();

                if (templates.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder_open_rounded,
                          size: 80,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty ? 'Henüz kayıtlı şablon bulunmamaktadır.' : 'Aramanıza uygun şablon bulunamadı.',
                          style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: templates.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final t = templates[index];
                    final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(t.createdAt);

                    // Count total classes scheduled
                    int lessonCount = 0;
                    t.schedule.forEach((day, lessons) {
                      lessonCount += lessons.length;
                    });

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
                                  child: const Icon(Icons.school_rounded, color: Colors.indigo),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.name,
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Oluşturulma: $dateStr • $lessonCount Ders Tanımlı',
                                        style: GoogleFonts.inter(
                                          color: Colors.grey.shade500,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _confirmDelete(t),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton.icon(
                                  icon: const Icon(Icons.visibility_outlined, size: 18),
                                  label: Text('Planı Gör', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                                  onPressed: () => _showSchedulePreview(t),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.grey.shade700,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.send, size: 16, color: Colors.white),
                                  label: Text('Şablonu Ata', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          ),
        ],
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
      final name = d['fullName'] ?? '${d['name'] ?? ''} ${d['surname'] ?? ''}'.trim();
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        width: 400,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Öğrenci Seçiniz',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo.shade900),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                hintText: 'Öğrenci Ara...',
                prefixIcon: const Icon(Icons.search, color: Colors.indigo),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.indigo, width: 1.5),
                ),
              ),
              onChanged: (v) {
                _search = v;
                _filter();
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selected.length}/${_allStudents.length} Seçildi',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selected.length == _filtered.length) {
                        _selected.clear();
                      } else {
                        _selected = _filtered.map((e) => e['id'] as String).toSet();
                      }
                    });
                  },
                  child: Text('Tümünü Seç/Sil', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: _filtered.isEmpty
                          ? const Center(child: Text('Öğrenci bulunamadı.', style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              itemCount: _filtered.length,
                              itemBuilder: (c, i) {
                                final s = _filtered[i];
                                final sel = _selected.contains(s['id']);
                                return CheckboxListTile(
                                  value: sel,
                                  title: Text(s['name'], style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                                  subtitle: Text('Sınıf/Şube: ${s['class']}', style: GoogleFonts.inter(fontSize: 11)),
                                  dense: true,
                                  activeColor: Colors.indigo,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selected.add(s['id']);
                                      } else {
                                        _selected.remove(s['id']);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    widget.onConfirm(_selected.toList());
                    Navigator.pop(context);
                  },
                  child: Text('Ata', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        width: 400,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Şube Seçiniz',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo.shade900),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selected.length}/${widget.classes.length} Şube Seçildi',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                ),
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
                  child: Text('Tümünü Seç/Kaldır', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ListView.builder(
                  itemCount: widget.classes.length,
                  itemBuilder: (c, i) {
                    final className = widget.classes[i];
                    final isSelected = _selected.contains(className);
                    return CheckboxListTile(
                      title: Text(className, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                      value: isSelected,
                      activeColor: Colors.indigo,
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
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    widget.onConfirm(_selected.toList());
                    Navigator.pop(context);
                  },
                  child: Text('Ata', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
