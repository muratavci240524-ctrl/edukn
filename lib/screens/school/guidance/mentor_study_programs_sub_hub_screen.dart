import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'guidance_study_program_screen.dart';
import 'saved_study_programs_screen.dart';
import 'saved_templates_screen.dart';
import 'study_template_creation_screen.dart';
import '../../../widgets/edukn_logo.dart';
import '../../../services/user_permission_service.dart';

class MentorStudyProgramsSubHubScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const MentorStudyProgramsSubHubScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<MentorStudyProgramsSubHubScreen> createState() =>
      _MentorStudyProgramsSubHubScreenState();
}

class _MentorStudyProgramsSubHubScreenState
    extends State<MentorStudyProgramsSubHubScreen> {
  bool _isLoading = true;
  bool _isStatsLoading = true;
  Map<String, dynamic>? _userData;

  int _totalPrograms = 0;
  int _recentPrograms = 0;
  int _evaluatedPrograms = 0;
  int _totalTasks = 0;
  int _completedTasks = 0;

  bool _hasNoMentorStudents = false;
  List<String> _assignedStudentIds = [];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    if (_userData == null) {
      setState(() => _isLoading = true);
    }
    setState(() => _isStatsLoading = true);
    try {
      _userData = await UserPermissionService.loadUserData();
      final role = (_userData?['role'] as String?)?.toLowerCase() ?? '';
      final bool isTeacher = role == 'ogretmen' || role == 'rehber_ogretmen';

      if (isTeacher) {
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        if (currentUserId != null) {
          final assignedStudentsQuery = await FirebaseFirestore.instance
              .collection('students')
              .where('institutionId', isEqualTo: widget.institutionId)
              .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
              .where('mentorId', isEqualTo: currentUserId)
              .where('isActive', isEqualTo: true)
              .get();

          if (assignedStudentsQuery.docs.isEmpty) {
            setState(() {
              _hasNoMentorStudents = true;
              _assignedStudentIds = [];
              _isLoading = false;
              _isStatsLoading = false;
            });
            return;
          } else {
            _hasNoMentorStudents = false;
            _assignedStudentIds =
                assignedStudentsQuery.docs.map((d) => d.id).toList();
          }
        }
      } else {
        _hasNoMentorStudents = false;
        _assignedStudentIds = [];
      }

      // Render sub-hub action buttons instantly
      if (mounted) {
        setState(() => _isLoading = false);
      }

      // Load statistics in background
      _fetchProgramsAndStatsAsync();
    } catch (e) {
      debugPrint("Error loading sub-hub data: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isStatsLoading = false;
        });
      }
    }
  }

  Future<void> _fetchProgramsAndStatsAsync() async {
    try {
      int totalProgs = 0;
      if (_assignedStudentIds.isNotEmpty) {
        final chunks = <List<String>>[];
        for (var i = 0; i < _assignedStudentIds.length; i += 30) {
          chunks.add(
            _assignedStudentIds.sublist(
              i,
              i + 30 > _assignedStudentIds.length
                  ? _assignedStudentIds.length
                  : i + 30,
            ),
          );
        }
        for (var chunk in chunks) {
          final countQuery = await FirebaseFirestore.instance
              .collection('institutions')
              .doc(widget.institutionId)
              .collection('study_programs')
              .where('studentId', whereIn: chunk)
              .count()
              .get();
          totalProgs += countQuery.count ?? 0;
        }
      } else {
        final countQuery = await FirebaseFirestore.instance
            .collection('institutions')
            .doc(widget.institutionId)
            .collection('study_programs')
            .count()
            .get();
        totalProgs = countQuery.count ?? 0;
      }

      final fortyFiveDaysAgo = DateTime.now().subtract(const Duration(days: 45));
      final query = await FirebaseFirestore.instance
          .collection('institutions')
          .doc(widget.institutionId)
          .collection('study_programs')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(fortyFiveDaysAgo))
          .get();

      int evaluatedProgs = 0;
      int totTasks = 0;
      int compTasks = 0;
      int recentProgs = 0;

      int processCount = 0;
      for (var doc in query.docs) {
        processCount++;
        if (processCount % 15 == 0) {
          await Future.delayed(Duration.zero);
        }
        final data = doc.data() as Map<String, dynamic>;
        final studentId = data['studentId']?.toString();
        if (_assignedStudentIds.isNotEmpty &&
            !_assignedStudentIds.contains(studentId)) {
          continue;
        }

        recentProgs++;

        bool hasEvaluation =
            data['mentorEvaluation'] != null &&
            data['mentorEvaluation'].toString().trim().isNotEmpty;

        if (hasEvaluation) {
          evaluatedProgs++;
        }

        int studentTotal = 0;
        int studentCompleted = 0;

        if (data['executionStatus'] != null) {
          final statusMap = data['executionStatus'] as Map<String, dynamic>;
          statusMap.forEach((key, val) {
            if (val is List) {
              final list = List<int>.from(val);
              studentTotal += list.length;
              studentCompleted += list.where((s) => s == 1).length;
            }
          });
        }

        totTasks += studentTotal;
        compTasks += studentCompleted;
      }

      if (mounted) {
        setState(() {
          _totalPrograms = totalProgs;
          _recentPrograms = recentProgs;
          _evaluatedPrograms = evaluatedProgs;
          _totalTasks = totTasks;
          _completedTasks = compTasks;
          _isStatsLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching programs and stats: $e");
      if (mounted) {
        setState(() => _isStatsLoading = false);
      }
    }
  }

  void _navigateToCreate() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GuidanceStudyProgramScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          allowedStudentIds:
              _assignedStudentIds.isNotEmpty ? _assignedStudentIds : null,
        ),
      ),
    ).then((_) => _loadAllData());
  }

  void _navigateToSaved() {
    final role = (_userData?['role'] as String?)?.toLowerCase();
    final bool isTeacher = role == 'ogretmen' || role == 'rehber_ogretmen';
    List<String>? allowedClassNames;
    List<String>? allowedStudentIds =
        _assignedStudentIds.isNotEmpty ? _assignedStudentIds : null;

    if (isTeacher && allowedStudentIds == null) {
      if (_userData?['classNames'] != null) {
        allowedClassNames = List<String>.from(_userData!['classNames']);
      }
      if (_userData?['studentIds'] != null) {
        allowedStudentIds = List<String>.from(_userData!['studentIds']);
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SavedStudyProgramsScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          isTeacher: isTeacher,
          allowedClassNames: allowedClassNames,
          allowedStudentIds: allowedStudentIds,
        ),
      ),
    ).then((_) => _loadAllData());
  }

  void _navigateToTemplates() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SavedTemplatesScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
        ),
      ),
    ).then((_) => _loadAllData());
  }

  void _navigateToCreateTemplate() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudyTemplateCreationScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
        ),
      ),
    ).then((_) => _loadAllData());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F4F6),
        body: Center(child: EduKnLoader(size: 80.0)),
      );
    }

    if (_hasNoMentorStudents) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Çalışma Programı Modülü',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
          ),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 4,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 48),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Mentörlük Çalışması Bulunamadı',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.grey.shade900),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Adınıza tanımlanmış aktif bir mentörlük/öğrenci çalışması bulunmamaktadır.\nLütfen kurum yöneticinizle iletişime geçin.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.5),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 150,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text('Geri Dön',
                            style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final double completionRate =
        _totalTasks > 0 ? (_completedTasks / _totalTasks * 100) : 0;
    final double feedbackRate =
        _recentPrograms > 0 ? (_evaluatedPrograms / _recentPrograms * 100) : 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(
          'Çalışma Programı Modülü',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBanner(),
            const SizedBox(height: 24),
            _buildStatsGrid(completionRate, feedbackRate),
            const SizedBox(height: 32),
            Text(
              'Hızlı İşlemler',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.indigo.shade900),
            ),
            const SizedBox(height: 12),
            _buildActionHub(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade700, Colors.indigo.shade900],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Haftalık Çalışma Programları',
            style: GoogleFonts.inter(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const SizedBox(height: 6),
          Text(
            'Haftalık görev tanımlamaları yapın, öğrencilerin ödev onaylarını kontrol edin ve ilerleme yüzdelerini canlı izleyin.',
            style: GoogleFonts.inter(
                color: Colors.indigo.shade100, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(double completionRate, double feedbackRate) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 900
            ? 4
            : (constraints.maxWidth > 500 ? 2 : 1);
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          childAspectRatio: 1.8,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _buildStatCard('Toplam Tanımlı Program', _isStatsLoading ? '...' : '$_totalPrograms',
                Icons.assignment, Colors.blue),
            _buildStatCard('Geribildirim Oranı', _isStatsLoading ? '...' : '%${feedbackRate.round()}',
                Icons.feedback, Colors.green),
            _buildStatCard('Ödev Tamamlama Oranı', _isStatsLoading ? '...' : '%${completionRate.round()}',
                Icons.offline_pin, Colors.orange),
            _buildStatCard(
                'Toplam Görev', _isStatsLoading ? '...' : '$_totalTasks', Icons.format_list_bulleted, Colors.purple),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.grey.shade900),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionHub() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 900
            ? 4
            : (constraints.maxWidth > 500 ? 2 : 1);
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          childAspectRatio: 1.3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _buildActionCard(
              title: 'Yeni Program Tanımla',
              subtitle:
                  'Gemini Yapay Zeka destekli deneme analizi veya şablondan program üretin.',
              icon: Icons.add_task_rounded,
              color: Colors.indigo,
              onTap: _navigateToCreate,
            ),
            _buildActionCard(
              title: 'Çalışma Programları',
              subtitle:
                  'Kayıtlı programları inceleyin, durum güncelleyin, mentör değerlendirmesi yazın.',
              icon: Icons.library_books_rounded,
              color: Colors.teal,
              onTap: _navigateToSaved,
            ),
            _buildActionCard(
              title: 'Ders Şablonları',
              subtitle:
                  'Grup ve seviye bazlı çalışma programı taslaklarını listeyin.',
              icon: Icons.table_chart_rounded,
              color: Colors.purple,
              onTap: _navigateToTemplates,
            ),
            _buildActionCard(
              title: 'Yeni Şablon Ekle',
              subtitle:
                  'Grup bazlı hızlı atamalar için sıfırdan haftalık program taslağı tasarlayın.',
              icon: Icons.dashboard_customize_rounded,
              color: Colors.amber.shade900,
              onTap: _navigateToCreateTemplate,
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              Text(
                title,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.grey.shade900),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 10, color: Colors.grey.shade500, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
