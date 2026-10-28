import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/school/dynamic_course_group_model.dart';
import 'dynamic_group_service.dart';

/// Bir öğrencinin kurlu bir derste (ör. İngilizce) bulunduğu kur bilgisi.
class TrackSlot {
  final String groupId;
  final String groupName;
  final String lessonName;
  final String subGroupId;
  final String subGroupName;
  final List<String> teacherIds;
  final List<String> teacherNames;

  const TrackSlot({
    required this.groupId,
    required this.groupName,
    required this.lessonName,
    required this.subGroupId,
    required this.subGroupName,
    required this.teacherIds,
    required this.teacherNames,
  });

  /// Raporlarda "şube" yerine kullanılacak ad. ('_' karakteri anahtar
  /// ayrıştırmayı bozmasın diye boşluğa çevrilir.)
  String get label =>
      '${groupName.isNotEmpty ? '$groupName • ' : ''}$subGroupName'.replaceAll('_', ' ');
}

/// Kurs Listesi'ndeki (courseGroups, type=track) kurları okuyup
/// "öğrenci + ders -> kur" eşlemesi sağlar. Performans Özeti ve Eylem
/// Planları'nda kurlu derslerde şube yerine kur kullanmak için ortaktır.
class CourseTrackResolver {
  final List<DynamicCourseGroup> groups;
  final Map<String, String> studentNoToDocId;
  final Map<String, String> tcNoToDocId;
  final Map<String, String> nameToDocId;
  final Map<String, List<String>> studentNoToDocIds;
  final Map<String, List<String>> nameToDocIds;

  CourseTrackResolver(
    this.groups, {
    this.studentNoToDocId = const {},
    this.tcNoToDocId = const {},
    this.nameToDocId = const {},
    this.studentNoToDocIds = const {},
    this.nameToDocIds = const {},
  });

  static final CourseTrackResolver empty = CourseTrackResolver(const []);

  static Future<CourseTrackResolver> load({
    required String institutionId,
    required String schoolTypeId,
    String? termId,
  }) async {
    try {
      List<DynamicCourseGroup> list = [];
      if (schoolTypeId.isNotEmpty) {
        list = await DynamicGroupService().fetchGroups(
          institutionId: institutionId,
          schoolTypeId: schoolTypeId,
          termId: termId,
          type: DynamicCourseGroupType.track,
        );
      }

      if (list.isEmpty) {
        Query<Map<String, dynamic>> q = FirebaseFirestore.instance
            .collection('courseGroups')
            .where('institutionId', whereIn: [institutionId.toUpperCase(), institutionId.toLowerCase()])
            .where('type', isEqualTo: 'track')
            .where('isActive', isEqualTo: true);
        if (schoolTypeId.isNotEmpty) {
          final snap = await q.where('schoolTypeId', isEqualTo: schoolTypeId).get();
          list = snap.docs.map((d) => DynamicCourseGroup.fromFirestore(d)).toList();
        }
        if (list.isEmpty) {
          final snap = await q.get();
          list = snap.docs.map((d) => DynamicCourseGroup.fromFirestore(d)).toList();
        }
      }

      final filteredGroups = list.where((g) => g.type == DynamicCourseGroupType.track).toList();

      final noMap = <String, String>{};
      final tcMap = <String, String>{};
      final nameMap = <String, String>{};
      final noListMap = <String, List<String>>{};
      final nameListMap = <String, List<String>>{};

      if (filteredGroups.isNotEmpty) {
        final enrolledIds = <String>{
          for (final g in filteredGroups)
            for (final sg in g.subGroups) ...sg.studentIds,
        };
        try {
          final snapStudents = await FirebaseFirestore.instance
              .collection('students')
              .where('institutionId', whereIn: [institutionId.toUpperCase(), institutionId.toLowerCase()])
              .where('isActive', isEqualTo: true)
              .get();
          for (final doc in snapStudents.docs) {
            final d = doc.data();
            final id = doc.id;
            final isEnrolled = enrolledIds.contains(id);
            final no = (d['studentNo'] ?? d['studentNumber'] ?? d['number'] ?? '').toString().trim();
            final tc = (d['tcNo'] ?? '').toString().trim();
            final fullNameRaw = (d['fullName'] ?? '').toString().trim();
            final combinedName = '${d['firstName'] ?? d['name'] ?? ''} ${d['lastName'] ?? d['surname'] ?? ''}'.trim();
            final candidateNames = <String>{
              if (fullNameRaw.isNotEmpty) _norm(fullNameRaw),
              if (combinedName.isNotEmpty) _norm(combinedName),
            }..removeWhere((e) => e.isEmpty);

            if (no.isNotEmpty) {
              if (isEnrolled || !noMap.containsKey(no)) noMap[no] = id;
              final lst = noListMap.putIfAbsent(no, () => []);
              if (isEnrolled) {
                lst.insert(0, id);
              } else {
                lst.add(id);
              }
            }
            if (tc.isNotEmpty) {
              if (isEnrolled || !tcMap.containsKey(tc)) tcMap[tc] = id;
            }
            for (final name in candidateNames) {
              if (isEnrolled || !nameMap.containsKey(name)) nameMap[name] = id;
              final lst = nameListMap.putIfAbsent(name, () => []);
              if (isEnrolled) {
                lst.insert(0, id);
              } else {
                lst.add(id);
              }
            }
          }
        } catch (e) {
          debugPrint('CourseTrackResolver student mapping load error: $e');
        }
      }

      return CourseTrackResolver(
        filteredGroups,
        studentNoToDocId: noMap,
        tcNoToDocId: tcMap,
        nameToDocId: nameMap,
        studentNoToDocIds: noListMap,
        nameToDocIds: nameListMap,
      );
    } catch (e) {
      debugPrint('CourseTrackResolver yüklenemedi: $e');
      return empty;
    }
  }

  static String _norm(String s) => s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'i')
      .replaceAll('ı', 'i')
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _isEnglish(String s) {
    final n = _norm(s);
    return n.contains('ingilizce') || n.contains('maincourse') || n.contains('english');
  }

  static bool _isClub(String s) {
    final n = _norm(s);
    return n.contains('kulup') || n.contains('kulub');
  }

  static bool lessonMatches(String a, String b) {
    if (_isEnglish(a) && _isEnglish(b)) return true;
    if (_isClub(a) && _isClub(b)) return true;
    final x = _norm(a);
    final y = _norm(b);
    return x.isNotEmpty && y.isNotEmpty && (x == y || x.contains(y) || y.contains(x));
  }

  bool get isEmpty => groups.isEmpty;

  /// Şube veya sınıf düzeyinden seviye rakamını çıkarır (ör. "704" -> "7", "7. Sınıf" -> "7").
  static String? _extractGradeDigit(String? rawBranch, String? classLevel) {
    if (classLevel != null && classLevel.trim().isNotEmpty) {
      final m = RegExp(r'(\d+)').firstMatch(classLevel.trim());
      if (m != null) {
        final d = m.group(1)!;
        if (d.length <= 2) return d;
      }
    }
    if (rawBranch != null && rawBranch.trim().isNotEmpty) {
      final b = rawBranch.trim();
      final m3 = RegExp(r'^(\d)(\d{2})\b').firstMatch(b);
      if (m3 != null) return m3.group(1)!;
      final m4 = RegExp(r'^(\d{2})(\d{2})\b').firstMatch(b);
      if (m4 != null) return m4.group(1)!;
      final m1 = RegExp(r'^(\d{1,2})\b').firstMatch(b);
      if (m1 != null) return m1.group(1)!;
    }
    return null;
  }

  static bool _groupMatchesGrade(DynamicCourseGroup g, String? gradeDigit) {
    if (gradeDigit == null || gradeDigit.isEmpty) return true;
    final gn = g.name.trim();
    final gm = RegExp(r'(\d+)').firstMatch(gn);
    if (gm != null && gm.group(1) != gradeDigit) {
      return false;
    }
    if (g.subGroups.isNotEmpty) {
      final hasMatchingSub = g.subGroups.any((sg) {
        final sgn = sg.name.trim();
        final sgm = RegExp(r'^(\d)(\d{2})\b').firstMatch(sgn);
        return sgm == null || sgm.group(1) == gradeDigit;
      });
      if (!hasMatchingSub) return false;
    }
    return true;
  }

  /// Bu ders için tanımlı bir kur grubu var mı?
  bool isTrackSubject(String subject) =>
      groups.any((g) => lessonMatches(g.lessonName, subject) || lessonMatches(g.name, subject));

  /// Belirli bir şube/sınıf seviyesi ve ders için tanımlı bir kur grubu var mı?
  /// (Örn. 5, 6, 7. sınıflarda İngilizce kur grubu varken 8. sınıflarda olmayabilir.)
  bool hasTrackForBranchOrLevel(
    String subject, {
    String? rawBranch,
    String? classLevel,
  }) {
    final gradeDigit = _extractGradeDigit(rawBranch, classLevel);
    return groups.any((g) =>
        (lessonMatches(g.lessonName, subject) || lessonMatches(g.name, subject)) &&
        _groupMatchesGrade(g, gradeDigit));
  }

  TrackSlot? _directSlotForId(String studentId, String subject, {String? gradeDigit}) {
    for (final g in groups) {
      if (!lessonMatches(g.lessonName, subject) && !lessonMatches(g.name, subject)) continue;
      if (!_groupMatchesGrade(g, gradeDigit)) continue;
      for (final sg in g.subGroups) {
        if (sg.studentIds.contains(studentId)) return _slot(g, sg);
      }
    }
    if (gradeDigit != null) {
      for (final g in groups) {
        if (!lessonMatches(g.lessonName, subject) && !lessonMatches(g.name, subject)) continue;
        for (final sg in g.subGroups) {
          if (sg.studentIds.contains(studentId)) return _slot(g, sg);
        }
      }
    }
    return null;
  }

  /// Öğrencinin bu dersteki kuru (yoksa null).
  TrackSlot? slotFor(String? studentId, String subject, {String? gradeDigit}) {
    if (studentId == null || studentId.isEmpty) return null;
    final clean = studentId.trim();
    final direct = _directSlotForId(clean, subject, gradeDigit: gradeDigit);
    if (direct != null) return direct;

    if (clean.contains('|')) {
      final parts = clean.split('|');
      return slotForStudent(
        studentNo: parts.first.trim(),
        studentName: parts.skip(1).join('|').trim(),
        subject: subject,
      );
    }

    for (final id in studentNoToDocIds[clean] ?? const <String>[]) {
      final s = _directSlotForId(id, subject, gradeDigit: gradeDigit);
      if (s != null) return s;
    }
    final byTc = tcNoToDocId[clean];
    if (byTc != null) {
      final s = _directSlotForId(byTc, subject, gradeDigit: gradeDigit);
      if (s != null) return s;
    }
    final normName = _norm(clean);
    for (final id in nameToDocIds[normName] ?? const <String>[]) {
      final s = _directSlotForId(id, subject, gradeDigit: gradeDigit);
      if (s != null) return s;
    }
    return null;
  }

  /// Öğrenciyi ID, TC, ad veya numara üzerinden çok yönlü eşleyerek kurunu bulur.
  TrackSlot? slotForStudent({
    String? studentId,
    String? studentNo,
    String? tcNo,
    String? studentName,
    required String subject,
    String? rawBranch,
    String? classLevel,
  }) {
    final gradeDigit = _extractGradeDigit(rawBranch, classLevel);

    // 1. Doğrudan studentId
    if (studentId != null && studentId.trim().isNotEmpty) {
      final s = _directSlotForId(studentId.trim(), subject, gradeDigit: gradeDigit);
      if (s != null) return s;
    }
    // 2. TC Kimlik No (benzersiz)
    if (tcNo != null && tcNo.trim().isNotEmpty) {
      final cleanTc = tcNo.trim();
      final resolvedId = tcNoToDocId[cleanTc];
      if (resolvedId != null) {
        final s = _directSlotForId(resolvedId, subject, gradeDigit: gradeDigit);
        if (s != null) return s;
      }
      final directTc = _directSlotForId(cleanTc, subject, gradeDigit: gradeDigit);
      if (directTc != null) return directTc;
    }
    // 3. Öğrenci Adı + Soyadı
    if (studentName != null && studentName.trim().isNotEmpty) {
      final normName = _norm(studentName);
      for (final id in nameToDocIds[normName] ?? const <String>[]) {
        final s = _directSlotForId(id, subject, gradeDigit: gradeDigit);
        if (s != null) return s;
      }
      final singleId = nameToDocId[normName];
      if (singleId != null) {
        final s = _directSlotForId(singleId, subject, gradeDigit: gradeDigit);
        if (s != null) return s;
      }
    }
    // 4. Öğrenci Numarası
    if (studentNo != null && studentNo.trim().isNotEmpty) {
      final cleanNo = studentNo.trim();
      for (final id in studentNoToDocIds[cleanNo] ?? const <String>[]) {
        final s = _directSlotForId(id, subject, gradeDigit: gradeDigit);
        if (s != null) return s;
      }
      final singleId = studentNoToDocId[cleanNo];
      if (singleId != null) {
        final s = _directSlotForId(singleId, subject, gradeDigit: gradeDigit);
        if (s != null) return s;
      }
      final directNo = _directSlotForId(cleanNo, subject, gradeDigit: gradeDigit);
      if (directNo != null) return directNo;
    }
    return null;
  }

  /// Tüm kurlar (etiket -> kur). Öğretmen adı/filtresi için kullanılır.
  Map<String, TrackSlot> allSlotsByLabel() {
    final map = <String, TrackSlot>{};
    for (final g in groups) {
      for (final sg in g.subGroups) {
        final s = _slot(g, sg);
        map[s.label] = s;
      }
    }
    return map;
  }

  /// Şube ders programındaki kurlu ders (ör. İngilizce) slotlarını zenginleştirir:
  /// o şubenin öğrencilerinin hangi kurlara gittiği hücreye yazılır.
  /// [scheduleData] değerleri yerinde güncellenir ('teacherName' kısa özet,
  /// 'trackSummary' ayrıntılı satırlar, 'isTrackSlot' = true).
  Future<void> enrichClassSchedule({
    required String classId,
    required Map<String, Map<String, dynamic>> scheduleData,
  }) async {
    if (groups.isEmpty || scheduleData.isEmpty || classId.isEmpty) return;
    final relevant = groups.where((g) => g.targetClassIds.contains(classId)).toList();
    if (relevant.isEmpty) return;

    final Set<String> classStudentIds = {};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .where('classId', isEqualTo: classId)
          .where('isActive', isEqualTo: true)
          .get();
      classStudentIds.addAll(snap.docs.map((d) => d.id));
    } catch (e) {
      debugPrint('Kur özeti için öğrenciler yüklenemedi: $e');
      return;
    }
    if (classStudentIds.isEmpty) return;

    for (final key in scheduleData.keys.toList()) {
      final slot = scheduleData[key]!;
      final lessonId = (slot['lessonId'] ?? '').toString();
      final lessonName = (slot['lessonName'] ?? '').toString();
      DynamicCourseGroup? g;
      for (final cand in relevant) {
        if ((cand.lessonId.isNotEmpty && cand.lessonId == lessonId) ||
            lessonMatches(cand.lessonName, lessonName)) {
          g = cand;
          break;
        }
      }
      if (g == null) continue;

      final short = <String>[];
      final lines = <String>[];
      var assigned = 0;
      for (final sg in g.subGroups) {
        final count = sg.studentIds.where(classStudentIds.contains).length;
        if (count == 0) continue;
        assigned += count;
        final label = sg.name.replaceAll(RegExp(r'\s+'), ' ').trim();
        short.add('$label ($count)');
        final extras = <String>[
          '$count öğrenci',
          if (sg.teacherNames.isNotEmpty) sg.teacherNames.join(', '),
          if (sg.classroomName.isNotEmpty) sg.classroomName,
        ];
        lines.add('Kur $label • ${extras.join(' • ')}');
      }
      final unassigned = classStudentIds.length - assigned;
      if (unassigned > 0) {
        short.add('Atanmamış ($unassigned)');
        lines.add('Kura atanmamış • $unassigned öğrenci');
      }
      if (short.isEmpty) continue;
      slot['teacherName'] = 'Kur: ${short.join(' • ')}';
      slot['trackSummary'] = lines;
      slot['isTrackSlot'] = true;
    }
  }

  TrackSlot _slot(DynamicCourseGroup g, DynamicSubGroup sg) => TrackSlot(
        groupId: g.id,
        groupName: g.name,
        lessonName: g.lessonName,
        subGroupId: sg.id,
        subGroupName: sg.name,
        teacherIds: sg.teacherIds,
        teacherNames: sg.teacherNames,
      );
}
