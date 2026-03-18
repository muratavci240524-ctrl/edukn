import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../services/user_permission_service.dart';
import '../../services/announcement_service.dart';
import '../announcements/announcement_detail_screen.dart';
import 'teacher_social_media_screen.dart';
import '../../models/school/homework_model.dart';
import '../school/homework/homework_detail_screen.dart';
import '../school/attendance_operations_screen.dart';

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
 
  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }
 
  @override
  void dispose() {
    for (var s in _streams.values) {
      s.cancel();
    }
    super.dispose();
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
    final instId = widget.institutionId.toUpperCase();
 
    _listenTo('announcements', FirebaseFirestore.instance
        .collection('schools')
        .doc(_schoolId)
        .collection('announcements')
        .where('status', isEqualTo: 'published')
        .snapshots());
 
    _listenTo('social', FirebaseFirestore.instance
        .collection('social_media_posts')
        .where('institutionId', isEqualTo: instId)
        .snapshots());
 
    _listenTo('assignments', FirebaseFirestore.instance
        .collection('lessonAssignments')
        .where('institutionId', isEqualTo: instId)
        .where('teacherIds', arrayContains: currentUserId)
        .where('isActive', isEqualTo: true)
        .snapshots());
 
    _listenTo('duty', FirebaseFirestore.instance
        .collection('dutyScheduleItems')
        .where('institutionId', isEqualTo: instId)
        .where('teacherId', isEqualTo: currentUserId)
        .snapshots());
 
    _listenTo('schedules', FirebaseFirestore.instance
        .collection('classSchedules')
        .where('institutionId', isEqualTo: instId)
        .where('teacherIds', arrayContains: currentUserId)
        .where('isActive', isEqualTo: true)
        .snapshots());
 
    final todayDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _listenTo('attendance', FirebaseFirestore.instance
        .collection('lessonAttendance')
        .where('institutionId', isEqualTo: instId)
        .where('date', isEqualTo: todayDateStr)
        .snapshots());

    _listenTo('homeworks', FirebaseFirestore.instance
        .collection('homeworks')
        .where('institutionId', isEqualTo: instId)
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
        // If it's a missing index error, it's NOT a crash, but it needs an index.
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
 
    final List<Map<String, dynamic>> result = [];
    final user = FirebaseAuth.instance.currentUser;
    final currentUserId = user?.uid;
    final currentUserEmail = user?.email;
    final schoolTypes = _userData?['schoolTypes'] as List<dynamic>? ?? [];
    final userSchoolTypeSet = schoolTypes.map((e) => e.toString()).toSet();
    final now = DateTime.now();
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
        final publishDate = (data['publishDate'] as Timestamp?)?.toDate();
 
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
 
    // 2. NÖBET
    if (dutySnap != null) {
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final weekStart = DateTime(monday.year, monday.month, monday.day);
      for (var doc in dutySnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final dDayOfWeek = data['dayOfWeek'] as int?;
        final dWeekStart = (data['weekStart'] as Timestamp?)?.toDate();
        if (dDayOfWeek == now.weekday && dWeekStart != null) {
          if (dWeekStart.year == weekStart.year && dWeekStart.month == weekStart.month && dWeekStart.day == weekStart.day) {
            result.add({
              'id': 'duty_${doc.id}',
              'title': 'Bugün Nöbetçisiniz!',
              'subtitle': 'Nöbet yerinizi kontrol edin.',
              'time': now,
              'type': 'duty',
              'data': data,
            });
            break;
          }
        }
      }
    }
 
        // 3. YOKLAMA UYARISI
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
            
            final key = '${classId}_$lessonHour';
            if (!takenKeys.contains(key)) {
              result.add({
                'id': 'att_${doc.id}',
                'title': 'Yoklama Eksik: $className',
                'subtitle': '$lessonHour. ders yoklaması henüz alınmadı.',
                'time': now.subtract(const Duration(milliseconds: 100)),
                'type': 'attendance_warning',
                'data': data,
              });
            }
          }
        }
      } catch (e) {
        debugPrint('Attendance warning processing error: $e');
      }
    }
 
    // 4. SOSYAL
    if (socSnap != null) {
      final threeDaysAgo = now.subtract(const Duration(days: 3));
      for (var doc in socSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final readBy = List<dynamic>.from(data['readBy'] ?? []);
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
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

    // 5. ÖDEV KONTROLÜ
    if (hwSnap != null) {
      for (var doc in hwSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final dueDate = (data['dueDate'] as Timestamp?)?.toDate();
        if (dueDate != null) {
          final isTodayOrPast = dueDate.isBefore(now) || 
              (dueDate.year == now.year && dueDate.month == now.month && dueDate.day == now.day);
          
          if (isTodayOrPast) {
            final statuses = Map<String, dynamic>.from(data['studentStatuses'] ?? {});
            final targetIds = List<String>.from(data['targetStudentIds'] ?? []);
            
            // Eğer hiç durum girilmemişse veya bekleyen (0) varsa
            bool needsCheck = targetIds.isNotEmpty && (statuses.isEmpty || statuses.values.any((s) => s == 0));
            
            if (needsCheck) {
              result.add({
                'id': 'hw_${doc.id}',
                'title': 'Ödev Kontrolü: ${data['title']}',
                'subtitle': 'Kontrol edilmesi gereken ödev saati geldi.',
                'time': dueDate,
                'type': 'homework_warning',
                'data': {...data, 'id': doc.id},
              });
            }
          }
        }
      }
    }

    result.sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));
    if (mounted) {
      setState(() => _allNotifications = result);
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
    if (type == 'announcement') { icon = Icons.campaign_rounded; color = Colors.blue; }
    else if (type == 'duty') { icon = Icons.security_rounded; color = Colors.orange; }
    else if (type == 'attendance_warning') { icon = Icons.event_busy_rounded; color = Colors.red; }
    else { icon = Icons.share_rounded; color = Colors.purple; }
 
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    final timeStr = DateFormat('HH:mm').format(time);
 
    return InkWell(
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
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), spreadRadius: 2, blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
    required this.institutionId,
  });

  @override
  State<_CalendarSection> createState() => _CalendarSectionState();
}

class _CalendarSectionState extends State<_CalendarSection> {
  DateTime _focusedDay = DateTime.now();
  bool _isLoading = false;

  final List<String> _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];

  @override
  void initState() {
    super.initState();
    _loadTeacherEvents();
  }

  Future<void> _loadTeacherEvents() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }
      
      // Teacher specific events (Dersler, Etütler, Nöbetler vb.)
      // Bu örnekte mock etkinlikler yüklenebilir veya öğretmenin emailine/kullanıcı adına göre filtrelenebilir.
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Takvim yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isWideScreen = MediaQuery.of(context).size.width > 900;

    return Container(
      margin: EdgeInsets.all(isWideScreen ? 24 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: isWideScreen
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  spreadRadius: 5,
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_months[_focusedDay.month - 1]} ${_focusedDay.year}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    if (_isLoading)
                      Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: SizedBox(
                          width: 60,
                          height: 2,
                          child: LinearProgressIndicator(
                            backgroundColor: Colors.blue.withOpacity(0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.blue,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Takvim bileşeni ve size ait etkinlikler burada görünecek.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
