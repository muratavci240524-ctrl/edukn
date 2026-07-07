import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/user_permission_service.dart';
import '../../services/announcement_service.dart';
import '../announcements/announcement_detail_screen.dart';
import 'teacher_social_media_screen.dart';
import '../../models/school/homework_model.dart';
import '../school/homework/homework_detail_screen.dart';
import '../school/attendance_operations_screen.dart';
import '../school/school_types/school_type_detail_screen.dart';

class TeacherDashboardTab extends StatefulWidget {
  final String institutionId;

  const TeacherDashboardTab({
    Key? key,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<TeacherDashboardTab> createState() => _TeacherDashboardTabState();
}

class _TeacherDashboardTabState extends State<TeacherDashboardTab> {
  late Widget _notificationSection;
  late Widget _calendarSection;

  @override
  void initState() {
    super.initState();
    _notificationSection = _NotificationSection(
      institutionId: widget.institutionId,
    );
    _calendarSection = _CalendarSection(
      institutionId: widget.institutionId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isWideScreen = constraints.maxWidth > 900;

        if (isWideScreen) {
          return Scaffold(
            backgroundColor: Colors.grey.shade50,
            body: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _notificationSection,
                ),
                Expanded(
                  flex: 3,
                  child: _calendarSection,
                ),
              ],
            ),
          );
        } else {
          return DefaultTabController(
            length: 2,
            child: Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                title: Text(
                  'Dashboard',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                bottom: TabBar(
                  labelColor: Colors.blue.shade700,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.blue.shade700,
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Bildirimler'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Takvim'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              body: TabBarView(
                children: [
                  _notificationSection,
                  _calendarSection,
                ],
              ),
            ),
          );
        }
      },
    );
  }
}

class _NotificationSection extends StatefulWidget {
  final String institutionId;
 
  const _NotificationSection({required this.institutionId});
 
  @override
  State<_NotificationSection> createState() => _NotificationSectionState();
}
 
class _NotificationSectionState extends State<_NotificationSection> {
  Map<String, dynamic>? _userData;
  String? _schoolId;
  String? _schoolTypeId;
  String? _schoolTypeName;
  final _streams = <String, StreamSubscription>{};
  final _snaps = <String, QuerySnapshot>{};
  bool _isLoading = true;
  List<Map<String, dynamic>> _allNotifications = [];
  Timer? _timer;
 
  Set<String> _dismissedIds = {};

  @override
  void initState() {
    super.initState();
    _loadDismissedIds().then((_) {
      _loadInitialData();
    });
  }

  Future<void> _loadDismissedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('dismissed_notification_ids') ?? [];
      if (mounted) {
        setState(() {
          _dismissedIds = list.toSet();
        });
      }
    } catch (e) {
      debugPrint('Error loading dismissed ids: $e');
    }
  }

  Future<void> _dismissNotification(String notifId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _dismissedIds.add(notifId);
      });
      await prefs.setStringList('dismissed_notification_ids', _dismissedIds.toList());
      _updateNotifications();
    } catch (e) {
      debugPrint('Error dismissing notification: $e');
    }
  }
 
  @override
  void dispose() {
    _timer?.cancel();
    for (var s in _streams.values) {
      s.cancel();
    }
    super.dispose();
  }

  DateTime? _parseDateTime(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) {
      final clean = val.trim();
      final isoParsed = DateTime.tryParse(clean);
      if (isoParsed != null) return isoParsed;

      try {
        final regex = RegExp(r'(\d{2})\.(\d{2})\.(\d{4})(?:\s+(\d{2}):(\d{2}))?');
        final match = regex.firstMatch(clean);
        if (match != null) {
          final day = int.parse(match.group(1)!);
          final month = int.parse(match.group(2)!);
          final year = int.parse(match.group(3)!);
          final hour = match.group(4) != null ? int.parse(match.group(4)!) : 0;
          final minute = match.group(5) != null ? int.parse(match.group(5)!) : 0;
          return DateTime(year, month, day, hour, minute);
        }
      } catch (_) {}
    }
    return null;
  }
 
  Future<void> _loadInitialData() async {
    try {
      _userData = await UserPermissionService.loadUserData().timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      _schoolId = await AnnouncementService().getSchoolId().timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
 
      if (_userData != null) {
        _schoolTypeId = _userData!['schoolTypeId'];
        _schoolTypeName = _userData!['schoolTypeName'];
      }

      final instId = widget.institutionId.toUpperCase();
      if (_schoolTypeId == null) {
        final schoolTypesSnap = await FirebaseFirestore.instance
            .collection('schoolTypes')
            .where('institutionId', isEqualTo: instId)
            .limit(1)
            .get();
        if (schoolTypesSnap.docs.isNotEmpty) {
          _schoolTypeId = schoolTypesSnap.docs.first.id;
          _schoolTypeName = schoolTypesSnap.docs.first.data()['name'] ?? 'Okul';
        }
      }

      if (mounted) {
        _startListening();
        _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
          if (mounted) {
            _updateNotifications();
          }
        });
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }
 
  void _startListening() {
    if (_schoolId == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
 
    final currentUserId = user.uid;
    final List<String> instIds = [widget.institutionId.toUpperCase(), widget.institutionId.toLowerCase()];
 
    _listenTo('announcements', FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolId)
        .collection('announcements')
        .where('status', isEqualTo: 'published')
        .snapshots());
 
    _listenTo('social', FirebaseFirestore.instance
        .collection('social_media_posts')
        .where('institutionId', whereIn: instIds)
        .snapshots());
 
    _listenTo('assignments', FirebaseFirestore.instance
        .collection('lessonAssignments')
        .where('institutionId', whereIn: instIds)
        .where('teacherIds', arrayContains: currentUserId)
        .where('isActive', isEqualTo: true)
        .snapshots());
 
    _listenTo('duty', FirebaseFirestore.instance
        .collection('dutyScheduleItems')
        .where('institutionId', whereIn: instIds)
        .where('teacherId', isEqualTo: currentUserId)
        .snapshots());
 
    _listenTo('schedules', FirebaseFirestore.instance
        .collection('classSchedules')
        .where('institutionId', whereIn: instIds)
        .where('teacherIds', arrayContains: currentUserId)
        .where('isActive', isEqualTo: true)
        .snapshots());
 
    final todayDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _listenTo('attendance', FirebaseFirestore.instance
        .collection('lessonAttendance')
        .where('institutionId', whereIn: instIds)
        .where('date', isEqualTo: todayDateStr)
        .snapshots());
 
    _listenTo('homeworks', FirebaseFirestore.instance
        .collection('homeworks')
        .where('institutionId', whereIn: instIds)
        .where('teacherId', isEqualTo: currentUserId)
        .snapshots());

    _listenTo('etuts', FirebaseFirestore.instance
        .collection('etut_requests')
        .where('institutionId', whereIn: instIds)
        .where('teacherId', isEqualTo: currentUserId)
        .snapshots());
  }
 
  void _listenTo(String type, Stream<QuerySnapshot> stream) {
    try {
      final sub = stream.listen((snap) {
        if (mounted) {
          _snaps[type] = snap;
          _updateNotifications();
        }
      }, onError: (e) {
        debugPrint('--- Stream error ($type) ---');
        debugPrint(e.toString());
        if (e.toString().contains('index')) {
          print('💡 İpucu: $type için Firestore indeksi eksik olabilir.');
        }
      });
      _streams[type] = sub;
    } catch (e) {
      debugPrint('Error setting up listener for $type: $e');
    }
  }
 
  void _updateNotifications() {
    if (!mounted) return;
 
    final annSnap = _snaps['announcements'];
    final socSnap = _snaps['social'];
    final assignSnap = _snaps['assignments'];
    final dutySnap = _snaps['duty'];
    final scheduleSnap = _snaps['schedules'];
    final attSnap = _snaps['attendance'];
    final hwSnap = _snaps['homeworks'];
    final etutSnap = _snaps['etuts'];
 
    final List<Map<String, dynamic>> result = [];
    final user = FirebaseAuth.instance.currentUser;
    final currentUserId = user?.uid;
    final currentUserEmail = user?.email;
    final schoolTypes = _userData?['schoolTypes'] as List<dynamic>? ?? [];
    final userSchoolTypeSet = schoolTypes.map((e) => e.toString()).toSet();
    
    final now = DateTime.now();
    final todayAt08 = DateTime(now.year, now.month, now.day, 8, 0);
    final currentDayName = _dayNameTr(now);
 
    final assignedClassIds = assignSnap?.docs
            .map((doc) => doc.data() as Map<String, dynamic>)
            .map((data) => data['classId']?.toString())
            .where((id) => id != null)
            .cast<String>()
            .toSet() ?? {};
 
    // 1. DUYURULAR
    if (annSnap != null) {
      for (var doc in annSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final readBy = List<dynamic>.from(data['readBy'] ?? []);
        if (currentUserEmail != null && readBy.contains(currentUserEmail)) continue;
 
        final schoolTypeId = data['schoolTypeId']?.toString();
        final recipients = List<String>.from(data['recipients'] ?? []);
        final publishDate = _parseDateTime(data['publishDate']);
 
        if (publishDate != null && publishDate.isAfter(now)) continue;
 
        bool isRecipient = (recipients.contains('ALL') || recipients.contains('TEACHER') || recipients.contains('unit:ogretmen'));
        if (!isRecipient && currentUserId != null) {
          if (recipients.contains('user:$currentUserId') || (currentUserEmail != null && recipients.contains(currentUserEmail))) {
            isRecipient = true;
          } else {
            for (var cid in assignedClassIds) {
              if (recipients.contains('class:$cid') || recipients.contains('branch:$cid:Öğretmenler')) {
                isRecipient = true;
                break;
              }
            }
          }
        }
 
        if (isRecipient && schoolTypeId != null && !userSchoolTypeSet.contains(schoolTypeId)) {
          if (!recipients.contains('ALL') && !recipients.contains('TEACHER')) isRecipient = false;
        }
 
        if (isRecipient) {
          result.add({
            'id': doc.id,
            'title': data['title'] ?? 'Duyuru',
            'subtitle': data['content'] ?? '',
            'time': publishDate ?? now,
            'type': 'announcement',
            'data': data,
          });
        }
      }
    }
 
    // 2. NÖBET (Anlık ve Günlük)
    if (dutySnap != null) {
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final weekStart = DateTime(monday.year, monday.month, monday.day);
      for (var doc in dutySnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final dDayOfWeek = data['dayOfWeek'] as int?;
        final dWeekStart = _parseDateTime(data['weekStart']);
        final createdAt = _parseDateTime(data['createdAt']);
        final location = data['locationName'] ?? data['dutyLocation'] ?? 'Nöbet Yeri';

        // A. Anlık Bildirim (Yazıldığı an - son 3 günde oluşturulmuşsa)
        if (createdAt != null && now.difference(createdAt).inDays < 3) {
          result.add({
            'id': 'duty_scheduled_${doc.id}',
            'title': 'Yeni Nöbet Yazıldı!',
            'subtitle': '${_weekdayNameTr(dDayOfWeek)} günü nöbetiniz bulunmaktadır. Yer: $location',
            'time': createdAt,
            'type': 'duty_scheduled',
            'data': data,
          });
        }

        // B. Günlük Hatırlatıcı (Nöbet Günü - Sabah 08:00'de)
        if (now.isAfter(todayAt08) && dDayOfWeek == now.weekday && dWeekStart != null) {
          if (dWeekStart.year == weekStart.year && dWeekStart.month == weekStart.month && dWeekStart.day == weekStart.day) {
            result.add({
              'id': 'duty_today_${doc.id}',
              'title': 'Bugün Nöbetçisiniz!',
              'subtitle': 'Bugün nöbet yeriniz: $location. Lütfen kontrol edin.',
              'time': todayAt08,
              'type': 'duty_today',
              'data': data,
            });
          }
        }
      }
    }

    // 3. ETÜT (Anlık ve Günlük)
    if (etutSnap != null) {
      for (var doc in etutSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final attendanceTaken = data['attendanceTaken'] ?? false;
        if (attendanceTaken) continue;
        final etutDate = _parseDateTime(data['startTime'] ?? data['date']);
        final createdAt = _parseDateTime(data['createdAt']);
        final lessonName = data['subject'] ?? data['lessonName'] ?? 'Etüt';

        // A. Anlık Bildirim (Yazıldığı an - son 3 günde oluşturulmuşsa)
        if (createdAt != null && now.difference(createdAt).inDays < 3) {
          final dateStr = etutDate != null ? DateFormat('dd.MM.yyyy HH:mm').format(etutDate) : '';
          result.add({
            'id': 'etut_scheduled_${doc.id}',
            'title': 'Yeni Etüt Yazıldı!',
            'subtitle': '$dateStr saatinde etütünüz bulunmaktadır: $lessonName',
            'time': createdAt,
            'type': 'etut_scheduled',
            'data': data,
          });
        }

        // B. Günlük Hatırlatıcı (Etüt Günü - Sabah 08:00'de)
        if (etutDate != null && 
            etutDate.year == now.year && etutDate.month == now.month && etutDate.day == now.day &&
            now.isAfter(todayAt08)) {
          final timeStr = DateFormat('HH:mm').format(etutDate);
          result.add({
            'id': 'etut_today_${doc.id}',
            'title': 'Bugün Etütünüz Var!',
            'subtitle': 'Saat $timeStr\'da $lessonName etütünüz bulunmaktadır.',
            'time': todayAt08,
            'type': 'etut_today',
            'data': data,
          });
        }
      }
    }
 
    // 4. YOKLAMA UYARISI (Dersler & Etütler)
    // A. Ders Yoklama Uyarısı (Başlangıçtan 5 dakika geçince)
    if (scheduleSnap != null && attSnap != null) {
      try {
        final takenKeys = <String>{};
        for (var doc in attSnap.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final cId = d['classId']?.toString() ?? '';
          final lH = d['lessonHour']?.toString() ?? '';
          if (cId.isNotEmpty && lH.isNotEmpty) {
            takenKeys.add('${cId}_$lH');
          }
        }
 
        for (var doc in scheduleSnap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final sDay = data['day']?.toString() ?? '';
          if (_isSameDay(sDay, currentDayName)) {
            final classId = data['classId']?.toString() ?? '';
            final className = data['className']?.toString() ?? 'Sınıf';
            final hourIdx = data['hourIndex'] as int? ?? 0;
            final lessonHour = hourIdx + 1;
            final subject = data['subjectName'] ?? data['lessonName'] ?? 'Ders';
            
            final lessonStart = DateTime(now.year, now.month, now.day, 9, 0).add(Duration(minutes: hourIdx * 45));
            final warningTriggerTime = lessonStart.add(const Duration(minutes: 5));

            if (now.isAfter(warningTriggerTime)) {
              final key = '${classId}_$lessonHour';
              if (!takenKeys.contains(key)) {
                result.add({
                  'id': 'att_${doc.id}',
                  'title': 'Yoklama Eksik: $className',
                  'subtitle': '$lessonHour. ders ($subject) yoklaması henüz alınmadı (5 dk geçti).',
                  'time': warningTriggerTime,
                  'type': 'attendance_warning',
                  'data': data,
                });
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Attendance warning processing error: $e');
      }
    }

    // B. Etüt Yoklama Uyarısı (Başlangıçtan 5 dakika geçince)
    if (etutSnap != null) {
      for (var doc in etutSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final etutDate = _parseDateTime(data['startTime'] ?? data['date']);
        if (etutDate != null && 
            etutDate.year == now.year && etutDate.month == now.month && etutDate.day == now.day) {
          final warningTriggerTime = etutDate.add(const Duration(minutes: 5));
          if (now.isAfter(warningTriggerTime)) {
            final attendanceTaken = data['attendanceTaken'] ?? false;
            if (!attendanceTaken) {
              final timeStr = DateFormat('HH:mm').format(etutDate);
              final lessonName = data['subject'] ?? data['lessonName'] ?? 'Etüt';
              result.add({
                'id': 'etut_att_${doc.id}',
                'title': 'Etüt Yoklaması Eksik!',
                'subtitle': 'Saat $timeStr\'daki $lessonName etüt yoklaması alınmadı (5 dk geçti).',
                'time': warningTriggerTime,
                'type': 'etut_attendance_warning',
                'data': data,
              });
            }
          }
        }
      }
    }
 
    // 5. SOSYAL
    if (socSnap != null) {
      final threeDaysAgo = now.subtract(const Duration(days: 3));
      for (var doc in socSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final readBy = List<dynamic>.from(data['readBy'] ?? []);
        final createdAt = _parseDateTime(data['createdAt']);
        if (currentUserEmail != null && readBy.contains(currentUserEmail)) continue;
        if (createdAt != null && createdAt.isBefore(threeDaysAgo)) continue;
 
        final recipients = List<String>.from(data['recipients'] ?? []);
        bool isRecipient = (recipients.isEmpty || recipients.contains('ALL') || recipients.contains('TEACHER'));
        if (!isRecipient && currentUserId != null) {
          if (recipients.contains('user:$currentUserId')) isRecipient = true;
          else {
            for (var cid in assignedClassIds) {
              if (recipients.contains('class:$cid')) { isRecipient = true; break; }
            }
          }
        }
 
        if (isRecipient) {
          result.add({
            'id': doc.id,
            'title': 'Yeni Sosyal Paylaşım',
            'subtitle': data['caption'] ?? 'Bir paylaşım yapıldı.',
            'time': createdAt ?? now,
            'type': 'social',
            'data': {...data, 'id': doc.id},
          });
        }
      }
    }
 
    // 6. ÖDEV KONTROLÜ (Sabah 08:00'de)
    if (hwSnap != null) {
      for (var doc in hwSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final dueDate = _parseDateTime(data['dueDate']);
        if (dueDate != null) {
          final isToday = dueDate.year == now.year && dueDate.month == now.month && dueDate.day == now.day;
          
          if (isToday && now.isAfter(todayAt08)) {
            final statuses = Map<String, dynamic>.from(data['studentStatuses'] ?? {});
            final targetIds = List<String>.from(data['targetStudentIds'] ?? []);
            
            // Eğer hiç durum girilmemişse veya bekleyen (0) varsa
            bool needsCheck = targetIds.isNotEmpty && (statuses.isEmpty || statuses.values.any((s) => s == 0));
            
            if (needsCheck) {
              result.add({
                'id': 'hw_today_${doc.id}',
                'title': 'Bugün Ödev Kontrol Günü!',
                'subtitle': '"${data['title']}" ödevinin son kontrol günü bugün. Kontrol etmeyi unutmayın.',
                'time': todayAt08,
                'type': 'homework_warning',
                'data': {...data, 'id': doc.id},
              });
            }
          }
        }
      }
    }
 
    final filteredResult = result.where((item) => !_dismissedIds.contains(item['id'])).toList();
    filteredResult.sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));
    if (mounted) {
      setState(() => _allNotifications = filteredResult);
    }
  }

  String _weekdayNameTr(int? day) {
    switch (day) {
      case 1: return 'Pazartesi'; case 2: return 'Salı'; case 3: return 'Çarşamba';
      case 4: return 'Perşembe'; case 5: return 'Cuma'; case 6: return 'Cumartesi';
      case 7: return 'Pazar'; default: return '';
    }
  }

  String _dayNameTr(DateTime date) {
    switch (date.weekday) {
      case 1: return 'Pazartesi'; case 2: return 'Salı'; case 3: return 'Çarşamba';
      case 4: return 'Perşembe'; case 5: return 'Cuma'; case 6: return 'Cumartesi';
      case 7: return 'Pazar'; default: return '';
    }
  }
 
  bool _isSameDay(String dbDay, String selectedDay) {
    final d1 = dbDay.toLowerCase().replaceAll('ı', 'i').replaceAll('İ', 'i').trim();
    final d2 = selectedDay.toLowerCase().replaceAll('ı', 'i').replaceAll('İ', 'i').trim();
    return d1 == d2;
  }
 
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
 
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Text(
              'BİLDİRİMLER',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 1.2),
            ),
          ),
          Expanded(
            child: _allNotifications.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_off_outlined, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('Yeni bildirim bulunmuyor', style: TextStyle(color: Colors.grey.shade400)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _allNotifications.length,
                    itemBuilder: (context, index) {
                      final item = _allNotifications[index];
                      return _buildNotificationCard(
                        id: item['id'],
                        title: item['title'],
                        subtitle: item['subtitle'],
                        time: item['time'],
                        type: item['type'],
                        originalData: item['data'],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
 
  Widget _buildNotificationCard({
    required String id, required String title, required String subtitle,
    required DateTime time, required String type, required Map<String, dynamic> originalData,
  }) {
    IconData icon; Color color;
    if (type == 'announcement') { icon = Icons.campaign_rounded; color = Colors.blue.shade600; }
    else if (type == 'social') { icon = Icons.share_rounded; color = Colors.purple.shade600; }
    else if (type == 'duty_scheduled' || type == 'duty_today') { icon = Icons.security_rounded; color = Colors.orange.shade700; }
    else if (type == 'etut_scheduled' || type == 'etut_today') { icon = Icons.school_rounded; color = Colors.teal.shade600; }
    else if (type == 'attendance_warning' || type == 'etut_attendance_warning') { icon = Icons.event_busy_rounded; color = Colors.red.shade600; }
    else if (type == 'homework_warning') { icon = Icons.assignment_turned_in_rounded; color = Colors.indigo.shade600; }
    else { icon = Icons.notifications_none_rounded; color = Colors.grey.shade600; }
 
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    final timeStr = DateFormat('HH:mm').format(time);
 
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), spreadRadius: 2, blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              if (userEmail != null) {
                if (type == 'announcement') {
                  await FirebaseFirestore.instance.collection('schools').doc(_schoolId).collection('announcements').doc(id).update({
                    'readBy': FieldValue.arrayUnion([userEmail])
                  });
                  if (mounted) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => AnnouncementDetailScreen(announcementId: id, schoolId: _schoolId!)));
                  }
                } else if (type == 'social') {
                  await FirebaseFirestore.instance.collection('social_media_posts').doc(id).update({
                    'readBy': FieldValue.arrayUnion([userEmail])
                  });
                  if (mounted) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherSocialMediaScreen(institutionId: widget.institutionId)));
                  }
                } else if (type == 'homework_warning') {
                  if (mounted) {
                    Navigator.push(
                      context, 
                      MaterialPageRoute(
                        builder: (_) => HomeworkDetailScreen(
                          homework: Homework.fromMap(originalData),
                        )
                      )
                    );
                  }
                } else if (type == 'attendance_warning') {
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AttendanceOperationsScreen(
                          institutionId: widget.institutionId,
                          schoolTypeId: _schoolTypeId ?? '',
                          schoolTypeName: _schoolTypeName ?? 'Okul',
                        )
                      )
                    );
                  }
                } else if (type == 'etut_scheduled' || type == 'etut_today' || type == 'etut_attendance_warning') {
                  if (mounted) {
                    // Extract real etut ID by removing prefixed string
                    String realEtutId = id;
                    if (id.startsWith('etut_scheduled_')) {
                      realEtutId = id.replaceFirst('etut_scheduled_', '');
                    } else if (id.startsWith('etut_today_')) {
                      realEtutId = id.replaceFirst('etut_today_', '');
                    } else if (id.startsWith('etut_att_')) {
                      realEtutId = id.replaceFirst('etut_att_', '');
                    }

                    final mappedEtutData = Map<String, dynamic>.from(originalData);
                    mappedEtutData['id'] = realEtutId;
                    _showEtutAttendanceSheet(mappedEtutData);
                  }
                } else if (type == 'duty_scheduled' || type == 'duty_today') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Nöbet bilgilerinizi takvim sekmesinden de takip edebilirsiniz.'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(width: 6, color: color),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              Text(timeStr, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            ]),
                            const SizedBox(height: 4),
                            Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                          ])),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                            onPressed: () {
                              _dismissNotification(id);
                            },
                          ),
                        ],
                      ),
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

  Future<void> _showEtutAttendanceSheet(Map<String, dynamic> etutData) async {
    final etutId = etutData['id'] ?? '';
    if (etutId.isEmpty) return;

    // Show a loading indicator dialog or sheet while fetching student names
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 200,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );

    final navigator = Navigator.of(context);

    // Resolve topic dynamically if empty or 'Belirtilmemiş'
    final String topic = (etutData['topic'] ?? '').toString().trim();
    String resolvedTopic = topic;
    if (topic.isEmpty ||
        topic.toLowerCase() == 'belirtilmemis' ||
        topic.toLowerCase() == 'belirtilmemiş' ||
        topic.toLowerCase() == 'konu belirtilmemis' ||
        topic.toLowerCase() == 'konu belirtilmemiş' ||
        topic == '-' ||
        topic == 'null') {
      final campGroupId = etutData['campGroupId']?.toString();
      final agmGroupId = etutData['agmGroupId']?.toString();
      
      if (campGroupId != null && campGroupId.isNotEmpty) {
        try {
          final groupDoc = await FirebaseFirestore.instance
              .collection('camp_groups')
              .doc(campGroupId)
              .get();
          if (groupDoc.exists) {
            final list = List<dynamic>.from(groupDoc.data()?['kazanimlar'] ?? []);
            if (list.isNotEmpty) {
              resolvedTopic = list.join(', ');
            }
          }
        } catch (e) {
          debugPrint('Error fetching camp group kazanimlar: $e');
        }
      } else if (agmGroupId != null && agmGroupId.isNotEmpty) {
        try {
          final groupDoc = await FirebaseFirestore.instance
              .collection('agm_groups')
              .doc(agmGroupId)
              .get();
          if (groupDoc.exists) {
            final list = List<dynamic>.from(groupDoc.data()?['kazanimlar'] ?? []);
            if (list.isNotEmpty) {
              resolvedTopic = list.join(', ');
            }
          }
        } catch (e) {
          debugPrint('Error fetching agm group kazanimlar: $e');
        }
      }
    }

    List<String> studentIds = [];
    if (etutData['studentIds'] is List) {
      studentIds = List<String>.from(etutData['studentIds']);
    }

    final Map<String, String> studentNameMap = {};
    if (studentIds.isNotEmpty) {
      try {
        final instId = widget.institutionId.toUpperCase();
        var studentSnap = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: instId)
            .where(FieldPath.documentId, whereIn: studentIds)
            .get();

        if (studentSnap.docs.isEmpty) {
          studentSnap = await FirebaseFirestore.instance
              .collection('students')
              .where('institutionId', isEqualTo: instId.toLowerCase())
              .where(FieldPath.documentId, whereIn: studentIds)
              .get();
        }

        for (var doc in studentSnap.docs) {
          final data = doc.data();
          studentNameMap[doc.id] = (data['fullName'] ?? data['name'] ?? '').toString();
        }
      } catch (e) {
        debugPrint('Error loading students for sheet: $e');
      }
    }

    // Dismiss the loading sheet
    navigator.pop();

    // Map student names
    final List<String> studentNames = [];
    for (var id in studentIds) {
      studentNames.add(studentNameMap[id] ?? 'Öğrenci ($id)');
    }

    final Map<String, dynamic> attendanceData = etutData['attendance'] ?? {};
    final Map<String, bool> localAttendance = {};
    for (var id in studentIds) {
      localAttendance[id] = attendanceData[id] ?? true;
    }
    final notesController = TextEditingController(
      text: etutData['teacherNotes'] ?? '',
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.92,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 16, 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.assignment_rounded, color: Colors.indigo.shade700),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Etüt Yoklama Al',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                            Text(
                              'Yoklama durumunu ve notlarınızı güncelleyin',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.grey),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          elevation: 0,
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                _buildInfoRowForDialog(Icons.topic, 'Konu', resolvedTopic.isNotEmpty ? resolvedTopic : 'Belirtilmemiş'),
                                if ((etutData['action'] ?? '').toString().isNotEmpty) ...[
                                  const Divider(height: 24),
                                  _buildInfoRowForDialog(Icons.category, 'Kategori', etutData['action'], isOrange: true),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Text(
                                'YOKLAMA LİSTESİ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.indigo.shade800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${studentIds.length} Öğrenci',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (studentIds.isEmpty)
                          _buildEmptyStateForDialog('Öğrenci bulunamadı')
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.symmetric(
                                horizontal: BorderSide(color: Colors.grey.shade200, width: 0.5),
                              ),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: studentIds.length,
                              separatorBuilder: (context, index) =>
                                  Divider(height: 1, color: Colors.grey.shade100, indent: 24),
                              itemBuilder: (context, index) {
                                final sId = studentIds[index];
                                final sName = studentNames[index];
                                final isPresent = localAttendance[sId] ?? true;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                                  title: Text(sName,
                                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildPresenceButtonForDialog(
                                        icon: Icons.check_circle_rounded,
                                        label: 'VAR',
                                        isSelected: isPresent,
                                        activeColor: Colors.green,
                                        onTap: () => setDialogState(() => localAttendance[sId] = true),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildPresenceButtonForDialog(
                                        icon: Icons.cancel_rounded,
                                        label: 'YOK',
                                        isSelected: !isPresent,
                                        activeColor: Colors.red,
                                        onTap: () => setDialogState(() => localAttendance[sId] = false),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 32),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ÖĞRETMEN NOTLARI',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.indigo.shade800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: notesController,
                                maxLines: 4,
                                style: const TextStyle(fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: 'Etüt ile ilgili gözlemlerinizi buraya yazabilirsiniz...',
                                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: Colors.grey.shade200),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: Colors.grey.shade200),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: Colors.indigo.shade300, width: 1.5),
                                  ),
                                  contentPadding: const EdgeInsets.all(16),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                        SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + MediaQuery.of(context).padding.bottom),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            'İPTAL',
                            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            final scaffoldMessenger = ScaffoldMessenger.of(context);
                            final notes = notesController.text;
                            Navigator.pop(context);
                            
                            // Save attendance
                            try {
                              await FirebaseFirestore.instance
                                  .collection('etut_requests')
                                  .doc(etutId)
                                  .update({
                                    'attendance': localAttendance,
                                    'attendanceTaken': true,
                                    'attendanceTakenAt': FieldValue.serverTimestamp(),
                                    'teacherNotes': notes,
                                  });
                              scaffoldMessenger.showSnackBar(
                                const SnackBar(content: Text('Yoklama kaydedildi.'))
                              );
                            } catch (e) {
                              scaffoldMessenger.showSnackBar(
                                SnackBar(content: Text('Hata: $e'))
                              );
                            }
                          },
                          child: const Text('KAYDET', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoRowForDialog(IconData icon, String label, String value, {bool isOrange = false}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.indigo.shade300),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isOrange ? Colors.orange.shade800 : Colors.indigo.shade900,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPresenceButtonForDialog({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? activeColor : Colors.grey.shade200),
        ),
        child: Icon(icon, size: 20, color: isSelected ? Colors.white : Colors.grey.shade400),
      ),
    );
  }

  Widget _buildEmptyStateForDialog(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
      ),
    );
  }
}
 
class Rx {
  static Stream<T> combineLatest3<A, B, C, T>(
    Stream<A> streamA,
    Stream<B> streamB,
    Stream<C> streamC,
    T Function(A a, B b, C c) combiner,
  ) {
    A? lastA;
    B? lastB;
    C? lastC;
    bool hasA = false;
    bool hasB = false;
    bool hasC = false;
 
    final controller = StreamController<T>();
 
    void emitIfReady() {
      try {
        if (hasA && hasB && hasC) {
          controller.add(combiner(lastA as A, lastB as B, lastC as C));
        }
      } catch (e, s) {
        debugPrint('CombineLatest3 Error: $e\n$s');
      }
    }
 
    final subA = streamA.listen((val) { lastA = val; hasA = true; emitIfReady(); }, onError: controller.addError);
    final subB = streamB.listen((val) { lastB = val; hasB = true; emitIfReady(); }, onError: controller.addError);
    final subC = streamC.listen((val) { lastC = val; hasC = true; emitIfReady(); }, onError: controller.addError);
 
    controller.onCancel = () {
      subA.cancel();
      subB.cancel();
      subC.cancel();
    };
 
    return controller.stream;
  }
 
  static Stream<T> combineLatest6<A, B, C, D, E, F, T>(
    Stream<A> streamA,
    Stream<B> streamB,
    Stream<C> streamC,
    Stream<D> streamD,
    Stream<E> streamE,
    Stream<F> streamF,
    T Function(A a, B b, C c, D d, E e, F f) combiner,
  ) {
    A? lastA;
    B? lastB;
    C? lastC;
    D? lastD;
    E? lastE;
    F? lastF;
    bool hasA = false;
    bool hasB = false;
    bool hasC = false;
    bool hasD = false;
    bool hasE = false;
    bool hasF = false;
 
    final controller = StreamController<T>();
 
    void emitIfReady() {
      try {
        if (hasA && hasB && hasC && hasD && hasE && hasF) {
          controller.add(combiner(lastA as A, lastB as B, lastC as C, lastD as D, lastE as E, lastF as F));
        }
      } catch (e, s) {
        debugPrint('CombineLatest Error: $e\n$s');
      }
    }
 
    final subA = streamA.listen((val) { lastA = val; hasA = true; emitIfReady(); }, onError: controller.addError);
    final subB = streamB.listen((val) { lastB = val; hasB = true; emitIfReady(); }, onError: controller.addError);
    final subC = streamC.listen((val) { lastC = val; hasC = true; emitIfReady(); }, onError: controller.addError);
    final subD = streamD.listen((val) { lastD = val; hasD = true; emitIfReady(); }, onError: controller.addError);
    final subE = streamE.listen((val) { lastE = val; hasE = true; emitIfReady(); }, onError: controller.addError);
    final subF = streamF.listen((val) { lastF = val; hasF = true; emitIfReady(); }, onError: controller.addError);
 
    controller.onCancel = () {
      subA.cancel();
      subB.cancel();
      subC.cancel();
      subD.cancel();
      subE.cancel();
      subF.cancel();
    };
 
    return controller.stream;
  }
}

class _CalendarSection extends StatefulWidget {
  final String institutionId;

  const _CalendarSection({
    Key? key,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<_CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<_CalendarSection> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final data = await UserPermissionService.loadUserData();
      if (mounted) {
        setState(() {
          _userData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user data for calendar: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SharedCalendarSection(
      schoolTypeId: '',
      institutionId: widget.institutionId,
      userData: _userData,
    );
  }
}
