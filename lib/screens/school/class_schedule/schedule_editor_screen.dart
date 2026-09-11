import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../services/term_service.dart';
import '../../../services/class_schedule_sync_service.dart';
import '../../../services/auto_schedule_service.dart';
import '../../../widgets/edukn_logo.dart';
import '../schedule_settings_panel.dart';
import '../../../services/pdf_service.dart';
import '../../../services/excel_service.dart';

// ==================== PROGRAM DİZENLEME EKRANI ====================
class ScheduleEditorScreen extends StatefulWidget {
  final String periodId;
  final Map<String, dynamic> periodData;
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final bool isViewingPastTerm;
  final VoidCallback onBack;

  const ScheduleEditorScreen({
    required this.periodId,
    required this.periodData,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    required this.isViewingPastTerm,
    required this.onBack,
  });

  @override
  State<ScheduleEditorScreen> createState() => _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState extends State<ScheduleEditorScreen> {
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _allClasses = []; // Filtrelenmemiş tüm sınıflar
  List<Map<String, dynamic>> _lessonHours = [];
  Map<String, List<Map<String, dynamic>>> _dayLessonTimes =
      {}; // Günlere gİre ders saatleri
  Map<String, Map<String, dynamic>> _scheduleData =
      {}; // key: "classId_day_hour"
  Map<String, List<Map<String, dynamic>>> _classLessons =
      {}; // Şubeye atanmış dersler
  Map<String, int> _remainingHours = {}; // Kalan ders saatleri
  Map<String, int> _dailyLessonCounts = {}; // Her gün iğin ders sayısı
  Map<String, String> _lessonShortNames = {}; // lessonId -> shortName
  bool _isLoading = true;
  bool _isDistributing = false;

  // Daşıtım Ayarları (Kalıcı Firestore kaydedilen)
  Map<String, List<int>> _lessonBlockPatterns = {};
  Map<String, bool> _lessonAllowSplit = {};
  Map<String, bool> _lessonAvoidFirstHour = {};
  Map<String, bool> _lessonAvoidLastHour = {};
  List<Map<String, dynamic>> _lessonClassMerges = [];
  Map<String, Set<String>> _closedSlots = {};
  Map<String, int> _teacherMaxDailyHours = {};
  Set<String> _lockedSlots =
      {}; // Kilitli ders slotlari: 'classId_day_hourIndex'
  // Yarim Gun Ayarlari
  List<int> _halfDayMorningHours = [];
  List<int> _halfDayAfternoonHours = [];
  Set<String> _halfDayFlexible = {};
  Map<String, String> _halfDayAssignedDays = {};
  String?
  _cachedTermId; // Cache'lenmiş termId ÔÇö her seferinde Firestore'dan ğekmemek iğin

  // Görünüm Modu ve Yerleşemeyen Ders Seçimi State
  List<Map<String, dynamic>> _teachers = [];
  bool _isTeacherView = false;
  bool _isSchedulePublished = false;
  bool _isFitToScreen = false; // Web'de ekrana sığdırma modu
  Map<String, dynamic>? _selectedUnassignedLesson;
  String?
  _unassignedFilterId; // Yerleşemeyen ders filtresi: classId veya teacherId
  bool _hasAutoDistributed = false; // Otomatik daşıtım yapıldı mı?
  Map<String, dynamic>?
  _selectedEmptySlot; // Boş slot seğimi: {classId, day, hourIndex}

  // Filtre deşişkenleri
  int? _selectedClassLevel;
  String? _selectedClassType;
  Set<int> _availableClassLevels = {};
  Set<String> _availableClassTypes = {};

  List<String> _days = ['Pazartesi', 'Salı', 'çarşamba', 'Perşembe', 'Cuma'];
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final firestore = FirebaseFirestore.instance;

      // ÔöÇÔöÇ ADIM 1: workPeriods dokümanını TEK KERE oku (ayarlar + ders saatleri birlikte) ÔöÇÔöÇ
      final periodDocFuture = firestore
          .collection('workPeriods')
          .doc(widget.periodId)
          .get();

      // ÔöÇÔöÇ ADIM 2: classes, lessons, schedule, assignments PARALEL ğek ÔöÇÔöÇ
      final classesFuture = firestore
          .collection('classes')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('termId', isEqualTo: widget.periodData['termId'])
          .where('isActive', isEqualTo: true)
          .get();

      final lessonsFuture = firestore
          .collection('lessons')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('termId', isEqualTo: widget.periodData['termId'])
          .get();

      final scheduleFuture = firestore
          .collection('classSchedules')
          .where('periodId', isEqualTo: widget.periodId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      // TİM ders atamalarını tek query ile ğek (şube bazlı dİngü yerine)
      final assignmentsFuture = firestore
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      // TermId'yi de cache'le
      final termIdFuture = TermService().getSelectedTermId();
      final activeTermIdFuture = TermService().getActiveTermId();

      // Aktif öğretmenleri users koleksiyonundan çek
      final usersFuture = firestore
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('type', isEqualTo: 'staff')
          .where('isActive', isEqualTo: true)
          .get();

      final usersLowerFuture = firestore
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId.toLowerCase())
          .where('type', isEqualTo: 'staff')
          .where('isActive', isEqualTo: true)
          .get();

      // PARALEL BEKLE
      final results = await Future.wait<dynamic>([
        periodDocFuture, // 0
        classesFuture, // 1
        lessonsFuture, // 2
        scheduleFuture, // 3
        assignmentsFuture, // 4
        termIdFuture, // 5
        activeTermIdFuture, // 6
        usersFuture, // 7
        usersLowerFuture, // 8
      ]);

      final periodDoc = results[0] as DocumentSnapshot;
      final classesSnapshot = results[1] as QuerySnapshot;
      final lessonsSnapshot = results[2] as QuerySnapshot;
      final scheduleSnapshot = results[3] as QuerySnapshot;
      final assignmentsSnapshot = results[4] as QuerySnapshot;
      final selectedTermId = results[5] as String?;
      final activeTermId = results[6] as String?;
      final usersSnapshot = results[7] as QuerySnapshot;
      final usersLowerSnapshot = results[8] as QuerySnapshot;

      // TermId cache
      _cachedTermId = selectedTermId ?? activeTermId;

      // ÔöÇÔöÇ Daşıtım Ayarlarını Parse Et (periodDoc'tan) ÔöÇÔöÇ
      try {
        if (periodDoc.exists &&
            (periodDoc.data() as Map<String, dynamic>?)?.containsKey(
                  'scheduleSettings',
                ) ==
                true) {
          final settings =
              (periodDoc.data() as Map<String, dynamic>)['scheduleSettings']
                  as Map<String, dynamic>;
          _lessonBlockPatterns =
              (settings['lessonBlockPatterns'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, List<int>.from(v)),
              ) ??
              {};
          _lessonAllowSplit =
              (settings['lessonAllowSplit'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, v as bool),
              ) ??
              {};
          _lessonAvoidFirstHour =
              (settings['lessonAvoidFirstHour'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, v as bool),
              ) ??
              {};
          _lessonAvoidLastHour =
              (settings['lessonAvoidLastHour'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, v as bool),
              ) ??
              {};
          _lessonClassMerges =
              (settings['lessonClassMerges'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [];
          _closedSlots =
              (settings['closedSlots'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, Set<String>.from(v as List)),
              ) ??
              {};
          _teacherMaxDailyHours =
              (settings['teacherMaxDailyHours'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, (v as num).toInt()),
              ) ??
              {};
          _lockedSlots =
              (settings['lockedSlots'] as List?)
                  ?.map((e) => e.toString())
                  .toSet() ??
              {};
          // ── Yarım Gün Ayarları (hot-restart sonrası kaybolmaması için) ──
          _halfDayMorningHours =
              (settings['halfDayMorningHours'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toList() ??
              [];
          _halfDayAfternoonHours =
              (settings['halfDayAfternoonHours'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toList() ??
              [];
          _halfDayFlexible =
              (settings['halfDayFlexible'] as List?)
                  ?.map((e) => e.toString())
                  .toSet() ??
              {};
          _halfDayAssignedDays =
              (settings['halfDayAssignedDays'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, v.toString()),
              ) ??
              {};
        }
      } catch (e) {
        print('Dağıtım ayarları yüklenemedi: $e');
      }

      // Ders Short Names
      final Map<String, String> lessonShortNames = {};
      for (var doc in lessonsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        lessonShortNames[doc.id] = data['shortName'] ?? '';
      }

      // ÔöÇÔöÇ Classes ÔöÇÔöÇ
      final classes = classesSnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();

      classes.sort((a, b) {
        final levelA = (a['classLevel'] ?? 0) is int
            ? a['classLevel']
            : int.tryParse(a['classLevel'].toString()) ?? 0;
        final levelB = (b['classLevel'] ?? 0) is int
            ? b['classLevel']
            : int.tryParse(b['classLevel'].toString()) ?? 0;
        final levelCompare = levelA.compareTo(levelB);
        if (levelCompare != 0) return levelCompare;
        return (a['className'] ?? '').toString().compareTo(
          (b['className'] ?? '').toString(),
        );
      });

      // ÔöÇÔöÇ Ders Saatlerini Parse Et (periodDoc'tan ÔÇö aynı doküman) ÔöÇÔöÇ
      List<Map<String, dynamic>> hours = [];
      List<String> selectedDays = [];
      Map<String, dynamic> dailyCounts = {};
      try {
        if (periodDoc.exists) {
          final periodData = periodDoc.data() as Map<String, dynamic>;

          final lessonHoursData =
              periodData['lessonHours'] as Map<String, dynamic>?;

          if (lessonHoursData != null) {
            selectedDays = List<String>.from(
              lessonHoursData['selectedDays'] ?? [],
            );

            if (lessonHoursData['dailyLessonCounts'] != null) {
              dailyCounts = Map<String, dynamic>.from(
                lessonHoursData['dailyLessonCounts'],
              );
            }

            final lessonTimesRaw = lessonHoursData['lessonTimes'];

            Map<String, List<Map<String, dynamic>>> dayTimes = {};

            if (lessonTimesRaw != null) {
              if (lessonTimesRaw is Map) {
                final lessonTimesMap = Map<String, dynamic>.from(
                  lessonTimesRaw,
                );

                final firstKey = lessonTimesMap.keys.first;
                final isNumericKey = int.tryParse(firstKey) != null;

                if (isNumericKey) {
                  final sortedKeys = lessonTimesMap.keys.toList()
                    ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

                  hours = sortedKeys.map((key) {
                    final time = Map<String, dynamic>.from(lessonTimesMap[key]);
                    final startHour = time['startHour'] ?? 0;
                    final startMinute = time['startMinute'] ?? 0;
                    final endHour = time['endHour'] ?? 0;
                    final endMinute = time['endMinute'] ?? 0;
                    return {
                      'hourNumber': int.parse(key) + 1,
                      'startTime':
                          '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}',
                      'endTime':
                          '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}',
                    };
                  }).toList();

                  for (var day in selectedDays) {
                    dayTimes[day] = List.from(hours);
                  }
                } else {
                  for (var day in selectedDays) {
                    final dayData = lessonTimesMap[day];
                    if (dayData != null && dayData is List) {
                      dayTimes[day] = dayData.asMap().entries.map((entry) {
                        final time = Map<String, dynamic>.from(entry.value);
                        final startHour = time['startHour'] ?? 0;
                        final startMinute = time['startMinute'] ?? 0;
                        final endHour = time['endHour'] ?? 0;
                        final endMinute = time['endMinute'] ?? 0;
                        return {
                          'hourNumber': entry.key + 1,
                          'startTime':
                              '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}',
                          'endTime':
                              '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}',
                        };
                      }).toList();
                    } else {
                      final dayCount = dailyCounts[day] is int
                          ? dailyCounts[day]
                          : int.tryParse(dailyCounts[day]?.toString() ?? '8') ??
                                8;
                      dayTimes[day] = List.generate(
                        dayCount,
                        (i) => {
                          'hourNumber': i + 1,
                          'startTime':
                              '${(9 + i).toString().padLeft(2, '0')}:00',
                          'endTime': '${(9 + i).toString().padLeft(2, '0')}:40',
                        },
                      );
                    }
                  }
                  if (dayTimes.isNotEmpty) {
                    hours = dayTimes.values.reduce(
                      (a, b) => a.length > b.length ? a : b,
                    );
                  }
                }
              } else if (lessonTimesRaw is List) {
                hours = lessonTimesRaw.asMap().entries.map((entry) {
                  final time = Map<String, dynamic>.from(entry.value);
                  final startHour = time['startHour'] ?? 0;
                  final startMinute = time['startMinute'] ?? 0;
                  final endHour = time['endHour'] ?? 0;
                  final endMinute = time['endMinute'] ?? 0;
                  return {
                    'hourNumber': entry.key + 1,
                    'startTime':
                        '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}',
                    'endTime':
                        '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}',
                  };
                }).toList();

                for (var day in selectedDays) {
                  dayTimes[day] = List.from(hours);
                }
              }
            }

            _dayLessonTimes = dayTimes;
          }
        }
      } catch (e) {
        print('Ders saatleri yüklenemedi: $e');
      }

      // ── Aktif Öğretmen Haritası (Canlı users Koleksiyonundan) ──
      final Set<String> seenUserDocIds = {};
      final Map<String, Map<String, dynamic>> activeTeachersById = {};
      final Map<String, String> activeTeacherIdByName = {};

      final allUserDocs = [...usersSnapshot.docs, ...usersLowerSnapshot.docs];
      for (var doc in allUserDocs) {
        if (!seenUserDocIds.add(doc.id)) continue;
        final data = doc.data() as Map<String, dynamic>;
        final title = (data['title'] ?? '').toString().toLowerCase();
        final role = (data['role'] ?? '').toString().toLowerCase();
        final isTeacher = data['type'] == 'staff' ||
            title == 'ogretmen' ||
            title == 'teacher' ||
            title == 'öğretmen' ||
            role == 'teacher';
        if (!isTeacher) continue;

        final fullName = (data['fullName'] ?? '').toString().trim();
        final firstName = (data['firstName'] ?? '').toString().trim();
        final lastName = (data['lastName'] ?? '').toString().trim();
        final name = fullName.isNotEmpty
            ? fullName
            : '$firstName $lastName'.trim();
        if (name.isEmpty) continue;

        activeTeachersById[doc.id] = {
          'id': doc.id,
          'name': name,
          'firstName': firstName,
          'lastName': lastName,
          'branch': (data['branch'] ?? '').toString(),
        };
        final normName = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        activeTeacherIdByName[normName] = doc.id;
      }

      // Ders Atamaları - TEK QUERY sonucunu classId'ye göre grupla
      final Map<String, List<Map<String, dynamic>>> classLessons = {};
      final Map<String, int> remainingHours = {};
      final classIdSet = classes.map((c) => c['id'] as String).toSet();

      for (var doc in assignmentsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        final classId = data['classId']?.toString();
        if (classId != null && classIdSet.contains(classId)) {
          // Eski/silinmiş öğretmen referansını aktif öğretmenle eşle (örn. silinip tekrar açılan Fatih Bay)
          final rawTIds = (data['teacherIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
          final rawTNames = (data['teacherNames'] as List?)?.map((e) => e.toString()).toList() ?? [];
          final singleTId = data['teacherId']?.toString();
          final singleTName = data['teacherName']?.toString();

          final List<String> resolvedTIds = [];
          final List<String> resolvedTNames = [];

          if (rawTIds.isNotEmpty) {
            for (int i = 0; i < rawTIds.length; i++) {
              final tId = rawTIds[i];
              final tName = i < rawTNames.length ? rawTNames[i] : '';
              if (activeTeachersById.containsKey(tId)) {
                resolvedTIds.add(tId);
                resolvedTNames.add(activeTeachersById[tId]!['name'] as String);
              } else {
                final normTName = tName.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
                if (normTName.isNotEmpty && activeTeacherIdByName.containsKey(normTName)) {
                  final newId = activeTeacherIdByName[normTName]!;
                  if (!resolvedTIds.contains(newId)) {
                    resolvedTIds.add(newId);
                    resolvedTNames.add(activeTeachersById[newId]!['name'] as String);
                  }
                }
              }
            }
          } else if (singleTId != null && singleTId.isNotEmpty) {
            if (activeTeachersById.containsKey(singleTId)) {
              resolvedTIds.add(singleTId);
              resolvedTNames.add(activeTeachersById[singleTId]!['name'] as String);
            } else {
              final normTName = (singleTName ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
              if (normTName.isNotEmpty && activeTeacherIdByName.containsKey(normTName)) {
                final newId = activeTeacherIdByName[normTName]!;
                resolvedTIds.add(newId);
                resolvedTNames.add(activeTeachersById[newId]!['name'] as String);
              }
            }
          }

          if (resolvedTIds.isNotEmpty) {
            data['teacherIds'] = resolvedTIds;
            data['teacherNames'] = resolvedTNames;
            data['teacherId'] = resolvedTIds.first;
            data['teacherName'] = resolvedTNames.first;
          }

          classLessons.putIfAbsent(classId, () => []).add(data);
          final lessonKey = '${classId}_${data['lessonId']}';
          remainingHours[lessonKey] = (data['weeklyHours'] ?? 0) as int;
        }
      }
      // classIdSet'te olup assignment'ı olmayan sınıflar için boş liste
      for (var cId in classIdSet) {
        classLessons.putIfAbsent(cId, () => []);
      }

      // ── Mevcut programı parse et ──
      final Map<String, Map<String, dynamic>> scheduleData = {};
      for (var doc in scheduleSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        // Hücredeki öğretmen silinmiş veya eski ID ise güncel aktif öğretmenle eşle
        final currentTId = data['teacherId']?.toString();
        final currentTName = (data['teacherName'] ?? '').toString().trim();
        if (currentTId != null && !activeTeachersById.containsKey(currentTId)) {
          final normTName = currentTName.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
          if (normTName.isNotEmpty && activeTeacherIdByName.containsKey(normTName)) {
            final newId = activeTeacherIdByName[normTName]!;
            data['teacherId'] = newId;
            data['teacherIds'] = [newId];
            data['teacherName'] = activeTeachersById[newId]!['name'];
          }
        }
        final key = '${data['classId']}_${data['day']}_${data['hourIndex']}';
        scheduleData[key] = {...data, 'id': doc.id};

        final lessonKey = '${data['classId']}_${data['lessonId']}';
        if (remainingHours.containsKey(lessonKey)) {
          remainingHours[lessonKey] = (remainingHours[lessonKey] ?? 1) - 1;
        }
      }

      // ── Filtre için sınıf seviyeleri ve tipleri ──
      final Set<int> classLevels = {};
      final Set<String> classTypes = {};
      for (var c in classes) {
        final level = c['classLevel'];
        if (level != null) {
          classLevels.add(
            level is int ? level : int.tryParse(level.toString()) ?? 0,
          );
        }
        final type = c['classTypeName'] as String?;
        if (type != null && type.isNotEmpty) {
          classTypes.add(type);
        }
      }

      // Öğretmen Listesi - Yalnızca canlı aktif öğretmenler
      final Map<String, Map<String, dynamic>> teacherMap = {};
      for (var lessonList in classLessons.values) {
        for (var l in lessonList) {
          final tIds = (l['teacherIds'] as List?)
              ?.map((e) => e.toString())
              .toList();
          if (tIds != null) {
            for (var id in tIds) {
              if (activeTeachersById.containsKey(id)) {
                teacherMap[id] = activeTeachersById[id]!;
              }
            }
          }
        }
      }
      if (teacherMap.isEmpty && activeTeachersById.isNotEmpty) {
        teacherMap.addAll(activeTeachersById);
      }
      final teachersList = teacherMap.values.toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      final isPublished = (periodDoc.data() as Map<String, dynamic>?)?['schedulePublished'] == true;

      setState(() {
        _allClasses = classes;
        _classes = classes;
        _teachers = teachersList;
        _isSchedulePublished = isPublished;
        _lessonHours = hours;
        _classLessons = classLessons;
        _remainingHours = remainingHours;
        _lessonShortNames = lessonShortNames;
        _scheduleData = scheduleData;
        if (scheduleData.isNotEmpty) _hasAutoDistributed = true;
        _availableClassLevels = classLevels;
        _availableClassTypes = classTypes;
        if (selectedDays.isNotEmpty) {
          _days = selectedDays;
        }
        _dailyLessonCounts = dailyCounts.map(
          (k, v) => MapEntry(k, v is int ? v : int.tryParse(v.toString()) ?? 0),
        );
        _isLoading = false;
      });
    } catch (e) {
      print('Veri yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Hafif yükleme: Sadece classSchedules koleksiyonunu ğeker ve kalan saatleri yeniden hesaplar.
  /// Ayarlar, sınıflar, dersler vb. zaten lokal olarak mevcut olduşu iğin tekrar ğekilmez.
  Future<void> _loadScheduleOnly() async {
    setState(() => _isLoading = true);
    try {
      final scheduleSnapshot = await FirebaseFirestore.instance
          .collection('classSchedules')
          .where('periodId', isEqualTo: widget.periodId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final Map<String, Map<String, dynamic>> scheduleData = {};
      for (var doc in scheduleSnapshot.docs) {
        final data = doc.data();
        final key = '${data['classId']}_${data['day']}_${data['hourIndex']}';
        scheduleData[key] = {...data, 'id': doc.id};
      }

      // Kalan saatleri yeniden hesapla
      final Map<String, int> remainingHours = {};
      for (var cId in _classLessons.keys) {
        for (var lesson in _classLessons[cId] ?? []) {
          final lessonKey = '${cId}_${lesson['lessonId']}';
          remainingHours[lessonKey] = (lesson['weeklyHours'] ?? 0) as int;
        }
      }
      for (var entry in scheduleData.values) {
        final lessonKey = '${entry['classId']}_${entry['lessonId']}';
        if (remainingHours.containsKey(lessonKey)) {
          remainingHours[lessonKey] = (remainingHours[lessonKey] ?? 1) - 1;
        }
      }

      setState(() {
        _scheduleData = scheduleData;
        _remainingHours = remainingHours;
        _isLoading = false;
      });
    } catch (e) {
      print('Hafif yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    setState(() {
      _classes = _allClasses.where((c) {
        // Sınıf seviyesi filtresi
        if (_selectedClassLevel != null) {
          final level = c['classLevel'];
          final classLevel = level is int
              ? level
              : int.tryParse(level.toString()) ?? 0;
          if (classLevel != _selectedClassLevel) return false;
        }
        // Sınıf tipi filtresi
        if (_selectedClassType != null) {
          final type = c['classTypeName'] as String?;
          if (type != _selectedClassType) return false;
        }
        return true;
      }).toList();
    });
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              Icon(Icons.filter_list_rounded, color: Colors.purple.shade700),
              SizedBox(width: 12),
              Text('Filtrele', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Container(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFilterHeader('Sınıf Seviyesi'),
                SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFilterChip(
                      label: 'Tümü',
                      selected: _selectedClassLevel == null,
                      onSelected: (selected) =>
                          setDialogState(() => _selectedClassLevel = null),
                    ),
                    ...(_availableClassLevels.toList()..sort()).map(
                      (level) => _buildFilterChip(
                        label: '$level. Sınıf',
                        selected: _selectedClassLevel == level,
                        onSelected: (selected) => setDialogState(
                          () => _selectedClassLevel = selected ? level : null,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24),
                _buildFilterHeader('Sınıf Tipi'),
                SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFilterChip(
                      label: 'Tümü',
                      selected: _selectedClassType == null,
                      onSelected: (selected) =>
                          setDialogState(() => _selectedClassType = null),
                    ),
                    ..._availableClassTypes.map(
                      (type) => _buildFilterChip(
                        label: type,
                        selected: _selectedClassType == type,
                        onSelected: (selected) => setDialogState(
                          () => _selectedClassType = selected ? type : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedClassLevel = null;
                  _selectedClassType = null;
                });
                _applyFilter();
                Navigator.pop(context);
              },
              child: Text(
                'Temizle',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                _applyFilter();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                elevation: 0,
              ),
              child: Text(
                'Uygula',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade800,
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required Function(bool) onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: Colors.purple.shade100,
      labelStyle: TextStyle(
        color: selected ? Colors.purple.shade900 : Colors.grey.shade700,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
      ),
      backgroundColor: Colors.grey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? Colors.purple.shade200 : Colors.transparent,
        ),
      ),
      elevation: 0,
      pressElevation: 0,
      padding: EdgeInsets.symmetric(horizontal: 4),
    );
  }

  void _showPrintDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.print_rounded,
                      color: Colors.purple.shade700,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Yazdır / Dışa Aktar',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade900,
                          ),
                        ),
                        Text(
                          widget.periodData['periodName'] ?? '',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 32),
              _buildPrintOption(
                icon: Icons.class_rounded,
                color: Colors.blue,
                title: 'Tekli Sınıf Programı',
                subtitle: 'Sınıf seçerek PDF/Excel çıktısı alın',
                onPdf: () => _handlePrint('class_single', 'pdf'),
                onExcel: () => _handlePrint('class_single', 'excel'),
              ),
              _buildPrintOption(
                icon: Icons.person_rounded,
                color: Colors.orange,
                title: 'Tekli Öğretmen Programı',
                subtitle: 'Öğretmen seçerek PDF/Excel çıktısı alın',
                onPdf: () => _handlePrint('teacher_single', 'pdf'),
                onExcel: () => _handlePrint('teacher_single', 'excel'),
              ),
              _buildPrintOption(
                icon: Icons.grid_view_rounded,
                color: Colors.purple,
                title: 'Sınıf çarşaf Listesi',
                subtitle: 'Tüm sınıfları toplu tablo olarak indir',
                onPdf: () => _handlePrint('class_master', 'pdf'),
                onExcel: () => _handlePrint('class_master', 'excel'),
              ),
              _buildPrintOption(
                icon: Icons.person_search_rounded,
                color: Colors.green,
                title: 'Öğretmen çarşaf Listesi',
                subtitle: 'Tüm öğretmenleri toplu tablo olarak indir',
                onPdf: () => _handlePrint('teacher_master', 'pdf'),
                onExcel: () => _handlePrint('teacher_master', 'excel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrintOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onPdf,
    required VoidCallback onExcel,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey.shade900,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          _buildTinyPrintButton('PDF', Colors.red, onPdf),
          SizedBox(width: 8),
          _buildTinyPrintButton('EXCEL', Colors.green.shade700, onExcel),
        ],
      ),
    );
  }

  Widget _buildTinyPrintButton(
    String label,
    Color color,
    VoidCallback onPressed,
  ) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Future<void> _handlePrint(String type, String format) async {
    Navigator.pop(context);

    // Kurum bilgilerini sor ve kaydet
    final info = await _showInstitutionInfoDialog();
    if (info == null) return;

    try {
      final pdfService = PdfService();
      final excelService = ExcelService();

      if (type == 'class_single') {
        // Sınıf seç (çoklu Seçim)
        final List<String> classNames = _classes
            .map((c) => c['className'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        final selectedClassNames = await _showMultiSelectionDialog(
          'Yazdırılacak Sınıfları Seçin',
          classNames,
          Icons.class_outlined,
        );
        if (selectedClassNames == null || selectedClassNames.isEmpty) return;

        _showLoadingIndicator();

        // Her seçilen sınıf için veri hazırla
        List<Map<String, dynamic>> multiClassData = [];

        for (var className in selectedClassNames) {
          final targetClass = _classes.firstWhere(
            (c) => c['className'] == className,
          );
          final classId = targetClass['id'];

          Map<String, dynamic> scheduleData = {};
          Map<String, int> lessonCounts = {};
          Map<String, String> lessonTeachers = {};
          Map<String, String> lessonNameToShort = {};

          _scheduleData.forEach((key, data) {
            if (data['classId'] == classId) {
              final scheduleKey = '${data['day']}_${data['hourIndex']}';
              scheduleData[scheduleKey] = {
                'lessonName': data['lessonName'],
                'shortName': _lessonShortNames[data['lessonId']] ?? '',
                'teacherName': data['teacherName'],
              };
              lessonNameToShort[data['lessonName'] ?? ''] =
                  _lessonShortNames[data['lessonId']] ?? '';
              final lessonName = data['lessonName'] as String?;
              if (lessonName != null) {
                lessonCounts[lessonName] = (lessonCounts[lessonName] ?? 0) + 1;
                lessonTeachers[lessonName] = data['teacherName'] ?? '';
              }
            }
          });

          final lessonStats = lessonCounts.entries
              .map(
                (e) => {
                  'lessonName': e.key,
                  'shortName': lessonNameToShort[e.key] ?? '',
                  'count': e.value,
                  'teacherName': lessonTeachers[e.key],
                },
              )
              .toList();

          multiClassData.add({
            'className': className,
            'scheduleData': scheduleData,
            'lessonStats': lessonStats,
          });
        }

        if (format == 'pdf') {
          final bytes = await pdfService.generateClassSchedulePdf(
            multiClassData: multiClassData,
            days: _days,
            lessonHours: _lessonHours,
            institutionInfo: info,
          );
          await Printing.sharePdf(
            bytes: bytes,
            filename: 'Sinif_Programlari.pdf',
          );
        } else {
          // Excel iğin (çoklu sayfalı excel servisi henüz yoksa ilkini atalım veya geliştirelim)
          await excelService.exportScheduleToExcel(
            title: '${selectedClassNames.first} Haftalık Ders Programı',
            days: _days,
            lessonHours: _lessonHours,
            scheduleData: multiClassData.first['scheduleData'],
            institutionInfo: info,
            fileName: 'Sinif_Programi',
          );
        }
      } else if (type == 'teacher_single') {
        // Öğretmen seçtir (çoklu Seçim)
        final teachers =
            _scheduleData.values
                .map((e) => e['teacherName'] as String?)
                .whereType<String>()
                .toSet()
                .toList()
              ..sort();

        if (teachers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Henüz programda Öğretmen atanmamış.')),
          );
          return;
        }

        final selectedTeacherNames = await _showMultiSelectionDialog(
          'Yazdırılacak Öğretmenleri Seçin',
          teachers,
          Icons.person_outline,
        );
        if (selectedTeacherNames == null || selectedTeacherNames.isEmpty)
          return;

        _showLoadingIndicator();

        List<Map<String, dynamic>> multiTeacherData = [];

        for (var teacherName in selectedTeacherNames) {
          Map<String, dynamic> scheduleData = {};
          // östatistikler iğin Key: "Ders Adı | Sınıf Adı"
          Map<String, int> lessonCounts = {};
          Map<String, String> lessonNameToShort = {};

          final Set<String> processedTeacherSlots = {};

          _scheduleData.forEach((key, data) {
            final tName = data['teacherName']?.toString();
            final tNames = (data['teacherIds'] as List?)
                ?.map((e) => e.toString())
                .toList();
            if (tName == teacherName ||
                (tNames != null && tNames.contains(teacherName))) {
              final scheduleKey = '${data['day']}_${data['hourIndex']}';
              final resolvedClassName = _resolveClassName(data);
              scheduleData[scheduleKey] = {
                'lessonName': data['lessonName'],
                'shortName': _lessonShortNames[data['lessonId']] ?? '',
                'className': resolvedClassName,
              };

              if (!processedTeacherSlots.contains(scheduleKey)) {
                processedTeacherSlots.add(scheduleKey);
                final lessonName = data['lessonName'] as String?;
                final className = resolvedClassName;
                if (lessonName != null) {
                  final statsKey = '$lessonName|$className';
                  lessonCounts[statsKey] = (lessonCounts[statsKey] ?? 0) + 1;
                  lessonNameToShort[lessonName] =
                      _lessonShortNames[data['lessonId']] ?? '';
                }
              }
            }
          });

          final lessonStats = lessonCounts.entries.map((e) {
            final parts = e.key.split('|');
            final lName = parts[0];
            final cName = parts[1];
            return {
              'lessonName': lName,
              'shortName': lessonNameToShort[lName] ?? '',
              'count': e.value,
              'className': cName,
            };
          }).toList();

          multiTeacherData.add({
            'teacherName': teacherName,
            'scheduleData': scheduleData,
            'lessonStats': lessonStats,
          });
        }

        if (format == 'pdf') {
          final bytes = await pdfService.generateTeacherSchedulePdf(
            multiTeacherData: multiTeacherData,
            days: _days,
            lessonHours: _lessonHours,
            institutionInfo: info,
          );
          await Printing.sharePdf(
            bytes: bytes,
            filename: 'Ogretmen_Programlari.pdf',
          );
        } else {
          // Excel iğin master yapısını kullanalım
          List<Map<String, dynamic>> rows = multiTeacherData
              .map(
                (e) => {
                  'name': e['teacherName'],
                  'scheduleData': e['scheduleData'],
                },
              )
              .toList();

          await excelService.exportMasterScheduleToExcel(
            days: _days,
            lessonHours: _lessonHours,
            rows: rows,
            institutionInfo: info,
            typeLabel: 'Öğretmen Programı',
            fileName: 'Ogretmen_Programi',
          );
        }
      } else if (type == 'class_master' || type == 'teacher_master') {
        _showLoadingIndicator();
        List<Map<String, dynamic>> masterRows = [];

        if (type == 'class_master') {
          for (var cls in _classes) {
            final classId = cls['id'];
            Map<String, dynamic> rowSchedule = {};

            _scheduleData.forEach((key, data) {
              if (data != null && data['classId'] == classId) {
                final scheduleKey = '${data['day']}_${data['hourIndex']}';
                rowSchedule[scheduleKey] = {
                  'lessonName': data['lessonName'],
                  'shortName': _lessonShortNames[data['lessonId']] ?? '',
                  'teacherName': data['teacherName'],
                };
              }
            });

            masterRows.add({
              'name': cls['className'] ?? 'Sınıf',
              'scheduleData': rowSchedule,
            });
          }
        } else {
          // üşretmen bazlı gruplandırma
          Map<String, Map<String, dynamic>> teacherSchedules = {};
          _scheduleData.forEach((key, data) {
            if (data == null) return;
            final teacherName = data['teacherName'] ?? 'Bilinmeyen';
            final scheduleKey = '${data['day']}_${data['hourIndex']}';

            if (!teacherSchedules.containsKey(teacherName)) {
              teacherSchedules[teacherName] = {};
            }
            teacherSchedules[teacherName]![scheduleKey] = {
              'lessonName': data['lessonName'],
              'shortName': _lessonShortNames[data['lessonId']] ?? '',
              'className': _resolveClassName(data),
            };
          });

          teacherSchedules.forEach((name, schedule) {
            masterRows.add({'name': name, 'scheduleData': schedule});
          });
        }

        if (format == 'pdf') {
          final bytes = await pdfService.generateMasterSchedulePdf(
            days: _days,
            lessonHours: _lessonHours,
            rows: masterRows,
            institutionInfo: info,
            typeLabel: type == 'class_master' ? 'Sınıflar' : 'Öğretmenler',
          );
          await Printing.sharePdf(bytes: bytes, filename: 'Carsaf_Liste.pdf');
        } else {
          await excelService.exportMasterScheduleToExcel(
            days: _days,
            lessonHours: _lessonHours,
            rows: masterRows,
            institutionInfo: info,
            typeLabel: type == 'class_master' ? 'Sınıflar' : 'Öğretmenler',
            fileName: 'Carsaf_Liste',
          );
        }
      }

      if (mounted && Navigator.canPop(context))
        Navigator.pop(context); // Yükleniyor'u kapat
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Widget _buildCustomLoader() {
    if (!_isDistributing) {
      return Container(
        color: Colors.white.withValues(alpha: 0.6),
        child: const Center(child: EduKnLoader(size: 60)),
      );
    }
    return Container(
      color: Colors.white.withValues(alpha: 0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.8, end: 1.2),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOut,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purple.withValues(alpha: 0.2),
                          blurRadius: 15 * scale,
                          spreadRadius: 8 * scale,
                        ),
                      ],
                    ),
                    child: const EduKnLoader(size: 60),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
            const Text(
              'En iyi ihtimaller hesaplanıyor...',
              style: TextStyle(
                color: Colors.purple,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLoadingIndicator() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (context) => _buildCustomLoader(),
    );
  }

  Future<List<String>?> _showMultiSelectionDialog(
    String title,
    List<String> items,
    IconData icon,
  ) async {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Navigator.push<List<String>>(
        context,
        MaterialPageRoute(
          builder: (context) =>
              FullSelectionPage(title: title, items: items, icon: icon),
          fullscreenDialog: true,
        ),
      );
    }

    return showDialog<List<String>>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: _MultiSelectionContent(
          title: title,
          items: items,
          icon: icon,
          isDialog: true,
        ),
      ),
    );
  }

  Future<Map<String, String>?> _showInstitutionInfoDialog() async {
    // Okul türü dokümanını çek
    final schoolTypeDoc = await FirebaseFirestore.instance
        .collection('schoolTypes')
        .doc(widget.schoolTypeId)
        .get();
    final schoolTypeData = schoolTypeDoc.data() ?? {};

    // Daha önce kaydedilmiş bilgiler (öncelikli)
    final savedInfo = Map<String, dynamic>.from(
      schoolTypeData['institutionalInfo'] ?? {},
    );

    // Varsayılan okul adı: okul türünün kendi adı
    final defaultSchoolName =
        schoolTypeData['name']?.toString() ??
        widget.schoolTypeName;

    // Müdür adı: önce kaydedilmiş bilgiden, yoksa users koleksiyonundan çek
    String defaultPrincipal = '';
    if (savedInfo['principalName']?.toString().isNotEmpty == true) {
      defaultPrincipal = savedInfo['principalName']!.toString();
    } else {
      try {
        // Bu okul türüne atanmış mudur rolündeki kullanıcıyı bul
        final managerQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('schoolTypes', arrayContains: widget.schoolTypeId)
            .where('role', whereIn: ['mudur', 'manager', 'admin'])
            .limit(1)
            .get();
        if (managerQuery.docs.isNotEmpty) {
          final mData = managerQuery.docs.first.data();
          final firstName = mData['firstName']?.toString() ?? '';
          final lastName = mData['lastName']?.toString() ?? '';
          final fullName = mData['name']?.toString() ??
              mData['displayName']?.toString() ??
              '${firstName} ${lastName}'.trim();
          defaultPrincipal = fullName;
        }
      } catch (_) {}
    }

    final cityCtrl = TextEditingController(
      text: savedInfo['city']?.toString().isNotEmpty == true
          ? savedInfo['city']!.toString()
          : '',
    );
    final districtCtrl = TextEditingController(
      text: savedInfo['district']?.toString().isNotEmpty == true
          ? savedInfo['district']!.toString()
          : '',
    );
    final schoolCtrl = TextEditingController(
      text: savedInfo['schoolName']?.toString().isNotEmpty == true
          ? savedInfo['schoolName']!.toString()
          : defaultSchoolName,
    );
    final principalCtrl = TextEditingController(
      text: defaultPrincipal,
    );


    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.business_rounded, color: Colors.blue),
            SizedBox(width: 12),
            Text(
              'Yazdırma Bilgileri',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModernField(cityCtrl, 'Şehir', Icons.location_city),
              SizedBox(height: 16),
              _buildModernField(districtCtrl, 'İlçe', Icons.map),
              SizedBox(height: 16),
              _buildModernField(schoolCtrl, 'Okul Adı', Icons.school),
              SizedBox(height: 16),
              _buildModernField(principalCtrl, 'Okul Müdürü', Icons.person),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.blue.shade700,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu bilgiler her okul türü için kaydedilir.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, {
              'city': cityCtrl.text,
              'district': districtCtrl.text,
              'schoolName': schoolCtrl.text,
              'principalName': principalCtrl.text,
            }),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              'Kaydet ve Devam Et',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (result != null) {
      // Bilgileri Firestore'a kaydet
      await FirebaseFirestore.instance
          .collection('schoolTypes')
          .doc(widget.schoolTypeId)
          .set({'institutionalInfo': result}, SetOptions(merge: true));
    }

    return result;
  }

  Widget _buildModernField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade600),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blue, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  void _showCopyToAnotherPeriodDialog() async {
    // Dişer dİnemleri yükle (aynı akademik dİneme ait alt dİnemler)
    final periodsSnapshot = await FirebaseFirestore.instance
        .collection('workPeriods')
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('termId', isEqualTo: widget.periodData['termId'])
        .where('isActive', isEqualTo: true)
        .get();

    final periods = periodsSnapshot.docs
        .where((doc) => doc.id != widget.periodId)
        .toList();

    if (periods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kopyalanacak başka dİnem bulunamadı')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.copy, color: Colors.blue),
            SizedBox(width: 12),
            Text('Programı Kopyala'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ders programını hangi dİneme kopyalamak istiyorsunuz?',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              SizedBox(height: 16),
              ...periods.map((doc) {
                final data = doc.data();
                return ListTile(
                  leading: Icon(Icons.calendar_today, color: Colors.purple),
                  title: Text(data['periodName'] ?? 'Öğretmen'),
                  onTap: () {
                    Navigator.pop(context);
                    _copyScheduleToPeriod(
                      doc.id,
                      data['periodName'] ?? 'Öğretmen',
                    );
                  },
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyScheduleToPeriod(
    String targetPeriodId,
    String targetPeriodName,
  ) async {
    try {
      // Mevcut programı al
      final currentSchedule = _scheduleData.values.toList();

      if (currentSchedule.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kopyalanacak program bulunamadı')),
        );
        return;
      }

      // Hedef dİnemdeki mevcut programı sil
      final existingSchedule = await FirebaseFirestore.instance
          .collection('classSchedules')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('periodId', isEqualTo: targetPeriodId)
          .get();

      final batch = FirebaseFirestore.instance.batch();

      for (var doc in existingSchedule.docs) {
        batch.delete(doc.reference);
      }

      // Yeni programı ekle
      for (var schedule in currentSchedule) {
        final newDocRef = FirebaseFirestore.instance
            .collection('classSchedules')
            .doc();
        batch.set(newDocRef, {
          'classId': schedule['classId'],
          'day': schedule['day'],
          'hourIndex': schedule['hourIndex'],
          'lessonId': schedule['lessonId'],
          'lessonName': schedule['lessonName'],
          'className': schedule['className'],
          'teacherId': schedule['teacherId'],
          'teacherName': schedule['teacherName'],
          'periodId': targetPeriodId,
          'schoolTypeId': widget.schoolTypeId,
          'institutionId': widget.institutionId,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Program "$targetPeriodName" dönemine kopyalandı'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kopyalama hatası: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showLessonPicker(String classId, String day, int hourIndex) {
    final lessons = _classLessons[classId] ?? [];
    final key = '${classId}_${day}_$hourIndex';
    final currentAssignment = _scheduleData[key];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 300,
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.book, color: Colors.purple),
                  SizedBox(width: 8),
                  Text(
                    'Ders Seğ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Divider(),
              if (lessons.isEmpty)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'Bu şubeye atanmış ders yok',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ...lessons.map((lesson) {
                  final lessonKey = '${classId}_${lesson['lessonId']}';
                  final remaining = _remainingHours[lessonKey] ?? 0;
                  final lessonName = lesson['lessonName'] ?? '';
                  final isSelected =
                      currentAssignment != null &&
                      currentAssignment['lessonId'] == lesson['lessonId'];

                  return ListTile(
                    dense: true,
                    selected: isSelected,
                    selectedTileColor: Colors.purple.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: remaining > 0
                          ? Colors.purple.shade100
                          : Colors.grey.shade200,
                      child: Text(
                        lessonName.isNotEmpty
                            ? lessonName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: remaining > 0 ? Colors.purple : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    title: Text(
                      lessonName,
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: remaining > 0
                            ? Colors.green.shade100
                            : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '($remaining)',
                        style: TextStyle(
                          color: remaining > 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    onTap: remaining > 0 || isSelected
                        ? () => _assignLesson(
                            classId,
                            day,
                            hourIndex,
                            lesson,
                            _classes.firstWhere(
                              (c) => c['id'] == classId,
                              orElse: () => {'className': 'Sınıf'},
                            )['className'],
                            closePicker: true,
                          )
                        : null,
                  );
                }),
              SizedBox(height: 8),
              if (currentAssignment != null)
                TextButton.icon(
                  onPressed: () => _removeAssignment(classId, day, hourIndex),
                  icon: Icon(Icons.delete_outline, color: Colors.red),
                  label: Text(
                    'Dersi Kaldır',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _assignLesson(
    String classId,
    String day,
    int hourIndex,
    Map<String, dynamic> lesson,
    String className, {
    bool closePicker = false,
  }) async {
    final lessonName = (lesson['lessonName'] ?? '').toString().trim();
    final teacherIds = lesson['teacherIds'] as List<dynamic>?;
    final teacherNames = lesson['teacherNames'] as List<dynamic>?;
    final teacherId = (teacherIds != null && teacherIds.isNotEmpty)
        ? teacherIds.first?.toString()
        : null;
    final teacherName = (teacherNames != null && teacherNames.isNotEmpty)
        ? teacherNames.first?.toString() ?? 'Öğretmen'
        : 'Öğretmen';

    final slotKey = '${day}_$hourIndex';

    // KAPALI SAAT KONTROLİ - Şube ve öğretmen Kapalı saatlerini KESİNLİKLE ENGELLER
    if (_closedSlots['class_$classId']?.contains(slotKey) == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$className sınıfının $day $hourIndex. saati kapalıdır! Ders atanamaz.',
          ),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
      if (closePicker) Navigator.pop(context);
      return;
    }

    if (teacherId != null &&
        _closedSlots['teacher_$teacherId']?.contains(slotKey) == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$teacherName öğretmeninin $day $hourIndex. saati kapalı olarak işaretlenmiştir! Kapatılan saate ders atanamaz.',
          ),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
      if (closePicker) Navigator.pop(context);
      return;
    }

    // Birleştirilmiş sınıfları kontrol et
    List<String> targetClassIds = [classId];
    for (var merge in _lessonClassMerges) {
      final mName = (merge['lessonName'] ?? '').toString().trim();
      final mClassIds = List<String>.from(merge['classIds'] ?? []);
      if (mName.toLowerCase() == lessonName.toLowerCase() &&
          mClassIds.contains(classId)) {
        targetClassIds = mClassIds;
        break;
      }
    }

    // üşretmen ğakışma kontrolü (birleştirilmiş sınıflar haricindeki dişer derslerle)
    if (teacherId != null) {
      for (var entry in _scheduleData.entries) {
        final data = entry.value;
        if (data['day'] == day && data['hourIndex'] == hourIndex) {
          final assignedClassId = data['classId']?.toString();
          if (data['teacherId'] == teacherId &&
              !targetClassIds.contains(assignedClassId)) {
            final conflictClassName = _classes.firstWhere(
              (c) => c['id'] == assignedClassId,
              orElse: () => {'className': 'Bilinmeyen'},
            )['className'];

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$teacherName bu saatte $conflictClassName sınıfında ders veriyor!',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
            if (closePicker) Navigator.pop(context);
            return;
          }
        }
      }
    }

    // üşretmen günlük ders limiti kontrolü ve uyarısı (Birleştirilmiş sınıflar tek ders saati sayılır)
    if (teacherId != null) {
      final Set<int> teacherDailySlots = {};
      for (var entry in _scheduleData.values) {
        if (entry['day'] == day) {
          final tId = entry['teacherId']?.toString();
          final tIds = (entry['teacherIds'] as List?)
              ?.map((e) => e.toString())
              .toList();
          if (tId == teacherId || (tIds != null && tIds.contains(teacherId))) {
            final h = entry['hourIndex'] is int
                ? entry['hourIndex'] as int
                : int.tryParse(entry['hourIndex'].toString()) ?? -1;
            if (h >= 0) teacherDailySlots.add(h);
          }
        }
      }
      final currentDailyCount = teacherDailySlots.length;

      final dayMax = _dailyLessonCounts[day] ?? 8;
      final maxLimit =
          _teacherMaxDailyHours[teacherId] ??
          (dayMax > 1 ? dayMax - 1 : dayMax);

      if (currentDailyCount >= maxLimit) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Ders Limiti Uyarısı',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Text(
              '$teacherName öğretmeninin $day günü için tanımlanan günlük ders limiti ($maxLimit saat) dolmuştur.\nŞu an $day gününe $currentDailyCount saat ders atanmış durumdadır.\n\nYine de devam edip bu dersi eklemek istiyor musunuz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Yine de Atansın',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );

        if (proceed != true) {
          return;
        }
      }
    }

    if (closePicker) {
      Navigator.pop(context);
    }

    // Her hedef (birleştirilmiş) sınıf iğin atamayı gerğekleştir
    final syncService = ClassScheduleSyncService();

    for (var targetCId in targetClassIds) {
      final key = '${targetCId}_${day}_$hourIndex';
      final lessonKey = '${targetCId}_${lesson['lessonId']}';
      final oldAssignment = _scheduleData[key];

      // Zaten aynı ders atanmışsa atla
      if (oldAssignment != null &&
          oldAssignment['lessonId'] == lesson['lessonId']) {
        continue;
      }

      // Eski atamayı kaldır (varsa)
      if (oldAssignment != null) {
        final oldLessonKey = '${targetCId}_${oldAssignment['lessonId']}';
        _remainingHours[oldLessonKey] =
            (_remainingHours[oldLessonKey] ?? 0) + 1;
        if (oldAssignment['id'] != null) {
          try {
            await FirebaseFirestore.instance
                .collection('classSchedules')
                .doc(oldAssignment['id'])
                .delete();
          } catch (e) {
            print('Eski atama silinemedi: $e');
          }
        }
      }

      final targetClassName = _classes.firstWhere(
        (c) => c['id'] == targetCId,
        orElse: () => {'className': targetCId},
      )['className'];

      setState(() {
        _scheduleData[key] = {
          'classId': targetCId,
          'day': day,
          'hourIndex': hourIndex,
          'lessonId': lesson['lessonId'],
          'lessonName': lessonName,
          'className': targetClassName,
          'teacherId': teacherId,
          'teacherName': teacherName,
        };
        _remainingHours[lessonKey] = (_remainingHours[lessonKey] ?? 1) - 1;
      });

      try {
        await syncService.syncLessonAssignment(
          institutionId: widget.institutionId,
          periodId: widget.periodId,
          classId: targetCId,
          className: targetClassName,
          day: day,
          hourIndex: hourIndex,
          lessonId: lesson['lessonId'],
          lessonName: lessonName,
          teacherIds: teacherIds?.map((e) => e.toString()).toList() ?? [],
          termId: _cachedTermId,
        );
      } catch (e) {
        print('Ders senkronize edilemedi (Firestore): $e');
      }
    }
  }

  Future<void> _removeAssignment(
    String classId,
    String day,
    int hourIndex,
  ) async {
    final key = '${classId}_${day}_$hourIndex';
    final assignment = _scheduleData[key];

    if (assignment == null) {
      Navigator.pop(context);
      return;
    }

    final lessonName = (assignment['lessonName'] ?? '').toString().trim();

    // Birleştirilmiş sınıfları kontrol et
    List<String> targetClassIds = [classId];
    for (var merge in _lessonClassMerges) {
      final mName = (merge['lessonName'] ?? '').toString().trim();
      final mClassIds = List<String>.from(merge['classIds'] ?? []);
      if (mName.toLowerCase() == lessonName.toLowerCase() &&
          mClassIds.contains(classId)) {
        targetClassIds = mClassIds;
        break;
      }
    }

    Navigator.pop(context);

    final syncService = ClassScheduleSyncService();

    for (var targetCId in targetClassIds) {
      final targetKey = '${targetCId}_${day}_$hourIndex';
      final targetAssignment = _scheduleData[targetKey];

      if (targetAssignment != null) {
        final lessonKey = '${targetCId}_${targetAssignment['lessonId']}';

        setState(() {
          _scheduleData.remove(targetKey);
          _remainingHours[lessonKey] = (_remainingHours[lessonKey] ?? 0) + 1;
        });

        try {
          await syncService.removeLessonAssignment(
            periodId: widget.periodId,
            classId: targetCId,
            day: day,
            hourIndex: hourIndex,
          );
        } catch (e) {
          print('Ders silinemedi (Firestore): $e');
        }
      }
    }
  }

  /// çift tıklama ile hızlı ders kaldırma (dialog ağmadan)
  void _quickRemoveAssignment(
    String rowId,
    String day,
    int hourIndex,
    Map<String, dynamic> assignment,
  ) {
    final classId = !_isTeacherView
        ? rowId
        : (assignment['classId']?.toString() ?? rowId);
    final lessonName = (assignment['lessonName'] ?? '').toString().trim();

    // Birleştirilmiş sınıfları kontrol et
    List<String> targetClassIds = [classId];
    for (var merge in _lessonClassMerges) {
      final mName = (merge['lessonName'] ?? '').toString().trim();
      final mClassIds = List<String>.from(merge['classIds'] ?? []);
      if (mName.toLowerCase() == lessonName.toLowerCase() &&
          mClassIds.contains(classId)) {
        targetClassIds = mClassIds;
        break;
      }
    }

    final syncService = ClassScheduleSyncService();

    for (var targetCId in targetClassIds) {
      final targetKey = '${targetCId}_${day}_$hourIndex';
      final targetAssignment = _scheduleData[targetKey];

      if (targetAssignment != null) {
        final lessonKey = '${targetCId}_${targetAssignment['lessonId']}';

        setState(() {
          _scheduleData.remove(targetKey);
          _remainingHours[lessonKey] = (_remainingHours[lessonKey] ?? 0) + 1;
        });

        syncService.removeLessonAssignment(
          periodId: widget.periodId,
          classId: targetCId,
          day: day,
          hourIndex: hourIndex,
        );
      }
    }
  }

  Future<void> _showScheduleSettings() async {
    // Preloaded assignments formatina donustur (FAST PATH icin)
    final preloadedAssignments = <Map<String, dynamic>>[];
    final Map<String, Map<String, dynamic>> groupMap = {};
    for (final classId in _classLessons.keys) {
      for (final lesson in _classLessons[classId] ?? []) {
        final lName = (lesson['lessonName'] ?? lesson['name'] ?? '').toString().trim();
        final wh = (lesson['weeklyHours'] as num?)?.toInt() ?? 0;
        final lId = (lesson['lessonId'] ?? lesson['id'] ?? '').toString();
        final cName = (lesson['className'] ?? '').toString().trim();
        if (lName.isEmpty || wh <= 0) continue;
        final groupKey = '${lName.toLowerCase()}|$wh';
        if (!groupMap.containsKey(groupKey)) {
          groupMap[groupKey] = {
            'groupKey': groupKey,
            'lessonId': lId,
            'lessonName': lName,
            'weeklyHours': wh,
            'classIds': <String>[],
            'classNames': <String>[],
          };
        }
        if (classId.isNotEmpty &&
            !(groupMap[groupKey]!['classIds'] as List).contains(classId)) {
          (groupMap[groupKey]!['classIds'] as List).add(classId);
          (groupMap[groupKey]!['classNames'] as List).add(cName);
        }
      }
    }
    preloadedAssignments.addAll(groupMap.values);

    final screenW = MediaQuery.of(context).size.width;
    final panelWidth = kIsWeb ? (screenW * 0.80).clamp(400.0, 1100.0) : screenW;

    final result = await showModalBottomSheet<ScheduleSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Center(
        child: SizedBox(
          width: panelWidth,
          child: ScheduleSettingsPanel(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            periodId: widget.periodId,
            periodData: widget.periodData,
            preloadedTeachers: List.from(_teachers),
            preloadedClasses: List.from(_classes),
            preloadedAssignments: preloadedAssignments,
            initialSettings: ScheduleSettings(
              lessonBlockPatterns: Map.from(_lessonBlockPatterns),
              lessonAllowSplit: Map.from(_lessonAllowSplit),
              lessonAvoidFirstHour: Map.from(_lessonAvoidFirstHour),
              lessonAvoidLastHour: Map.from(_lessonAvoidLastHour),
              lessonClassMerges: List.from(_lessonClassMerges),
              closedSlots: Map.fromEntries(
                _closedSlots.entries.map((e) => MapEntry(e.key, Set.from(e.value))),
              ),
              teacherMaxDailyHours: Map.from(_teacherMaxDailyHours),
              halfDayMorningHours: List.from(_halfDayMorningHours),
              halfDayAfternoonHours: List.from(_halfDayAfternoonHours),
              halfDayFlexible: Set.from(_halfDayFlexible),
              halfDayAssignedDays: Map.from(_halfDayAssignedDays),
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _lessonBlockPatterns = result.lessonBlockPatterns;
        _lessonAllowSplit = result.lessonAllowSplit;
        _lessonAvoidFirstHour = result.lessonAvoidFirstHour;
        _lessonAvoidLastHour = result.lessonAvoidLastHour;
        _lessonClassMerges = result.lessonClassMerges;
        _closedSlots = result.closedSlots;
        _teacherMaxDailyHours = result.teacherMaxDailyHours;
        _halfDayMorningHours = List.from(result.halfDayMorningHours);
        _halfDayAfternoonHours = List.from(result.halfDayAfternoonHours);
        _halfDayFlexible = Set.from(result.halfDayFlexible);
        _halfDayAssignedDays = Map.from(result.halfDayAssignedDays);
      });

      // Firestore'a kalıcı olarak kaydet!
      try {
        await FirebaseFirestore.instance
            .collection('workPeriods')
            .doc(widget.periodId)
            .set({
              'scheduleSettings': {
                'lessonBlockPatterns': result.lessonBlockPatterns,
                'lessonAllowSplit': result.lessonAllowSplit,
                'lessonAvoidFirstHour': result.lessonAvoidFirstHour,
                'lessonAvoidLastHour': result.lessonAvoidLastHour,
                'lessonClassMerges': result.lessonClassMerges,
                'closedSlots': result.closedSlots.map(
                  (k, v) => MapEntry(k, v.toList()),
                ),
                'teacherMaxDailyHours': result.teacherMaxDailyHours,
                'halfDayMorningHours': result.halfDayMorningHours,
                'halfDayAfternoonHours': result.halfDayAfternoonHours,
                'halfDayFlexible': result.halfDayFlexible.toList(),
                'halfDayAssignedDays': result.halfDayAssignedDays,
              },
            }, SetOptions(merge: true));
        print('­• Daşıtım ayarları Firestore\'a kalıcı kaydedildi!');
      } catch (e) {
        print('• Daşıtım ayarları Firestore\'a kaydedilemedi: $e');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Dağıtım ayarları kalıcı olarak kaydedildi!'),
          backgroundColor: Colors.indigo.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearSchedule() async {
    final lockedCount = _lockedSlots.length;
    bool deleteLocked = false;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.delete_forever, color: Colors.red),
                  SizedBox(width: 12),
                  Text('Programı Temizle'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deleteLocked
                        ? 'Tüm program (kilitli dersler dahil) tamamen silinecektir.'
                        : (lockedCount > 0
                              ? 'Kilitli olmayan tüm dersler programdan temizlenecek.\n­şöÆ $lockedCount kilitli ders korunacaktır.'
                              : 'Programdaki tüm dersler temizlenecek. Devam etmek istiyor musunuz?'),
                    style: const TextStyle(height: 1.4),
                  ),
                  if (lockedCount > 0) ...[
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: deleteLocked
                            ? Colors.red.shade50
                            : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: deleteLocked
                              ? Colors.red.shade300
                              : Colors.amber.shade300,
                        ),
                      ),
                      child: CheckboxListTile(
                        value: deleteLocked,
                        onChanged: (val) {
                          setDialogState(() => deleteLocked = val ?? false);
                        },
                        dense: true,
                        activeColor: Colors.red,
                        title: Text(
                          'Kilitli olan dersleri de kaldır ($lockedCount kilit)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: deleteLocked
                                ? Colors.red.shade900
                                : Colors.amber.shade900,
                          ),
                        ),
                        subtitle: Text(
                          deleteLocked
                              ? 'Tüm kilitler açılacak ve program sıfırlanacak'
                              : 'İşaretlenmezse kilitli dersleriniz korunur',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    'Temizle',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final allDocs = await FirebaseFirestore.instance
          .collection('classSchedules')
          .where('periodId', isEqualTo: widget.periodId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      int deletedCount = 0;
      int keptCount = 0;
      for (var doc in allDocs.docs) {
        final data = doc.data();
        final slotKey =
            '${data['classId']}_${data['day']}_${data['hourIndex']}';
        final isLocked = _lockedSlots.contains(slotKey);

        if (isLocked && !deleteLocked) {
          // Kilitli slotlar korunuyor
          keptCount++;
        } else {
          batch.delete(doc.reference);
          deletedCount++;
        }
      }
      await batch.commit();

      if (deleteLocked) {
        setState(() {
          _lockedSlots.clear();
          _scheduleData.clear();
        });
        await _saveLockedSlots();
      } else {
        setState(() {
          _scheduleData.removeWhere((key, value) {
            return !_lockedSlots.contains(key);
          });
        });
      }

      // await _loadData(); // öPTAL EDöLDö - çok yavaşlatıyordu, lokalden sildik.

      // Kalan saatleri lokalden tekrar hesapla
      for (var cId in _classLessons.keys) {
        for (var lesson in _classLessons[cId] ?? []) {
          final lKey = '${cId}_${lesson['lessonId']}';
          _remainingHours[lKey] = (lesson['weeklyHours'] ?? 0) as int;
        }
      }
      for (var entry in _scheduleData.values) {
        final lKey = '${entry['classId']}_${entry['lessonId']}';
        if (_remainingHours.containsKey(lKey)) {
          _remainingHours[lKey] = (_remainingHours[lKey] ?? 1) - 1;
        }
      }

      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              deleteLocked
                  ? 'Tüm program ve kilitler sıfırlandı ($deletedCount ders silindi).'
                  : (keptCount > 0
                        ? '$deletedCount ders silindi. $keptCount kilitli ders korundu.'
                        : 'Tüm program temizlendi.'),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _autoDistributeSchedule() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.smart_toy_rounded,
                color: Colors.orange.shade800,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Otomatik Ders Dağıtımı',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Otomatik dağıtım algoritması (Monte Carlo simülasyonu) çalıştırılarak dersler yerleştirilecektir.',
            ),
            const SizedBox(height: 12),
            Text(
              'Elle yapılan yerleşimler korunacak, birleştirilmiş dersler ve öğretmen günlük ders limitleri dikkate alınacaktır.',
              style: TextStyle(
                color: Colors.indigo.shade800,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Dağıtımı Başlat',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show Animated Progress Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _AutoDistributionProgressDialog();
      },
    );

    try {
      final service = AutoScheduleService();
      final result = await service.distributeSchedule(
        periodId: widget.periodId,
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        lessonBlockPatterns: _lessonBlockPatterns.isNotEmpty
            ? _lessonBlockPatterns
            : null,
        lessonAllowSplit: _lessonAllowSplit.isNotEmpty
            ? _lessonAllowSplit
            : null,
        lessonAvoidFirstHour: _lessonAvoidFirstHour.isNotEmpty
            ? _lessonAvoidFirstHour
            : null,
        lessonAvoidLastHour: _lessonAvoidLastHour.isNotEmpty
            ? _lessonAvoidLastHour
            : null,
        lessonClassMerges: _lessonClassMerges.isNotEmpty
            ? _lessonClassMerges
            : null,
        closedSlots: _closedSlots.isNotEmpty ? _closedSlots : null,
        teacherMaxDailyHours: _teacherMaxDailyHours.isNotEmpty
            ? _teacherMaxDailyHours
            : null,
        lockedSlots: _lockedSlots.isNotEmpty ? _lockedSlots : null,
      );

      // Dismiss Progress Dialog
      if (mounted) Navigator.pop(context);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(
                  result.unassignedCount == 0
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  color: result.unassignedCount == 0
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  result.unassignedCount == 0
                      ? 'Dağıtım Başarılı!'
                      : 'Dağıtım Tamamlandı',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: result.unassignedCount == 0
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '• ${result.assignedCount} saat ders yerleştirildi.',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: result.unassignedCount == 0
                                  ? Colors.green.shade900
                                  : Colors.orange.shade900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (result.unassignedCount > 0) ...[
                    const SizedBox(height: 14),
                    Text(
                      '• ${result.unassignedCount} ders saati yerleştirilemedi:',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: result.unassignedDetails.map((detail) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '• ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      detail,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tavsiye: Dağıtım ayarlarından Öğretmen kapalı saatlerini azaltabilir veya Öğretmen günlük limitlerini artırabilirsiniz.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Tamam',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );

        _hasAutoDistributed = true;
        // Hafif yükleme: sadece classSchedules'ı tekrar ğek (ayarlar, sınıflar, dersler zaten lokal)
        _loadScheduleOnly();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _publishSchedule() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.publish_rounded, color: Colors.green.shade700),
            const SizedBox(width: 10),
            const Text('Ders Programını Yayınla'),
          ],
        ),
        content: Text(
          '${widget.periodData['periodName'] ?? 'Ders Programı'} tüm öğretmenlerin ve şubelerin ders programı ekranına iletilecektir. Yayınlamak istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yayınla'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(widget.periodId)
          .update({'schedulePublished': true});

      setState(() => _isSchedulePublished = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Ders programı yayınlandı ve öğretmen ders programına iletildi!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _unpublishSchedule() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.visibility_off_outlined, color: Colors.orange.shade700),
            const SizedBox(width: 10),
            const Text('Yayından Kaldır'),
          ],
        ),
        content: const Text(
          'Ders programı öğretmenlerin ekranından kaldırılacaktır. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yayından Kaldır'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(widget.periodId)
          .update({'schedulePublished': false});

      setState(() => _isSchedulePublished = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ders programı yayından kaldırıldı.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showPublishStatusDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green.shade700),
            const SizedBox(width: 10),
            const Text('Program Yayında'),
          ],
        ),
        content: Text(
          '${widget.periodData['periodName'] ?? 'Ders Programı'} şu anda yayınlanmış durumdadır ve öğretmenlerin ders programı ekranında görüntülenmektedir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              _unpublishSchedule();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange.shade800,
              side: BorderSide(color: Colors.orange.shade300),
            ),
            child: const Text('Yayından Kaldır'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final periodName = widget.periodData['periodName'] ?? 'Ders Programı';

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: Colors.grey.shade800),
          onPressed: widget.onBack,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ders Programı',
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              periodName,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        actions: [
          // Filtre butonu
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: (_selectedClassLevel != null || _selectedClassType != null)
                  ? Colors.purple
                  : Colors.grey.shade700,
            ),
            onPressed: _showFilterDialog,
            tooltip: 'Filtrele',
          ),
          // Ekrana Sığdır Butonu (Sadece geniş ekranlarda - mobilde gereksiz)
          Builder(
            builder: (context) {
              final isWide = MediaQuery.of(context).size.width > 600;
              if (!isWide) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(
                  _isFitToScreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fit_screen_rounded,
                  color: _isFitToScreen ? Colors.purple : Colors.grey.shade700,
                ),
                onPressed: () {
                  setState(() {
                    _isFitToScreen = !_isFitToScreen;
                  });
                },
                tooltip: _isFitToScreen
                    ? 'Orijinal Boyuta Dön'
                    : 'Ekrana Sığdır',
              );
            },
          ),
          // Yayınla / Yayında Butonu
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: _isSchedulePublished
                ? OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                      side: BorderSide(color: Colors.green.shade300),
                      backgroundColor: Colors.green.shade50,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 15),
                    label: const Text('Yayında', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _showPublishStatusDialog,
                  )
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.send_rounded, size: 14),
                    label: const Text('Yayınla', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _publishSchedule,
                  ),
          ),
          // 3 nokta menüsü (yazdır, kopyala vb.)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey.shade700),
            onSelected: (value) {
              if (value == 'print') {
                _showPrintDialog();
              } else if (value == 'copy') {
                _showCopyToAnotherPeriodDialog();
              } else if (value == 'clear') {
                _clearSchedule();
              } else if (value == 'settings') {
                _showScheduleSettings();
              } else if (value == 'auto_distribute') {
                _autoDistributeSchedule();
              } else if (value == 'publish') {
                _publishSchedule();
              } else if (value == 'unpublish') {
                _unpublishSchedule();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'print',
                child: Row(
                  children: [
                    Icon(Icons.print, color: Colors.purple, size: 20),
                    SizedBox(width: 8),
                    Text('Yazdır / PDF'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('Başka Döneme Kopyala'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Programı Temizle'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, color: Colors.indigo, size: 20),
                    SizedBox(width: 8),
                    Text('Dağıtım Ayarları'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'auto_distribute',
                child: Row(
                  children: [
                    Icon(Icons.smart_toy, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text('Otomatik Dağıt'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _isSchedulePublished ? 'unpublish' : 'publish',
                child: Row(
                  children: [
                    Icon(
                      _isSchedulePublished
                          ? Icons.visibility_off_outlined
                          : Icons.publish_rounded,
                      color: _isSchedulePublished ? Colors.orange : Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isSchedulePublished
                          ? 'Yayından Kaldır'
                          : 'Öğretmenlere Yayınla',
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.isViewingPastTerm)
            Container(
              margin: EdgeInsets.only(right: 8),
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 14, color: Colors.orange.shade700),
                  SizedBox(width: 4),
                  Text(
                    'Geçmiş',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          _classes.isEmpty && !_isLoading
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildViewModeToggle(),
                    Expanded(child: _buildScheduleGrid()),
                    _buildUnassignedLessonsBar(),
                  ],
                ),
          if (_isLoading) _buildCustomLoader(),
        ],
      ),
    );
  }

  Widget _buildViewModeToggle() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        return Container(
          color: Colors.grey.shade50,
          padding: EdgeInsets.symmetric(
            vertical: 6,
            horizontal: isMobile ? 8 : 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // İst satır: Tab toggle (her zaman)
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildToggleItem(
                          'Sınıf Programı',
                          Icons.class_rounded,
                          !_isTeacherView,
                          () => setState(() {
                            _isTeacherView = false;
                            _unassignedFilterId = null;
                            _selectedUnassignedLesson = null;
                            _selectedEmptySlot = null;
                            _selectedClassLevel = null;
                            _selectedClassType = null;
                            _classes = _allClasses;
                          }),
                          isMobile: isMobile,
                        ),
                        _buildToggleItem(
                          'Öğretmen Programı',
                          Icons.person_rounded,
                          _isTeacherView,
                          () => setState(() {
                            _isTeacherView = true;
                            _unassignedFilterId = null;
                            _selectedUnassignedLesson = null;
                            _selectedEmptySlot = null;
                            _selectedClassLevel = null;
                            _selectedClassType = null;
                            _classes = _allClasses;
                          }),
                          isMobile: isMobile,
                        ),
                      ],
                    ),
                  ),
                  if (!isMobile) ...[
                    // Web'de: seğili ders/filtre bilgisi aynı satırda
                    if (_selectedUnassignedLesson != null) ...[
                      const SizedBox(width: 12),
                      Expanded(child: _buildSelectedLessonInfo()),
                    ] else if (_unassignedFilterId != null) ...[
                      const SizedBox(width: 12),
                      Expanded(child: _buildFilterInfo()),
                    ],
                  ],
                ],
              ),
              // Mobilde: seğili ders/filtre bilgisi alt satırda
              if (isMobile) ...[
                if (_selectedUnassignedLesson != null) ...[
                  const SizedBox(height: 6),
                  _buildSelectedLessonInfo(),
                ] else if (_unassignedFilterId != null) ...[
                  const SizedBox(height: 6),
                  _buildFilterInfo(),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  /// Seğili ders bilgisi + kilitle/zorla butonları
  Widget _buildSelectedLessonInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.touch_app_rounded, size: 16, color: Colors.green.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Seğili: ${_selectedUnassignedLesson!['lessonName']} (${_selectedUnassignedLesson!['className']}) ÔåÆ ${_selectedUnassignedLesson!['_isAssignedSelection'] == true ? '­şşó Yeşil: Boş saatler  |  ­şşí Turuncu: çakışmasız dolu saatler' : 'Yeşil saatlere dokunup yerleştirin'}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade900,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_selectedUnassignedLesson!['_isAssignedSelection'] == true) ...[
            Builder(
              builder: (context) {
                final slotKey =
                    '${_selectedUnassignedLesson!['classId']}_${_selectedUnassignedLesson!['day']}_${_selectedUnassignedLesson!['hourIndex']}';
                final isLocked = _lockedSlots.contains(slotKey);
                return InkWell(
                  onTap: () => _toggleLockLesson(_selectedUnassignedLesson!),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: isLocked
                          ? Colors.red.shade100
                          : Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isLocked
                            ? Colors.red.shade400
                            : Colors.amber.shade600,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLocked
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          size: 13,
                          color: isLocked
                              ? Colors.red.shade800
                              : Colors.amber.shade900,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isLocked ? 'Ders Kilidini Ağ' : 'Dersi Kilitle',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isLocked
                                ? Colors.red.shade900
                                : Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ] else ...[
            InkWell(
              onTap: () =>
                  _forcePlaceUnassignedLesson(_selectedUnassignedLesson!),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade700, Colors.amber.shade700],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Otomatik Daşıtımı Zorla',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _selectedUnassignedLesson = null),
          ),
        ],
      ),
    );
  }

  /// Filtre bilgisi (seğili şube/İşretmen) + kilitle butonu
  Widget _buildFilterInfo() {
    return Builder(
      builder: (context) {
        final String entityName;
        final bool isLocked;
        final VoidCallback onToggle;
        final String lockButtonText;
        if (_isTeacherView) {
          final t = _teachers.firstWhere(
            (x) => x['id']?.toString() == _unassignedFilterId,
            orElse: () => {},
          );
          entityName = t['name'] ?? 'Öğretmen';
          final teacherKeys = _scheduleData.entries
              .where((e) {
                final tId = e.value['teacherId']?.toString();
                final tIds = (e.value['teacherIds'] as List?)
                    ?.map((x) => x.toString())
                    .toList();
                return tId == _unassignedFilterId ||
                    tIds?.contains(_unassignedFilterId) == true;
              })
              .map((e) => e.key)
              .toList();
          isLocked =
              teacherKeys.isNotEmpty &&
              teacherKeys.every((k) => _lockedSlots.contains(k));
          onToggle = () => _toggleLockTeacher(_unassignedFilterId!);
          lockButtonText = isLocked
              ? 'Öğretmen Kilidini Aç'
              : 'Seçili Öğretmeni Kilitle';
        } else {
          final c = _classes.firstWhere(
            (x) => x['id']?.toString() == _unassignedFilterId,
            orElse: () => {},
          );
          entityName = c['className'] ?? 'Şube';
          final classKeys = _scheduleData.keys
              .where((k) => k.startsWith('${_unassignedFilterId}_'))
              .toList();
          isLocked =
              classKeys.isNotEmpty &&
              classKeys.every((k) => _lockedSlots.contains(k));
          onToggle = () => _toggleLockClass(_unassignedFilterId!);
          lockButtonText = isLocked
              ? 'Şube Kilidini Aç'
              : 'Seçili Şubeyi Kilitle';
        }

        // Esnek yarim gun kontrolu (ogretmen filtresi + esnek secili)
        // _halfDayFlexible format: 'teacher_<id>_morning' veya 'teacher_<id>_afternoon'
        final flexPrefix = _isTeacherView && _unassignedFilterId != null
            ? 'teacher_${_unassignedFilterId}'
            : null;
        final bool hasFlexMorning =
            flexPrefix != null &&
            _halfDayFlexible.contains('${flexPrefix}_morning') &&
            _halfDayMorningHours.isNotEmpty;
        final bool hasFlexAfternoon =
            flexPrefix != null &&
            _halfDayFlexible.contains('${flexPrefix}_afternoon') &&
            _halfDayAfternoonHours.isNotEmpty;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_alt_rounded,
                    size: 16,
                    color: Colors.indigo.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$entityName seçili',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: isLocked
                            ? Colors.red.shade100
                            : Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isLocked
                              ? Colors.red.shade400
                              : Colors.amber.shade600,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLocked
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            size: 13,
                            color: isLocked
                                ? Colors.red.shade800
                                : Colors.amber.shade900,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            lockButtonText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isLocked
                                  ? Colors.red.shade900
                                  : Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _unassignedFilterId = null),
                  ),
                ],
              ),
            ),
            // Esnek yarim gun banneri - tiklaninca gun atama dialog'u acar
            if (hasFlexMorning || hasFlexAfternoon) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => _showAssignFlexibleHalfDayDialog(
                  teacherId: _unassignedFilterId!,
                  entityName: entityName,
                  hasMorning: hasFlexMorning,
                  hasAfternoon: hasFlexAfternoon,
                ),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFE07B00).withValues(alpha: 0.6),
                    ),
                    color: const Color(0xFFFFF3E0),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: Color(0xFFE07B00),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF5D4037),
                            ),
                            children: [
                              TextSpan(
                                text: '$entityName • ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const TextSpan(
                                text: 'Esnek Yarım Gün İzni: ',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (hasFlexMorning)
                                TextSpan(
                                  text:
                                      'Sabah (${_halfDayMorningHours.first + 1}-${_halfDayMorningHours.last + 1}. saat)',
                                ),
                              if (hasFlexMorning && hasFlexAfternoon)
                                const TextSpan(text: '  |  '),
                              if (hasFlexAfternoon)
                                TextSpan(
                                  text:
                                      'Öğleden Sonra (${_halfDayAfternoonHours.first + 1}-${_halfDayAfternoonHours.last + 1}. saat)',
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.add_circle_outline_rounded,
                        size: 14,
                        color: Color(0xFFE07B00),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Esnek yarim gun icin gun atama dialog'u - tiklayinca hangi gune atanacagini secer
  Future<void> _showAssignFlexibleHalfDayDialog({
    required String teacherId,
    required String entityName,
    required bool hasMorning,
    required bool hasAfternoon,
  }) async {
    final days = widget.periodData['lessonHours']?['selectedDays'] != null
        ? List<String>.from(widget.periodData['lessonHours']['selectedDays'])
        : ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma'];

    String? selectedDay;
    String? selectedSession = hasMorning
        ? 'morning'
        : (hasAfternoon ? 'afternoon' : null);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.schedule_rounded, color: Color(0xFFE07B00)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$entityName — Yarım Gün Atama',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Session secimi (hem sabah hem ogleden sonra eslekse)
              if (hasMorning && hasAfternoon) ...[
                const Text(
                  'İzin Türü:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _buildSessionChip(
                        label: '☀️ Sabah',
                        selected: selectedSession == 'morning',
                        onTap: () => setDialogState(
                          () => selectedSession = 'morning',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSessionChip(
                        label: '🌙 Öğleden Sonra',
                        selected: selectedSession == 'afternoon',
                        onTap: () => setDialogState(
                          () => selectedSession = 'afternoon',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              const Text(
                'Hangi gün?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: days.map((day) {
                  final isSelected = selectedDay == day;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedDay = day),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFE07B00)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFE07B00)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        day,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE07B00),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Ata'),
              onPressed: (selectedDay != null && selectedSession != null)
                  ? () => Navigator.pop(ctx, {
                        'day': selectedDay!,
                        'session': selectedSession!,
                      })
                  : null,
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;
    final day = result['day']!;
    final session = result['session']!;
    final key = 'teacher_${teacherId}_$session';

    setState(() {
      // Esnek listesinden cikar (artik sabit)
      _halfDayFlexible.remove(key);
      // Sabit gun ata
      _halfDayAssignedDays[key] = day;
    });

    // Firestore'a kaydet
    try {
      await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(widget.periodId)
          .set({
            'scheduleSettings': {
              'halfDayFlexible': _halfDayFlexible.toList(),
              'halfDayAssignedDays': _halfDayAssignedDays,
            },
          }, SetOptions(merge: true));
    } catch (e) {
      print('halfDay assign save error: $e');
    }
  }

  /// Session chip helper
  Widget _buildSessionChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE07B00) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? const Color(0xFFE07B00)
                : Colors.grey.shade300,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }



  Widget _buildToggleItem(
    String title,
    IconData icon,
    bool active,
    VoidCallback onTap, {
    bool isMobile = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 14,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? Colors.indigo.shade700 : Colors.grey.shade600,
            ),
            if (!isMobile) ...[
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  color: active ? Colors.indigo.shade900 : Colors.grey.shade700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getUnassignedLessons() {
    final List<Map<String, dynamic>> result = [];
    for (var entry in _classLessons.entries) {
      final classId = entry.key;
      final className =
          _classes.firstWhere(
                (c) => c['id'] == classId,
                orElse: () => {'className': 'Sınıf'},
              )['className']
              as String;

      for (var lesson in entry.value) {
        final lessonKey = '${classId}_${lesson['lessonId']}';
        final remaining = _remainingHours[lessonKey] ?? 0;
        if (remaining > 0) {
          result.add({
            ...lesson,
            'classId': classId,
            'className': className,
            'remainingHours': remaining,
          });
        }
      }
    }
    result.sort(
      (a, b) =>
          (b['remainingHours'] as int).compareTo(a['remainingHours'] as int),
    );
    return result;
  }

  Widget _buildUnassignedLessonsBar() {
    var unassigned = _getUnassignedLessons();

    // Filtre uygula
    if (_unassignedFilterId != null) {
      if (_isTeacherView) {
        // üşretmen filtresi: İşretmenin derslerini gİster
        unassigned = unassigned.where((item) {
          final teacherIds =
              (item['teacherIds'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          final teacherId = item['teacherId']?.toString();
          return teacherIds.contains(_unassignedFilterId) ||
              teacherId == _unassignedFilterId;
        }).toList();
      } else {
        // Sınıf filtresi: sınıfın derslerini gİster
        unassigned = unassigned.where((item) {
          return item['classId']?.toString() == _unassignedFilterId;
        }).toList();
      }
    }

    if (unassigned.isEmpty && _unassignedFilterId == null)
      return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Colors.orange.shade800,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _unassignedFilterId != null
                      ? 'Yerleşemeyen Dersler (${unassigned.fold<int>(0, (sum, item) => sum + ((item['remainingHours'] as int?) ?? 0))} Ders Saati) • Filtre: ${_isTeacherView ? _teachers.firstWhere((t) => t['id']?.toString() == _unassignedFilterId, orElse: () => <String, dynamic>{'name': '?'})['name'] : _classes.firstWhere((c) => c['id']?.toString() == _unassignedFilterId, orElse: () => <String, dynamic>{'className': '?'})['className']}'
                      : 'Yerleşemeyen Dersler (${unassigned.fold<int>(0, (sum, item) => sum + ((item['remainingHours'] as int?) ?? 0))} Ders Saati)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_unassignedFilterId != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() => _unassignedFilterId = null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, size: 12, color: Colors.red.shade600),
                        const SizedBox(width: 2),
                        Text(
                          'Filtreyi Kaldır',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.red.shade600,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_unassignedFilterId == null) ...[
                const SizedBox(width: 8),
                Text(
                  '• Dokunup yerleşebileceği yeşil saatleri görün',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: unassigned.length,
                itemBuilder: (context, idx) {
                  final item = unassigned[idx];
                  final isSelected =
                      _selectedUnassignedLesson != null &&
                      _selectedUnassignedLesson!['classId'] ==
                          item['classId'] &&
                      _selectedUnassignedLesson!['lessonId'] ==
                          item['lessonId'];
                  final remaining = item['remainingHours'] as int;
                  final lessonName = item['lessonName'] as String? ?? 'Ders';
                  final className = item['className'] as String? ?? '';
                  final teacherName =
                      (item['teacherNames'] as List?)?.isNotEmpty == true
                      ? item['teacherNames'][0]
                      : (item['teacherName'] ?? '');

                  // Boş slot seğiliyken bu ders o slota gidebilir mi?
                  bool canFitEmpty = false;
                  bool canFitEmptyBlocked = false;
                  if (_selectedEmptySlot != null) {
                    final emptyClassId = _selectedEmptySlot!['classId']
                        ?.toString();
                    final emptyDay = _selectedEmptySlot!['day']?.toString();
                    final emptyHour = _selectedEmptySlot!['hourIndex'];
                    final itemClassId = item['classId']?.toString();
                    if (itemClassId == emptyClassId &&
                        emptyDay != null &&
                        emptyHour != null) {
                      final itemTeacherIds =
                          (item['teacherIds'] as List?)
                              ?.map((e) => e.toString())
                              .toList() ??
                          [];
                      final itemTeacherId = item['teacherId']?.toString();
                      final checkIds = itemTeacherIds.isNotEmpty
                          ? itemTeacherIds
                          : (itemTeacherId != null
                                ? [itemTeacherId]
                                : <String>[]);
                      final slotKey = '${emptyDay}_$emptyHour';
                      bool teacherFree = true;
                      for (var tId in checkIds) {
                        if (_closedSlots['teacher_$tId']?.contains(slotKey) ==
                            true) {
                          teacherFree = false;
                          break;
                        }
                        for (var entry in _scheduleData.values) {
                          if (entry['day'] == emptyDay &&
                              entry['hourIndex'] == emptyHour) {
                            final entTId = entry['teacherId']?.toString();
                            final entTIds = (entry['teacherIds'] as List?)
                                ?.map((e) => e.toString())
                                .toList();
                            if ((entTId != null && entTId == tId) ||
                                (entTIds != null && entTIds.contains(tId))) {
                              teacherFree = false;
                              break;
                            }
                          }
                        }
                        if (!teacherFree) break;
                      }
                      final slotFree =
                          _scheduleData['${emptyClassId}_${emptyDay}_$emptyHour'] ==
                          null;
                      if (teacherFree && slotFree) {
                        // Birleştirilmiş sınıfları kontrol et
                        final mergedClassIds = _getMergedClassIds(item);
                        if (mergedClassIds.length > 1) {
                          bool allPartnersFree = true;
                          for (var partnerId in mergedClassIds) {
                            if (partnerId == emptyClassId) continue;
                            final partnerSlotKey =
                                '${partnerId}_${emptyDay}_$emptyHour';
                            final partnerSlotFree =
                                _scheduleData[partnerSlotKey] == null;
                            final partnerClosed =
                                _closedSlots['class_$partnerId']?.contains(
                                  slotKey,
                                ) ==
                                true;
                            if (!partnerSlotFree || partnerClosed) {
                              allPartnersFree = false;
                              break;
                            }
                          }
                          if (allPartnersFree) {
                            canFitEmpty = true;
                          } else {
                            canFitEmptyBlocked =
                                true; // Başka sınıfta orası uygun deşil ÔåÆ turuncu
                          }
                        } else {
                          canFitEmpty = true;
                        }
                      }
                    }
                  }

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedEmptySlot = null; // Boş slot seğimini kaldır
                        if (isSelected) {
                          _selectedUnassignedLesson = null;
                        } else {
                          _selectedUnassignedLesson = item;
                        }
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.green.shade50
                            : canFitEmpty
                            ? Colors.green.shade50
                            : canFitEmptyBlocked
                            ? Colors.orange.shade50
                            : Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.green.shade500
                              : canFitEmpty
                              ? Colors.green.shade400
                              : canFitEmptyBlocked
                              ? Colors.orange.shade400
                              : Colors.indigo.shade200,
                          width:
                              (isSelected || canFitEmpty || canFitEmptyBlocked)
                              ? 2
                              : 1,
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: isSelected
                                    ? Colors.green.shade200
                                    : canFitEmpty
                                    ? Colors.green.shade100
                                    : Colors.indigo.shade100,
                                child: Text(
                                  lessonName.isNotEmpty
                                      ? lessonName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.green.shade800
                                        : canFitEmpty
                                        ? Colors.green.shade700
                                        : Colors.indigo.shade800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    lessonName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.green.shade900
                                          : Colors.grey.shade900,
                                    ),
                                  ),
                                  Text(
                                    '$className • $teacherName',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isSelected
                                          ? Colors.green.shade700
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),
                            ],
                          ),
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.green.shade600
                                    : Colors.red.shade600,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              child: Center(
                                child: Text(
                                  '$remaining',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.class_, size: 64, color: Colors.grey.shade400),
          SizedBox(height: 16),
          Text(
            'Henüz şube tanımlanmamış',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'Önce şube ekleyin',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Sabit yarim gun kartini grid'de gosterir
  /// Esnek ogretmenler icin null dondurur (grid'de gosterilmez, filtre bannerinda gosterilir)
  String? _getTeacherHalfDaySession(String teacherId, String day) {
    final prefix = 'teacher_$teacherId';
    final morningKey = '${prefix}_morning';
    final afternoonKey = '${prefix}_afternoon';

    // Esnek yarim gun: grid'e koyma (banner ile gosterilir)
    // Hem morning hem afternoon esnek kontrolu
    final isMorningFlex = _halfDayFlexible.contains(morningKey);
    final isAfternoonFlex = _halfDayFlexible.contains(afternoonKey);

    // Gunde sabite bakiyoruz, ama esnek ise o session'i gosterme
    if (!isMorningFlex &&
        _halfDayAssignedDays.containsKey(morningKey) &&
        _halfDayAssignedDays[morningKey] == day) return 'morning';
    if (!isAfternoonFlex &&
        _halfDayAssignedDays.containsKey(afternoonKey) &&
        _halfDayAssignedDays[afternoonKey] == day) return 'afternoon';
    return null;
  }


  /// Yarim gun seans saatlerini dondurur
  List<int> _getHalfDayHours(String session) =>
      session == 'morning' ? _halfDayMorningHours : _halfDayAfternoonHours;

  /// Sabit yarim gun kartini olusturur (grid'de gosterilir, esnek olanlar gosterilmez)
  Widget _buildHalfDayCard(
    String session,
    double cellWidth,
    double cellHeight, {
    String? teacherId,
  }) {
    final hours = _getHalfDayHours(session);
    final span = hours.length;
    if (span == 0) return SizedBox(width: 0, height: cellHeight);

    final isMorning = session == 'morning';
    final bgColor = isMorning
        ? const Color(0xFFE07B00)
        : const Color(0xFF0D7377);
    final borderColor = isMorning
        ? const Color(0xFFFF9900)
        : const Color(0xFF14FFEC).withValues(alpha: 0.4);
    final iconData = isMorning
        ? Icons.wb_sunny_rounded
        : Icons.brightness_3_rounded;
    final title = isMorning ? 'SABAH YARIM GÜN İZNİ' : 'ÖĞLEDEN SONRA İZNİ';
    final hourStart = hours.isNotEmpty ? hours.first + 1 : 1;
    final hourEnd = hours.isNotEmpty ? hours.last + 1 : span;
    final subtitle = '$span Ders İzin ($hourStart-$hourEnd. Saatler)';

    // Piksel tasmasi olmamasi icin ClipRect ile sar
    return ClipRect(
      child: SizedBox(
        width: cellWidth * span,
        height: cellHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 1),
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(iconData, size: 12, color: Colors.white),
                          const SizedBox(height: 1),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 7.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.1,
                              letterSpacing: 0.3,
                            ),
                          ),
                          Text(
                            subtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 6.5,
                              color: Colors.white70,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Sol ust: SABİT rozeti (kilitli oldugunu belirtir)
                Positioned(
                  left: 3,
                  top: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded, size: 7, color: Colors.white),
                        SizedBox(width: 2),
                        Text(
                          'SABİT',
                          style: TextStyle(
                            fontSize: 6,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // X butonu - atanmis gunu kaldirir ve Firestore'a kaydeder
                if (teacherId != null && !widget.isViewingPastTerm)
                  Positioned(
                    right: 3,
                    top: 3,
                    child: GestureDetector(
                      onTap: () async {
                        setState(() {
                          _halfDayAssignedDays
                              .remove('teacher_${teacherId}_morning');
                          _halfDayAssignedDays
                              .remove('teacher_${teacherId}_afternoon');
                        });
                        // Firestore'a kaydet
                        try {
                          await FirebaseFirestore.instance
                              .collection('workPeriods')
                              .doc(widget.periodId)
                              .set({
                                'scheduleSettings': {
                                  'halfDayAssignedDays': _halfDayAssignedDays,
                                },
                              }, SetOptions(merge: true));
                        } catch (e) {
                          print('halfDay remove save error: $e');
                        }
                      },
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 9,
                          color: Colors.white,
                        ),
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

  Widget _buildScheduleGrid() {
    if (_lessonHours.isEmpty) {
      if (_isLoading) {
        return const Center(
          child: CircularProgressIndicator(
            color: Colors.orange,
          ), // Sadece spinner gİster
        );
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time, size: 64, color: Colors.orange.shade300),
            const SizedBox(height: 16),
            Text(
              'Bu dönem için ders saati tanımlanmamış',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Önce "Ders Saatleri" bölümünden ders saatlerini tanımlayın',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final cellHeight = 38.0;
    final headerHeight = 60.0;
    final rowHeaderWidth = _isTeacherView ? 115.0 : 65.0;
    final rows = _isTeacherView ? _teachers : _classes;

    int getHourCountForDay(String day) {
      return _dailyLessonCounts[day] ?? _lessonHours.length;
    }

    // Seğili ders bilgileri (yerleşemeyen veya mevcut atanmış ders)
    final _activeSelection = _selectedUnassignedLesson;
    final targetClassId = _activeSelection?['classId']?.toString();
    final targetClassName = _activeSelection?['className']?.toString();
    final targetTeacherId = _activeSelection?['teacherId']?.toString();
    final targetTeacherIds =
        (_activeSelection?['teacherIds'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        (targetTeacherId != null ? [targetTeacherId] : []);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - rowHeaderWidth;
        int totalHours = 0;
        for (var d in _days) {
          totalHours += getHourCountForDay(d);
        }
        final double totalBorderWidth = _days.length * 2.0;
        final double netAvailableWidth =
            (availableWidth - totalBorderWidth - 1.0).clamp(
              0.0,
              double.infinity,
            );
        final double cellWidth = _isFitToScreen && totalHours > 0
            ? (netAvailableWidth / totalHours).clamp(16.0, 120.0)
            : 50.0;

        double totalWidth = 0;
        for (var day in _days) {
          totalWidth += getHourCountForDay(day) * cellWidth + 2;
        }
        if (_isFitToScreen) {
          totalWidth = availableWidth;
        }

        return Row(
          children: [
            // Sol sütun - Şube veya üşretmen başlışı ve isimleri
            Column(
              children: [
                Container(
                  width: rowHeaderWidth,
                  height: headerHeight,
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    border: Border(
                      right: BorderSide(color: Colors.grey.shade300),
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _isTeacherView ? 'Öğretmen' : 'Şube',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: rowHeaderWidth,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border(
                        right: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: ListView.builder(
                      controller: _verticalScrollController,
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final rowData = rows[index];
                        final name = _isTeacherView
                            ? (rowData['name'] ?? 'Öğretmen')
                            : (rowData['className'] ?? 'Şube');
                        final rowId = rowData['id']?.toString() ?? '';

                        // Bu şube/İşretmenin atanacak dersi kaldı mı?
                        bool hasRemainingLessons = false;
                        if (_isTeacherView) {
                          // üşretmen: bu İşretmenin dersi olan sınıflarda kalan saat var mı?
                          for (var entry in _classLessons.entries) {
                            for (var lesson in entry.value) {
                              final tIds =
                                  (lesson['teacherIds'] as List?)
                                      ?.map((e) => e.toString())
                                      .toList() ??
                                  [];
                              final tId = lesson['teacherId']?.toString();
                              if (tIds.contains(rowId) || tId == rowId) {
                                final lessonKey =
                                    '${entry.key}_${lesson['lessonId']}';
                                if ((_remainingHours[lessonKey] ?? 0) > 0) {
                                  hasRemainingLessons = true;
                                  break;
                                }
                              }
                            }
                            if (hasRemainingLessons) break;
                          }
                        } else {
                          // Sınıf: bu sınıfın kalan ders saati var mı?
                          final classLessons = _classLessons[rowId] ?? [];
                          for (var lesson in classLessons) {
                            final lessonKey = '${rowId}_${lesson['lessonId']}';
                            if ((_remainingHours[lessonKey] ?? 0) > 0) {
                              hasRemainingLessons = true;
                              break;
                            }
                          }
                        }

                        final isFilterSelected = _unassignedFilterId == rowId;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (_unassignedFilterId == rowId) {
                                _unassignedFilterId = null;
                              } else {
                                _unassignedFilterId = rowId;
                              }
                            });
                          },
                          child: Container(
                            height: cellHeight,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: isFilterSelected
                                  ? Colors.indigo.shade50
                                  : (index % 2 == 0
                                        ? Colors.white
                                        : Colors.grey.shade50),
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade200),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: isFilterSelected
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                  fontSize: 11,
                                  color: hasRemainingLessons
                                      ? Colors.red.shade700
                                      : isFilterSelected
                                      ? Colors.indigo.shade800
                                      : Colors.grey.shade800,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),

            // Saş taraf - Günler/saatler ve program hücreleri
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                  },
                ),
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: _isFitToScreen
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  child: SizedBox(
                    width: totalWidth,
                    child: Column(
                      children: [
                        // İst başlık satırı (Günler ve Saatler)
                        Container(
                          height: headerHeight,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Row(
                            children: _days.map((day) {
                              final dayHourCount = getHourCountForDay(day);
                              return Container(
                                width: dayHourCount * cellWidth + 2,
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                      color: Colors.grey.shade300,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: Colors.purple.shade100,
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Colors.purple.shade200,
                                          ),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          day,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.purple.shade800,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Row(
                                        children: List.generate(dayHourCount, (
                                          hourIndex,
                                        ) {
                                          final dayHours =
                                              _dayLessonTimes[day] ??
                                              _lessonHours;
                                          final hour =
                                              hourIndex < dayHours.length
                                              ? dayHours[hourIndex]
                                              : null;
                                          final startTime =
                                              hour?['startTime'] ?? '';
                                          final hourNumber = hourIndex + 1;
                                          return Container(
                                            width: cellWidth,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade50,
                                              border: Border(
                                                right: BorderSide(
                                                  color: Colors.grey.shade200,
                                                ),
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  startTime.toString(),
                                                  style: TextStyle(
                                                    fontSize: 8,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                                Text(
                                                  '$hourNumber',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 10,
                                                    color: Colors.grey.shade800,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        // Program Hücreleri
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification is ScrollUpdateNotification) {
                                if (_verticalScrollController.hasClients) {
                                  _verticalScrollController.jumpTo(
                                    notification.metrics.pixels,
                                  );
                                }
                              }
                              return true;
                            },
                            child: ListView.builder(
                              itemCount: rows.length,
                              itemBuilder: (context, rowIndex) {
                                final rowData = rows[rowIndex];
                                final rowId = rowData['id'] as String;

                                return Container(
                                  height: cellHeight,
                                  decoration: BoxDecoration(
                                    color: rowIndex % 2 == 0
                                        ? Colors.white
                                        : Colors.grey.shade50,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: _days.map((day) {
                                      final dayHourCount = getHourCountForDay(
                                        day,
                                      );
                                      return Container(
                                        width: dayHourCount * cellWidth + 2,
                                        decoration: BoxDecoration(
                                          border: Border(
                                            right: BorderSide(
                                              color: Colors.grey.shade300,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: List.generate(dayHourCount, (
                                            hourIndex,
                                          ) {
                                            // Hücre atamasını bul
                                            Map<String, dynamic>? assignment;
                                            if (!_isTeacherView) {
                                              assignment =
                                                  _scheduleData['${rowId}_${day}_$hourIndex'];
                                            } else {
                                              for (var data
                                                  in _scheduleData.values) {
                                                if (data['day'] == day &&
                                                    data['hourIndex'] ==
                                                        hourIndex) {
                                                  final tId = data['teacherId']
                                                      ?.toString();
                                                  final tIds =
                                                      (data['teacherIds']
                                                              as List?)
                                                          ?.map(
                                                            (e) => e.toString(),
                                                          )
                                                          .toList();
                                                  if (tId == rowId ||
                                                      (tIds != null &&
                                                          tIds.contains(
                                                            rowId,
                                                          ))) {
                                                    assignment = data;
                                                    break;
                                                  }
                                                }
                                              }
                                            }

                                            // Kapalı slot kontrolü
                                            final slotKey = '${day}_$hourIndex';
                                            final cellClassId = !_isTeacherView
                                                ? rowId
                                                : (assignment?['classId']
                                                          ?.toString() ??
                                                      targetClassId ??
                                                      '');
                                            final isClassClosed =
                                                _closedSlots['class_$cellClassId']
                                                    ?.contains(slotKey) ??
                                                false;

                                            // Bu hücre veya seğili ders iğin İşretmen kapalı mı?
                                            final Set<String>
                                            relevantTeacherIds = {};
                                            if (assignment != null) {
                                              if (assignment['teacherId'] !=
                                                  null)
                                                relevantTeacherIds.add(
                                                  assignment['teacherId']
                                                      .toString(),
                                                );
                                              if (assignment['teacherIds'] !=
                                                  null) {
                                                relevantTeacherIds.addAll(
                                                  (assignment['teacherIds']
                                                          as List)
                                                      .map((e) => e.toString()),
                                                );
                                              }
                                            }
                                            if (_isTeacherView) {
                                              relevantTeacherIds.add(rowId);
                                            }

                                            final isTargetRow = !_isTeacherView
                                                ? rowId == targetClassId
                                                : (targetTeacherIds.contains(
                                                    rowId,
                                                  ));

                                            if (_selectedUnassignedLesson !=
                                                    null &&
                                                isTargetRow) {
                                              relevantTeacherIds.addAll(
                                                targetTeacherIds,
                                              );
                                            }

                                            bool isTeacherClosed = false;
                                            for (var t in relevantTeacherIds) {
                                              if (_closedSlots['teacher_$t']
                                                      ?.contains(slotKey) ==
                                                  true) {
                                                isTeacherClosed = true;
                                                break;
                                              }
                                            }

                                            final isClosed =
                                                isClassClosed ||
                                                isTeacherClosed;

                                            // Yarim gun kontrolu (sadece ogretmen gorunumunde)
                                            final String? halfDaySession =
                                                _isTeacherView
                                                ? _getTeacherHalfDaySession(
                                                    rowId,
                                                    day,
                                                  )
                                                : null;
                                            final bool isHalfDay =
                                                halfDaySession != null &&
                                                _getHalfDayHours(
                                                  halfDaySession,
                                                ).contains(hourIndex);
                                            // Birlesik yarim gun karti sadece ilk saatte gosterilir
                                            final bool isHalfDayFirst =
                                                isHalfDay &&
                                                _getHalfDayHours(
                                                  halfDaySession!,
                                                ).isNotEmpty &&
                                                _getHalfDayHours(
                                                      halfDaySession,
                                                    ).first ==
                                                    hourIndex;
                                            final bool isHalfDayNonFirst =
                                                isHalfDay && !isHalfDayFirst;

                                            // önteraktif yeşil & turuncu vurgu hesabı
                                            bool isHighlightGreen = false;
                                            bool isHighlightOrange = false;
                                            if (_selectedUnassignedLesson !=
                                                    null &&
                                                targetClassId != null &&
                                                !isClosed &&
                                                isTargetRow) {
                                              final classFree =
                                                  _scheduleData['${targetClassId}_${day}_$hourIndex'] ==
                                                  null;
                                              bool teachersFree = true;
                                              for (var entry
                                                  in _scheduleData.values) {
                                                if (entry['day'] == day &&
                                                    entry['hourIndex'] ==
                                                        hourIndex) {
                                                  final entTId =
                                                      entry['teacherId']
                                                          ?.toString();
                                                  final entTIds =
                                                      (entry['teacherIds']
                                                              as List?)
                                                          ?.map(
                                                            (e) => e.toString(),
                                                          )
                                                          .toList();
                                                  if ((entTId != null &&
                                                          targetTeacherIds
                                                              .contains(
                                                                entTId,
                                                              )) ||
                                                      (entTIds != null &&
                                                          entTIds.any(
                                                            (t) =>
                                                                targetTeacherIds
                                                                    .contains(
                                                                      t,
                                                                    ),
                                                          ))) {
                                                    teachersFree = false;
                                                    break;
                                                  }
                                                }
                                              }
                                              if (classFree && teachersFree) {
                                                isHighlightGreen = true;
                                              } else if (!classFree &&
                                                  teachersFree) {
                                                // üşretmen müsait ama şube dolu ÔåÆ turuncu vurgu
                                                isHighlightOrange = true;
                                              }
                                            }

                                            // Turuncu hücre iğin şubenin o saatteki dersini bul
                                            Map<String, dynamic>?
                                            classAssignment;
                                            if (isHighlightOrange &&
                                                targetClassId != null) {
                                              classAssignment =
                                                  _scheduleData['${targetClassId}_${day}_$hourIndex'];
                                              if (classAssignment == null) {
                                                // birleştirilmiş sınıf olabilir, values üzerinden ara
                                                for (var d
                                                    in _scheduleData.values) {
                                                  if (d['day'] == day &&
                                                      d['hourIndex'] ==
                                                          hourIndex &&
                                                      d['classId']
                                                              ?.toString() ==
                                                          targetClassId) {
                                                    classAssignment = d;
                                                    break;
                                                  }
                                                }
                                              }
                                            }

                                            // Yarim gun hucre render mantigi
                                            if (isHalfDayNonFirst) {
                                              return SizedBox(
                                                width: 0,
                                                height: cellHeight,
                                              );
                                            }
                                            if (isHalfDayFirst) {
                                              return _buildHalfDayCard(
                                                halfDaySession!,
                                                cellWidth,
                                                cellHeight,
                                                teacherId: rowId,
                                              );
                                            }

                                            return GestureDetector(
                                              onTap: widget.isViewingPastTerm
                                                  ? null
                                                  : () {
                                                      // 1) Yerleşemeyen ders seğiliyse ÔåÆ boş hücreye ata veya dolu hücreye ğift tıkla
                                                      if (_selectedUnassignedLesson !=
                                                              null &&
                                                          _selectedUnassignedLesson!['_isAssignedSelection'] !=
                                                              true) {
                                                        if (isHighlightGreen) {
                                                          _assignLesson(
                                                            targetClassId!,
                                                            day,
                                                            hourIndex,
                                                            _selectedUnassignedLesson!,
                                                            targetClassName ??
                                                                'Sınıf',
                                                          );
                                                          final remaining =
                                                              _remainingHours['${targetClassId}_${_selectedUnassignedLesson!['lessonId']}'] ??
                                                              0;
                                                          if (remaining <= 0) {
                                                            setState(
                                                              () =>
                                                                  _selectedUnassignedLesson =
                                                                      null,
                                                            );
                                                          }
                                                        } else if (assignment !=
                                                            null) {
                                                          // Dolu hücreye tıklandı ÔåÆ seğimi bu hücredeki derse geğir
                                                          final classIdForSelection =
                                                              !_isTeacherView
                                                              ? rowId
                                                              : (assignment['classId']
                                                                        ?.toString() ??
                                                                    '');
                                                          final classNameForSelection =
                                                              _classes.firstWhere(
                                                                    (c) =>
                                                                        c['id'] ==
                                                                        classIdForSelection,
                                                                    orElse: () =>
                                                                        <
                                                                          String,
                                                                          dynamic
                                                                        >{
                                                                          'className':
                                                                              'Sınıf',
                                                                        },
                                                                  )['className']
                                                                  as String;
                                                          setState(() {
                                                            _selectedEmptySlot =
                                                                null;
                                                            _selectedUnassignedLesson = {
                                                              ...assignment!,
                                                              'classId':
                                                                  classIdForSelection,
                                                              'className':
                                                                  classNameForSelection,
                                                              '_isAssignedSelection':
                                                                  true,
                                                            };
                                                          });
                                                        }
                                                        return;
                                                      }

                                                      // 2) Atanmış ders seğiliyse ÔåÆ boş hücreye taşı veya dolu hücreye geğ
                                                      if (_selectedUnassignedLesson !=
                                                              null &&
                                                          _selectedUnassignedLesson!['_isAssignedSelection'] ==
                                                              true) {
                                                        if (isHighlightGreen) {
                                                          // Boş hücreye tıklandı ÔåÆ taşı
                                                          final origDay =
                                                              _selectedUnassignedLesson!['day']
                                                                  ?.toString();
                                                          final origHour =
                                                              _selectedUnassignedLesson!['hourIndex'];
                                                          final origClassId =
                                                              _selectedUnassignedLesson!['classId']
                                                                  ?.toString();
                                                          if (origDay != null &&
                                                              origHour !=
                                                                  null &&
                                                              origClassId !=
                                                                  null) {
                                                            final origKey =
                                                                '${origClassId}_${origDay}_$origHour';
                                                            final origAssignment =
                                                                _scheduleData[origKey];
                                                            if (origAssignment !=
                                                                null) {
                                                              _quickRemoveAssignment(
                                                                origClassId,
                                                                origDay,
                                                                origHour is int
                                                                    ? origHour
                                                                    : int.tryParse(
                                                                            origHour.toString(),
                                                                          ) ??
                                                                          0,
                                                                origAssignment,
                                                              );
                                                            }
                                                          }
                                                          _assignLesson(
                                                            targetClassId!,
                                                            day,
                                                            hourIndex,
                                                            _selectedUnassignedLesson!,
                                                            targetClassName ??
                                                                'Sınıf',
                                                          );
                                                          setState(
                                                            () =>
                                                                _selectedUnassignedLesson =
                                                                    null,
                                                          );
                                                          return;
                                                        } else if (assignment !=
                                                            null) {
                                                          // Dolu hücreye tıklandı ÔåÆ aynıysa seğimi kaldır, farklıysa ona geğ
                                                          final isSameCell =
                                                              _selectedUnassignedLesson!['day'] ==
                                                                  day &&
                                                              _selectedUnassignedLesson!['hourIndex'] ==
                                                                  hourIndex &&
                                                              isTargetRow;
                                                          if (isSameCell) {
                                                            setState(
                                                              () =>
                                                                  _selectedUnassignedLesson =
                                                                      null,
                                                            );
                                                          } else {
                                                            final classIdForSelection =
                                                                !_isTeacherView
                                                                ? rowId
                                                                : (assignment['classId']
                                                                          ?.toString() ??
                                                                      '');
                                                            final classNameForSelection =
                                                                _classes.firstWhere(
                                                                      (c) =>
                                                                          c['id'] ==
                                                                          classIdForSelection,
                                                                      orElse: () =>
                                                                          <
                                                                            String,
                                                                            dynamic
                                                                          >{
                                                                            'className':
                                                                                'Sınıf',
                                                                          },
                                                                    )['className']
                                                                    as String;
                                                            setState(() {
                                                              _selectedEmptySlot =
                                                                  null;
                                                              _selectedUnassignedLesson = {
                                                                ...assignment!,
                                                                'classId':
                                                                    classIdForSelection,
                                                                'className':
                                                                    classNameForSelection,
                                                                '_isAssignedSelection':
                                                                    true,
                                                              };
                                                            });
                                                          }
                                                          return;
                                                        }
                                                      }

                                                      // 3) Seğim yokken tıklama
                                                      if (assignment != null) {
                                                        // Dolu hücre ÔåÆ seğ
                                                        final classIdForSelection =
                                                            !_isTeacherView
                                                            ? rowId
                                                            : (assignment['classId']
                                                                      ?.toString() ??
                                                                  '');
                                                        final classNameForSelection =
                                                            _classes.firstWhere(
                                                                  (c) =>
                                                                      c['id'] ==
                                                                      classIdForSelection,
                                                                  orElse: () =>
                                                                      <
                                                                        String,
                                                                        dynamic
                                                                      >{
                                                                        'className':
                                                                            'Sınıf',
                                                                      },
                                                                )['className']
                                                                as String;
                                                        setState(() {
                                                          _selectedEmptySlot =
                                                              null;
                                                          _selectedUnassignedLesson = {
                                                            ...assignment!,
                                                            'classId':
                                                                classIdForSelection,
                                                            'className':
                                                                classNameForSelection,
                                                            '_isAssignedSelection':
                                                                true,
                                                          };
                                                        });
                                                      } else {
                                                        // Boş hücre
                                                        final targetCId =
                                                            !_isTeacherView
                                                            ? rowId
                                                            : (assignment?['classId']
                                                                      ?.toString() ??
                                                                  _classes
                                                                      .first['id']);

                                                        if (_hasAutoDistributed) {
                                                          final isSameSlot =
                                                              _selectedEmptySlot !=
                                                                  null &&
                                                              _selectedEmptySlot!['classId'] ==
                                                                  targetCId &&
                                                              _selectedEmptySlot!['day'] ==
                                                                  day &&
                                                              _selectedEmptySlot!['hourIndex'] ==
                                                                  hourIndex;

                                                          if (isSameSlot) {
                                                            setState(
                                                              () =>
                                                                  _selectedEmptySlot =
                                                                      null,
                                                            );
                                                            _showLessonPicker(
                                                              targetCId,
                                                              day,
                                                              hourIndex,
                                                            );
                                                          } else {
                                                            setState(() {
                                                              _selectedEmptySlot = {
                                                                'classId':
                                                                    targetCId,
                                                                'day': day,
                                                                'hourIndex':
                                                                    hourIndex,
                                                              };
                                                            });
                                                          }
                                                        } else {
                                                          _showLessonPicker(
                                                            targetCId,
                                                            day,
                                                            hourIndex,
                                                          );
                                                        }
                                                      }
                                                    },
                                              onDoubleTap:
                                                  widget.isViewingPastTerm
                                                  ? null
                                                  : () {
                                                      if (assignment != null &&
                                                          _selectedUnassignedLesson ==
                                                              null) {
                                                        // çift tıklama: dersi kaldır
                                                        _quickRemoveAssignment(
                                                          rowId,
                                                          day,
                                                          hourIndex,
                                                          assignment!,
                                                        );
                                                      } else if (assignment !=
                                                              null &&
                                                          _selectedUnassignedLesson !=
                                                              null &&
                                                          (isHighlightOrange ||
                                                              !isHighlightGreen)) {
                                                        // Seğim var + dolu hücreye ğift tıklama ÔåÆ mevcut dersi kaldır, seğili dersi yerleştir
                                                        final isMoving =
                                                            _selectedUnassignedLesson!['_isAssignedSelection'] ==
                                                            true;

                                                        // ünce hedef hücredeki dersi kaldır
                                                        _quickRemoveAssignment(
                                                          rowId,
                                                          day,
                                                          hourIndex,
                                                          assignment!,
                                                        );

                                                        // Eşer atanmış ders taşınıyorsa, eski konumdan da kaldır
                                                        if (isMoving) {
                                                          final origDay =
                                                              _selectedUnassignedLesson!['day']
                                                                  ?.toString();
                                                          final origHour =
                                                              _selectedUnassignedLesson!['hourIndex'];
                                                          final origClassId =
                                                              _selectedUnassignedLesson!['classId']
                                                                  ?.toString();
                                                          if (origDay != null &&
                                                              origHour !=
                                                                  null &&
                                                              origClassId !=
                                                                  null) {
                                                            final origKey =
                                                                '${origClassId}_${origDay}_$origHour';
                                                            final origAssignment =
                                                                _scheduleData[origKey];
                                                            if (origAssignment !=
                                                                null) {
                                                              _quickRemoveAssignment(
                                                                origClassId,
                                                                origDay,
                                                                origHour is int
                                                                    ? origHour
                                                                    : int.tryParse(
                                                                            origHour.toString(),
                                                                          ) ??
                                                                          0,
                                                                origAssignment,
                                                              );
                                                            }
                                                          }
                                                        }

                                                        // Yeni konuma yerleştir
                                                        final selClassId =
                                                            _selectedUnassignedLesson!['classId']
                                                                ?.toString();
                                                        if (selClassId !=
                                                            null) {
                                                          _assignLesson(
                                                            selClassId,
                                                            day,
                                                            hourIndex,
                                                            _selectedUnassignedLesson!,
                                                            _selectedUnassignedLesson!['className'] ??
                                                                'Sınıf',
                                                          );
                                                          setState(
                                                            () =>
                                                                _selectedUnassignedLesson =
                                                                    null,
                                                          );
                                                        }
                                                      }
                                                    },
                                              child: Builder(
                                                builder: (context) {
                                                  // Seğilen kaynak hücre mi?
                                                  final isSelectedSource =
                                                      _selectedUnassignedLesson !=
                                                          null &&
                                                      _selectedUnassignedLesson!['_isAssignedSelection'] ==
                                                          true &&
                                                      assignment != null &&
                                                      _selectedUnassignedLesson!['day'] ==
                                                          day &&
                                                      _selectedUnassignedLesson!['hourIndex'] ==
                                                          hourIndex &&
                                                      _selectedUnassignedLesson!['lessonId'] ==
                                                          assignment!['lessonId'] &&
                                                      isTargetRow;

                                                  // Boş slot seğili mi?
                                                  final isSelectedEmptySlot =
                                                      _selectedEmptySlot !=
                                                          null &&
                                                      assignment == null &&
                                                      !isClosed &&
                                                      _selectedEmptySlot!['day'] ==
                                                          day &&
                                                      _selectedEmptySlot!['hourIndex'] ==
                                                          hourIndex &&
                                                      ((!_isTeacherView &&
                                                              rowId ==
                                                                  _selectedEmptySlot!['classId']) ||
                                                          (_isTeacherView &&
                                                              targetClassId ==
                                                                  _selectedEmptySlot!['classId']));

                                                  // Kardeş ders mi? (aynı sınıf+ders, farklı saat)
                                                  final isSiblingLesson =
                                                      !isSelectedSource &&
                                                      _selectedUnassignedLesson !=
                                                          null &&
                                                      assignment != null &&
                                                      isTargetRow &&
                                                      assignment!['lessonId'] ==
                                                          _selectedUnassignedLesson!['lessonId'];

                                                  // Bu dolu hücredeki ders, seğili boş slota gidebilir mi?
                                                  bool canFitInEmptySlot =
                                                      false;
                                                  bool
                                                  canFitInEmptySlotBlocked =
                                                      false;
                                                  if (_selectedEmptySlot !=
                                                          null &&
                                                      assignment != null &&
                                                      !isSelectedEmptySlot) {
                                                    final emptyClassId =
                                                        _selectedEmptySlot!['classId']
                                                            ?.toString();
                                                    final emptyDay =
                                                        _selectedEmptySlot!['day']
                                                            ?.toString();
                                                    final emptyHour =
                                                        _selectedEmptySlot!['hourIndex'];
                                                    // Dersin classId'si seğili boş slotun classId'siyle eşleşmeli
                                                    final assignClassId =
                                                        assignment!['classId']
                                                            ?.toString() ??
                                                        (!_isTeacherView
                                                            ? rowId
                                                            : '');
                                                    if (assignClassId ==
                                                            emptyClassId &&
                                                        emptyDay != null &&
                                                        emptyHour != null) {
                                                      // üşretmen boş mu kontrol et
                                                      final aTeacherId =
                                                          assignment['teacherId']
                                                              ?.toString();
                                                      final aTeacherIds =
                                                          (assignment['teacherIds']
                                                                  as List?)
                                                              ?.map(
                                                                (e) => e
                                                                    .toString(),
                                                              )
                                                              .toList() ??
                                                          [];
                                                      final slotKey =
                                                          '${emptyDay}_$emptyHour';
                                                      bool teacherFreeAtEmpty =
                                                          true;
                                                      final checkIds =
                                                          aTeacherIds.isNotEmpty
                                                          ? aTeacherIds
                                                          : (aTeacherId != null
                                                                ? [aTeacherId]
                                                                : <String>[]);
                                                      for (var tId
                                                          in checkIds) {
                                                        // üşretmen kapalı mı?
                                                        if (_closedSlots['teacher_$tId']
                                                                ?.contains(
                                                                  slotKey,
                                                                ) ==
                                                            true) {
                                                          teacherFreeAtEmpty =
                                                              false;
                                                          break;
                                                        }
                                                        // üşretmen o saatte başka derste mi?
                                                        for (var entry
                                                            in _scheduleData
                                                                .values) {
                                                          if (entry['day'] ==
                                                                  emptyDay &&
                                                              entry['hourIndex'] ==
                                                                  emptyHour) {
                                                            final entTId =
                                                                entry['teacherId']
                                                                    ?.toString();
                                                            final entTIds =
                                                                (entry['teacherIds']
                                                                        as List?)
                                                                    ?.map(
                                                                      (e) => e
                                                                          .toString(),
                                                                    )
                                                                    .toList();
                                                            if ((entTId !=
                                                                        null &&
                                                                    entTId ==
                                                                        tId) ||
                                                                (entTIds !=
                                                                        null &&
                                                                    entTIds
                                                                        .contains(
                                                                          tId,
                                                                        ))) {
                                                              teacherFreeAtEmpty =
                                                                  false;
                                                              break;
                                                            }
                                                          }
                                                        }
                                                        if (!teacherFreeAtEmpty)
                                                          break;
                                                      }
                                                      // Sınıf boş mu kontrol et
                                                      final emptySlotFree =
                                                          _scheduleData['${emptyClassId}_${emptyDay}_$emptyHour'] ==
                                                          null;
                                                      if (teacherFreeAtEmpty &&
                                                          emptySlotFree) {
                                                        // Birleştirilmiş sınıflar varsa dişer sınıflar da o saatte boş mu kontrol et
                                                        final mergedClassIds =
                                                            _getMergedClassIds(
                                                              assignment,
                                                            );
                                                        if (mergedClassIds
                                                                .length >
                                                            1) {
                                                          bool allPartnersFree =
                                                              true;
                                                          for (var partnerId
                                                              in mergedClassIds) {
                                                            if (partnerId ==
                                                                emptyClassId)
                                                              continue;
                                                            final partnerSlotKey =
                                                                '${partnerId}_${emptyDay}_$emptyHour';
                                                            final partnerSlotFree =
                                                                _scheduleData[partnerSlotKey] ==
                                                                null;
                                                            final partnerClosed =
                                                                _closedSlots['class_$partnerId']
                                                                    ?.contains(
                                                                      slotKey,
                                                                    ) ==
                                                                true;
                                                            if (!partnerSlotFree ||
                                                                partnerClosed) {
                                                              allPartnersFree =
                                                                  false;
                                                              break;
                                                            }
                                                          }
                                                          if (allPartnersFree) {
                                                            canFitInEmptySlot =
                                                                true;
                                                          } else {
                                                            canFitInEmptySlotBlocked =
                                                                true; // Başka sınıfta orası uygun deşil ÔåÆ turuncuya dİn
                                                          }
                                                        } else {
                                                          canFitInEmptySlot =
                                                              true;
                                                        }
                                                      }
                                                    }
                                                  }

                                                  final dynamicFontSize =
                                                      cellWidth < 36
                                                      ? 7.5
                                                      : (cellWidth < 46
                                                            ? 8.0
                                                            : 9.0);

                                                  return Container(
                                                    width: cellWidth - 4,
                                                    height: cellHeight - 4,
                                                    margin:
                                                        const EdgeInsets.all(2),
                                                    decoration: BoxDecoration(
                                                      color: isSelectedSource
                                                          ? Colors
                                                                .orange
                                                                .shade100
                                                          : isSiblingLesson
                                                          ? Colors
                                                                .indigo
                                                                .shade400
                                                          : isSelectedEmptySlot
                                                          ? Colors.blue.shade100
                                                          : (isHighlightGreen
                                                                ? Colors
                                                                      .green
                                                                      .shade100
                                                                : (isHighlightOrange
                                                                      ? Colors
                                                                            .green
                                                                            .shade100
                                                                      : (canFitInEmptySlot
                                                                            ? Colors.green.shade100
                                                                            : (canFitInEmptySlotBlocked
                                                                                  ? Colors.orange.shade100
                                                                                  : (isClosed
                                                                                        ? Colors.blueGrey.shade700
                                                                                        : (assignment != null
                                                                                              ? Colors.red.shade500
                                                                                              : Colors.grey.shade100)))))),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      border: Border.all(
                                                        color: isSelectedSource
                                                            ? Colors
                                                                  .orange
                                                                  .shade700
                                                            : isSiblingLesson
                                                            ? Colors
                                                                  .indigo
                                                                  .shade700
                                                            : isSelectedEmptySlot
                                                            ? Colors
                                                                  .blue
                                                                  .shade600
                                                            : (isHighlightGreen
                                                                  ? Colors
                                                                        .green
                                                                        .shade600
                                                                  : (isHighlightOrange
                                                                        ? Colors
                                                                              .green
                                                                              .shade600
                                                                        : (canFitInEmptySlot
                                                                              ? Colors.green.shade600
                                                                              : (canFitInEmptySlotBlocked
                                                                                    ? Colors.orange.shade600
                                                                                    : (isClosed
                                                                                          ? Colors.blueGrey.shade900
                                                                                          : (assignment != null
                                                                                                ? Colors.red.shade700
                                                                                                : Colors.grey.shade300)))))),
                                                        width:
                                                            (isSelectedSource ||
                                                                isSiblingLesson ||
                                                                isSelectedEmptySlot ||
                                                                isHighlightGreen ||
                                                                isHighlightOrange ||
                                                                canFitInEmptySlot ||
                                                                canFitInEmptySlotBlocked)
                                                            ? 2.5
                                                            : 1,
                                                      ),
                                                    ),
                                                    child: Stack(
                                                      children: [
                                                        Center(
                                                          child:
                                                              isHighlightGreen
                                                              ? Icon(
                                                                  Icons
                                                                      .add_circle_rounded,
                                                                  size:
                                                                      cellWidth <
                                                                          35
                                                                      ? 11
                                                                      : 14,
                                                                  color: Colors
                                                                      .green
                                                                      .shade800,
                                                                )
                                                              : (isHighlightOrange
                                                                    ? Text(
                                                                        _isTeacherView
                                                                            ? (cellWidth <
                                                                                      36
                                                                                  ? _getShortName(
                                                                                      classAssignment?['lessonName'] ??
                                                                                          assignment?['lessonName'] ??
                                                                                          '',
                                                                                    )
                                                                                  : '${_getShortName(classAssignment?['lessonName'] ?? assignment?['lessonName'] ?? '')}\n${_resolveClassName(classAssignment ?? assignment ?? {})}')
                                                                            : _getShortName(
                                                                                classAssignment?['lessonName'] ??
                                                                                    assignment?['lessonName'] ??
                                                                                    '',
                                                                              ),
                                                                        style: TextStyle(
                                                                          color: Colors
                                                                              .green
                                                                              .shade900,
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                          fontSize:
                                                                              dynamicFontSize,
                                                                        ),
                                                                        textAlign:
                                                                            TextAlign.center,
                                                                        overflow:
                                                                            TextOverflow.ellipsis,
                                                                      )
                                                                    : (isClosed &&
                                                                              assignment == null
                                                                          ? Icon(
                                                                              Icons.lock_rounded,
                                                                              size:
                                                                                  cellWidth <
                                                                                      35
                                                                                  ? 10
                                                                                  : 12,
                                                                              color: Colors.blueGrey.shade300,
                                                                            )
                                                                          : (assignment != null
                                                                                ? Text(
                                                                                    _isTeacherView
                                                                                        ? (cellWidth <
                                                                                                  36
                                                                                              ? _getShortName(
                                                                                                  assignment['lessonName'] ??
                                                                                                      '',
                                                                                                )
                                                                                              : '${_getShortName(assignment['lessonName'] ?? '')}\n${_resolveClassName(assignment)}')
                                                                                        : _getShortName(
                                                                                            assignment['lessonName'] ??
                                                                                                '',
                                                                                          ),
                                                                                    style: TextStyle(
                                                                                      color: isSelectedSource
                                                                                          ? Colors.orange.shade900
                                                                                          : (canFitInEmptySlot
                                                                                                ? Colors.green.shade900
                                                                                                : (canFitInEmptySlotBlocked
                                                                                                      ? Colors.orange.shade900
                                                                                                      : Colors.white)),
                                                                                      fontWeight: FontWeight.bold,
                                                                                      fontSize: dynamicFontSize,
                                                                                    ),
                                                                                    textAlign: TextAlign.center,
                                                                                    overflow: TextOverflow.ellipsis,
                                                                                  )
                                                                                : null))),
                                                        ),
                                                        // Kilit ikonu
                                                        Builder(
                                                          builder: (context) {
                                                            final cellClassId =
                                                                assignment?['classId']
                                                                    ?.toString() ??
                                                                (!_isTeacherView
                                                                    ? rowId
                                                                    : '');
                                                            final slotKey =
                                                                '${cellClassId}_${day}_$hourIndex';
                                                            final isCellLocked =
                                                                assignment !=
                                                                    null &&
                                                                _lockedSlots
                                                                    .contains(
                                                                      slotKey,
                                                                    );
                                                            if (!isCellLocked)
                                                              return const SizedBox.shrink();
                                                            return Positioned(
                                                              top: 1,
                                                              right: 1,
                                                              child: Container(
                                                                padding:
                                                                    const EdgeInsets.all(
                                                                      1.5,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: Colors
                                                                      .black
                                                                      .withOpacity(
                                                                        0.45,
                                                                      ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        4,
                                                                      ),
                                                                ),
                                                                child: const Icon(
                                                                  Icons
                                                                      .lock_rounded,
                                                                  size: 8,
                                                                  color: Colors
                                                                      .amberAccent,
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            );
                                          }),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                );
                              },
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
      },
    );
  }

  String _getShortName(String lessonName) {
    if (lessonName.length <= 3) return lessonName.toUpperCase();

    // ölk 3 harfi al
    final words = lessonName.split(' ');
    if (words.length > 1) {
      return words.map((w) => w.isNotEmpty ? w[0] : '').join('').toUpperCase();
    }
    return lessonName.substring(0, 3).toUpperCase();
  }

  /// Tek bir ders atamasını (ve varsa birleştirilmiş partner sınıfları) kilitler / kilidini ağar
  Future<void> _toggleLockLesson(Map<String, dynamic> assignment) async {
    final classId = assignment['classId']?.toString();
    final day = assignment['day']?.toString();
    final hourIndex = assignment['hourIndex'];
    if (classId == null || day == null || hourIndex == null) return;

    final mergedIds = _getMergedClassIds(assignment);
    final key = '${classId}_${day}_$hourIndex';
    final isAlreadyLocked = _lockedSlots.contains(key);

    setState(() {
      for (var cId in mergedIds) {
        final slotKey = '${cId}_${day}_$hourIndex';
        if (isAlreadyLocked) {
          _lockedSlots.remove(slotKey);
        } else {
          _lockedSlots.add(slotKey);
        }
      }
    });

    await _saveLockedSlots();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAlreadyLocked
                ? '• Ders kilidi kaldırıldı'
                : '• Ders kilitlendi (daşıtım ve temizlemede korunacak)',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Seğili şubenin tüm derslerini kilitler / kilidini ağar
  Future<void> _toggleLockClass(String classId) async {
    final classKeys = _scheduleData.keys
        .where((k) => k.startsWith('${classId}_'))
        .toList();
    if (classKeys.isEmpty) return;
    final allLocked = classKeys.every((k) => _lockedSlots.contains(k));

    setState(() {
      for (var key in classKeys) {
        if (allLocked) {
          _lockedSlots.remove(key);
        } else {
          _lockedSlots.add(key);
        }
      }
    });

    await _saveLockedSlots();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allLocked
                ? '• Şubenin tüm derslerinin kilidi kaldırıldı'
                : '• Şubenin tüm dersleri kilitlendi (korunacak)',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Seğili İşretmenin girdişi tüm dersleri kilitler / kilidini ağar
  Future<void> _toggleLockTeacher(String teacherId) async {
    final teacherKeys = <String>[];
    for (var entry in _scheduleData.entries) {
      final tId = entry.value['teacherId']?.toString();
      final tIds = (entry.value['teacherIds'] as List?)
          ?.map((e) => e.toString())
          .toList();
      if (tId == teacherId || tIds?.contains(teacherId) == true) {
        teacherKeys.add(entry.key);
      }
    }
    if (teacherKeys.isEmpty) return;
    final allLocked = teacherKeys.every((k) => _lockedSlots.contains(k));

    setState(() {
      for (var key in teacherKeys) {
        if (allLocked) {
          _lockedSlots.remove(key);
        } else {
          _lockedSlots.add(key);
        }
      }
    });

    await _saveLockedSlots();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allLocked
                ? '• Öğretmenin tüm derslerinin kilidi kaldırıldı'
                : '• Öğretmenin tüm dersleri kilitlendi (korunacak)',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Kilitli slotları Firestore workPeriods/scheduleSettings altında saklar
  Future<void> _saveLockedSlots() async {
    try {
      final periodDoc = await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(widget.periodId)
          .get();
      final currentSettings = Map<String, dynamic>.from(
        periodDoc.data()?['scheduleSettings'] ?? {},
      );
      currentSettings['lockedSlots'] = _lockedSlots.toList();
      await FirebaseFirestore.instance
          .collection('workPeriods')
          .doc(widget.periodId)
          .set({'scheduleSettings': currentSettings}, SetOptions(merge: true));
    } catch (e) {
      print('Kilitli slotlar kaydedilemedi: $e');
    }
  }

  /// Verilen atamanın birleştirilmiş olduşu tüm sınıf ID'lerini dİndürür.
  Set<String> _getMergedClassIds(Map<String, dynamic> data) {
    final Set<String> result = {};
    final classId = data['classId']?.toString();
    if (classId != null && classId.isNotEmpty) {
      result.add(classId);
    }
    // 1) Explicit 'mergedClassIds' alanı varsa
    final mergedIds = (data['mergedClassIds'] as List?)
        ?.map((e) => e.toString())
        .toList();
    if (mergedIds != null && mergedIds.isNotEmpty) {
      result.addAll(mergedIds);
    }
    // 2) _lessonClassMerges yapılandırmasından kontrol et
    final lessonName = (data['lessonName'] ?? '').toString().trim();
    if (classId != null && lessonName.isNotEmpty) {
      for (var merge in _lessonClassMerges) {
        final mName = (merge['lessonName'] ?? '').toString().trim();
        final mClassIds = List<String>.from(
          merge['classIds'] ?? [],
        ).map((e) => e.toString()).toList();
        if (mName.toLowerCase() == lessonName.toLowerCase() &&
            mClassIds.contains(classId)) {
          result.addAll(mClassIds);
        }
      }
    }
    // 3) _scheduleData iğinde aynı gün ve saatte bu İşretmenin girdişi dişer sınıflar
    final day = data['day']?.toString();
    final hourIndex = data['hourIndex'];
    final teacherId = data['teacherId']?.toString();
    if (day != null &&
        hourIndex != null &&
        teacherId != null &&
        lessonName.isNotEmpty) {
      for (var entry in _scheduleData.values) {
        if (entry['day'] == day &&
            entry['hourIndex'] == hourIndex &&
            entry['teacherId']?.toString() == teacherId &&
            (entry['lessonName'] ?? '').toString().trim().toLowerCase() ==
                lessonName.toLowerCase()) {
          final cId = entry['classId']?.toString();
          if (cId != null && cId.isNotEmpty) {
            result.add(cId);
          }
        }
      }
    }
    return result;
  }

  /// Atama verisindeki classId'yi kullanarak sınıf adını ğİzer.
  /// Birleştirilmiş sınıfları tespit ederek sınıf adlarını tire (-) ile birleştirir (ürn: 801-802-803).
  String _resolveClassName(Map<String, dynamic> data) {
    final day = data['day']?.toString();
    final hourIndex = data['hourIndex'];
    final teacherId = data['teacherId']?.toString();
    final lessonName = (data['lessonName'] ?? '').toString().trim();

    // 1) Explicit 'mergedClassIds' alanı varsa
    final mergedIds = (data['mergedClassIds'] as List?)
        ?.map((e) => e.toString())
        .toList();
    if (mergedIds != null && mergedIds.isNotEmpty) {
      final names = mergedIds.map((cId) {
        final found = _classes.firstWhere(
          (c) => c['id']?.toString() == cId,
          orElse: () => <String, dynamic>{},
        );
        return found.isNotEmpty ? (found['className']?.toString() ?? cId) : cId;
      }).toList();
      return names.join('-');
    }

    // 2) _lessonClassMerges yapılandırmasından kontrol et
    final classId = data['classId']?.toString();
    if (classId != null && lessonName.isNotEmpty) {
      for (var merge in _lessonClassMerges) {
        final mName = (merge['lessonName'] ?? '').toString().trim();
        final mClassIds = List<String>.from(merge['classIds'] ?? []);
        if (mName.toLowerCase() == lessonName.toLowerCase() &&
            mClassIds.contains(classId)) {
          final names = mClassIds.map((cId) {
            final found = _classes.firstWhere(
              (c) => c['id']?.toString() == cId,
              orElse: () => <String, dynamic>{},
            );
            return found.isNotEmpty
                ? (found['className']?.toString() ?? cId)
                : cId;
          }).toList();
          return names.join('-');
        }
      }
    }

    // 3) _scheduleData iğinde aynı gün ve saatte bu İşretmenin girdişi dişer sınıfları birleştir
    if (day != null &&
        hourIndex != null &&
        teacherId != null &&
        lessonName.isNotEmpty) {
      final Set<String> relatedClassNames = {};
      for (var entry in _scheduleData.values) {
        if (entry['day'] == day &&
            entry['hourIndex'] == hourIndex &&
            entry['teacherId']?.toString() == teacherId &&
            (entry['lessonName'] ?? '').toString().trim().toLowerCase() ==
                lessonName.toLowerCase()) {
          final cId = entry['classId']?.toString();
          if (cId != null) {
            final found = _classes.firstWhere(
              (c) => c['id']?.toString() == cId,
              orElse: () => <String, dynamic>{},
            );
            final cName = found.isNotEmpty
                ? (found['className']?.toString() ?? cId)
                : (entry['className']?.toString() ?? cId);
            relatedClassNames.add(cName);
          }
        }
      }
      if (relatedClassNames.length > 1) {
        final sortedList = relatedClassNames.toList()..sort();
        return sortedList.join('-');
      }
    }

    if (classId == null) return data['className']?.toString() ?? 'Bilinmeyen';
    final found = _classes.firstWhere(
      (c) => c['id']?.toString() == classId,
      orElse: () => <String, dynamic>{},
    );
    if (found.isNotEmpty) return found['className']?.toString() ?? 'Bilinmeyen';
    // Fallback: stored className field
    return data['className']?.toString() ?? 'Bilinmeyen';
  }

  /// Yerleşemeyen bir dersi mevcut programa ğakışmasız ve kilitleri bozmadan
  /// gerekirse dişer dersleri alternatif boş slotlara kaydırarak (smart swap) zorla yerleştirir
  Future<void> _forcePlaceUnassignedLesson(Map<String, dynamic> lesson) async {
    final classId = lesson['classId']?.toString();
    final lessonId = lesson['lessonId']?.toString();
    final lessonName = (lesson['lessonName'] ?? 'Ders').toString();
    final className = (lesson['className'] ?? 'Sınıf').toString();
    final teacherId = lesson['teacherId']?.toString();
    final teacherIds =
        (lesson['teacherIds'] as List?)?.map((e) => e.toString()).toList() ??
        (teacherId != null ? [teacherId] : <String>[]);

    if (classId == null || lessonId == null) return;

    final mergedClassIds = _getMergedClassIds(lesson);
    final remainingKey = '${classId}_$lessonId';
    int remainingHours = _remainingHours[remainingKey] ?? 1;
    if (remainingHours <= 0) remainingHours = 1;

    // öşlemden İnce mevcut durumu Geri Al iğin LOKAL olarak kaydet (Firebase okuması YOK)
    final backupScheduleData = Map<String, Map<String, dynamic>>.from(
      _scheduleData.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v))),
    );
    final backupRemainingHours = Map<String, int>.from(_remainingHours);

    setState(() {
      _isLoading = true;
      _isDistributing = true;
    });

    int placedCount = 0;
    List<String> logs = [];
    // Deşişiklikleri izle: Firestore'a toplu yazma iğin
    List<Map<String, dynamic>> pendingWrites = [];

    // O(1) hızında İşretmen meşguliyet tablosunu oluştur
    Map<String, Set<String>> teacherBusySlots = {};
    for (var entry in _scheduleData.values) {
      final tId = entry['teacherId']?.toString();
      final tIds =
          (entry['teacherIds'] as List?)?.map((e) => e.toString()).toList() ??
          [];
      if (tId != null && !tIds.contains(tId)) tIds.add(tId);

      final day = entry['day'];
      final h = entry['hourIndex'];
      final key = '${day}_$h';

      for (var id in tIds) {
        teacherBusySlots.putIfAbsent(id, () => {}).add(key);
      }
    }

    for (int step = 0; step < remainingHours; step++) {
      bool placedThisStep = false;

      // ADIM 1: Doğrudan Boş Slot Ara
      for (var day in _days) {
        final dayMax = _dailyLessonCounts[day] ?? _lessonHours.length;
        for (int h = 0; h < dayMax; h++) {
          final slotKey = '${day}_$h';

          // Sınıf kapalı mı?
          bool classClosed = false;
          for (var cId in mergedClassIds) {
            if (_closedSlots['class_$cId']?.contains(slotKey) == true) {
              classClosed = true;
              break;
            }
          }
          if (classClosed) continue;

          // Sınıflar boş mu?
          bool classesFree = true;
          for (var cId in mergedClassIds) {
            if (_scheduleData['${cId}_${day}_$h'] != null) {
              classesFree = false;
              break;
            }
          }
          if (!classesFree) continue;

          // Öğretmen kapalı mı veya o saatte başka sınıfta mı?
          bool teachersFree = true;
          for (var tId in teacherIds) {
            if (_closedSlots['teacher_$tId']?.contains(slotKey) == true) {
              teachersFree = false;
              break;
            }
            if (teacherBusySlots[tId]?.contains(slotKey) == true) {
              teachersFree = false;
              break;
            }
          }
          if (!teachersFree) continue;

          // Bulundu! Doğrudan ata (LOKAL)
          for (var targetCId in mergedClassIds) {
            final key = '${targetCId}_${day}_$h';
            final lessonKey = '${targetCId}_${lesson['lessonId']}';
            final targetClassName = _classes.firstWhere(
              (c) => c['id'] == targetCId,
              orElse: () => <String, dynamic>{'className': targetCId},
            )['className'];
            final assignData = {
              'classId': targetCId,
              'day': day,
              'hourIndex': h,
              'lessonId': lesson['lessonId'],
              'lessonName': lessonName,
              'className': targetClassName,
              'teacherId': teacherId,
              'teacherName':
                  (lesson['teacherNames'] as List?)?.isNotEmpty == true
                  ? lesson['teacherNames'][0]
                  : 'üşretmen',
              'teacherIds': teacherIds,
              'periodId': widget.periodId,
              'institutionId': widget.institutionId,
              'termId': _cachedTermId,
              'isActive': true,
            };
            _scheduleData[key] = assignData;
            _remainingHours[lessonKey] = (_remainingHours[lessonKey] ?? 1) - 1;
            pendingWrites.add(assignData);
            // teacherBusySlots güncelle
            for (var tId in teacherIds) {
              teacherBusySlots.putIfAbsent(tId, () => {}).add('${day}_$h');
            }
          }
          placedThisStep = true;
          placedCount++;
          logs.add('$day ${h + 1}. saate doşrudan yerleştirildi.');
          break;
        }
        if (placedThisStep) break;
      }

      if (placedThisStep) continue;

      // ADIM 2: 1-Hop Akıllı Yer Değiştirme (Swap / Eject)
      // Hedef dersi bir slot (d1, h1)'e koymak için, oradaki kilitli olmayan 'victim' dersi
      // başka bir uygun boş slot (bestD2, bestH2)'ye kaydır.
      for (var d1 in _days) {
        if (placedThisStep) break;
        final d1Max = _dailyLessonCounts[d1] ?? _lessonHours.length;

        for (int h1 = 0; h1 < d1Max; h1++) {
          final slot1Key = '${d1}_$h1';

          // Kilitli slotlara ASLA dokunma
          bool isAnyClassLocked = false;
          for (var cId in mergedClassIds) {
            if (_lockedSlots.contains('${cId}_${d1}_$h1')) {
              isAnyClassLocked = true;
              break;
            }
          }
          if (isAnyClassLocked) continue;

          // Sınıf kapalı mı?
          bool classClosed = false;
          for (var cId in mergedClassIds) {
            if (_closedSlots['class_$cId']?.contains(slot1Key) == true) {
              classClosed = true;
              break;
            }
          }
          if (classClosed) continue;

          // Hedef dersin Öğretmeni (d1, h1)'de boş mu?
          bool targetTeachersFree = true;
          for (var tId in teacherIds) {
            if (_closedSlots['teacher_$tId']?.contains(slot1Key) == true) {
              targetTeachersFree = false;
              break;
            }
            if (teacherBusySlots[tId]?.contains(slot1Key) == true) {
              // Öğretmen bu slotta dolu gözüküyor.
              // Ancak eğer buradaki ders victim dersiyse ve victim de bu Öğretmeninse,
              // victim oradan çıkacağı için slot boşa çıkacaktır.
              final victimAtSlot = _scheduleData['${classId}_${d1}_$h1'];
              bool isVictimSelf = false;
              if (victimAtSlot != null) {
                final vTId = victimAtSlot['teacherId']?.toString();
                final vTIds =
                    (victimAtSlot['teacherIds'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    [];
                if (vTId == tId || vTIds.contains(tId)) {
                  isVictimSelf = true;
                }
              }
              if (!isVictimSelf) {
                targetTeachersFree = false;
                break;
              }
            }
          }
          if (!targetTeachersFree) continue;

          // Mevcut victim dersi al
          final victim = _scheduleData['${classId}_${d1}_$h1'];
          if (victim == null) continue;

          final victimMergedClassIds = _getMergedClassIds(victim);
          final victimTeacherId = victim['teacherId']?.toString();
          final victimTeacherIds =
              (victim['teacherIds'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              (victimTeacherId != null ? [victimTeacherId] : <String>[]);
          final victimClassName = victim['className']?.toString() ?? className;

          // Victim ders iğin (d2, h2) boş slotu ara
          bool foundVictimNewSlot = false;
          String? bestD2;
          int? bestH2;

          for (var d2 in _days) {
            final d2Max = _dailyLessonCounts[d2] ?? _lessonHours.length;
            for (int h2 = 0; h2 < d2Max; h2++) {
              if (d2 == d1 && h2 == h1) continue;
              final slot2Key = '${d2}_$h2';

              // Victim'in sınıfları kapalı mı?
              bool vClassClosed = false;
              for (var cId in victimMergedClassIds) {
                if (_closedSlots['class_$cId']?.contains(slot2Key) == true) {
                  vClassClosed = true;
                  break;
                }
              }
              if (vClassClosed) continue;

              // Victim sınıfları boş mu?
              bool vClassesFree = true;
              for (var cId in victimMergedClassIds) {
                if (_scheduleData['${cId}_${d2}_$h2'] != null) {
                  vClassesFree = false;
                  break;
                }
              }
              if (!vClassesFree) continue;

              // Victim İşretmenleri müsait mi?
              bool vTeachersFree = true;
              for (var tId in victimTeacherIds) {
                if (_closedSlots['teacher_$tId']?.contains(slot2Key) == true) {
                  vTeachersFree = false;
                  break;
                }
                if (teacherBusySlots[tId]?.contains(slot2Key) == true) {
                  vTeachersFree = false;
                  break;
                }
              }
              if (!vTeachersFree) continue;

              // Bulundu!
              bestD2 = d2;
              bestH2 = h2;
              foundVictimNewSlot = true;
              break;
            }
            if (foundVictimNewSlot) break;
          }

          if (foundVictimNewSlot && bestD2 != null && bestH2 != null) {
            // SWAP UYGULA (LOKAL):
            // 1. Victim'ı eski yerden kaldır
            for (var vCId in victimMergedClassIds) {
              final oldKey = '${vCId}_${d1}_$h1';
              _scheduleData.remove(oldKey);
            }
            // 2. Victim'ı yeni yere koy
            for (var vCId in victimMergedClassIds) {
              final newKey = '${vCId}_${bestD2}_$bestH2';
              final vClassName = _classes.firstWhere(
                (c) => c['id'] == vCId,
                orElse: () => <String, dynamic>{'className': vCId},
              )['className'];
              final vData = {
                'classId': vCId,
                'day': bestD2,
                'hourIndex': bestH2,
                'lessonId': victim['lessonId'],
                'lessonName': victim['lessonName'],
                'className': vClassName,
                'teacherId': victimTeacherId,
                'teacherIds': victimTeacherIds,
                'periodId': widget.periodId,
                'institutionId': widget.institutionId,
                'termId': _cachedTermId,
                'isActive': true,
              };
              _scheduleData[newKey] = vData;
              pendingWrites.add(vData);
            }
            // 3. Hedef dersi (d1, h1)'e koy
            for (var targetCId in mergedClassIds) {
              final key = '${targetCId}_${d1}_$h1';
              final lessonKey = '${targetCId}_${lesson['lessonId']}';
              final targetClassName = _classes.firstWhere(
                (c) => c['id'] == targetCId,
                orElse: () => <String, dynamic>{'className': targetCId},
              )['className'];
              final assignData = {
                'classId': targetCId,
                'day': d1,
                'hourIndex': h1,
                'lessonId': lesson['lessonId'],
                'lessonName': lessonName,
                'className': targetClassName,
                'teacherId': teacherId,
                'teacherIds': teacherIds,
                'periodId': widget.periodId,
                'institutionId': widget.institutionId,
                'termId': _cachedTermId,
                'isActive': true,
              };
              _scheduleData[key] = assignData;
              _remainingHours[lessonKey] =
                  (_remainingHours[lessonKey] ?? 1) - 1;
              pendingWrites.add(assignData);
            }
            // teacherBusySlots güncelle
            for (var tId in victimTeacherIds) {
              teacherBusySlots[tId]?.remove('${d1}_$h1');
              teacherBusySlots
                  .putIfAbsent(tId, () => {})
                  .add('${bestD2}_$bestH2');
            }
            for (var tId in teacherIds) {
              teacherBusySlots.putIfAbsent(tId, () => {}).add('${d1}_$h1');
            }

            placedThisStep = true;
            placedCount++;
            logs.add(
              '${victim['lessonName']} dersi $bestD2 ${bestH2! + 1}. saate kaydırılarak yer alındı.',
            );
            break;
          }
        }
      }
    }

    // DEĞİŞİKLİKLERİ FİRESTORE'A TOPLU YAZ
    if (pendingWrites.isNotEmpty) {
      try {
        final firestore = FirebaseFirestore.instance;
        final batch = firestore.batch();
        for (var data in pendingWrites) {
          final docId =
              '${widget.periodId}_${data['classId']}_${data['day']}_${data['hourIndex']}';
          batch.set(
            firestore.collection('classSchedules').doc(docId),
            {...data, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      } catch (e) {
        print('Toplu Firestore yazma hatası: $e');
      }
    }

    setState(() {
      _isLoading = false;
      _isDistributing = false;
    });

    if (placedCount > 0) {
      setState(() => _selectedUnassignedLesson = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Expanded(
                  child: Text(
                    '• $lessonName ($className) yerleştirildi!\n${logs.join("\n")}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    // GERİ AL İŞLEMİ – Lokal backup'ı geri yükle
                    setState(() {
                      _isLoading = true;
                      _isDistributing = false;
                    });

                    // Lokal state'i geri al
                    _scheduleData = backupScheduleData;
                    _remainingHours = backupRemainingHours;

                    // Firestore'ı da geri al
                    try {
                      final firestore = FirebaseFirestore.instance;
                      final batch = firestore.batch();
                      // Yeni yazılanları sil
                      for (var data in pendingWrites) {
                        final docId =
                            '${widget.periodId}_${data['classId']}_${data['day']}_${data['hourIndex']}';
                        batch.delete(
                          firestore.collection('classSchedules').doc(docId),
                        );
                      }
                      // Eski verileri geri yaz
                      for (var entry in backupScheduleData.entries) {
                        final data = entry.value;
                        final docId =
                            '${widget.periodId}_${data['classId']}_${data['day']}_${data['hourIndex']}';
                        batch.set(
                          firestore.collection('classSchedules').doc(docId),
                          data,
                          SetOptions(merge: true),
                        );
                      }
                      await batch.commit();
                    } catch (e) {
                      print('Geri Al Firestore hatası: $e');
                    }

                    setState(() => _isLoading = false);
                  },
                  child: const Text(
                    'GERİ AL',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  },
                  child: const Text(
                    'TAMAM',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
          ),
        );
      }
    } else {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                const Text('Zorla Yerleştirilemedi'),
              ],
            ),
            content: Text(
              '$lessonName ($className) dersi iğin boş slot veya kilitleri bozmadan yer ağabilecek bir yer deşiştirme (swap) varyantı bulunamadı.\n\n'
              '• Olası Nedenler:\n'
              '• Öğretmenin dişer gün/saatleri kapalı veya başka sınıflarla tamamen dolu olabilir.\n'
              '• Alternatif slotlardaki dersler kilitli olabilir.\n'
              '• Öğretmenin kapalı saatlerini veya dişer derslerin kilitlerini gİzden geğiriniz.',
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Anladım',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      }
    }
  }
}

class _MultiSelectionContent extends StatefulWidget {
  final String title;
  final List<String> items;
  final IconData icon;
  final bool isDialog;

  const _MultiSelectionContent({
    required this.title,
    required this.items,
    required this.icon,
    this.isDialog = false,
  });

  @override
  State<_MultiSelectionContent> createState() => _MultiSelectionContentState();
}

class _MultiSelectionContentState extends State<_MultiSelectionContent> {
  List<String> selectedItems = [];
  late Map<String, List<String>> levelGroups;
  late List<String> sortedLevels;

  @override
  void initState() {
    super.initState();
    _initializeGroups();
  }

  void _initializeGroups() {
    levelGroups = {};
    for (var item in widget.items) {
      String level = 'Dişer';
      final digitsMatch = RegExp(r'^(\d+)').firstMatch(item);
      if (digitsMatch != null) {
        String digits = digitsMatch.group(1)!;
        if (digits.length >= 3) {
          level = '${digits.substring(0, digits.length - 2)}. Sınıf';
        } else {
          level = '$digits. Sınıf';
        }
      }
      if (!levelGroups.containsKey(level)) levelGroups[level] = [];
      levelGroups[level]!.add(item);
    }
    sortedLevels = levelGroups.keys.toList()
      ..sort((a, b) {
        if (a == 'Dişer') return 1;
        if (b == 'Dişer') return -1;
        return a.compareTo(b);
      });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.isDialog ? 600 : double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: widget.isDialog ? BorderRadius.circular(28) : null,
      ),
      child: Column(
        mainAxisSize: widget.isDialog ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(24, widget.isDialog ? 24 : 48, 16, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade700, Colors.indigo.shade700],
              ),
              borderRadius: widget.isDialog
                  ? BorderRadius.vertical(top: Radius.circular(28))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 28),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      Text(
                        'Lütfen yazdırılacak Öğretmen ve Sınıfları seçin',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hızlı Seçim',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: Text('Tümünü Seç'),
                      selected:
                          selectedItems.length == widget.items.length &&
                          widget.items.isNotEmpty,
                      onSelected: (val) {
                        setState(() {
                          if (val)
                            selectedItems = List.from(widget.items);
                          else
                            selectedItems.clear();
                        });
                      },
                    ),
                    if (levelGroups.length > 1)
                      ...sortedLevels.map((lvl) {
                        final lvlItems = levelGroups[lvl]!;
                        final isAllSelected = lvlItems.every(
                          (i) => selectedItems.contains(i),
                        );
                        return FilterChip(
                          label: Text('$lvl ler'),
                          selected: isAllSelected,
                          selectedColor: Colors.purple.withOpacity(0.2),
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                for (var i in lvlItems)
                                  if (!selectedItems.contains(i))
                                    selectedItems.add(i);
                              } else {
                                for (var i in lvlItems) selectedItems.remove(i);
                              }
                            });
                          },
                        );
                      }),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1),
          Expanded(
            flex: widget.isDialog ? 0 : 1,
            child: Container(
              constraints: widget.isDialog
                  ? BoxConstraints(maxHeight: 400)
                  : null,
              padding: EdgeInsets.all(20),
              child: widget.items.length > 8
                  ? GridView.builder(
                      shrinkWrap: widget.isDialog,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: MediaQuery.of(context).size.width > 600
                            ? 3
                            : 2,
                        childAspectRatio: 3.5,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: widget.items.length,
                      itemBuilder: (context, index) =>
                          _buildItemCard(widget.items[index]),
                    )
                  : ListView.builder(
                      shrinkWrap: widget.isDialog,
                      itemCount: widget.items.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: _buildItemCard(widget.items[index]),
                      ),
                    ),
            ),
          ),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: widget.isDialog
                  ? BorderRadius.vertical(bottom: Radius.circular(28))
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                Text(
                  '${selectedItems.length} İşe seçildi',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'İPTAL',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
                SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple.shade600, Colors.indigo.shade600],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple.withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: selectedItems.isEmpty
                        ? null
                        : () => Navigator.pop(context, selectedItems),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Hemen Yazdır',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(String item) {
    final isSelected = selectedItems.contains(item);
    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected)
            selectedItems.remove(item);
          else
            selectedItems.add(item);
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? Colors.purple.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.purple.shade300 : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.purple.withOpacity(0.1),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected ? Colors.purple : Colors.grey.shade400,
              size: 20,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                item,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FullSelectionPage extends StatelessWidget {
  final String title;
  final List<String> items;
  final IconData icon;

  const FullSelectionPage({
    required this.title,
    required this.items,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _MultiSelectionContent(
        title: title,
        items: items,
        icon: icon,
        isDialog: false,
      ),
    );
  }
}

/// Otomatik daşıtım sırasında gİsterilen premium animasyonlu progress dialog
class _AutoDistributionProgressDialog extends StatefulWidget {
  @override
  State<_AutoDistributionProgressDialog> createState() =>
      _AutoDistributionProgressDialogState();
}

class _AutoDistributionProgressDialogState
    extends State<_AutoDistributionProgressDialog>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  late AnimationController _pulseController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnimation;
  Timer? _stepTimer;

  static const _steps = [
    {
      'icon': '•',
      'title': 'Veriler Hazırlanıyor',
      'desc': 'Sınıf, Öğretmen ve ders bilgileri yükleniyor...',
    },
    {
      'icon': '•',
      'title': 'Kısıtlar Analiz Ediliyor',
      'desc': 'Öğretmen kapalı saatleri ve günlük limitler kontrol ediliyor...',
    },
    {
      'icon': '•',
      'title': 'Blok Desenleri Uygulanıyor',
      'desc': 'Ders blokları ve birleştirme kuralları hesaplanıyor...',
    },
    {
      'icon': '•',
      'title': 'Simülasyon Çalışıyor',
      'desc': 'Monte Carlo simülasyonları ile en iyi dağılım aranıyor...',
    },
    {
      'icon': '•',
      'title': 'Çakışmalar Çözülüyor',
      'desc': 'Öğretmen ve sınıf çakışmaları gideriliyor...',
    },
    {
      'icon': '•',
      'title': 'Skorlar Hesaplanıyor',
      'desc': 'Her dağılım senaryosu puanlanıyor...',
    },
    {
      'icon': '•',
      'title': 'En İyi Sonuç Seçiliyor',
      'desc': 'En yüksek skorlu dağılım belirleniyor...',
    },
    {
      'icon': '•',
      'title': 'Kayıt Ediliyor',
      'desc': 'Ders programı veritabanına yazılıyor...',
    },
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _stepTimer = Timer.periodic(const Duration(milliseconds: 2200), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_currentStep < _steps.length - 1) {
        setState(() => _currentStep++);
        _progressController.animateTo(
          (_currentStep + 1) / _steps.length,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
        );
      }
    });

    _progressController.animateTo(
      1 / _steps.length,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 20,
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.orange.shade50],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // İst başlık ve animasyonlu icon
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value * 0.3 + 0.85,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.orange.shade400,
                              Colors.deepOrange.shade600,
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.shade300.withValues(
                                alpha: _pulseAnimation.value * 0.6,
                              ),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.auto_fix_high_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Otomatik Daşıtım',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      'Lütfen bekleyin...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Progress bar
            AnimatedBuilder(
              animation: _progressController,
              builder: (context, child) {
                return Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        height: 8,
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: _progressController.value,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.orange.shade400,
                                      Colors.deepOrange.shade600,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Adım ${_currentStep + 1} / ${_steps.length}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${((_progressController.value) * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 20),

            // Adım listesi
            ...List.generate(_steps.length, (index) {
              final step = _steps[index];
              final isCompleted = index < _currentStep;
              final isActive = index == _currentStep;
              final isPending = index > _currentStep;

              return AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: isPending ? 0.35 : 1.0,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: isActive ? 10 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.orange.shade50
                          : isCompleted
                          ? Colors.green.shade50
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: isActive
                          ? Border.all(
                              color: Colors.orange.shade200,
                              width: 1.5,
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Status icon
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                          child: isCompleted
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  key: ValueKey('done_$index'),
                                  color: Colors.green.shade600,
                                  size: 20,
                                )
                              : isActive
                              ? AnimatedBuilder(
                                  animation: _pulseAnimation,
                                  builder: (context, child) {
                                    return Container(
                                      key: ValueKey('active_$index'),
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.orange.shade100,
                                        border: Border.all(
                                          color: Colors.orange.shade500,
                                          width: 2.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.orange.shade300
                                                .withValues(
                                                  alpha:
                                                      _pulseAnimation.value *
                                                      0.5,
                                                ),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.orange.shade600,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                )
                              : Container(
                                  key: ValueKey('pending_$index'),
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        // Step text
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    step['icon']!,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      step['title']!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isActive
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isCompleted
                                            ? Colors.green.shade800
                                            : isActive
                                            ? Colors.orange.shade900
                                            : Colors.grey.shade500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (isActive) ...[
                                const SizedBox(height: 3),
                                Text(
                                  step['desc']!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange.shade700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
