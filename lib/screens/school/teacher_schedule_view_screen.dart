import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'class_lesson_hub_screen.dart';
import '../../services/term_service.dart';

class TeacherScheduleViewScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final bool isTeacherView;

  const TeacherScheduleViewScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    this.isTeacherView = false,
  }) : super(key: key);

  @override
  State<TeacherScheduleViewScreen> createState() =>
      _TeacherScheduleViewScreenState();
}

class _TeacherScheduleViewScreenState extends State<TeacherScheduleViewScreen> {
  List<Map<String, dynamic>> _allTeachers = [];
  Map<String, dynamic>? _selectedTeacher;
  Map<String, Map<String, dynamic>> _scheduleData = {};
  List<String> _days = [];
  Map<String, int> _dailyLessonCounts = {};
  Map<String, List<Map<String, dynamic>>> _dayLessonTimes = {};
  bool _isLoading = true;
  String? _activePeriodId;
  bool _showTableViewWide = true;
  DateTime _weekStart = DateTime.now();
  int _currentTabIndex = 0; // 0: Program, 1: Etütler
  List<Map<String, dynamic>> _weeklyEtuts = [];

  // Öğretmen ders sayıları
  Map<String, int> _teacherLessonCounts = {};

  // Filtre değişkenleri
  String? _selectedBranch;
  Set<String> _availableBranches = {};

  final ScrollController _horizontalScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
    _loadData();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  MaterialColor _getColorFor(String text) {
    if (text.isEmpty) return Colors.blue;

    final colors = <MaterialColor>[
      Colors.teal,
      Colors.indigo,
      Colors.orange,
      Colors.pink,
      Colors.purple,
      Colors.blueGrey,
      Colors.cyan,
      Colors.brown,
      Colors.amber,
      Colors.deepOrange,
      Colors.lightGreen,
      Colors.lime,
      Colors.lightBlue,
      Colors.green,
      Colors.blue,
    ];

    final RegExp digitRegex = RegExp(r'\d+');
    final match = digitRegex.firstMatch(text);

    int index = 0;
    if (match != null) {
      index = int.parse(match.group(0)!);
    }

    // Add character offset to distinguish classes like 8-A, 8-B
    // This allows 801, 802 to be distinct (different numbers)
    // AND 8-A, 8-B to be distinct (different chars via sum)
    int charSum = 0;
    for (var code in text.runes) {
      if (code < 48 || code > 57) {
        charSum += code;
      }
    }

    return colors[(index + charSum).abs() % colors.length];
  }

  DateTime _startOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  String _monthNameTr(int month) {
    const months = <String>[
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    if (month < 1 || month > 12) return '';
    return months[month - 1];
  }

  String _formatWeekRange(DateTime weekStart) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(Duration(days: 6));
    if (start.month == end.month && start.year == end.year) {
      return '${start.day} - ${end.day} ${_monthNameTr(end.month)} ${end.year}';
    }
    return '${start.day} ${_monthNameTr(start.month)} - ${end.day} ${_monthNameTr(end.month)} ${end.year}';
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final instId = widget.institutionId.toUpperCase();
    final schoolTypeId = widget.schoolTypeId;

    try {
      // 1. Yayınlanmış aktif dönemi bul (Case-insensitive institutionId)
      var periodsSnapshot = await FirebaseFirestore.instance
          .collection('workPeriods')
          .where('schoolTypeId', isEqualTo: schoolTypeId)
          .where('institutionId', isEqualTo: instId)
          .where('isActive', isEqualTo: true)
          .where('schedulePublished', isEqualTo: true)
          .get();

      // Fallback: lowercase institutionId
      if (periodsSnapshot.docs.isEmpty) {
        periodsSnapshot = await FirebaseFirestore.instance
            .collection('workPeriods')
            .where('schoolTypeId', isEqualTo: schoolTypeId)
            .where('institutionId', isEqualTo: instId.toLowerCase())
            .where('isActive', isEqualTo: true)
            .where('schedulePublished', isEqualTo: true)
            .get();
      }

      if (periodsSnapshot.docs.isEmpty) {
        debugPrint('❌ Aktif veya yayınlanmış dönem bulunamadı. Inst: $instId, Type: $schoolTypeId');
        setState(() => _isLoading = false);
        return;
      }

      final periodDoc = periodsSnapshot.docs.first;
      _activePeriodId = periodDoc.id;
      final periodData = periodDoc.data();

      // Ders saatlerini yükle
      final lessonHoursData =
          periodData['lessonHours'] as Map<String, dynamic>?;
      if (lessonHoursData != null) {
        _days = List<String>.from(lessonHoursData['selectedDays'] ?? []);

        final dailyCountsRaw =
            lessonHoursData['dailyLessonCounts'] as Map<String, dynamic>?;
        if (dailyCountsRaw != null) {
          _dailyLessonCounts = dailyCountsRaw.map(
            (k, v) =>
                MapEntry(k, v is int ? v : int.tryParse(v.toString()) ?? 0),
          );
        }

        // Ders saatlerini parse et
        final lessonTimesRaw = lessonHoursData['lessonTimes'];
        if (lessonTimesRaw != null && lessonTimesRaw is Map) {
          final lessonTimesMap = Map<String, dynamic>.from(lessonTimesRaw);
          final firstKey = lessonTimesMap.keys.first;
          final isNumericKey = int.tryParse(firstKey) != null;

          if (isNumericKey) {
            final sortedKeys = lessonTimesMap.keys.toList()
              ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

            final hours = sortedKeys.map((key) {
              final time = Map<String, dynamic>.from(lessonTimesMap[key]);
              return {
                'hourNumber': int.parse(key) + 1,
                'startTime':
                    '${(time['startHour'] ?? 0).toString().padLeft(2, '0')}:${(time['startMinute'] ?? 0).toString().padLeft(2, '0')}',
                'endTime':
                    '${(time['endHour'] ?? 0).toString().padLeft(2, '0')}:${(time['endMinute'] ?? 0).toString().padLeft(2, '0')}',
              };
            }).toList();

            for (var day in _days) {
              _dayLessonTimes[day] = List.from(hours);
            }
          } else {
            for (var day in _days) {
              final dayData = lessonTimesMap[day];
              if (dayData != null && dayData is List) {
                _dayLessonTimes[day] = dayData.asMap().entries.map((entry) {
                  final time = Map<String, dynamic>.from(entry.value);
                  return {
                    'hourNumber': entry.key + 1,
                    'startTime':
                        '${(time['startHour'] ?? 0).toString().padLeft(2, '0')}:${(time['startMinute'] ?? 0).toString().padLeft(2, '0')}',
                    'endTime':
                        '${(time['endHour'] ?? 0).toString().padLeft(2, '0')}:${(time['endMinute'] ?? 0).toString().padLeft(2, '0')}',
                  };
                }).toList();
              }
            }
          }
        }
      }

      // 2. Öğretmenleri Yükle (Case-insensitive institutionId)
      var teachersQuerySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: instId)
          .where('type', isEqualTo: 'staff')
          .where('isActive', isEqualTo: true)
          .get();
      
      if (teachersQuerySnapshot.docs.isEmpty) {
        teachersQuerySnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: instId.toLowerCase())
            .where('type', isEqualTo: 'staff')
            .where('isActive', isEqualTo: true)
            .get();
      }

      final currentUid = FirebaseAuth.instance.currentUser?.uid;

      List<Map<String, dynamic>> teachers = teachersQuerySnapshot.docs
          .map((doc) {
            final data = doc.data();
            final fullName = (data['fullName'] ?? '').toString().trim();

            final firstNameRaw = (data['firstName'] ?? '').toString().trim();
            final lastNameRaw = (data['lastName'] ?? '').toString().trim();
            final firstName = firstNameRaw.isNotEmpty
                ? firstNameRaw
                : (fullName.split(' ').isNotEmpty
                      ? fullName.split(' ').first
                      : '');
            final lastName = lastNameRaw.isNotEmpty
                ? lastNameRaw
                : (fullName.split(' ').length > 1
                      ? fullName.split(' ').skip(1).join(' ')
                      : '');

            return {
              'id': doc.id,
              'name': fullName.isNotEmpty
                  ? fullName
                  : '${firstName} ${lastName}'.trim(),
              'firstName': firstName,
              'lastName': lastName,
              'branch': (data['branch'] ?? '').toString(),
              'title': (data['title'] ?? '').toString(),
              // Okul türü eşleştirmesi için ham alanlar
              'workLocations': data['workLocations'],
              'workLocation': data['workLocation'],
            };
          })
          .where((t) {
            // Eğer "Öğretmen Görünümü" ise ve bu kişi BEN isem her türlü geçsin
            if (widget.isTeacherView && currentUid != null && t['id'] == currentUid) {
              return true;
            }

            // Ünvan filtresi: öğretmen
            final title = (t['title'] ?? '').toString().toLowerCase();
            final isTeacher = title == 'ogretmen' || title == 'teacher' || title == 'öğretmen';
            if (!isTeacher) return false;

            // Okul türü filtresi: personel ekranındaki mantıkla uyumlu
            final dynamic workLocations = t['workLocations'];
            final dynamic workLocation = t['workLocation'];
            if (workLocations is List) {
              final locations = workLocations.map((e) => e.toString().toUpperCase()).toList();
              return locations.contains(widget.schoolTypeName.toUpperCase());
            }
            if (workLocation != null && workLocation.toString().isNotEmpty) {
              return workLocation.toString().toUpperCase() == widget.schoolTypeName.toUpperCase();
            }
            return true;
          })
          .map((t) {
            // UI için fazladan alanları temizle
            final copy = Map<String, dynamic>.from(t);
            copy.remove('workLocations');
            copy.remove('workLocation');
            return copy;
          })
          .toList();

      // Branş sırasına göre sırala, sonra ada göre
      teachers.sort((a, b) {
        final branchCompare = (a['branch'] ?? '').compareTo(b['branch'] ?? '');
        if (branchCompare != 0) return branchCompare;
        return (a['name'] ?? '').compareTo(b['name'] ?? '');
      });

      // Branşları topla
      final branches = teachers
          .map((t) => t['branch'] as String?)
          .where((b) => b != null && b.isNotEmpty)
          .cast<String>()
          .toSet();

      final selectedTermId = await TermService().getSelectedTermId();
      final activeTermId = await TermService().getActiveTermId();
      final effectiveTermId = selectedTermId ?? activeTermId;

      final lessonQueries = [
        FirebaseFirestore.instance.collection('lessons')
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('institutionId', isEqualTo: instId)
            .where('isActive', isEqualTo: true).get(),
        FirebaseFirestore.instance.collection('lessons')
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('institutionId', isEqualTo: instId.toLowerCase())
            .where('isActive', isEqualTo: true).get(),
      ];
      final lessonSnaps = await Future.wait(lessonQueries);
      final activeLessonIds = lessonSnaps.expand((s) => s.docs).map((d) => d.id).toSet();

      final Map<String, int> lessonCounts = {};
      final assignQueries = [
        FirebaseFirestore.instance.collection('lessonAssignments')
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('institutionId', isEqualTo: instId)
            .where('isActive', isEqualTo: true).get(),
        FirebaseFirestore.instance.collection('lessonAssignments')
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('institutionId', isEqualTo: instId.toLowerCase())
            .where('isActive', isEqualTo: true).get(),
      ];
      final assignSnaps = await Future.wait(assignQueries);
      final assignmentsDocs = assignSnaps.expand((s) => s.docs).toList();

      for (final doc in assignmentsDocs) {
        final data = doc.data();

        final assignmentTermId = (data['termId'] ?? '').toString();
        if (effectiveTermId != null && assignmentTermId != effectiveTermId) {
          continue;
        }

        final lessonId = (data['lessonId'] ?? '').toString();
        if (lessonId.isEmpty || !activeLessonIds.contains(lessonId)) {
          continue;
        }

        final dynamic weeklyHoursRaw = data['weeklyHours'];
        final int weeklyHours = weeklyHoursRaw is int
            ? weeklyHoursRaw
            : int.tryParse((weeklyHoursRaw ?? '').toString()) ?? 0;

        if (weeklyHours <= 0) continue;

        final dynamic teacherIdsRaw = data['teacherIds'];
        if (teacherIdsRaw is! List) continue;

        final uniqueTeacherIds = teacherIdsRaw.map((e) => e.toString()).toSet();
        for (final teacherId in uniqueTeacherIds) {
          if (teacherId.isEmpty) continue;
          lessonCounts[teacherId] =
              (lessonCounts[teacherId] ?? 0) + weeklyHours;
        }
      }

      setState(() {
        _allTeachers = teachers;
        _availableBranches = branches;
        _teacherLessonCounts = lessonCounts;
        
        // Mevcut kullanıcı bir öğretmen ise otomatik seç
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid != null && _selectedTeacher == null) {
          try {
            final self = _allTeachers.firstWhere(
              (t) => t['id'] == currentUid,
              orElse: () => {},
            );
            if (self.isNotEmpty) {
              _selectedTeacher = self;
              _loadTeacherSchedule(self['id']);
            } else if (widget.isTeacherView) {
              // Failsafe: Listede bulunmasa bile programını çekmeye çalış
              _selectedTeacher = {'id': currentUid, 'name': 'Öğretmen'};
              _loadTeacherSchedule(currentUid);
            }
          } catch (_) {
            if (widget.isTeacherView) {
              _selectedTeacher = {'id': currentUid, 'name': 'Öğretmen'};
              _loadTeacherSchedule(currentUid);
            }
          }
        }

        _isLoading = false;
      });
    } catch (e) {
      print('Veri yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTeacherSchedule(String teacherId) async {
    if (_activePeriodId == null) {
      debugPrint('⚠️ Ders programı yüklenemedi: Aktif dönem ID bulunamadı.');
      return;
    }

    final instId = widget.institutionId.toUpperCase();
    final schoolTypeId = widget.schoolTypeId;

    try {
      debugPrint('🔍 Program Verileri Yükleniyor - Teacher: $teacherId, Inst: $instId, Type: $schoolTypeId');
      
      // 1. Önce öğretmenin ders atamalarını bul (GENİŞLETİLMİŞ ARAMA)
      final assignQueries = [
        FirebaseFirestore.instance.collection('lessonAssignments')
            .where('institutionId', isEqualTo: instId)
            .where('schoolTypeId', isEqualTo: schoolTypeId)
            .where('teacherIds', arrayContains: teacherId).get(),
        FirebaseFirestore.instance.collection('lessonAssignments')
            .where('institutionId', isEqualTo: instId.toLowerCase())
            .where('schoolTypeId', isEqualTo: schoolTypeId)
            .where('teacherIds', arrayContains: teacherId).get(),
      ];

      final assignSnaps = await Future.wait(assignQueries);
      
      // (classId|lessonId) -> assignment info
      final Map<String, Map<String, dynamic>> assignmentMap = {};
      final Set<String> classIds = {};
      
      debugPrint('   DEBUG: Atama sorguları tamamlandı. Toplam snap: ${assignSnaps.length}');

      for (var snap in assignSnaps) {
        for (var doc in snap.docs) {
          final data = doc.data();
          final cid = (data['classId'] ?? '').toString();
          final lid = (data['lessonId'] ?? '').toString();
          
          final docInstId = (data['institutionId'] ?? "").toString().toUpperCase();
          final docTypeId = (data['schoolTypeId'] ?? "").toString();
          final docIsActive = data['isActive'] ?? true;

          debugPrint('   DEBUG: Atama Kontrol - ID: ${doc.id}, Class: $cid, Lesson: $lid, Inst: $docInstId, Type: $docTypeId, Active: $docIsActive');

          if (cid.isEmpty || lid.isEmpty) {
             debugPrint('     ⚠️ CID veya LID boş, atlanıyor.');
             continue;
          }

          // Seçili okul türü ve kurum kontrolü (Boşsa veya eşleşiyorsa al)
          bool instMatch = instId.isEmpty || docInstId == instId || docInstId == instId.toLowerCase();
          bool typeMatch = schoolTypeId.isEmpty || docTypeId == schoolTypeId;

          if (instMatch && typeMatch && docIsActive) {
            classIds.add(cid);
            assignmentMap['$cid|$lid'] = {
              'lessonName': (data['lessonName'] ?? '').toString(),
              'className': (data['className'] ?? '').toString(),
            };
            debugPrint('     ✅ Atama eklendi.');
          } else {
            debugPrint('     ❌ Filtreye takıldı: InstMatch: $instMatch, TypeMatch: $typeMatch, ActiveMatch: $docIsActive');
          }
        }
      }

      debugPrint('   - Final atama haritası: ${assignmentMap.length}, Benzersiz sınıf: ${classIds.length}');

      final List<String> classIdList = classIds.toList();

      // Şube adlarını tamamlamak için classes dokümanlarını batch + paralel çek
      final Map<String, String?> classNameById = {};
      final List<Future<QuerySnapshot<Map<String, dynamic>>>> classFetches = [];
      
      if (classIdList.isNotEmpty) {
        for (int i = 0; i < classIdList.length; i += 10) {
          final batch = classIdList.skip(i).take(10).toList();
          classFetches.add(
            FirebaseFirestore.instance
                .collection('classes')
                .where(FieldPath.documentId, whereIn: batch)
                .get(),
          );
        }
      }

      // Bu öğretmenin ders verdiği şubelerin programını batch + paralel çek
      final List<Future<QuerySnapshot<Map<String, dynamic>>>> scheduleFetches = [];
      
      // 1. Sınıf bazlı aramalar
      if (classIdList.isNotEmpty) {
        for (int i = 0; i < classIdList.length; i += 10) {
          final batch = classIdList.skip(i).take(10).toList();
          scheduleFetches.add(
            FirebaseFirestore.instance
                .collection('classSchedules')
                .where('periodId', isEqualTo: _activePeriodId)
                .where('classId', whereIn: batch)
                .where('isActive', isEqualTo: true)
                .get(),
          );
        }
      }

      // 2. Doğrudan öğretmen bazlı arama (Failsafe)
      scheduleFetches.add(
        FirebaseFirestore.instance
            .collection('classSchedules')
            .where('institutionId', isEqualTo: instId)
            .where('periodId', isEqualTo: _activePeriodId)
            .where('teacherIds', arrayContains: teacherId)
            .where('isActive', isEqualTo: true)
            .get(),
      );
      scheduleFetches.add(
        FirebaseFirestore.instance
            .collection('classSchedules')
            .where('institutionId', isEqualTo: instId.toLowerCase())
            .where('periodId', isEqualTo: _activePeriodId)
            .where('teacherIds', arrayContains: teacherId)
            .where('isActive', isEqualTo: true)
            .get(),
      );

      final classSnapshots = await Future.wait(classFetches);
      final scheduleSnapshots = await Future.wait(scheduleFetches);

      for (final snap in classSnapshots) {
        for (final doc in snap.docs) {
          classNameById[doc.id] = (doc.data()['className'] ?? '').toString();
        }
      }

      final Map<String, Map<String, dynamic>> scheduleData = {};
      for (final scheduleSnapshot in scheduleSnapshots) {
        for (var doc in scheduleSnapshot.docs) {
          final data = doc.data();
          final classId = (data['classId'] ?? '').toString();
          final lessonId = (data['lessonId'] ?? '').toString();
          if (classId.isEmpty || lessonId.isEmpty) continue;

          // Bu hücre, seçili öğretmenin atanmış olduğu bir derse mi ait?
          final assignmentKey = '${classId}|${lessonId}';
          final hasAssignment = assignmentMap.containsKey(assignmentKey);
          
          // EĞER assignmentMap'te yoksa ama dokumanın kendisinde bu öğretmen varsa yine de ekle (Failsafe)
          final lessonTeacherIds = List<String>.from(data['teacherIds'] ?? []);
          final isAssignedDirectly = lessonTeacherIds.contains(teacherId);

          if (!hasAssignment && !isAssignedDirectly) continue;

          final key = '${data['day']}_${data['hourIndex']}';

          // className ve lessonName'i assignment verisiyle tamamla
          final assignmentInfo = hasAssignment ? assignmentMap[assignmentKey]! : null;
          final className = assignmentInfo != null 
              ? (classNameById[classId] ?? assignmentInfo['className'])
              : (classNameById[classId] ?? data['className'] ?? 'Sınıf');
          final lessonName = assignmentInfo != null
              ? (assignmentInfo['lessonName'] ?? data['lessonName'])
              : (data['lessonName'] ?? 'Ders');

          scheduleData[key] = {
            ...data,
            'id': doc.id,
            'className': className,
            'lessonName': lessonName,
          };
        }
      }

      setState(() {
        _scheduleData = scheduleData;
      });

      // ---------------------------------------------------------
      // GEÇİCİ ATAMALARI YÜKLE (SUBSTITUTE / ABSENCE)
      // ---------------------------------------------------------
      try {
        final startOfWeek = DateTime(
          _weekStart.year,
          _weekStart.month,
          _weekStart.day,
        );
        final endOfWeek = startOfWeek
            .add(Duration(days: 7))
            .subtract(Duration(milliseconds: 1));

        final temporaryRef = FirebaseFirestore.instance.collection(
          'temporaryTeacherAssignments',
        );

        final absenceSnap = await temporaryRef
            .where('institutionId', isEqualTo: instId)
            .where('originalTeacherId', isEqualTo: teacherId)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek),
            )
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek))
            .where('status', isEqualTo: 'published')
            .get();

        final substituteSnap = await temporaryRef
            .where('institutionId', isEqualTo: instId)
            .where('substituteTeacherId', isEqualTo: teacherId)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek),
            )
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek))
            .where('status', isEqualTo: 'published')
            .get();

        print('DEBUG: Teacher ID: $teacherId');
        print('DEBUG: Date Range: $startOfWeek - $endOfWeek');
        print('DEBUG: Absence Docs: ${absenceSnap.docs.length}');
        print('DEBUG: Substitute Docs: ${substituteSnap.docs.length}');

        Map<String, Map<String, dynamic>> updatedSchedule =
            Map<String, Map<String, dynamic>>.from(_scheduleData);

        for (var doc in absenceSnap.docs) {
          final data = doc.data();
          // Calculate dayName from date to handle bad data
          final dateVal = (data['date'] as Timestamp).toDate();
          final dayNames = [
            '',
            'Pazartesi',
            'Salı',
            'Çarşamba',
            'Perşembe',
            'Cuma',
            'Cumartesi',
            'Pazar',
          ];
          final dayName = dayNames[dateVal.weekday];
          final hourIndex = data['hourIndex'];
          final subName = (data['substituteTeacherName'] ?? '').toString();

          final key = '${dayName}_$hourIndex';

          if (updatedSchedule.containsKey(key)) {
            final original = updatedSchedule[key]!;
            updatedSchedule[key] = {
              ...original,
              'isAbsence': true,
              'substituteName': subName,
              'reason': (data['reason'] ?? '').toString(),
            };
          }
        }

        for (var doc in substituteSnap.docs) {
          final data = doc.data();
          // Calculate dayName from date
          final dateVal = (data['date'] as Timestamp).toDate();
          final dayNames = [
            '',
            'Pazartesi',
            'Salı',
            'Çarşamba',
            'Perşembe',
            'Cuma',
            'Cumartesi',
            'Pazar',
          ];
          final dayName = dayNames[dateVal.weekday];
          final hourIndex = data['hourIndex'];
          final origName = (data['originalTeacherName'] ?? '').toString();

          final key = '${dayName}_$hourIndex';

          updatedSchedule[key] = {
            'id': doc.id,
            'className': (data['className'] ?? '').toString(),
            'lessonName': (data['lessonName'] ?? '').toString(),
            'isSubstitute': true,
            'originalTeacherName': origName,
            'day': dayName,
            'hourIndex': hourIndex,
            'classId': data['classId'],
            'lessonId': data['lessonId'],
            'institutionId': data['institutionId'],
            'schoolTypeId': data['schoolTypeId'],
            'isTemporary': true,
          };
        }

        // ---------------------------------------------------------
        // ETÜT TALEPLERİNİ YÜKLE (ETUT REQUESTS)
        // ---------------------------------------------------------
        List<Map<String, dynamic>> weeklyEtuts = [];
        try {
          final startMidnight = DateTime(
            startOfWeek.year,
            startOfWeek.month,
            startOfWeek.day,
          );
          final endMidnight = startMidnight.add(const Duration(days: 7));

          final etutSnapQueries = [
            FirebaseFirestore.instance.collection('etut_requests')
                .where('institutionId', isEqualTo: instId)
                .where('teacherId', isEqualTo: teacherId)
                .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startMidnight))
                .where('date', isLessThan: Timestamp.fromDate(endMidnight))
                .get(),
            FirebaseFirestore.instance.collection('etut_requests')
                .where('institutionId', isEqualTo: instId.toLowerCase())
                .where('teacherId', isEqualTo: teacherId)
                .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startMidnight))
                .where('date', isLessThan: Timestamp.fromDate(endMidnight))
                .get(),
          ];
          final etutSnaps = await Future.wait(etutSnapQueries);
          
          for (var snap in etutSnaps) {
            for (var doc in snap.docs) {
              final data = doc.data();
              data['id'] = doc.id;
              weeklyEtuts.add(data);
            }
          }

          // -------------------------------------------------------
          // STUDENT NAME FETCHING LOGIC - MASAÜSTÜ
          // -------------------------------------------------------
          final Set<String> allStudentIds = {};
          for (var etut in weeklyEtuts) {
            final sIds = List<String>.from(etut['studentIds'] ?? []);
            allStudentIds.addAll(sIds);
          }

          final Map<String, String> studentNameMap = {};
          if (allStudentIds.isNotEmpty) {
            final idsList = allStudentIds.toList();
            for (var i = 0; i < idsList.length; i += 10) {
              final chunk = idsList.skip(i).take(10).toList();
              try {
                // Try uppercase
                var userSnap = await FirebaseFirestore.instance
                    .collection('students')
                    .where('institutionId', isEqualTo: instId)
                    .where(FieldPath.documentId, whereIn: chunk)
                    .get();
                
                // Fallback to lowercase
                if (userSnap.docs.isEmpty) {
                  userSnap = await FirebaseFirestore.instance
                    .collection('students')
                    .where('institutionId', isEqualTo: instId.toLowerCase())
                    .where(FieldPath.documentId, whereIn: chunk)
                    .get();
                }

                for (var uDoc in userSnap.docs) {
                  final data = uDoc.data();
                  final name = data['fullName'] ?? data['name'] ?? '';
                  studentNameMap[uDoc.id] = name.toString();
                }
              } catch (e) {
                debugPrint('Error fetching students: $e');
              }
            }
          }

          for (var etut in weeklyEtuts) {
            final sIds = List<String>.from(etut['studentIds'] ?? []);
            if (sIds.isNotEmpty) {
              final List<String> freshNames = [];
              for (var sId in sIds) {
                if (studentNameMap.containsKey(sId)) {
                  freshNames.add(studentNameMap[sId]!);
                }
              }
              if (freshNames.isNotEmpty) {
                etut['studentNames'] = freshNames;
              }
            }
          }

          // Tarih ve saate göre sırala
          weeklyEtuts.sort((a, b) {
            final dateA = (a['date'] as Timestamp).toDate();
            final dateB = (b['date'] as Timestamp).toDate();
            final cmp = dateA.compareTo(dateB);
            if (cmp != 0) return cmp;

            final startA = (a['startTime'] as Timestamp).toDate();
            final startB = (b['startTime'] as Timestamp).toDate();
            return startA.compareTo(startB);
          });
        } catch (e) {
          debugPrint('Error loading etut requests: $e');
        }

        if (mounted) {
          setState(() {
            _scheduleData = updatedSchedule;
            _weeklyEtuts = weeklyEtuts;
          });
        }
      } catch (e) {
        print('Geçici atama yükleme hatası: $e');
      }
    } catch (e) {
      print('Program yükleme hatası: $e');
    }
  }

  List<Map<String, dynamic>> get _filteredTeachers {
    return _allTeachers.where((t) {
      // Arama filtresi
      if (_searchQuery.isNotEmpty) {
        final name = (t['name'] ?? '').toString().toLowerCase();
        if (!name.contains(_searchQuery.toLowerCase())) return false;
      }
      // Branş filtresi
      if (_selectedBranch != null) {
        final branch = t['branch'] as String?;
        if (branch != _selectedBranch) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.purple),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isTeacherView ? 'Benim Ders Programım' : 'Öğretmen Ders Programı',
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.schoolTypeName,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _activePeriodId == null
          ? _buildNoPublishedSchedule()
          : _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    if (widget.isTeacherView) {
      if (_selectedTeacher == null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Ders programınız hazırlanıyor...'),
            ],
          ),
        );
      }
      return _buildScheduleView();
    }

    final isWideScreen = MediaQuery.of(context).size.width > 900;

    // Mobil görünümde sadece liste göster
    if (!isWideScreen) {
      return _buildTeacherList();
    }

    // Geniş ekranda sol-sağ panel
    return Row(
      children: [
        // Sol panel - Öğretmen listesi
        Container(
          width: 320,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(right: BorderSide(color: Colors.grey.shade300)),
          ),
          child: _buildTeacherList(),
        ),
        // Sağ panel - Program görünümü
        Expanded(
          child: _selectedTeacher == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.touch_app,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Programı görmek için bir öğretmen seçin',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : _buildScheduleView(),
        ),
      ],
    );
  }

  Widget _buildTeacherList() {
    return Column(
      children: [
        // Filtreler - Öğretmen listesi tarzında
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue.shade600, Colors.blue.shade400],
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Başlık
              Row(
                children: [
                  Icon(Icons.person_outline, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Öğretmenler',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_filteredTeachers.length}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              // Arama
              SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Öğretmen ara...',
                    hintStyle: TextStyle(color: Colors.white70, fontSize: 14),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: Colors.white70,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear,
                              size: 18,
                              color: Colors.white70,
                            ),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 0,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              SizedBox(height: 12),
              // Filtre butonları - Tümü ve Branş
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedBranch = null;
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _selectedBranch == null
                              ? Colors.white
                              : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(
                            'Tümü',
                            style: TextStyle(
                              color: _selectedBranch == null
                                  ? Colors.blue
                                  : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: PopupMenuButton<String>(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _selectedBranch != null
                              ? Colors.white
                              : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.work_outline,
                              size: 14,
                              color: _selectedBranch != null
                                  ? Colors.blue
                                  : Colors.white,
                            ),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _selectedBranch ?? 'Branş',
                                style: TextStyle(
                                  color: _selectedBranch != null
                                      ? Colors.blue
                                      : Colors.white,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      onSelected: (branch) {
                        setState(() {
                          _selectedBranch = branch;
                        });
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(value: null, child: Text('Tümü')),
                        ..._availableBranches.map(
                          (branch) =>
                              PopupMenuItem(value: branch, child: Text(branch)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Öğretmen listesi
        Expanded(
          child: _filteredTeachers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_off,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Öğretmen bulunamadı',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  itemCount: _filteredTeachers.length,
                  itemBuilder: (context, index) {
                    final teacher = _filteredTeachers[index];
                    final isSelected = _selectedTeacher?['id'] == teacher['id'];
                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      elevation: isSelected ? 3 : 1,
                      color: isSelected ? Colors.blue.shade50 : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSelected ? Colors.blue : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: isSelected
                              ? Colors.blue
                              : Colors.blue.shade100,
                          child: Text(
                            (teacher['firstName'] ?? '').toString().isNotEmpty
                                ? (teacher['firstName'] as String)
                                      .substring(0, 1)
                                      .toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.blue.shade700,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          teacher['name'] ?? '',
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? Colors.blue.shade700
                                : Colors.grey.shade800,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Text(
                                teacher['branch'] ?? '',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_teacherLessonCounts[teacher['id']] ?? 0} saat',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: isSelected ? Colors.blue : Colors.grey,
                        ),
                        onTap: () {
                          setState(() {
                            _selectedTeacher = teacher;
                          });
                          _loadTeacherSchedule(teacher['id']);
                          // Mobil görünümde program sayfasına git
                          // Mobil görünümde program sayfasına git
                          if (MediaQuery.of(context).size.width <= 900) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    _TeacherScheduleDetailView(
                                      teacherData: teacher,
                                      days: _days,
                                      dailyLessonCounts: _dailyLessonCounts,
                                      dayLessonTimes: _dayLessonTimes,
                                      activePeriodId: _activePeriodId,
                                    ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNoPublishedSchedule() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today, size: 64, color: Colors.grey.shade400),
          SizedBox(height: 16),
          Text(
            'Yayınlanmış ders programı bulunamadı',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Ders programı yönetici tarafından yayınlandığında burada görünecektir',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleView() {
    if (_days.isEmpty) {
      return Center(child: Text('Ders saati tanımlanmamış'));
    }

    final maxHours = _dailyLessonCounts.values.isNotEmpty
        ? _dailyLessonCounts.values.reduce((a, b) => a > b ? a : b)
        : 8;

    return Column(
      children: [
        // Başlık
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade400, Colors.blue.shade600],
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_view_week, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_selectedTeacher!['name']}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () {
                        print('DEBUG: Left Arrow Clicked');
                        setState(() {
                          _weekStart = _weekStart.subtract(Duration(days: 7));
                        });
                        print('DEBUG: New WeekStart: $_weekStart');
                        if (_selectedTeacher != null) {
                          print(
                            'DEBUG: Loading for teacher: ${_selectedTeacher!['id']}',
                          );
                          if (_selectedTeacher != null) {
                            print(
                              'DEBUG: Loading for teacher: ${_selectedTeacher!['id']}',
                            );
                            _loadTeacherSchedule(_selectedTeacher!['id']);
                          } else {
                            print('DEBUG: selectedTeacher is NULL');
                          }
                        } else {
                          print('DEBUG: selectedTeacher is NULL');
                        }
                      },
                      icon: Icon(Icons.chevron_left, color: Colors.white),
                    ),
                    SizedBox(width: 6),
                    Text(
                      _formatWeekRange(_weekStart),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () {
                        print('DEBUG: Right Arrow Clicked');
                        setState(() {
                          _weekStart = _weekStart.add(Duration(days: 7));
                        });
                        print('DEBUG: New WeekStart: $_weekStart');
                        if (_selectedTeacher != null) {
                          print(
                            'DEBUG: Loading for teacher: ${_selectedTeacher!['id']}',
                          );
                          if (_selectedTeacher != null) {
                            print(
                              'DEBUG: Loading for teacher: ${_selectedTeacher!['id']}',
                            );
                            _loadTeacherSchedule(_selectedTeacher!['id']);
                          } else {
                            print('DEBUG: selectedTeacher is NULL');
                          }
                        } else {
                          print('DEBUG: selectedTeacher is NULL');
                        }
                      },
                      icon: Icon(Icons.chevron_right, color: Colors.white),
                    ),
                    SizedBox(width: 10),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () {
                        setState(() {
                          _showTableViewWide = !_showTableViewWide;
                        });
                      },
                      icon: Icon(
                        _showTableViewWide
                            ? Icons.view_agenda_outlined
                            : Icons.table_rows_outlined,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _buildTabToggle(), // Moved here from header
        Expanded(
          child: _currentTabIndex == 0
              ? (_showTableViewWide
                    ? _buildTableScheduleWide(maxHours)
                    : _buildCardScheduleWide())
              : _buildEtutListView(),
        ),
      ],
    );
  }

  Widget _buildTabToggle() {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      padding: EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tabButton(0, 'Program', Icons.grid_on),
          _tabButton(1, 'Etütler', Icons.list_alt),
        ],
      ),
    );
  }

  Widget _tabButton(int index, String label, IconData icon) {
    final isSelected = _currentTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTabIndex = index),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.blue.shade700 : Colors.blue.shade300,
            ),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue.shade700 : Colors.blue.shade600,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEtutListView() {
    if (_weeklyEtuts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 48, color: Colors.grey.shade400),
            SizedBox(height: 12),
            Text(
              'Bu hafta için etüt bulunamadı',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _weeklyEtuts.length,
      itemBuilder: (context, index) {
        final etut = _weeklyEtuts[index];
        final date = (etut['date'] as Timestamp).toDate();
        final start = (etut['startTime'] as Timestamp).toDate();
        final end = (etut['endTime'] as Timestamp).toDate();
        final topic = etut['topic'] ?? 'Konu Belirtilmemiş';
        final action = (etut['action'] ?? '').toString();
        final duration = end.difference(start).inMinutes;
        final studentNames = List<String>.from(etut['studentNames'] ?? []);
        final attendanceTaken = etut['attendanceTaken'] ?? false;

        return Card(
          margin: EdgeInsets.only(bottom: 12),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200, width: 0.5),
          ),
          child: InkWell(
            onTap: () => _showAttendanceDialog(etut),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: attendanceTaken
                          ? Colors.green.shade50
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            color: attendanceTaken
                                ? Colors.green.shade700
                                : Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          _monthNameTr(
                            date.month,
                          ).substring(0, 3).toUpperCase(),
                          style: TextStyle(
                            color: attendanceTaken
                                ? Colors.green.shade700
                                : Colors.blue.shade700,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          studentNames.isNotEmpty
                              ? studentNames.join(', ')
                              : 'Öğrenci Belirtilmemiş',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4),
                        Text(
                          topic,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (action.isNotEmpty) ...[
                          SizedBox(height: 8),
                          Text(
                            action,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ],
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: Colors.grey,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} ($duration dk)',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            Spacer(),
                            if (attendanceTaken)
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 14,
                                    color: Colors.green,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Yoklama Alındı',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                'Yoklama Bekliyor',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAttendanceDialog(Map<String, dynamic> etut) {
    final List<String> studentIds = List<String>.from(etut['studentIds'] ?? []);
    final List<String> studentNames = List<String>.from(
      etut['studentNames'] ?? [],
    );
    final Map<String, dynamic> attendanceData = etut['attendance'] ?? {};
    final Map<String, bool> localAttendance = {};
    for (var id in studentIds) {
      localAttendance[id] = attendanceData[id] ?? true;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final notesController = TextEditingController(
            text: etut['teacherNotes'] ?? '',
          );
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            titlePadding: EdgeInsets.zero,
            title: Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(Icons.assignment, color: Colors.blue.shade700),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Etüt Detayı',
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Bilgi Kartı
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.topic_outlined,
                                size: 18,
                                color: Colors.grey.shade600,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  etut['topic'] ?? 'Konu Belirtilmemiş',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if ((etut['action'] ?? '').toString().isNotEmpty) ...[
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.category_outlined,
                                  size: 18,
                                  color: Colors.grey.shade600,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  etut['action'],
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Yoklama Listesi',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    SizedBox(height: 12),
                    if (studentIds.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Text(
                            'Öğrenci bulunamadı',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: List.generate(studentIds.length, (index) {
                            final sId = studentIds[index];
                            final sName = index < studentNames.length
                                ? studentNames[index]
                                : 'Öğrenci ($sId)';
                            final isPresent = localAttendance[sId] ?? true;
                            final isLast = index == studentIds.length - 1;

                            return Container(
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: isLast
                                      ? BorderSide.none
                                      : BorderSide(color: Colors.grey.shade100),
                                ),
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                title: Text(
                                  sName,
                                  style: TextStyle(fontSize: 14),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ToggleButtons(
                                      isSelected: [isPresent, !isPresent],
                                      onPressed: (idx) {
                                        setDialogState(() {
                                          localAttendance[sId] = idx == 0;
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      constraints: BoxConstraints(
                                        minHeight: 32,
                                        minWidth: 40,
                                      ),
                                      selectedColor: Colors.white,
                                      fillColor: isPresent
                                          ? Colors.green
                                          : Colors.red,
                                      children: [
                                        Icon(
                                          Icons.check,
                                          color: isPresent
                                              ? Colors.white
                                              : Colors.green,
                                          size: 16,
                                        ),
                                        Icon(
                                          Icons.close,
                                          color: !isPresent
                                              ? Colors.white
                                              : Colors.red,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    SizedBox(height: 24),
                    Text(
                      'Öğretmen Notları',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Etüt ile ilgili notlar...',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
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
                          borderSide: BorderSide(
                            color: Colors.blue.shade300,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: EdgeInsets.all(16),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            actionsPadding: EdgeInsets.all(20),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'İPTAL',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () async {
                  final notes = notesController.text;
                  Navigator.pop(context);
                  await _saveAttendance(etut['id'], localAttendance, notes);
                },
                child: Text('KAYDET'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveAttendance(
    String etutId,
    Map<String, bool> attendance,
    String teacherNotes,
  ) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('etut_requests')
          .doc(etutId)
          .update({
            'attendance': attendance,
            'attendanceTaken': true,
            'attendanceTakenAt': FieldValue.serverTimestamp(),
            'teacherNotes': teacherNotes,
          });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Yoklama kaydedildi.')));
        if (_selectedTeacher != null) {
          _loadTeacherSchedule(_selectedTeacher!['id']);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _dayNameTr(int weekday) {
    const days = <String>[
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    if (weekday < 1 || weekday > 7) return '';
    return days[weekday - 1];
  }

  Map<String, dynamic>? _getEtutForSlot(String day, int hourIndex) {
    if (_weeklyEtuts.isEmpty) return null;

    // Check if we have lesson times for this day and hour
    final dayTimes = _dayLessonTimes[day];
    if (dayTimes == null || dayTimes.length <= hourIndex) return null;

    final slotTime = dayTimes[hourIndex];
    // slotTime is { hourNumber: 1, startTime: "09:00", endTime: "09:40" }
    final slotStart = (slotTime['startTime'] ?? '').toString();
    if (slotStart.isEmpty) return null;

    for (var etut in _weeklyEtuts) {
      final etutDate = (etut['date'] as Timestamp).toDate();
      final etutDayName = _dayNameTr(etutDate.weekday);
      if (etutDayName != day) continue;

      final etutStart = (etut['startTime'] as Timestamp).toDate();
      final etutStartStr =
          '${etutStart.hour.toString().padLeft(2, '0')}:${etutStart.minute.toString().padLeft(2, '0')}';

      if (etutStartStr == slotStart) {
        return etut;
      }
    }
    return null;
  }

  Widget _buildTableScheduleWide(int maxHours) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
      ),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _horizontalScrollController,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: [
                        Container(
                          width: 100,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.blue.shade500,
                                Colors.blue.shade700,
                              ],
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'GÜN',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                        ...List.generate(
                          maxHours,
                          (hourIndex) => Container(
                            width: 90,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.shade500,
                                  Colors.blue.shade700,
                                ],
                              ),
                              border: Border(
                                left: BorderSide(
                                  color: Colors.blue.shade400,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '${hourIndex + 1}. Ders',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Data rows
                    ...List.generate(_days.length, (dayIndex) {
                      final day = _days[dayIndex];
                      final dayHourCount = _dailyLessonCounts[day] ?? maxHours;
                      final isLast = dayIndex == _days.length - 1;
                      final isEvenRow = dayIndex % 2 == 0;

                      return Row(
                        children: [
                          // Day label
                          Container(
                            width: 100,
                            height: 72,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isEvenRow
                                    ? [
                                        Colors.blue.shade50,
                                        Colors.blue.shade100,
                                      ]
                                    : [Colors.white, Colors.blue.shade50],
                              ),
                              border: Border(
                                top: BorderSide(
                                  color: Colors.blue.shade100,
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                day,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ),
                          ),
                          // Hour cells
                          ...List.generate(maxHours, (hourIndex) {
                            if (hourIndex >= dayHourCount) {
                              return Container(
                                width: 90,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.grey.shade200,
                                      width: 1,
                                    ),
                                    left: BorderSide(
                                      color: Colors.grey.shade200,
                                      width: 1,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final key = '${day}_$hourIndex';
                            final assignment = _scheduleData[key];

                            MaterialColor? cellColor;
                            if (assignment != null) {
                              if (assignment['isSubstitute'] == true) {
                                cellColor = Colors.orange;
                              } else if (assignment['isAbsence'] == true) {
                                cellColor = Colors.grey;
                              } else {
                                cellColor = _getColorFor(
                                  (assignment['className'] ?? '')
                                      .toString()
                                      .trim()
                                      .toUpperCase(),
                                );
                              }
                            }

                            final etut = _getEtutForSlot(day, hourIndex);

                            return Stack(
                              children: [
                                Container(
                                  width: 90,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    gradient: assignment != null
                                        ? LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              cellColor!.shade100,
                                              cellColor.shade200,
                                            ],
                                          )
                                        : null,
                                    color: assignment == null
                                        ? (isEvenRow
                                              ? Colors.grey.shade50
                                              : Colors.white)
                                        : null,
                                    border: Border(
                                      top: BorderSide(
                                        color: assignment != null
                                            ? cellColor!.shade300
                                            : Colors.grey.shade200,
                                        width: 1,
                                      ),
                                      left: BorderSide(
                                        color: assignment != null
                                            ? cellColor!.shade300
                                            : Colors.grey.shade200,
                                        width: 1,
                                      ),
                                      bottom: isLast
                                          ? BorderSide(
                                              color: assignment != null
                                                  ? cellColor!.shade300
                                                  : Colors.grey.shade200,
                                              width: 1,
                                            )
                                          : BorderSide.none,
                                    ),
                                  ),
                                  child: assignment != null
                                      ? assignment['isAbsence'] == true
                                            ? Padding(
                                                padding: EdgeInsets.all(4),
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      '${(assignment['className'] ?? '')} - İZİNLİ',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors
                                                            .grey
                                                            .shade700,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                    SizedBox(height: 2),
                                                    Text(
                                                      '${(assignment['lessonName'] ?? '')} - ${(assignment['substituteName'] ?? '-')}',
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        color: Colors
                                                            .grey
                                                            .shade600,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 6,
                                                ),
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    if (assignment['isSubstitute'] ==
                                                        true) ...[
                                                      Container(
                                                        padding:
                                                            EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 1,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors
                                                              .orange
                                                              .shade700,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          'GÖREVLİ',
                                                          style: TextStyle(
                                                            fontSize: 8,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(height: 2),
                                                    ],
                                                    Text(
                                                      (assignment['className'] ??
                                                              '')
                                                          .toString(),
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            cellColor!.shade900,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 1,
                                                    ),
                                                    SizedBox(height: 2),
                                                    if (assignment['isSubstitute'] ==
                                                        true)
                                                      Flexible(
                                                        child: Text(
                                                          '${(assignment['lessonName'] ?? '')} - ${(assignment['originalTeacherName'] ?? '')}',
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            color: cellColor
                                                                .shade700,
                                                          ),
                                                          textAlign:
                                                              TextAlign.center,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      )
                                                    else
                                                      Flexible(
                                                        child: Text(
                                                          (assignment['lessonName'] ??
                                                                  '')
                                                              .toString(),
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: cellColor
                                                                .shade700,
                                                          ),
                                                          textAlign:
                                                              TextAlign.center,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              )
                                      : null,
                                ),
                                if (etut != null)
                                  Positioned.fill(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () =>
                                            _showAttendanceDialog(etut),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Colors.green.shade100,
                                                Colors.green.shade200,
                                              ],
                                            ),
                                            border: Border.all(
                                              color: Colors.green.shade300,
                                              width: 1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          padding: EdgeInsets.all(4),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                'ETÜT',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green.shade900,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Expanded(
                                                child: Center(
                                                  child: Text(
                                                    (etut['studentName'] ??
                                                            'Öğrenci')
                                                        .toString(),
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      color:
                                                          Colors.green.shade800,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          }),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardScheduleWide() {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _days.map((day) {
            final dayHourCount = _dailyLessonCounts[day] ?? 8;
            final dayTimes = _dayLessonTimes[day] ?? [];

            return Container(
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            day,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$dayHourCount ders',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...List.generate(dayHourCount, (hourIndex) {
                    final timeInfo = hourIndex < dayTimes.length
                        ? dayTimes[hourIndex]
                        : null;
                    final startTime = timeInfo != null
                        ? (timeInfo['startTime'] ?? '').toString()
                        : '';
                    final endTime = timeInfo != null
                        ? (timeInfo['endTime'] ?? '').toString()
                        : '';
                    final key = '${day}_$hourIndex';
                    final assignment = _scheduleData[key];

                    return InkWell(
                      onTap: assignment == null
                          ? null
                          : () {
                              final classId = (assignment['classId'] ?? '')
                                  .toString();
                              final lessonId = (assignment['lessonId'] ?? '')
                                  .toString();
                              if (classId.isEmpty || lessonId.isEmpty) return;

                              final dayIndex = _days.indexOf(day);
                              final initialDate = dayIndex >= 0
                                  ? _weekStart.add(Duration(days: dayIndex))
                                  : null;
                              final List<int> availableLessonHours = [];
                              for (int i = 0; i < dayHourCount; i++) {
                                final checkKey = '${day}_$i';
                                final a = _scheduleData[checkKey];
                                final aClassId = (a?['classId'] ?? '')
                                    .toString();
                                final aLessonId = (a?['lessonId'] ?? '')
                                    .toString();
                                if (aClassId == classId &&
                                    aLessonId == lessonId) {
                                  availableLessonHours.add(i + 1);
                                }
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ClassLessonHubScreen(
                                    institutionId:
                                        (assignment['institutionId'] ?? '')
                                            .toString(),
                                    schoolTypeId:
                                        (assignment['schoolTypeId'] ?? '')
                                            .toString(),
                                    periodId: _activePeriodId,
                                    classId: classId,
                                    lessonId: lessonId,
                                    className: (assignment['className'] ?? '')
                                        .toString(),
                                    lessonName: (assignment['lessonName'] ?? '')
                                        .toString(),
                                    initialDate: initialDate,
                                    initialLessonHour: hourIndex + 1,
                                    availableLessonHours: availableLessonHours,
                                  ),
                                ),
                              );
                            },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: hourIndex == dayHourCount - 1
                                  ? Colors.transparent
                                  : Colors.grey.shade200,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 60,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${hourIndex + 1}. Ders',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  if (startTime.isNotEmpty)
                                    Text(
                                      startTime,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  if (endTime.isNotEmpty)
                                    Text(
                                      endTime,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(child: _buildCardItemLogic(assignment)),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCardItemLogic(Map<String, dynamic>? assignment) {
    if (assignment == null) {
      return Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Boş',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      );
    }

    MaterialColor cellColor;
    if (assignment['isSubstitute'] == true) {
      cellColor = Colors.orange;
    } else if (assignment['isAbsence'] == true) {
      cellColor = Colors.grey;
    } else {
      cellColor = _getColorFor((assignment['className'] ?? '').toString());
    }

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cellColor.shade300, cellColor.shade400],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (assignment['isSubstitute'] == true) ...[
                Text(
                  'GÖREVLİ',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  (assignment['className'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          if (assignment['isSubstitute'] == true)
            Text(
              '${(assignment['lessonName'] ?? '')} - ${(assignment['originalTeacherName'] ?? '')}',
              style: TextStyle(fontSize: 11, color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          else if (assignment['isAbsence'] == true)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'İZİNLİ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
                Text(
                  '${(assignment['lessonName'] ?? '')} - ${(assignment['substituteName'] ?? '-')}',
                  style: TextStyle(fontSize: 11, color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            )
          else
            Text(
              (assignment['lessonName'] ?? '').toString(),
              style: TextStyle(fontSize: 11, color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

// Mobil görünüm için öğretmen detay sayfası
class _TeacherScheduleDetailView extends StatefulWidget {
  final Map<String, dynamic> teacherData;
  final List<String> days;
  final Map<String, int> dailyLessonCounts;
  final Map<String, List<Map<String, dynamic>>> dayLessonTimes;
  final String? activePeriodId;

  const _TeacherScheduleDetailView({
    required this.teacherData,
    required this.days,
    required this.dailyLessonCounts,
    required this.dayLessonTimes,
    this.activePeriodId,
  });

  @override
  State<_TeacherScheduleDetailView> createState() =>
      _TeacherScheduleDetailViewState();
}

class _TeacherScheduleDetailViewState
    extends State<_TeacherScheduleDetailView> {
  Map<String, Map<String, dynamic>> _scheduleData = {};
  bool _showTableView = true;
  final ScrollController _horizontalScrollController = ScrollController();
  DateTime _weekStart = DateTime.now();
  int _currentTabIndex = 0; // 0: Program, 1: Etütler
  List<Map<String, dynamic>> _weeklyEtuts = [];
  bool _isLoading = false;

  MaterialColor _getColorFor(String text) {
    if (text.isEmpty) return Colors.blue;
    final colors = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.brown,
      Colors.blue,
    ];
    final hash = text.hashCode;
    return colors[hash.abs() % colors.length];
  }

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
    _loadSchedule();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  DateTime _startOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  String _monthNameTr(int month) {
    const months = <String>[
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    if (month < 1 || month > 12) return '';
    return months[month - 1];
  }

  String _formatWeekRange(DateTime weekStart) {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(Duration(days: 6));
    if (start.month == end.month && start.year == end.year) {
      return '${start.day} - ${end.day} ${_monthNameTr(end.month)} ${end.year}';
    }
    return '${start.day} ${_monthNameTr(start.month)} - ${end.day} ${_monthNameTr(end.month)} ${end.year}';
  }

  Future<void> _loadSchedule() async {
    if (widget.activePeriodId == null) return;
    setState(() => _isLoading = true);

    try {
      final teacherId = (widget.teacherData['id'] ?? '').toString();
      if (teacherId.isEmpty) return;

      final assignmentsSnapshot = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('isActive', isEqualTo: true)
          .where('teacherIds', arrayContains: teacherId)
          .get();

      final Set<String> classIds = {};
      final Map<String, Map<String, dynamic>> assignmentMap = {};
      for (var doc in assignmentsSnapshot.docs) {
        final data = doc.data();
        final classId = (data['classId'] ?? '').toString();
        final lessonId = (data['lessonId'] ?? '').toString();
        if (classId.isEmpty || lessonId.isEmpty) continue;
        classIds.add(classId);
        assignmentMap['${classId}|${lessonId}'] = {
          'lessonName': (data['lessonName'] ?? '').toString(),
          'className': (data['className'] ?? '').toString(),
        };
      }

      if (classIds.isEmpty) {
        setState(() {
          _scheduleData = {};
        });
        return;
      }

      final classIdList = classIds.toList();
      final List<Future<QuerySnapshot<Map<String, dynamic>>>> scheduleFetches =
          [];
      for (int i = 0; i < classIdList.length; i += 10) {
        final batch = classIdList.skip(i).take(10).toList();
        scheduleFetches.add(
          FirebaseFirestore.instance
              .collection('classSchedules')
              .where('periodId', isEqualTo: widget.activePeriodId)
              .where('classId', whereIn: batch)
              .where('isActive', isEqualTo: true)
              .get(),
        );
      }

      final scheduleSnapshots = await Future.wait(scheduleFetches);

      final Map<String, Map<String, dynamic>> scheduleData = {};
      for (final snap in scheduleSnapshots) {
        for (final doc in snap.docs) {
          final data = doc.data();
          final classId = (data['classId'] ?? '').toString();
          final lessonId = (data['lessonId'] ?? '').toString();
          final assignmentKey = '${classId}|${lessonId}';
          if (!assignmentMap.containsKey(assignmentKey)) continue;

          final key = '${data['day']}_${data['hourIndex']}';
          final assignmentInfo = assignmentMap[assignmentKey]!;
          scheduleData[key] = {
            ...data,
            'id': doc.id,
            'className': assignmentInfo['className'],
            'lessonName': assignmentInfo['lessonName'],
          };
        }
      }

      // GEÇİCİ ATAMALARI YÜKLE (SUBSTITUTE / ABSENCE)
      try {
        final startOfWeek = DateTime(
          _weekStart.year,
          _weekStart.month,
          _weekStart.day,
        );
        final endOfWeek = startOfWeek
            .add(Duration(days: 7))
            .subtract(Duration(milliseconds: 1));

        final temporaryRef = FirebaseFirestore.instance.collection(
          'temporaryTeacherAssignments',
        );

        final absenceSnap = await temporaryRef
            .where('originalTeacherId', isEqualTo: teacherId)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek),
            )
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek))
            .where('status', isEqualTo: 'published')
            .get();

        final substituteSnap = await temporaryRef
            .where('substituteTeacherId', isEqualTo: teacherId)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek),
            )
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek))
            .where('status', isEqualTo: 'published')
            .get();

        for (var doc in absenceSnap.docs) {
          final data = doc.data();
          // Calculate dayName from date
          final dateVal = (data['date'] as Timestamp).toDate();
          final dayNames = [
            '',
            'Pazartesi',
            'Salı',
            'Çarşamba',
            'Perşembe',
            'Cuma',
            'Cumartesi',
            'Pazar',
          ];
          final dayName = dayNames[dateVal.weekday];
          final hourIndex = data['hourIndex'];
          final subName = (data['substituteTeacherName'] ?? '').toString();

          final key = '${dayName}_$hourIndex';

          if (scheduleData.containsKey(key)) {
            final original = scheduleData[key]!;
            scheduleData[key] = {
              ...original,
              'isAbsence': true,
              'substituteName': subName,
              'reason': (data['reason'] ?? '').toString(),
            };
          }
        }

        for (var doc in substituteSnap.docs) {
          final data = doc.data();
          // Calculate dayName from date
          final dateVal = (data['date'] as Timestamp).toDate();
          final dayNames = [
            '',
            'Pazartesi',
            'Salı',
            'Çarşamba',
            'Perşembe',
            'Cuma',
            'Cumartesi',
            'Pazar',
          ];
          final dayName = dayNames[dateVal.weekday];
          final hourIndex = data['hourIndex'];
          final origName = (data['originalTeacherName'] ?? '').toString();

          final key = '${dayName}_$hourIndex';

          scheduleData[key] = {
            'id': doc.id,
            'className': (data['className'] ?? '').toString(),
            'lessonName': (data['lessonName'] ?? '').toString(),
            'isSubstitute': true,
            'originalTeacherName': origName,
            'day': dayName,
            'hourIndex': hourIndex,
            'classId': data['classId'],
            'lessonId': data['lessonId'],
            'institutionId': data['institutionId'],
            'schoolTypeId': data['schoolTypeId'],
            'isTemporary': true,
          };
        }
        // ---------------------------------------------------------
        // ETÜT TALEPLERİNİ YÜKLE (ETUT REQUESTS)
        // ---------------------------------------------------------
        List<Map<String, dynamic>> weeklyEtuts = [];
        try {
          final startMidnight = DateTime(
            startOfWeek.year,
            startOfWeek.month,
            startOfWeek.day,
          );
          final endMidnight = startMidnight.add(const Duration(days: 7));
          final etutSnap = await FirebaseFirestore.instance
              .collection('etut_requests')
              .where('teacherId', isEqualTo: teacherId)
              .where(
                'date',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startMidnight),
              )
              .where('date', isLessThan: Timestamp.fromDate(endMidnight))
              .get();

          for (var doc in etutSnap.docs) {
            final data = doc.data();
            data['id'] = doc.id;
            weeklyEtuts.add(data);
          }

          // -------------------------------------------------------
          // STUDENT NAME FETCHING LOGIC
          // -------------------------------------------------------
          final Set<String> allStudentIds = {};
          for (var etut in weeklyEtuts) {
            final sIds = List<String>.from(etut['studentIds'] ?? []);
            allStudentIds.addAll(sIds);
          }

          final Map<String, String> studentNameMap = {};
          if (allStudentIds.isNotEmpty) {
            final idsList = allStudentIds.toList();
            for (var i = 0; i < idsList.length; i += 10) {
              final chunk = idsList.skip(i).take(10).toList();
              try {
                final userSnap = await FirebaseFirestore.instance
                    .collection('students')
                    .where(FieldPath.documentId, whereIn: chunk)
                    .get();
                for (var uDoc in userSnap.docs) {
                  final data = uDoc.data();
                  final name = data['fullName'] ?? data['name'] ?? '';
                  studentNameMap[uDoc.id] = name.toString();
                }
              } catch (e) {
                debugPrint('Error fetching students: $e');
              }
            }
          }

          for (var etut in weeklyEtuts) {
            final sIds = List<String>.from(etut['studentIds'] ?? []);
            if (sIds.isNotEmpty) {
              final List<String> freshNames = [];
              for (var sId in sIds) {
                if (studentNameMap.containsKey(sId)) {
                  freshNames.add(studentNameMap[sId]!);
                }
              }
              if (freshNames.isNotEmpty) {
                etut['studentNames'] = freshNames;
              }
            }
          }

          weeklyEtuts.sort((a, b) {
            final dateA = (a['date'] as Timestamp).toDate();
            final dateB = (b['date'] as Timestamp).toDate();
            final cmp = dateA.compareTo(dateB);
            if (cmp != 0) return cmp;
            final startA = (a['startTime'] as Timestamp).toDate();
            final startB = (b['startTime'] as Timestamp).toDate();
            return startA.compareTo(startB);
          });
        } catch (e) {
          debugPrint('Error loading etut requests: $e');
        }

        setState(() {
          _scheduleData = scheduleData;
          _weeklyEtuts = weeklyEtuts;
          _isLoading = false;
        });
      } catch (e) {
        print('Geçici atama yükleme hatası: $e');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Program yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  Widget _buildTabToggle() {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      padding: EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tabButton(0, 'Program', Icons.grid_on),
          _tabButton(1, 'Etütler', Icons.list_alt),
        ],
      ),
    );
  }

  Widget _tabButton(int index, String label, IconData icon) {
    final isSelected = _currentTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTabIndex = index),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? Colors.blue.shade700 : Colors.blue.shade300,
            ),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue.shade700 : Colors.blue.shade600,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teacherName = widget.teacherData['name'] ?? '';

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.blue),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Container(
            margin: EdgeInsets.only(right: 4),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    setState(() {
                      _weekStart = _weekStart.subtract(Duration(days: 7));
                    });
                    _loadSchedule();
                  },
                  icon: Icon(Icons.chevron_left, color: Colors.blue),
                ),
                Text(
                  _formatWeekRange(_weekStart),
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    setState(() {
                      _weekStart = _weekStart.add(Duration(days: 7));
                    });
                    _loadSchedule();
                  },
                  icon: Icon(Icons.chevron_right, color: Colors.blue),
                ),
              ],
            ),
          ),
          if (_currentTabIndex == 0)
            IconButton(
              icon: Icon(
                _showTableView
                    ? Icons.table_rows_outlined
                    : Icons.view_agenda_outlined,
                color: Colors.blue,
              ),
              onPressed: () {
                setState(() {
                  _showTableView = !_showTableView;
                });
              },
            ),
        ],
        title: Text(
          teacherName,
          style: TextStyle(
            color: Colors.grey.shade900,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildTabToggle(),
          Expanded(
            child: Stack(
              children: [
                _currentTabIndex == 0
                    ? (_showTableView
                          ? _buildTableScheduleView()
                          : _buildScheduleView())
                    : _buildEtutListView(),
                if (_isLoading)
                  Container(
                    color: Colors.white70,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEtutListView() {
    if (_weeklyEtuts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 48, color: Colors.grey.shade400),
            SizedBox(height: 12),
            Text(
              'Bu hafta için etüt bulunamadı',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _weeklyEtuts.length,
      itemBuilder: (context, index) {
        final etut = _weeklyEtuts[index];
        final date = (etut['date'] as Timestamp).toDate();
        final start = (etut['startTime'] as Timestamp).toDate();
        final end = (etut['endTime'] as Timestamp).toDate();
        final topic = etut['topic'] ?? 'Konu Belirtilmemiş';
        final action = (etut['action'] ?? '').toString();
        final duration = end.difference(start).inMinutes;
        final studentNames = List<String>.from(etut['studentNames'] ?? []);
        final attendanceTaken = etut['attendanceTaken'] ?? false;

        return Card(
          margin: EdgeInsets.only(bottom: 8),
          elevation: 0.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.grey.shade200, width: 0.5),
          ),
          child: InkWell(
            onTap: () => _showEtutDetailSheet(etut),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: attendanceTaken
                          ? Colors.green.shade50
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            color: attendanceTaken
                                ? Colors.green.shade700
                                : Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _monthNameTr(
                            date.month,
                          ).substring(0, 3).toUpperCase(),
                          style: TextStyle(
                            color: attendanceTaken
                                ? Colors.green.shade700
                                : Colors.blue.shade700,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          studentNames.isNotEmpty
                              ? studentNames.join(', ')
                              : 'Öğrenci Belirtilmemiş',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2),
                        Text(
                          topic,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (action.isNotEmpty) ...[
                          SizedBox(height: 4),
                          Text(
                            action,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 11,
                              color: Colors.grey,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} ($duration dk)',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                              ),
                            ),
                            Spacer(),
                            Icon(
                              attendanceTaken
                                  ? Icons.check_circle
                                  : Icons.pending,
                              size: 13,
                              color: attendanceTaken
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showEtutDetailSheet(Map<String, dynamic> etut) {
    final List<String> studentIds = List<String>.from(etut['studentIds'] ?? []);
    final List<String> studentNames = List<String>.from(
      etut['studentNames'] ?? [],
    );
    final Map<String, dynamic> attendanceData = etut['attendance'] ?? {};
    final Map<String, bool> localAttendance = {};
    for (var id in studentIds) {
      localAttendance[id] = attendanceData[id] ?? true;
    }

    final TextEditingController notesController = TextEditingController(
      text: etut['teacherNotes'] ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        'Etüt Detayı',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _saveAttendance(
                          etut['id'],
                          localAttendance,
                          notesController.text,
                        );
                      },
                      child: Text(
                        'KAYDET',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bilgi Kartı
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              studentNames.isNotEmpty
                                  ? studentNames.join(', ')
                                  : 'Öğrenci Belirtilmemiş',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              etut['topic'] ?? 'Konu Belirtilmemiş',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue.shade700,
                              ),
                            ),
                            if ((etut['action'] ?? '')
                                .toString()
                                .isNotEmpty) ...[
                              SizedBox(height: 8),
                              Text(
                                etut['action'],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ],
                            SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '${(etut['date'] as Timestamp).toDate().day} ${_monthNameTr((etut['date'] as Timestamp).toDate().month)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                SizedBox(width: 16),
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '${(etut['startTime'] as Timestamp).toDate().hour.toString().padLeft(2, '0')}:${(etut['startTime'] as Timestamp).toDate().minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 24),
                      Text(
                        'Yoklama Listesi',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      if (studentIds.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Text(
                              'Öğrenci bulunamadı',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: NeverScrollableScrollPhysics(),
                          itemCount: studentIds.length,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1),
                          itemBuilder: (context, index) {
                            final sId = studentIds[index];
                            final sName = index < studentNames.length
                                ? studentNames[index]
                                : 'Öğrenci ($sId)';
                            final isPresent = localAttendance[sId] ?? true;

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                sName,
                                style: TextStyle(fontSize: 14),
                              ),
                              trailing: ToggleButtons(
                                isSelected: [isPresent, !isPresent],
                                onPressed: (idx) {
                                  setSheetState(() {
                                    localAttendance[sId] = idx == 0;
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                constraints: BoxConstraints(
                                  minHeight: 32,
                                  minWidth: 50,
                                ),
                                selectedColor: Colors.white,
                                fillColor: isPresent
                                    ? Colors.green
                                    : Colors.red,
                                children: [
                                  Icon(
                                    Icons.check,
                                    color: isPresent
                                        ? Colors.white
                                        : Colors.green,
                                    size: 18,
                                  ),
                                  Icon(
                                    Icons.close,
                                    color: !isPresent
                                        ? Colors.white
                                        : Colors.red,
                                    size: 18,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      SizedBox(height: 24),
                      Text(
                        'Öğretmen Notları / Açıklama',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText:
                              'Etüt ile ilgili notlarınızı buraya yazın...',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                          ),
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
                            borderSide: BorderSide(
                              color: Colors.blue.shade300,
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          contentPadding: EdgeInsets.all(16),
                        ),
                      ),
                      SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveAttendance(
    String etutId,
    Map<String, bool> attendance,
    String teacherNotes,
  ) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('etut_requests')
          .doc(etutId)
          .update({
            'attendance': attendance,
            'attendanceTaken': true,
            'attendanceTakenAt': FieldValue.serverTimestamp(),
            'teacherNotes': teacherNotes,
          });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Etüt detayları kaydedildi.')));
        _loadSchedule();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildScheduleView() {
    if (widget.days.isEmpty) {
      return Center(child: Text('Ders saati tanımlanmamış'));
    }

    final maxHours = widget.dailyLessonCounts.values.isNotEmpty
        ? widget.dailyLessonCounts.values.reduce((a, b) => a > b ? a : b)
        : 8;

    return Column(
      children: [
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
            ),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _horizontalScrollController,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header row
                          Row(
                            children: [
                              Container(
                                width: 80,
                                height: 45,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.blue.shade500,
                                      Colors.blue.shade700,
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'GÜN',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.white,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                              ...List.generate(
                                maxHours,
                                (hourIndex) => Container(
                                  width: 75,
                                  height: 45,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.blue.shade500,
                                        Colors.blue.shade700,
                                      ],
                                    ),
                                    border: Border(
                                      left: BorderSide(
                                        color: Colors.blue.shade400,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${hourIndex + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // Data rows
                          ...List.generate(widget.days.length, (dayIndex) {
                            final day = widget.days[dayIndex];
                            final dayHourCount =
                                widget.dailyLessonCounts[day] ?? maxHours;
                            final isEvenRow = dayIndex % 2 == 0;

                            return Row(
                              children: [
                                // Day label
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isEvenRow
                                          ? [
                                              Colors.blue.shade50,
                                              Colors.blue.shade100,
                                            ]
                                          : [Colors.white, Colors.blue.shade50],
                                    ),
                                    border: Border(
                                      top: BorderSide(
                                        color: Colors.blue.shade100,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      day.length > 3
                                          ? day.substring(0, 3)
                                          : day,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                  ),
                                ),
                                // Hour cells
                                ...List.generate(maxHours, (hourIndex) {
                                  if (hourIndex >= dayHourCount) {
                                    return Container(
                                      width: 75,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        border: Border(
                                          top: BorderSide(
                                            color: Colors.grey.shade200,
                                            width: 1,
                                          ),
                                          left: BorderSide(
                                            color: Colors.grey.shade200,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  final key = '${day}_$hourIndex';
                                  final assignment = _scheduleData[key];

                                  MaterialColor? mCellColor;
                                  if (assignment != null) {
                                    if (assignment['isSubstitute'] == true) {
                                      mCellColor = Colors.orange;
                                    } else if (assignment['isAbsence'] ==
                                        true) {
                                      mCellColor = Colors.grey;
                                    } else {
                                      mCellColor = _getColorFor(
                                        (assignment['className'] ?? '')
                                            .toString()
                                            .trim()
                                            .toUpperCase(),
                                      );
                                    }
                                  }

                                  return InkWell(
                                    onTap: assignment == null
                                        ? null
                                        : () {
                                            final classId =
                                                (assignment['classId'] ?? '')
                                                    .toString();
                                            final lessonId =
                                                (assignment['lessonId'] ?? '')
                                                    .toString();
                                            if (classId.isEmpty ||
                                                lessonId.isEmpty)
                                              return;

                                            final dayIndex = widget.days
                                                .indexOf(day);
                                            final initialDate = dayIndex >= 0
                                                ? _weekStart.add(
                                                    Duration(days: dayIndex),
                                                  )
                                                : null;
                                            final List<int>
                                            availableLessonHours = [];
                                            for (
                                              int i = 0;
                                              i < dayHourCount;
                                              i++
                                            ) {
                                              final checkKey = '${day}_$i';
                                              final a = _scheduleData[checkKey];
                                              final aClassId =
                                                  (a?['classId'] ?? '')
                                                      .toString();
                                              final aLessonId =
                                                  (a?['lessonId'] ?? '')
                                                      .toString();
                                              if (aClassId == classId &&
                                                  aLessonId == lessonId) {
                                                availableLessonHours.add(i + 1);
                                              }
                                            }

                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => ClassLessonHubScreen(
                                                  institutionId:
                                                      (assignment['institutionId'] ??
                                                              '')
                                                          .toString(),
                                                  schoolTypeId:
                                                      (assignment['schoolTypeId'] ??
                                                              '')
                                                          .toString(),
                                                  periodId:
                                                      widget.activePeriodId,
                                                  classId: classId,
                                                  lessonId: lessonId,
                                                  className:
                                                      (assignment['className'] ??
                                                              '')
                                                          .toString(),
                                                  lessonName:
                                                      (assignment['lessonName'] ??
                                                              '')
                                                          .toString(),
                                                  initialDate: initialDate,
                                                  initialLessonHour:
                                                      hourIndex + 1,
                                                  availableLessonHours:
                                                      availableLessonHours,
                                                ),
                                              ),
                                            );
                                          },
                                    child: Container(
                                      width: 75,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        gradient: assignment != null
                                            ? LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  mCellColor!.shade100,
                                                  mCellColor.shade200,
                                                ],
                                              )
                                            : null,
                                        color: assignment == null
                                            ? (isEvenRow
                                                  ? Colors.grey.shade50
                                                  : Colors.white)
                                            : null,
                                        border: Border(
                                          top: BorderSide(
                                            color: assignment != null
                                                ? mCellColor!.shade300
                                                : Colors.grey.shade200,
                                            width: 1,
                                          ),
                                          left: BorderSide(
                                            color: assignment != null
                                                ? mCellColor!.shade300
                                                : Colors.grey.shade200,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: assignment != null
                                          ? Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Expanded(
                                                    child: Center(
                                                      child: Text(
                                                        (assignment['className'] ??
                                                                '')
                                                            .toString(),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: mCellColor!
                                                              .shade900,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  if (assignment['isSubstitute'] ==
                                                      true) ...[
                                                    SizedBox(height: 2),
                                                    Text(
                                                      'Yerine: ${(assignment['originalTeacherName'] ?? '').toString().split(' ').first}',
                                                      style: TextStyle(
                                                        fontSize: 7,
                                                        color:
                                                            mCellColor.shade700,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ] else if ((assignment['lessonName'] ??
                                                          '')
                                                      .toString()
                                                      .isNotEmpty)
                                                    Text(
                                                      (assignment['lessonName'] ??
                                                              '')
                                                          .toString(),
                                                      style: TextStyle(
                                                        fontSize: 8,
                                                        color:
                                                            mCellColor.shade700,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                ],
                                              ),
                                            )
                                          : null,
                                    ),
                                  );
                                }),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableScheduleView() {
    if (widget.days.isEmpty) {
      return Center(child: Text('Ders saati tanımlanmamış'));
    }

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widget.days.map((day) {
            final dayHourCount = widget.dailyLessonCounts[day] ?? 8;
            final dayTimes = widget.dayLessonTimes[day] ?? [];

            return Container(
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            day,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$dayHourCount ders',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...List.generate(dayHourCount, (hourIndex) {
                    final key = '${day}_$hourIndex';
                    final assignment = _scheduleData[key];

                    final timeInfo = hourIndex < dayTimes.length
                        ? dayTimes[hourIndex]
                        : null;
                    final startTime = timeInfo != null
                        ? (timeInfo['startTime'] ?? '').toString()
                        : '';
                    final endTime = timeInfo != null
                        ? (timeInfo['endTime'] ?? '').toString()
                        : '';

                    return InkWell(
                      onTap: assignment == null
                          ? null
                          : () {
                              final classId = (assignment['classId'] ?? '')
                                  .toString();
                              final lessonId = (assignment['lessonId'] ?? '')
                                  .toString();
                              if (classId.isEmpty || lessonId.isEmpty) return;

                              final dayIndex = widget.days.indexOf(day);
                              final initialDate = dayIndex >= 0
                                  ? _weekStart.add(Duration(days: dayIndex))
                                  : null;
                              final List<int> availableLessonHours = [];
                              for (int i = 0; i < dayHourCount; i++) {
                                final checkKey = '${day}_$i';
                                final a = _scheduleData[checkKey];
                                final aClassId = (a?['classId'] ?? '')
                                    .toString();
                                final aLessonId = (a?['lessonId'] ?? '')
                                    .toString();
                                if (aClassId == classId &&
                                    aLessonId == lessonId) {
                                  availableLessonHours.add(i + 1);
                                }
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ClassLessonHubScreen(
                                    institutionId:
                                        (assignment['institutionId'] ?? '')
                                            .toString(),
                                    schoolTypeId:
                                        (assignment['schoolTypeId'] ?? '')
                                            .toString(),
                                    periodId: widget.activePeriodId,
                                    classId: classId,
                                    lessonId: lessonId,
                                    className: (assignment['className'] ?? '')
                                        .toString(),
                                    lessonName: (assignment['lessonName'] ?? '')
                                        .toString(),
                                    initialDate: initialDate,
                                    initialLessonHour: hourIndex + 1,
                                    availableLessonHours: availableLessonHours,
                                  ),
                                ),
                              );
                            },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: hourIndex == dayHourCount - 1
                                  ? Colors.transparent
                                  : Colors.grey.shade200,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 60,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${hourIndex + 1}. Ders',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  if (startTime.isNotEmpty)
                                    Text(
                                      startTime,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  if (endTime.isNotEmpty)
                                    Text(
                                      endTime,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: assignment != null
                                  ? _buildCardItemLogic(assignment)
                                  : Container(
                                      height: 40,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '-',
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCardItemLogic(Map<String, dynamic>? assignment) {
    if (assignment == null) {
      return Container(
        height: 40,
        alignment: Alignment.centerLeft,
        child: Text('-', style: TextStyle(color: Colors.grey.shade400)),
      );
    }

    MaterialColor cellColor;
    if (assignment['isSubstitute'] == true) {
      cellColor = Colors.orange;
    } else if (assignment['isAbsence'] == true) {
      cellColor = Colors.grey;
    } else {
      cellColor = _getColorFor(
        (assignment['className'] ?? '').toString().trim().toUpperCase(),
      );
    }

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cellColor.shade300, cellColor.shade400],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (assignment['isSubstitute'] == true) ...[
                Text(
                  'GÖREVLİ',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  (assignment['className'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          if (assignment['isSubstitute'] == true)
            Text(
              '${(assignment['lessonName'] ?? '')} - ${(assignment['originalTeacherName'] ?? '')}',
              style: TextStyle(fontSize: 11, color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          else if (assignment['isAbsence'] == true)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'İZİNLİ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
                Text(
                  '${(assignment['lessonName'] ?? '')} - ${(assignment['substituteName'] ?? '-')}',
                  style: TextStyle(fontSize: 11, color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            )
          else
            Text(
              (assignment['lessonName'] ?? '').toString(),
              style: TextStyle(fontSize: 11, color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
