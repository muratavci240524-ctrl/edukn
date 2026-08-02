import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'class_lesson_hub_screen.dart';
import '../../services/term_service.dart';
import '../../services/user_permission_service.dart';
import '../../widgets/edukn_logo.dart';

class TeacherScheduleViewScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final bool isTeacherView;
  final String? initialEtutId;
  final DateTime? initialEtutDate;

  const TeacherScheduleViewScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    this.isTeacherView = false,
    this.initialEtutId,
    this.initialEtutDate,
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
  bool _isScheduleLoading = false;
  String? _activePeriodId;
  bool _showTableViewWide = true;
  DateTime _weekStart = DateTime.now();
  int _currentTabIndex = 0; // 0: Program, 1: Etütler
  List<Map<String, dynamic>> _weeklyEtuts = [];
  List<Map<String, dynamic>> _teacherAssignments = [];
  String? _resolvedSchoolTypeName;

  // Öğretmen ders sayıları
  Map<String, int> _teacherLessonCounts = {};
  List<Map<String, dynamic>> _lessonClassMerges = [];

  // Filtre değişkenleri
  String? _selectedBranch;
  Set<String> _availableBranches = {};

  final ScrollController _horizontalScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool _hasAutoOpenedEtut = false;

  String _sortBy = 'name'; // 'name' veya 'branch'

  int compareTurkishStrings(String a, String b) {
    final aLower = a.toLowerCase();
    final bLower = b.toLowerCase();

    final maxLen = aLower.length < bLower.length ? aLower.length : bLower.length;
    for (int i = 0; i < maxLen; i++) {
      final charA = aLower[i];
      final charB = bLower[i];
      if (charA != charB) {
        final indexA = _getTurkishCharOrder(charA);
        final indexB = _getTurkishCharOrder(charB);
        if (indexA != indexB) {
          return indexA.compareTo(indexB);
        }
        return charA.compareTo(charB);
      }
    }
    return aLower.length.compareTo(bLower.length);
  }

  int _getTurkishCharOrder(String char) {
    switch (char) {
      case 'a': return 1;
      case 'b': return 2;
      case 'c': return 3;
      case 'ç': return 4;
      case 'd': return 5;
      case 'e': return 6;
      case 'f': return 7;
      case 'g': return 8;
      case 'ğ': return 9;
      case 'h': return 10;
      case 'ı': return 11;
      case 'i': return 12;
      case 'j': return 13;
      case 'k': return 14;
      case 'l': return 15;
      case 'm': return 16;
      case 'n': return 17;
      case 'o': return 18;
      case 'ö': return 19;
      case 'p': return 20;
      case 'r': return 21;
      case 's': return 22;
      case 'ş': return 23;
      case 't': return 24;
      case 'u': return 25;
      case 'ü': return 26;
      case 'v': return 27;
      case 'y': return 28;
      case 'z': return 29;
      default: return 100 + (char.isNotEmpty ? char.codeUnitAt(0) : 0);
    }
  }

  int compareClassNames(String nameA, String nameB) {
    final reg = RegExp(r'\d+');
    final matchA = reg.firstMatch(nameA);
    final matchB = reg.firstMatch(nameB);

    final int numA = matchA != null ? int.parse(matchA.group(0)!) : 0;
    final int numB = matchB != null ? int.parse(matchB.group(0)!) : 0;

    if (numA != numB) {
      return numA.compareTo(numB);
    }
    return compareTurkishStrings(nameA, nameB);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialEtutDate != null || widget.initialEtutId != null) {
      if (widget.initialEtutDate != null) {
        _weekStart = _startOfWeek(widget.initialEtutDate!);
      } else {
        _weekStart = _startOfWeek(DateTime.now());
      }
      _currentTabIndex = 1; // "Etütler" tab
    } else {
      _weekStart = _startOfWeek(DateTime.now());
    }
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

  Future<void> _loadData({bool reloadSidebar = true}) async {
    if (reloadSidebar) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _isScheduleLoading = true);
    }
    
    if (widget.initialEtutId != null) {
      try {
        final etutDoc = await FirebaseFirestore.instance
            .collection('etut_requests')
            .doc(widget.initialEtutId)
            .get();
        if (etutDoc.exists) {
          final etutData = etutDoc.data();
          if (etutData != null && etutData['date'] != null) {
            final dateVal = etutData['date'];
            DateTime? etutDate;
            if (dateVal is Timestamp) {
              etutDate = dateVal.toDate();
            } else if (dateVal is String) {
              etutDate = DateTime.tryParse(dateVal);
            }
            if (etutDate != null) {
              _weekStart = _startOfWeek(etutDate);
              _currentTabIndex = 1;
            }
          }
        }
      } catch (e) {
        debugPrint('Error fetching initial etut for date routing: $e');
      }
    }

    final instId = widget.institutionId.toUpperCase();
    final schoolTypeId = widget.schoolTypeId;

    String schoolTypeName = widget.schoolTypeName;
    if (schoolTypeName == 'Okul' || schoolTypeName.isEmpty) {
      try {
        final typeDoc = await FirebaseFirestore.instance
            .collection('schoolTypes')
            .doc(schoolTypeId)
            .get();
        if (typeDoc.exists) {
          final data = typeDoc.data();
          schoolTypeName = data?['schoolTypeName'] ?? data?['typeName'] ?? data?['name'] ?? 'Okul';
        }
      } catch (e) {
        debugPrint('Error loading schoolTypeName: $e');
      }
    }
    _resolvedSchoolTypeName = schoolTypeName;

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

      _days = [];
      _dailyLessonCounts = {};
      _dayLessonTimes = {};
      _activePeriodId = null;
      _scheduleData = {};

      if (periodsSnapshot.docs.isNotEmpty) {
        QueryDocumentSnapshot? activePeriodDoc;
        final targetDate = _weekStart;

        for (var doc in periodsSnapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final start = (data['startDate'] as Timestamp?)?.toDate();
          final end = (data['endDate'] as Timestamp?)?.toDate();

          if (start != null && end != null) {
            if (targetDate.isAfter(start.subtract(const Duration(days: 1))) &&
                targetDate.isBefore(end.add(const Duration(days: 1)))) {
              activePeriodDoc = doc;
              break;
            }
          }
        }

        if (activePeriodDoc != null) {
          final periodDoc = activePeriodDoc;
          _activePeriodId = periodDoc.id;
          final periodData = periodDoc.data() as Map<String, dynamic>;
          final mergesRaw = periodData['lessonClassMerges'] as List<dynamic>?;
          _lessonClassMerges = mergesRaw != null
              ? mergesRaw.map((e) => Map<String, dynamic>.from(e)).toList()
              : [];

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
      } else {
          _activePeriodId = null;
          _scheduleData = {};
          _dayLessonTimes = {};
          _days = [];
          _lessonClassMerges = [];
        }
      } else {
        _activePeriodId = null;
        _scheduleData = {};
        _dayLessonTimes = {};
        _days = [];
        _lessonClassMerges = [];
        debugPrint('❌ Aktif veya yayınlanmış dönem bulunamadı. Inst: $instId, Type: $schoolTypeId');
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

      final userData = await UserPermissionService.loadUserData();
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
              return locations.contains((_resolvedSchoolTypeName ?? widget.schoolTypeName).toUpperCase());
            }
            if (workLocation != null && workLocation.toString().isNotEmpty) {
              return workLocation.toString().toUpperCase() == (_resolvedSchoolTypeName ?? widget.schoolTypeName).toUpperCase();
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
        final branchCompare = compareTurkishStrings(
          (a['branch'] ?? '').toString(),
          (b['branch'] ?? '').toString(),
        );
        if (branchCompare != 0) return branchCompare;
        return compareTurkishStrings(
          (a['name'] ?? '').toString(),
          (b['name'] ?? '').toString(),
        );
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

      final Map<String, int> lessonCounts = {};
      if (_activePeriodId != null) {
        final scheduleSnap = await FirebaseFirestore.instance
            .collection('classSchedules')
            .where('periodId', isEqualTo: _activePeriodId)
            .get();

        final Map<String, Set<String>> teacherScheduledSlots = {};

        for (var doc in scheduleSnap.docs) {
          final data = doc.data();
          if (data['isActive'] == false) continue;

          final day = data['day'] as String?;
          final hourIndex = data['hourIndex'];
          if (day == null || hourIndex == null) continue;

          final slotKey = '${day}_$hourIndex';

          final tId = (data['teacherId'] ?? '').toString();
          final tIds = (data['teacherIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

          final Set<String> teachersInSlot = {};
          if (tId.isNotEmpty) {
            teachersInSlot.add(tId);
          }
          for (final id in tIds) {
            if (id.isNotEmpty) {
              teachersInSlot.add(id);
            }
          }

          for (final teacherId in teachersInSlot) {
            teacherScheduledSlots.putIfAbsent(teacherId, () => {}).add(slotKey);
          }
        }

        teacherScheduledSlots.forEach((teacherId, slots) {
          lessonCounts[teacherId] = slots.length;
        });
      }

      setState(() {
        _allTeachers = teachers;
        _availableBranches = branches;
        _teacherLessonCounts = lessonCounts;
        
        final resolvedTeacherId = userData?['id'] ?? userData?['teacherId'] ?? currentUid;
        
        if (_selectedTeacher != null && _selectedTeacher!['id'] != null) {
          _loadTeacherSchedule(_selectedTeacher!['id']);
        } else if (resolvedTeacherId != null && _selectedTeacher == null) {
          try {
            final self = _allTeachers.firstWhere(
              (t) => t['id'] == resolvedTeacherId || t['id'] == currentUid,
              orElse: () => {},
            );
            
            if (self.isNotEmpty) {
              _selectedTeacher = self;
              _loadTeacherSchedule(self['id']);
            } else if (widget.isTeacherView) {
              // Failsafe: Listede bulunmasa bile programını çekmeye çalış
              _selectedTeacher = {'id': resolvedTeacherId, 'name': 'Öğretmen'};
              _loadTeacherSchedule(resolvedTeacherId);
            }
          } catch (_) {
            if (widget.isTeacherView) {
              _selectedTeacher = {'id': resolvedTeacherId, 'name': 'Öğretmen'};
              _loadTeacherSchedule(resolvedTeacherId);
            }
          }
        }

        _isLoading = false;
        _isScheduleLoading = false;
      });
    } catch (e) {
      debugPrint('Veri yükleme hatası: $e');
      setState(() {
        _isLoading = false;
        _isScheduleLoading = false;
      });
    }
  }

  Future<void> _loadTeacherSchedule(String teacherId) async {
    if (_activePeriodId == null) {
      setState(() {
        _scheduleData = {};
        _weeklyEtuts = [];
      });
      debugPrint('⚠️ Aktif dönem ID bulunamadı, ders programı sıfırlandı.');
      return;
    }

    final instId = widget.institutionId.toUpperCase();
    final schoolTypeId = widget.schoolTypeId;

    try {
      debugPrint('🔍 Program Verileri Yükleniyor - Teacher: $teacherId, Inst: $instId, Type: $schoolTypeId');
      
      final instIds = [instId, instId.toLowerCase()].toSet().toList();

      // 1. Önce öğretmenin ders atamalarını tek sorguyla bul
      final assignSnap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', whereIn: instIds)
          .where('schoolTypeId', isEqualTo: schoolTypeId)
          .where('teacherIds', arrayContains: teacherId)
          .get();

      final Map<String, Map<String, dynamic>> assignmentMap = {};
      final Set<String> classIds = {};
      final List<Map<String, dynamic>> teacherAssignments = [];
      final Set<String> seenAssignmentKeys = {};

      for (var doc in assignSnap.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        final cid = (data['classId'] ?? '').toString();
        final lid = (data['lessonId'] ?? '').toString();
        final docIsActive = data['isActive'] ?? true;

        final assignmentKey = '$cid|$lid';

        if (cid.isNotEmpty && lid.isNotEmpty && docIsActive) {
          classIds.add(cid);
          assignmentMap[assignmentKey] = {
            'lessonName': (data['lessonName'] ?? '').toString(),
            'className': (data['className'] ?? '').toString(),
          };
          teacherAssignments.add(data);
        }
      }

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
                .where('classId', whereIn: batch)
                .get(),
          );
        }
      }

      // 2. Doğrudan öğretmen bazlı aramalar (Failsafe)
      scheduleFetches.add(
        FirebaseFirestore.instance
            .collection('classSchedules')
            .where('institutionId', whereIn: instIds)
            .where('teacherIds', arrayContains: teacherId)
            .get(),
      );
      scheduleFetches.add(
        FirebaseFirestore.instance
            .collection('classSchedules')
            .where('institutionId', whereIn: instIds)
            .where('teacherId', isEqualTo: teacherId)
            .get(),
      );

      final classSnapshots = await Future.wait(classFetches);
      final scheduleSnapshots = await Future.wait(scheduleFetches);

      for (final snap in classSnapshots) {
        for (final doc in snap.docs) {
          classNameById[doc.id] = (doc.data()['className'] ?? doc.data()['name'] ?? '').toString();
        }
      }

      final Map<String, Map<String, dynamic>> updatedSchedule = {};
      final Set<String> processedScheduleDocIds = {};

      for (final scheduleSnapshot in scheduleSnapshots) {
        for (var doc in scheduleSnapshot.docs) {
          if (processedScheduleDocIds.contains(doc.id)) continue;
          processedScheduleDocIds.add(doc.id);

          final data = doc.data();
          if (data['isActive'] == false) continue;

          final slotPeriodId = (data['periodId'] ?? '').toString();
          if (_activePeriodId != null &&
              slotPeriodId.isNotEmpty &&
              slotPeriodId != _activePeriodId) {
            continue;
          }

          final cid = (data['classId'] ?? '').toString();
          final lid = (data['lessonId'] ?? '').toString();
          final assignmentKey = '$cid|$lid';
          final hasAssignment = assignmentMap.containsKey(assignmentKey);

          final slotTeacherId = (data['teacherId'] ?? '').toString();
          final lessonTeacherIds = (data['teacherIds'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          if (slotTeacherId.isNotEmpty && !lessonTeacherIds.contains(slotTeacherId)) {
            lessonTeacherIds.add(slotTeacherId);
          }

          // Eğer saat diliminde öğretmen ID(leri) tanımlıysa, hedef öğretmen ID'si bulunmalı!
          if (lessonTeacherIds.isNotEmpty) {
            if (!lessonTeacherIds.contains(teacherId)) continue;
          } else {
            // Eğer saat diliminde öğretmen ID'si hiç yazılmamışsa, atama haritasına bak
            if (!hasAssignment) continue;
          }

          final day = data['day'] as String?;
          final hourIndex = data['hourIndex'] as int?;
          if (day == null || hourIndex == null) continue;

          final key = '${day}_$hourIndex';

          final assignmentInfo = hasAssignment ? assignmentMap[assignmentKey] : null;
          final className = assignmentInfo != null
              ? (classNameById[cid] ?? assignmentInfo['className'])
              : (classNameById[cid] ?? data['className'] ?? 'Sınıf');
          final lessonName = assignmentInfo != null
              ? (assignmentInfo['lessonName'] ?? data['lessonName'])
              : (data['lessonName'] ?? 'Ders');

          final newSlotData = {
            ...data,
            'id': doc.id,
            'className': className,
            'lessonName': lessonName,
          };

          if (updatedSchedule.containsKey(key)) {
            final existing = updatedSchedule[key]!;
            final existingLName = existing['lessonName']?.toString();
            if (existingLName == lessonName) {
              final existingClassNames = existing['classNames'] != null 
                  ? List<String>.from(existing['classNames']) 
                  : [existing['className']?.toString() ?? 'Sınıf'];
              
              final existingClassIds = existing['classIds'] != null 
                  ? List<String>.from(existing['classIds']) 
                  : [existing['classId']?.toString() ?? ''];

              final existingDocIds = existing['scheduleDocIds'] != null 
                  ? List<String>.from(existing['scheduleDocIds']) 
                  : [existing['id']?.toString() ?? ''];

              final existingAssignmentIds = existing['assignmentIds'] != null
                  ? List<String>.from(existing['assignmentIds'])
                  : [existing['assignmentId']?.toString() ?? ''];

              if (!existingClassIds.contains(cid)) {
                existingClassNames.add(className.toString());
                existingClassIds.add(cid);
                existingDocIds.add(doc.id);
                if (data['assignmentId'] != null) {
                  existingAssignmentIds.add(data['assignmentId'].toString());
                }
              }

              existingClassNames.sort((a, b) => compareClassNames(a, b));

              existing['className'] = existingClassNames.join('/');
              existing['classNames'] = existingClassNames;
              existing['classIds'] = existingClassIds;
              existing['scheduleDocIds'] = existingDocIds;
              existing['assignmentIds'] = existingAssignmentIds;
              existing['isCombined'] = true;
            } else {
              updatedSchedule[key] = newSlotData;
            }
          } else {
            updatedSchedule[key] = {
              ...newSlotData,
              'classNames': [className.toString()],
              'classIds': [cid],
              'scheduleDocIds': [doc.id],
              'assignmentIds': data['assignmentId'] != null ? [data['assignmentId'].toString()] : <String>[],
            };
          }
        }
      }

      // Her atama dokümanı için ders programındaki işlenme durumunu hesapla
      final Map<String, int> assignmentPlacedSlotsCount = {};
      final Set<String> assignedDocIdsPlaced = {};

      for (final slot in updatedSchedule.values) {
        final slotLid = (slot['lessonId'] ?? '').toString();

        final List<String> slotClassIds = slot['classIds'] != null
            ? List<String>.from(slot['classIds'])
            : [(slot['classId'] ?? '').toString()];

        final List<String> slotAssignmentIds = slot['assignmentIds'] != null
            ? List<String>.from(slot['assignmentIds'])
            : [(slot['assignmentId'] ?? '').toString()];

        for (final assignmentId in slotAssignmentIds) {
          if (assignmentId.isNotEmpty) {
            assignedDocIdsPlaced.add(assignmentId);
            assignmentPlacedSlotsCount[assignmentId] = (assignmentPlacedSlotsCount[assignmentId] ?? 0) + 1;
          }
        }

        for (final cid in slotClassIds) {
          if (cid.isNotEmpty && slotLid.isNotEmpty) {
            final matchKey = '$cid|$slotLid';
            assignmentPlacedSlotsCount[matchKey] = (assignmentPlacedSlotsCount[matchKey] ?? 0) + 1;
          }
        }
      }

      final Set<String> consumedMatchKeys = {};

      for (var assignment in teacherAssignments) {
        final docId = (assignment['id'] ?? '').toString();
        final cid = (assignment['classId'] ?? '').toString();
        final lid = (assignment['lessonId'] ?? '').toString();
        final matchKey = '$cid|$lid';

        int placed = 0;
        if (assignedDocIdsPlaced.contains(docId)) {
          placed = assignmentPlacedSlotsCount[docId] ?? 0;
        } else if (assignmentPlacedSlotsCount.containsKey(matchKey) && !consumedMatchKeys.contains(matchKey)) {
          placed = assignmentPlacedSlotsCount[matchKey] ?? 0;
          consumedMatchKeys.add(matchKey);
        }

        assignment['placedHours'] = placed;
        assignment['isPlaced'] = placed > 0;
      }

      teacherAssignments.sort((a, b) {
        final classNameA = (a['className'] ?? '').toString();
        final classNameB = (b['className'] ?? '').toString();
        return compareClassNames(classNameA, classNameB);
      });

      setState(() {
        _scheduleData = updatedSchedule;
        _teacherAssignments = teacherAssignments;
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

          final etutSnap = await FirebaseFirestore.instance
              .collection('etut_requests')
              .where('institutionId', whereIn: instIds)
              .where('teacherId', isEqualTo: teacherId)
              .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startMidnight))
              .where('date', isLessThan: Timestamp.fromDate(endMidnight))
              .get();
          
          for (var doc in etutSnap.docs) {
            final data = doc.data();
            final docInstId = (data['institutionId'] ?? '').toString().toUpperCase();
            if (docInstId == instId || docInstId == instId.toLowerCase()) {
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

          // Otomatik Yoklama Açma Mantığı (Bildirimden Yönlendirilince)
          if (widget.initialEtutId != null && !_hasAutoOpenedEtut) {
            try {
              final matchedEtut = _weeklyEtuts.firstWhere(
                (etut) => etut['id'] == widget.initialEtutId,
                orElse: () => {},
              );
              if (matchedEtut.isNotEmpty) {
                _hasAutoOpenedEtut = true;
                Future.microtask(() {
                  _showAttendanceDialog(matchedEtut);
                });
              }
            } catch (e) {
              debugPrint('Otomatik etut yoklamasi acilamadi: $e');
            }
          }
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
          icon: Icon(Icons.arrow_back, color: Colors.blue.shade800),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isTeacherView ? 'Benim Ders Programım' : 'Öğretmen Ders Programı',
              style: TextStyle(
                color: Colors.blue.shade900,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _resolvedSchoolTypeName ?? widget.schoolTypeName,
              style: TextStyle(color: Colors.blue.shade400, fontSize: 12),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: EduKnLoader(size: 80.0))
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
              EduKnLoader(size: 80.0),
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
                  SizedBox(width: 6),
                  PopupMenuButton<String>(
                    onSelected: (val) {
                      setState(() {
                        _sortBy = val;
                      });
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'name',
                        child: Row(
                          children: [
                            Icon(Icons.sort_by_alpha, size: 16, color: _sortBy == 'name' ? Colors.blue : Colors.grey),
                            SizedBox(width: 8),
                            Text('A-Z İsim', style: TextStyle(fontWeight: _sortBy == 'name' ? FontWeight.bold : FontWeight.normal)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'branch',
                        child: Row(
                          children: [
                            Icon(Icons.category_outlined, size: 16, color: _sortBy == 'branch' ? Colors.blue : Colors.grey),
                            SizedBox(width: 8),
                            Text('Branşa Göre', style: TextStyle(fontWeight: _sortBy == 'branch' ? FontWeight.bold : FontWeight.normal)),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.sort,
                            size: 14,
                            color: Colors.white,
                          ),
                          SizedBox(width: 4),
                          Text(
                            _sortBy == 'name' ? 'A-Z' : 'Branş',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
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
                                      institutionId: widget.institutionId,
                                      schoolTypeId: widget.schoolTypeId,
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
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.shade900.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: Colors.blue.shade50),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.calendar_month_outlined,
                size: 48,
                color: Colors.blue.shade400,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Bu Tarihte Ders Programı Bulunmamaktadır',
              style: TextStyle(
                color: Colors.blue.shade900,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Seçilen tarih aktif çalışma dönemi aralığı dışında kaldığı için veya henüz program yayınlanmadığı için gösterilecek ders bulunmuyor.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleView() {
    final maxHours = _dailyLessonCounts.values.isNotEmpty
        ? _dailyLessonCounts.values.reduce((a, b) => a > b ? a : b)
        : 8;

    return Column(
      children: [
        _buildTabToggle(),
        if (_currentTabIndex != 2) _buildDateSelectorRow(),
        Expanded(
          child: _currentTabIndex == 0
              ? (_isScheduleLoading
                  ? const Center(child: EduKnLoader(size: 80.0))
                  : (_activePeriodId == null
                      ? _buildNoPublishedSchedule()
                      : (_days.isEmpty
                          ? Center(child: const Text('Ders saati tanımlanmamış'))
                          : (_showTableViewWide
                              ? _buildTableScheduleWide(maxHours)
                              : _buildCardScheduleWide()))))
              : (_currentTabIndex == 1
                  ? _buildEtutListView()
                  : _buildAssignedLessonsView()),
        ),
      ],
    );
  }

  Widget _buildDateSelectorRow() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade50),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade900.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _weekStart = _weekStart.subtract(Duration(days: 7));
                  });
                  _loadData(reloadSidebar: false);
                },
                icon: Icon(Icons.arrow_back_ios_new, size: 14, color: Colors.blue.shade700),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(32, 32),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedTeacher?['name']?.toString().toUpperCase() ?? 'HAFTALIK PROGRAM',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.blue.shade300,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    _formatWeekRange(_weekStart),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _weekStart = _weekStart.add(Duration(days: 7));
                  });
                  _loadData(reloadSidebar: false);
                },
                icon: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.blue.shade700),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(32, 32),
                ),
              ),
            ],
          ),
          if (_currentTabIndex == 0)
            IconButton(
              icon: Icon(
                _showTableViewWide ? Icons.table_rows_outlined : Icons.view_agenda_outlined,
                color: Colors.blue.shade700,
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  _showTableViewWide = !_showTableViewWide;
                });
              },
              style: IconButton.styleFrom(
                backgroundColor: Colors.blue.shade50,
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(36, 36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ],
      ),
    );
  }

  void _onLessonTap(Map<String, dynamic> assignment, String day, int hourIndex) {
    debugPrint('DEBUG: _onLessonTap called for $day - $hourIndex');
    final classId = (assignment['classId'] ?? '').toString();
    final lessonId = (assignment['lessonId'] ?? '').toString();
    if (classId.isEmpty || lessonId.isEmpty) {
      debugPrint('⚠️ Ders detayı açılamadı: classId veya lessonId eksik.');
      return;
    }

    final dayIndex = _days.indexOf(day);
    final initialDate = dayIndex >= 0
        ? _weekStart.add(Duration(days: dayIndex))
        : null;

    final List<int> availableLessonHours = [];
    final dayHourCount = _dailyLessonCounts[day] ?? 8;
    for (int i = 0; i < dayHourCount; i++) {
        final checkKey = '${day}_$i';
        final a = _scheduleData[checkKey];
        final aClassId = (a?['classId'] ?? '').toString();
        final aLessonId = (a?['lessonId'] ?? '').toString();
        final aClassIds = a?['classIds'] != null ? List<String>.from(a?['classIds']) : [aClassId];
        if (aClassIds.contains(classId) && aLessonId == lessonId) {
            availableLessonHours.add(i + 1);
        }
    }

    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => ClassLessonHubScreen(
                institutionId: (assignment['institutionId'] ?? '').toString(),
                schoolTypeId: (assignment['schoolTypeId'] ?? '').toString(),
                periodId: _activePeriodId,
                classId: classId,
                lessonId: lessonId,
                className: (assignment['className'] ?? '').toString(),
                lessonName: (assignment['lessonName'] ?? '').toString(),
                initialDate: initialDate,
                initialLessonHour: hourIndex + 1,
                availableLessonHours: availableLessonHours,
                combinedClassIds: assignment['classIds'] != null ? List<String>.from(assignment['classIds']) : null,
                combinedClassNames: assignment['classNames'] != null ? List<String>.from(assignment['classNames']) : null,
            ),
        ),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tabButton(0, 'Program', Icons.grid_on),
          _tabButton(1, 'Etütler', Icons.list_alt),
          _tabButton(2, 'Atalı Dersler', Icons.assignment_ind),
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
                        FutureBuilder<String>(
                          future: _resolveEtutTopic(etut),
                          builder: (context, snapshot) {
                            final topicVal = snapshot.data ?? topic;
                            return Text(
                              topicVal,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
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

  Widget _buildAssignedLessonsView() {
    if (_teacherAssignments.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.shade900.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: Colors.blue.shade50),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.assignment_late_outlined,
                  size: 48,
                  color: Colors.blue.shade400,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Atanmış Ders Bulunmuyor',
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Bu öğretmene ait aktif müfredat ders ataması bulunmamaktadır.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final hasUnplacedDuplicates = _teacherAssignments.any((a) => a['isPlaced'] == false);

    return Column(
      children: [
        // Bilgilendirme ve Hızlı Temizleme Çubuğu
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blue.shade50.withOpacity(0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Programda işli olan atamalar yeşil (✓), boşta kalanlar turuncu (⚠️) rozetle gösterilir.',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade900, fontWeight: FontWeight.w500),
                ),
              ),
              if (hasUnplacedDuplicates) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _cleanUpUnplacedDuplicates,
                  icon: const Icon(Icons.cleaning_services, size: 14, color: Colors.white),
                  label: const Text(
                    'Boştakileri Temizle',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: _teacherAssignments.length,
            itemBuilder: (context, index) {
              final assignment = _teacherAssignments[index];
              final className = (assignment['className'] ?? 'Sınıf').toString();
              final lessonName = (assignment['lessonName'] ?? 'Ders').toString();
              final weeklyHours = assignment['weeklyHours'] as int? ?? 0;
              final isPlaced = assignment['isPlaced'] as bool? ?? false;
              final placedHours = assignment['placedHours'] as int? ?? 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isPlaced ? Colors.blue.shade100 : Colors.orange.shade200,
                    width: isPlaced ? 1 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade900.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isPlaced
                              ? [Colors.blue.shade400, Colors.blue.shade700]
                              : [Colors.orange.shade400, Colors.orange.shade700],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(
                          isPlaced ? Icons.class_outlined : Icons.event_busy,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  className,
                                  style: TextStyle(
                                    color: Colors.blue.shade800,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$weeklyHours saat/hafta',
                                  style: TextStyle(
                                    color: Colors.blue.shade900,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // PROGRAMDA İŞLİ Mİ / BOŞTA MI ROZETİ
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isPlaced ? Colors.green.shade50 : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isPlaced ? Colors.green.shade200 : Colors.orange.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isPlaced ? Icons.check_circle : Icons.warning_amber_rounded,
                                      size: 12,
                                      color: isPlaced ? Colors.green.shade700 : Colors.orange.shade900,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isPlaced
                                          ? 'Programda Var ($placedHours Saat)'
                                          : 'Boşta / Programda Yok',
                                      style: TextStyle(
                                        color: isPlaced ? Colors.green.shade800 : Colors.orange.shade900,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            lessonName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _confirmCancelAssignment(assignment),
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      label: const Text(
                        'İptal Et',
                        style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red.shade200),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _cleanUpUnplacedDuplicates() async {
    final unplaced = _teacherAssignments.where((a) => a['isPlaced'] == false).toList();
    if (unplaced.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cleaning_services, color: Colors.orange.shade800, size: 24),
            ),
            const SizedBox(width: 10),
            const Text('Boştaki Atamaları Temizle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Ders programında yer almayan (${unplaced.length} adet) boştaki atamaları topluca pasife almak istediğinize emin misiniz?\n\nProgramda işli olan derslerinize hiçbir zarar gelmeyecektir.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, Temizle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final assignment in unplaced) {
        final docId = (assignment['id'] ?? '').toString();
        if (docId.isNotEmpty) {
          final docRef = FirebaseFirestore.instance.collection('lessonAssignments').doc(docId);
          batch.update(docRef, {'isActive': false});
        }
      }
      await batch.commit();

      setState(() {
        _teacherAssignments.removeWhere((a) => a['isPlaced'] == false);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${unplaced.length} adet boştaki atama başarıyla temizlendi.'),
          backgroundColor: Colors.green,
        ),
      );

      if (_selectedTeacher != null && _selectedTeacher!['id'] != null) {
        await _loadTeacherSchedule(_selectedTeacher!['id']);
      }
      await _loadData(reloadSidebar: false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Temizleme sırasında hata oluştu: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _confirmCancelAssignment(Map<String, dynamic> assignment) {
    final docId = (assignment['id'] ?? '').toString();
    final className = (assignment['className'] ?? 'Sınıf').toString();
    final lessonName = (assignment['lessonName'] ?? 'Ders').toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade600, size: 24),
            ),
            const SizedBox(width: 10),
            const Text('Atamayı İptal Et', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '"$className - $lessonName" ders atamasını bu öğretmen için iptal etmek istediğinize emin misiniz?',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final docSnap = await FirebaseFirestore.instance.collection('lessonAssignments').doc(docId).get();
                if (docSnap.exists) {
                  final data = docSnap.data();
                  final tIds = List<String>.from(data?['teacherIds'] ?? []);
                  final tNames = List<String>.from(data?['teacherNames'] ?? []);
                  
                  if (tIds.length > 1 && _selectedTeacher != null) {
                    tIds.remove(_selectedTeacher!['id']);
                    if (tNames.isNotEmpty && _selectedTeacher!['name'] != null) {
                      tNames.removeWhere((n) => n.contains(_selectedTeacher!['name'].toString()));
                    }
                    await FirebaseFirestore.instance.collection('lessonAssignments').doc(docId).update({
                      'teacherIds': tIds,
                      'teacherNames': tNames,
                    });
                  } else {
                    await FirebaseFirestore.instance.collection('lessonAssignments').doc(docId).update({
                      'isActive': false,
                    });
                  }
                }

                setState(() {
                  _teacherAssignments.removeWhere((a) => a['id'] == docId);
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ders ataması başarıyla iptal edildi.'),
                    backgroundColor: Colors.green,
                  ),
                );

                if (_selectedTeacher != null && _selectedTeacher!['id'] != null) {
                  await _loadTeacherSchedule(_selectedTeacher!['id']);
                }
                await _loadData(reloadSidebar: false);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Atama iptal edilirken hata oluştu: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Evet, İptal Et', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<String> _resolveEtutTopic(Map<String, dynamic> etut) async {
    final String topic = (etut['topic'] ?? '').toString().trim();
    String resolvedTopic = topic;
    if (topic.isEmpty ||
        topic.toLowerCase() == 'belirtilmemis' ||
        topic.toLowerCase() == 'belirtilmemiş' ||
        topic.toLowerCase() == 'konu belirtilmemis' ||
        topic.toLowerCase() == 'konu belirtilmemiş' ||
        topic == '-' ||
        topic == 'null') {
      final campGroupId = etut['campGroupId']?.toString();
      final agmGroupId = etut['agmGroupId']?.toString();
      
      if (campGroupId != null && campGroupId.isNotEmpty) {
        try {
          final groupDoc = await FirebaseFirestore.instance
              .collection('camp_groups')
              .doc(campGroupId)
              .get();
          if (groupDoc.exists) {
            final list = List<dynamic>.from(groupDoc.data()?['kazanimlar'] ?? []);
            if (list.isNotEmpty) {
              return list.join(', ');
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
              return list.join(', ');
            }
          }
        } catch (e) {
          debugPrint('Error fetching agm group kazanimlar: $e');
        }
      }
    }
    return resolvedTopic.isNotEmpty ? resolvedTopic : 'Belirtilmemiş';
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
    final notesController = TextEditingController(
      text: etut['teacherNotes'] ?? '',
    );

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
                // Handle Bar
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
                // Custom Header
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
                              'Etüt Detayı',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                            Text(
                              'Yoklama ve öğretmen notlarını güncelleyin',
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
                        // Info Section
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
                                FutureBuilder<String>(
                                  future: _resolveEtutTopic(etut),
                                  builder: (context, snapshot) {
                                    final topicVal = snapshot.data ?? etut['topic'] ?? 'Yükleniyor...';
                                    return _buildInfoRow(Icons.topic, 'Konu', topicVal);
                                  },
                                ),
                                if ((etut['action'] ?? '').toString().isNotEmpty) ...[
                                  const Divider(height: 24),
                                  _buildInfoRow(Icons.category, 'Kategori', etut['action'], isOrange: true),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Attendance Section Header
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
                          _buildEmptyState('Öğrenci bulunamadı')
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
                                final sName = index < studentNames.length ? studentNames[index] : 'Öğrenci ($sId)';
                                final isPresent = localAttendance[sId] ?? true;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                                  title: Text(sName,
                                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildPresenceButton(
                                        icon: Icons.check_circle_rounded,
                                        label: 'VAR',
                                        isSelected: isPresent,
                                        activeColor: Colors.green,
                                        onTap: () => setDialogState(() => localAttendance[sId] = true),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildPresenceButton(
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
                        // Notes Section Header
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
                        // Add some bottom padding for scroll
                        SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
                      ],
                    ),
                  ),
                ),
                // Sticky Action Buttons
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
                            final notes = notesController.text;
                            Navigator.pop(context);
                            await _saveAttendance(etut['id'], localAttendance, notes);
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

  Widget _buildInfoRow(IconData icon, String label, String value, {bool isOrange = false}) {
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

  Widget _buildPresenceButton({
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

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
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
                                if (assignment != null)
                                  Positioned.fill(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _onLessonTap(assignment, day, hourIndex),
                                      ),
                                    ),
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
                          : () => _onLessonTap(assignment, day, hourIndex),
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

class _TeacherScheduleDetailView extends StatefulWidget {
  final Map<String, dynamic> teacherData;
  final List<String> days;
  final Map<String, int> dailyLessonCounts;
  final Map<String, List<Map<String, dynamic>>> dayLessonTimes;
  final String? activePeriodId;
  final String institutionId;
  final String schoolTypeId;

  const _TeacherScheduleDetailView({
    required this.teacherData,
    required this.days,
    required this.dailyLessonCounts,
    required this.dayLessonTimes,
    this.activePeriodId,
    required this.institutionId,
    required this.schoolTypeId,
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
  int _currentTabIndex = 0; // 0: Program, 1: Etütler, 2: Atalı Dersler
  List<Map<String, dynamic>> _weeklyEtuts = [];
  List<Map<String, dynamic>> _teacherAssignments = [];
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

  int compareTurkishStrings(String a, String b) {
    final aLower = a.toLowerCase();
    final bLower = b.toLowerCase();

    final maxLen = aLower.length < bLower.length ? aLower.length : bLower.length;
    for (int i = 0; i < maxLen; i++) {
      final charA = aLower[i];
      final charB = bLower[i];
      if (charA != charB) {
        final indexA = _getTurkishCharOrder(charA);
        final indexB = _getTurkishCharOrder(charB);
        if (indexA != indexB) {
          return indexA.compareTo(indexB);
        }
        return charA.compareTo(charB);
      }
    }
    return aLower.length.compareTo(bLower.length);
  }

  int _getTurkishCharOrder(String char) {
    switch (char) {
      case 'a': return 1;
      case 'b': return 2;
      case 'c': return 3;
      case 'ç': return 4;
      case 'd': return 5;
      case 'e': return 6;
      case 'f': return 7;
      case 'g': return 8;
      case 'ğ': return 9;
      case 'h': return 10;
      case 'ı': return 11;
      case 'i': return 12;
      case 'j': return 13;
      case 'k': return 14;
      case 'l': return 15;
      case 'm': return 16;
      case 'n': return 17;
      case 'o': return 18;
      case 'ö': return 19;
      case 'p': return 20;
      case 'r': return 21;
      case 's': return 22;
      case 'ş': return 23;
      case 't': return 24;
      case 'u': return 25;
      case 'ü': return 26;
      case 'v': return 27;
      case 'y': return 28;
      case 'z': return 29;
      default: return 100 + (char.isNotEmpty ? char.codeUnitAt(0) : 0);
    }
  }

  int compareClassNames(String nameA, String nameB) {
    final reg = RegExp(r'\d+');
    final matchA = reg.firstMatch(nameA);
    final matchB = reg.firstMatch(nameB);

    final int numA = matchA != null ? int.parse(matchA.group(0)!) : 0;
    final int numB = matchB != null ? int.parse(matchB.group(0)!) : 0;

    if (numA != numB) {
      return numA.compareTo(numB);
    }
    return compareTurkishStrings(nameA, nameB);
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

  void _onLessonTap(Map<String, dynamic> assignment, String day, int hourIndex) {
    debugPrint('DEBUG: _onLessonTap (Detail) called for $day - $hourIndex');
    final classId = (assignment['classId'] ?? '').toString();
    final lessonId = (assignment['lessonId'] ?? '').toString();
    if (classId.isEmpty || lessonId.isEmpty) return;

    final dayIndex = widget.days.indexOf(day);
    final initialDate = dayIndex >= 0
        ? _weekStart.add(Duration(days: dayIndex))
        : null;

    final List<int> availableLessonHours = [];
    final dayHourCount = widget.dailyLessonCounts[day] ?? 8;
    for (int i = 0; i < dayHourCount; i++) {
        final checkKey = '${day}_$i';
        final a = _scheduleData[checkKey];
        final aClassId = (a?['classId'] ?? '').toString();
        final aLessonId = (a?['lessonId'] ?? '').toString();
        final aClassIds = a?['classIds'] != null ? List<String>.from(a?['classIds']) : [aClassId];
        if (aClassIds.contains(classId) && aLessonId == lessonId) {
            availableLessonHours.add(i + 1);
        }
    }

    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => ClassLessonHubScreen(
                institutionId: (assignment['institutionId'] ?? '').toString(),
                schoolTypeId: (assignment['schoolTypeId'] ?? '').toString(),
                periodId: widget.activePeriodId,
                classId: classId,
                lessonId: lessonId,
                className: (assignment['className'] ?? '').toString(),
                lessonName: (assignment['lessonName'] ?? '').toString(),
                initialDate: initialDate,
                initialLessonHour: hourIndex + 1,
                availableLessonHours: availableLessonHours,
                combinedClassIds: assignment['classIds'] != null ? List<String>.from(assignment['classIds']) : null,
                combinedClassNames: assignment['classNames'] != null ? List<String>.from(assignment['classNames']) : null,
            ),
        ),
    );
  }

  Future<void> _loadSchedule() async {
    if (widget.activePeriodId == null) return;
    setState(() => _isLoading = true);

    try {
      final teacherId = (widget.teacherData['id'] ?? '').toString();
      if (teacherId.isEmpty) return;

      final instId = widget.institutionId.toUpperCase();
      final instIds = [instId, instId.toLowerCase()].toSet().toList();

      final assignmentsSnapshot = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', whereIn: instIds)
          .where('isActive', isEqualTo: true)
          .where('teacherIds', arrayContains: teacherId)
          .get();

      final Set<String> classIds = {};
      final Map<String, Map<String, dynamic>> assignmentMap = {};
      final List<Map<String, dynamic>> teacherAssignments = [];
      for (var doc in assignmentsSnapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        final classId = (data['classId'] ?? '').toString();
        final lessonId = (data['lessonId'] ?? '').toString();
        if (classId.isEmpty || lessonId.isEmpty) continue;
        classIds.add(classId);
        assignmentMap['${classId}|${lessonId}'] = {
          'lessonName': (data['lessonName'] ?? '').toString(),
          'className': (data['className'] ?? '').toString(),
        };
        teacherAssignments.add(data);
      }

      if (classIds.isEmpty) {
        setState(() {
          _scheduleData = {};
          _teacherAssignments = [];
          _isLoading = false;
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
              .where('institutionId', whereIn: instIds)
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
          final newSlotData = {
            ...data,
            'id': doc.id,
            'className': assignmentInfo['className'],
            'lessonName': assignmentInfo['lessonName'],
          };

          if (scheduleData.containsKey(key)) {
            final existing = scheduleData[key]!;
            final existingLName = existing['lessonName']?.toString();
            if (existingLName == assignmentInfo['lessonName']) {
              final existingClassNames = existing['classNames'] != null 
                  ? List<String>.from(existing['classNames']) 
                  : [existing['className']?.toString() ?? 'Sınıf'];
              
              final existingClassIds = existing['classIds'] != null 
                  ? List<String>.from(existing['classIds']) 
                  : [existing['classId']?.toString() ?? ''];

              final existingDocIds = existing['scheduleDocIds'] != null 
                  ? List<String>.from(existing['scheduleDocIds']) 
                  : [existing['id']?.toString() ?? ''];

              final existingAssignmentIds = existing['assignmentIds'] != null
                  ? List<String>.from(existing['assignmentIds'])
                  : [existing['assignmentId']?.toString() ?? ''];

              if (!existingClassIds.contains(classId)) {
                existingClassNames.add(assignmentInfo['className'].toString());
                existingClassIds.add(classId);
                existingDocIds.add(doc.id);
                if (data['assignmentId'] != null) {
                  existingAssignmentIds.add(data['assignmentId'].toString());
                }
              }

              existingClassNames.sort((a, b) => compareClassNames(a, b));

              existing['className'] = existingClassNames.join('/');
              existing['classNames'] = existingClassNames;
              existing['classIds'] = existingClassIds;
              existing['scheduleDocIds'] = existingDocIds;
              existing['assignmentIds'] = existingAssignmentIds;
              existing['isCombined'] = true;
            } else {
              scheduleData[key] = newSlotData;
            }
          } else {
            scheduleData[key] = {
              ...newSlotData,
              'classNames': [assignmentInfo['className'].toString()],
              'classIds': [classId],
              'scheduleDocIds': [doc.id],
              'assignmentIds': data['assignmentId'] != null ? [data['assignmentId'].toString()] : <String>[],
            };
          }
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
            .where('institutionId', whereIn: instIds)
            .where('originalTeacherId', isEqualTo: teacherId)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek),
            )
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek))
            .where('status', isEqualTo: 'published')
            .get();

        final substituteSnap = await temporaryRef
            .where('institutionId', whereIn: instIds)
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
        
        // Atalı Derslerin durumunu hesapla
        final Map<String, int> assignmentPlacedSlotsCount = {};
        final Set<String> assignedDocIdsPlaced = {};

        for (final slot in scheduleData.values) {
          final slotLid = (slot['lessonId'] ?? '').toString();

          final List<String> slotClassIds = slot['classIds'] != null
              ? List<String>.from(slot['classIds'])
              : [(slot['classId'] ?? '').toString()];

          final List<String> slotAssignmentIds = slot['assignmentIds'] != null
              ? List<String>.from(slot['assignmentIds'])
              : [(slot['assignmentId'] ?? '').toString()];

          for (final assignmentId in slotAssignmentIds) {
            if (assignmentId.isNotEmpty) {
              assignedDocIdsPlaced.add(assignmentId);
              assignmentPlacedSlotsCount[assignmentId] = (assignmentPlacedSlotsCount[assignmentId] ?? 0) + 1;
            }
          }

          for (final cid in slotClassIds) {
            if (cid.isNotEmpty && slotLid.isNotEmpty) {
              final matchKey = '$cid|$slotLid';
              assignmentPlacedSlotsCount[matchKey] = (assignmentPlacedSlotsCount[matchKey] ?? 0) + 1;
            }
          }
        }

        final Set<String> consumedMatchKeys = {};

        for (var assignment in teacherAssignments) {
          final docId = (assignment['id'] ?? '').toString();
          final cid = (assignment['classId'] ?? '').toString();
          final lid = (assignment['lessonId'] ?? '').toString();
          final matchKey = '$cid|$lid';

          int placed = 0;
          if (assignedDocIdsPlaced.contains(docId)) {
            placed = assignmentPlacedSlotsCount[docId] ?? 0;
          } else if (assignmentPlacedSlotsCount.containsKey(matchKey) && !consumedMatchKeys.contains(matchKey)) {
            placed = assignmentPlacedSlotsCount[matchKey] ?? 0;
            consumedMatchKeys.add(matchKey);
          }

          assignment['placedHours'] = placed;
          assignment['isPlaced'] = placed > 0;
        }

        teacherAssignments.sort((a, b) {
          final classNameA = (a['className'] ?? '').toString();
          final classNameB = (b['className'] ?? '').toString();
          return compareClassNames(classNameA, classNameB);
        });

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
              .where('institutionId', whereIn: instIds)
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
          _teacherAssignments = teacherAssignments;
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

  void _confirmCancelAssignment(Map<String, dynamic> assignment) {
    final docId = (assignment['id'] ?? '').toString();
    final className = (assignment['className'] ?? 'Sınıf').toString();
    final lessonName = (assignment['lessonName'] ?? 'Ders').toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade600, size: 24),
            ),
            const SizedBox(width: 10),
            const Text('Atamayı İptal Et', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '"$className - $lessonName" ders atamasını bu öğretmen için iptal etmek istediğinize emin misiniz?',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final docSnap = await FirebaseFirestore.instance.collection('lessonAssignments').doc(docId).get();
                final teacherId = widget.teacherData['id']?.toString() ?? '';
                final teacherName = widget.teacherData['name']?.toString() ?? '';
                if (docSnap.exists) {
                  final data = docSnap.data();
                  final tIds = List<String>.from(data?['teacherIds'] ?? []);
                  final tNames = List<String>.from(data?['teacherNames'] ?? []);
                  
                  if (tIds.length > 1 && teacherId.isNotEmpty) {
                    tIds.remove(teacherId);
                    if (tNames.isNotEmpty && teacherName.isNotEmpty) {
                      tNames.removeWhere((n) => n.contains(teacherName));
                    }
                    await FirebaseFirestore.instance.collection('lessonAssignments').doc(docId).update({
                      'teacherIds': tIds,
                      'teacherNames': tNames,
                    });
                  } else {
                    await FirebaseFirestore.instance.collection('lessonAssignments').doc(docId).update({
                      'isActive': false,
                    });
                  }
                }

                setState(() {
                  _teacherAssignments.removeWhere((a) => a['id'] == docId);
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ders ataması başarıyla iptal edildi.'),
                    backgroundColor: Colors.green,
                  ),
                );

                await _loadSchedule();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Atama iptal edilirken hata oluştu: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Evet, İptal Et', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _cleanUpUnplacedDuplicates() async {
    final unplaced = _teacherAssignments.where((a) => a['isPlaced'] == false).toList();
    if (unplaced.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cleaning_services, color: Colors.orange.shade700, size: 24),
            ),
            const SizedBox(width: 10),
            const Text('Boştakileri Temizle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Bu öğretmene atanmış ancak programda yer almayan (${unplaced.length} adet) ders atamasını silmek istiyor musunuz?',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Temizle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final teacherId = widget.teacherData['id']?.toString() ?? '';
      final teacherName = widget.teacherData['name']?.toString() ?? '';
      for (final a in unplaced) {
        final docId = a['id']?.toString() ?? '';
        if (docId.isEmpty) continue;

        final tIds = List<String>.from(a['teacherIds'] ?? []);
        final tNames = List<String>.from(a['teacherNames'] ?? []);

        if (tIds.length > 1 && teacherId.isNotEmpty) {
          tIds.remove(teacherId);
          if (tNames.isNotEmpty && teacherName.isNotEmpty) {
            tNames.removeWhere((n) => n.contains(teacherName));
          }
          await FirebaseFirestore.instance.collection('lessonAssignments').doc(docId).update({
            'teacherIds': tIds,
            'teacherNames': tNames,
          });
        } else {
          await FirebaseFirestore.instance.collection('lessonAssignments').doc(docId).update({
            'isActive': false,
          });
        }
      }

      setState(() {
        _teacherAssignments.removeWhere((a) => a['isPlaced'] == false);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Boştaki ders atamaları başarıyla temizlendi.'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadSchedule();
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Temizleme sırasında hata oluştu: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildAssignedLessonsView() {
    if (_teacherAssignments.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.shade900.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: Colors.blue.shade50),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.assignment_late_outlined,
                  size: 48,
                  color: Colors.blue.shade400,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Atanmış Ders Bulunmuyor',
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Bu öğretmene ait aktif müfredat ders ataması bulunmamaktadır.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final hasUnplacedDuplicates = _teacherAssignments.any((a) => a['isPlaced'] == false);

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blue.shade50.withOpacity(0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Programda işli olan atamalar yeşil (✓), boşta kalanlar turuncu (⚠️) rozetle gösterilir.',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade900, fontWeight: FontWeight.w500),
                ),
              ),
              if (hasUnplacedDuplicates) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _cleanUpUnplacedDuplicates,
                  icon: const Icon(Icons.cleaning_services, size: 14, color: Colors.white),
                  label: const Text(
                    'Temizle',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: _teacherAssignments.length,
            itemBuilder: (context, index) {
              final assignment = _teacherAssignments[index];
              final className = (assignment['className'] ?? 'Sınıf').toString();
              final lessonName = (assignment['lessonName'] ?? 'Ders').toString();
              final weeklyHours = assignment['weeklyHours'] as int? ?? 0;
              final isPlaced = assignment['isPlaced'] as bool? ?? false;
              final placedHours = assignment['placedHours'] as int? ?? 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isPlaced ? Colors.blue.shade100 : Colors.orange.shade200,
                    width: isPlaced ? 1 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade900.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isPlaced
                              ? [Colors.blue.shade400, Colors.blue.shade700]
                              : [Colors.orange.shade400, Colors.orange.shade700],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(
                          isPlaced ? Icons.class_outlined : Icons.event_busy,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  className,
                                  style: TextStyle(
                                    color: Colors.blue.shade800,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$weeklyHours saat/h',
                                  style: TextStyle(
                                    color: Colors.blue.shade900,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isPlaced ? Colors.green.shade50 : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isPlaced ? Colors.green.shade200 : Colors.orange.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isPlaced ? Icons.check_circle : Icons.warning_amber_rounded,
                                      size: 12,
                                      color: isPlaced ? Colors.green.shade700 : Colors.orange.shade900,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isPlaced
                                          ? 'İşli ($placedHours s)'
                                          : 'Boşta',
                                      style: TextStyle(
                                        color: isPlaced ? Colors.green.shade800 : Colors.orange.shade900,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            lessonName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmCancelAssignment(assignment),
                    ),
                  ],
                ),
              );
            },
          ),
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
          _tabButton(2, 'Atalı Dersler', Icons.assignment_ind),
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
          icon: Icon(Icons.arrow_back, color: Colors.blue.shade800),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_currentTabIndex == 0)
            IconButton(
              icon: Icon(
                _showTableView
                    ? Icons.table_rows_outlined
                    : Icons.view_agenda_outlined,
                color: Colors.blue.shade800,
              ),
              onPressed: () {
                setState(() {
                  _showTableView = !_showTableView;
                });
              },
            ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              teacherName,
              style: TextStyle(
                color: Colors.blue.shade900,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Öğretmen Ders Programı',
              style: TextStyle(
                color: Colors.blue.shade400,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildTabToggle(),
          if (_currentTabIndex != 2) _buildDateSelectorRow(),
          Expanded(
            child: Stack(
              children: [
                _currentTabIndex == 0
                    ? (_showTableView
                          ? _buildTableScheduleView()
                          : _buildScheduleView())
                    : _currentTabIndex == 1
                        ? _buildEtutListView()
                        : _buildAssignedLessonsView(),
                if (_isLoading)
                  Container(
                    color: Colors.white70,
                    child: const Center(child: EduKnLoader(size: 80.0)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelectorRow() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade50),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade900.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _weekStart = _weekStart.subtract(Duration(days: 7));
              });
              _loadSchedule();
            },
            icon: Icon(Icons.arrow_back_ios_new, size: 14, color: Colors.blue.shade700),
            style: IconButton.styleFrom(
              backgroundColor: Colors.blue.shade50,
              padding: const EdgeInsets.all(8),
              minimumSize: const Size(32, 32),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _currentTabIndex == 0 ? 'HAFTALIK PROGRAM' : 'HAFTALIK ETÜTLER',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.blue.shade300,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                _formatWeekRange(_weekStart),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _weekStart = _weekStart.add(Duration(days: 7));
              });
              _loadSchedule();
            },
            icon: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.blue.shade700),
            style: IconButton.styleFrom(
              backgroundColor: Colors.blue.shade50,
              padding: const EdgeInsets.all(8),
              minimumSize: const Size(32, 32),
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
                        FutureBuilder<String>(
                          future: _resolveEtutTopic(etut),
                          builder: (context, snapshot) {
                            final topicVal = snapshot.data ?? topic;
                            return Text(
                              topicVal,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
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

  Future<String> _resolveEtutTopic(Map<String, dynamic> etut) async {
    final String topic = (etut['topic'] ?? '').toString().trim();
    String resolvedTopic = topic;
    if (topic.isEmpty ||
        topic.toLowerCase() == 'belirtilmemis' ||
        topic.toLowerCase() == 'belirtilmemiş' ||
        topic.toLowerCase() == 'konu belirtilmemis' ||
        topic.toLowerCase() == 'konu belirtilmemiş' ||
        topic == '-' ||
        topic == 'null') {
      final campGroupId = etut['campGroupId']?.toString();
      final agmGroupId = etut['agmGroupId']?.toString();
      
      if (campGroupId != null && campGroupId.isNotEmpty) {
        try {
          final groupDoc = await FirebaseFirestore.instance
              .collection('camp_groups')
              .doc(campGroupId)
              .get();
          if (groupDoc.exists) {
            final list = List<dynamic>.from(groupDoc.data()?['kazanimlar'] ?? []);
            if (list.isNotEmpty) {
              return list.join(', ');
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
              return list.join(', ');
            }
          }
        } catch (e) {
          debugPrint('Error fetching agm group kazanimlar: $e');
        }
      }
    }
    return resolvedTopic.isNotEmpty ? resolvedTopic : 'Belirtilmemiş';
  }

  void _showEtutDetailSheet(Map<String, dynamic> etut) {
    _showAttendanceDialog(etut);
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
    final notesController = TextEditingController(
      text: etut['teacherNotes'] ?? '',
    );

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
                // Handle Bar
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
                // Custom Header
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
                              'Etüt Detayı',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                            Text(
                              'Yoklama ve öğretmen notlarını güncelleyin',
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
                        // Info Section
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
                                FutureBuilder<String>(
                                  future: _resolveEtutTopic(etut),
                                  builder: (context, snapshot) {
                                    final topicVal = snapshot.data ?? etut['topic'] ?? 'Yükleniyor...';
                                    return _buildInfoRow(Icons.topic, 'Konu', topicVal);
                                  },
                                ),
                                if ((etut['action'] ?? '').toString().isNotEmpty) ...[
                                  const Divider(height: 24),
                                  _buildInfoRow(Icons.category, 'Kategori', etut['action'], isOrange: true),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Attendance Section Header
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
                          _buildEmptyState('Öğrenci bulunamadı')
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
                                final sName = index < studentNames.length ? studentNames[index] : 'Öğrenci ($sId)';
                                final isPresent = localAttendance[sId] ?? true;

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                                  title: Text(sName,
                                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildPresenceButton(
                                        icon: Icons.check_circle_rounded,
                                        label: 'VAR',
                                        isSelected: isPresent,
                                        activeColor: Colors.green,
                                        onTap: () => setDialogState(() => localAttendance[sId] = true),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildPresenceButton(
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
                        // Notes Section Header
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
                        // Add some bottom padding for scroll
                        SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
                      ],
                    ),
                  ),
                ),
                // Sticky Action Buttons
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
                            final notes = notesController.text;
                            Navigator.pop(context);
                            await _saveAttendance(etut['id'], localAttendance, notes);
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

  Widget _buildInfoRow(IconData icon, String label, String value, {bool isOrange = false}) {
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

  Widget _buildPresenceButton({
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

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
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
                                        : () => _onLessonTap(assignment, day, hourIndex),
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
                          : () => _onLessonTap(assignment, day, hourIndex),
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
