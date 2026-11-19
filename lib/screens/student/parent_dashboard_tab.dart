import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../services/term_service.dart';
import '../../services/user_permission_service.dart';
import '../school/school_types/school_type_announcements_screen.dart';
import '../school/school_types/school_type_detail_screen.dart';
import 'parent_accounting_screen.dart';
import 'parent_early_pickup_screen.dart';
import 'student_and_parent_tools_screen.dart';
import 'student_exam_stats_screen.dart';
import 'student_homework_stats_screen.dart';
import 'student_personal_academic_tools_screen.dart';

/// Öğrenci ve Veli Ana Sayfası (Bildirimler & Takvim).
/// Üst AppBar `ParentMainScreen` içerisindeki okul logolu `EduknAppBar` tarafından
/// sağlandığı için burada ikinci bir AppBar oluşturulmaz (çift AppBar sorunu %100 önlenir).
class ParentDashboardTab extends StatefulWidget {
  final String institutionId;
  final String? studentId;
  final Map<String, dynamic>? studentData;
  final bool isParentUser;
  final bool dailyReportEnabled;

  const ParentDashboardTab({
    Key? key,
    required this.institutionId,
    this.studentId,
    this.studentData,
    this.isParentUser = false,
    this.dailyReportEnabled = false,
  }) : super(key: key);

  @override
  State<ParentDashboardTab> createState() => _ParentDashboardTabState();
}

class _ParentDashboardTabState extends State<ParentDashboardTab> {
  final List<StreamSubscription> _subs = [];
  String? _schoolId;
  String? _activeTermId;
  bool _loadingNotifs = true;

  List<QueryDocumentSnapshot> _annDocs = [];
  List<QueryDocumentSnapshot> _hwDocs = [];
  List<QueryDocumentSnapshot> _examDocs = [];
  List<QueryDocumentSnapshot> _personalNotifDocs = [];
  List<Map<String, dynamic>> _notifications = [];

  String get _studentName {
    final full = (widget.studentData?['fullName'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    return '${widget.studentData?['name'] ?? ''} ${widget.studentData?['surname'] ?? ''}'
        .trim();
  }

  String get _studentNo =>
      (widget.studentData?['studentNo'] ??
              widget.studentData?['studentNumber'] ??
              widget.studentData?['no'] ??
              '')
          .toString()
          .trim();

  String get _className =>
      (widget.studentData?['className'] ?? '').toString().trim();

  String get _classId =>
      (widget.studentData?['classId'] ?? '').toString().trim();

  String get _schoolTypeId =>
      (widget.studentData?['schoolTypeId'] ?? '').toString().trim();

  String get _schoolTypeName =>
      (widget.studentData?['schoolTypeName'] ?? '').toString().trim();

  String get _classLevel {
    final raw =
        (widget.studentData?['classLevel'] ??
                widget.studentData?['gradeLevel'] ??
                '')
            .toString()
            .trim();
    if (raw.isNotEmpty) return raw;
    final digits = RegExp(r'\d+').firstMatch(_className)?.group(0) ?? '';
    if (digits.startsWith('10') ||
        digits.startsWith('11') ||
        digits.startsWith('12')) {
      return digits.substring(0, 2);
    }
    return digits.isNotEmpty ? digits.substring(0, 1) : '';
  }

  String get _studentSubtitle {
    final parts = <String>[
      if (widget.isParentUser) 'Veli Paneli',
      if (_studentNo.isNotEmpty) _studentNo,
      if (_studentName.isNotEmpty) _studentName,
      if (_className.isNotEmpty) '($_className)',
    ];
    return parts.join(' • ');
  }

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  @override
  void didUpdateWidget(covariant ParentDashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId ||
        oldWidget.institutionId != widget.institutionId) {
      _cancelStreams();
      _initStreams();
    }
  }

  void _cancelStreams() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  void dispose() {
    _cancelStreams();
    super.dispose();
  }

  Future<void> _initStreams() async {
    setState(() => _loadingNotifs = true);
    final instIds = {
      widget.institutionId,
      widget.institutionId.toUpperCase(),
      widget.institutionId.toLowerCase(),
    }.where((s) => s.isNotEmpty).toList();

    try {
      final res = await Future.wait([
        TermService()
            .getSelectedTermId()
            .then((v) async => v ?? await TermService().getActiveTermId())
            .timeout(const Duration(seconds: 3), onTimeout: () => null),
        instIds.isNotEmpty
            ? FirebaseFirestore.instance
                  .collection('schools')
                  .where('institutionId', whereIn: instIds)
                  .limit(1)
                  .get()
                  .timeout(const Duration(seconds: 4))
                  .then((s) => s.docs.isNotEmpty ? s.docs.first.id : null)
                  .catchError((_) => null)
            : Future.value(null),
      ]);
      _activeTermId = res[0];
      _schoolId = res[1];
    } catch (_) {}

    if (!mounted) return;

    // 1. Okul Duyuruları (schools/{schoolId}/announcements -> collectionGroup index hatası sıfır!)
    if (_schoolId != null && _schoolId!.isNotEmpty) {
      _subs.add(
        FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolId)
            .collection('announcements')
            .snapshots()
            .listen((snap) {
              _annDocs = snap.docs;
              _rebuildNotifications();
            }, onError: (_) {}),
      );
    }

    // 2. Sınıf Ödevleri
    if (_classId.isNotEmpty && instIds.isNotEmpty) {
      _subs.add(
        FirebaseFirestore.instance
            .collection('homeworks')
            .where('institutionId', whereIn: instIds)
            .where('classId', isEqualTo: _classId)
            .snapshots()
            .listen((snap) {
              _hwDocs = snap.docs;
              _rebuildNotifications();
            }, onError: (_) {}),
      );

      // 3. Sınıf Yazılı Sınavları
      _subs.add(
        FirebaseFirestore.instance
            .collection('class_exams')
            .where('institutionId', whereIn: instIds)
            .where('classId', isEqualTo: _classId)
            .snapshots()
            .listen((snap) {
              _examDocs = snap.docs;
              _rebuildNotifications();
            }, onError: (_) {}),
      );
    }

    // 4. Kişisel Bildirimler
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      _subs.add(
        FirebaseFirestore.instance
            .collection('notifications')
            .doc(uid)
            .collection('items')
            .orderBy('createdAt', descending: true)
            .limit(25)
            .snapshots()
            .listen((snap) {
              _personalNotifDocs = snap.docs;
              _rebuildNotifications();
            }, onError: (_) {}),
      );
    }

    if (mounted) {
      _rebuildNotifications();
      setState(() => _loadingNotifs = false);
    }
  }

  DateTime _parseDt(dynamic val) {
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
    return DateTime.now();
  }

  void _rebuildNotifications() {
    if (!mounted) return;
    final items = <Map<String, dynamic>>[];
    final now = DateTime.now();

    // Duyurular
    for (final doc in _annDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final status = (d['status'] ?? 'published').toString().toLowerCase();
      if (status != 'published') continue;
      final stId = (d['schoolTypeId'] ?? '').toString().trim();
      if (_schoolTypeId.isNotEmpty &&
          stId.isNotEmpty &&
          stId != _schoolTypeId) {
        continue;
      }
      final dt = _parseDt(d['publishDate'] ?? d['createdAt']);
      items.add({
        'id': 'ann_${doc.id}',
        'title': (d['title'] ?? 'Duyuru').toString(),
        'body': (d['content'] ?? d['summary'] ?? '').toString(),
        'badge': 'Duyuru',
        'icon': Icons.campaign_rounded,
        'color': const Color(0xFFEA580C),
        'time': dt,
        'type': 'announcement',
      });
    }

    // Aktif & Yaklaşan Ödevler
    for (final doc in _hwDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final docTerm = d['termId']?.toString().trim();
      if (_activeTermId != null &&
          _activeTermId!.isNotEmpty &&
          docTerm != null &&
          docTerm.isNotEmpty &&
          docTerm != _activeTermId) {
        continue;
      }
      final due = _parseDt(d['dueDate'] ?? d['createdAt']);
      if (due.isBefore(now.subtract(const Duration(days: 14)))) continue;
      final lesson = (d['lessonName'] ?? d['branchName'] ?? 'Ders').toString();
      final title = (d['title'] ?? 'Ödev').toString();
      items.add({
        'id': 'hw_${doc.id}',
        'title': '$lesson: $title',
        'body': 'Son Teslim: ${DateFormat('dd.MM.yyyy').format(due)}',
        'badge': 'Ödev',
        'icon': Icons.assignment_rounded,
        'color': const Color(0xFF059669),
        'time': _parseDt(d['createdAt'] ?? d['dueDate']),
        'type': 'homework',
      });
    }

    // Yazılı Sınavlar & Not Açıklamaları
    for (final doc in _examDocs) {
      final d = doc.data() as Map<String, dynamic>;
      final docTerm = d['termId']?.toString().trim();
      if (_activeTermId != null &&
          _activeTermId!.isNotEmpty &&
          docTerm != null &&
          docTerm.isNotEmpty &&
          docTerm != _activeTermId) {
        continue;
      }
      final examDt = _parseDt(d['date'] ?? d['createdAt']);
      final grades = Map<String, dynamic>.from(d['grades'] ?? {});
      final myGrade = widget.studentId != null
          ? grades[widget.studentId]
          : null;
      final lesson = (d['lessonName'] ?? d['lesson'] ?? 'Ders').toString();
      final examName = (d['examName'] ?? 'Yazılı Sınav').toString();
      if (myGrade != null) {
        items.add({
          'id': 'grade_${doc.id}',
          'title': '$lesson Sınav Notu Açıklandı',
          'body': '$examName • Puan: $myGrade',
          'badge': 'Not',
          'icon': Icons.workspace_premium_rounded,
          'color': const Color(0xFF4F46E5),
          'time': examDt,
          'type': 'exam',
        });
      } else if (examDt.isAfter(now.subtract(const Duration(days: 2)))) {
        items.add({
          'id': 'exam_${doc.id}',
          'title': 'Yaklaşan Sınav: $lesson',
          'body':
              '$examName • Tarih: ${DateFormat('dd.MM.yyyy').format(examDt)}',
          'badge': 'Sınav',
          'icon': Icons.quiz_rounded,
          'color': const Color(0xFF7C3AED),
          'time': examDt,
          'type': 'exam',
        });
      }
    }

    // Kişisel Anlık Bildirimler
    for (final doc in _personalNotifDocs) {
      final d = doc.data() as Map<String, dynamic>;
      items.add({
        'id': 'p_${doc.id}',
        'title': (d['title'] ?? 'Bildirim').toString(),
        'body': (d['body'] ?? d['message'] ?? '').toString(),
        'badge': 'Bildirim',
        'icon': Icons.notifications_active_rounded,
        'color': const Color(0xFF0284C7),
        'time': _parseDt(d['createdAt']),
        'type': 'personal',
      });
    }

    items.sort(
      (a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime),
    );

    setState(() {
      _notifications = items.take(35).toList();
    });
  }

  Widget _buildQuickActionStrip() {
    final instUpper = widget.institutionId.toUpperCase();
    final stId = widget.studentId ?? '';
    final stData = widget.studentData ?? <String, dynamic>{};

    final quickActions =
        <({String label, IconData icon, Color color, VoidCallback onTap})>[
          if (widget.isParentUser && stId.isNotEmpty)
            (
              label: 'Erken Alma Talebi',
              icon: Icons.directions_car_filled_rounded,
              color: const Color(0xFF0D9488),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ParentEarlyPickupScreen(
                    institutionId: instUpper,
                    studentId: stId,
                    initialStudentData: stData,
                  ),
                ),
              ),
            ),
          (
            label: 'Yemek Listesi',
            icon: Icons.restaurant_menu_rounded,
            color: const Color(0xFFEA580C),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentMealMenuScreen(
                  institutionId: instUpper,
                  schoolTypeId: _schoolTypeId,
                  studentSubtitle: _studentSubtitle,
                ),
              ),
            ),
          ),
          if (!widget.isParentUser)
            (
              label: 'Online İşlemler',
              icon: Icons.language_rounded,
              color: const Color(0xFF00897B),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentOnlineServicesScreen(
                    institutionId: instUpper,
                    studentId: stId,
                    studentData: stData,
                    studentSubtitle: _studentSubtitle,
                  ),
                ),
              ),
            ),
          if (stId.isNotEmpty)
            (
              label: 'Hedef & Net Koçum',
              icon: Icons.rocket_launch_rounded,
              color: const Color(0xFF4F46E5),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentPersonalAcademicToolsScreen(
                    institutionId: instUpper,
                    studentId: stId,
                    studentData: stData,
                    isParentView: widget.isParentUser,
                  ),
                ),
              ),
            ),
          (
            label: 'Tüm Araçlar',
            icon: Icons.handyman_rounded,
            color: const Color(0xFF7C3AED),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentAndParentToolsScreen(
                  institutionId: instUpper,
                  studentId: stId,
                  studentData: stData,
                  isParentUser: widget.isParentUser,
                  dailyReportEnabled: widget.dailyReportEnabled,
                ),
              ),
            ),
          ),
          if (widget.isParentUser && stId.isNotEmpty)
            (
              label: 'Ödeme Planı',
              icon: Icons.account_balance_wallet_rounded,
              color: const Color(0xFF2563EB),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ParentAccountingScreen(
                    institutionId: instUpper,
                    studentId: stId,
                    studentName: _studentName,
                  ),
                ),
              ),
            ),
        ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: quickActions.map((a) {
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: a.onTap,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: a.color.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: a.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(a.icon, size: 16, color: a.color),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        a.label,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNotificationColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildQuickActionStrip(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Text(
                'AKIŞ VE BİLDİRİMLER',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: const Color(0xFF64748B),
                ),
              ),
              const Spacer(),
              if (_notifications.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_notifications.length} Kayıt',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF4338CA),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loadingNotifs
              ? const Center(child: CircularProgressIndicator())
              : _notifications.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_none_rounded,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Yeni bildirim bulunmuyor',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final n = _notifications[index];
                    final color = n['color'] as Color;
                    final dt = n['time'] as DateTime;
                    final iconData = n['type'] == 'exam'
                        ? Icons.workspace_premium_rounded
                        : (n['icon'] as IconData);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ListTile(
                        onTap: () => _onNotificationTap(n),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(iconData, color: color, size: 20),
                        ),
                        title: Text(
                          (n['title'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((n['body'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  n['body'].toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('dd.MM.yyyy HH:mm').format(dt),
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _onNotificationTap(Map<String, dynamic> n) {
    final type = n['type']?.toString() ?? '';
    final instUpper = widget.institutionId.toUpperCase();
    if (type == 'announcement') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SchoolTypeAnnouncementsScreen(
            schoolTypeId: _schoolTypeId,
            schoolTypeName: _schoolTypeName.isEmpty
                ? 'Duyurular'
                : _schoolTypeName,
            institutionId: instUpper,
          ),
        ),
      );
    } else if (type == 'homework' && widget.studentId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudentHomeworkStatsScreen(
            institutionId: instUpper,
            studentId: widget.studentId!,
            classId: _classId,
            studentName: _studentName,
          ),
        ),
      );
    } else if (type == 'exam' && widget.studentId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudentExamStatsScreen(
            institutionId: instUpper,
            studentId: widget.studentId!,
            classId: _classId,
            classLevel: _classLevel,
            studentName: _studentName,
            schoolNumber: _studentNo,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseUser =
        UserPermissionService.cachedUserData ?? <String, dynamic>{};
    final enrichedCalendarUserData = <String, dynamic>{
      ...baseUser,
      'role': widget.isParentUser ? 'parent' : 'student',
      'selectedStudentId': widget.studentId ?? '',
      'selectedStudentClassId': _classId,
      'selectedStudentClassLevel': _classLevel,
    };

    final calendarWidget = SharedCalendarSection(
      key: ValueKey('cal_${widget.studentId}_$_classId'),
      schoolTypeId: _schoolTypeId,
      institutionId: widget.institutionId,
      userData: enrichedCalendarUserData,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 900;
        if (isWideScreen) {
          return Container(
            color: const Color(0xFFF8FAFC),
            child: Row(
              children: [
                Expanded(flex: 2, child: _buildNotificationColumn()),
                Expanded(flex: 3, child: calendarWidget),
              ],
            ),
          );
        }

        return DefaultTabController(
          length: 2,
          child: Container(
            color: const Color(0xFFF8FAFC),
            child: Column(
              children: [
                Container(
                  color: Colors.white,
                  child: const TabBar(
                    labelColor: Color(0xFF4F46E5),
                    unselectedLabelColor: Color(0xFF64748B),
                    indicatorColor: Color(0xFF4F46E5),
                    indicatorSize: TabBarIndicatorSize.label,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_none_rounded, size: 19),
                            SizedBox(width: 6),
                            Text('Bildirimler & Hızlı Menü'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 17),
                            SizedBox(width: 6),
                            Text('Takvim'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildNotificationColumn(),
                      SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 90),
                        child: calendarWidget,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
