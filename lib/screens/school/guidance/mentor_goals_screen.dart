import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../widgets/edukn_logo.dart';
import '../../../services/user_permission_service.dart';
import '../../../services/crypto_service.dart';

class MentorGoalsScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const MentorGoalsScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<MentorGoalsScreen> createState() => _MentorGoalsScreenState();
}

class _MentorGoalsScreenState extends State<MentorGoalsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  String _searchQuery = '';
  Map<String, dynamic>? _userData;
  
  Map<String, dynamic>? _selectedStudent;
  
  // Controllers
  final _formKey = GlobalKey<FormState>();
  final _pointsController = TextEditingController();
  final _netsController = TextEditingController();
  final _schoolController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _pointsController.dispose();
    _netsController.dispose();
    _schoolController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _userData = await UserPermissionService.loadUserData();
      final role = (_userData?['role'] as String?)?.toLowerCase() ?? '';
      final bool isTeacher = role == 'ogretmen' || role == 'rehber_ogretmen';
      
      Query query = FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true);

      if (isTeacher) {
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        if (currentUserId != null) {
          query = query.where('mentorId', isEqualTo: currentUserId);
        }
      }

      final querySnapshot = await query.get();
      final list = querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        data['fullName'] = data['fullName'] ?? '${data['name'] ?? ''} ${data['surname'] ?? ''}'.trim();
        return data;
      }).toList();

      list.sort((a, b) => (a['fullName'] as String).compareTo(b['fullName'] as String));

      setState(() {
        _students = list;
        _filteredStudents = list;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading students for goals: $e");
      setState(() => _isLoading = false);
    }
  }

  void _filter(String query) {
    setState(() {
      _searchQuery = query;
      _filteredStudents = _students
          .where((s) => s['fullName'].toString().toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  void _selectStudent(Map<String, dynamic> student) {
    setState(() {
      _selectedStudent = student;
      final goals = student['mentorGoals'] as Map<String, dynamic>?;
      _pointsController.text = goals?['points']?.toString() ?? '';
      _netsController.text = goals?['nets']?.toString() ?? '';
      _schoolController.text = goals?['targetSchool']?.toString() ?? '';
      _notesController.text = CryptoService.decrypt(goals?['notes']?.toString(), institutionId: widget.institutionId);
    });
  }

  Future<void> _saveGoals() async {
    if (_selectedStudent == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final double? points = double.tryParse(_pointsController.text.trim());
      final double? nets = double.tryParse(_netsController.text.trim());
      final String school = _schoolController.text.trim();
      final String notes = CryptoService.encrypt(_notesController.text.trim(), institutionId: widget.institutionId);

      final goalsMap = {
        'points': points,
        'nets': nets,
        'targetSchool': school,
        'notes': notes,
        'updatedAt': Timestamp.now(),
      };

      await FirebaseFirestore.instance
          .collection('students')
          .doc(_selectedStudent!['id'])
          .update({'mentorGoals': goalsMap});

      // Update local state
      setState(() {
        _selectedStudent!['mentorGoals'] = goalsMap;
        final idx = _students.indexWhere((s) => s['id'] == _selectedStudent!['id']);
        if (idx != -1) {
          _students[idx]['mentorGoals'] = goalsMap;
        }
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hedefler başarıyla güncellendi.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          backgroundColor: Colors.teal.shade600,
        ),
      );
    } catch (e) {
      debugPrint("Error saving goals: $e");
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F4F6),
        body: Center(child: EduKnLoader(size: 80.0)),
      );
    }

    final isMobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(
          'Hedef Belirleme Modülü',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isMobile ? _buildMobileBody() : _buildDesktopBody(),
    );
  }

  Widget _buildDesktopBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Student List panel
        Container(
          width: 380,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: Colors.grey.shade200)),
          ),
          child: _buildStudentListPanel(),
        ),
        // Right edit details panel
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: _buildEditPanel(),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBody() {
    if (_selectedStudent != null) {
      return WillPopScope(
        onWillPop: () async {
          setState(() => _selectedStudent = null);
          return false;
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _buildEditPanel(),
        ),
      );
    }
    return _buildStudentListPanel();
  }

  Widget _buildStudentListPanel() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Öğrenci Ara...',
              prefixIcon: const Icon(Icons.search, color: Colors.indigo),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
            onChanged: _filter,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _filteredStudents.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      _searchQuery.isEmpty ? 'Aktif mentörlük yaptığınız öğrenci kaydı bulunamadı.' : 'Öğrenci bulunamadı.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _filteredStudents.length,
                  separatorBuilder: (c, idx) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final s = _filteredStudents[index];
                    final isSelected = _selectedStudent != null && _selectedStudent!['id'] == s['id'];
                    final goals = s['mentorGoals'] as Map<String, dynamic>?;
                    final targetSchool = goals?['targetSchool'] as String?;

                    return ListTile(
                      selected: isSelected,
                      selectedColor: Colors.indigo,
                      selectedTileColor: Colors.indigo.shade50,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: isSelected ? Colors.indigo : Colors.grey.shade100,
                        child: Text(
                          s['fullName'].substring(0, 1).toUpperCase(),
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.indigo,
                          ),
                        ),
                      ),
                      title: Text(
                        s['fullName'],
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isSelected ? Colors.indigo.shade900 : Colors.black87,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sınıf/Şube: ${s['className'] ?? 'Belirtilmemiş'}',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
                          ),
                          if (targetSchool != null && targetSchool.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  'Hedef: $targetSchool',
                                  style: GoogleFonts.inter(fontSize: 9, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                      onTap: () => _selectStudent(s),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEditPanel() {
    if (_selectedStudent == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 100),
            Icon(Icons.track_changes_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              "Hedeflerini düzenlemek için listeden bir öğrenci seçiniz.",
              style: GoogleFonts.inter(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Student Header card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.indigo.shade900,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white.withOpacity(0.15),
                  child: Text(
                    _selectedStudent!['fullName'].substring(0, 1).toUpperCase(),
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedStudent!['fullName'],
                        style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sınıf: ${_selectedStudent!['className'] ?? 'Bilinmeyen'} • Öğrenci No: ${_selectedStudent!['studentNo'] ?? '-'}',
                        style: GoogleFonts.inter(color: Colors.indigo.shade100, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // Close button for mobile view
                if (MediaQuery.of(context).size.width < 900)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => setState(() => _selectedStudent = null),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Hedef Bilgilerini Tanımlayın',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.indigo.shade900),
          ),
          const SizedBox(height: 16),

          // Points field
          TextFormField(
            controller: _pointsController,
            keyboardType: TextInputType.number,
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Puan Hedefi',
              hintText: 'Örn: 480.50',
              prefixIcon: const Icon(Icons.auto_awesome, color: Colors.indigo),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
            ),
            validator: (val) {
              if (val != null && val.isNotEmpty && double.tryParse(val) == null) {
                return 'Geçerli bir sayı giriniz.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Nets field
          TextFormField(
            controller: _netsController,
            keyboardType: TextInputType.number,
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Net Hedefi',
              hintText: 'Örn: 85.25',
              prefixIcon: const Icon(Icons.format_list_bulleted_rounded, color: Colors.indigo),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
            ),
            validator: (val) {
              if (val != null && val.isNotEmpty && double.tryParse(val) == null) {
                return 'Geçerli bir sayı giriniz.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Target School field
          TextFormField(
            controller: _schoolController,
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: 'Hedef Okul / Program (Lise veya Üniversite)',
              hintText: 'Örn: Galatasaray Lisesi veya ODTÜ Bilgisayar',
              prefixIcon: const Icon(Icons.school, color: Colors.indigo),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
            ),
          ),
          const SizedBox(height: 16),

          // Notes field
          TextFormField(
            controller: _notesController,
            maxLines: 4,
            style: GoogleFonts.inter(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Rehberlik / Mentör Notları',
              hintText: 'Öğrencinin hedefe bağlılığı ve takip durumu hakkında notlar ekleyin...',
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 50.0),
                child: Icon(Icons.note_alt_outlined, color: Colors.indigo),
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
            ),
          ),
          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveGoals,
              icon: _isSaving 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_rounded, color: Colors.white),
              label: Text(
                _isSaving ? 'Kaydediliyor...' : 'Hedefleri Kaydet',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
