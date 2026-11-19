import 'package:cloud_firestore/cloud_firestore.dart';

import 'demo_seed_context.dart';

/// GÜNLÜK KARNE (günlük rapor) demo verisi:
///  * `schools/{schoolDocId}/settings/daily_report_config` -> modül ayarı
///  * `schools/{schoolDocId}/daily_reports/{yyyy-MM-dd}_{studentId}` -> karneler
///    (Anaokulu: son 15 iş günü, İlkokul 1. sınıf: son 5 iş günü)

/// Yazılan üst düzey koleksiyon yok.
const List<String> demoDailyReportTopCollections = [];

/// `schools/{schoolDocId}/...` altında yazılan alt koleksiyonlar.
/// (`settings/daily_report_config` listelerle ulaşılamaz -> extras ile silinir.)
const List<String> demoDailyReportSchoolSubcollections = ['daily_reports'];

/// `settings/daily_report_config` demo dokümanını siler (yalnızca isDemo ise).
Future<int> cleanDemoDailyReportExtras(
  FirebaseFirestore db,
  String inst,
  String prefix,
  String schoolDocId,
) async {
  if (schoolDocId.isEmpty) return 0;
  try {
    final ref = db
        .collection('schools')
        .doc(schoolDocId)
        .collection('settings')
        .doc('daily_report_config');
    final snap = await ref.get();
    if (!snap.exists) return 0;
    final data = snap.data();
    if (data == null || data['isDemo'] != true) return 0;
    await ref.delete();
    return 1;
  } catch (_) {
    return 0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Yardımcılar
// ─────────────────────────────────────────────────────────────────────────────

String _two(int n) => n.toString().padLeft(2, '0');

String _ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// Bugünden geriye doğru [count] iş günü (bugün dahil, hafta sonu hariç).
List<DateTime> _schoolDays(DemoSeedContext ctx, int count) {
  final t = DateTime(ctx.today.year, ctx.today.month, ctx.today.day);
  final start = DateTime(
    ctx.termStart.year,
    ctx.termStart.month,
    ctx.termStart.day,
  );
  final days = <DateTime>[];
  var back = 0;
  while (days.length < count && back < 120) {
    final d = DateTime(t.year, t.month, t.day - back);
    back++;
    if (d.isBefore(start)) break;
    if (d.weekday > 5) continue;
    days.add(d);
  }
  return days.reversed.toList();
}

class _Act {
  final String category;
  final String title;
  final String description;
  final String time;
  const _Act(this.category, this.title, this.description, this.time);
}

const List<_Act> _acts = [
  _Act(
    'book',
    'Hikaye Saati',
    'Aç Tırtıl hikayesi okundu, karakterler üzerine sohbet edildi.',
    '09:30',
  ),
  _Act(
    'book',
    'Masal Dinleme',
    'Üç Küçük Kurt masalı dinlendi ve resimlerle anlatıldı.',
    '10:00',
  ),
  _Act(
    'art',
    'Sanat Etkinliği',
    'Parmak boyası ile mevsim ağacı kolajı yapıldı.',
    '10:30',
  ),
  _Act(
    'art',
    'Hamur Atölyesi',
    'Oyun hamuruyla hayvan figürleri şekillendirildi.',
    '10:30',
  ),
  _Act(
    'music',
    'Müzik & Ritim',
    'Orff çalgılarıyla ritim tutma ve çocuk şarkıları çalışıldı.',
    '11:00',
  ),
  _Act(
    'drama',
    'Oyun Zamanı',
    'Meslekler yaratıcı drama canlandırması ve halka oyunu yapıldı.',
    '11:00',
  ),
  _Act(
    'science',
    'Fen Deneyi',
    'Su-yağ yoğunluk deneyi yapıldı, gözlemler paylaşıldı.',
    '10:15',
  ),
  _Act(
    'science',
    'Akıl Oyunları',
    'Eşleştirme ve sıralama akıl oyunları oynandı.',
    '14:00',
  ),
  _Act(
    'sport',
    'Bahçe Oyunu',
    'Denge parkuru, top yakalama ve açık hava egzersizi yapıldı.',
    '13:30',
  ),
  _Act(
    'literacy',
    'Matematik & Hazırlık',
    'Çizgi tamamlama ve 1-10 arası nesne sayma çalışması yapıldı.',
    '09:15',
  ),
  _Act(
    'english',
    'İngilizce',
    'Renkler ve hayvanlar şarkılarla tekrar edildi.',
    '14:30',
  ),
];

const List<String> _participations = [
  'enthusiastic',
  'enthusiastic',
  'participated',
  'participated',
  'observed',
  'supported',
];

const List<String> _moods = [
  'happy',
  'happy',
  'happy',
  'energetic',
  'calm',
  'calm',
  'shy',
  'tired',
  'fussy',
];

const List<String> _socials = ['great', 'great', 'good', 'good', 'individual'];

const List<String> _waters = ['good', 'good', 'medium', 'medium', 'low'];

const List<String> _selfCare = [
  'El Yıkama & Hijyen Tam ✨',
  'Diş Fırçalama Yapıldı 🪥',
  'Tuvalet İhtiyacı Bağımsız 👍',
  'Tuvalet Eğitiminde Desteklendi 🤲',
  'Yedek Kıyafet Değiştirildi 👕',
  'Terlediği İçin Üstü Değiştirildi 🧥',
];

const List<String> _neededItems = [
  'Yedek Kıyafet Gönderiniz 👕',
  'Islak Mendil / Peçete İhtiyacı 🧻',
  'Suluk Gönderilmeli 💧',
  'Panduf / Okul Ayakkabısı 👟',
  'Boyama Önlüğü 🎨',
  'Yarın Gezi / Etkinlik Günü 🚌',
];

const List<String> _breakfastMenus = [
  'Peynir, zeytin, domates, süt',
  'Yumurta, salatalık, simit, süt',
  'Bal, tereyağı, ekmek, meyve suyu',
  'Omlet, peynir, mevsim meyvesi',
];

const List<String> _lunchMenus = [
  'Mercimek çorbası, tavuk sote, pilav, ayran',
  'Kuru fasulye, bulgur pilavı, cacık, meyve',
  'Ezogelin çorbası, köfte, makarna, yoğurt',
  'Sebze çorbası, fırın patates, tavuk, komposto',
  'Etli nohut, pilav, turşu, tatlı',
];

const List<String> _snackMenus = [
  'Meyve tabağı ve kurabiye',
  'Süt ve tam buğday bisküvi',
  'Mevsim meyvesi, kuru üzüm',
];

const List<String> _sleepRanges = [
  '30 Dakika',
  '45 Dakika',
  '1 Saat',
  '1.5 Saat',
  '2 Saat',
  '12:30 - 14:00',
  '13:00 - 14:30',
];

const List<String> _positiveNotes = [
  'bugün arkadaşlarıyla çok güzel vakit geçirdi, etkinliklere istekle katıldı.',
  'sınıfta çok paylaşımcıydı, oyuncaklarını arkadaşlarıyla paylaştı.',
  'yeni öğrendiği şarkıyı bütün gün mırıldandı, çok neşeliydi.',
  'boyama etkinliğinde dikkatini uzun süre sürdürdü, emeğini takdir ettik.',
  'toplama ve sayma çalışmasında harika ilerleme gösterdi.',
  'bugün kendi başına ayakkabılarını giymeye çalıştı, çok gururlandı.',
  'hikaye saatinde sorulara aktif cevap verdi.',
  'bahçe oyununda enerjisi yerindeydi, grup oyunlarına katıldı.',
];

const List<String> _careNotes = [
  'sabah ayrılırken biraz duygusaldı ancak kısa sürede uyum sağladı.',
  'bugün biraz yorgun görünüyordu, sakin etkinliklerle desteklendi.',
  'öğle yemeğinde iştahı azdı, su içmesi için teşvik edildi.',
  'arkadaşıyla küçük bir anlaşmazlık yaşadı, birlikte konuşarak çözdük.',
];

const List<String> _feedbacks = [
  'Bilgilendirme için çok teşekkür ederiz, evde de tekrar edeceğiz.',
  'Çocuğumuz akşam gün boyu yaptıklarını heyecanla anlattı, emekleriniz için sağ olun.',
  'Yedek kıyafeti yarın göndereceğiz, hatırlattığınız için teşekkürler.',
  'Uyku düzeni konusunda evde de dikkat edeceğiz.',
];

const List<String> _healthNotes = [
  'Hafif öksürük gözlemlendi, veliye bilgi verildi.',
  'Bahçede düşme sonucu dizinde hafif sıyrık oluştu, pansuman yapıldı.',
  'Burun akıntısı mevcuttu, bol sıvı tüketmesi sağlandı.',
];

String _firstName(String full) {
  final parts = full.trim().split(' ');
  return parts.isEmpty || parts.first.isEmpty ? 'Öğrencimiz' : parts.first;
}

/// Ağırlıklı öğün durumu.
String _mealStatus(DemoSeedContext ctx, {double appetite = 0.5}) {
  final r = ctx.rng.nextInt(100);
  final shift = ((appetite - 0.5) * 30).round();
  final v = r - shift;
  if (v < 45) return 'full';
  if (v < 72) return 'half';
  if (v < 90) return 'little';
  return 'none';
}

// ─────────────────────────────────────────────────────────────────────────────
// Ana giriş noktası
// ─────────────────────────────────────────────────────────────────────────────

Future<void> seedDemoDailyReport(DemoSeedContext ctx) async {
  if (ctx.schoolDocId.isEmpty) return;

  final kinderClasses = ctx.classes
      .where((c) => c.typeKind == 'Anaokulu')
      .toList();
  if (kinderClasses.isEmpty) return;

  // İlkokul 1. sınıflar (daha hafif set)
  final primaryClasses = ctx.classes
      .where((c) => c.typeKind == 'İlkokul' && c.level == 1)
      .toList();

  final reportsCol = ctx.schoolCol('daily_reports');
  if (reportsCol == null) return;

  // (a) Konfigürasyon: modül Anaokulu (+ 1. sınıf olan İlkokul) türlerinde açık.
  final enabledTypeIds = <String>{
    for (final c in kinderClasses) c.typeId,
    for (final c in primaryClasses) c.typeId,
  }.where((e) => e.isNotEmpty).toList();

  await ctx.set(
    ctx.db
        .collection('schools')
        .doc(ctx.schoolDocId)
        .collection('settings')
        .doc('daily_report_config'),
    {
      'institutionId': ctx.inst,
      'enabled': true,
      'enabledSchoolTypeIds': enabledTypeIds,
      'trackMood': true,
      'trackMeals': true,
      'trackWater': true,
      'trackSleep': true,
      'trackActivities': true,
      'trackSelfCare': true,
      'trackHealthNote': true,
      'allowParentFeedback': true,
      'updatedAt': Timestamp.fromDate(ctx.today),
    },
  );
  ctx.count('Günlük karne ayarı');

  // (b) Karneler
  final kinderDays = _schoolDays(ctx, 15);
  final primaryDays = _schoolDays(ctx, 5);
  var actSeq = 0;

  Future<void> seedClass(DemoClassInfo cls, List<DateTime> days) async {
    final students = ctx.studentsByClass[cls.id] ?? const <DemoStudentInfo>[];
    if (students.isEmpty || days.isEmpty) return;

    // Sınıf öğretmeni: ilk dersin öğretmeni, yoksa aynı türden / ilk öğretmen.
    String teacherId = '';
    String teacherName = '';
    for (final l in cls.lessons) {
      if (l.teacherName.trim().isNotEmpty) {
        teacherId = l.teacherId;
        teacherName = l.teacherName;
        break;
      }
    }
    if (teacherName.isEmpty && ctx.teachers.isNotEmpty) {
      final same = ctx.teachers.where((t) => t.typeId == cls.typeId).toList();
      final t = same.isNotEmpty ? same.first : ctx.teachers.first;
      teacherId = t.id;
      teacherName = t.fullName;
    }
    if (teacherName.isEmpty) teacherName = 'Sınıf Öğretmeni';

    // Her öğrenci için 1-2 devamsızlık günü + iştah / uyku eğilimi.
    for (final s in students) {
      final absent = <int>{};
      final absentCount = ctx.between(0, 2);
      for (var i = 0; i < absentCount; i++) {
        absent.add(ctx.rng.nextInt(days.length));
      }
      final appetite = ctx.rng.nextDouble();
      final sleeper = ctx.rng.nextInt(100) < 70;
      final first = _firstName(s.fullName);

      for (var di = 0; di < days.length; di++) {
        if (absent.contains(di)) continue;
        final day = days[di];
        final isToday =
            day.year == ctx.today.year &&
            day.month == ctx.today.month &&
            day.day == ctx.today.day;
        final dateKey = _ymd(day);

        final nAct = ctx.between(2, 4);
        final chosen = <_Act>[];
        // Sınıf günü içinde tekrar etmesin diye gün bazlı başlangıç.
        final startIdx = (di * 3 + cls.name.length) % _acts.length;
        for (var i = 0; i < nAct; i++) {
          chosen.add(_acts[(startIdx + i * 2) % _acts.length]);
        }
        final activities = <Map<String, dynamic>>[];
        for (final a in chosen) {
          final hh = int.tryParse(a.time.split(':').first) ?? 10;
          final mm = int.tryParse(a.time.split(':').last) ?? 0;
          activities.add({
            'id': ctx.id('dra_${actSeq++}'),
            'category': a.category,
            'title': a.title,
            'description': a.description,
            'timeLabel': a.time,
            'participation': ctx.pick(_participations),
            'photoUrl': '',
            'teacherName': teacherName,
            'createdAt': Timestamp.fromDate(
              DateTime(day.year, day.month, day.day, hh, mm),
            ),
          });
        }

        final sleepStatusRoll = ctx.rng.nextInt(100);
        String sleepStatus;
        if (sleeper) {
          sleepStatus = sleepStatusRoll < 80 ? 'slept' : 'rested';
        } else {
          sleepStatus = sleepStatusRoll < 50 ? 'rested' : 'awake';
        }
        final slept = sleepStatus == 'slept';

        final mood = ctx.pick(_moods);
        final tiredOrFussy = mood == 'tired' || mood == 'fussy';

        final selfCare = <String>{
          'El Yıkama & Hijyen Tam ✨',
          if (ctx.rng.nextBool()) 'Tuvalet İhtiyacı Bağımsız 👍',
          if (ctx.rng.nextInt(3) == 0) 'Diş Fırçalama Yapıldı 🪥',
          if (ctx.rng.nextInt(10) == 0) ctx.pick(_selfCare),
        }.toList();

        final needed = <String>[];
        if (ctx.rng.nextInt(100) < 35) {
          needed.add(ctx.pick(_neededItems));
          if (ctx.rng.nextInt(5) == 0) {
            final extra = ctx.pick(_neededItems);
            if (!needed.contains(extra)) needed.add(extra);
          }
        }

        final healthNote = ctx.rng.nextInt(100) < 8
            ? ctx.pick(_healthNotes)
            : '';

        final note = tiredOrFussy || ctx.rng.nextInt(100) < 15
            ? '$first ${ctx.pick(_careNotes)}'
            : '$first ${ctx.pick(_positiveNotes)}';

        // Veli görüntüleme / geri bildirim (bugünkü karneler çoğunlukla görülmemiş).
        DateTime? seenAt;
        String reaction = '';
        String feedbackNote = '';
        DateTime? feedbackAt;
        final seenRoll = ctx.rng.nextInt(100);
        if (isToday ? seenRoll < 20 : seenRoll < 65) {
          seenAt = DateTime(
            day.year,
            day.month,
            day.day,
            ctx.between(17, 21),
            ctx.between(0, 59),
          );
          if (ctx.rng.nextInt(100) < 55) {
            reaction = ctx.pick(['❤️', '👏', '😊', '👍']);
          }
          if (ctx.rng.nextInt(100) < 18) {
            feedbackNote = ctx.pick(_feedbacks);
            feedbackAt = seenAt.add(Duration(minutes: ctx.between(2, 30)));
          }
        }

        var updatedAt = DateTime(day.year, day.month, day.day, 16, 30);
        if (updatedAt.isAfter(ctx.today)) updatedAt = ctx.today;

        final docId = '${dateKey}_${s.id}';
        await ctx.set(reportsCol.doc(docId), {
          'institutionId': ctx.inst,
          'schoolDocId': ctx.schoolDocId,
          'schoolTypeId': cls.typeId,
          'schoolTypeName': cls.typeName,
          'classId': cls.id,
          'className': cls.name,
          'classLevel': cls.level.toString(),
          'studentId': s.id,
          'studentName': s.fullName,
          'studentNo': s.no,
          'dateKey': dateKey,
          'mood': mood,
          'socialHarmony': ctx.pick(_socials),
          'breakfast': {
            'status': _mealStatus(ctx, appetite: appetite),
            'menuOrNote': ctx.pick(_breakfastMenus),
          },
          'lunch': {
            'status': _mealStatus(ctx, appetite: appetite),
            'menuOrNote': ctx.pick(_lunchMenus),
          },
          'snack': {
            'status': _mealStatus(ctx, appetite: appetite),
            'menuOrNote': ctx.pick(_snackMenus),
          },
          'waterIntake': ctx.pick(_waters),
          'sleep': {
            'status': sleepStatus,
            'durationOrRange': slept
                ? ctx.pick(_sleepRanges)
                : (sleepStatus == 'rested' ? '30 Dakika' : ''),
            'quality': slept
                ? ctx.pick(['peaceful', 'peaceful', 'normal', 'light'])
                : '',
            'note': '',
          },
          'activities': activities,
          'selfCareTags': selfCare,
          'healthNote': healthNote,
          'neededItems': needed,
          'teacherNote': note,
          'isPublished': true,
          if (seenAt != null) 'parentSeenAt': Timestamp.fromDate(seenAt),
          'parentReaction': reaction,
          'parentFeedbackNote': feedbackNote,
          if (feedbackAt != null)
            'parentFeedbackAt': Timestamp.fromDate(feedbackAt),
          'updatedAt': Timestamp.fromDate(updatedAt),
          'updatedByUid': teacherId,
          'updatedByName': teacherName,
          'contributors': [teacherName],
        });
        ctx.count('Günlük karne');
      }
    }
  }

  for (final cls in kinderClasses) {
    await seedClass(cls, kinderDays);
  }
  for (final cls in primaryClasses) {
    await seedClass(cls, primaryDays);
  }
}
