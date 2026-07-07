import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'mentor_student_report_detail_screen.dart';
import '../../../widgets/edukn_logo.dart';
import '../../../services/user_permission_service.dart';

class MentorReportsScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const MentorReportsScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<MentorReportsScreen> createState() => _MentorReportsScreenState();
}

class _MentorReportsScreenState extends State<MentorReportsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _studentsReportData = [];
  List<Map<String, dynamic>> _filteredReports = [];
  String _searchQuery = '';
  Map<String, dynamic>? _userData;

  int _greenCount = 0;
  int _yellowCount = 0;
  int _redCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAllReportsData();
  }

  Future<void> _loadAllReportsData() async {
    setState(() => _isLoading = true);
    try {
      _userData = await UserPermissionService.loadUserData();
      final role = (_userData?['role'] as String?)?.toLowerCase() ?? '';
      final bool isTeacher = role == 'ogretmen' || role == 'rehber_ogretmen';
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      // 1. Fetch Students
      Query studentsQuery = FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true);

      if (isTeacher && currentUserId != null) {
        studentsQuery = studentsQuery.where('mentorId', isEqualTo: currentUserId);
      }

      final studentSnap = await studentsQuery.get();
      final students = studentSnap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        data['fullName'] = data['fullName'] ?? '${data['name'] ?? ''} ${data['surname'] ?? ''}'.trim();
        return data;
      }).toList();

      if (students.isEmpty) {
        setState(() {
          _studentsReportData = [];
          _filteredReports = [];
          _isLoading = false;
        });
        return;
      }

      // 2. Fetch study programs (last 30 days) to analyze completion rate
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final programsQuery = await FirebaseFirestore.instance
          .collection('institutions')
          .doc(widget.institutionId)
          .collection('study_programs')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
          .get();

      // Group study programs by student
      Map<String, List<Map<String, dynamic>>> studentPrograms = {};
      for (var doc in programsQuery.docs) {
        final data = doc.data();
        final studentId = data['studentId']?.toString();
        if (studentId != null) {
          studentPrograms.putIfAbsent(studentId, () => []);
          studentPrograms[studentId]!.add(doc.data());
        }
      }

      // 3. Fetch interviews (last 14 days) to check active logging
      final fourteenDaysAgo = DateTime.now().subtract(const Duration(days: 14));
      final interviewsQuery = await FirebaseFirestore.instance
          .collection('guidance_interviews')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();

      // Set of student IDs who have interview log in the last 14 days
      Set<String> studentsWithRecentLogs = {};
      for (var doc in interviewsQuery.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final dateStamp = data['date'] as Timestamp?;
        if (dateStamp != null && dateStamp.toDate().isBefore(fourteenDaysAgo)) {
          continue;
        }
        final participants = data['participants'] as List<dynamic>?;
        if (participants != null) {
          for (var p in participants) {
            studentsWithRecentLogs.add(p.toString());
          }
        }
      }

      // 4. Calculate stats for each student
      List<Map<String, dynamic>> processedList = [];
      int gCount = 0;
      int yCount = 0;
      int rCount = 0;

      for (var s in students) {
        final sId = s['id'] as String;
        final progs = studentPrograms[sId] ?? [];
        
        // Calculate task completion rate
        int totalTasks = 0;
        int completedTasks = 0;

        for (var p in progs) {
          if (p['executionStatus'] != null) {
            final statusMap = p['executionStatus'] as Map<String, dynamic>;
            statusMap.forEach((key, val) {
              if (val is List) {
                final list = List<int>.from(val);
                totalTasks += list.length;
                completedTasks += list.where((status) => status == 1).length;
              }
            });
          }
        }

        final double completionRate = totalTasks > 0 ? (completedTasks / totalTasks * 100) : 0.0;
        final bool hasRecentLog = studentsWithRecentLogs.contains(sId);

        // Determine Traffic Light status
        String status = 'yellow';
        if (completionRate >= 80.0) {
          status = 'green';
          gCount++;
        } else if (completionRate < 50.0 || !hasRecentLog) {
          status = 'red';
          rCount++;
        } else {
          status = 'yellow';
          yCount++;
        }

        processedList.add({
          'student': s,
          'completionRate': completionRate,
          'hasRecentLog': hasRecentLog,
          'status': status,
          'totalTasks': totalTasks,
          'completedTasks': completedTasks,
        });
      }

      processedList.sort((a, b) => (a['student']['fullName'] as String).compareTo(b['student']['fullName'] as String));

      setState(() {
        _studentsReportData = processedList;
        _filteredReports = processedList;
        _greenCount = gCount;
        _yellowCount = yCount;
        _redCount = rCount;
        _isLoading = false;
      });

    } catch (e) {
      debugPrint("Error loading reports: $e");
      setState(() => _isLoading = false);
    }
  }

  void _filter(String query) {
    setState(() {
      _searchQuery = query;
      _filteredReports = _studentsReportData.where((r) {
        final name = r['student']['fullName'].toString().toLowerCase();
        return name.contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F4F6),
        body: Center(child: EduKnLoader(size: 80.0)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text(
          'Öğrenci Gelişim Raporları',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Filter & Summary Panel
          _buildSummaryBar(),
          Expanded(
            child: _filteredReports.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        _searchQuery.isEmpty ? 'Aktif mentörlük raporu bulunamadı.' : 'Arama sonucu bulunamadı.',
                        style: GoogleFonts.inter(color: Colors.grey),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);
                      return GridView.builder(
                        padding: const EdgeInsets.all(20),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          childAspectRatio: 1.55,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: _filteredReports.length,
                        itemBuilder: (context, index) {
                          return _buildStudentReportCard(_filteredReports[index]);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Öğrenci Adı Ara...',
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
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSummaryIndicator('Kritik Durum', '$_redCount Öğrenci', Colors.red),
              _buildSummaryIndicator('Takip Gereken', '$_yellowCount Öğrenci', Colors.orange),
              _buildSummaryIndicator('İşler Yolunda', '$_greenCount Öğrenci', Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryIndicator(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 5, backgroundColor: color),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 11, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentReportCard(Map<String, dynamic> item) {
    final s = item['student'] as Map<String, dynamic>;
    final double completionRate = item['completionRate'] as double;
    final bool hasRecentLog = item['hasRecentLog'] as bool;
    final String status = item['status'] as String;

    Color statusColor = Colors.green;
    String statusText = 'Yolunda';
    if (status == 'red') {
      statusColor = Colors.red;
      statusText = !hasRecentLog ? 'Log Eksik' : 'Kritik';
    } else if (status == 'yellow') {
      statusColor = Colors.orange;
      statusText = 'Takip Et';
    }

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MentorStudentReportDetailScreen(
                student: s,
                institutionId: widget.institutionId,
                schoolTypeId: widget.schoolTypeId,
              ),
            ),
          ).then((_) => _loadAllReportsData());
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      s['fullName'],
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo.shade900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(radius: 3, backgroundColor: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: GoogleFonts.inter(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Sınıf: ${s['className'] ?? 'Sınıfsız'}',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Uyum Oranı',
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '%${completionRate.round()}',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: statusColor),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Rehberlik Görüşmesi',
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasRecentLog ? 'Yapıldı (Son 14 Gün)' : 'Log Girilmedi!',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: hasRecentLog ? Colors.teal : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
