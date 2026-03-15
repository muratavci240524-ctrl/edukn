import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../survey/survey_stats_screen.dart';

import '../../../../models/survey_model.dart';
import '../../../../models/project_assignment_model.dart';
import '../../../../services/project_assignment_service.dart';
import '../../../../services/survey_service.dart';

import 'project_assignment_form_screen.dart';
import 'manual_assign_dialog.dart';
// import 'project_topic_manager.dart'; // Will create these
// import 'project_distribution_manager.dart';

class ProjectAssignmentDashboardScreen extends StatefulWidget {
  final ProjectAssignment assignment;

  const ProjectAssignmentDashboardScreen({Key? key, required this.assignment})
    : super(key: key);

  @override
  State<ProjectAssignmentDashboardScreen> createState() =>
      _ProjectAssignmentDashboardScreenState();
}

class _ProjectAssignmentDashboardScreenState
    extends State<ProjectAssignmentDashboardScreen>
    with SingleTickerProviderStateMixin {
  late ProjectAssignment _assignment;
  late TabController _tabController;
  final _service = ProjectAssignmentService();

  @override
  void initState() {
    super.initState();
    _assignment = widget.assignment;
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<void> _refresh() async {
    final updated = await _service.getProjectAssignment(_assignment.id);
    if (updated != null) {
      setState(() => _assignment = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_assignment.name, style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.indigo,
          tabs: const [
            Tab(text: 'Konular & Kontenjan'),
            Tab(text: 'Dağıtım & Atamalar'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () async {
              // Edit settings
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProjectAssignmentFormScreen(
                    institutionId: _assignment.institutionId,
                    assignment: _assignment,
                  ),
                ),
              );
              _refresh();
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildSubjectsTab(), _buildDistributionTab()],
      ),
    );
  }

  // --- TAB 1: TOPIC MANAGEMENT ---

  Widget _buildSubjectsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ders Listesi (${_assignment.subjects.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showSubjectDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Ders Ekle'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
              ),
            ],
          ),
        ),
        Expanded(
          child: _assignment.subjects.isEmpty
              ? Center(
                  child: Text(
                    'Henüz ders eklenmemiş.\n"Ders Ekle" butonu ile başlayın.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _assignment.subjects.length,
                  itemBuilder: (context, index) {
                    final subject = _assignment.subjects[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        title: Text(
                          subject.lessonName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${subject.targetBranchIds.length} Şube • ${subject.topics.length} Konu',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.add_circle,
                                color: Colors.green,
                              ),
                              tooltip: 'Konu Ekle',
                              onPressed: () =>
                                  _showTopicDialog(subjectIndex: index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _showSubjectDialog(
                                existingSubject: subject,
                                index: index,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteSubject(index),
                            ),
                            // Expansion arrow is default
                          ],
                        ),
                        children: [
                          if (subject.topics.isEmpty)
                            const ListTile(
                              title: Text(
                                'Henüz konu eklenmedi',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ...subject.topics.asMap().entries.map((entry) {
                            final topicIndex = entry.key;
                            final topic = entry.value;
                            return ListTile(
                              title: Text(topic.name),
                              subtitle: Text(
                                'Kontenjan: ${topic.quotaPerTeacher} (Öğretmen Başı)',
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () => _deleteTopic(
                                  subjectIndex: index,
                                  topicIndex: topicIndex,
                                ),
                              ),
                              onTap: () => _showTopicDialog(
                                subjectIndex: index,
                                existingTopic: topic,
                                topicIndex: topicIndex,
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- TAB 2: DISTRIBUTION ---

  Widget _buildDistributionTab() {
    // Basic stats
    final totalStudents = _assignment.targetStudentIds.length;
    final allocatedCount = _assignment.allocations.length;
    final unassignedCount = totalStudents - allocatedCount;

    return Column(
      children: [
        // Stats Header
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.indigo.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Toplam', totalStudents.toString()),
              _buildStatItem(
                'Atanan',
                allocatedCount.toString(),
                color: Colors.green,
              ),
              _buildStatItem(
                'Bekleyen',
                unassignedCount.toString(),
                color: Colors.orange,
              ),
            ],
          ),
        ),

        // Action Bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.poll),
                  label: const Text('Anket İşlemleri'),
                  onPressed: _showSurveyOptions,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Sonuçları Değerlendir ve Dağıt'),
                  onPressed: _runDistribution,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                ),
              ),
            ],
          ),
        ),

        const Divider(),

        // Student List
        Expanded(
          child: ListView.builder(
            itemCount: totalStudents,
            itemBuilder: (context, index) {
              final studentId = _assignment.targetStudentIds[index];
              // Find allocation
              final allocation = _assignment.allocations.firstWhere(
                (a) => a.studentId == studentId,
                orElse: () => ProjectAllocation(
                  studentId: '',
                  topicId: '',
                  teacherId: '',
                  method: '',
                  allocatedAt: DateTime.fromMillisecondsSinceEpoch(0),
                ),
              );

              final isAllocated = allocation.studentId.isNotEmpty;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isAllocated
                      ? Colors.green.shade100
                      : Colors.grey.shade200,
                  child: Icon(
                    isAllocated ? Icons.check : Icons.person,
                    color: isAllocated ? Colors.green.shade700 : Colors.grey,
                  ),
                ),
                title: FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('students')
                      .doc(studentId)
                      .get(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return Text(studentId);
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    return Text(data?['fullName'] ?? 'Bilinmeyen Öğrenci');
                  },
                ),
                subtitle: isAllocated
                    ? FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(allocation.teacherId)
                            .get(),
                        builder: (context, teacherSnap) {
                          String tName = '...';
                          if (teacherSnap.hasData &&
                              teacherSnap.data != null &&
                              teacherSnap.data!.exists) {
                            final userData =
                                teacherSnap.data!.data()
                                    as Map<String, dynamic>?;
                            tName = userData?['fullName'] ?? 'Bilinmeyen';
                          }

                          // Find topic name
                          String topicName = 'Konu Bulunamadı';
                          try {
                            final topic = _assignment.subjects
                                .expand((s) => s.topics)
                                .firstWhere((t) => t.id == allocation.topicId);
                            topicName = topic.name;
                          } catch (_) {}

                          return Text('$topicName ($tName)');
                        },
                      )
                    : const Text(
                        'Atanmamış',
                        style: TextStyle(color: Colors.orange),
                      ),
                trailing: isAllocated
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _removeAllocation(studentId),
                      )
                    : IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showManualAssignDialog(studentId),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- HELPER METHODS ---

  Widget _buildStatItem(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.indigo,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Future<void> _deleteSubject(int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Dersi Sil'),
        content: const Text(
          'Bu dersi ve altındaki tüm konuları silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _assignment.subjects.removeAt(index));
      await _service.updateProjectAssignment(_assignment);
    }
  }

  Future<void> _deleteTopic({
    required int subjectIndex,
    required int topicIndex,
  }) async {
    setState(
      () => _assignment.subjects[subjectIndex].topics.removeAt(topicIndex),
    );
    await _service.updateProjectAssignment(_assignment);
  }

  Future<void> _removeAllocation(String studentId) async {
    setState(() {
      _assignment.allocations.removeWhere((a) => a.studentId == studentId);
    });
    await _service.updateProjectAssignment(_assignment);
  }

  Future<void> _showSubjectDialog({
    ProjectSubject? existingSubject,
    int? index,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => _ProjectSubjectDialog(
        institutionId: _assignment.institutionId,
        availableScopeBranchIds: _assignment.targetBranchIds,
        existingSubject: existingSubject,
        onSave: (newSubject) async {
          setState(() {
            if (index != null) {
              _assignment.subjects[index] = newSubject;
            } else {
              _assignment.subjects.add(newSubject);
            }
          });
          await _service.updateProjectAssignment(_assignment);
        },
      ),
    );
  }

  Future<void> _showTopicDialog({
    required int subjectIndex,
    ProjectTopic? existingTopic,
    int? topicIndex,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => _ProjectTopicDialog(
        existingTopic: existingTopic,
        onSave: (newTopic) async {
          setState(() {
            final subject = _assignment.subjects[subjectIndex];
            if (topicIndex != null) {
              subject.topics[topicIndex] = newTopic;
            } else {
              subject.topics.add(newTopic);
            }
          });
          await _service.updateProjectAssignment(_assignment);
        },
      ),
    );
  }

  void _showSurveyOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_task),
              title: const Text('Anket Oluştur'),
              subtitle: const Text('Derslere göre anket oluşturur'),
              onTap: () {
                Navigator.pop(context);
                _createSurvey();
              },
            ),
            if (_assignment.surveyId != null)
              ListTile(
                leading: const Icon(Icons.analytics),
                title: const Text('Anket Sonuçlarını Gör'),
                onTap: () async {
                  Navigator.pop(context); // Close bottom sheet

                  final surveyId = _assignment.surveyId;
                  if (surveyId == null) return;

                  // Show loading
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (c) =>
                        const Center(child: CircularProgressIndicator()),
                  );

                  try {
                    final survey = await SurveyService().getSurvey(surveyId);

                    if (mounted) {
                      Navigator.pop(context); // Close loading

                      if (survey != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                SurveyStatsScreen(survey: survey),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Anket verisi bulunamadı.'),
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      Navigator.pop(context); // Close loading
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
                    }
                  }
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _createSurvey() async {
    if (_assignment.subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anket için önce ders ekleyiniz')),
      );
      return;
    }

    // 1. Prepare Defaults
    final defaultTitle = '${_assignment.name} - Proje Ödevi Tercihleri';
    final defaultContent =
        '''Sevgili öğrenciler,

${_assignment.name} için proje ödevi tercih belirleme süreci başlamıştır.

Lütfen "Anketler" bölümünden anket listesine giderek veya aşağıda belirtilen bağlantıdan, sorumlu olduğunuz derslerden almak istediğiniz proje konularını seçiniz.

Son Katılım Tarihi: ${DateFormat('dd.MM.yyyy').format(_assignment.surveyDeadline ?? DateTime.now().add(const Duration(days: 7)))}''';

    final titleController = TextEditingController(text: defaultTitle);
    final contentController = TextEditingController(text: defaultContent);
    DateTime scheduleDate = DateTime.now();
    TimeOfDay scheduleTime = TimeOfDay.now();

    // Ranking configuration defaults
    int maxProjectsPerStudent = 2; // Öğrenci kaç proje alacak
    int maxTotalChoices = 5; // Toplam kaç tercih yapabilecek
    int maxSubjects = 3; // En fazla kaç farklı ders seçebilir
    int maxChoicesPerSubject = 2; // Bir dersten en fazla kaç tercih yapabilir

    // 2. Show Dialog
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Anket ve Duyuru Ayarları'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Duyuru/Anket Başlığı',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: contentController,
                      decoration: const InputDecoration(
                        labelText: 'Duyuru İçeriği',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 5,
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Tercih Kuralları',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Öğrenci kaç proje alacak
                    Row(
                      children: [
                        Expanded(child: Text('Öğrenci kaç proje alacak:')),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            controller: TextEditingController(
                              text: maxProjectsPerStudent.toString(),
                            ),
                            onChanged: (v) {
                              final val = int.tryParse(v);
                              if (val != null && val > 0) {
                                maxProjectsPerStudent = val;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Toplam kaç tercih yapabilecek
                    Row(
                      children: [
                        Expanded(child: Text('Toplam kaç tercih yapabilecek:')),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            controller: TextEditingController(
                              text: maxTotalChoices.toString(),
                            ),
                            onChanged: (v) {
                              final val = int.tryParse(v);
                              if (val != null && val > 0) {
                                maxTotalChoices = val;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // En fazla kaç farklı ders seçebilir
                    Row(
                      children: [
                        Expanded(child: Text('En fazla kaç farklı ders:')),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            controller: TextEditingController(
                              text: maxSubjects.toString(),
                            ),
                            onChanged: (v) {
                              final val = int.tryParse(v);
                              if (val != null && val > 0) {
                                maxSubjects = val;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Bir dersten en fazla kaç tercih yapabilir
                    Row(
                      children: [
                        Expanded(
                          child: Text('Bir dersten en fazla kaç tercih:'),
                        ),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            controller: TextEditingController(
                              text: maxChoicesPerSubject.toString(),
                            ),
                            onChanged: (v) {
                              final val = int.tryParse(v);
                              if (val != null && val > 0) {
                                maxChoicesPerSubject = val;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Yayınlanma Zamanı'),
                      subtitle: Text(
                        '${DateFormat('dd.MM.yyyy').format(scheduleDate)} ${scheduleTime.format(context)}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: scheduleDate,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (d != null) {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: scheduleTime,
                          );
                          if (t != null) {
                            setStateDialog(() {
                              scheduleDate = d;
                              scheduleTime = t;
                            });
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Onayla ve Oluştur'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    setState(() {}); // Loading...

    List<SurveyQuestion> questions = [];
    for (var subject in _assignment.subjects) {
      if (subject.topics.isEmpty) continue;
      questions.add(
        SurveyQuestion(
          id: subject.id,
          text:
              '${subject.lessonName} - Proje Konusu Tercihleri (Öncelik sırasına göre seçiniz)',
          type: SurveyQuestionType.ranking,
          options: subject.topics.map((t) => t.name).toList(),
          isRequired: true, // Make it required for better data
        ),
      );
    }

    final scheduledDateTime = DateTime(
      scheduleDate.year,
      scheduleDate.month,
      scheduleDate.day,
      scheduleTime.hour,
      scheduleTime.minute,
    );

    // Determine School Type ID from target students
    String? schoolTypeId;

    if (_assignment.targetStudentIds.isNotEmpty) {
      final firstStudentId = _assignment.targetStudentIds.first;
      print('🔍 Determining schoolTypeId from student: $firstStudentId');

      try {
        // Try students collection first
        var studentDoc = await FirebaseFirestore.instance
            .collection('students')
            .doc(firstStudentId)
            .get();

        if (studentDoc.exists) {
          final studentData = studentDoc.data();
          schoolTypeId =
              studentData?['schoolTypeId'] ?? studentData?['schoolType'];
          print('✅ SchoolTypeId from students collection: $schoolTypeId');
        } else {
          // Fallback: try users collection
          print('⚠️ Student not in students collection, trying users...');
          studentDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(firstStudentId)
              .get();

          if (studentDoc.exists) {
            final userData = studentDoc.data();
            schoolTypeId = userData?['schoolTypeId'] ?? userData?['schoolType'];
            print('✅ SchoolTypeId from users collection: $schoolTypeId');
          } else {
            print(
              '❌ Student document not found in both collections: $firstStudentId',
            );
          }
        }
      } catch (e) {
        print('❌ Error fetching student data: $e');
      }
    } else {
      print('❌ No targetStudentIds in assignment');
    }

    // CRITICAL: SchoolTypeId must exist for announcement to appear in school type screen
    if (schoolTypeId == null || schoolTypeId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'HATA: Okul türü belirlenemedi. Anket oluşturulamadı.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    print('📝 Creating survey with schoolTypeId: $schoolTypeId');

    final survey = Survey(
      id: '',
      institutionId: _assignment.institutionId,
      schoolTypeId: schoolTypeId,
      title: titleController.text,
      description: contentController.text,
      authorId: _assignment.authorId,
      createdAt: DateTime.now(),
      status: SurveyStatus.published,
      scheduledAt: scheduledDateTime,
      targetType: SurveyTargetType.students,
      targetIds: _assignment.targetStudentIds,
      sections: [
        SurveySection(
          id: 'preferences',
          title: 'Ders Tercihleri',
          questions: questions,
        ),
      ],
      // Ranking configuration
      maxProjectsPerStudent: maxProjectsPerStudent,
      maxTotalChoices: maxTotalChoices,
      maxSubjects: maxSubjects,
      maxChoicesPerSubject: maxChoicesPerSubject,
    );

    try {
      final createdId = await SurveyService().createSurvey(survey);

      // Add current user (creator/admin) to recipients safely
      final currentUser = FirebaseAuth.instance.currentUser;
      String? currentUserId;

      if (currentUser?.email != null) {
        try {
          final userDocs = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: currentUser!.email)
              .limit(1)
              .get();
          if (userDocs.docs.isNotEmpty) {
            currentUserId = userDocs.docs.first.id;
          } else {
            // Fallback to Auth UID if no doc found
            currentUserId = currentUser.uid;
          }
        } catch (e) {
          print('Error finding admin user doc: $e');
          currentUserId = currentUser!.uid;
        }
      }

      // FIX: Recipients must be prefixed with 'user:' for the Announcement system.
      final List<String> recipients = _assignment.targetStudentIds
          .map((id) => 'user:$id')
          .toList();

      if (currentUserId != null) {
        recipients.add('user:$currentUserId');
      }

      await SurveyService().publishSurvey(createdId, recipients);

      setState(() {
        _assignment = ProjectAssignment(
          id: _assignment.id,
          institutionId: _assignment.institutionId,
          termId: _assignment.termId,
          name: _assignment.name,
          createdAt: _assignment.createdAt,
          authorId: _assignment.authorId,
          status: _assignment.status,
          targetStudentIds: _assignment.targetStudentIds,
          targetClassLevels: _assignment.targetClassLevels,
          targetBranchIds: _assignment.targetBranchIds,
          subjects: _assignment.subjects,
          allocations: _assignment.allocations,
          surveyId: createdId,
          surveyDeadline: _assignment.surveyDeadline,
        );
      });
      await _service.updateProjectAssignment(_assignment);

      final isPublishedNow =
          scheduleDate.difference(DateTime.now()).inMinutes < 1;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPublishedNow
                ? 'Anket oluşturuldu ve duyuru YAYINLANDI.'
                : 'Anket oluşturuldu ve duyuru PLANLANDI.',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _runDistribution() async {
    if (_assignment.surveyId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Anket bulunamadı')));
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Dağıtım Başlatılıyor...')));

    // 1. Fetch Survey Responses
    final responses = await SurveyService().getSurveyResponses(
      _assignment.surveyId!,
    );

    // Parse answers
    Map<String, Map<String, String>> studentSubjectChoices =
        {}; // StudentId -> { SubjectID : TopicName }

    for (var r in responses) {
      final uid = r['userId'] as String?;
      final answers = r['answers'] as Map<String, dynamic>?;
      if (uid != null && answers != null) {
        studentSubjectChoices[uid] = {};
        answers.forEach((qId, val) {
          studentSubjectChoices[uid]![qId] = val.toString();
        });
      }
    }

    // 2. Pre-fetch Data
    final studentClasses = <String, String>{};
    for (var sid in _assignment.targetStudentIds) {
      final doc = await FirebaseFirestore.instance
          .collection('students')
          .doc(sid)
          .get();
      if (doc.exists) studentClasses[sid] = doc.data()?['classId'] ?? '';
    }

    final usedClassIds = studentClasses.values.toSet().toList();
    if (usedClassIds.isEmpty) return;

    // Fetch teachers for these classes
    // Chunking to 10
    final classLessonTeacherMap = <String, Map<String, String>>{};

    for (var i = 0; i < usedClassIds.length; i += 10) {
      final chunk = usedClassIds.sublist(
        i,
        i + 10 > usedClassIds.length ? usedClassIds.length : i + 10,
      );
      final snap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('classId', whereIn: chunk)
          .where('isActive', isEqualTo: true)
          .get();

      for (var d in snap.docs) {
        final data = d.data();
        final cid = data['classId'] as String;
        final lname = data['lessonName'] as String;
        final tid = data['teacherId'] as String;

        if (!classLessonTeacherMap.containsKey(cid))
          classLessonTeacherMap[cid] = {};
        classLessonTeacherMap[cid]![lname] = tid;
      }
    }

    // 3. Allocation Logic
    final newAllocations = <ProjectAllocation>[];
    final alreadyAssigned = _assignment.allocations
        .map((a) => a.studentId)
        .toSet();

    for (var sid in _assignment.targetStudentIds) {
      if (alreadyAssigned.contains(sid)) continue;

      final choices = studentSubjectChoices[sid];
      if (choices == null || choices.isEmpty) continue;

      final classId = studentClasses[sid];
      if (classId == null) continue;

      // Iterate user's subject choices
      for (var subjectId in choices.keys) {
        final chosenTopicName = choices[subjectId];

        // Find Subject
        final subject = _assignment.subjects.firstWhere(
          (s) => s.id == subjectId,
          orElse: () => ProjectSubject(
            id: '',
            lessonName: '',
            targetBranchIds: [],
            topics: [],
          ),
        );
        if (subject.id.isEmpty) continue;

        // Find Topic
        final topic = subject.topics.firstWhere(
          (t) => t.name == chosenTopicName,
          orElse: () => ProjectTopic(id: '', name: ''),
        );
        if (topic.id.isEmpty) continue;

        // Find Teacher
        final teacherMap = classLessonTeacherMap[classId];
        final teacherId = teacherMap?[subject.lessonName];

        if (teacherId == null) {
          print('No teacher found for ${subject.lessonName} in class $classId');
          continue;
        }

        // Check Quota (Global check for this teacher & topic)
        // Note: Quota in ProjectSubject/Topic is per Teacher.
        // We need to count allocations for THIS topic and THIS teacher.

        int currentCount = 0;
        currentCount += _assignment.allocations
            .where((a) => a.topicId == topic.id && a.teacherId == teacherId)
            .length;
        currentCount += newAllocations
            .where((a) => a.topicId == topic.id && a.teacherId == teacherId)
            .length;

        if (currentCount < topic.quotaPerTeacher) {
          // Assign
          newAllocations.add(
            ProjectAllocation(
              studentId: sid,
              topicId: topic.id,
              teacherId: teacherId,
              method: 'auto_survey',
              allocatedAt: DateTime.now(),
            ),
          );
        }
      }
    }

    if (newAllocations.isNotEmpty) {
      setState(() {
        _assignment.allocations.addAll(newAllocations);
      });
      await _service.updateProjectAssignment(_assignment);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${newAllocations.length} atama yapıldı.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Yeni atama yapılamadı (Kontenjan dolu veya veri eksik).',
          ),
        ),
      );
    }
  }

  void _showManualAssignDialog(String studentId) {
    showDialog(
      context: context,
      builder: (context) => ManualAssignDialog(
        assignment: _assignment,
        studentId: studentId,
        onAssign: (topicId, teacherId) async {
          setState(() {
            _assignment.allocations.add(
              ProjectAllocation(
                studentId: studentId,
                topicId: topicId,
                teacherId: teacherId,
                method: 'manual',
                allocatedAt: DateTime.now(),
              ),
            );
          });
          await _service.updateProjectAssignment(_assignment);
        },
      ),
    );
  }
}

// --- New Dialog Classes ---

class _ProjectSubjectDialog extends StatefulWidget {
  final String institutionId;
  final List<String> availableScopeBranchIds;
  final ProjectSubject? existingSubject;
  final Function(ProjectSubject) onSave;

  const _ProjectSubjectDialog({
    Key? key,
    required this.institutionId,
    required this.availableScopeBranchIds,
    this.existingSubject,
    required this.onSave,
  }) : super(key: key);

  @override
  State<_ProjectSubjectDialog> createState() => _ProjectSubjectDialogState();
}

class _ProjectSubjectDialogState extends State<_ProjectSubjectDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedLesson;
  List<String> _lessonList = []; // Will be fetched from server
  bool _isLoadingLessons = false;

  List<String> _selectedBranchIds = [];
  bool _isLoadingBranches = false;
  List<Map<String, dynamic>> _availableBranches = []; // {id, name}

  @override
  void initState() {
    super.initState();
    if (widget.existingSubject != null) {
      _selectedLesson = widget.existingSubject!.lessonName;
      _selectedBranchIds = List.from(widget.existingSubject!.targetBranchIds);
      if (!_lessonList.contains(_selectedLesson) && _selectedLesson != null) {
        _lessonList.add(_selectedLesson!);
      }
    } else {
      _selectedBranchIds = List.from(widget.availableScopeBranchIds);
    }
    Future.microtask(() {
      _loadBranches();
      _fetchLessons();
    });
  }

  Future<void> _fetchLessons() async {
    setState(() => _isLoadingLessons = true);
    try {
      // Find all lessons for this institution (and schoolType if possible, but institutionId is strict enough usually)
      final snapshot = await FirebaseFirestore.instance
          .collection('lessons')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final Set<String> uniqueLessonNames = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['lessonName'] as String?;
        if (name != null && name.isNotEmpty) {
          uniqueLessonNames.add(name);
        }
      }

      final loaded = uniqueLessonNames.toList()..sort();

      if (mounted) {
        setState(() {
          _lessonList = loaded;
          // Ensure selectedLesson is valid even if not in fetched list (e.g. deleted or custom)
          if (_selectedLesson != null &&
              !_lessonList.contains(_selectedLesson)) {
            _lessonList.add(_selectedLesson!);
            _lessonList.sort();
          }
        });
      }
    } catch (e) {
      print('Error fetching lessons: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLessons = false);
    }
  }

  Future<void> _loadBranches() async {
    if (!mounted) return;
    setState(() => _isLoadingBranches = true);
    try {
      Query query = FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true);

      final snapshot = await query.get();

      final allBranches = snapshot.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        return {
          'id': d.id,
          'name': (data['name'] ?? data['className'] ?? '').toString(),
        };
      }).toList();

      if (widget.availableScopeBranchIds.isNotEmpty) {
        _availableBranches = allBranches
            .where((b) => widget.availableScopeBranchIds.contains(b['id']))
            .toList();
      } else {
        _availableBranches = allBranches;
      }
      _availableBranches.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );
    } catch (e) {
      print(e);
    } finally {
      if (mounted) setState(() => _isLoadingBranches = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existingSubject != null ? 'Ders Düzenle' : 'Yeni Ders',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoadingLessons)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: _lessonList.contains(_selectedLesson)
                      ? _selectedLesson
                      : null,
                  items: _lessonList
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedLesson = v),
                  decoration: const InputDecoration(
                    labelText: 'Ders Seçimi (Sistem Kayıtlı)',
                  ),
                  validator: (v) => v == null ? 'Lütfen ders seçiniz' : null,
                  isExpanded: true,
                ),
              const SizedBox(height: 16),
              const Text(
                'Hangi Şubeler?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (_isLoadingBranches)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: LinearProgressIndicator(),
                )
              else if (_availableBranches.isEmpty)
                const Text(
                  'Hiç şube bulunamadı.',
                  style: TextStyle(color: Colors.red),
                )
              else
                Wrap(
                  spacing: 4,
                  runSpacing: 0,
                  children: _availableBranches.map((b) {
                    final isSelected = _selectedBranchIds.contains(b['id']);
                    return FilterChip(
                      label: Text(b['name']),
                      selected: isSelected,
                      onSelected: (v) {
                        setState(() {
                          if (v)
                            _selectedBranchIds.add(b['id']);
                          else
                            _selectedBranchIds.remove(b['id']);
                        });
                      },
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final subject = ProjectSubject(
                id:
                    widget.existingSubject?.id ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
                lessonName: _selectedLesson!,
                targetBranchIds: _selectedBranchIds,
                topics: widget.existingSubject?.topics ?? [],
              );
              widget.onSave(subject);
              Navigator.pop(context);
            }
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class _ProjectTopicDialog extends StatefulWidget {
  final ProjectTopic? existingTopic;
  final Function(ProjectTopic) onSave;

  const _ProjectTopicDialog({
    Key? key,
    this.existingTopic,
    required this.onSave,
  }) : super(key: key);

  @override
  State<_ProjectTopicDialog> createState() => _ProjectTopicDialogState();
}

class _ProjectTopicDialogState extends State<_ProjectTopicDialog> {
  final _controller = TextEditingController();
  final _quotaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existingTopic != null) {
      _controller.text = widget.existingTopic!.name;
      _quotaController.text = widget.existingTopic!.quotaPerTeacher.toString();
    } else {
      _quotaController.text = '5';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existingTopic != null ? 'Konu Düzenle' : 'Yeni Konu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Konu Başlığı (Örn: Matematik Projesi)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quotaController,
            decoration: const InputDecoration(
              labelText: 'Öğretmen Başına Kontenjan',
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_controller.text.isEmpty) return;
            final topic = ProjectTopic(
              id:
                  widget.existingTopic?.id ??
                  DateTime.now().millisecondsSinceEpoch.toString(),
              name: _controller.text,
              quotaPerTeacher: int.tryParse(_quotaController.text) ?? 5,
            );
            widget.onSave(topic);
            Navigator.pop(context);
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
