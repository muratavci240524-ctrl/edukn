import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lütfen şablon adını giriniz.')));
      return;
    }

    // Prepare template object (ID will be assigned later or now for reference)
    // We generate a local ID to pass around, but definitive save happens last.

    // Let's create the object.
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
      // 1. Save Template
      // Reuse ID if exists, OR generate new one
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Şablon başarıyla kaydedildi.')));
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
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Şablon tüm okula atandı.')));
      } else if (className != null) {
        await _guidanceService.assignTemplateToClass(
          widget.institutionId,
          widget.schoolTypeId,
          newTemplate.id,
          newTemplate.name,
          className,
        );
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Şablon $className şubesine atandı.')),
          );
      } else if (studentIds != null && studentIds.isNotEmpty) {
        await _guidanceService.assignTemplateToStudents(
          widget.institutionId,
          newTemplate.id,
          newTemplate.name,
          studentIds,
        );
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Şablon öğrencilere atandı.')));
      }

      Navigator.pop(context); // Close Screen
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
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

    final classes =
        query.docs
            .map((d) => d['className'] as String? ?? '')
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Şube Seçiniz'),
        content: Container(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: classes.length,
            itemBuilder: (c, i) {
              return ListTile(
                title: Text(classes[i]),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _performSaveAndAssign(template, className: classes[i]);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAssignAll(StudyTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tüm Okula Ata'),
        content: Text(
          'Bu şablonu bu okul türündeki TÜM aktif öğrencilere atamak istediğinize emin misiniz?',
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

            return AlertDialog(
              title: Text('$day - Ders Seçimi'),
              content: Container(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Ders Ara...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          searchQuery = val;
                        });
                      },
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filteredBranches.length,
                        itemBuilder: (context, index) {
                          final branch = filteredBranches[index];
                          final isSelected = selected.contains(branch);
                          return CheckboxListTile(
                            title: Text(branch),
                            value: isSelected,
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true)
                                  selected.add(branch);
                                else
                                  selected.remove(branch);
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
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Tamam'),
                ),
              ],
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
        appBar: AppBar(title: Text('Şablon Oluşturuluyor...')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Yeni Şablon Oluştur'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Şablon Adı',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.title),
                        hintText: 'Örn: 8. Sınıf Sayısal Şablonu',
                      ),
                      validator: (v) =>
                          v!.trim().isEmpty ? 'İsim gerekli' : null,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Haftalık Ders Programı',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    ..._days.map((day) => _buildDayCard(day)).toList(),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(blurRadius: 5, color: Colors.black12)],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Bu şablonu kimlere atayacaksınız?',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _startAssignmentProcess('save'),
                    icon: Icon(Icons.save, color: Colors.white),
                    label: Text(
                      'Şablonu Kaydet',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      minimumSize: Size(double.infinity, 50),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Veya doğrudan atayın:',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                          ),
                          onPressed: () => _startAssignmentProcess('student'),
                          child: Text(
                            'Öğrenciye',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                          ),
                          onPressed: () => _startAssignmentProcess('class'),
                          child: Text(
                            'Şubeye',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () => _startAssignmentProcess('all'),
                          child: Text(
                            'Herkes',
                            style: TextStyle(color: Colors.white),
                          ),
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
      margin: EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 2,
      child: ExpansionTile(
        title: Text(day, style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          subjects.isEmpty
              ? 'Ders seçilmedi'
              : '${subjects.length} ders seçildi',
          style: TextStyle(color: subjects.isEmpty ? Colors.red : Colors.green),
        ),
        trailing: IconButton(
          icon: Icon(Icons.add_circle, color: Colors.indigo),
          onPressed: () => _modifyDay(day),
        ),
        children: [
          if (subjects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: subjects
                    .map(
                      (s) => Chip(
                        label: Text(s),
                        deleteIcon: Icon(Icons.close, size: 16),
                        onDeleted: () {
                          setState(() {
                            _schedule[day]!.remove(s);
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          TextButton(onPressed: () => _modifyDay(day), child: Text('Düzenle')),
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
          onPressed: () => widget.onConfirm(_selected.toList()),
          child: Text('Ata'),
        ),
      ],
    );
  }
}
