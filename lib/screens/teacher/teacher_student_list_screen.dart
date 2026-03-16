import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/user_permission_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../school/student_detail_view_screen.dart';

class TeacherStudentListScreen extends StatefulWidget {
  final String institutionId;

  const TeacherStudentListScreen({Key? key, required this.institutionId}) : super(key: key);

  @override
  State<TeacherStudentListScreen> createState() => _TeacherStudentListScreenState();
}

class _TeacherStudentListScreenState extends State<TeacherStudentListScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _students = [];
  String _searchQuery = '';
  String? _selectedLevel;
  String? _selectedBranch;

  List<String> get _availableLevels {
    final levels = _students
        .map((s) => s['classLevel']?.toString())
        .where((l) => l != null && l.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    levels.sort();
    return levels;
  }

  List<String> get _availableBranches {
    final branches = _students
        .map((s) => s['className']?.toString())
        .where((b) => b != null && b.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    branches.sort();
    return branches;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final userData = await UserPermissionService.loadUserData();
      final teacherId = userData?['id'] ?? user.uid;
      final instId = userData?['institutionId'] ?? widget.institutionId;

      // 1. Atanmış sınıfları bul
      final assignmentsSnap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: instId)
          .where('teacherIds', arrayContains: teacherId)
          .where('isActive', isEqualTo: true)
          .get();

      final classIds = assignmentsSnap.docs
          .map((doc) => doc.data()['classId']?.toString())
          .where((id) => id != null)
          .cast<String>()
          .toSet();

      if (classIds.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // 2. Bu sınıflardaki öğrencileri bul
      List<Map<String, dynamic>> allStudents = [];
      final classIdList = classIds.toList();

      for (var i = 0; i < classIdList.length; i += 10) {
        final chunk = classIdList.skip(i).take(10).toList();
        final studentSnap = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('classId', whereIn: chunk)
            .get();
        
        for (var doc in studentSnap.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          allStudents.add(data);
        }
      }

      // Ada göre sırala
      allStudents.sort((a, b) => (a['fullName'] ?? '').toString().compareTo((b['fullName'] ?? '').toString()));

      if (mounted) {
        setState(() {
          _students = allStudents;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Öğrenci listesi yükleme hatası: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredStudents = _students.where((s) {
      final name = (s['fullName'] ?? '').toString().toLowerCase();
      final matchesSearch = name.contains(_searchQuery.toLowerCase());
      
      final level = s['classLevel']?.toString();
      final branch = s['className']?.toString();
      
      final matchesLevel = _selectedLevel == null || level == _selectedLevel;
      final matchesBranch = _selectedBranch == null || branch == _selectedBranch;
      
      return matchesSearch && matchesLevel && matchesBranch;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Tanımlı Öğrencilerim', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.indigo,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          _buildSearchAndFilters(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredStudents.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredStudents.length,
                        itemBuilder: (context, index) {
                          final student = filteredStudents[index];
                          return _buildStudentCard(student);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showStudentCard(Map<String, dynamic> student) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentDetailViewScreen(
          student: student,
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final levels = _availableLevels;
    final branches = _availableBranches;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.indigo,
      child: Column(
        children: [
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Öğrenci ara...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
              prefixIcon: const Icon(Icons.search, color: Colors.white),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          if (levels.isNotEmpty || branches.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (levels.isNotEmpty)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          dropdownColor: Colors.indigo.shade800,
                          value: _selectedLevel,
                          hint: const Text('Sınıf', style: TextStyle(color: Colors.white, fontSize: 13)),
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
                          style: const TextStyle(color: Colors.white),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Tümü')),
                            ...levels.map((l) => DropdownMenuItem(value: l, child: Text('$l. Sınıf'))),
                          ],
                          onChanged: (val) => setState(() => _selectedLevel = val),
                        ),
                      ),
                    ),
                  ),
                if (levels.isNotEmpty && branches.isNotEmpty) const SizedBox(width: 12),
                if (branches.isNotEmpty)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          dropdownColor: Colors.indigo.shade800,
                          value: _selectedBranch,
                          hint: const Text('Şube', style: TextStyle(color: Colors.white, fontSize: 13)),
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 20),
                          style: const TextStyle(color: Colors.white),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Tümü')),
                            ...branches.map((b) => DropdownMenuItem(value: b, child: Text('$b Şubesi'))),
                          ],
                          onChanged: (val) => setState(() => _selectedBranch = val),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.indigo.shade50,
          child: Text(
            (student['fullName'] ?? '?')[0].toUpperCase(),
            style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(student['fullName'] ?? 'İsimsiz Öğrenci', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Şube: ${student['className'] ?? 'Belirtilmemiş'}'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        onTap: () => _showStudentCard(student),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'Tanımlı öğrenciniz bulunamadı' : 'Aramanıza uygun öğrenci bulunamadı',
            style: GoogleFonts.inter(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
