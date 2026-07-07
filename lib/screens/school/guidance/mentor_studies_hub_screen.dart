import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'mentor_goals_screen.dart';
import 'mentor_study_programs_sub_hub_screen.dart';
import 'guidance_interview_screen.dart';
import 'mentor_reports_screen.dart';
import 'mentor_assignment_dialog.dart';
import '../../../widgets/edukn_logo.dart';
import '../../../services/user_permission_service.dart';

class MentorStudiesHubScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const MentorStudiesHubScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<MentorStudiesHubScreen> createState() => _MentorStudiesHubScreenState();
}

class _MentorStudiesHubScreenState extends State<MentorStudiesHubScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isAuditLoading = true;
  Map<String, dynamic>? _userData;

  // Study programs stats
  Map<String, Map<String, int>> _teacherFeedbackStats = {};
  List<Map<String, dynamic>> _sortedStudentsRisk = [];

  // Goal tracking stats
  List<Map<String, dynamic>> _goalStatusList = [];

  // Guidance interviews stats
  Map<String, int> _interviewerStats = {};

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    // If we already have data, avoid showing full screen loader to keep transitions instant
    if (_userData == null || _goalStatusList.isEmpty) {
      setState(() => _isLoading = true);
    }
    setState(() => _isAuditLoading = true);

    try {
      _userData = await UserPermissionService.loadUserData();
      final role = (_userData?['role'] as String?)?.toLowerCase() ?? '';
      final bool isTeacher = role == 'ogretmen' || role == 'rehber_ogretmen';
      
      // 1. Fetch Assigned Students & Active Students (fast query)
      List<String> assignedStudentIds = [];
      if (isTeacher) {
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        if (currentUserId != null) {
          final assignedQuery = await FirebaseFirestore.instance
              .collection('students')
              .where('institutionId', isEqualTo: widget.institutionId)
              .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
              .where('mentorId', isEqualTo: currentUserId)
              .where('isActive', isEqualTo: true)
              .get();
          assignedStudentIds = assignedQuery.docs.map((d) => d.id).toList();
        }
      }

      // Fetch students for goal tracking
      Query studentsQuery = FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true);
      
      if (isTeacher) {
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        if (currentUserId != null) {
          studentsQuery = studentsQuery.where('mentorId', isEqualTo: currentUserId);
        }
      }
      
      final studentsSnapshot = await studentsQuery.get();
      final allStudents = studentsSnapshot.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        data['id'] = d.id;
        data['fullName'] = data['fullName'] ?? '${data['name'] ?? ''} ${data['surname'] ?? ''}'.trim();
        return data;
      }).toList();

      // Analyze goals
      _goalStatusList = allStudents.map((s) {
        final goals = s['mentorGoals'] as Map<String, dynamic>?;
        final bool hasGoals = goals != null && 
            (goals['points'] != null || goals['nets'] != null || (goals['targetSchool'] != null && goals['targetSchool'].toString().isNotEmpty));
        return {
          'name': s['fullName'],
          'class': s['className'] ?? 'Sınıfsız',
          'hasGoals': hasGoals,
          'goals': goals,
        };
      }).toList();
      _goalStatusList.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      // Immediate render of premium cards
      if (mounted) {
        setState(() => _isLoading = false);
      }

      // 2. Perform heavy calculations asynchronously in the background
      _loadAuditDataAsync(isTeacher, assignedStudentIds);

    } catch (e) {
      debugPrint("Error loading core data: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isAuditLoading = false;
        });
      }
    }
  }

  Future<void> _loadAuditDataAsync(bool isTeacher, List<String> assignedStudentIds) async {
    try {
      final fortyFiveDaysAgo = DateTime.now().subtract(const Duration(days: 45));
      Query programsQuery = FirebaseFirestore.instance
          .collection('institutions')
          .doc(widget.institutionId)
          .collection('study_programs')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(fortyFiveDaysAgo));

      final progSnapshot = await programsQuery.get();

      Map<String, Map<String, int>> teacherFeedback = {};
      Map<String, Map<String, dynamic>> studentRisk = {};

      int processCount = 0;
      for (var doc in progSnapshot.docs) {
        processCount++;
        if (processCount % 15 == 0) {
          await Future.delayed(Duration.zero);
        }
        final data = doc.data() as Map<String, dynamic>;
        final studentId = data['studentId']?.toString();
        
        if (isTeacher && assignedStudentIds.isNotEmpty && !assignedStudentIds.contains(studentId)) {
          continue;
        }

        String teacher = data['creatorName'] ?? 'Bilinmiyor';
        bool hasEvaluation = data['mentorEvaluation'] != null && data['mentorEvaluation'].toString().trim().isNotEmpty;
        
        teacherFeedback.putIfAbsent(teacher, () => {'assigned': 0, 'evaluated': 0});
        teacherFeedback[teacher]!['assigned'] = teacherFeedback[teacher]!['assigned']! + 1;
        if (hasEvaluation) {
          teacherFeedback[teacher]!['evaluated'] = teacherFeedback[teacher]!['evaluated']! + 1;
        }

        int studentTotal = 0;
        int studentCompleted = 0;
        int studentMissed = 0;
        int studentIncomplete = 0;

        if (data['executionStatus'] != null) {
          final statusMap = data['executionStatus'] as Map<String, dynamic>;
          statusMap.forEach((key, val) {
            if (val is List) {
              final list = List<int>.from(val);
              studentTotal += list.length;
              studentCompleted += list.where((s) => s == 1).length;
              studentIncomplete += list.where((s) => s == 2).length;
              studentMissed += list.where((s) => s == 3).length;
            }
          });
        }

        String studentName = data['studentName'] ?? 'Bilinmiyor';
        String branch = data['studentBranch'] ?? data['className'] ?? 'Sınıfsız';
        
        studentRisk.putIfAbsent(studentName, () => {
          'totalTasks': 0,
          'completedTasks': 0,
          'missedTasks': 0,
          'incompleteTasks': 0,
          'branch': branch,
        });

        studentRisk[studentName]!['totalTasks'] = studentRisk[studentName]!['totalTasks'] + studentTotal;
        studentRisk[studentName]!['completedTasks'] = studentRisk[studentName]!['completedTasks'] + studentCompleted;
        studentRisk[studentName]!['incompleteTasks'] = studentRisk[studentName]!['incompleteTasks'] + studentIncomplete;
        studentRisk[studentName]!['missedTasks'] = studentRisk[studentName]!['missedTasks'] + studentMissed;
      }

      _teacherFeedbackStats = teacherFeedback;

      var sortedRisk = studentRisk.entries.map((e) => {
        'name': e.key,
        'totalTasks': e.value['totalTasks'],
        'completedTasks': e.value['completedTasks'],
        'missedTasks': e.value['missedTasks'],
        'incompleteTasks': e.value['incompleteTasks'],
        'branch': e.value['branch'],
      }).toList();

      sortedRisk.sort((a, b) {
        int failedA = (a['missedTasks'] as int) + (a['incompleteTasks'] as int);
        int failedB = (b['missedTasks'] as int) + (b['incompleteTasks'] as int);
        return failedB.compareTo(failedA);
      });
      _sortedStudentsRisk = sortedRisk;

      // 3. Fetch guidance interviews (last 30 days)
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      Query interviewsQuery = FirebaseFirestore.instance
          .collection('guidance_interviews')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId);
      
      final intSnapshot = await interviewsQuery.get();
      Map<String, int> interviewerCounts = {};

      for (var doc in intSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final dateStamp = data['date'] as Timestamp?;
        if (dateStamp == null || dateStamp.toDate().isBefore(thirtyDaysAgo)) {
          continue;
        }
        String interviewer = data['interviewerName'] ?? 'Bilinmiyor';
        interviewerCounts[interviewer] = (interviewerCounts[interviewer] ?? 0) + 1;
      }
      _interviewerStats = interviewerCounts;

      if (mounted) {
        setState(() => _isAuditLoading = false);
      }
    } catch (e) {
      debugPrint("Error loading async audit: $e");
      if (mounted) {
        setState(() => _isAuditLoading = false);
      }
    }
  }

  void _showMentorAssignmentSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MentorAssignmentDialog(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
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

    final role = (_userData?['role'] as String?)?.toLowerCase() ?? '';
    final bool isAdmin = role == 'genel_mudur' || role == 'mudur' || role == 'mudur_yardimcisi' || role == 'admin' || role == 'superadmin';
    final bool isTeacher = role == 'ogretmen' || role == 'rehber_ogretmen';
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(
          'Mentör Çalışmaları Portalı',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_rounded),
              tooltip: 'Mentör Atama Yönetimi',
              onPressed: _showMentorAssignmentSheet,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBanner(),
            const SizedBox(height: 28),
            Text(
              'Mentörlük Modülleri',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.indigo.shade900,
              ),
            ),
            const SizedBox(height: 12),
            _buildModulesGrid(isTeacher, currentUserId),
            const SizedBox(height: 32),
            Text(
              'Performans ve Risk Denetim Paneli',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.indigo.shade900,
              ),
            ),
            const SizedBox(height: 12),
            _buildAuditPanel(),
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
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mentör Çalışmaları Portalı',
            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
          ),
          const SizedBox(height: 6),
          Text(
            'Öğrencilerin akademik hedeflerini belirleyin, haftalık çalışma programlarını takip edin, görüşme notları tutun ve detaylı gelişim raporları hazırlayın.',
            style: GoogleFonts.inter(color: Colors.indigo.shade100, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildModulesGrid(bool isTeacher, String? currentUserId) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 480 ? 2 : 1);
        final double ratio = cols == 4 ? 1.15 : (cols == 2 ? 1.4 : 2.2);

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          childAspectRatio: ratio,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _buildModuleCard(
              title: 'Hedef Belirleme',
              description: 'Puan, Net ve Lise hedefleri tanımlayın.',
              icon: Icons.track_changes_rounded,
              gradient: [Colors.amber.shade700, Colors.amber.shade900],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MentorGoalsScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ).then((_) => _loadAllData());
              },
            ),
            _buildModuleCard(
              title: 'Çalışma Programı',
              description: 'Görevler, onaylar ve % takipleri.',
              icon: Icons.calendar_month_rounded,
              gradient: [Colors.indigo.shade500, Colors.indigo.shade800],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MentorStudyProgramsSubHubScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ).then((_) => _loadAllData());
              },
            ),
            _buildModuleCard(
              title: 'Görüşme Notları',
              description: 'Etiketli haftalık rehberlik logları.',
              icon: Icons.forum_rounded,
              gradient: [Colors.teal.shade500, Colors.teal.shade800],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GuidanceInterviewScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                      schoolTypeName: 'Okul Türü',
                      isTeacher: isTeacher,
                      teacherId: currentUserId,
                    ),
                  ),
                ).then((_) => _loadAllData());
              },
            ),
            _buildModuleCard(
              title: 'Raporlar',
              description: 'Öğrenci gelişim karnesi ve PDF çıktıları.',
              icon: Icons.analytics_rounded,
              gradient: [Colors.cyan.shade600, Colors.cyan.shade900],
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MentorReportsScreen(
                      institutionId: widget.institutionId,
                      schoolTypeId: widget.schoolTypeId,
                    ),
                  ),
                ).then((_) => _loadAllData());
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildModuleCard({
    required String title,
    required String description,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.15),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: gradient.last.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background Watermark Icon
          Positioned(
            right: -24,
            bottom: -24,
            child: Transform.rotate(
              angle: -0.15,
              child: Icon(
                icon,
                size: 130,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          // Content
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.25),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(icon, color: Colors.white, size: 24),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Yönet',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 10,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditPanel() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.indigo,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.indigo,
              indicatorWeight: 3,
              isScrollable: true,
              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(text: 'Program & Geri Bildirim'),
                Tab(text: 'Görev Risk Analizi'),
                Tab(text: 'Hedef Belirleme Takibi'),
                Tab(text: 'Rehberlik Görüşme Logları'),
              ],
            ),
          ),
          SizedBox(
            height: 380,
            child: _isAuditLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const EduKnLoader(size: 50.0),
                        const SizedBox(height: 16),
                        Text(
                          'Denetim ve risk verileri analiz ediliyor...',
                          style: GoogleFonts.inter(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Program & Feedback
                _teacherFeedbackStats.isEmpty
                    ? const Center(child: Text('Denetlenecek program kaydı bulunamadı.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _teacherFeedbackStats.length,
                        itemBuilder: (context, index) {
                          final key = _teacherFeedbackStats.keys.elementAt(index);
                          final stats = _teacherFeedbackStats[key]!;
                          final assigned = stats['assigned']!;
                          final evaluated = stats['evaluated']!;
                          final rate = assigned > 0 ? ((evaluated / assigned) * 100).round() : 0;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: rate > 75 ? Colors.green.shade50 : (rate > 40 ? Colors.orange.shade50 : Colors.red.shade50),
                              child: Text(
                                '%$rate',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: rate > 75 ? Colors.green : (rate > 40 ? Colors.orange : Colors.red),
                                ),
                              ),
                            ),
                            title: Text(key, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text('Hazırlanan Program: $assigned • Haftalık Geri Bildirim: $evaluated'),
                          );
                        },
                      ),

                // Tab 2: Risk Analysis
                _sortedStudentsRisk.isEmpty
                    ? const Center(child: Text('Uyum analizi yapılacak öğrenci verisi bulunamadı.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _sortedStudentsRisk.length,
                        itemBuilder: (context, index) {
                          final data = _sortedStudentsRisk[index];
                          final name = data['name'] as String;
                          final total = data['totalTasks'] as int;
                          final completed = data['completedTasks'] as int;
                          final missed = data['missedTasks'] as int;
                          final incomplete = data['incompleteTasks'] as int;
                          final branch = data['branch'] as String;

                          final totalFailed = missed + incomplete;
                          final failureRate = total > 0 ? ((totalFailed / total) * 100).round() : 0;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: failureRate > 30 ? Colors.red.shade50 : Colors.green.shade50,
                              child: Icon(
                                failureRate > 30 ? Icons.warning_amber_rounded : Icons.thumb_up_alt_rounded,
                                color: failureRate > 30 ? Colors.red : Colors.green,
                              ),
                            ),
                            title: Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text('Sınıf: $branch • Toplam: $total Görev • Yapılan: $completed • Eksik: $totalFailed'),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '%$failureRate',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    color: failureRate > 30 ? Colors.red : Colors.green,
                                    fontSize: 14,
                                  ),
                                ),
                                Text('Aksatma Oranı', style: GoogleFonts.inter(fontSize: 8, color: Colors.grey)),
                              ],
                            ),
                          );
                        },
                      ),

                // Tab 3: Goal Tracking
                _goalStatusList.isEmpty
                    ? const Center(child: Text('Hedef analizi yapılacak öğrenci bulunamadı.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _goalStatusList.length,
                        itemBuilder: (context, index) {
                          final data = _goalStatusList[index];
                          final name = data['name'] as String;
                          final className = data['class'] as String;
                          final bool hasGoals = data['hasGoals'] as bool;
                          final goals = data['goals'] as Map<String, dynamic>?;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: hasGoals ? Colors.green.shade50 : Colors.red.shade50,
                              child: Icon(
                                hasGoals ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
                                color: hasGoals ? Colors.green : Colors.red,
                              ),
                            ),
                            title: Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: hasGoals
                                ? Text(
                                    'Puan: ${goals?['points'] ?? '-'} • Net: ${goals?['nets'] ?? '-'} • Okul: ${goals?['targetSchool'] ?? 'Belirtilmemiş'}',
                                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600),
                                  )
                                : Text(
                                    'Henüz hedef tanımlaması yapılmamış.',
                                    style: GoogleFonts.inter(fontSize: 11, color: Colors.red.shade400, fontWeight: FontWeight.w500),
                                  ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                className,
                                style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        },
                      ),

                // Tab 4: Guidance Interview Logs
                _interviewerStats.isEmpty
                    ? const Center(child: Text('Son 30 günde kaydedilmiş görüşme bulunamadı.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _interviewerStats.length,
                        itemBuilder: (context, index) {
                          final key = _interviewerStats.keys.elementAt(index);
                          final count = _interviewerStats[key]!;

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.teal.shade50,
                              child: Icon(Icons.forum_rounded, color: Colors.teal.shade700, size: 20),
                            ),
                            title: Text(key, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: const Text('Son 30 günde gerçekleştirilen rehberlik görüşmeleri.'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade600,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$count Görüşme',
                                style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
