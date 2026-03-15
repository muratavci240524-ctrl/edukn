import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/project_assignment_model.dart';
// import '../../../../models/lesson_model.dart';

class ManualAssignDialog extends StatefulWidget {
  final ProjectAssignment assignment;
  final String studentId;
  final Function(String, String) onAssign;

  const ManualAssignDialog({
    Key? key,
    required this.assignment,
    required this.studentId,
    required this.onAssign,
  }) : super(key: key);

  @override
  State<ManualAssignDialog> createState() => _ManualAssignDialogState();
}

class _ManualAssignDialogState extends State<ManualAssignDialog> {
  bool _isLoading = true;
  String? _studentClassId;
  String? _studentName;

  // Filtered list of subjects that apply to this student's class
  List<ProjectSubject> _availableSubjects = [];

  String? _selectedSubjectId;
  String? _selectedTopicId;

  // Found teachers for the selected subject
  List<Map<String, String>> _foundTeachers = [];
  String? _selectedTeacherId; // Selected from found list
  bool _isSearchingTeacher = false;
  String? _teacherSearchError;

  @override
  void initState() {
    super.initState();
    _loadStudentData();
  }

  Future<void> _loadStudentData() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.studentId)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        _studentClassId = data['classId'];
        _studentName = data['fullName'] ?? '${data['name']} ${data['surname']}';

        // Filter subjects
        if (_studentClassId != null) {
          _availableSubjects = widget.assignment.subjects
              .where((s) => s.targetBranchIds.contains(_studentClassId))
              .toList();
        }
      }
    } catch (e) {
      print(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _findTeacherForSubject(String subjectId) async {
    final subject = widget.assignment.subjects.firstWhere(
      (s) => s.id == subjectId,
    );
    if (_studentClassId == null) return;

    setState(() {
      _isSearchingTeacher = true;
      _foundTeachers = [];
      _selectedTeacherId = null;
      _teacherSearchError = null;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('classId', isEqualTo: _studentClassId)
          .where('lessonName', isEqualTo: subject.lessonName)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        // Check for plural first, then singular fallback
        List<String> tIds = [];
        if (data['teacherIds'] != null) {
          tIds = List<String>.from(data['teacherIds']);
        } else if (data['teacherId'] != null) {
          tIds.add(data['teacherId']);
        }

        if (tIds.isNotEmpty) {
          final teachers = <Map<String, String>>[];

          // Fetch names parallelly
          await Future.wait(
            tIds.map((tid) async {
              // Try 'users' first (common for auth/profile)
              var doc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(tid)
                  .get();

              String name = 'Bilinmiyor';
              if (doc.exists) {
                name = doc.data()?['fullName'] ?? 'İsimsiz';
              } else {
                // Fallback to 'staff' if not in 'users'
                final staffDoc = await FirebaseFirestore.instance
                    .collection('staff')
                    .doc(tid)
                    .get();
                if (staffDoc.exists) {
                  name =
                      '${staffDoc.data()?['name'] ?? ''} ${staffDoc.data()?['surname'] ?? ''}'
                          .trim();
                } else {
                  // Fallback: check if 'teacherNames' exists in assignment data and try to map by index (unreliable but possible) or just show ID
                  name = 'Öğretmen ($tid)';
                }
              }
              teachers.add({'id': tid, 'name': name});
            }),
          );

          if (mounted) {
            setState(() {
              _foundTeachers = teachers;
              if (teachers.length == 1) {
                _selectedTeacherId = teachers.first['id'];
              }
            });
          }
        } else {
          if (mounted) {
            setState(
              () => _teacherSearchError =
                  'Ders ataması var fakat öğretmen listesi boş.',
            );
          }
        }
      } else {
        if (mounted) {
          setState(
            () => _teacherSearchError =
                'Bu ders için sınıfa atanmış öğretmen bulunamadı.',
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _teacherSearchError = 'Hata: $e');
    } finally {
      if (mounted) setState(() => _isSearchingTeacher = false);
    }
  }

  void _handleAssign() {
    if (_selectedSubjectId == null ||
        _selectedTopicId == null ||
        _selectedTeacherId == null)
      return;

    // Find the topic quota
    final subject = widget.assignment.subjects.firstWhere(
      (s) => s.id == _selectedSubjectId,
    );
    final topic = subject.topics.firstWhere((t) => t.id == _selectedTopicId);
    final quota = topic.quotaPerTeacher;

    // Calculate current allocations for this teacher & topic
    final currentCount = widget.assignment.allocations
        .where(
          (a) =>
              a.topicId == _selectedTopicId &&
              a.teacherId == _selectedTeacherId,
        )
        .length;

    if (currentCount >= quota) {
      // Show Warning Dialog
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Kontenjan Dolu'),
          content: Text(
            'Seçilen öğretmenin bu konu için kontenjanı dolmuştur.\n'
            'Mevcut Atama: $currentCount / $quota\n\n'
            'Yine de atama yapmak istiyor musunuz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () {
                Navigator.pop(ctx); // Close warning
                _performAssign();
              },
              child: const Text('Evet, Ata'),
            ),
          ],
        ),
      );
    } else {
      // Proceed normally
      _performAssign();
    }
  }

  void _performAssign() {
    widget.onAssign(_selectedTopicId!, _selectedTeacherId!);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manuel Atama',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          if (_isLoading)
            const SizedBox(
              height: 4,
              width: 20,
              child: LinearProgressIndicator(),
            )
          else if (_studentName != null)
            Text(
              _studentName!.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                color: Colors.indigo.shade400,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 100,
              child: Center(child: Text('Öğrenci bilgileri yükleniyor...')),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_availableSubjects.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Bu öğrencinin şubesine tanımlı herhangi bir proje dersi/konusu bulunamadı.',
                        style: TextStyle(color: Colors.red),
                      ),
                    )
                  else ...[
                    // Subject Selection
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Ders Seçimi',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      value: _selectedSubjectId,
                      items: _availableSubjects
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.lessonName),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedSubjectId = v;
                          _selectedTopicId = null;
                          _selectedTeacherId = null;
                          _foundTeachers = [];
                          _teacherSearchError = null;
                        });
                        if (v != null) _findTeacherForSubject(v);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Topic Selection (Dependent on Subject)
                    if (_selectedSubjectId != null)
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Konu Seçimi',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        value: _selectedTopicId,
                        items: widget.assignment.subjects
                            .firstWhere((s) => s.id == _selectedSubjectId)
                            .topics
                            .map(
                              (t) => DropdownMenuItem(
                                value: t.id,
                                child: Text(t.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedTopicId = v),
                        isExpanded: true,
                      ),

                    const SizedBox(height: 24),

                    // Teacher Selection Loop
                    const Text(
                      'Sorumlu Öğretmen:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_isSearchingTeacher)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: LinearProgressIndicator(),
                      )
                    else if (_teacherSearchError != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          _teacherSearchError!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      )
                    else if (_selectedSubjectId == null)
                      const Text(
                        'Önce ders seçiniz.',
                        style: TextStyle(color: Colors.grey),
                      )
                    else if (_foundTeachers.isEmpty)
                      const Text(
                        'Öğretmen verisi bekleniyor...',
                        style: TextStyle(color: Colors.grey),
                      )
                    else if (_foundTeachers.length == 1)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _foundTeachers.first['name']!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Öğretmen Seçiniz',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.orange.shade50,
                        ),
                        value: _selectedTeacherId,
                        items: _foundTeachers
                            .map(
                              (t) => DropdownMenuItem(
                                value: t['id'],
                                child: Text(t['name']!),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedTeacherId = v),
                      ),
                  ],
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: (_selectedTopicId != null && _selectedTeacherId != null)
              ? _handleAssign
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: const Text('Öğrenciyi Ata'),
        ),
      ],
    );
  }
}
