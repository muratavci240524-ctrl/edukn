import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../services/assessment_service.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import 'error_booklet_editor_screen.dart';
import 'error_booklet_student_list_screen.dart';

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
      body: StreamBuilder<List<TrialExam>>(
        stream: _assessmentService.getTrialExams(widget.institutionId),
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
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
        border: Border.all(color: isSelected ? Colors.indigo : Colors.indigo.withOpacity(0.05), width: isSelected ? 2 : 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: Checkbox(
          value: isSelected,
          activeColor: Colors.indigo,
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
        title: Text(
          exam.name,
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
        ),
        subtitle: Text(
          '${exam.examTypeName} - ${exam.date.day}/${exam.date.month}/${exam.date.year}',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildProgressBadge(exam),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.design_services_outlined, color: Colors.indigo),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (ctx) => ErrorBookletEditorScreen(exam: exam)),
                );
              },
              tooltip: 'Soruları Kırp',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBadge(TrialExam exam) {
    final total = _getTotalQuestions(exam);
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('trial_exams')
          .doc(exam.id)
          .collection('questions_pool')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        final isComplete = total > 0 && count >= total;
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isComplete ? Colors.green.shade50 : Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isComplete ? Colors.green.shade200 : Colors.indigo.shade100),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isComplete ? Icons.check_circle : Icons.collections_outlined,
                size: 14,
                color: isComplete ? Colors.green.shade700 : Colors.indigo,
              ),
              const SizedBox(width: 4),
              Text(
                '$count / $total',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isComplete ? Colors.green.shade700 : Colors.indigo,
                ),
              ),
            ],
          ),
        );
      },
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
