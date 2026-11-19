import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/guidance/tests/academic_motivation_test.dart';
import '../../models/guidance/tests/guidance_test_definition.dart';
import '../../models/guidance/tests/school_adaptation_test.dart';
import '../../models/guidance/tests/social_skill_test.dart';
import '../../models/guidance/tests/stress_coping_test.dart';
import '../../models/guidance/tests/test_anxiety_test.dart';
import 'demo_seed_context.dart';

/// REHBERLİK modülleri için demo veri üreticisi.
///
/// Yazılan koleksiyonlar:
///  * surveys / survey_responses  (anketler + rehberlik envanterleri;
///    envanterler `guidanceTemplateId` taşıyan anketlerdir, çözümleri
///    survey_responses içinde tutulur)
///  * applied_tests               (öğrenci portfolyosu "Rehberlik Testleri" sekmesi)
///  * guidance_interviews         (görüşme notları)
///  * institutions/{inst}/study_programs (mentör çalışma programları)
///  * development_criteria / development_report_sessions /
///    development_reports / development_evaluations (gelişim raporları)
///  * guidance_demands            (talepler / yönlendirmeler)
///  * activities / activity_evaluations (etkinlik & gözlemler)
///
/// Not: assessment_action_plans (sınav analizine bağlı eylem planları) ve
/// öğrenci `mentorId` alanı bu dosyada üretilmez.
const List<String> demoGuidanceTopCollections = [
  'surveys',
  'survey_responses',
  'applied_tests',
  'guidance_interviews',
  'development_criteria',
  'development_report_sessions',
  'development_reports',
  'development_evaluations',
  'guidance_demands',
  'activities',
  'activity_evaluations',
];

const List<String> demoGuidanceSchoolSubcollections = <String>[];

/// institutions/{inst}/study_programs altındaki demo dokümanlarını siler.
Future<int> cleanDemoGuidanceExtras(
  FirebaseFirestore db,
  String inst,
  String prefix,
  String schoolDocId,
) async {
  int deleted = 0;
  final col = db
      .collection('institutions')
      .doc(inst)
      .collection('study_programs');
  final snap = await col.where('isDemo', isEqualTo: true).get();
  WriteBatch batch = db.batch();
  int pending = 0;
  for (final d in snap.docs) {
    batch.delete(d.reference);
    pending++;
    deleted++;
    if (pending >= 400) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending > 0) await batch.commit();
  return deleted;
}

// ---------------------------------------------------------------------------
// Yardımcılar
// ---------------------------------------------------------------------------

DateTime _pastDate(DemoSeedContext ctx, int maxDaysAgo) {
  var d = ctx.today.subtract(Duration(days: ctx.between(1, maxDaysAgo)));
  if (d.isBefore(ctx.termStart)) {
    d = ctx.termStart.add(Duration(days: ctx.between(0, 5)));
  }
  if (d.isAfter(ctx.today)) d = ctx.today;
  return DateTime(
    d.year,
    d.month,
    d.day,
    ctx.between(9, 16),
    ctx.pick<int>([0, 15, 30, 45]),
  );
}

String _surname(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  return parts.isEmpty ? '' : parts.last;
}

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

Map<String, dynamic> _q(
  String id,
  String text,
  String type, {
  List<String> options = const [],
  bool required = true,
}) => {
  'id': id,
  'text': text,
  'type': type,
  'isRequired': required,
  'options': options,
  'mediaUrl': null,
};

// ---------------------------------------------------------------------------
// Ana fonksiyon
// ---------------------------------------------------------------------------

Future<void> seedDemoGuidance(DemoSeedContext ctx) async {
  final students = List<DemoStudentInfo>.of(ctx.allStudents);
  if (students.isEmpty || ctx.teachers.isEmpty) return;
  students.shuffle(ctx.rng);

  final classById = <String, DemoClassInfo>{
    for (final c in ctx.classes) c.id: c,
  };
  final defaultType = ctx.types.isNotEmpty ? ctx.types.first.id : '';
  String typeOf(DemoStudentInfo s) =>
      classById[s.classId]?.typeId ?? defaultType;

  final guides = ctx.teachers
      .where((t) => t.branch.toLowerCase().contains('rehber'))
      .toList();
  final counselors = guides.isNotEmpty ? guides : ctx.teachers;
  final mainCounselor = counselors.first;

  final startYear = ctx.termStart.month >= 8
      ? ctx.termStart.year
      : ctx.termStart.year - 1;
  final schoolYear = '$startYear-${startYear + 1}';

  await _seedSurveys(ctx, students, defaultType, mainCounselor);
  await _seedGuidanceTests(ctx, students, classById, typeOf, mainCounselor);
  await _seedInterviews(ctx, students, typeOf, counselors);
  await _seedStudyPrograms(ctx, students, classById, typeOf, counselors);
  await _seedDevelopmentReports(
    ctx,
    students,
    classById,
    schoolYear,
    counselors,
  );
  await _seedDemands(ctx, students, typeOf, counselors);
  await _seedActivities(ctx, students, classById, typeOf);
}

// ---------------------------------------------------------------------------
// 1) ANKETLER
// ---------------------------------------------------------------------------

Future<void> _seedSurveys(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
  String typeId,
  DemoTeacherInfo author,
) async {
  final ratingTexts = <String>[
    'Okulumuzdan genel memnuniyet düzeyiniz nedir?',
    'Okuldaki sosyal etkinlikleri nasıl değerlendirirsiniz?',
  ];
  final teachingOpts = ['Çok yeterli', 'Yeterli', 'Kısmen yeterli', 'Yetersiz'];
  final activityOpts = [
    'Spor turnuvaları',
    'Bilim şenliği',
    'Kitap okuma kulübü',
    'Gezi ve teknik geziler',
    'Müzik ve sahne gösterileri',
    'Satranç ve zeka oyunları',
  ];
  final comments = [
    'Kantin çeşitleri artırılabilir.',
    'Kütüphane saatleri uzatılırsa çok iyi olur.',
    'Öğretmenlerimizden memnunum, etütler çok faydalı.',
    'Laboratuvar derslerinin sayısı artırılsın.',
    'Teneffüs süreleri biraz daha uzun olabilir.',
    'Sosyal kulüpler çok güzel, devam etsin.',
    'Sınav takvimi daha dengeli dağıtılabilir.',
  ];

  final needTopics = [
    'Verimli ders çalışma teknikleri',
    'Sınav kaygısı ile başa çıkma',
    'Zaman yönetimi',
    'Meslek ve bölüm seçimi',
    'Arkadaşlık ilişkileri',
    'Motivasyon',
    'Teknoloji kullanımı',
  ];
  final contactOpts = [
    'Evet, birçok kez',
    'Evet, bir kez',
    'Hayır ama istiyorum',
    'Hayır',
  ];

  final surveys = <Map<String, dynamic>>[
    {
      'key': 'sv_memnuniyet',
      'title': 'Öğrenci Memnuniyet Anketi',
      'description':
          'Okul yaşamına ilişkin görüşlerinizi almak amacıyla hazırlanmıştır. Katılımınız için teşekkürler.',
      'targetType': 'students',
      'targetNames': ['Tüm Öğrenciler'],
      'status': 'published',
      'daysAgo': 40,
      'sections': [
        {
          'id': 'sec_1',
          'title': 'Genel Değerlendirme',
          'description': null,
          'questions': [
            _q('q1', ratingTexts[0], 'rating'),
            _q(
              'q2',
              'Derslerin işleniş biçimini nasıl buluyorsunuz?',
              'singleChoice',
              options: teachingOpts,
            ),
            _q(
              'q3',
              'Hangi etkinlikler düzenlensin isterdiniz?',
              'multipleChoice',
              options: activityOpts,
            ),
            _q('q4', ratingTexts[1], 'rating'),
            _q(
              'q5',
              'Eklemek istediğiniz görüş ve önerileriniz',
              'longText',
              required: false,
            ),
          ],
        },
      ],
    },
    {
      'key': 'sv_rehberlik',
      'title': 'Rehberlik Servisi İhtiyaç Analizi',
      'description':
          'Rehberlik servisinin çalışmalarını sizin ihtiyaçlarınıza göre planlamak için hazırlanmıştır.',
      'targetType': 'students',
      'targetNames': ['Tüm Öğrenciler'],
      'status': 'closed',
      'daysAgo': 60,
      'sections': [
        {
          'id': 'sec_1',
          'title': 'İhtiyaçlar',
          'description': null,
          'questions': [
            _q(
              'q1',
              'Hangi konularda destek almak istersiniz?',
              'multipleChoice',
              options: needTopics,
            ),
            _q(
              'q2',
              'Rehberlik servisi ile bu dönem görüştünüz mü?',
              'singleChoice',
              options: contactOpts,
            ),
            _q('q3', 'Rehberlik servisinden memnuniyetiniz', 'rating'),
          ],
        },
      ],
    },
    {
      'key': 'sv_ogretmen',
      'title': 'Öğretmen Görüş Anketi',
      'description':
          'Okul işleyişi ve rehberlik hizmetlerine ilişkin öğretmen görüşleri.',
      'targetType': 'teachers',
      'targetNames': ['Tüm Öğretmenler'],
      'status': 'published',
      'daysAgo': 25,
      'sections': [
        {
          'id': 'sec_1',
          'title': 'Öğretmen Görüşleri',
          'description': null,
          'questions': [
            _q('q1', 'Okul içi iletişimden memnuniyetiniz', 'rating'),
            _q(
              'q2',
              'Rehberlik servisi ile iş birliği düzeyi',
              'singleChoice',
              options: teachingOpts,
            ),
            _q('q3', 'Öneri ve talepleriniz', 'longText', required: false),
          ],
        },
      ],
    },
    {
      'key': 'sv_veli',
      'title': 'Veli Memnuniyet Anketi',
      'description':
          'Velilerimizin okulumuz hakkındaki görüşlerini almak için planlanmıştır.',
      'targetType': 'parents',
      'targetNames': ['Tüm Veliler'],
      'status': 'scheduled',
      'daysAgo': 0,
      'sections': [
        {
          'id': 'sec_1',
          'title': 'Veli Görüşleri',
          'description': null,
          'questions': [
            _q('q1', 'Okulumuzdan genel memnuniyetiniz', 'rating'),
            _q(
              'q2',
              'Okul-veli iletişimini nasıl buluyorsunuz?',
              'singleChoice',
              options: teachingOpts,
            ),
          ],
        },
      ],
    },
  ];

  for (final sv in surveys) {
    final key = sv['key'] as String;
    final status = sv['status'] as String;
    final targetType = sv['targetType'] as String;
    final created = _pastDate(
      ctx,
      sv['daysAgo'] as int > 0 ? sv['daysAgo'] as int : 1,
    );
    final surveyId = ctx.id(key);

    // Katılımcılar
    final respondents = <String>[];
    if (targetType == 'students') {
      final take = math.min(
        students.length,
        key == 'sv_memnuniyet' ? 150 : 100,
      );
      final n = (take * (0.6 + ctx.rng.nextDouble() * 0.3)).round();
      for (final s in students.take(n)) {
        respondents.add(s.id);
      }
    } else if (targetType == 'teachers') {
      for (final t in ctx.teachers) {
        if (ctx.rng.nextDouble() < 0.8) respondents.add(t.id);
      }
    }

    final totalTarget = targetType == 'students'
        ? students.length
        : (targetType == 'teachers' ? ctx.teachers.length : students.length);

    final doc = <String, dynamic>{
      'id': surveyId,
      'institutionId': ctx.inst,
      'schoolTypeId': typeId,
      'title': sv['title'],
      'description': sv['description'],
      'authorId': author.id,
      'createdAt': Timestamp.fromDate(created),
      'publishedAt': status == 'draft'
          ? null
          : Timestamp.fromDate(
              status == 'scheduled'
                  ? ctx.today.add(const Duration(days: 3))
                  : created.add(const Duration(hours: 2)),
            ),
      'scheduledAt': status == 'scheduled'
          ? Timestamp.fromDate(ctx.today.add(const Duration(days: 3)))
          : null,
      'closedAt': status == 'closed'
          ? Timestamp.fromDate(created.add(const Duration(days: 14)))
          : null,
      'status': status,
      'targetType': targetType,
      'targetIds': <String>[],
      'sections': sv['sections'],
      'responseCount': respondents.length,
      'isAnonymous': false,
      'guidanceTemplateId': null,
      'targetNames': sv['targetNames'],
      'totalTargetCount': totalTarget,
      'termId': ctx.termId,
    };
    await ctx.set(ctx.col('surveys').doc(surveyId), doc);
    ctx.count('Anket');

    for (final uid in respondents) {
      Map<String, dynamic> answers;
      if (key == 'sv_memnuniyet') {
        final picks = List<String>.of(activityOpts)..shuffle(ctx.rng);
        answers = {
          'q1': ctx.between(3, 5),
          'q2': ctx.pick<String>(teachingOpts.sublist(0, 3)),
          'q3': picks.take(ctx.between(1, 3)).toList(),
          'q4': ctx.between(2, 5),
          if (ctx.rng.nextDouble() < 0.4) 'q5': ctx.pick<String>(comments),
        };
      } else if (key == 'sv_rehberlik') {
        final picks = List<String>.of(needTopics)..shuffle(ctx.rng);
        answers = {
          'q1': picks.take(ctx.between(1, 3)).toList(),
          'q2': ctx.pick<String>(contactOpts),
          'q3': ctx.between(3, 5),
        };
      } else {
        answers = {
          'q1': ctx.between(3, 5),
          'q2': ctx.pick<String>(teachingOpts.sublist(0, 3)),
          if (ctx.rng.nextDouble() < 0.4)
            'q3': 'Ortak planlama saatleri artırılabilir.',
        };
      }
      final rid = ctx.id('sr_${key}_$uid');
      await ctx.set(ctx.col('survey_responses').doc(rid), {
        'institutionId': ctx.inst,
        'surveyId': surveyId,
        'userId': uid,
        'answers': answers,
        'submittedAt': Timestamp.fromDate(
          created.add(Duration(hours: ctx.between(3, 24 * 12))),
        ),
      });
    }
    ctx.count('Anket yanıtı', respondents.length);
  }
}

// ---------------------------------------------------------------------------
// 4) REHBERLİK ENVANTERLERİ (test çözümleri)
// ---------------------------------------------------------------------------

Future<void> _seedGuidanceTests(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
  Map<String, DemoClassInfo> classById,
  String Function(DemoStudentInfo) typeOf,
  DemoTeacherInfo author,
) async {
  final defs = <GuidanceTestDefinition>[
    TestAnxietyTest(),
    StressCopingTest(),
    SchoolAdaptationTest(),
    AcademicMotivationTest(),
    SocialSkillTest(),
  ];
  final sample = students.take(math.min(students.length, 100)).toList();
  if (sample.isEmpty) return;
  final schoolTypeId = ctx.types.isNotEmpty ? ctx.types.first.id : '';

  // Her öğrenci 2 envanter çözer.
  final assigned = <int, List<DemoStudentInfo>>{
    for (int i = 0; i < defs.length; i++) i: <DemoStudentInfo>[],
  };
  for (int i = 0; i < sample.length; i++) {
    final a = i % defs.length;
    final b = (a + 1 + ctx.rng.nextInt(defs.length - 1)) % defs.length;
    assigned[a]!.add(sample[i]);
    assigned[b]!.add(sample[i]);
  }

  for (int di = 0; di < defs.length; di++) {
    final def = defs[di];
    final list = assigned[di]!;
    if (list.isEmpty) continue;
    final created = _pastDate(ctx, 45);
    final surveyId = ctx.id('gt_${def.id}');
    final sections = def.sections.map((s) => s.toMap()).toList();

    await ctx.set(ctx.col('surveys').doc(surveyId), {
      'id': surveyId,
      'institutionId': ctx.inst,
      'schoolTypeId': schoolTypeId,
      'title': def.title,
      'description': def.description,
      'authorId': author.id,
      'createdAt': Timestamp.fromDate(created),
      'publishedAt': Timestamp.fromDate(created.add(const Duration(hours: 1))),
      'scheduledAt': null,
      'closedAt': null,
      'status': 'published',
      'targetType': 'students',
      'targetIds': <String>[],
      'sections': sections,
      'responseCount': list.length,
      'isAnonymous': def.isAnonymous,
      'guidanceTemplateId': def.id,
      'targetNames': ['Seçili Öğrenciler'],
      'totalTargetCount': list.length + ctx.between(2, 8),
      'termId': ctx.termId,
    });
    ctx.count('Rehberlik envanteri');

    for (final s in list) {
      // Öğrenciye özgü eğilim: -0.2 .. +0.2
      final bias = (ctx.rng.nextDouble() - 0.5) * 0.4;
      double fracSum = 0;
      int qCount = 0;
      final answers = <String, dynamic>{};
      for (final sec in def.sections) {
        for (final q in sec.questions) {
          final opts = q.options;
          if (opts.isEmpty) continue;
          final f = _clamp01(0.5 + (ctx.rng.nextDouble() - 0.5) * 0.9 + bias);
          final idx = ((opts.length - 1) * f).round();
          answers[q.id] = opts[idx];
          fracSum += opts.length > 1 ? idx / (opts.length - 1) : 0;
          qCount++;
        }
      }
      final completed = created.add(
        Duration(hours: ctx.between(4, 24 * 10), minutes: ctx.between(0, 59)),
      );
      final submitted = completed.isAfter(ctx.today) ? ctx.today : completed;
      await ctx.set(
        ctx.col('survey_responses').doc(ctx.id('gtr_${def.id}_${s.id}')),
        {
          'institutionId': ctx.inst,
          'surveyId': surveyId,
          'userId': s.id,
          'answers': answers,
          'submittedAt': Timestamp.fromDate(submitted),
        },
      );
      ctx.count('Envanter çözümü');

      final pct = qCount == 0 ? 0 : (fracSum / qCount * 100).round();
      final level = pct < 38 ? 'Düşük' : (pct < 62 ? 'Orta' : 'Yüksek');
      await ctx
          .set(ctx.col('applied_tests').doc(ctx.id('at_${def.id}_${s.id}')), {
            'institutionId': ctx.inst,
            'schoolTypeId': typeOf(s),
            'studentId': s.id,
            'studentName': s.fullName,
            'className': s.className,
            'surveyId': surveyId,
            'testId': def.id,
            'testName': def.title,
            'resultSummary': '$level düzey (%$pct)',
            'completedAt': Timestamp.fromDate(submitted),
          });
      ctx.count('Uygulanan test');
    }
  }
}

// ---------------------------------------------------------------------------
// 2) GÖRÜŞME NOTLARI
// ---------------------------------------------------------------------------

Future<void> _seedInterviews(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
  String Function(DemoStudentInfo) typeOf,
  List<DemoTeacherInfo> counselors,
) async {
  final titles = [
    'Akademik Görüşme',
    'Davranışsal Görüşme',
    'Motivasyon Görüşmesi',
    'Bilgilendirme Görüşmesi',
    'Diğer',
  ];
  final types = ['Yüz Yüze', 'Yüz Yüze', 'Yüz Yüze', 'Telefon', 'Online'];
  final notes = <String, List<String>>{
    'Akademik Görüşme': [
      'Öğrenci ile son deneme sınavı sonuçları değerlendirildi. Matematik ve fen derslerinde konu eksikleri belirlendi, haftalık çalışma planı oluşturuldu.',
      'Ders başarısındaki düşüşün nedenleri konuşuldu. Düzenli tekrar ve etüt katılımı önerildi. İki hafta sonra tekrar görüşülecek.',
      'Hedef okul ve puan beklentisi gözden geçirildi. Gerçekçi hedefler belirlenerek soru çözüm süresi artırıldı.',
    ],
    'Davranışsal Görüşme': [
      'Sınıf içi iletişimde yaşanan sorunlar ele alındı. Öğrenci kendini ifade etti, empati çalışması yapıldı.',
      'Teneffüslerde yaşanan küçük anlaşmazlıklar konuşuldu. Öğrenciye öfke kontrolü ve çatışma çözme stratejileri anlatıldı.',
      'Derse geç kalma davranışı görüşüldü. Sabah rutini ve uyku düzeni üzerine öneriler paylaşıldı.',
    ],
    'Motivasyon Görüşmesi': [
      'Öğrencinin ders çalışma isteğinde azalma gözlendi. İlgi alanları ve kısa vadeli hedefler üzerinden motivasyon çalışması yapıldı.',
      'Başarı hikayeleri paylaşıldı, öğrenciye küçük ödüllü hedefler belirlendi. Olumlu geri bildirim verildi.',
    ],
    'Bilgilendirme Görüşmesi': [
      'Sınav takvimi, LGS süreci ve kontenjanlar hakkında bilgi verildi. Öğrencinin soruları yanıtlandı.',
      'Kulüp ve sosyal etkinliklere katılım imkanları hakkında bilgilendirme yapıldı.',
      'Tercih dönemine ilişkin süreç ve dikkat edilecek hususlar anlatıldı.',
    ],
    'Diğer': [
      'Genel durum değerlendirmesi yapıldı. Öğrenci okula uyumundan memnun olduğunu belirtti.',
      'Aile içi değişiklikler nedeniyle yaşanan kaygı dinlendi, destek sağlanacağı ifade edildi.',
    ],
  };
  final parentNotes = [
    'Veli ile öğrencinin akademik durumu paylaşıldı. Evde çalışma ortamı ve düzen konusunda öneriler sunuldu.',
    'Veli, öğrencinin davranış değişikliklerinden endişe duyduğunu belirtti. Okulda gözlemlerimiz aktarıldı, ortak iş birliği kararlaştırıldı.',
    'Deneme sınavı sonuçları veliye açıklandı. Hedef belirleme ve motivasyon desteği için yol haritası çizildi.',
    'Velinin talebi üzerine devamsızlık konusu görüşüldü. Takip planı oluşturuldu.',
  ];
  final parentTitles = [
    'Akademik Görüşme',
    'Davranışsal Görüşme',
    'Bilgilendirme Görüşmesi',
  ];

  final studentCount = math.min(students.length, 90);
  for (int i = 0; i < studentCount; i++) {
    final s = students[ctx.rng.nextInt(students.length)];
    final t = ctx.pick<DemoTeacherInfo>(counselors);
    final title = ctx.pick<String>(titles);
    final date = _pastDate(ctx, 90);
    await ctx.set(ctx.col('guidance_interviews').doc(ctx.id('gi_s_$i')), {
      'institutionId': ctx.inst,
      'schoolTypeId': typeOf(s),
      'interviewerId': t.id,
      'interviewerEmail': null,
      'participants': [s.id],
      'participantNames': [s.fullName],
      'participantDetails': [
        {
          'id': s.id,
          'name': s.fullName,
          'sub': '${s.className} - ${s.no}',
          'type': 'ogrenci',
          'studentId': s.id,
          'phone': null,
          'actualParticipantName': null,
        },
      ],
      'date': Timestamp.fromDate(date),
      'category': 'ogrenci',
      'type': ctx.pick<String>(types),
      'title': title,
      'notes': ctx.pick<String>(notes[title]!),
      'isPrivate': ctx.rng.nextDouble() < 0.7,
      'createdAt': Timestamp.fromDate(date),
      'isBatchCreated': false,
      'fileUrl': null,
      'fileName': null,
      'interviewerName': t.fullName,
    });
    ctx.count('Görüşme notu');
  }

  final parentCount = math.min(students.length, 25);
  for (int i = 0; i < parentCount; i++) {
    final s = students[ctx.rng.nextInt(students.length)];
    final t = ctx.pick<DemoTeacherInfo>(counselors);
    final date = _pastDate(ctx, 90);
    final relation = ctx.pick<String>(['Anne', 'Baba']);
    final parentName =
        '${relation == 'Anne' ? 'Ayşe' : 'Mehmet'} ${_surname(s.fullName)}';
    final parentId = 'P_${s.id}_$parentName';
    await ctx.set(ctx.col('guidance_interviews').doc(ctx.id('gi_p_$i')), {
      'institutionId': ctx.inst,
      'schoolTypeId': typeOf(s),
      'interviewerId': t.id,
      'interviewerEmail': null,
      'participants': [parentId, s.id],
      'participantNames': [parentName],
      'participantDetails': [
        {
          'id': parentId,
          'name': s.fullName,
          'sub': '$parentName (Veli) - $relation',
          'type': 'veli',
          'studentId': s.id,
          'phone': null,
          'actualParticipantName': parentName,
        },
      ],
      'date': Timestamp.fromDate(date),
      'category': 'veli',
      'type': ctx.pick<String>(['Yüz Yüze', 'Telefon', 'Online']),
      'title': ctx.pick<String>(parentTitles),
      'notes': ctx.pick<String>(parentNotes),
      'isPrivate': ctx.rng.nextDouble() < 0.5,
      'createdAt': Timestamp.fromDate(date),
      'isBatchCreated': false,
      'fileUrl': null,
      'fileName': null,
      'interviewerName': t.fullName,
    });
    ctx.count('Görüşme notu');
  }
}

// ---------------------------------------------------------------------------
// 3 + 6) MENTÖR ÇALIŞMALARI / ÇALIŞMA PROGRAMLARI
// ---------------------------------------------------------------------------

Future<void> _seedStudyPrograms(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
  Map<String, DemoClassInfo> classById,
  String Function(DemoStudentInfo) typeOf,
  List<DemoTeacherInfo> counselors,
) async {
  const days = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  const modes = [
    '📚 Konu Çalışması',
    '📝 Soru Çözümü',
    '🔁 Tekrar',
    '🎯 Deneme Analizi',
  ];
  final targets = [
    'Bu hafta her gün en az 40 soru çözülecek.',
    'Eksik konuların tekrarı tamamlanacak.',
    'Deneme sınavındaki yanlışların analizi yapılacak.',
    'Haftalık okuma hedefi: 150 sayfa.',
  ];
  final evaluations = [
    'Öğrenci programa büyük ölçüde uydu, düzenli çalışması takdire değer.',
    'Hafta içi çalışmalar iyiydi; hafta sonu programı aksatıldı. Planlama konusunda destek verilecek.',
    'Matematik tekrarları eksik kaldı. Gelecek hafta bu derse öncelik verilecek.',
    'Motivasyonu yüksek, hedeflerine yaklaşıyor. Devam etmesi önerildi.',
  ];

  final col = ctx.db
      .collection('institutions')
      .doc(ctx.inst)
      .collection('study_programs');
  final count = math.min(students.length, 40);
  final thisMonday = DateTime(
    ctx.today.year,
    ctx.today.month,
    ctx.today.day,
  ).subtract(Duration(days: ctx.today.weekday - 1));

  for (int i = 0; i < count; i++) {
    final s = students[i];
    final cls = classById[s.classId];
    final lessons = (cls?.lessons ?? const <DemoLessonInfo>[])
        .map((l) => l.name)
        .toList();
    final lessonPool = lessons.isNotEmpty
        ? lessons
        : [
            'Matematik',
            'Türkçe',
            'Fen Bilimleri',
            'Sosyal Bilgiler',
            'İngilizce',
          ];
    final mentor = ctx.pick<DemoTeacherInfo>(counselors);

    for (int w = 0; w < 2; w++) {
      // w=0: geçen hafta (değerlendirilmiş), w=1: bu hafta
      var start = thisMonday.subtract(Duration(days: 7 * (1 - w)));
      if (start.isBefore(ctx.termStart)) start = ctx.termStart;
      final end = start.add(const Duration(days: 6));
      final schedule = <String, dynamic>{};
      final execution = <String, dynamic>{};
      final priority = <String, dynamic>{};
      for (final day in days) {
        final dayIndex = days.indexOf(day);
        final n = dayIndex >= 5 ? ctx.between(2, 3) : ctx.between(2, 4);
        final items = <String>[];
        final status = <int>[];
        for (int k = 0; k < n; k++) {
          items.add(
            '${ctx.pick<String>(lessonPool)}\n${ctx.pick<String>(modes)}',
          );
          final dayDate = start.add(Duration(days: dayIndex));
          if (dayDate.isAfter(ctx.today)) {
            status.add(0);
          } else {
            final r = ctx.rng.nextDouble();
            status.add(r < 0.65 + s.ability * 0.1 ? 1 : (r < 0.85 ? 2 : 0));
          }
          if (k == 0 && ctx.rng.nextDouble() < 0.3)
            priority['${day}_$k'] = true;
        }
        schedule[day] = items;
        execution[day] = status;
      }
      final created = start.add(const Duration(hours: 9));
      final data = <String, dynamic>{
        'institutionId': ctx.inst,
        'schoolTypeId': typeOf(s),
        'studentId': s.id,
        'studentName': s.fullName,
        'studentBranch': s.className,
        'className': s.className,
        'classLevel': s.level,
        'title': '${s.fullName} - Mentör Çalışması',
        'examName': w == 0 ? 'Manuel Oluşturuldu' : 'Son Deneme Analizi',
        'schedule': schedule,
        'executionStatus': execution,
        'priorityTasks': priority,
        'topicAnalysis': <dynamic>[],
        'startDate': Timestamp.fromDate(start),
        'endDate': Timestamp.fromDate(end),
        'createdAt': Timestamp.fromDate(
          created.isAfter(ctx.today) ? ctx.today : created,
        ),
        'creatorId': mentor.id,
        'creatorName': mentor.fullName,
        'weeklyTarget': ctx.pick<String>(targets),
      };
      if (w == 0) {
        data['mentorEvaluation'] = ctx.pick<String>(evaluations);
        data['mentorEvaluationBy'] = mentor.fullName;
        data['mentorEvaluationDate'] = Timestamp.fromDate(
          end.isAfter(ctx.today) ? ctx.today : end,
        );
      }
      await ctx.set(col.doc(ctx.id('sp_${i}_$w')), data);
      ctx.count('Çalışma programı');
    }
  }
}

// ---------------------------------------------------------------------------
// 5) GELİŞİM RAPORLARI
// ---------------------------------------------------------------------------

Future<void> _seedDevelopmentReports(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
  Map<String, DemoClassInfo> classById,
  String schoolYear,
  List<DemoTeacherInfo> counselors,
) async {
  final levelSet = <String>{for (final c in ctx.classes) '${c.level}'};
  final levels = levelSet.isEmpty ? ['5', '6', '7', '8'] : levelSet.toList();

  final critDefs = <Map<String, dynamic>>[
    {
      'category': 'Akademik Gelişim',
      'subCategory': 'Genel',
      'title': 'Ders İlgisi',
      'description': 'Derslere karşı ilgi ve katılım düzeyi.',
    },
    {
      'category': 'Akademik Gelişim',
      'subCategory': 'Genel',
      'title': 'Ödev Bilinci',
      'description': 'Ödevlerini zamanında ve eksiksiz yapma.',
    },
    {
      'category': 'Sosyal Gelişim',
      'subCategory': 'İletişim',
      'title': 'Arkadaşlık İlişkileri',
      'description': 'Arkadaşlarıyla uyumlu ilişkiler kurma.',
    },
    {
      'category': 'Sosyal Gelişim',
      'subCategory': 'İletişim',
      'title': 'Kurallara Uyma',
      'description': 'Okul ve sınıf kurallarına uyum.',
    },
    {
      'category': 'Davranış ve Sorumluluk',
      'subCategory': 'Genel',
      'title': 'Sorumluluk Bilinci',
      'description': 'Aldığı görevleri yerine getirme.',
    },
  ];
  final critIds = <String>[];
  final critCategory = <String, String>{};
  for (int i = 0; i < critDefs.length; i++) {
    final id = ctx.id('dcrit_${i + 1}');
    critIds.add(id);
    critCategory[id] = critDefs[i]['category'] as String;
    await ctx.set(ctx.col('development_criteria').doc(id), {
      'id': id,
      'institutionId': ctx.inst,
      'category': critDefs[i]['category'],
      'subCategory': critDefs[i]['subCategory'],
      'title': critDefs[i]['title'],
      'description': critDefs[i]['description'],
      'targetGradeLevels': levels,
      'type': 'scale_1_5',
      'order': i + 1,
    });
  }
  ctx.count('Gelişim kriteri', critIds.length);

  final sample = students.take(math.min(students.length, 80)).toList();
  if (sample.isEmpty) return;

  final sessionId = ctx.id('dsess_1');
  final sessionDate = _pastDate(ctx, 30);
  final reviewers = ctx.teachers.take(4).toList();
  await ctx.set(ctx.col('development_report_sessions').doc(sessionId), {
    'id': sessionId,
    'institutionId': ctx.inst,
    'title': '1. Dönem Öğrenci Gelişim Raporu',
    'targetGroup': 'student',
    'schoolYear': schoolYear,
    'assignedReviewerIds': reviewers.map((t) => t.id).toList(),
    'targetUserIds': sample.map((s) => s.id).toList(),
    'createdAt': Timestamp.fromDate(sessionDate),
    'createdBy': counselors.first.id,
    'isPublished': true,
    'termId': ctx.termId,
  });
  ctx.count('Gelişim rapor oturumu');

  final posComments = [
    'Derse aktif katılım gösteriyor.',
    'Arkadaşlarıyla uyumlu ve yardımsever.',
    'Sorumluluklarını zamanında yerine getiriyor.',
    'Ödevlerini düzenli yapıyor.',
  ];
  final negComments = [
    'Derste dikkati kolay dağılıyor, takip edilmeli.',
    'Ödev teslimlerinde aksamalar var.',
    'Kurallara uyum konusunda hatırlatma gerekiyor.',
  ];

  for (final s in sample) {
    final reportId = ctx.id('drep_${s.id}');
    final evalRoles = <MapEntry<DemoTeacherInfo, String>>[];
    final classTeachers = reviewers.isEmpty ? ctx.teachers : reviewers;
    evalRoles.add(
      MapEntry(ctx.pick<DemoTeacherInfo>(classTeachers), 'teacher'),
    );
    evalRoles.add(MapEntry(ctx.pick<DemoTeacherInfo>(counselors), 'guidance'));

    final base = _clamp01(s.ability) * 2.0 + 2.5; // ~2.5 .. 4.5
    final categorySums = <String, double>{};
    final categoryCounts = <String, int>{};
    final categoryComments = <String, List<String>>{};
    final reportDate = sessionDate.add(Duration(days: ctx.between(1, 7)));
    final reportTs = reportDate.isAfter(ctx.today) ? ctx.today : reportDate;

    for (int e = 0; e < evalRoles.length; e++) {
      final ev = evalRoles[e];
      final scores = <String, dynamic>{};
      final comments = <String, String>{};
      for (final cid in critIds) {
        final int v = (base + (ctx.rng.nextDouble() - 0.5) * 1.6)
            .round()
            .clamp(1, 5)
            .toInt();
        scores[cid] = v;
        final cat = critCategory[cid]!;
        categorySums[cat] = (categorySums[cat] ?? 0) + v;
        categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
        if (ctx.rng.nextDouble() < 0.25) {
          final txt = v >= 4
              ? ctx.pick<String>(posComments)
              : (v <= 2 ? ctx.pick<String>(negComments) : '');
          if (txt.isNotEmpty) {
            comments[cid] = txt;
            final line = '${ev.key.fullName} (${ev.value}): $txt';
            final list = categoryComments.putIfAbsent(cat, () => <String>[]);
            if (!list.contains(line)) list.add(line);
          }
        }
      }
      await ctx.set(
        ctx.col('development_evaluations').doc(ctx.id('deval_${s.id}_$e')),
        {
          'id': ctx.id('deval_${s.id}_$e'),
          'institutionId': ctx.inst,
          'reportId': reportId,
          'evaluatorId': ev.key.id,
          'evaluatorName': ev.key.fullName,
          'evaluatorRole': ev.value,
          'scores': scores,
          'comments': comments,
          'createdAt': Timestamp.fromDate(reportTs),
          'updatedAt': null,
        },
      );
    }

    final finalScores = <String, double>{};
    categorySums.forEach((cat, sum) {
      finalScores[cat] = double.parse(
        (sum / (categoryCounts[cat] ?? 1)).toStringAsFixed(2),
      );
    });
    final avgTotal = finalScores.isEmpty
        ? 0.0
        : finalScores.values.reduce((a, b) => a + b) / finalScores.length;
    final behavior = finalScores['Davranış ve Sorumluluk'] ?? 5.0;
    double risk = 0;
    final riskFactors = <String>[];
    if (behavior < 2.0) {
      risk += 40;
      riskFactors.add('Davranış puanı kritik seviyenin altında (<2).');
    }
    final sorted = finalScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final strengths = <String>[];
    final improvements = <String>[];
    for (final en in sorted) {
      if (en.value >= 4.0 && strengths.length < 3) strengths.add(en.key);
      if (en.value < 2.5 && improvements.length < 3) improvements.add(en.key);
    }
    String summary = 'Öğrencinin genel gelişimi ';
    if (avgTotal >= 4.5) {
      summary += 'mükemmel seviyededir. ';
    } else if (avgTotal >= 3.5) {
      summary += 'iyi seviyededir. ';
    } else if (avgTotal >= 2.5) {
      summary += 'orta seviyededir. ';
    } else {
      summary += 'desteklenmesi gereken seviyededir. ';
    }
    if (risk > 50) {
      summary +=
          'Dikkat! Risk faktörleri tespit edilmiştir. Rehberlik servisi görüşmesi önerilir.';
    }

    await ctx.set(ctx.col('development_reports').doc(reportId), {
      'id': reportId,
      'institutionId': ctx.inst,
      'sessionId': sessionId,
      'targetId': s.id,
      'targetType': 'student',
      'term': '1. Dönem Öğrenci Gelişim Raporu',
      'schoolYear': schoolYear,
      'categoryScores': finalScores,
      'analysis': {
        'riskFactors': riskFactors,
        'strengths': strengths,
        'improvements': improvements,
        'warnings': <String>[],
        'summary': summary,
        'categoryComments': categoryComments,
        'lastCalculated': Timestamp.fromDate(reportTs),
        'evaluationCount': evalRoles.length,
        'trend': 0.0,
      },
      'status': 'published',
      'isPublished': true,
      'createdAt': Timestamp.fromDate(reportTs),
      'updatedAt': Timestamp.fromDate(reportTs),
      'riskScore': risk,
      'growthIndex': double.parse(avgTotal.toStringAsFixed(2)),
      'termId': ctx.termId,
    });
    ctx.count('Gelişim raporu');
  }
}

// ---------------------------------------------------------------------------
// 7) TALEPLER / YÖNLENDİRMELER
// ---------------------------------------------------------------------------

Future<void> _seedDemands(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
  String Function(DemoStudentInfo) typeOf,
  List<DemoTeacherInfo> counselors,
) async {
  final items = <List<String>>[
    [
      'Akademik',
      'Derslerde ciddi başarı düşüşü',
      'Öğrencinin son iki sınavda belirgin düşüş var. Rehberlik görüşmesi ve çalışma planı desteği talep ediyorum.',
    ],
    [
      'Disiplin',
      'Sınıf içi davranış sorunu',
      'Ders sırasında arkadaşlarını rahatsız eden davranışlar sergiliyor. Davranışsal görüşme yapılmasını rica ederim.',
    ],
    [
      'Rehberlik',
      'Sınav kaygısı gözlemi',
      'Sınav öncesi aşırı gerginlik ve karın ağrısı şikayeti dile getiriyor. Kaygı yönetimi desteği talep ediyorum.',
    ],
    [
      'Sosyal',
      'Arkadaş ilişkilerinde zorlanma',
      'Teneffüslerde yalnız kalıyor, grup çalışmalarına katılmak istemiyor. Sosyal uyum çalışması önerilir.',
    ],
    [
      'Akademik',
      'Ödev yapmama alışkanlığı',
      'Son üç haftadır ödevlerini teslim etmiyor. Veli ile ortak bir görüşme planlanmasını talep ediyorum.',
    ],
    [
      'Rehberlik',
      'Devamsızlık takibi',
      'Öğrencinin devamsızlığı artmıştır. Aile ile iletişime geçilerek nedenlerin öğrenilmesi gerekiyor.',
    ],
    [
      'Diğer',
      'Veli görüşme talebi',
      'Veli, rehberlik servisi ile görüşmek istediğini bildirdi. Randevu verilmesi rica olunur.',
    ],
  ];
  final closing = [
    'Öğrenci ve veli ile görüşüldü, takip planı oluşturuldu.',
    'Bireysel görüşme yapıldı; durum olumlu seyrediyor.',
    'Sınıf öğretmeniyle koordineli çalışma başlatıldı, talep sonuçlandı.',
  ];
  final priorities = ['low', 'medium', 'medium', 'high', 'urgent'];

  final count = math.min(students.length, 24);
  for (int i = 0; i < count; i++) {
    final s = students[ctx.rng.nextInt(students.length)];
    final sender = ctx.pick<DemoTeacherInfo>(ctx.teachers);
    final rcv = ctx.pick<DemoTeacherInfo>(counselors);
    final it = items[i % items.length];
    final created = _pastDate(ctx, 60);
    final r = ctx.rng.nextDouble();
    final status = r < 0.35
        ? 'completed'
        : (r < 0.6
              ? 'inProgress'
              : (r < 0.85 ? 'open' : (r < 0.95 ? 'pending' : 'cancelled')));
    final closedAt = status == 'completed'
        ? created.add(Duration(days: ctx.between(1, 10)))
        : null;
    final closed = closedAt != null && closedAt.isAfter(ctx.today)
        ? ctx.today
        : closedAt;
    await ctx.set(ctx.col('guidance_demands').doc(ctx.id('dem_$i')), {
      'institutionId': ctx.inst,
      'schoolTypeId': typeOf(s),
      'termId': ctx.termId,
      'senderUid': sender.id,
      'senderName': sender.fullName,
      'senderRole': 'teacher',
      'receiverUids': [rcv.id],
      'receiverNames': [rcv.fullName],
      'studentUid': s.id,
      'studentName': s.fullName,
      'studentClassName': s.className,
      'title': it[1],
      'description': it[2],
      'category': it[0],
      'priority': ctx.pick<String>(priorities),
      'status': status,
      'createdAt': Timestamp.fromDate(created),
      'updatedAt': Timestamp.fromDate(closed ?? created),
      'closedAt': closed != null ? Timestamp.fromDate(closed) : null,
      'closingNote': status == 'completed' ? ctx.pick<String>(closing) : null,
      'closerUid': status == 'completed' ? rcv.id : null,
      'closerName': status == 'completed' ? rcv.fullName : null,
    });
    ctx.count('Rehberlik talebi');
  }
}

// ---------------------------------------------------------------------------
// 8) ETKİNLİKLER
// ---------------------------------------------------------------------------

Future<void> _seedActivities(
  DemoSeedContext ctx,
  List<DemoStudentInfo> students,
  Map<String, DemoClassInfo> classById,
  String Function(DemoStudentInfo) typeOf,
) async {
  final defs = <List<String>>[
    [
      'Kitap Okuma Etkinliği',
      'activity',
      'Sınıf kütüphanesinde sessiz okuma ve kitap tanıtımı etkinliği.',
    ],
    [
      'Bilim Şenliği',
      'activity',
      'Öğrencilerin hazırladığı deney ve projelerin sergilendiği şenlik.',
    ],
    [
      'Sınıf İçi Dikkat Gözlemi',
      'observation',
      'Ders sürecinde öğrencilerin dikkat ve katılım düzeyinin gözlenmesi.',
    ],
    [
      'Akran İlişkileri Gözlemi',
      'observation',
      'Teneffüs ve grup çalışmalarında akran etkileşimlerinin gözlemi.',
    ],
    [
      'Meslekler Tanıtım Günü',
      'activity',
      'Farklı meslek gruplarından konukların öğrencilerle buluşması.',
    ],
    ['Satranç Turnuvası', 'activity', 'Sınıflar arası satranç turnuvası.'],
    [
      'Bahar Şenliği Hazırlık Gözlemi',
      'observation',
      'Hazırlık çalışmalarında iş birliği ve sorumluluk gözlemi.',
    ],
    [
      'Sağlıklı Beslenme Semineri',
      'activity',
      'Okul hemşiresi ve rehberlik servisi ile beslenme semineri.',
    ],
  ];
  final obsQuestions = <Map<String, dynamic>>[
    _q('q1', 'Öğrencinin katılım düzeyi', 'rating'),
    _q(
      'q2',
      'Öğrencinin iş birliği becerisi',
      'singleChoice',
      options: ['Çok iyi', 'İyi', 'Orta', 'Geliştirilmeli'],
    ),
    _q('q3', 'Öğretmen notu', 'longText', required: false),
  ];
  final notes = [
    'Etkinliğe istekli katıldı.',
    'Grup içinde liderlik özellikleri gösterdi.',
    'Katılım konusunda teşvik edilmesi gerekiyor.',
    'Arkadaşlarıyla uyumlu çalıştı.',
  ];
  final qualities = ['Çok iyi', 'İyi', 'Orta', 'Geliştirilmeli'];

  if (ctx.classes.isEmpty) return;
  for (int i = 0; i < defs.length; i++) {
    final d = defs[i];
    final cls = ctx.classes[i % ctx.classes.length];
    final classStudents =
        ctx.studentsByClass[cls.id] ?? const <DemoStudentInfo>[];
    if (classStudents.isEmpty) continue;
    final teacher = ctx.pick<DemoTeacherInfo>(ctx.teachers);
    final isPlanned = i >= defs.length - 2;
    final date = isPlanned
        ? DateTime(
            ctx.today.year,
            ctx.today.month,
            ctx.today.day,
            10,
            0,
          ).add(Duration(days: ctx.between(2, 14)))
        : _pastDate(ctx, 70);
    final targetIds = classStudents.map((s) => s.id).toList();
    final participated = isPlanned
        ? <String>[]
        : classStudents
              .where((s) => ctx.rng.nextDouble() < 0.9)
              .map((s) => s.id)
              .toList();
    final activityId = ctx.id('act_$i');
    final evalEnabled = d[1] == 'observation';
    final created = _pastDate(ctx, 80);

    await ctx.set(ctx.col('activities').doc(activityId), {
      'institutionId': ctx.inst,
      'schoolTypeId': classById[cls.id]?.typeId ?? '',
      'title': '${d[0]} (${cls.name})',
      'description': d[2],
      'type': d[1],
      'date': Timestamp.fromDate(date),
      'responsibleTeacherId': teacher.id,
      'responsibleTeacherName': teacher.fullName,
      'targetStudentIds': targetIds,
      'isEvaluationEnabled': evalEnabled,
      'evaluatorTeacherIds': [teacher.id],
      'questions': evalEnabled ? obsQuestions : <Map<String, dynamic>>[],
      'status': isPlanned ? 'planned' : 'completed',
      'createdAt': Timestamp.fromDate(created.isAfter(date) ? date : created),
      'participatedStudentIds': participated,
      'termId': ctx.termId,
    });
    ctx.count('Etkinlik');

    if (evalEnabled && !isPlanned) {
      for (final sid in participated.take(12)) {
        await ctx.set(
          ctx.col('activity_evaluations').doc(ctx.id('actev_${i}_$sid')),
          {
            'institutionId': ctx.inst,
            'activityId': activityId,
            'studentId': sid,
            'evaluatorId': teacher.id,
            'evaluatorName': teacher.fullName,
            'createdAt': Timestamp.fromDate(date),
            'responses': {
              'q1': ctx.between(3, 5),
              'q2': ctx.pick<String>(qualities),
              'q3': ctx.pick<String>(notes),
            },
          },
        );
        ctx.count('Etkinlik değerlendirmesi');
      }
    }
  }
}
