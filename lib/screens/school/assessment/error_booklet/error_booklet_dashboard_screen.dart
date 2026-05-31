import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../services/assessment_service.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import 'error_booklet_editor_screen.dart';
import 'error_booklet_student_list_screen.dart';
import '../../../../services/user_permission_service.dart';


class ErrorBookletDashboardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const ErrorBookletDashboardScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<ErrorBookletDashboardScreen> createState() => _ErrorBookletDashboardScreenState();
}

class _ErrorBookletDashboardScreenState extends State<ErrorBookletDashboardScreen> {
  final AssessmentService _assessmentService = AssessmentService();
  final Set<String> _selectedExamIds = {};
  List<TrialExam> _allExams = [];
  List<String>? _filterClassLevels;
  bool _isLoadingFilter = true;
  String? _realInstitutionId;

  @override
  void initState() {
    super.initState();
    _loadFilterData();
  }

  Future<void> _loadFilterData() async {
    if (!mounted) return;
    setState(() => _isLoadingFilter = true);
    try {
      final userData = await UserPermissionService.loadUserData();
      final userEmail = (userData?['email'] ?? FirebaseAuth.instance.currentUser?.email) ?? '';
      _realInstitutionId = await UserPermissionService.resolveInstitutionId(userEmail, userData: userData);

      // Use school_types root collection for filtering if that's the project standard
      final stDoc = await FirebaseFirestore.instance.collection('schoolTypes').doc(widget.schoolTypeId).get();
      
      if (stDoc.exists) {
        final data = stDoc.data();
        if (data != null && data['activeGrades'] != null) {
          List<String> grades = List<String>.from(data['activeGrades'].map((e) => e.toString()));
          
          if (userData != null && (userData['role'] == 'ogretmen' || userData['role'] == 'teacher')) {
            final classesQuery = await FirebaseFirestore.instance.collection('classes')
                .where('institutionId', isEqualTo: _realInstitutionId)
                .where('classTeacherId', isEqualTo: userData['authUserId'] ?? userData['id'])
                .get();
            
            if (classesQuery.docs.isNotEmpty) {
              final teacherGrades = classesQuery.docs.map((d) => d['classLevel'].toString()).toSet();
              grades = grades.where((g) => teacherGrades.contains(g)).toList();
              
              if (grades.isEmpty && teacherGrades.isNotEmpty) {
                grades = teacherGrades.toList();
              }
            }
          }
          _filterClassLevels = grades;
        }
      }
    } catch (e) {
      debugPrint('Error loading filter data: $e');
    } finally {
      if (mounted) setState(() => _isLoadingFilter = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Hata Kitapçığı Yönetimi',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.indigo.shade900),
        actions: [
          if (_selectedExamIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  '${_selectedExamIds.length} Sınav Seçildi',
                  style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: _isLoadingFilter 
        ? const Center(child: CircularProgressIndicator())
        : StreamBuilder<List<TrialExam>>(
        stream: _assessmentService.getTrialExams(
          _realInstitutionId ?? widget.institutionId, 
          classLevels: _filterClassLevels
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          
          _allExams = snapshot.data ?? [];
          
          if (_allExams.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_stories_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'Henüz tanımlanmış sınav bulunmuyor.',
                    style: GoogleFonts.inter(color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: _allExams.length,
            itemBuilder: (context, index) {
              final exam = _allExams[index];
              return _buildExamCard(exam);
            },
          );
        },
      ),
      floatingActionButton: _selectedExamIds.length >= 1
          ? FloatingActionButton.extended(
              onPressed: _openStudentListForSelected,
              backgroundColor: Colors.indigo,
              icon: const Icon(Icons.auto_awesome, color: Colors.white),
              label: Text(
                _selectedExamIds.length == 1 ? 'Öğrenci Listesi' : 'Karma Kitapçık Oluştur',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }

  void _openStudentListForSelected() {
    final selectedExams = _allExams.where((e) => _selectedExamIds.contains(e.id)).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ErrorBookletStudentListScreen(exams: selectedExams),
      ),
    );
  }

  Widget _buildExamCard(TrialExam exam) {
    bool isSelected = _selectedExamIds.contains(exam.id);
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    
    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(
          color: isSelected ? Colors.indigo : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedExamIds.remove(exam.id);
            } else {
              _selectedExamIds.add(exam.id);
            }
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Checkbox
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: isSelected,
                  activeColor: Colors.indigo,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedExamIds.add(exam.id);
                      } else {
                        _selectedExamIds.remove(exam.id);
                      }
                    });
                  },
                ),
              ),
              SizedBox(width: isMobile ? 8 : 12),
              // Title & Subtitle Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    Text(
                      exam.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 13 : 16,
                        color: Colors.indigo.shade900,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Subtitle (thin text: Sınav Türü - Tarih - Soru/Soru)
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('trial_exams')
                          .doc(exam.id)
                          .collection('questions_pool')
                          .snapshots(),
                      builder: (context, snapshot) {
                        final count = snapshot.data?.docs.length ?? 0;
                        final total = _getTotalQuestions(exam);
                        final formattedDate = '${exam.date.day}/${exam.date.month}/${exam.date.year}';
                        
                        return Text(
                          '${exam.examTypeName} - $formattedDate - $count/$total',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 10 : 12,
                            fontWeight: FontWeight.w400,
                            color: Colors.blueGrey.shade500,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action Button (Crop Questions)
              Material(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
                child: IconButton(
                  icon: Icon(Icons.design_services_outlined, color: Colors.indigo, size: isMobile ? 18 : 20),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (ctx) => ErrorBookletEditorScreen(exam: exam)),
                    );
                  },
                  constraints: BoxConstraints(
                    minWidth: isMobile ? 32 : 38,
                    minHeight: isMobile ? 32 : 38,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'Soruları Kırp',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _getTotalQuestions(TrialExam exam) {
    if (exam.answerKeys.isEmpty) return 0;
    try {
      final firstBooklet = exam.answerKeys.keys.first;
      final subjects = exam.answerKeys[firstBooklet] ?? {};
      int total = 0;
      subjects.forEach((_, answers) => total += answers.trim().length);
      return total;
    } catch (e) {
      return 0;
    }
  }
}
