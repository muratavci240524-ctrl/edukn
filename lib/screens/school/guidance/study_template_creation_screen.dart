import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/guidance/study_template_model.dart';
import '../../../services/guidance_service.dart';
import '../../../services/assessment_service.dart';

class StudyTemplateCreationScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const StudyTemplateCreationScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<StudyTemplateCreationScreen> createState() =>
      _StudyTemplateCreationScreenState();
}

class _StudyTemplateCreationScreenState
    extends State<StudyTemplateCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final GuidanceService _guidanceService = GuidanceService();
  final AssessmentService _assessmentService = AssessmentService();

  bool _isLoading = false;
  List<String> _availableBranches = [];

  String _templateId = '';
  // Schedule Data: Day -> List of Selected Branches
  final Map<String, List<String>> _schedule = {
    'Pazartesi': [],
    'Salı': [],
    'Çarşamba': [],
    'Perşembe': [],
    'Cuma': [],
    'Cumartesi': [],
    'Pazar': [],
  };

  // Day Order for UI
  final List<String> _days = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    final branches = await _assessmentService.getAvailableBranches(
      widget.institutionId,
    );
    if (mounted) {
      setState(() {
        _availableBranches = branches;
      });
    }
  }

  // --- Assignments ---

  Future<void> _startAssignmentProcess(String type) async {
    if (!_formKey.currentState!.validate()) return;
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lütfen şablon adını giriniz.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }

    final template = StudyTemplate(
      id: _templateId,
      institutionId: widget.institutionId,
      name: _nameController.text.trim(),
      schedule: _schedule,
      createdAt: DateTime.now(),
    );

    if (type == 'student') {
      _showStudentSelectionDialog(template);
    } else if (type == 'class') {
      _showClassSelectionDialog(template);
    } else if (type == 'all') {
      _confirmAssignAll(template);
    } else if (type == 'save') {
      await _performSaveAndAssign(template);
    }
  }

  // This function performs the actual Save & Assign
  Future<void> _performSaveAndAssign(
    StudyTemplate template, {
    List<String>? studentIds,
    String? className,
    bool isAll = false,
  }) async {
    setState(() => _isLoading = true);

    try {
      final String idToUse = _templateId.isNotEmpty
          ? _templateId
          : FirebaseFirestore.instance
                .collection('institutions')
                .doc(widget.institutionId)
                .collection('study_templates')
                .doc()
                .id;

      final newTemplate = StudyTemplate(
        id: idToUse,
        institutionId: template.institutionId,
        name: template.name,
        schedule: template.schedule,
        createdAt: template.createdAt,
      );

      await _guidanceService.saveStudyTemplate(newTemplate);

      if (mounted) {
        setState(() {
          _templateId = idToUse;
        });
      }

      // Check if it's just a save operation
      if (!isAll &&
          className == null &&
          (studentIds == null || studentIds.isEmpty)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Şablon başarıyla kaydedildi.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              backgroundColor: Colors.teal.shade600,
            ),
          );
        }
        Navigator.pop(context);
        return;
      }

      // 2. Assign
      if (isAll) {
        await _guidanceService.assignTemplateToAll(
          widget.institutionId,
          widget.schoolTypeId,
          newTemplate.id,
          newTemplate.name,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Şablon tüm okula atandı.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              backgroundColor: Colors.teal.shade600,
            ),
          );
        }
      } else if (className != null) {
        await _guidanceService.assignTemplateToClass(
          widget.institutionId,
          widget.schoolTypeId,
          newTemplate.id,
          newTemplate.name,
          className,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Şablon $className şubesine atandı.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              backgroundColor: Colors.teal.shade600,
            ),
          );
        }
      } else if (studentIds != null && studentIds.isNotEmpty) {
        await _guidanceService.assignTemplateToStudents(
          widget.institutionId,
          newTemplate.id,
          newTemplate.name,
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
      }

      Navigator.pop(context); // Close Screen
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e', style: GoogleFonts.inter(fontWeight: FontWeight.w600)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showStudentSelectionDialog(StudyTemplate template) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _StudentSelectorDialog(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          onConfirm: (selectedIds) async {
            Navigator.pop(ctx);
            if (selectedIds.isEmpty) return;
            await _performSaveAndAssign(template, studentIds: selectedIds);
          },
        );
      },
    );
  }

  Future<void> _showClassSelectionDialog(StudyTemplate template) async {
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
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(20),
            width: 400,
            height: 450,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Şube Seçiniz',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo.shade900),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: classes.length,
                      separatorBuilder: (c, idx) => const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (c, i) {
                        return ListTile(
                          title: Text(classes[i], style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _performSaveAndAssign(template, className: classes[i]);
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _confirmAssignAll(StudyTemplate template) async {
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
                decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.people_alt_rounded, color: Colors.orange, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                'Tüm Okula Ata',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              Text(
                'Bu şablonu bu okul türündeki TÜM aktif öğrencilere atamak istediğinize emin misiniz? Bu işlem toplu bir işlemdir.',
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
      await _performSaveAndAssign(template, isAll: true);
    }
  }

  void _modifyDay(String day) async {
    final selected = Set<String>.from(_schedule[day] ?? []);
    String searchQuery = '';

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredBranches = _availableBranches
                .where(
                  (b) => b.toLowerCase().contains(searchQuery.toLowerCase()),
                )
                .toList();

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
                      '$day - Ders Seçimi',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo.shade900),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Ders Ara...',
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
                      onChanged: (val) {
                        setDialogState(() {
                          searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: ListView.builder(
                          itemCount: filteredBranches.length,
                          itemBuilder: (context, index) {
                            final branch = filteredBranches[index];
                            final isSelected = selected.contains(branch);
                            return CheckboxListTile(
                              activeColor: Colors.indigo,
                              title: Text(branch, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                              value: isSelected,
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) {
                                    selected.add(branch);
                                  } else {
                                    selected.remove(branch);
                                  }
                                });
                              },
                            );
                          },
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
                        child: Text('Tamam', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    setState(() {
      _schedule[day] = selected.toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          title: Text('Şablon Kaydediliyor...', style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.indigo),
              SizedBox(height: 16),
              Text('Değişiklikler sunucuya kaydediliyor, lütfen bekleyin...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(
          'Yeni Şablon Oluştur',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        labelText: 'Şablon Adı *',
                        labelStyle: const TextStyle(color: Colors.indigo),
                        filled: true,
                        fillColor: Colors.white,
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
                        prefixIcon: const Icon(Icons.title, color: Colors.indigo),
                        hintText: 'Örn: 8. Sınıf Sayısal Şablonu',
                      ),
                      validator: (v) =>
                          v!.trim().isEmpty ? 'Şablon adı girilmesi zorunludur.' : null,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Haftalık Ders Programı',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._days.map((day) => _buildDayCard(day)).toList(),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, -2))],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Şablon Kayıt ve Atama İşlemleri',
                    style: GoogleFonts.inter(color: Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _startAssignmentProcess('save'),
                    icon: const Icon(Icons.save, color: Colors.white, size: 20),
                    label: Text(
                      'Şablonu Kaydet',
                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade600,
                      elevation: 0,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.person, color: Colors.white, size: 16),
                          label: Text('Öğrenciye', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _startAssignmentProcess('student'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.class_, color: Colors.white, size: 16),
                          label: Text('Şubeye', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _startAssignmentProcess('class'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.people, color: Colors.white, size: 16),
                          label: Text('Herkes', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _startAssignmentProcess('all'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(String day) {
    final subjects = _schedule[day] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(day, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo.shade900)),
        subtitle: Text(
          subjects.isEmpty
              ? 'Ders seçilmedi'
              : '${subjects.length} ders seçildi',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: subjects.isEmpty ? Colors.red.shade700 : Colors.teal.shade700,
          ),
        ),
        trailing: Container(
          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
          child: IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.indigo),
            onPressed: () => _modifyDay(day),
          ),
        ),
        children: [
          if (subjects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: subjects
                    .map(
                      (s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          border: Border.all(color: Colors.indigo.shade100),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              s,
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _schedule[day]!.remove(s);
                                });
                              },
                              child: const Icon(Icons.close_rounded, size: 14, color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _modifyDay(day),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: Text('Dersleri Düzenle', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.indigo,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Helper Dialog for Student Selection
class _StudentSelectorDialog extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final Function(List<String>) onConfirm;

  const _StudentSelectorDialog({
    required this.institutionId,
    required this.schoolTypeId,
    required this.onConfirm,
  });

  @override
  State<_StudentSelectorDialog> createState() => _StudentSelectorDialogState();
}

class _StudentSelectorDialogState extends State<_StudentSelectorDialog> {
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
                  onPressed: () => widget.onConfirm(_selected.toList()),
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
