import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'demo_seed_context.dart';

/// Demo veri üreticisi: ÇALIŞMA TAKVİMİ (alt dönemler + ders saatleri),
/// DERS PROGRAMI (classSchedules), yıllık/haftalık planlar, sınıf ders
/// planları, derslikler ve derslik-ders atamaları.
///
/// Yazılan koleksiyonlar:
///  * workPeriods        (okul türü başına 1 alt dönem + lessonHours)
///  * classSchedules     (her şube için çakışmasız haftalık program)
///  * yearlyPlans        (+ alt koleksiyon yearlyPlans/{id}/weeklyPlans)
///  * classLessonPlans
///  * classrooms / classroomLessons
///  * users              (yalnızca öğretmen yükü taşan derslerde "yardımcı" öğretmen)

/// Yazdığımız üst düzey koleksiyonlar (hepsinde institutionId + isDemo vardır).
const List<String> demoScheduleTopCollections = [
  'workPeriods',
  'classSchedules',
  'yearlyPlans',
  'classLessonPlans',
  'classrooms',
  'classroomLessons',
  'users',
];

/// schools/{schoolDocId}/ altına yazılan alt koleksiyon yok.
const List<String> demoScheduleSchoolSubcollections = [];

/// En fazla üretilecek yıllık plan sayısı (temizlik bu sayıya kadar tarar).
const int _maxYearlyPlans = 120;

const List<String> _days = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
];

/// Ders başlangıç dakikaları (08:30 ...), her ders 40 dk.
const List<int> _lessonStartMinutes = [510, 560, 610, 660, 710, 800, 850, 900];
const int _lessonMinutes = 40;
const int _gridHours = 8;
const int _slotsPerDay = 8;

/// Bir okul türünün alt dönem (workPeriods) doküman kimliği.
String demoSchedulePeriodId(DemoSeedContext ctx, String typeId) =>
    ctx.id('wp_$typeId');

Future<void> seedDemoSchedule(DemoSeedContext ctx) async {
  if (ctx.classes.isEmpty || ctx.types.isEmpty) return;

  final DateTime periodStart = DateTime(
    ctx.termStart.year,
    ctx.termStart.month,
    ctx.termStart.day,
  );
  DateTime periodEnd = DateTime(ctx.termStart.year + 1, 6, 20);
  if (ctx.today.isAfter(periodEnd.subtract(const Duration(days: 10)))) {
    periodEnd = ctx.today.add(const Duration(days: 30));
  }

  // ── 1. Ders programı çözümü (öğretmen çakışmasız) ───────────────────
  _Plan? plan;
  for (final factor in const [0.8, 0.7, 0.6, 0.5]) {
    plan = _solve(ctx, factor);
    if (plan != null) break;
  }
  if (plan == null) return;
  final _Plan solved = plan;

  // ── 2. Yardımcı öğretmenler (yalnızca gerekirse) ────────────────────
  for (final t in solved.teachers) {
    if (!t.isExtra) continue;
    await ctx.set(ctx.col('users').doc(t.id), {
      'uid': t.id,
      'institutionId': ctx.inst,
      'type': 'staff',
      'title': 'ogretmen',
      'role': 'teacher',
      'fullName': t.name,
      'name': t.first,
      'surname': t.last,
      'username': t.username,
      'email': '${t.username}@${ctx.inst}.edukn'.toLowerCase(),
      'branch': t.branch,
      'workLocations': [t.typeName],
      'schoolTypeId': t.typeId,
      'termId': ctx.termId,
      'isActive': true,
      'createdAt': Timestamp.fromDate(ctx.termStart),
      'updatedAt': Timestamp.fromDate(ctx.today),
    });
    ctx.count('Yardımcı Öğretmen');
  }

  // ── 3. Alt dönemler (çalışma takvimi + ders saatleri) ───────────────
  final int startYear = ctx.termStart.year;
  final lessonTimes = <String, dynamic>{};
  for (final day in _days) {
    lessonTimes[day] = List.generate(_gridHours, (i) {
      final s = _lessonStartMinutes[i];
      final e = s + _lessonMinutes;
      return {
        'startHour': s ~/ 60,
        'startMinute': s % 60,
        'endHour': e ~/ 60,
        'endMinute': e % 60,
      };
    });
  }
  final dailyCounts = <String, dynamic>{for (final d in _days) d: _gridHours};

  for (final type in ctx.types) {
    final hasClasses = ctx.classes.any((c) => c.typeId == type.id);
    if (!hasClasses) continue;
    await ctx.set(
      ctx.col('workPeriods').doc(demoSchedulePeriodId(ctx, type.id)),
      {
        'periodName': 'Eğitim Öğretim Yılı ($startYear-${startYear + 1})',
        'startDate': Timestamp.fromDate(periodStart),
        'endDate': Timestamp.fromDate(periodEnd),
        'schoolTypeId': type.id,
        'schoolTypeName': type.name,
        'institutionId': ctx.inst,
        'termId': ctx.termId,
        'isActive': true,
        'schedulePublished': true,
        'isPublished': true,
        'lessonHours': {
          'selectedDays': List<String>.from(_days),
          'dailyLessonCounts': dailyCounts,
          'lessonTimes': lessonTimes,
          'updatedAt': Timestamp.fromDate(ctx.termStart),
        },
        'createdAt': Timestamp.fromDate(ctx.termStart),
        'updatedAt': Timestamp.fromDate(ctx.termStart),
      },
    );
    ctx.count('Çalışma Dönemi');
  }

  // ── 4. classSchedules ───────────────────────────────────────────────
  for (final g in solved.grids) {
    final c = g.info;
    for (int i = 0; i < g.total; i++) {
      final li = g.items[i];
      final lesson = c.lessons[li];
      final t = solved.teachers[g.lessonTeacher[li]];
      final day = _days[g.cellDay[i]];
      final hour = g.cellHour[i];
      await ctx.set(
        ctx
            .col('classSchedules')
            .doc(ctx.id('cs_${c.id}_${g.cellDay[i]}_$hour')),
        {
          'classId': c.id,
          'className': c.name,
          'lessonId': lesson.id,
          'lessonName': lesson.name,
          'teacherId': t.id,
          'teacherName': t.name,
          'teacherIds': [t.id],
          'teacherNames': [t.name],
          'day': day,
          'hourIndex': hour,
          'periodId': demoSchedulePeriodId(ctx, c.typeId),
          'institutionId': ctx.inst,
          'schoolTypeId': c.typeId,
          'isActive': true,
          'isMerged': false,
          'isAutoDistributed': true,
          'createdAt': Timestamp.fromDate(ctx.termStart),
        },
      );
      ctx.count('Ders Programı Kaydı');
    }
  }

  // ── 5. Yıllık / haftalık planlar + sınıf ders planları ─────────────
  final int totalWeeks = math.max(
    1,
    (periodEnd.difference(periodStart).inDays / 7).ceil(),
  );
  final int curWeek = (ctx.today.difference(periodStart).inDays ~/ 7 + 1)
      .clamp(1, totalWeeks)
      .toInt();
  final int filledWeeks = math.min(math.min(curWeek + 2, totalWeeks), 36);
  int planNo = 0;

  for (final type in ctx.types) {
    final typeClasses = ctx.classes.where((c) => c.typeId == type.id).toList()
      ..sort((a, b) {
        final l = a.level.compareTo(b.level);
        return l != 0 ? l : a.name.compareTo(b.name);
      });
    if (typeClasses.isEmpty) continue;
    final classIds = typeClasses.map((c) => c.id).toList();
    final classNames = typeClasses.map((c) => c.name).toList();
    final periodId = demoSchedulePeriodId(ctx, type.id);
    final periodName = 'Eğitim Öğretim Yılı ($startYear-${startYear + 1})';

    for (final lesson in typeClasses.first.lessons) {
      if (planNo >= _maxYearlyPlans) break;
      final planId = ctx.id('yp_$planNo');
      final myPlanNo = planNo;
      planNo++;
      await ctx.set(ctx.col('yearlyPlans').doc(planId), {
        'periodId': periodId,
        'periodName': periodName,
        'lessonId': lesson.id,
        'lessonName': lesson.name,
        'classIds': classIds,
        'classNames': classNames,
        'planTitle': '${lesson.name} Yıllık Planı',
        'description':
            '${type.name} ${lesson.name} dersi için örnek yıllık plan.',
        'schoolTypeId': type.id,
        'institutionId': ctx.inst,
        'termId': ctx.termId,
        'isActive': true,
        'createdAt': Timestamp.fromDate(ctx.termStart),
        'updatedAt': Timestamp.fromDate(ctx.today),
      });
      ctx.count('Yıllık Plan');

      final topics = _topicsFor(lesson.name);
      final weekIds = <int, String>{};
      final weekTopics = <int, List<String>>{};
      for (int w = 1; w <= filledWeeks; w++) {
        final weekStart = periodStart.add(Duration(days: (w - 1) * 7));
        DateTime weekEnd = weekStart.add(const Duration(days: 6));
        if (weekEnd.isAfter(periodEnd)) weekEnd = periodEnd;
        final t = topics[(w - 1) % topics.length];
        final bool repeat = (w - 1) >= topics.length;
        final unit = repeat ? '${t[0]} (Pekiştirme)' : t[0];
        final topic = repeat ? '${t[1]} - Tekrar ve Uygulama' : t[1];
        final outcome = t[2];
        final wid = ctx.id('wk_${myPlanNo}_$w');
        weekIds[w] = wid;
        weekTopics[w] = [unit, topic, outcome];
        final covered = w < curWeek
            ? classIds
            : (w == curWeek
                  ? classIds.take((classIds.length / 2).ceil()).toList()
                  : <String>[]);
        await ctx.set(
          ctx.col('yearlyPlans').doc(planId).collection('weeklyPlans').doc(wid),
          {
            'weekNumber': w,
            'weekStart': Timestamp.fromDate(weekStart),
            'weekEnd': Timestamp.fromDate(weekEnd),
            'unit': unit,
            'topic': topic,
            'outcome': outcome,
            'coveredClassIds': covered,
            'institutionId': ctx.inst,
            'schoolTypeId': type.id,
            'updatedAt': Timestamp.fromDate(ctx.today),
          },
        );
        ctx.count('Haftalık Plan');
      }

      // Sınıf ders planları: son iki hafta (geçmiş/bu hafta).
      for (int w = math.max(1, curWeek - 1); w <= curWeek; w++) {
        if (!weekIds.containsKey(w)) continue;
        final wt = weekTopics[w]!;
        final weekStart = periodStart.add(Duration(days: (w - 1) * 7));
        for (final c in typeClasses) {
          final tIdx = solved.teacherByClassLesson['${c.id}|${lesson.id}'];
          final teacherId = tIdx != null
              ? solved.teachers[tIdx].id
              : lesson.teacherId;
          final covers =
              w < curWeek ||
              classIds.indexOf(c.id) < (classIds.length / 2).ceil();
          if (!covers) continue;
          await ctx.set(
            ctx
                .col('classLessonPlans')
                .doc(ctx.id('clp_${c.id}_${myPlanNo}_$w')),
            {
              'institutionId': ctx.inst,
              'schoolTypeId': type.id,
              'periodId': periodId,
              'classId': c.id,
              'lessonId': lesson.id,
              'lessonName': lesson.name,
              'teacherId': teacherId,
              'title': '$w. Hafta ${lesson.name} Planı',
              'content': wt[1],
              'outcome': wt[2],
              'yearlyPlanId': planId,
              'weeklyPlanId': weekIds[w],
              'isFromYearlyPlan': true,
              'updatedAt': Timestamp.fromDate(
                weekStart.add(const Duration(days: 2)),
              ),
              'attachments': <Map<String, dynamic>>[],
              'date': Timestamp.fromDate(
                weekStart.add(const Duration(days: 1)),
              ),
              'createdAt': Timestamp.fromDate(weekStart),
            },
          );
          ctx.count('Sınıf Ders Planı');
        }
      }
    }
  }

  // ── 6. Derslikler + derslik ders atamaları ─────────────────────────
  for (final type in ctx.types) {
    final typeClasses = ctx.classes.where((c) => c.typeId == type.id).toList()
      ..sort((a, b) {
        final l = a.level.compareTo(b.level);
        return l != 0 ? l : a.name.compareTo(b.name);
      });
    if (typeClasses.isEmpty) continue;
    final classNames = typeClasses.map((c) => c.name).toList();
    final lessons = typeClasses.first.lessons;

    Future<void> addRoom(
      String key,
      String name,
      String code,
      String roomType,
      int capacity,
      String floor,
      String description,
      List<DemoLessonInfo> roomLessons,
    ) async {
      final roomId = ctx.id('room_${type.id}_$key');
      await ctx.set(ctx.col('classrooms').doc(roomId), {
        'classroomName': name,
        'classroomCode': code,
        'classroomType': roomType,
        'capacity': capacity,
        'floor': floor,
        'building': 'Ana Bina',
        'description': description,
        'schoolTypeId': type.id,
        'schoolTypeName': type.name,
        'institutionId': ctx.inst,
        'createdAt': Timestamp.fromDate(ctx.termStart),
        'updatedAt': null,
        'isActive': true,
      });
      ctx.count('Derslik');
      for (final l in roomLessons) {
        await ctx.set(
          ctx.col('classroomLessons').doc(ctx.id('rl_${roomId}_${l.id}')),
          {
            'classroomId': roomId,
            'classroomName': name,
            'lessonId': l.id,
            'lessonName': l.name,
            'lessonAssignmentIds': <String>[],
            'classNames': classNames,
            'schoolTypeId': type.id,
            'institutionId': ctx.inst,
            'isActive': true,
            'createdAt': Timestamp.fromDate(ctx.termStart),
          },
        );
        ctx.count('Derslik Ders Ataması');
      }
    }

    // Her şube için bir sınıf dersliği.
    for (final c in typeClasses) {
      final floorNo = (c.level % 4);
      await addRoom(
        'cls_${c.id}',
        '${c.name} Sınıfı',
        c.name.replaceAll('-', ''),
        'Sınıf',
        c.typeKind == 'Lise' ? 30 : 28,
        floorNo == 0 ? 'Zemin Kat' : '$floorNo. Kat',
        '${c.name} şubesinin ana dersliği',
        const [],
      );
    }

    bool has(DemoLessonInfo l, List<String> keys) =>
        keys.any((k) => l.name.contains(k));
    final fenLessons = lessons
        .where((l) => has(l, ['Fen', 'Fizik', 'Kimya', 'Biyoloji']))
        .toList();
    final spor = lessons.where((l) => has(l, ['Beden'])).toList();
    final sanat = lessons.where((l) => has(l, ['Görsel', 'Müzik'])).toList();

    await addRoom(
      'fen',
      'Fen Laboratuvarı',
      'LAB1',
      'Laboratuvar',
      24,
      'Zemin Kat',
      'Deney düzeneklerinin bulunduğu fen laboratuvarı',
      fenLessons,
    );
    await addRoom(
      'bilisim',
      'Bilişim Laboratuvarı',
      'LAB2',
      'Laboratuvar',
      24,
      '1. Kat',
      'Bilgisayar ve kodlama dersleri için laboratuvar',
      const [],
    );
    await addRoom(
      'spor',
      'Spor Salonu',
      'SPOR',
      'Spor Salonu',
      60,
      'Zemin Kat',
      'Kapalı spor salonu',
      spor,
    );
    await addRoom(
      'sanat',
      'Müzik ve Görsel Sanatlar Atölyesi',
      'ATL1',
      'Atölye',
      26,
      '2. Kat',
      'Resim ve müzik dersleri için atölye',
      sanat,
    );
  }
}

/// Üretilen dokümanlardan üst düzey sorgularla ulaşılamayanları siler
/// (yearlyPlans/{id}/weeklyPlans alt koleksiyonu).
Future<int> cleanDemoScheduleExtras(
  FirebaseFirestore db,
  String inst,
  String prefix,
  String schoolDocId,
) async {
  int deleted = 0;
  WriteBatch batch = db.batch();
  int pending = 0;

  for (int start = 0; start < _maxYearlyPlans; start += 20) {
    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (int n = start; n < math.min(start + 20, _maxYearlyPlans); n++) {
      futures.add(
        db
            .collection('yearlyPlans')
            .doc('${prefix}yp_$n')
            .collection('weeklyPlans')
            .get(),
      );
    }
    final snaps = await Future.wait(futures);
    for (final snap in snaps) {
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
        pending++;
        deleted++;
        if (pending >= 400) {
          await batch.commit();
          batch = db.batch();
          pending = 0;
        }
      }
    }
  }
  if (pending > 0) {
    await batch.commit();
  }
  return deleted;
}

// ═══════════════════════════════════════════════════════════════════════
//  Ders programı çözücüsü
// ═══════════════════════════════════════════════════════════════════════

class _Teacher {
  final String id;
  final String name;
  final String first;
  final String last;
  final String username;
  final String branch;
  final String typeId;
  final String typeName;
  final bool isExtra;
  const _Teacher({
    required this.id,
    required this.name,
    required this.first,
    required this.last,
    required this.username,
    required this.branch,
    required this.typeId,
    required this.typeName,
    required this.isExtra,
  });
}

class _Grid {
  final DemoClassInfo info;
  final int total;
  final List<int> cellDay;
  final List<int> cellHour;
  final List<int> dayStart;
  final List<int> dayEnd;
  final List<int> items;
  final List<int> lessonWh;
  final List<int> lessonTeacher;
  _Grid({
    required this.info,
    required this.total,
    required this.cellDay,
    required this.cellHour,
    required this.dayStart,
    required this.dayEnd,
    required this.items,
    required this.lessonWh,
    required this.lessonTeacher,
  });
}

class _Plan {
  final List<_Grid> grids;
  final List<_Teacher> teachers;
  final Map<String, int> teacherByClassLesson;
  _Plan(this.grids, this.teachers, this.teacherByClassLesson);
}

const List<String> _extraFemale = [
  'Gülay',
  'Sevgi',
  'Nurten',
  'Hülya',
  'Derya',
  'Pınar',
  'Ebru',
  'Tuğba',
  'Seda',
  'Burcu',
  'Esra',
  'Yasemin',
];
const List<String> _extraMale = [
  'Kemal',
  'Orhan',
  'Serkan',
  'Volkan',
  'Erdem',
  'Murat',
  'Hakan',
  'Tolga',
  'Cem',
  'Uğur',
  'Barış',
  'Levent',
];
const List<String> _extraSurnames = [
  'Aksoy',
  'Karaca',
  'Erdoğan',
  'Polat',
  'Güneş',
  'Taş',
  'Aydın',
  'Çetin',
  'Kurt',
  'Özkan',
  'Sezer',
  'Bulut',
  'Yıldırım',
  'Şimşek',
  'Koç',
  'Arslan',
];

_Plan? _solve(DemoSeedContext ctx, double factor) {
  final rng = ctx.rng;
  final teachers = <_Teacher>[];
  final teacherIdxByKey = <String, int>{};
  final teacherByClassLesson = <String, int>{};
  int extraCounter = 0;

  int registerTeacher(
    String key,
    DemoLessonInfo lesson,
    DemoTypeDef type,
    int ordinal,
  ) {
    final existing = teacherIdxByKey[key];
    if (existing != null) return existing;
    late _Teacher t;
    if (ordinal == 0) {
      String branch = lesson.name;
      for (final ti in ctx.teachers) {
        if (ti.id == lesson.teacherId) {
          branch = ti.branch;
          break;
        }
      }
      t = _Teacher(
        id: lesson.teacherId,
        name: lesson.teacherName,
        first: lesson.teacherName.split(' ').first,
        last: lesson.teacherName.split(' ').last,
        username: '',
        branch: branch,
        typeId: type.id,
        typeName: type.name,
        isExtra: false,
      );
    } else {
      final n = extraCounter++;
      final female = n % 2 == 0;
      final first = female
          ? _extraFemale[(n * 5 + 1) % _extraFemale.length]
          : _extraMale[(n * 7 + 2) % _extraMale.length];
      final last = _extraSurnames[(n * 3 + 4) % _extraSurnames.length];
      String branch = lesson.name;
      for (final ti in ctx.teachers) {
        if (ti.id == lesson.teacherId) {
          branch = ti.branch;
          break;
        }
      }
      t = _Teacher(
        id: ctx.id('tx_$n'),
        name: '$first $last',
        first: first,
        last: last,
        username: 'yrdogretmen${n + 1}',
        branch: branch,
        typeId: type.id,
        typeName: type.name,
        isExtra: true,
      );
    }
    teachers.add(t);
    teacherIdxByKey[key] = teachers.length - 1;
    return teachers.length - 1;
  }

  final grids = <_Grid>[];
  int classOrder = 0;

  for (final type in ctx.types) {
    final typeClasses = ctx.classes.where((c) => c.typeId == type.id).toList()
      ..sort((a, b) {
        final l = a.level.compareTo(b.level);
        return l != 0 ? l : a.name.compareTo(b.name);
      });
    if (typeClasses.isEmpty) continue;

    int maxTotal = 0;
    for (final c in typeClasses) {
      int t = 0;
      for (final l in c.lessons) {
        t += l.weeklyHours;
      }
      if (t > maxTotal) maxTotal = t;
    }

    // Ders başına öğretmen yükü sınırı.
    final Map<String, int> lessonTeacherOrdinal = {};
    final Map<String, int> lessonTeacherLoad = {};

    for (final c in typeClasses) {
      int total = 0;
      for (final l in c.lessons) {
        total += l.weeklyHours;
      }
      if (total <= 0 || total > _days.length * _slotsPerDay) continue;

      final lessonTeacher = <int>[];
      final lessonWh = <int>[];
      for (final l in c.lessons) {
        final cap = math.max(l.weeklyHours, (maxTotal * factor).floor());
        int ord = lessonTeacherOrdinal[l.id] ?? 0;
        int load = lessonTeacherLoad['${l.id}|$ord'] ?? 0;
        if (load + l.weeklyHours > cap && load > 0) {
          ord++;
          load = 0;
        }
        lessonTeacherOrdinal[l.id] = ord;
        lessonTeacherLoad['${l.id}|$ord'] = load + l.weeklyHours;
        final key = ord == 0 ? l.teacherId : '${type.id}|${l.id}|$ord';
        final idx = registerTeacher(key, l, type, ord);
        lessonTeacher.add(idx);
        lessonWh.add(l.weeklyHours);
        teacherByClassLesson['${c.id}|${l.id}'] = idx;
      }

      // Hücreler: günlere eşit dağıtım, her gün 0..k-1 saat (boşluksuz).
      final base = total ~/ _days.length;
      final extra = total % _days.length;
      final cellDay = <int>[];
      final cellHour = <int>[];
      final dayStart = List<int>.filled(_days.length, 0);
      final dayEnd = List<int>.filled(_days.length, 0);
      for (int d = 0; d < _days.length; d++) {
        final rel =
            (d - (classOrder % _days.length) + _days.length) % _days.length;
        final cnt = base + (rel < extra ? 1 : 0);
        dayStart[d] = cellDay.length;
        for (int h = 0; h < cnt; h++) {
          cellDay.add(d);
          cellHour.add(h);
        }
        dayEnd[d] = cellDay.length;
      }
      classOrder++;

      final items = <int>[];
      for (int li = 0; li < c.lessons.length; li++) {
        for (int k = 0; k < c.lessons[li].weeklyHours; k++) {
          items.add(li);
        }
      }
      items.shuffle(rng);

      grids.add(
        _Grid(
          info: c,
          total: total,
          cellDay: cellDay,
          cellHour: cellHour,
          dayStart: dayStart,
          dayEnd: dayEnd,
          items: items,
          lessonWh: lessonWh,
          lessonTeacher: lessonTeacher,
        ),
      );
    }
  }
  if (grids.isEmpty) return null;

  // ── Yerel arama (min-conflicts) ────────────────────────────────────
  const int stride = 64;
  final cnt = List<int>.filled(teachers.length * stride, 0);
  int slotOf(_Grid g, int cell) =>
      g.cellDay[cell] * _slotsPerDay + g.cellHour[cell];

  void addAll() {
    for (final g in grids) {
      for (int i = 0; i < g.total; i++) {
        cnt[g.lessonTeacher[g.items[i]] * stride + slotOf(g, i)]++;
      }
    }
  }

  int totalConflicts() {
    int s = 0;
    for (final v in cnt) {
      if (v > 1) s += v - 1;
    }
    return s;
  }

  int tc(int t, int s) {
    final v = cnt[t * stride + s];
    return v > 1 ? v - 1 : 0;
  }

  int dayPen(_Grid g, int day) {
    final s = g.dayStart[day];
    final e = g.dayEnd[day];
    int pen = 0;
    for (int i = s; i < e; i++) {
      final it = g.items[i];
      int c = 0;
      for (int j = s; j < e; j++) {
        if (g.items[j] == it) c++;
      }
      if (c > 2) {
        pen += 3;
      } else if (c == 2) {
        final adjacent =
            (i + 1 < e && g.items[i + 1] == it) ||
            (i > s && g.items[i - 1] == it);
        if (!adjacent) {
          pen += 1;
        } else if (g.lessonWh[it] <= 3) {
          pen += 2;
        }
      }
    }
    return pen;
  }

  int teacherPart(_Grid g, int a, int b) {
    final ta = g.lessonTeacher[g.items[a]];
    final tb = g.lessonTeacher[g.items[b]];
    if (ta == tb) return 0;
    final sa = slotOf(g, a);
    final sb = slotOf(g, b);
    return tc(ta, sa) + tc(ta, sb) + tc(tb, sa) + tc(tb, sb);
  }

  int softPart(_Grid g, int a, int b) {
    final da = g.cellDay[a];
    final db = g.cellDay[b];
    return dayPen(g, da) + (db != da ? dayPen(g, db) : 0);
  }

  void swap(_Grid g, int a, int b) {
    final ia = g.items[a];
    final ib = g.items[b];
    final ta = g.lessonTeacher[ia];
    final tb = g.lessonTeacher[ib];
    final sa = slotOf(g, a);
    final sb = slotOf(g, b);
    cnt[ta * stride + sa]--;
    cnt[tb * stride + sb]--;
    cnt[ta * stride + sb]++;
    cnt[tb * stride + sa]++;
    g.items[a] = ib;
    g.items[b] = ia;
  }

  int softTotal() {
    int s = 0;
    for (final g in grids) {
      for (int d = 0; d < _days.length; d++) {
        s += dayPen(g, d);
      }
    }
    return s;
  }

  bool run() {
    cnt.fillRange(0, cnt.length, 0);
    for (final g in grids) {
      g.items.shuffle(rng);
    }
    addAll();
    int conflicts = totalConflicts();
    int softIters = 0;
    for (int iter = 0; iter < 60000; iter++) {
      if (conflicts == 0) {
        softIters++;
        if (softIters > 4000) break;
        if (softIters % 500 == 0 && softTotal() == 0) break;
      }
      final g = grids[rng.nextInt(grids.length)];
      final a = rng.nextInt(g.total);
      final ta = g.lessonTeacher[g.items[a]];
      final conflicted = cnt[ta * stride + slotOf(g, a)] > 1;
      if (!conflicted && rng.nextDouble() > (conflicts == 0 ? 0.6 : 0.03)) {
        continue;
      }
      int bestB = -1;
      int bestDelta = 1 << 30;
      int bestTDelta = 0;
      for (int k = 0; k < 14; k++) {
        final b = rng.nextInt(g.total);
        if (b == a || g.items[a] == g.items[b]) continue;
        final before = 10 * teacherPart(g, a, b) + softPart(g, a, b);
        final tBefore = teacherPart(g, a, b);
        swap(g, a, b);
        final after = 10 * teacherPart(g, a, b) + softPart(g, a, b);
        final tAfter = teacherPart(g, a, b);
        swap(g, a, b);
        // Çakışmasız hâlde öğretmen çakışması üretecek hamleleri reddet.
        if (conflicts == 0 && tAfter > tBefore) continue;
        final delta = after - before;
        if (delta < bestDelta) {
          bestDelta = delta;
          bestB = b;
          bestTDelta = tAfter - tBefore;
        }
      }
      if (bestB < 0) continue;
      if (bestDelta < 0 || (bestDelta == 0 && rng.nextDouble() < 0.3)) {
        swap(g, a, bestB);
        conflicts += bestTDelta;
      }
    }
    return conflicts == 0;
  }

  for (int attempt = 0; attempt < 8; attempt++) {
    if (run()) {
      return _Plan(grids, teachers, teacherByClassLesson);
    }
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════
//  Plan konuları
// ═══════════════════════════════════════════════════════════════════════

List<List<String>> _topicsFor(String lessonName) {
  const matematik = [
    [
      '1. Ünite: Sayılar',
      'Doğal sayılar ve işlemler',
      'Doğal sayılarla dört işlemi yapar.',
    ],
    [
      '1. Ünite: Sayılar',
      'Bölünebilme kuralları',
      'Bölünebilme kurallarını uygular.',
    ],
    ['1. Ünite: Sayılar', 'EBOB - EKOK', 'EBOB ve EKOK problemlerini çözer.'],
    [
      '2. Ünite: Cebir',
      'Cebirsel ifadeler',
      'Cebirsel ifadeleri sadeleştirir.',
    ],
    ['2. Ünite: Cebir', 'Denklemler', 'Birinci dereceden denklemleri çözer.'],
    [
      '3. Ünite: Geometri',
      'Açılar ve üçgenler',
      'Üçgenlerde açı özelliklerini kullanır.',
    ],
  ];
  const turkce = [
    [
      '1. Ünite: Okuma',
      'Metin türleri ve ana fikir',
      'Metnin ana fikrini belirler.',
    ],
    [
      '1. Ünite: Okuma',
      'Söz varlığı ve deyimler',
      'Deyim ve atasözlerini anlamına uygun kullanır.',
    ],
    [
      '2. Ünite: Dil Bilgisi',
      'Sözcükte yapı',
      'Sözcüklerin yapısını ayırt eder.',
    ],
    [
      '2. Ünite: Dil Bilgisi',
      'Cümle türleri',
      'Cümleleri yapı ve anlam yönünden sınıflandırır.',
    ],
    ['3. Ünite: Yazma', 'Paragraf yazma', 'Planlı paragraf oluşturur.'],
    ['3. Ünite: Yazma', 'Hikâye edici anlatım', 'Hikâye edici metin yazar.'],
  ];
  const fen = [
    [
      '1. Ünite: Canlılar',
      'Hücre ve organeller',
      'Hücre organellerinin görevlerini açıklar.',
    ],
    [
      '1. Ünite: Canlılar',
      'Canlıların sınıflandırılması',
      'Canlıları ortak özelliklerine göre sınıflandırır.',
    ],
    [
      '2. Ünite: Madde',
      'Maddenin tanecikli yapısı',
      'Maddenin tanecikli yapısını modelle açıklar.',
    ],
    ['2. Ünite: Madde', 'Isı ve sıcaklık', 'Isı ve sıcaklık farkını açıklar.'],
    [
      '3. Ünite: Kuvvet',
      'Kuvvet ve hareket',
      'Kuvvetin hareket üzerindeki etkisini yorumlar.',
    ],
    ['3. Ünite: Kuvvet', 'Basınç', 'Basıncı etkileyen faktörleri belirler.'],
  ];
  const ingilizce = [
    [
      'Unit 1: Hello',
      'Greetings and introductions',
      'Kendini ve başkalarını tanıtır.',
    ],
    ['Unit 2: My Day', 'Daily routines', 'Günlük rutinlerini anlatır.'],
    [
      'Unit 3: Places',
      'Prepositions of place',
      'Yer bildiren sözcükleri kullanır.',
    ],
    [
      'Unit 4: Food',
      'Likes and dislikes',
      'Sevdiği ve sevmediği şeyleri ifade eder.',
    ],
    ['Unit 5: Past', 'Simple past tense', 'Geçmiş zaman cümleleri kurar.'],
    ['Unit 6: Future', 'Future plans', 'Gelecek planlarını anlatır.'],
  ];
  const sosyal = [
    [
      '1. Ünite: Birey ve Toplum',
      'Kültürel miras',
      'Kültürel mirasın önemini açıklar.',
    ],
    [
      '1. Ünite: Birey ve Toplum',
      'Toplumsal roller',
      'Toplumsal rolleri örneklerle açıklar.',
    ],
    ['2. Ünite: Harita', 'Harita bilgisi', 'Harita okuyarak konum belirler.'],
    [
      '2. Ünite: Harita',
      'İklim ve doğal afetler',
      'İklim özelliklerini karşılaştırır.',
    ],
    [
      '3. Ünite: Tarih',
      'İlk Türk devletleri',
      'İlk Türk devletlerinin özelliklerini açıklar.',
    ],
    [
      '3. Ünite: Tarih',
      'Anadolu\'nun Türkleşmesi',
      'Anadolu\'ya yapılan göçleri değerlendirir.',
    ],
  ];
  const fizik = [
    [
      '1. Ünite: Fizik Bilimi',
      'Fizik bilimine giriş ve ölçme',
      'Fiziksel nicelikleri ölçer.',
    ],
    [
      '2. Ünite: Madde ve Özellikleri',
      'Dayanıklılık ve yoğunluk',
      'Yoğunluk problemlerini çözer.',
    ],
    [
      '3. Ünite: Hareket',
      'Doğrusal hareket',
      'Hız-zaman grafiklerini yorumlar.',
    ],
    [
      '3. Ünite: Hareket',
      'Newton\'un hareket yasaları',
      'Newton yasalarını günlük olaylara uygular.',
    ],
    ['4. Ünite: Enerji', 'İş, güç ve enerji', 'İş-enerji ilişkisini kurar.'],
    ['5. Ünite: Isı', 'Isı ve sıcaklık', 'Isı alışverişi problemlerini çözer.'],
  ];
  const kimya = [
    [
      '1. Ünite: Kimya Bilimi',
      'Kimyanın alt dalları ve laboratuvar güvenliği',
      'Laboratuvar güvenlik kurallarını uygular.',
    ],
    ['2. Ünite: Atom', 'Atom modelleri', 'Atom modellerini karşılaştırır.'],
    [
      '2. Ünite: Atom',
      'Periyodik sistem',
      'Elementleri periyodik sistemde konumlandırır.',
    ],
    ['3. Ünite: Etkileşimler', 'Kimyasal bağlar', 'Bağ türlerini ayırt eder.'],
    [
      '4. Ünite: Maddenin Halleri',
      'Gazlar',
      'Gaz yasalarını problemlerde kullanır.',
    ],
    ['5. Ünite: Karışımlar', 'Çözeltiler', 'Derişim hesaplamaları yapar.'],
  ];
  const biyoloji = [
    [
      '1. Ünite: Yaşam Bilimi',
      'Canlıların ortak özellikleri',
      'Canlıların ortak özelliklerini açıklar.',
    ],
    [
      '2. Ünite: Hücre',
      'Hücre zarı ve madde geçişleri',
      'Madde geçiş mekanizmalarını karşılaştırır.',
    ],
    ['2. Ünite: Hücre', 'Hücresel solunum', 'Solunum basamaklarını özetler.'],
    ['3. Ünite: Kalıtım', 'Mendel genetiği', 'Çaprazlama problemlerini çözer.'],
    ['4. Ünite: Ekosistem', 'Besin zincirleri', 'Enerji akışını yorumlar.'],
    [
      '5. Ünite: Sistemler',
      'Sindirim sistemi',
      'Sindirim sistemi organlarını görevleriyle eşleştirir.',
    ],
  ];
  const edebiyat = [
    [
      '1. Ünite: Giriş',
      'Edebiyatın tanımı ve sanat dalları',
      'Edebiyat-sanat ilişkisini açıklar.',
    ],
    [
      '2. Ünite: Hikâye',
      'Hikâyenin unsurları',
      'Hikâyenin yapı unsurlarını belirler.',
    ],
    [
      '3. Ünite: Şiir',
      'Şiirde ahenk unsurları',
      'Şiirde ahenk unsurlarını bulur.',
    ],
    [
      '4. Ünite: Destan',
      'Destan geleneği',
      'Destanların özelliklerini açıklar.',
    ],
    ['5. Ünite: Tiyatro', 'Tiyatro türleri', 'Tiyatro türlerini ayırt eder.'],
    ['6. Ünite: Roman', 'Romanın unsurları', 'Roman unsurlarını inceler.'],
  ];
  const tarih = [
    [
      '1. Ünite: Tarih Bilimi',
      'Tarih ve zaman',
      'Tarihin kaynaklarını sınıflandırır.',
    ],
    [
      '2. Ünite: İlk Uygarlıklar',
      'Mezopotamya ve Mısır',
      'İlk uygarlıkların özelliklerini açıklar.',
    ],
    [
      '3. Ünite: İslamiyet',
      'İslamiyet\'in doğuşu',
      'İslamiyet\'in yayılışını değerlendirir.',
    ],
    [
      '4. Ünite: Türk Tarihi',
      'Orta Asya Türk devletleri',
      'Türk devletlerinin kurumlarını açıklar.',
    ],
    [
      '5. Ünite: Selçuklular',
      'Büyük Selçuklu Devleti',
      'Selçuklu siyasetini yorumlar.',
    ],
    [
      '6. Ünite: Osmanlı',
      'Osmanlı\'nın kuruluşu',
      'Kuruluş dönemini kronolojik sıralar.',
    ],
  ];
  const cografya = [
    [
      '1. Ünite: Doğa ve İnsan',
      'Coğrafyanın konusu',
      'Coğrafi bakış açısını açıklar.',
    ],
    [
      '2. Ünite: Dünya',
      'Dünya\'nın şekli ve hareketleri',
      'Dünya\'nın hareketlerinin sonuçlarını açıklar.',
    ],
    [
      '3. Ünite: Harita',
      'Harita bilgisi ve koordinatlar',
      'Koordinat sisteminde yer belirler.',
    ],
    ['4. Ünite: İklim', 'İklim elemanları', 'İklim elemanlarını yorumlar.'],
    [
      '5. Ünite: Yerşekilleri',
      'İç ve dış kuvvetler',
      'Yerşekillerini oluşum süreçleriyle ilişkilendirir.',
    ],
    [
      '6. Ünite: Nüfus',
      'Nüfus ve göç',
      'Nüfus dağılışını etkileyen faktörleri açıklar.',
    ],
  ];
  const hayat = [
    ['1. Ünite: Okulumuzda Hayat', 'Okul kuralları', 'Okul kurallarına uyar.'],
    [
      '2. Ünite: Evimizde Hayat',
      'Aile bireyleri ve görevleri',
      'Ailedeki görev paylaşımını açıklar.',
    ],
    [
      '3. Ünite: Sağlıklı Hayat',
      'Dengeli beslenme',
      'Sağlıklı besinleri seçer.',
    ],
    [
      '4. Ünite: Güvenli Hayat',
      'Trafik kuralları',
      'Trafik kurallarını sıralar.',
    ],
    [
      '5. Ünite: Ülkemizde Hayat',
      'Millî bayramlarımız',
      'Millî bayramların anlamını açıklar.',
    ],
    [
      '6. Ünite: Doğada Hayat',
      'Mevsimler ve canlılar',
      'Mevsimlerin canlılara etkisini gözlemler.',
    ],
  ];
  const din = [
    ['1. Ünite: İnanç', 'Allah inancı', 'İnanç esaslarını açıklar.'],
    [
      '2. Ünite: İbadet',
      'İbadetin anlamı',
      'İbadetlerin bireye katkılarını açıklar.',
    ],
    [
      '3. Ünite: Ahlak',
      'Güzel ahlak ve davranışlar',
      'Güzel ahlak örneklerini sıralar.',
    ],
    [
      '4. Ünite: Hz. Muhammed',
      'Peygamberimizin hayatı',
      'Hz. Muhammed\'in hayatından örnekler verir.',
    ],
    [
      '5. Ünite: Değerler',
      'Paylaşma ve yardımlaşma',
      'Yardımlaşmanın önemini açıklar.',
    ],
    [
      '6. Ünite: Kültür',
      'Dinî bayramlar',
      'Dinî bayramların toplumsal işlevini açıklar.',
    ],
  ];
  const beden = [
    [
      '1. Ünite: Hareket',
      'Isınma ve esneme hareketleri',
      'Isınma hareketlerini doğru uygular.',
    ],
    ['2. Ünite: Atletizm', 'Koşu teknikleri', 'Koşu tekniklerini uygular.'],
    [
      '3. Ünite: Takım Sporları',
      'Voleybol temel beceriler',
      'Voleybolda temel becerileri sergiler.',
    ],
    [
      '3. Ünite: Takım Sporları',
      'Basketbol temel beceriler',
      'Basketbolda top sürme ve pas yapar.',
    ],
    [
      '4. Ünite: Oyun',
      'Geleneksel çocuk oyunları',
      'Geleneksel oyunları kurallarına uygun oynar.',
    ],
    [
      '5. Ünite: Sağlık',
      'Fiziksel uygunluk',
      'Fiziksel uygunluk testlerine katılır.',
    ],
  ];
  const gorsel = [
    [
      '1. Ünite: Çizgi',
      'Çizgi çalışmaları',
      'Çizgi türlerini kullanarak kompozisyon yapar.',
    ],
    ['2. Ünite: Renk', 'Renk çemberi', 'Ana ve ara renkleri ayırt eder.'],
    [
      '3. Ünite: Desen',
      'Doğadan desen çalışması',
      'Doğal formları gözlemleyerek çizer.',
    ],
    [
      '4. Ünite: Kolaj',
      'Kolaj tasarımı',
      'Farklı malzemelerle kolaj hazırlar.',
    ],
    [
      '5. Ünite: Resim',
      'Manzara resmi',
      'Perspektif kullanarak manzara çizer.',
    ],
    ['6. Ünite: Sergi', 'Sergi hazırlığı', 'Çalışmalarını sergiler.'],
  ];
  const muzik = [
    [
      '1. Ünite: Dinleme',
      'Ses ve nota bilgisi',
      'Notaların sürelerini ayırt eder.',
    ],
    [
      '2. Ünite: Söyleme',
      'Millî marşlarımız',
      'İstiklal Marşı\'nı doğru söyler.',
    ],
    ['3. Ünite: Ritim', 'Ritim çalışmaları', 'Basit ritimleri uygular.'],
    ['4. Ünite: Çalgı', 'Orff çalgıları', 'Çalgıyla eşlik yapar.'],
    ['5. Ünite: Halk Müziği', 'Türkü türleri', 'Yöresel türküleri tanır.'],
    [
      '6. Ünite: Müzik Kültürü',
      'Müzik ve toplum',
      'Müziğin toplumsal işlevini açıklar.',
    ],
  ];

  if (lessonName.contains('Matematik')) return matematik;
  if (lessonName.contains('Türkçe')) return turkce;
  if (lessonName.contains('Edebiyat')) return edebiyat;
  if (lessonName.contains('İngilizce')) return ingilizce;
  if (lessonName.contains('Sosyal')) return sosyal;
  if (lessonName.contains('Fizik')) return fizik;
  if (lessonName.contains('Kimya')) return kimya;
  if (lessonName.contains('Biyoloji')) return biyoloji;
  if (lessonName.contains('Fen')) return fen;
  if (lessonName.contains('Tarih')) return tarih;
  if (lessonName.contains('Coğrafya')) return cografya;
  if (lessonName.contains('Hayat')) return hayat;
  if (lessonName.contains('Din')) return din;
  if (lessonName.contains('Beden')) return beden;
  if (lessonName.contains('Görsel')) return gorsel;
  if (lessonName.contains('Müzik')) return muzik;
  return [
    [
      '1. Ünite',
      '$lessonName - Giriş ve temel kavramlar',
      'Temel kavramları açıklar.',
    ],
    [
      '1. Ünite',
      '$lessonName - Uygulama çalışmaları',
      'Öğrendiklerini uygular.',
    ],
    [
      '2. Ünite',
      '$lessonName - Konu pekiştirme',
      'Konuyu örneklerle pekiştirir.',
    ],
    ['2. Ünite', '$lessonName - Değerlendirme', 'Kazanımları değerlendirir.'],
  ];
}
