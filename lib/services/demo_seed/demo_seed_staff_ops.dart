import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'demo_seed_context.dart';

/// Personel operasyonları demo verisi: izinler, geçici öğretmen atamaları,
/// nöbet programı, geziler, proje ödevleri, görevler, vardiya/devam kayıtları.

/// Yazılan tüm üst düzey koleksiyonlar (hepsinde `institutionId` vardır).
const List<String> demoStaffOpsTopCollections = [
  'leave_requests',
  'temporaryTeacherAssignments',
  'workPeriods',
  'dutyLocations',
  'dutyRules',
  'dutyScheduleItems',
  'field_trips',
  'project_assignments',
  'tasks',
  'shift_templates',
  'staff_shift_assignments',
  'staff_attendance',
  'staff_overtime',
];

/// `schools/{schoolDocId}/` altına yazılan alt koleksiyon yok.
const List<String> demoStaffOpsSchoolSubcollections = [];

/// Üst düzey/alt koleksiyon listeleriyle silinemeyen ek demo dokümanları yok.
Future<int> cleanDemoStaffOpsExtras(
  FirebaseFirestore db,
  String inst,
  String prefix,
  String schoolDocId,
) async {
  return 0;
}

const List<String> _dayNames = [
  '',
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _nextWeekday(DateTime d) {
  var x = _day(d);
  while (x.weekday > 5) {
    x = x.add(const Duration(days: 1));
  }
  return x;
}

class _LeaveRec {
  final String id;
  final DemoTeacherInfo teacher;
  final DateTime start;
  final DateTime end;
  final String status;
  _LeaveRec(this.id, this.teacher, this.start, this.end, this.status);
}

class _LeaveSpec {
  final int offset;
  final int len;
  final String type;
  final String status;
  final String note;
  final bool full;
  const _LeaveSpec(
    this.offset,
    this.len,
    this.type,
    this.status,
    this.note, [
    this.full = true,
  ]);
}

Future<void> seedDemoStaffOps(DemoSeedContext ctx) async {
  if (ctx.teachers.isEmpty) return;
  final today = _day(ctx.today);
  final termStart = _day(ctx.termStart);
  final teachers = List<DemoTeacherInfo>.from(ctx.teachers);

  final leaves = await _seedLeaves(ctx, teachers, today, termStart);
  await _seedSubstitutes(ctx, teachers, leaves, today);
  await _seedDuties(ctx, teachers, today, termStart);
  await _seedFieldTrips(ctx, teachers, today);
  await _seedProjects(ctx, teachers, today);
  await _seedTasks(ctx, teachers, today);
  await _seedShiftsAndAttendance(ctx, teachers, leaves, today);
}

// ───────────────────────── İZİNLER ─────────────────────────

Future<List<_LeaveRec>> _seedLeaves(
  DemoSeedContext ctx,
  List<DemoTeacherInfo> teachers,
  DateTime today,
  DateTime termStart,
) async {
  const specs = <_LeaveSpec>[
    // Bugün civarı (geçici görevlendirme için kullanılır)
    _LeaveSpec(-1, 3, 'Rapor', 'approved', 'Grip nedeniyle istirahat raporu.'),
    _LeaveSpec(0, 2, 'Mazeret İzni', 'approved', 'Ailevi mazeret.'),
    _LeaveSpec(2, 2, 'Yıllık İzin', 'lessons_assigned', 'Kısa tatil planı.'),
    _LeaveSpec(
      4,
      1,
      'Mazeret İzni',
      'pending',
      'Resmi işlem için izin talebi.',
    ),
    // Geçmiş
    _LeaveSpec(
      -45,
      1,
      'Mazeret İzni',
      'approved',
      'Veli toplantısı sonrası özel işler.',
    ),
    _LeaveSpec(
      -38,
      2,
      'Rapor',
      'approved',
      'Sağlık kontrolü ve dinlenme raporu.',
    ),
    _LeaveSpec(-30, 5, 'Yıllık İzin', 'approved', 'Yıllık izin kullanımı.'),
    _LeaveSpec(
      -26,
      1,
      'Mazeret İzni',
      'rejected',
      'Sınav haftasına denk geldiği için uygun görülmedi.',
    ),
    _LeaveSpec(
      -21,
      1,
      'Mazeret İzni',
      'approved',
      'Saatlik izin - banka işlemi.',
      false,
    ),
    _LeaveSpec(-17, 3, 'Ücretsiz İzin', 'approved', 'Ücretsiz izin talebi.'),
    _LeaveSpec(-12, 1, 'Rapor', 'approved', 'Diş tedavisi.'),
    _LeaveSpec(
      -9,
      1,
      'Mazeret İzni',
      'rejected',
      'Yerine görevlendirilecek öğretmen bulunamadı.',
    ),
    _LeaveSpec(-6, 2, 'Yıllık İzin', 'approved', 'Aile ziyareti.'),
    // Gelecek
    _LeaveSpec(7, 1, 'Mazeret İzni', 'pending', 'Çocuğun okul gezisi.'),
    _LeaveSpec(9, 3, 'Yıllık İzin', 'pending', 'Yıllık izin talebi.'),
    _LeaveSpec(
      12,
      1,
      'Mazeret İzni',
      'duties_checked',
      'Saatlik izin - hastane randevusu.',
      false,
    ),
    _LeaveSpec(15, 2, 'Rapor', 'pending', 'Planlı küçük operasyon.'),
    _LeaveSpec(20, 1, 'Mazeret İzni', 'pending', 'Nüfus müdürlüğü işlemleri.'),
  ];

  final shuffled = List<DemoTeacherInfo>.from(teachers)..shuffle(ctx.rng);
  final out = <_LeaveRec>[];
  var i = 0;
  for (final s in specs) {
    final t = shuffled[i % shuffled.length];
    i++;
    var start = _nextWeekday(today.add(Duration(days: s.offset)));
    if (start.isBefore(termStart)) start = _nextWeekday(termStart);
    final end = start.add(Duration(days: s.len - 1));
    final totalDays = end.difference(start).inDays + 1;
    final id = ctx.id('leave_$i');
    final createdAt = start.subtract(Duration(days: ctx.between(2, 7)));
    final decided = s.status == 'approved' || s.status == 'rejected';
    String managerNote = '';
    if (s.status == 'approved') managerNote = 'Uygundur, onaylandı.';
    if (s.status == 'rejected') managerNote = s.note;
    final lessonConf = ctx.between(0, 6);
    final dutyConf = ctx.between(0, 1);
    await ctx.set(ctx.col('leave_requests').doc(id), {
      'staffId': t.id,
      'userId': t.id,
      'institutionId': ctx.inst,
      'schoolTypeId': t.typeId,
      'leaveType': s.type,
      'type': s.type,
      'startDate': _ymd(start),
      'endDate': _ymd(end),
      'totalDays': totalDays,
      'status': s.status,
      'note': s.status == 'rejected'
          ? 'Mazeret nedeniyle izin talebi.'
          : s.note,
      'reason': s.status == 'rejected'
          ? 'Mazeret nedeniyle izin talebi.'
          : s.note,
      'managerNote': managerNote,
      'createdAt': Timestamp.fromDate(createdAt.add(const Duration(hours: 10))),
      if (decided)
        'updatedAt': Timestamp.fromDate(
          createdAt.add(const Duration(days: 1, hours: 14)),
        ),
      'createdByRole': 'teacher',
      'lessonConflicts': s.full ? lessonConf : 1,
      'dutyConflicts': dutyConf,
      'isFullDay': s.full,
      'startTime': s.full ? null : '10:00',
      'endTime': s.full ? null : '12:00',
      'termId': ctx.termId,
      if (s.status == 'lessons_assigned')
        'temporaryTeacherId': shuffled[(i + 3) % shuffled.length].id,
    });
    ctx.count('İzin talebi');
    out.add(_LeaveRec(id, t, start, end, s.status));
  }
  return out;
}

// ───────────────────── GEÇİCİ ÖĞRETMEN ATAMALARI ─────────────────────

Future<void> _seedSubstitutes(
  DemoSeedContext ctx,
  List<DemoTeacherInfo> teachers,
  List<_LeaveRec> leaves,
  DateTime today,
) async {
  if (teachers.length < 2) return;
  var n = 0;
  for (final lv in leaves) {
    if (lv.status != 'approved' && lv.status != 'lessons_assigned') continue;
    if (lv.end.isBefore(today.subtract(const Duration(days: 20))) ||
        lv.start.isAfter(today.add(const Duration(days: 14)))) {
      continue;
    }
    // Öğretmenin dersleri
    final slots = <List<Object>>[];
    for (final c in ctx.classes) {
      for (final l in c.lessons) {
        if (l.teacherId == lv.teacher.id) slots.add([c, l]);
      }
    }
    if (slots.isEmpty) continue;

    var date = lv.start;
    var dayCount = 0;
    while (!date.isAfter(lv.end) && dayCount < 3) {
      if (date.weekday <= 5) {
        dayCount++;
        final take = math.min(3, slots.length);
        for (var k = 0; k < take; k++) {
          final slot = slots[(k + dayCount) % slots.length];
          final c = slot[0] as DemoClassInfo;
          final l = slot[1] as DemoLessonInfo;
          final others = teachers.where((t) => t.id != lv.teacher.id).toList();
          final sameBranch = others
              .where((t) => t.branch == lv.teacher.branch)
              .toList();
          final sub = sameBranch.isNotEmpty && ctx.rng.nextBool()
              ? ctx.pick(sameBranch)
              : ctx.pick(others);
          n++;
          final isPast = date.isBefore(today);
          await ctx.set(
            ctx.col('temporaryTeacherAssignments').doc(ctx.id('sub_$n')),
            {
              'institutionId': ctx.inst,
              'schoolTypeId': c.typeId,
              'originalTeacherId': lv.teacher.id,
              'originalTeacherName': lv.teacher.fullName,
              'substituteTeacherId': sub.id,
              'substituteTeacherName': sub.fullName,
              'classId': c.id,
              'className': c.name,
              'lessonId': l.id,
              'lessonName': l.name,
              'date': Timestamp.fromDate(date),
              'hourIndex': (k * 2 + dayCount) % 7,
              'dayName': _dayNames[date.weekday],
              'reason': lv.status == 'approved' && isPast
                  ? 'İzinli'
                  : (ctx.rng.nextBool() ? 'Raporlu' : 'İzinli'),
              'status': isPast || k == 0 ? 'published' : 'pending',
              'createdAt': Timestamp.fromDate(
                date
                    .subtract(const Duration(days: 1))
                    .add(const Duration(hours: 15)),
              ),
              'creatorId': sub.id,
              'termId': ctx.termId,
            },
          );
          ctx.count('Geçici öğretmen ataması');
        }
      }
      date = date.add(const Duration(days: 1));
    }
  }
}

// ───────────────────────── NÖBETLER ─────────────────────────

Future<void> _seedDuties(
  DemoSeedContext ctx,
  List<DemoTeacherInfo> teachers,
  DateTime today,
  DateTime termStart,
) async {
  const locDefs = <List<Object>>[
    ['Bahçe Nöbeti', 'Dış Alan', '08:00', '15:30', false],
    ['Okul Giriş Kapısı', 'Dış Alan', '07:45', '15:45', false],
    ['1. Kat Koridoru', 'Kat Nöbetleri', '08:30', '15:30', false],
    ['2. Kat Koridoru', 'Kat Nöbetleri', '08:30', '15:30', false],
    ['Kantin / Yemekhane', 'Genel', '11:30', '14:00', false],
    ['Nöbetçi Yönetici', 'Yönetim', '08:00', '16:00', true],
  ];

  // Nöbet yerleri (kuruma özel, tüm okul türleri paylaşır)
  final locIds = <String>[];
  final locNames = <String>[];
  for (var i = 0; i < locDefs.length; i++) {
    final d = locDefs[i];
    final id = ctx.id('dutyloc_${i + 1}');
    locIds.add(id);
    locNames.add(d[0] as String);
    await ctx.set(ctx.col('dutyLocations').doc(id), {
      'id': id,
      'institutionId': ctx.inst,
      'name': d[0],
      'activeDays': <int>[1, 2, 3, 4, 5],
      'startTime': d[2],
      'endTime': d[3],
      'description': '${d[0]} - ${d[1]}',
      'checkOtherDays': true,
      'order': i,
      'group': d[1],
      'isAmir': d[4],
      'eligibilities': <String, dynamic>{},
    });
    ctx.count('Nöbet yeri');
  }

  await ctx.set(ctx.col('dutyRules').doc(ctx.id('dutyrules')), {
    'institutionId': ctx.inst,
    'rotateLocations': true,
  });

  final monday = today.subtract(Duration(days: today.weekday - 1));
  final periodStart = termStart;
  final periodEnd = today.add(const Duration(days: 90));

  final types = ctx.types.isEmpty ? <DemoTypeDef>[] : ctx.types;
  final typeIds = types.isEmpty
      ? <String>['']
      : types.map((t) => t.id).toList();
  final typeNames = types.isEmpty
      ? <String>['']
      : types.map((t) => t.name).toList();

  for (var ti = 0; ti < typeIds.length; ti++) {
    final typeId = typeIds[ti];
    var pool = teachers.where((t) => t.typeId == typeId).toList();
    if (pool.length < 6) pool = List<DemoTeacherInfo>.from(teachers);
    if (pool.length < 2) continue;

    final periodId = ctx.id('wp_duty_$ti');
    final configs = <String, dynamic>{};
    for (var i = 0; i < locIds.length; i++) {
      configs[locIds[i]] = {
        'isEnabled': true,
        'activeDays': <int>[1, 2, 3, 4, 5],
        'startTime': locDefs[i][2],
        'endTime': locDefs[i][3],
        'order': i,
        'group': locDefs[i][1],
      };
    }
    await ctx.set(ctx.col('workPeriods').doc(periodId), {
      'institutionId': ctx.inst,
      'schoolTypeId': typeId,
      'schoolTypeName': typeNames[ti],
      'termId': ctx.termId,
      'name':
          'Nöbet Dönemi${typeNames[ti].isEmpty ? '' : ' - ${typeNames[ti]}'}',
      'startDate': Timestamp.fromDate(periodStart),
      'endDate': Timestamp.fromDate(periodEnd),
      'isActive': true,
      'dutyLocationConfigs': configs,
      'createdAt': Timestamp.fromDate(periodStart),
    });

    var seq = 0;
    for (var w = -2; w <= 2; w++) {
      final ws = monday.add(Duration(days: 7 * w));
      for (var d = 1; d <= 5; d++) {
        final date = ws.add(Duration(days: d - 1));
        final used = <String>{};
        for (var li = 0; li < locIds.length; li++) {
          DemoTeacherInfo? chosen;
          for (var tries = 0; tries < pool.length; tries++) {
            final cand =
                pool[((w + 2) * 5 + (d - 1) * 3 + li * 2 + ti + tries) %
                    pool.length];
            if (!used.contains(cand.id)) {
              chosen = cand;
              break;
            }
          }
          if (chosen == null) continue;
          used.add(chosen.id);
          seq++;
          final past = date.isBefore(today);
          await ctx.set(
            ctx.col('dutyScheduleItems').doc(ctx.id('duty_${ti}_$seq')),
            {
              'institutionId': ctx.inst,
              'periodId': periodId,
              'termId': ctx.termId,
              'schoolTypeId': typeId,
              'scopeType': 'alt_donem',
              'locationId': locIds[li],
              'locationName': locNames[li],
              'dayOfWeek': d,
              'teacherId': chosen.id,
              'teacherName': chosen.fullName,
              'weekStart': ws.toIso8601String(),
              'dutyDate': _ymd(date),
              'sendNotification': false,
              'notificationSent': past,
              'notifiedTeacherId': past ? chosen.id : null,
            },
          );
          ctx.count('Nöbet kaydı');
        }
      }
    }
  }
}

// ───────────────────────── GEZİLER ─────────────────────────

Future<void> _seedFieldTrips(
  DemoSeedContext ctx,
  List<DemoTeacherInfo> teachers,
  DateTime today,
) async {
  if (ctx.classes.isEmpty) return;
  const trips = <List<Object>>[
    [
      'Bilim Merkezi Gezisi',
      'Fen bilimleri konularını deneyerek öğrenmek.',
      -40,
      120.0,
    ],
    [
      'Tarihi Yarımada Kültür Gezisi',
      'Tarih ve kültürel mirası yerinde görmek.',
      -14,
      150.0,
    ],
    [
      'Planetaryum ve Müze Gezisi',
      'Astronomi ve doğa tarihi etkinlikleri.',
      12,
      135.0,
    ],
    [
      'Teknoloji Fuarı Ziyareti',
      'Teknoloji ve girişimcilik fuarını gezmek.',
      28,
      0.0,
    ],
  ];

  for (var i = 0; i < trips.length; i++) {
    final t = trips[i];
    final c0 = ctx.classes[i % ctx.classes.length];
    final sameLevel = ctx.classes
        .where((c) => c.typeId == c0.typeId && c.level == c0.level)
        .toList();
    final students = <DemoStudentInfo>[];
    for (final c in sameLevel) {
      students.addAll(ctx.studentsByClass[c.id] ?? const <DemoStudentInfo>[]);
    }
    if (students.isEmpty) continue;
    // Katılan öğrenciler (~80%)
    final participants = students
        .where((s) => ctx.rng.nextInt(100) < 80)
        .toList();
    if (participants.isEmpty) participants.add(students.first);

    final offset = t[2] as int;
    final amount = t[3] as double;
    final dep = DateTime(
      today.year,
      today.month,
      today.day,
      8,
      30,
    ).add(Duration(days: offset));
    final ret = DateTime(dep.year, dep.month, dep.day, 16, 0);
    final past = offset < 0;

    final paymentStatus = <String, bool>{};
    if (amount > 0) {
      for (final s in participants) {
        paymentStatus[s.id] = past ? true : ctx.rng.nextInt(100) < 55;
      }
    }

    // İki grup
    final half = (participants.length / 2).ceil();
    final g1 = participants.sublist(0, half);
    final g2 = participants.sublist(half);
    final tPool = List<DemoTeacherInfo>.from(teachers)..shuffle(ctx.rng);
    final groups = <Map<String, dynamic>>[];
    final groupSets = <List<DemoStudentInfo>>[g1, g2];
    for (var g = 0; g < groupSets.length; g++) {
      if (groupSets[g].isEmpty) continue;
      final gt = [
        tPool[(g * 2) % tPool.length],
        tPool[(g * 2 + 1) % tPool.length],
      ];
      groups.add({
        'id': ctx.id('trip${i}_g$g'),
        'name': '${g + 1}. Grup',
        'teacherIds': gt.map((e) => e.id).toList(),
        'teacherNames': gt.map((e) => e.fullName).toList(),
        'studentIds': groupSets[g].map((e) => e.id).toList(),
        'vehiclePlate': g == 0 ? '34 DMO 4${i}1' : '34 DMO 4${i}2',
        'driverPhone': '0532 555 0${i}${g}0',
      });
    }

    final typeName = ctx.types
        .where((e) => e.id == c0.typeId)
        .map((e) => e.name)
        .firstWhere((_) => true, orElse: () => c0.typeName);

    await ctx.set(ctx.col('field_trips').doc(ctx.id('trip_$i')), {
      'institutionId': ctx.inst,
      'schoolTypeId': c0.typeId,
      'schoolTypeName': typeName,
      'name': t[0],
      'purpose': t[1],
      'departureTime': Timestamp.fromDate(dep),
      'returnTime': Timestamp.fromDate(ret),
      'classLevel': c0.level.toString(),
      'targetBranchIds': sameLevel.map((c) => c.id).toList(),
      'targetStudentIds': participants.map((s) => s.id).toList(),
      'totalStudents': participants.length,
      'participationSurveyId': null,
      'surveyPublishDate': null,
      'manualParticipationStatus': <String, String>{},
      'isPaid': amount > 0,
      'amount': amount,
      'paymentStatus': paymentStatus,
      'feedbackSurveyId': null,
      'groups': groups,
      'authorId': teachers[i % teachers.length].id,
      'createdAt': Timestamp.fromDate(dep.subtract(const Duration(days: 20))),
      'status': past ? 'completed' : 'planned',
      'termId': ctx.termId,
    });
    ctx.count('Gezi');
  }
}

// ───────────────────────── PROJE ÖDEVLERİ ─────────────────────────

Future<void> _seedProjects(
  DemoSeedContext ctx,
  List<DemoTeacherInfo> teachers,
  DateTime today,
) async {
  if (ctx.classes.isEmpty) return;

  const topicBank = <String, List<String>>{
    'default': [
      'Güncel bir konuyu araştırma raporu',
      'Konuyla ilgili poster ve sunum hazırlama',
      'Mini deney / uygulama tasarımı',
      'Konu hakkında röportaj ve analiz',
    ],
  };
  final topics = topicBank['default']!;

  final levels = ctx.classes.map((c) => c.level).toSet().toList()..sort();
  const names = <String>[
    'Dönem Sonu Proje Ödevi',
    'Bilim ve Teknoloji Projesi',
    'Kitap İnceleme Projesi',
  ];
  const statuses = <String>['active', 'draft', 'completed'];

  for (var p = 0; p < 3; p++) {
    final level = levels[p % levels.length];
    final classes = ctx.classes.where((c) => c.level == level).toList();
    if (classes.isEmpty || classes.first.lessons.isEmpty) continue;
    final status = statuses[p];

    final lessonCount = math.min(2, classes.first.lessons.length);
    final subjects = <Map<String, dynamic>>[];
    final topicIdsBySubject = <int, List<String>>{};
    for (var s = 0; s < lessonCount; s++) {
      final lesson =
          classes.first.lessons[(s + p) % classes.first.lessons.length];
      final topicList = <Map<String, dynamic>>[];
      final tIds = <String>[];
      for (var k = 0; k < 3; k++) {
        final tid = ctx.id('proj${p}_s${s}_t$k');
        tIds.add(tid);
        topicList.add({
          'id': tid,
          'name': '${lesson.name}: ${topics[(k + s) % topics.length]}',
          'description':
              '${lesson.name} dersi kapsamında bireysel proje çalışması.',
          'quotaPerTeacher': 8,
        });
      }
      topicIdsBySubject[s] = tIds;
      subjects.add({
        'id': ctx.id('proj${p}_s$s'),
        'lessonName': lesson.name,
        'targetBranchIds': classes.map((c) => c.id).toList(),
        'topics': topicList,
      });
    }

    final students = <DemoStudentInfo>[];
    for (final c in classes) {
      students.addAll(ctx.studentsByClass[c.id] ?? const <DemoStudentInfo>[]);
    }

    final allocations = <Map<String, dynamic>>[];
    if (status != 'draft') {
      for (final stu in students) {
        final cls = classes.firstWhere(
          (c) => c.id == stu.classId,
          orElse: () => classes.first,
        );
        final s = ctx.rng.nextInt(lessonCount);
        final tIds = topicIdsBySubject[s]!;
        final lessonName = subjects[s]['lessonName'] as String;
        var teacherId = teachers.first.id;
        for (final l in cls.lessons) {
          if (l.name == lessonName) {
            teacherId = l.teacherId;
            break;
          }
        }
        allocations.add({
          'studentId': stu.id,
          'topicId': tIds[ctx.rng.nextInt(tIds.length)],
          'teacherId': teacherId,
          'method': ctx.pick(const [
            'manual',
            'survey_1',
            'survey_2',
            'random',
          ]),
          'allocatedAt': Timestamp.fromDate(
            today.subtract(Duration(days: ctx.between(3, 25))),
          ),
        });
      }
    }

    await ctx.set(ctx.col('project_assignments').doc(ctx.id('projasg_$p')), {
      'id': ctx.id('projasg_$p'),
      'institutionId': ctx.inst,
      'termId': ctx.termId,
      'name': '$level. Sınıf ${names[p]}',
      'createdAt': Timestamp.fromDate(
        today.subtract(Duration(days: 30 + p * 10)),
      ),
      'authorId': teachers[p % teachers.length].id,
      'status': status,
      'targetStudentIds': students.map((s) => s.id).toList(),
      'targetClassLevels': <String>[level.toString()],
      'targetBranchIds': classes.map((c) => c.id).toList(),
      'subjects': subjects,
      'allocations': allocations,
      'surveyId': null,
      'surveyDeadline': status == 'draft'
          ? null
          : Timestamp.fromDate(today.subtract(Duration(days: 20 - p * 5))),
    });
    ctx.count('Proje ödevi');
  }
}

// ───────────────────────── GÖREVLER (TO-DO) ─────────────────────────

Future<void> _seedTasks(
  DemoSeedContext ctx,
  List<DemoTeacherInfo> teachers,
  DateTime today,
) async {
  const defs = <List<Object>>[
    [
      'Sınav evraklarını teslim et',
      'Dönem sınavlarına ait optik formları ve cevap anahtarlarını müdür yardımcılığına teslim ediniz.',
      3,
      'none',
    ],
    [
      'Veli toplantısı sunumu hazırla',
      'Sınıfınızın akademik durumunu özetleyen kısa bir sunum hazırlayınız.',
      6,
      'none',
    ],
    [
      'Haftalık ders planlarını güncelle',
      'Önümüzdeki haftanın ders planlarını sisteme giriniz.',
      2,
      'weekly',
    ],
    [
      'Devamsızlık kayıtlarını kontrol et',
      'Öğrenci devamsızlık kayıtlarında eksik veya hatalı giriş olup olmadığını kontrol ediniz.',
      1,
      'daily',
    ],
    [
      'Kulüp faaliyet raporu',
      'Sorumlu olduğunuz kulübün aylık faaliyet raporunu yazınız.',
      10,
      'monthly',
    ],
    [
      'Laboratuvar envanter sayımı',
      'Laboratuvardaki malzemelerin sayımını yapıp listeyi paylaşınız.',
      -2,
      'none',
    ],
    [
      'Rehberlik anketi uygulaması',
      'Sınıfta rehberlik servisinin hazırladığı anketi uygulayınız.',
      -5,
      'none',
    ],
    [
      'Okul gezisi izin belgeleri',
      'Gezi katılım izin belgelerini velilerden toplayınız.',
      8,
      'none',
    ],
    [
      'Karne notlarını gir',
      'Dönem karne notlarını sisteme girerek onaya gönderiniz.',
      14,
      'none',
    ],
    [
      'Nöbet defterini doldur',
      'Nöbet sırasında yaşanan olayları nöbet defterine işleyiniz.',
      0,
      'weekly',
    ],
    [
      'Etüt planlaması',
      'Hafta içi etüt saatleri için öğrenci listesini oluşturunuz.',
      5,
      'none',
    ],
    [
      'Ders materyali paylaşımı',
      'Ders notlarını ve çalışma kağıtlarını ortak klasöre yükleyiniz.',
      -9,
      'none',
    ],
  ];

  final creator = teachers.first;
  for (var i = 0; i < defs.length; i++) {
    final d = defs[i];
    final offset = d[2] as int;
    final assignCount = 1 + ctx.rng.nextInt(math.min(3, teachers.length));
    final pool = List<DemoTeacherInfo>.from(teachers)..shuffle(ctx.rng);
    final assignees = pool.take(assignCount).toList();

    final deadline = DateTime(
      today.year,
      today.month,
      today.day,
      17,
      0,
    ).add(Duration(days: offset));
    final createdAt = deadline.subtract(Duration(days: ctx.between(5, 12)));

    final completedBy = <String>[];
    final completedAt = <String, dynamic>{};
    final overdue = offset < 0;
    for (final a in assignees) {
      final done = overdue
          ? ctx.rng.nextInt(100) < 60
          : ctx.rng.nextInt(100) < 20;
      if (done) {
        completedBy.add(a.id);
        completedAt[a.id] = Timestamp.fromDate(
          createdAt.add(Duration(days: ctx.between(1, 4), hours: 3)),
        );
      }
    }

    await ctx.set(ctx.col('tasks').doc(ctx.id('task_$i')), {
      'title': d[0],
      'description': d[1],
      'institutionId': ctx.inst,
      'schoolTypeId': assignees.first.typeId,
      'termId': ctx.termId,
      'creatorId': creator.id,
      'creatorName': creator.fullName,
      'createdAt': Timestamp.fromDate(createdAt),
      'deadline': Timestamp.fromDate(deadline),
      'recurrence': d[3],
      'assigneeIds': assignees.map((a) => a.id).toList(),
      'assigneeNames': {for (final a in assignees) a.id: a.fullName},
      'completedBy': completedBy,
      'completedAt': completedAt,
      'isArchived': false,
    });
    ctx.count('Görev');
  }
}

// ───────────────── VARDİYA / PERSONEL DEVAM / MESAİ ─────────────────

Future<void> _seedShiftsAndAttendance(
  DemoSeedContext ctx,
  List<DemoTeacherInfo> teachers,
  List<_LeaveRec> leaves,
  DateTime today,
) async {
  final tplStd = ctx.id('shift_std');
  final tplTeacher = ctx.id('shift_teacher');
  await ctx.set(ctx.col('shift_templates').doc(tplStd), {
    'name': 'Standart Mesai (08:00-17:00)',
    'startTime': '08:00',
    'endTime': '17:00',
    'breakDuration': 60,
    'workDuration': 480,
    'workDays': <int>[1, 2, 3, 4, 5],
    'toleranceMinutes': 10,
    'isActive': true,
    'institutionId': ctx.inst,
    'createdAt': Timestamp.fromDate(ctx.termStart),
  });
  await ctx.set(ctx.col('shift_templates').doc(tplTeacher), {
    'name': 'Öğretmen Mesaisi (08:30-16:30)',
    'startTime': '08:30',
    'endTime': '16:30',
    'breakDuration': 45,
    'workDuration': 435,
    'workDays': <int>[1, 2, 3, 4, 5],
    'toleranceMinutes': 10,
    'isActive': true,
    'institutionId': ctx.inst,
    'createdAt': Timestamp.fromDate(ctx.termStart),
  });
  ctx.count('Vardiya şablonu', 2);

  for (final t in teachers) {
    // Doküman kimliği = personel kimliği (uygulama böyle okur)
    await ctx.set(ctx.col('staff_shift_assignments').doc(t.id), {
      'templateId': tplTeacher,
      'institutionId': ctx.inst,
      'lastUpdate': Timestamp.fromDate(ctx.termStart),
    });
  }

  // Son 10 iş günü devam kayıtları
  final days = <DateTime>[];
  var cursor = today;
  while (days.length < 10) {
    if (cursor.weekday <= 5) days.add(cursor);
    cursor = cursor.subtract(const Duration(days: 1));
  }
  final staff = teachers.take(25).toList();
  for (final t in staff) {
    final tLeaves = leaves
        .where((l) => l.teacher.id == t.id && l.status == 'approved')
        .toList();
    for (final d in days) {
      final onLeave = tLeaves.any(
        (l) => !d.isBefore(l.start) && !d.isAfter(l.end),
      );
      String status;
      String? inT;
      String? outT;
      if (onLeave) {
        status = 'izinli';
      } else {
        final r = ctx.rng.nextInt(100);
        if (r < 82) {
          status = 'geldi';
          inT = '08:${ctx.between(10, 29)}';
          outT = '16:${ctx.between(30, 59)}';
        } else if (r < 92) {
          status = 'geckaldi';
          inT = '08:${ctx.between(41, 59)}';
          outT = '16:${ctx.between(30, 59)}';
        } else if (r < 96) {
          status = 'erkencikti';
          inT = '08:${ctx.between(10, 29)}';
          outT = '14:${ctx.between(10, 50)}';
        } else {
          status = 'gelmedi';
        }
      }
      final isToday = d == today;
      if (isToday && outT != null) outT = null;
      await ctx.set(ctx.col('staff_attendance').doc('${t.id}_${_ymd(d)}'), {
        'userId': t.id,
        'institutionId': ctx.inst,
        'date': _ymd(d),
        'status': status,
        'checkInTime': inT,
        'checkOutTime': outT,
        'lastUpdate': Timestamp.fromDate(d.add(const Duration(hours: 17))),
      });
      ctx.count('Personel devam kaydı');
    }
  }

  // Fazla mesai talepleri
  const otStatuses = [
    'onaylandi',
    'onaylandi',
    'bekliyor',
    'reddedildi',
    'bekliyor',
    'onaylandi',
  ];
  const otDesc = [
    'Veli toplantısı sonrası ek mesai',
    'Sınav gözetmenliği',
    'Hafta sonu etüt programı',
    'Okul tanıtım günü',
    'Karne dağıtımı hazırlığı',
    'Deneme sınavı organizasyonu',
  ];
  for (var i = 0; i < otStatuses.length; i++) {
    final t = teachers[(i * 3) % teachers.length];
    final date = today.subtract(Duration(days: 3 + i * 4));
    await ctx.set(ctx.col('staff_overtime').doc(ctx.id('ot_$i')), {
      'userId': t.id,
      'institutionId': ctx.inst,
      'date': _ymd(date),
      'durationMinutes': 60 + 30 * (i % 4),
      'description': otDesc[i],
      'status': otStatuses[i],
      'createdAt': Timestamp.fromDate(date.add(const Duration(hours: 18))),
      if (otStatuses[i] != 'bekliyor')
        'approvedAt': Timestamp.fromDate(date.add(const Duration(days: 1))),
    });
    ctx.count('Fazla mesai');
  }
}
