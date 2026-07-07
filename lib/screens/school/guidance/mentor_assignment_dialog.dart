import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class MentorAssignmentDialog extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const MentorAssignmentDialog({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<MentorAssignmentDialog> createState() => _MentorAssignmentDialogState();
}

class _MentorAssignmentDialogState extends State<MentorAssignmentDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isSaving = false;

  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _students = [];
  
  List<String> _uniqueClasses = [];
  List<String> _uniqueLevels = [];

  // Form selections
  String? _selectedTeacherId;
  String? _selectedTeacherName;
  String _assignmentType = 'level'; // 'level', 'branch', 'student'
  
  String? _selectedLevel;
  String? _selectedClass;
  Set<String> _selectedStudentIds = {};
  String _studentSearchQuery = '';
  String? _expandedTeacherId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch Teachers (staff role: ogretmen / rehber_ogretmen)
      final teachersQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('type', isEqualTo: 'staff')
          .get();

      final teachersList = teachersQuery.docs
          .map((doc) => {
                'id': doc.id,
                'name': doc.data()['fullName'] ?? 'İsimsiz Öğretmen',
                'role': doc.data()['role'] ?? 'ogretmen',
              })
          .where((t) => t['role'] == 'ogretmen' || t['role'] == 'rehber_ogretmen')
          .toList();

      teachersList.sort((a, b) => _turkishCompare(a['name'] as String, b['name'] as String));

      // 2. Fetch Active Students for unique class/level lists
      final studentsQuery = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      final studentsList = studentsQuery.docs.map((doc) {
        final data = doc.data();
        
        // Extract class name
        String rawBranch = (data['studentBranch'] ?? data['className'] ?? data['branch'] ?? '').toString().trim();
        final rawLevel = (data['classLevel'] ?? data['level'] ?? '').toString().trim();
        String className = rawBranch;
        if (className.isEmpty) {
          className = rawLevel.isNotEmpty ? "$rawLevel. Sınıf" : 'Sınıfsız';
        } else if (rawLevel.isNotEmpty) {
          String levelDigits = rawLevel.replaceAll(RegExp(r'[^0-9]'), '');
          if (levelDigits.isNotEmpty && !className.contains(levelDigits)) {
            className = "$levelDigits-$className";
          }
        }

        return {
          'id': doc.id,
          'name': data['fullName'] ?? '${data['name'] ?? ''} ${data['surname'] ?? ''}'.trim(),
          'class': className,
          'level': rawLevel,
          'mentorId': data['mentorId'],
          'mentorName': data['mentorName'],
          'docRef': doc.reference,
        };
      }).toList();

      studentsList.sort((a, b) => a['name'].compareTo(b['name']));

      // Extract unique levels and classes
      final Set<String> levels = {};
      final Set<String> classes = {};
      for (var s in studentsList) {
        if (s['level'].toString().isNotEmpty) levels.add(s['level']);
        if (s['class'].toString().isNotEmpty && s['class'] != 'Sınıfsız') classes.add(s['class']);
      }

      setState(() {
        _teachers = teachersList;
        _students = studentsList;
        _uniqueLevels = levels.toList()..sort();
        _uniqueClasses = classes.toList()..sort();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading assignment data: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveAssignment() async {
    if (_selectedTeacherId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir öğretmen seçin.'), backgroundColor: Colors.orange),
      );
      return;
    }

    List<Map<String, dynamic>> targetStudents = [];

    if (_assignmentType == 'level') {
      if (_selectedLevel == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen bir sınıf seviyesi seçin.'), backgroundColor: Colors.orange),
        );
        return;
      }
      targetStudents = _students.where((s) => s['level'] == _selectedLevel).toList();
    } else if (_assignmentType == 'branch') {
      if (_selectedClass == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen bir şube seçin.'), backgroundColor: Colors.orange),
        );
        return;
      }
      targetStudents = _students.where((s) => s['class'] == _selectedClass).toList();
    } else {
      if (_selectedStudentIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen en az bir öğrenci seçin.'), backgroundColor: Colors.orange),
        );
        return;
      }
      targetStudents = _students.where((s) => _selectedStudentIds.contains(s['id'])).toList();
    }

    if (targetStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Atama yapılacak öğrenci bulunamadı.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      int count = 0;

      for (var s in targetStudents) {
        final ref = s['docRef'] as DocumentReference;
        batch.update(ref, {
          'mentorId': _selectedTeacherId,
          'mentorName': _selectedTeacherName,
        });
        count++;
        if (count >= 490) {
          await batch.commit();
          count = 0;
        }
      }

      if (count > 0) {
        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ ${_selectedTeacherName} isimli öğretmene ${targetStudents.length} öğrenci başarıyla atandı.'), backgroundColor: Colors.green),
        );
        setState(() {
          _selectedStudentIds.clear();
          _selectedLevel = null;
          _selectedClass = null;
          _isSaving = false;
        });
        _loadData(); // Refresh assignments list
        _tabController.animateTo(1); // Switch to current list tab
      }
    } catch (e) {
      debugPrint("Error saving mentor assignment: $e");
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _removeAssignment(String studentId) async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('students').doc(studentId).update({
        'mentorId': FieldValue.delete(),
        'mentorName': FieldValue.delete(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Atama kaldırıldı.'), backgroundColor: Colors.green),
        );
        setState(() => _isSaving = false);
        _loadData();
      }
    } catch (e) {
      debugPrint("Error removing assignment: $e");
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _bulkRemoveTeacherAssignments(String teacherId, String teacherName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Atamaları Kaldır'),
        content: Text('$teacherName öğretmenine ait TÜM mentörlük atamalarını kaldırmak istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Tümünü Kaldır', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);

    try {
      final teacherStudents = _students.where((s) => s['mentorId'] == teacherId).toList();
      final batch = FirebaseFirestore.instance.batch();
      int count = 0;

      for (var s in teacherStudents) {
        final ref = s['docRef'] as DocumentReference;
        batch.update(ref, {
          'mentorId': FieldValue.delete(),
          'mentorName': FieldValue.delete(),
        });
        count++;
        if (count >= 490) {
          await batch.commit();
          count = 0;
        }
      }

      if (count > 0) {
        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ $teacherName öğretmeninin tüm mentörlük atamaları başarıyla kaldırıldı.'), backgroundColor: Colors.green),
        );
        setState(() => _isSaving = false);
        _loadData();
      }
    } catch (e) {
      debugPrint("Error bulk removing: $e");
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle Bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.indigo, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Mentör Atama Yönetimi',
                        style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // TabBar Header
              Container(
                color: Colors.indigo.shade50,
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.indigo,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: Colors.indigo,
                  indicatorWeight: 3,
                  labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: const [
                    Tab(text: 'Yeni Atama Yap'),
                    Tab(text: 'Mevcut Atamalar'),
                  ],
                ),
              ),

              // Content Area
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildNewAssignmentTab(scrollController),
                          _buildCurrentAssignmentsTab(scrollController),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNewAssignmentTab(ScrollController scrollController) {
    if (_teachers.isEmpty) {
      return const Center(child: Text('Kurumda tanımlı aktif öğretmen bulunamadı.'));
    }

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Select Teacher
          Text(
            '1. Mentör Öğretmen Seçin *',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo.shade900),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              return DropdownMenu<String>(
                width: constraints.maxWidth,
                enableSearch: true,
                enableFilter: true,
                hintText: 'Öğretmen Seçin',
                textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                menuStyle: MenuStyle(
                  backgroundColor: MaterialStateProperty.all(Colors.white),
                  elevation: MaterialStateProperty.all(8),
                  shape: MaterialStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  maximumSize: MaterialStateProperty.all(const Size.fromHeight(300)),
                ),
                dropdownMenuEntries: _teachers.map((t) {
                  return DropdownMenuEntry<String>(
                    value: t['id'] as String,
                    label: t['name'] as String,
                    style: ButtonStyle(
                      textStyle: MaterialStateProperty.all(
                        GoogleFonts.inter(fontSize: 14),
                      ),
                    ),
                  );
                }).toList(),
                onSelected: (value) {
                  setState(() {
                    _selectedTeacherId = value;
                    _selectedTeacherName = _teachers.firstWhere((t) => t['id'] == value)['name'] as String;
                  });
                },
              );
            },
          ),
          const SizedBox(height: 24),

          // 2. Select Assignment Type
          Text(
            '2. Atama Türü Seçin *',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo.shade900),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildTypeRadioCard('level', 'Sınıf Bazlı', Icons.school_rounded),
              const SizedBox(width: 8),
              _buildTypeRadioCard('branch', 'Şube Bazlı', Icons.home_work_rounded),
              const SizedBox(width: 8),
              _buildTypeRadioCard('student', 'Öğrenci Bazlı', Icons.people_rounded),
            ],
          ),
          const SizedBox(height: 24),

          // 3. Conditional Selections
          Text(
            '3. Hedef Seçin *',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo.shade900),
          ),
          const SizedBox(height: 12),
          if (_assignmentType == 'level') _buildLevelSelection()
          else if (_assignmentType == 'branch') _buildBranchSelection()
          else _buildStudentSelection(),

          const SizedBox(height: 32),

          // Save Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveAssignment,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSaving
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Atamayı Tamamla', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeRadioCard(String type, String label, IconData icon) {
    final bool isSelected = _assignmentType == type;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _assignmentType = type;
            _selectedClass = null;
            _selectedLevel = null;
            _selectedStudentIds.clear();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? Colors.indigo : Colors.grey.shade200, width: 1.5),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.indigo : Colors.grey.shade500, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.indigo : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLevelSelection() {
    if (_uniqueLevels.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12.0),
        child: Text('Sistemde kayıtlı sınıf seviyesi bulunamadı.', style: TextStyle(color: Colors.grey)),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _uniqueLevels.map((l) {
        final bool isSelected = _selectedLevel == l;
        return ChoiceChip(
          showCheckmark: false,
          label: Text(l.isNotEmpty ? "$l. Sınıf" : 'Sınıfsız'),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              _selectedLevel = selected ? l : null;
            });
          },
          selectedColor: Colors.indigo.shade100,
          labelStyle: TextStyle(color: isSelected ? Colors.indigo.shade900 : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
        );
      }).toList(),
    );
  }

  Widget _buildBranchSelection() {
    if (_uniqueClasses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12.0),
        child: Text('Sistemde kayıtlı şube bulunamadı.', style: TextStyle(color: Colors.grey)),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _uniqueClasses.map((c) {
        final bool isSelected = _selectedClass == c;

        // Check if any student in this branch is already assigned to a mentor
        final assignedStudent = _students.firstWhere(
          (s) => s['class'] == c && s['mentorId'] != null,
          orElse: () => {},
        );
        final bool isAlreadyAssigned = assignedStudent['mentorId'] != null;

        return ChoiceChip(
          showCheckmark: false,
          label: Text(c),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              _selectedClass = selected ? c : null;
            });
          },
          selectedColor: Colors.indigo.shade100,
          backgroundColor: isAlreadyAssigned ? Colors.orange.shade50 : Colors.grey.shade50,
          side: BorderSide(
            color: isSelected 
                ? Colors.indigo 
                : (isAlreadyAssigned ? Colors.orange.shade300 : Colors.grey.shade200),
            width: isSelected ? 2 : 1,
          ),
          labelStyle: TextStyle(
            color: isSelected 
                ? Colors.indigo.shade900 
                : (isAlreadyAssigned ? Colors.orange.shade900 : Colors.black87),
            fontWeight: (isSelected || isAlreadyAssigned) ? FontWeight.bold : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStudentSelection() {
    if (_students.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12.0),
        child: Text('Kayıtlı aktif öğrenci bulunamadı.', style: TextStyle(color: Colors.grey)),
      );
    }

    final filteredStudents = _students.where((s) {
      final name = s['name'].toString().toLowerCase();
      final query = _studentSearchQuery.toLowerCase();
      return name.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Student Search Bar
        TextField(
          decoration: InputDecoration(
            hintText: 'Öğrenci Ara...',
            prefixIcon: const Icon(Icons.search, color: Colors.indigo, size: 20),
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
            setState(() {
              _studentSearchQuery = val;
            });
          },
        ),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: filteredStudents.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Öğrenci bulunamadı.', style: TextStyle(color: Colors.grey)),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filteredStudents.length,
                  itemBuilder: (context, index) {
                    final s = filteredStudents[index];
                    final id = s['id'] as String;
                    final name = s['name'] as String;
                    final className = s['class'] as String;
                    final bool isSelected = _selectedStudentIds.contains(id);
                    final String? existingMentor = s['mentorName'];

                    return CheckboxListTile(
                      value: isSelected,
                      activeColor: Colors.indigo,
                      title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        existingMentor != null ? 'Şube: $className • Mevcut Mentör: $existingMentor' : 'Şube: $className',
                        style: TextStyle(fontSize: 11, color: existingMentor != null ? Colors.orange.shade800 : Colors.grey.shade600),
                      ),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedStudentIds.add(id);
                          } else {
                            _selectedStudentIds.remove(id);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCurrentAssignmentsTab(ScrollController scrollController) {
    // Group students by mentor id
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var s in _students) {
      final mentorId = s['mentorId'];
      if (mentorId != null && mentorId.toString().isNotEmpty) {
        grouped.putIfAbsent(mentorId, () => []);
        grouped[mentorId]!.add(s);
      }
    }

    if (grouped.isEmpty) {
      return const Center(child: Text('Sistemde henüz atanmış mentör bulunmamaktadır.'));
    }

    // Sort grouped entries by minimum class/branch name of students (ascending)
    final sortedEntries = grouped.entries.toList();
    sortedEntries.sort((entryA, entryB) {
      final branchesA = entryA.value.map((s) => s['class'].toString()).toSet().toList();
      final branchesB = entryB.value.map((s) => s['class'].toString()).toSet().toList();
      
      branchesA.sort(_turkishCompare);
      branchesB.sort(_turkishCompare);
      
      final minA = branchesA.isNotEmpty ? branchesA.first : '';
      final minB = branchesB.isNotEmpty ? branchesB.first : '';
      
      return _turkishCompare(minA, minB);
    });

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: sortedEntries.length,
      itemBuilder: (context, index) {
        final entry = sortedEntries[index];
        final teacherId = entry.key;
        final assignedList = entry.value;
        final teacherName = assignedList.first['mentorName'] ?? 'Bilinmeyen Öğretmen';

        // Extract assigned branches (classes) to display as badges
        final Set<String> branches = assignedList.map((s) => s['class'].toString()).toSet();

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
          child: ExpansionTile(
            key: ValueKey('$teacherId-${_expandedTeacherId == teacherId}'),
            initiallyExpanded: _expandedTeacherId == teacherId,
            shape: const Border(), // Removes top and bottom lines when expanded
            collapsedShape: const Border(), // Removes top and bottom lines when collapsed
            onExpansionChanged: (isExpanded) {
              setState(() {
                if (isExpanded) {
                  _expandedTeacherId = teacherId;
                } else if (_expandedTeacherId == teacherId) {
                  _expandedTeacherId = null;
                }
              });
            },
            leading: CircleAvatar(
              backgroundColor: Colors.indigo.shade50,
              child: const Icon(Icons.psychology_outlined, color: Colors.indigo),
            ),
            title: Text(teacherName, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                ...branches.map((b) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(6)),
                      child: Text(b, style: const TextStyle(fontSize: 10, color: Colors.indigo, fontWeight: FontWeight.bold)),
                    )),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(6)),
                  child: Text('${assignedList.length} Öğrenci', style: const TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              tooltip: 'Tüm Atamaları Kaldır',
              onPressed: () => _bulkRemoveTeacherAssignments(teacherId, teacherName),
            ),
            children: [
              const Divider(height: 1),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: assignedList.length,
                itemBuilder: (context, sIndex) {
                  final s = assignedList[sIndex];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                    title: Text(s['name'] ?? 'İsimsiz Öğrenci', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    subtitle: Text('Sınıf/Şube: ${s['class']}', style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.grey, size: 20),
                      onPressed: () => _removeAssignment(s['id']),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  int _turkishCompare(String a, String b) {
    const turkishChars = {
      'a': 'a', 'b': 'b', 'c': 'c', 'ç': 'cş', 'd': 'd', 'e': 'e', 'f': 'f',
      'g': 'g', 'ğ': 'gş', 'h': 'h', 'ı': 'ı', 'i': 'iş', 'j': 'j', 'k': 'k',
      'l': 'l', 'm': 'm', 'n': 'n', 'o': 'o', 'ö': 'oş', 'p': 'p', 'r': 'r',
      's': 's', 'ş': 'sş', 't': 't', 'u': 'u', 'ü': 'uş', 'v': 'v', 'y': 'y',
      'z': 'z'
    };

    String getComparable(String s) {
      return s.toLowerCase().split('').map((char) => turkishChars[char] ?? char).join();
    }

    return getComparable(a).compareTo(getComparable(b));
  }
}
