import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../models/project_assignment_model.dart';
import '../../../../services/project_assignment_service.dart';

class ProjectAssignmentFormScreen extends StatefulWidget {
  final String institutionId;
  final ProjectAssignment? assignment; // If editing

  const ProjectAssignmentFormScreen({
    Key? key,
    required this.institutionId,
    this.assignment,
  }) : super(key: key);

  @override
  State<ProjectAssignmentFormScreen> createState() =>
      _ProjectAssignmentFormScreenState();
}

class _ProjectAssignmentFormScreenState
    extends State<ProjectAssignmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ProjectAssignmentService();

  int _currentStep = 1;
  final int _totalSteps = 2;

  // Step 1: Assignment Details
  final _nameController = TextEditingController();
  final _termController = TextEditingController();
  DateTime? _surveyDeadline;

  // Step 2: Target Selection
  Set<String> _selectedClassLevels = {};
  List<Map<String, dynamic>> _availableBranches = [];
  List<String> _selectedBranchIds = [];
  bool _isLoadingBranches = false;

  List<Map<String, dynamic>> _availableStudents = [];
  List<String> _selectedStudentIds = [];
  Map<String, Map<String, dynamic>> _selectedStudentMap = {};
  bool _isLoadingStudents = false;
  bool _selectAllStudents = true;

  @override
  void initState() {
    super.initState();
    if (widget.assignment != null) {
      _nameController.text = widget.assignment!.name;
      _termController.text = widget.assignment!.termId;
      _surveyDeadline = widget.assignment!.surveyDeadline;
      _selectedStudentIds = List.from(widget.assignment!.targetStudentIds);
      // We assume class levels/branches logic needs re-fetching or we just show the students
      // For simplicity in edit mode, we might need to look up current students again or just list IDs.
      // Re-populating complex selection state is hard, might skip strict edit of students for now or reload.
      _selectedClassLevels = Set.from(widget.assignment!.targetClassLevels);
      _selectedBranchIds = List.from(widget.assignment!.targetBranchIds);
      // We'll load branches to allow modification
    } else {
      _termController.text = _calculateCurrentTerm();
      _surveyDeadline = DateTime.now().add(const Duration(days: 14));
    }
    _loadBranches();
  }

  String _calculateCurrentTerm() {
    final now = DateTime.now();
    final year = now.month > 8 ? now.year : now.year - 1;
    final term = now.month > 8 || now.month < 2 ? '1' : '2';
    return '$year-${year + 1} / $term. Dönem';
  }

  Future<void> _loadBranches() async {
    setState(() => _isLoadingBranches = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      setState(() {
        _availableBranches = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': (data['className'] ?? data['name'] ?? 'İsimsiz').toString(),
            'classLevel': (data['classLevel'] ?? '0').toString(),
          };
        }).toList();
        _availableBranches.sort((a, b) => a['name'].compareTo(b['name']));
      });

      // If editing, try to infer selected branch IDs if not stored explicitly,
      // typically we only store student IDs.
      // But we can just allow new selection.
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      setState(() => _isLoadingBranches = false);
    }
  }

  Future<void> _loadStudentsFromBranches() async {
    if (_selectedBranchIds.isEmpty) {
      setState(() => _availableStudents = []);
      return;
    }

    setState(() => _isLoadingStudents = true);
    try {
      List<Map<String, dynamic>> studentsFound = [];
      for (var branchId in _selectedBranchIds) {
        final snapshot = await FirebaseFirestore.instance
            .collection('students')
            .where('classId', isEqualTo: branchId)
            .where('isActive', isEqualTo: true)
            .get();

        for (var doc in snapshot.docs) {
          final data = doc.data();
          final sData = {
            'id': doc.id,
            'fullName':
                data['fullName'] ?? '${data['name']} ${data['surname']}',
            'className': data['className'] ?? '',
          };
          studentsFound.add(sData);

          if (_selectedStudentIds.contains(doc.id)) {
            _selectedStudentMap[doc.id] = sData;
          }
        }
      }

      setState(() {
        _availableStudents = studentsFound;
        if (_selectAllStudents && widget.assignment == null) {
          // Only auto-select all on creation, not editing to avoid overriding
          for (var s in studentsFound) {
            if (!_selectedStudentIds.contains(s['id'])) {
              _selectedStudentIds.add(s['id']);
              _selectedStudentMap[s['id']] = s;
            }
          }
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      setState(() => _isLoadingStudents = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir öğrenci seçiniz')),
      );
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final assignment = ProjectAssignment(
        id:
            widget.assignment?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        institutionId: widget.institutionId,
        termId: _termController.text,
        name: _nameController.text,
        createdAt: widget.assignment?.createdAt ?? DateTime.now(),
        authorId: widget.assignment?.authorId ?? user?.uid ?? '',
        status: widget.assignment?.status ?? 'draft',
        targetStudentIds: _selectedStudentIds,
        targetClassLevels: _selectedClassLevels.toList(),
        targetBranchIds: _selectedBranchIds,
        subjects: widget.assignment?.subjects ?? [],
        allocations: widget.assignment?.allocations ?? [],
        surveyId: widget.assignment?.surveyId,
        surveyDeadline: _surveyDeadline,
      );

      if (widget.assignment == null) {
        await _service.createProjectAssignment(assignment);
      } else {
        await _service.updateProjectAssignment(assignment);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proje Görevlendirmesi Kaydedildi')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.assignment == null
              ? 'Yeni Proje Görevlendirmesi'
              : 'Görevlendirmeyi Düzenle',
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: _currentStep == 1 ? _buildStep1() : _buildStep2(),
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Genel Bilgiler',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'Görevlendirme Adı',
            hintText: 'Örn: 2023-2024 Yıl Sonu Projeleri',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          validator: (v) => v!.isEmpty ? 'Gerekli' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _termController,
          decoration: InputDecoration(
            labelText: 'Dönem',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              initialDate:
                  _surveyDeadline ??
                  DateTime.now().add(const Duration(days: 14)),
            );
            if (date != null) setState(() => _surveyDeadline = date);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Son Seçim / Anket Tarihi',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: const Icon(Icons.calendar_today),
            ),
            child: Text(
              _surveyDeadline != null
                  ? "${_surveyDeadline!.day}.${_surveyDeadline!.month}.${_surveyDeadline!.year}"
                  : 'Seçilmedi',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    final levels =
        _availableBranches
            .map((b) => b['classLevel'] as String)
            .toSet()
            .toList()
          ..sort(
            (a, b) => int.tryParse(a)?.compareTo(int.tryParse(b) ?? 0) ?? 0,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Öğrenci Seçimi',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
        const SizedBox(height: 8),
        const Text('Hangi öğrenciler bu projeden sorumlu olacak?'),
        const SizedBox(height: 24),

        Text(
          'Sınıf Seviyeleri',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        if (_isLoadingBranches)
          const CircularProgressIndicator()
        else
          Wrap(
            spacing: 8,
            children: levels.map((l) {
              final isSelected = _selectedClassLevels.contains(l);
              return FilterChip(
                label: Text('$l. Sınıf'),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected)
                      _selectedClassLevels.add(l);
                    else
                      _selectedClassLevels.remove(l);
                  });
                },
              );
            }).toList(),
          ),

        const SizedBox(height: 16),
        if (_selectedClassLevels.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Şubeler',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              TextButton(
                onPressed: () {
                  final visibleBranches = _availableBranches
                      .where(
                        (b) => _selectedClassLevels.contains(b['classLevel']),
                      )
                      .map((b) => b['id'] as String)
                      .toList();
                  setState(() => _selectedBranchIds = visibleBranches);
                  _loadStudentsFromBranches();
                },
                child: const Text('Tümünü Seç'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: _availableBranches
                .where((b) => _selectedClassLevels.contains(b['classLevel']))
                .map((b) {
                  final isSelected = _selectedBranchIds.contains(b['id']);
                  return FilterChip(
                    label: Text(b['name']),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected)
                          _selectedBranchIds.add(b['id']);
                        else
                          _selectedBranchIds.remove(b['id']);
                      });
                      _loadStudentsFromBranches();
                    },
                  );
                })
                .toList(),
          ),
        ],

        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Öğrenciler (${_selectedStudentIds.length})',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            // Could add Manual Search here if needed as per FieldTrip
          ],
        ),
        const Divider(),
        if (_isLoadingStudents)
          const Center(child: CircularProgressIndicator())
        else if (_availableStudents.isNotEmpty)
          Container(
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.separated(
              itemCount: _availableStudents.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final student = _availableStudents[index];
                final isSelected = _selectedStudentIds.contains(student['id']);
                return CheckboxListTile(
                  title: Text(student['fullName']),
                  subtitle: Text(student['className']),
                  value: isSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedStudentIds.add(student['id']);
                      } else {
                        _selectedStudentIds.remove(student['id']);
                      }
                    });
                  },
                );
              },
            ),
          )
        else
          const Text('Şube seçiniz.'),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 1)
            TextButton(
              onPressed: () => setState(() => _currentStep--),
              child: const Text('Geri'),
            )
          else
            const SizedBox(),
          ElevatedButton(
            onPressed: () {
              if (_currentStep == 1) {
                if (!_formKey.currentState!.validate()) return;
                setState(() => _currentStep++);
              } else {
                _submit();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: Text(_currentStep == _totalSteps ? 'Kaydet' : 'İleri'),
          ),
        ],
      ),
    );
  }
}
