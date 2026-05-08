import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/edukn_logo.dart';

class ParentStudentSelectionScreen extends StatelessWidget {
  final String institutionId;
  final String parentTcNo;
  final List<Map<String, dynamic>> students;

  const ParentStudentSelectionScreen({
    Key? key,
    required this.institutionId,
    required this.parentTcNo,
    required this.students,
  }) : super(key: key);

  Future<void> _selectStudent(BuildContext context, Map<String, dynamic> student) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_student_id', student['id']);
    await prefs.setString('selected_student_name', student['fullName'] ?? '');
    
    // Yönlendirme
    Navigator.pushReplacementNamed(context, '/school-dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const EduKnLogo(type: EduKnLogoType.iconOnly, iconSize: 60),
                const SizedBox(height: 24),
                Text(
                  'Öğrenci Seçimi',
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1E2661),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'İşlem yapmak istediğiniz öğrenciyi seçiniz.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.blueGrey.shade600,
                  ),
                ),
                const SizedBox(height: 40),
                Expanded(
                  child: ListView.separated(
                    itemCount: students.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final student = students[index];
                      return _buildStudentCard(context, student);
                    },
                  ),
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/school-login'),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Çıkış Yap'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentCard(BuildContext context, Map<String, dynamic> student) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.shade100.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: Colors.indigo.shade50),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _selectStudent(context, student),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    student['gender'] == 'Kız' ? Icons.face_3_rounded : Icons.face_6_rounded,
                    color: Colors.indigo.shade700,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student['fullName'] ?? 'İsimsiz Öğrenci',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E2661),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${student['className'] ?? ''} - No: ${student['studentNumber'] ?? ''}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.indigo.shade200,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
