import 'package:cloud_firestore/cloud_firestore.dart';

import 'demo_seed_context.dart';

/// Öğrenci Portfolyosu sekmeleri için HER ÖĞRENCİYE demo veri üretir:
///  * Etkinlik Raporları (`activity_reports`)
///  * Rehberlik Testleri (`applied_tests`)
///  * Etütler (`etut_requests`, `subject` alanıyla)
///  * Kitaplar (`book_assignments`: öğrenciye doğrudan atama; kitaplar `books`
///    koleksiyonundaki demo kitaplardan seçilir)
///  * Eylem Planları (`assessment_action_plans`: seviye bazında planlar; öğrenci
///    başına görevler / başarı yüzdesi / veli bilgilendirme)
const List<String> demoPortfolioTopCollections = [
  'activity_reports',
  'applied_tests',
  'book_assignments',
  'etut_requests',
  'assessment_action_plans',
];
const List<String> demoPortfolioSchoolSubcollections = [];

Future<int> cleanDemoPortfolioExtras(
  FirebaseFirestore db,
  String inst,
  String prefix,
  String schoolDocId,
) async => 0;

Future<void> seedDemoPortfolio(DemoSeedContext ctx) async {
  final students = ctx.allStudents;
  if (students.isEmpty) return;
  final classById = {for (final c in ctx.classes) c.id: c};

  await _seedActivityReports(ctx, students);
  await _seedAppliedTests(ctx, students);
  await _seedEtuts(ctx, students, classById);
  await _seedBookAssignments(ctx, students);
  await _seedActionPlans(ctx, students, classById);
}

// ───────────────────────── Etkinlik raporları ─────────────────────────
Future<void> _seedActivityReports(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
) async {
  const activities = [
    [
      'Kodlama Atölyesi',
      'Etkinliğe aktif katıldı, görev paylaşımında liderlik gösterdi.',
    ],
    [
      'Bilim Şenliği',
      'Deney stantında arkadaşlarına yardımcı oldu, meraklı ve istekliydi.',
    ],
    ['Kitap Okuma Saati', 'Okuduğu kitabı sınıfa özetledi, anlatımı akıcıydı.'],
    ['Satranç Turnuvası', 'Turnuvada dikkatli ve sabırlı bir oyun sergiledi.'],
    [
      'Resim ve Sanat Atölyesi',
      'Yaratıcı fikirler üretti, çalışmasını özenle tamamladı.',
    ],
    [
      'Drama ve Tiyatro Çalışması',
      'Rolünü başarıyla canlandırdı, grup uyumu çok iyiydi.',
    ],
    ['Spor Şenliği', 'Takım ruhuyla hareket etti, fair play kurallarına uydu.'],
    [
      'Çevre ve Doğa Gezisi',
      'Gözlemlerini not aldı, sorumluluk bilinci yüksekti.',
    ],
    [
      'Matematik Oyunları Günü',
      'Problem çözme becerisini oyun içinde etkin kullandı.',
    ],
    [
      'Müzik Dinletisi',
      'Koro çalışmasına düzenli katıldı, ritim duygusu gelişmiş.',
    ],
  ];
  int index = 0;
  for (final s in students) {
    index++;
    final reportCount = 2 + ctx.rng.nextInt(2); // 2-3 rapor
    for (int k = 0; k < reportCount; k++) {
      final act = activities[(index + k * 3) % activities.length];
      var date = ctx.today.subtract(Duration(days: 4 + ctx.rng.nextInt(55)));
      if (date.isBefore(ctx.termStart)) {
        date = ctx.termStart.add(Duration(days: 7 + k));
      }
      await ctx.set(ctx.col('activity_reports').doc(ctx.id('ar_${s.id}_$k')), {
        'institutionId': ctx.inst,
        'studentId': s.id,
        'studentName': s.fullName,
        'classId': s.classId,
        'className': s.className,
        'activityName': act[0],
        'notes': act[1],
        'date': Timestamp.fromDate(date),
        'createdAt': Timestamp.fromDate(date),
        'termId': ctx.termId,
      });
      ctx.count('Etkinlik Raporu');
    }
  }
}

// ───────────────────────── Rehberlik testleri ─────────────────────────
Future<void> _seedAppliedTests(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
) async {
  const tests = [
    'Sınav Kaygısı Ölçeği',
    'Stresle Başa Çıkma Envanteri',
    'Okula Uyum Ölçeği',
    'Akademik Motivasyon Envanteri',
    'Sosyal Beceri Envanteri',
    'Öğrenme Stilleri Envanteri',
  ];
  const levels = [
    'Düşük düzey',
    'Orta düzey',
    'Yüksek düzey',
    'Çok yüksek düzey',
  ];
  int index = 0;
  for (final s in students) {
    index++;
    for (int k = 0; k < 2; k++) {
      final name = tests[(index + k * 2) % tests.length];
      final score = 35 + ctx.rng.nextInt(60);
      final level = levels[(score ~/ 25).clamp(0, 3)];
      var date = ctx.today.subtract(Duration(days: 6 + ctx.rng.nextInt(45)));
      if (date.isBefore(ctx.termStart)) {
        date = ctx.termStart.add(Duration(days: 10 + k));
      }
      await ctx.set(ctx.col('applied_tests').doc(ctx.id('at2_${s.id}_$k')), {
        'institutionId': ctx.inst,
        'studentId': s.id,
        'studentName': s.fullName,
        'classId': s.classId,
        'className': s.className,
        'testName': name,
        'resultSummary':
            '$level (%$score) — rehber öğretmen değerlendirmesi tamamlandı',
        'score': score,
        'completedAt': Timestamp.fromDate(date),
      });
      ctx.count('Rehberlik Testi');
    }
  }
}

// ───────────────────────────── Etütler ─────────────────────────────
Future<void> _seedEtuts(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
  Map<String, DemoClassInfo> classById,
) async {
  int index = 0;
  for (final s in students) {
    index++;
    final c = classById[s.classId];
    if (c == null || c.lessons.isEmpty) continue;
    for (int k = 0; k < 3; k++) {
      final l = c.lessons[(index + k) % c.lessons.length];
      // k=0 geçmiş, k=1 geçmiş, k=2 yaklaşan
      final offset = k == 0
          ? -(10 + ctx.rng.nextInt(14))
          : (k == 1 ? -(2 + ctx.rng.nextInt(6)) : (2 + ctx.rng.nextInt(9)));
      var date = ctx.today.add(Duration(days: offset));
      if (date.weekday == DateTime.saturday)
        date = date.add(const Duration(days: 2));
      if (date.weekday == DateTime.sunday)
        date = date.add(const Duration(days: 1));
      if (date.isBefore(ctx.termStart))
        date = ctx.termStart.add(Duration(days: 8 + k));
      final start = DateTime(date.year, date.month, date.day, 15, 20 + k * 20);
      final end = start.add(const Duration(minutes: 40));
      final id = ctx.id('etp_${s.id}_$k');
      await ctx.set(ctx.col('etut_requests').doc(id), {
        'id': id,
        'institutionId': ctx.inst,
        'studentId': s.id,
        'studentIds': [s.id],
        'recipientNames': {s.id: '${s.fullName} (${c.name})'},
        'teacherId': l.teacherId,
        'teacherName': l.teacherName,
        'dersId': l.id,
        'dersAdi': l.name,
        'lessonName': l.name,
        'subject': l.name,
        'date': Timestamp.fromDate(date),
        'startTime': Timestamp.fromDate(start),
        'endTime': Timestamp.fromDate(end),
        'className': c.name,
        'classId': c.id,
        'status': 'active',
        'type': 'Etut',
        'isRecurring': false,
        'isGroup': false,
        'groupStudentCount': 1,
        'termId': ctx.termId,
        'schoolTypeId': c.typeId,
        'createdAt': Timestamp.fromDate(date.subtract(const Duration(days: 3))),
      });
      ctx.count('Etüt (öğrenci)');
    }
  }
}

// ───────────────────────── Kitap atamaları ─────────────────────────
Future<void> _seedBookAssignments(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
) async {
  final snap = await ctx
      .col('books')
      .where('institutionId', isEqualTo: ctx.inst)
      .where('isDemo', isEqualTo: true)
      .get();
  if (snap.docs.isEmpty) return;
  final questionBanks = <String>[];
  final readings = <String>[];
  for (final d in snap.docs) {
    final t = (d.data()['type'] ?? '').toString().toLowerCase();
    if (t.contains('question')) {
      questionBanks.add(d.id);
    } else {
      readings.add(d.id);
    }
  }
  int index = 0;
  for (final s in students) {
    index++;
    final picks = <String>[];
    if (questionBanks.isNotEmpty) {
      picks.add(questionBanks[index % questionBanks.length]);
      if (questionBanks.length > 1) {
        picks.add(questionBanks[(index + 2) % questionBanks.length]);
      }
    }
    if (readings.isNotEmpty) {
      picks.add(readings[index % readings.length]);
      if (readings.length > 1) {
        picks.add(readings[(index + 3) % readings.length]);
      }
    }
    for (int k = 0; k < picks.length; k++) {
      final assigned = ctx.today.subtract(
        Duration(days: 5 + (index + k * 7) % 40),
      );
      await ctx.set(ctx.col('book_assignments').doc(ctx.id('ba2_${s.id}_$k')), {
        'institutionId': ctx.inst,
        'bookId': picks[k],
        'targetType': 'student',
        'targetId': s.id,
        'targetName': s.fullName,
        'assignedAt': Timestamp.fromDate(
          assigned.isBefore(ctx.termStart) ? ctx.termStart : assigned,
        ),
      });
      ctx.count('Kitap Ataması (öğrenci)');
    }
  }
}

// ───────────────────────── Eylem planları ─────────────────────────
Future<void> _seedActionPlans(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
  Map<String, DemoClassInfo> classById,
) async {
  // Seviye bazında grupla: "<typeId>|<level>" -> öğrenciler
  final groups = <String, List<DemoStudentInfo>>{};
  for (final s in students) {
    final c = classById[s.classId];
    if (c == null || c.typeKind == 'Anaokulu') continue;
    groups.putIfAbsent('${c.typeId}|${s.level}', () => []).add(s);
  }

  const outcomePool = {
    'Matematik': [
      'Çarpanlar ve Katlar',
      'Üslü İfadeler',
      'Veri Analizi',
      'Olasılık',
    ],
    'Türkçe': [
      'Paragrafta Anlam',
      'Cümlede Anlam',
      'Yazım Kuralları',
      'Fiilimsiler',
    ],
    'Fen Bilimleri': [
      'Basınç',
      'Madde ve Endüstri',
      'Enerji Dönüşümleri',
      'DNA ve Genetik Kod',
    ],
  };
  const taskTemplates = [
    ['soru', 'Eksik kazanımlardan 40 soru çöz'],
    ['konu', 'Konu özetini tekrar et ve not çıkar'],
    ['etut', 'Branş öğretmeniyle etüt randevusu al'],
    ['test', 'Haftalık kazanım testini tamamla'],
  ];

  int planIdx = 0;
  for (final entry in groups.entries) {
    planIdx++;
    final parts = entry.key.split('|');
    final typeId = parts[0];
    final level = int.tryParse(parts[1]) ?? 0;
    final list = entry.value;
    final sampleClass = classById[list.first.classId]!;
    final coreSubjects = sampleClass.lessons
        .take(4)
        .map((l) => l.name.replaceAll('_', ' '))
        .toList();

    final studentTasks = <String, dynamic>{};
    final studentInfo = <String, dynamic>{};
    final parentNotified = <String, dynamic>{};
    final studentStatus = <String, dynamic>{};
    final outcomeStats = <String, dynamic>{};
    final branchPlans = <String, dynamic>{};

    // Şube bazlı kazanım istatistikleri ve şube eylem planları
    final classNames = list.map((s) => s.className).toSet();
    for (final cn in classNames) {
      final subjMap = <String, dynamic>{};
      for (final subj in coreSubjects) {
        final outs =
            outcomePool[subj] ?? ['Kazanım 1', 'Kazanım 2', 'Kazanım 3'];
        final outMap = <String, dynamic>{};
        for (int oi = 0; oi < outs.length; oi++) {
          final total = 40 + ctx.rng.nextInt(60);
          final correct = (total * (0.38 + ctx.rng.nextDouble() * 0.5)).round();
          outMap[outs[oi]] = {'total': total, 'correct': correct};
          if (correct / total < 0.55) {
            branchPlans['${cn}_${subj}_${outs[oi]}'] = {
              'problemSource':
                  'Şubede bu kazanımda başarı %55 altında kaldı; konu temelinde eksiklik var.',
              'actionPlan':
                  'Ders saatinde konu tekrarı yapılacak, hafta sonu telafi etüdü planlanacak.',
              'status': ctx.rng.nextBool() ? 'Uygulanıyor' : 'Planlandı',
            };
          }
        }
        subjMap[subj] = outMap;
      }
      outcomeStats[cn] = subjMap;
    }

    int sIdx = 0;
    for (final s in list) {
      sIdx++;
      // Öğrencinin zayıf olduğu 2-3 ders
      final take = 2 + (sIdx % 2);
      for (int k = 0; k < take && k < coreSubjects.length; k++) {
        final subj = coreSubjects[(sIdx + k) % coreSubjects.length];
        final key = '${s.className}_${subj}_${s.id}';
        final success = (28 + ctx.rng.nextInt(40)).toDouble();
        studentInfo[key] = {
          'name': s.fullName,
          'no': s.no,
          'branch': s.className,
          'subject': subj,
          'success': success,
        };
        final tasks = <Map<String, dynamic>>[];
        for (int t = 0; t < 3; t++) {
          final tpl = taskTemplates[(sIdx + k + t) % taskTemplates.length];
          tasks.add({
            'type': tpl[0],
            'label': tpl[1],
            'done': ctx.rng.nextDouble() < 0.45,
          });
        }
        studentTasks[key] = tasks;
        parentNotified[key] = ctx.rng.nextDouble() < 0.6;
        studentStatus[key] = ctx.rng.nextDouble() < 0.4
            ? 'Tamamlandı'
            : 'Devam Ediyor';
      }
    }

    final date = ctx.today.subtract(Duration(days: 9 + planIdx % 7));
    final id = ctx.id('ap_${typeId}_$level');
    await ctx.set(ctx.col('assessment_action_plans').doc(id), {
      'id': id,
      'institutionId': ctx.inst,
      'schoolTypeId': typeId,
      'title': '$level. Sınıf Deneme Sınavı Eylem Planı',
      'date': Timestamp.fromDate(date),
      'createdBy': ctx.teachers.isNotEmpty ? ctx.teachers.first.id : 'demo',
      'creatorName': ctx.teachers.isNotEmpty
          ? ctx.teachers.first.fullName
          : 'Demo Rehber',
      'selectedExamIds': <String>[],
      'selectedExamNames': ['$level. Sınıf Deneme - 3'],
      'classLevel': '$level. Sınıf',
      'subjectThresholds': {for (final s in coreSubjects) s: 60.0},
      'outcomeStats': outcomeStats,
      'branchActionPlans': branchPlans,
      'studentTasks': studentTasks,
      'parentNotified': parentNotified,
      'studentStatus': studentStatus,
      'studentInfo': studentInfo,
      'isActive': true,
      'isRealized': false,
      'realizationNotes': '',
      'realizedDate': null,
    });
    ctx.count('Eylem Planı');
  }
}
