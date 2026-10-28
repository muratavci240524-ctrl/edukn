import 'dart:typed_data';

import 'package:edukn/models/assessment/trial_exam_model.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../odak64/models/odak_models.dart';

/// Bir kazanımdaki öğrenci sonucu.
class StudentOutcomeResult {
  final String label;
  int total = 0;
  int correct = 0;
  int wrong = 0;
  int empty = 0;
  StudentOutcomeResult(this.label);
  double get rate => total == 0 ? 0 : correct / total;
}

/// Bir dersteki öğrenci raporu.
class StudentSubjectReport {
  final String subject;
  final OdakSubjectStat stat;
  final double branchRate; // 0..1
  final List<StudentOutcomeResult> outcomes;
  final List<int> wrongQuestions;
  final List<int> emptyQuestions;

  StudentSubjectReport({
    required this.subject,
    required this.stat,
    required this.branchRate,
    required this.outcomes,
    required this.wrongQuestions,
    required this.emptyQuestions,
  });

  double get rate => stat.successRate;
}

class StudentGoal {
  final String subject;
  final double current;
  final double target;
  const StudentGoal(this.subject, this.current, this.target);
}

class StudySession {
  final String day;
  final String subject;
  final String task;
  final int minutes;

  /// true: genel tekrar oturumu (ek oturum / pazar). false: ana çalışma oturumu.
  final bool review;

  /// true: tekrar dersi, öğrencinin o gün okulda gördüğü dersten seçildi.
  final bool fromSchool;

  const StudySession(
    this.day,
    this.subject,
    this.task,
    this.minutes, {
    this.review = false,
    this.fromSchool = false,
  });
}

class StudyWeek {
  final int week;
  final String phase;
  final String objective;
  final String focus;
  final List<StudySession> sessions;
  const StudyWeek({
    required this.week,
    required this.phase,
    required this.objective,
    required this.focus,
    required this.sessions,
  });
  int get totalMinutes => sessions.fold(0, (a, s) => a + s.minutes);
}

/// Tek öğrencinin tüm raporu.
class StudentReport {
  final OdakExamResult result;
  final String branch;
  final double overallRate;
  final double branchOverall;
  final int correct;
  final int wrong;
  final int empty;
  final List<StudentSubjectReport> subjects;
  final List<String> strengths;
  final List<String> focusAreas;
  final List<String> habits;
  final List<StudentGoal> goals;
  final List<StudyWeek> plan;

  StudentReport({
    required this.result,
    required this.branch,
    required this.overallRate,
    required this.branchOverall,
    required this.correct,
    required this.wrong,
    required this.empty,
    required this.subjects,
    required this.strengths,
    required this.focusAreas,
    required this.habits,
    required this.goals,
    required this.plan,
  });

  String get name => result.student.name;

  /// Öğrencinin gerçekten girdiği kitapçık türü (örn. "B Kitapçığı").
  /// Optikte kitapçık okunamadıysa sistem A varsayar; bu durum açıkça belirtilir.
  bool get bookletKnown => result.booklet.trim().isNotEmpty;
  bool get merged => result.isMerged;
  String get bookletLabel => merged
      ? 'Birleşik değerlendirme'
      : (bookletKnown
          ? '${result.bookletLetter.toUpperCase()} Kitapçığı'
          : 'Kitapçık belirtilmemiş (A varsayıldı)');
}

/// Öğrenci bazlı performans özeti: analiz + kişisel çalışma planı + PDF.
/// Tamamen deterministik / kural tabanlıdır (API maliyeti yok).
class StudentPerfService {
  StudentPerfService._();

  static String level(double r) {
    if (r >= 0.85) return 'Çok iyi';
    if (r >= 0.70) return 'İyi';
    if (r >= 0.50) return 'Orta';
    if (r >= 0.30) return 'Geliştirilmeli';
    return 'Öncelikli';
  }

  /// Türkçe karakterleri sadeleştirip küçük harfe çevirir (karşılaştırma için).
  static String _fold(String s) {
    var t = s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
    const m = {'ı': 'i', 'ö': 'o', 'ü': 'u', 'ş': 's', 'ç': 'c', 'ğ': 'g'};
    m.forEach((k, v) => t = t.replaceAll(k, v));
    return t;
  }

  /// LGS sınav sırası: Türkçe - Sosyal Bilgiler (İnkılap) - Din Kültürü -
  /// İngilizce - Matematik - Fen Bilimleri. Tanınmayan dersler en sona gider.
  static int subjectRank(String subject) {
    final n = _fold(subject);
    if (n.contains('sosyal') || n.contains('inkilap') || n.contains('tarih')) {
      return 1;
    }
    if (n.contains('din') && (n.contains('kultur') || n.startsWith('din')) ||
        n.contains('ahlak')) {
      return 2;
    }
    if (n.contains('turkce') || n.contains('turk dili')) return 0;
    if (n.contains('ingilizce') ||
        n.contains('yabanci') ||
        n.contains('english')) {
      return 3;
    }
    if (n.contains('matematik')) return 4;
    if (n.contains('fen')) return 5;
    return 99;
  }

  /// Dersleri sınav sırasına göre (kararlı) dizer.
  static List<String> sortSubjects(Iterable<String> subjects) {
    final list = subjects.toList();
    final idx = {for (var i = 0; i < list.length; i++) list[i]: i};
    list.sort((a, b) {
      final c = subjectRank(a).compareTo(subjectRank(b));
      return c != 0 ? c : idx[a]!.compareTo(idx[b]!);
    });
    return list;
  }

  static String _outcomeFor(
    Map<String, Map<String, List<String>>> outcomes,
    OdakExamResult r,
    String subject,
    int i,
  ) {
    List<String>? list = outcomes[r.bookletLetter]?[subject];
    if (list == null) {
      for (final m in outcomes.values) {
        final l = m[subject];
        if (l != null) {
          list = l;
          break;
        }
      }
    }
    if (list == null || i >= list.length) return '';
    final o = list[i].trim();
    return o == '-' ? '' : o;
  }

  // ───────────────────────── SINAV ALIŞKANLIKLARI ─────────────────────────

  /// Kararlı (platform bağımsız) basit hash; aynı öğrenci → aynı metin seçimi.
  static int _hash(String s) {
    var h = 17;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  static int _pct(double v) => (v * 100).round();

  /// Geniş havuzlu, kural tabanlı sınav alışkanlığı üretici.
  /// Her kural birden çok ifade varyantı içerir; varyant öğrenci kimliğine göre
  /// deterministik seçilir. Aynı gruptan yalnızca bir madde alınır (çelişki yok).
  static List<String> _buildHabits({
    required String seed,
    required List<StudentSubjectReport> subs,
    required int tc,
    required int tw,
    required int te,
    required double overall,
    required double branchOverall,
  }) {
    final total = tc + tw + te;
    if (total == 0) return <String>[];

    String pick(String key, List<String> v) =>
        v[_hash('$seed|$key') % v.length];

    final er = te / total;
    final wr = tw / total;
    final attempted = tc + tw;
    final acc = attempted == 0 ? 0.0 : tc / attempted;

    // (öncelik, grup, metin) — düşük öncelik değeri = daha önemli
    final c = <(int, String, String)>[];
    void add(int p, String g, String t) => c.add((p, g, t));

    // ── Boş bırakma ──
    if (er >= 0.15) {
      add(1, 'empty', pick('empty_hi', [
        'Soruların %${_pct(er)}\'ini boş bıraktın ($te soru). Bilmediğin sorularda '
            'şıkları eleyerek tahmin etmeyi dene; boş soru kazandırmaz.',
        '$te soruyu cevapsız bırakmışsın (%${_pct(er)}). Emin olmadığın sorularda en az '
            'iki şıkkı eleyebiliyorsan işaretlemek çoğu zaman avantajlıdır.',
        'Boş oranın %${_pct(er)} ile yüksek. Önce kolay soruları topla, takıldıklarını '
            'işaretle; sonunda kalan süreyle tekrar dön.',
        'Çok sayıda boş ($te) var: bu genellikle özgüven ya da süre sorunudur. '
            'Deneme sırasında "20 saniye kuralı" uygula; çözemediğini geç, sonra dön.',
      ]));
    } else if (er >= 0.06) {
      add(4, 'empty', pick('empty_mid', [
        'Boş oranın %${_pct(er)} ile makul. Birkaç soruyu daha değerlendirirsen net artışı gelir.',
        '$te boş sorun var; bunların bir kısmı tahminle kazanıma dönüşebilir.',
        'Boş bırakma alışkanlığın kontrollü (%${_pct(er)}). Son turda boşlara göz at.',
      ]));
    } else {
      add(5, 'empty', pick('empty_lo', [
        'Neredeyse hiç soru boş bırakmıyorsun (%${_pct(er)}); bu cesur ve istikrarlı bir tutum.',
        'Tüm soruları denemen güzel bir alışkanlık; şimdi isabet oranını yükseltmeye odaklan.',
        'Boş oranın çok düşük ($te soru). Sınavı sonuna kadar yönetebiliyorsun.',
      ]));
    }

    // ── Yanlış oranı / tahmin kalitesi ──
    if (wr >= 0.35) {
      add(1, 'wrong', pick('wrong_hi', [
        'Yanlış oranın %${_pct(wr)} ($tw soru). Soruyu iki kez oku, anahtar '
            'kelimelerin altını çiz ve işlem sonuçlarını kontrol et.',
        '$tw yanlışın var; bunların çoğu dikkat hatası olabilir. Cevabı işaretlemeden '
            'önce soru kökünü yeniden oku ("değil", "en az" gibi ifadelere dikkat).',
        'Yanlış sayın yüksek (%${_pct(wr)}). Yanlış yaptığın soruları konu/dikkat hatası '
            'diye ayırarak bir hata defteri tut.',
        'Hızlı ama hatalı gidiyor olabilirsin. Her soruya birkaç saniye daha ayır ve '
            'şıkları tek tek sına.',
      ]));
    } else if (wr >= 0.20) {
      add(3, 'wrong', pick('wrong_mid', [
        'Yanlış oranın %${_pct(wr)}; biraz daha dikkatle bu rakamı kolayca düşürebilirsin.',
        '$tw yanlış var. Bunları tek tek incelemek en hızlı net kazancı sağlar.',
        'Yanlışların kontrol edilebilir seviyede (%${_pct(wr)}). Son kontrol turu faydalı olur.',
      ]));
    } else {
      add(5, 'wrong', pick('wrong_lo', [
        'Yanlış oranın düşük (%${_pct(wr)}); ne yaptığını bilerek işaretliyorsun.',
        'Sadece $tw yanlışın var; dikkat ve kontrol alışkanlığın güçlü.',
        'Hata oranın az. Şimdi zor sorulara biraz daha zaman ayırma vakti.',
      ]));
    }

    // ── Denenen sorulardaki isabet ──
    if (attempted >= 8) {
      if (acc >= 0.80) {
        add(3, 'acc', pick('acc_hi', [
          'Cevapladığın soruların %${_pct(acc)}\'i doğru; isabet oranın çok yüksek.',
          'İşaretlediğinde genelde haklısın (%${_pct(acc)} isabet). Daha fazla soruya girmek net getirir.',
          'Denediğin soruların %${_pct(acc)}\'ini doğru yapıyorsun; temelin sağlam.',
        ]));
      } else if (acc < 0.55 && tw >= 5) {
        add(2, 'acc', pick('acc_lo', [
          'İşaretlediğin soruların yalnızca %${_pct(acc)}\'i doğru. Emin olmadığında '
              'rastgele işaretlemek yerine eleme yöntemini kullan.',
          'İsabet oranın %${_pct(acc)}. Yanlışlar doğruları götürdüğü için (4 yanlış = 1 doğru) '
              'tahminlerini seçici yap.',
          'Cevapladıkların arasında doğruluk %${_pct(acc)}; önce bildiklerinden emin ol, sonra riske gir.',
        ]));
      }
    }

    // ── Net kaybı (yanlışın doğruyu götürmesi) ──
    final netSum = subs.fold<double>(0, (a, s) => a + s.stat.net);
    final lost = tc - netSum;
    if (lost >= 3) {
      add(3, 'net', pick('net', [
        'Yanlışlar yüzünden yaklaşık ${lost.toStringAsFixed(1)} net kaybettin; '
            'her yanlış bir doğruyu götürüyor.',
        'Doğru sayın $tc ama net ${netSum.toStringAsFixed(1)}: aradaki fark yanlışlardan geliyor.',
        '${lost.toStringAsFixed(1)} netlik bir kayıp var; yanlışları azaltmak toplam puanı doğrudan yükseltir.',
      ]));
    }

    // ── Ders bazlı en çok boş / yanlış ──
    StudentSubjectReport? maxEmpty, maxWrong;
    for (final s in subs) {
      if (maxEmpty == null || s.stat.empty > maxEmpty.stat.empty) maxEmpty = s;
      if (maxWrong == null || s.stat.wrong > maxWrong.stat.wrong) maxWrong = s;
    }
    if (maxEmpty != null && subs.length > 1 && maxEmpty.stat.empty >= 3) {
      final n = maxEmpty.stat.correct + maxEmpty.stat.wrong + maxEmpty.stat.empty;
      if (n > 0 && maxEmpty.stat.empty / n >= 0.2) {
        add(2, 'empty_subject', pick('es', [
          'En çok boşun ${maxEmpty.subject} dersinde (${maxEmpty.stat.empty}/$n). Bu derste konu '
              'eksiğin ya da süre sıkışıklığın olabilir.',
          '${maxEmpty.subject} dersinde ${maxEmpty.stat.empty} soruyu boş bıraktın; '
              'bu derse özel kısa tekrar yapmak işe yarar.',
          'Boşlarının çoğu ${maxEmpty.subject} dersinde. Bu dersin sorularına girmekten çekinme.',
        ]));
      }
    }
    if (maxWrong != null && subs.length > 1 && maxWrong.stat.wrong >= 3 &&
        (maxEmpty == null || maxWrong.subject != maxEmpty.subject || maxWrong.stat.wrong >= 5)) {
      add(2, 'wrong_subject', pick('ws', [
        'En çok yanlışın ${maxWrong.subject} dersinde (${maxWrong.stat.wrong} soru). '
            'Bu dersin yanlışlarını konu konu gözden geçir.',
        '${maxWrong.subject} dersinde ${maxWrong.stat.wrong} yanlış yapmışsın; bu ders hata defterinin ilk sırası olsun.',
        'Hatalar ${maxWrong.subject} dersinde yoğunlaşıyor (${maxWrong.stat.wrong}). Önce bu dersin soru tiplerine bak.',
      ]));
    }

    // ── Konum bazlı örüntüler (süre yönetimi / ısınma) ──
    var emptyTail = 0, emptyAll = 0, wrongHead = 0, wrongAll = 0, longRun = 0;
    String? runSubject;
    for (final s in subs) {
      final n = s.stat.correct + s.stat.wrong + s.stat.empty;
      if (n < 6) continue;
      final third = n / 3;
      for (final q in s.emptyQuestions) {
        emptyAll++;
        if (q > n - third) emptyTail++;
      }
      for (final q in s.wrongQuestions) {
        wrongAll++;
        if (q <= third) wrongHead++;
      }
      var run = 1;
      final eq = [...s.emptyQuestions]..sort();
      for (var i = 1; i < eq.length; i++) {
        run = eq[i] == eq[i - 1] + 1 ? run + 1 : 1;
        if (run > longRun) {
          longRun = run;
          runSubject = s.subject;
        }
      }
    }
    if (emptyAll >= 3 && emptyTail / emptyAll >= 0.6) {
      add(1, 'tail', pick('tail', [
        'Boşların çoğu derslerin son bölümünde. Süre yönetimini gözden geçir: '
            'daha hızlı başla, zor soruda takılma.',
        'Soruların sonlarına doğru boş bırakma artıyor; bu süre bitmesi veya yorgunluk işareti olabilir.',
        'Dersin son sorularına yetişemiyor olabilirsin. Süreli deneme çözerek tempo kazan.',
      ]));
    } else if (longRun >= 4) {
      add(2, 'tail', pick('run', [
        '$runSubject dersinde art arda $longRun soruyu boş bırakmışsın; bu bir konu bloğu eksiği olabilir.',
        'Art arda $longRun boş ($runSubject) bir konunun tamamen çalışılmadığını gösteriyor.',
        '$runSubject dersindeki ardışık $longRun boş soru, ilgili konuya dönmen gerektiğini söylüyor.',
      ]));
    } else if (wrongAll >= 4 && wrongHead / wrongAll >= 0.5) {
      add(2, 'tail', pick('head', [
        'Yanlışlar derslerin başında yoğunlaşıyor: ısınma turu yapıp ilk sorularda daha dikkatli ol.',
        'Sınava başlarken hata yapma eğilimin var; ilk 5 soruda yavaş ve kontrollü git.',
        'İlk sorularda yanlışların fazla. Sınav öncesi 10 dakikalık kısa ısınma çözümü yap.',
      ]));
    }

    // ── Dersler arası denge ──
    if (subs.length >= 3) {
      final rates = subs.map((s) => s.rate).toList()..sort();
      final spread = rates.last - rates.first;
      final best = subs.reduce((a, b) => a.rate >= b.rate ? a : b);
      final worst = subs.reduce((a, b) => a.rate <= b.rate ? a : b);
      if (spread >= 0.35) {
        add(2, 'spread', pick('spread_hi', [
          '${best.subject} (%${_pct(best.rate)}) ile ${worst.subject} (%${_pct(worst.rate)}) '
              'arasında büyük fark var; zamanını dengele.',
          'Dersler arası performansın dengesiz: ${worst.subject} geride kalıyor.',
          '${best.subject} güçlü, ${worst.subject} zayıf. Haftalık plana ${worst.subject} için ek süre koy.',
        ]));
      } else if (spread <= 0.12) {
        add(4, 'spread', pick('spread_lo', [
          'Dersler arasında dengeli bir performans sergiliyorsun.',
          'Başarın derslere eşit dağılmış; bu istikrar güvenli bir temel.',
          'Hiçbir derste belirgin düşüş yok; genel seviyeyi birlikte yükseltebilirsin.',
        ]));
      }
    }

    // ── Şube karşılaştırması (genel + ders bazlı) ──
    if (overall >= branchOverall + 0.05) {
      add(3, 'branch', pick('br_hi', [
        'Genel başarın şube ortalamasının %${_pct(overall - branchOverall)} puan üzerinde. Bu çizgiyi koru.',
        'Şubene göre öndesin (%${_pct(overall)} / ort. %${_pct(branchOverall)}). Tempoyu bırakma.',
        'Şube ortalamasının üzerinde bir sonuç aldın; bunu bir sonraki denemede de tekrarla.',
      ]));
    } else if (overall <= branchOverall - 0.05) {
      add(3, 'branch', pick('br_lo', [
        'Genel başarın şube ortalamasının biraz altında. Planı düzenli uygularsan farkı kısa sürede kapatabilirsin.',
        'Şube ortalamasına %${_pct(branchOverall - overall)} puan uzaktasın; hedeflenen çalışmalarla bu fark kapanır.',
        'Ortalamanın altında olman geçici; zayıf kazanımlara odaklanırsan hızla yükselirsin.',
      ]));
    } else {
      add(4, 'branch', pick('br_mid', [
        'Genel başarın şube ortalamasına yakın. Küçük gelişmelerle öne geçebilirsin.',
        'Şubenle aynı seviyedesin; birkaç net fark yaratabilir.',
        'Ortalamaya çok yakınsın; zayıf bir dersi toparlaman seni öne taşır.',
      ]));
    }
    if (subs.length >= 2) {
      final diffs = [for (final s in subs) (s, s.rate - s.branchRate)]
        ..sort((a, b) => b.$2.compareTo(a.$2));
      final top = diffs.first, low = diffs.last;
      if (top.$2 >= 0.10) {
        add(4, 'sub_top', pick('st', [
          '${top.$1.subject} dersinde şube ortalamasının belirgin üzerindesin (+%${_pct(top.$2)}).',
          'En parlak dersin ${top.$1.subject}: şubeden %${_pct(top.$2)} puan önde.',
        ]));
      }
      if (low.$2 <= -0.10) {
        add(3, 'sub_low', pick('sl', [
          '${low.$1.subject} dersinde şubenin %${_pct(-low.$2)} puan gerisindesin; öncelik bu derse.',
          'Şubeye göre en çok ${low.$1.subject} dersinde geridesin; bu ders için ek tekrar planla.',
        ]));
      }
    }

    // ── Genel seviye motivasyonu ──
    if (overall >= 0.80) {
      add(5, 'level', pick('lv_hi', [
        'Çok güçlü bir performans; şimdi zor ve yeni nesil sorularla kendini sına.',
        'Üst seviyedesin. Hedefin artık küçük dikkat hatalarını sıfırlamak olsun.',
      ]));
    } else if (overall < 0.40) {
      add(5, 'level', pick('lv_lo', [
        'Temel konularda sağlam bir tekrar başlangıçtır; her gün kısa ama düzenli çalışmak büyük fark yaratır.',
        'Henüz yolun başındasın; önce kolay ve orta soruları doğru yapmaya odaklan.',
      ]));
    }

    // ── Seçim: öncelik sırası, gruptan tek madde, en fazla 6 madde ──
    final ordered = [...c]..sort((a, b) {
        final r = a.$1.compareTo(b.$1);
        return r != 0 ? r : _hash('$seed|${a.$2}').compareTo(_hash('$seed|${b.$2}'));
      });
    final used = <String>{};
    final out = <String>[];
    // '+' olumlu, '!' dikkat edilecek madde (PDF'te renk için).
    String mark(({int p, String t}) e) => '${e.p >= 4 ? '+' : '!'}${e.t}';
    for (final e in ordered) {
      if (out.length >= 8) break;
      if (used.add(e.$2)) out.add(mark((p: e.$1, t: e.$3)));
    }
    // Düşük öncelikli olumlu notlardan en az biri yer alsın.
    final hasPositive = out.any((t) => t.startsWith('+'));
    if (!hasPositive && out.isNotEmpty) {
      for (final e in ordered) {
        if (e.$1 >= 4 && !used.contains(e.$2)) {
          out[out.length - 1] = mark((p: e.$1, t: e.$3));
          break;
        }
      }
    }
    return out;
  }

  // ───────────────────────── ANALİZ ─────────────────────────

  static StudentReport analyze({
    required OdakClassGroup branchGroup,
    required OdakExamResult result,
    required List<String> subjects,
    required Map<String, Map<String, List<String>>> outcomes,
    required int weeks,
    bool withPlan = true,

    /// Şubenin okul ders programı: gün adı -> o gün işlenen dersler (sırayla).
    /// Verilirse tekrar oturumları o gün okulda görülen dersten seçilir.
    Map<String, List<String>>? schoolDays,
  }) {
    final subs = <StudentSubjectReport>[];
    var tc = 0, tw = 0, te = 0;

    for (final subject in sortSubjects(subjects)) {
      final stat = result.subjects[subject] ??
          const OdakSubjectStat(correct: 0, wrong: 0, empty: 0, net: 0);
      tc += stat.correct;
      tw += stat.wrong;
      te += stat.empty;

      // Şube ortalaması
      var sum = 0.0;
      for (final s in branchGroup.students) {
        sum += s.result.subjects[subject]?.successRate ?? 0.0;
      }
      final branchRate =
          branchGroup.students.isEmpty ? 0.0 : sum / branchGroup.students.length;

      // Soru bazlı analiz
      final ans = result.answers[subject] ?? '';
      final ref = result.correctAnswers[subject] ?? '';
      final wrongQ = <int>[];
      final emptyQ = <int>[];
      final byOutcome = <String, StudentOutcomeResult>{};
      for (var i = 0; i < ref.length; i++) {
        final refChar = ref[i].toUpperCase();
        if (refChar == 'S' || refChar == 'X' || refChar == '#') continue;
        final sChar = i < ans.length ? ans[i] : ' ';
        final status = TrialExam.evaluateAnswer(sChar, refChar);
        final label = _outcomeFor(outcomes, result, subject, i);
        final o = label.isEmpty
            ? null
            : byOutcome.putIfAbsent(label, () => StudentOutcomeResult(label));
        o?.total++;
        switch (status) {
          case AnswerStatus.correct:
            o?.correct++;
            break;
          case AnswerStatus.wrong:
            o?.wrong++;
            wrongQ.add(i + 1);
            break;
          case AnswerStatus.empty:
            o?.empty++;
            emptyQ.add(i + 1);
            break;
        }
      }
      final oList = byOutcome.values.toList()
        ..sort((a, b) {
          final c = a.rate.compareTo(b.rate);
          return c != 0 ? c : b.total.compareTo(a.total);
        });
      subs.add(StudentSubjectReport(
        subject: subject,
        stat: stat,
        branchRate: branchRate,
        outcomes: oList,
        wrongQuestions: wrongQ,
        emptyQuestions: emptyQ,
      ));
    }

    final overall = subs.isEmpty
        ? 0.0
        : subs.fold(0.0, (a, s) => a + s.rate) / subs.length;
    final branchOverall = subs.isEmpty
        ? 0.0
        : subs.fold(0.0, (a, s) => a + s.branchRate) / subs.length;

    // Güçlü yönler
    final strengths = <String>[];
    final sortedBest = [...subs]..sort((a, b) => b.rate.compareTo(a.rate));
    for (final s in sortedBest.where((s) => s.rate >= 0.60).take(2)) {
      strengths.add('${s.subject}: %${(s.rate * 100).round()} başarı (${level(s.rate)}).');
    }
    final fullOutcomes = <String>[];
    for (final s in subs) {
      for (final o in s.outcomes) {
        if (o.total >= 2 && o.rate >= 1.0) {
          fullOutcomes.add('${s.subject} • ${o.label}');
        }
      }
    }
    for (final f in fullOutcomes.take(3)) {
      strengths.add('Tam hakimiyet: $f');
    }
    if (strengths.isEmpty) {
      strengths.add('Her sınav yeni bir fırsat: doğru yaptığın sorular üzerine inşa edeceğiz.');
    }

    // Geliştirilecek alanlar
    final focus = <String>[];
    final sortedWorst = [...subs]..sort((a, b) => a.rate.compareTo(b.rate));
    for (final s in sortedWorst.where((s) => s.rate < 0.70).take(2)) {
      focus.add('${s.subject}: %${(s.rate * 100).round()} başarı (${level(s.rate)}).');
    }
    // Kazanımlar ÖNCELİK PUANINA göre (kaybedilen soru × düzeltilmiş kayıp oranı):
    // 4 sorudan 2'sini kaçırmak, 1 sorudan 1'ini kaçırmaktan daha önceliklidir.
    final weakOutcomes = <(int, String, StudentOutcomeResult)>[];
    var wi = 0;
    for (final s in subs) {
      for (final o in priorityOutcomes(s)) {
        if (o.rate < 0.5 || o.wrong + o.empty >= 2) {
          weakOutcomes.add((wi++, s.subject, o));
        }
      }
    }
    weakOutcomes.sort((a, b) {
      final c = outcomePriority(b.$3).compareTo(outcomePriority(a.$3));
      if (c != 0) return c;
      final t = b.$3.total.compareTo(a.$3.total);
      return t != 0 ? t : a.$1.compareTo(b.$1);
    });
    for (final w in weakOutcomes.take(5)) {
      focus.add('${w.$2} • ${w.$3.label} '
          '(${w.$3.correct}/${w.$3.total} doğru)');
    }
    if (focus.isEmpty) {
      focus.add('Belirgin bir zayıf alan yok; hız ve zor soru çalışmasıyla seviyeni yükselt.');
    }

    // Sınav davranışı
    final habits = _buildHabits(
      seed: result.student.id,
      subs: subs,
      tc: tc,
      tw: tw,
      te: te,
      overall: overall,
      branchOverall: branchOverall,
    );

    // Hedefler
    final f = (0.10 + 0.08 * weeks).clamp(0.15, 0.60).toDouble();
    final goals = [
      for (final s in subs)
        StudentGoal(s.subject, s.rate, (s.rate + (1 - s.rate) * f).clamp(0.0, 1.0).toDouble()),
    ];

    return StudentReport(
      result: result,
      branch: branchGroup.name,
      overallRate: overall,
      branchOverall: branchOverall,
      correct: tc,
      wrong: tw,
      empty: te,
      subjects: subs,
      strengths: strengths,
      focusAreas: focus,
      habits: habits,
      goals: goals,
      plan: withPlan
          ? _plan(
              subs,
              weeks,
              grade: gradeOf(result.student.classLevel) ??
                  gradeOf(result.student.branch) ??
                  gradeOf(branchGroup.id),
              schoolDays: schoolDays,
            )
          : const [],
    );
  }

  // ───────────────────────── ÇALIŞMA PLANI ─────────────────────────

  static const _phaseTitles = [
    'Temel Eksikleri Kapatma',
    'Pekiştirme ve Soru Çözümü',
    'Genel Tekrar ve Pekiştirme',
  ];

  static const _phaseGoals = [
    'En zayıf kazanımlarını konu anlatımıyla yeniden öğrenerek temelini sağlamlaştır.',
    'Öğrendiğin konuları bol soru çözerek pekiştir; yanlışlarını hata defterine yaz.',
    'Tüm konuları hızlıca tekrar et, çözemediğin soruların çözümünü öğren ve eksiklerini kapat.',
  ];

  static const _days = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
  ];

  /// "8", "8. Sınıf", "8-A", "8/B", "704" (şube kodu) gibi metinlerden sınıf
  /// düzeyini çıkarır. Bulunamazsa null döner.
  static int? gradeOf(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    // "704" -> 7, "1203" -> 12 (seviye + 2 haneli şube numarası).
    final code = RegExp(r'^(\d{1,2})(\d{2})(?!\d)').firstMatch(t);
    final raw = code != null
        ? code.group(1)
        : RegExp(r'\d{1,2}').firstMatch(t)?.group(0);
    final g = raw == null ? null : int.tryParse(raw);
    return (g == null || g < 1 || g > 12) ? null : g;
  }

  /// Sınıf düzeyine göre (ana oturum, tekrar oturumu) süreleri (dk).
  /// 5 ve altı: 30/20 • 6: 40/20 • 7: 40/30 • 8 ve üstü: 60/30.
  /// Sınıf bilinmiyorsa varsayılan 60/40.
  static (int, int) sessionMinutes(int? grade) {
    if (grade == null) return (60, 40);
    if (grade <= 5) return (30, 20);
    if (grade == 6) return (40, 20);
    if (grade == 7) return (40, 30);
    return (60, 30);
  }

  /// Pazar haftalık genel tekrar süresi (dk). En az 120.
  /// 5 ve altı: 120 • 6: 130 • 7: 140 • 8 ve üstü (ve bilinmeyen): 150.
  static int sundayMinutes(int? grade) {
    if (grade == null) return 150;
    if (grade <= 5) return 120;
    if (grade == 6) return 130;
    if (grade == 7) return 140;
    return 150;
  }

  /// Bir soruya ayrılan ortalama süre (dk), sınıf düzeyine göre.
  static double minutesPerQuestion(int? grade) {
    if (grade == null) return 2.0;
    if (grade <= 5) return 2.5;
    if (grade == 6) return 2.25;
    if (grade == 7) return 2.0;
    return 1.75;
  }

  /// LGS katsayısı: Türkçe, Matematik, Fen = 4; diğerleri = 1 (hiçbiri 0 değil).
  /// YALNIZCA başarı yüzdeleri eşit olduğunda sıralamayı belirler.
  static int lgsWeight(String subject) {
    final r = subjectRank(subject);
    return (r == 0 || r == 4 || r == 5) ? 4 : 1;
  }

  /// Plan sırası (zayıftan güçlüye): önce başarı yüzdesi (tam sayı %),
  /// eşitse LGS katsayısı yüksek olan, o da eşitse sınav sırası.
  static List<StudentSubjectReport> planOrder(List<StudentSubjectReport> subs) {
    final idx = {for (var i = 0; i < subs.length; i++) subs[i].subject: i};
    return [...subs]
      ..sort((a, b) {
        final c = _pct(a.rate).compareTo(_pct(b.rate));
        if (c != 0) return c;
        final k = lgsWeight(b.subject).compareTo(lgsWeight(a.subject));
        if (k != 0) return k;
        return idx[a.subject]!.compareTo(idx[b.subject]!);
      });
  }

  // ── Kazanım önceliği ──

  /// Kazanım öncelik puanı = kaybedilen soru × düzeltilmiş kayıp oranı.
  /// kayıp = yanlış + boş, oran = (kayıp + 1) / (soru + 2).
  /// Düzeltme, tek soruluk kazanımlara aşırı tepki verilmesini önler.
  /// Örnekler: 3/3 kayıp → 2,40 • 4'te 2 kayıp → 1,00 • 1/1 kayıp → 0,67 •
  /// 4'te 1 kayıp → 0,33.
  static double outcomePriority(StudentOutcomeResult o) {
    final missed = o.wrong + o.empty;
    if (missed == 0) return 0;
    return missed * (missed + 1) / (o.total + 2);
  }

  /// Çalışılacak kazanımlar: en az bir sorusu kaçırılmış olanlar, öncelik
  /// puanına göre azalan (eşitlikte soru sayısı fazla olan, sonra sınav sırası).
  static List<StudentOutcomeResult> priorityOutcomes(StudentSubjectReport s) {
    final idx = {for (var i = 0; i < s.outcomes.length; i++) s.outcomes[i].label: i};
    return s.outcomes.where((o) => o.wrong + o.empty > 0).toList()
      ..sort((a, b) {
        final c = outcomePriority(b).compareTo(outcomePriority(a));
        if (c != 0) return c;
        final t = b.total.compareTo(a.total);
        if (t != 0) return t;
        return idx[a.label]!.compareTo(idx[b.label]!);
      });
  }

  /// Öncelik puanına göre plandaki tekrar sayısı (1..3).
  static int _repeatOf(double p) => p >= 2.0 ? 3 : (p >= 1.0 ? 2 : 1);

  /// Kazanım döngüsü: yüksek öncelikli kazanımlar daha sık çıkar ama art arda
  /// gelmez (yumuşak ağırlıklı sıralı dağıtım; deterministik).
  static List<StudentOutcomeResult> _rotation(List<StudentOutcomeResult> list) {
    if (list.isEmpty) return const [];
    final w = [for (final o in list) _repeatOf(outcomePriority(o))];
    final total = w.fold(0, (a, b) => a + b);
    final cur = List<int>.filled(list.length, 0);
    final out = <StudentOutcomeResult>[];
    for (var step = 0; step < total; step++) {
      var best = 0;
      for (var i = 0; i < list.length; i++) {
        cur[i] += w[i];
        if (cur[i] > cur[best]) best = i;
      }
      cur[best] -= total;
      out.add(list[best]);
    }
    return out;
  }

  // ── Görev metinleri ──

  /// Hata türü: 'empty' (boş ağırlıklı → konu eksiği), 'wrong' (yanlış
  /// ağırlıklı → dikkat / yanlış öğrenme), 'mixed' veya 'none'.
  static String _errorType(int wrong, int empty) {
    if (wrong + empty == 0) return 'none';
    if (empty > wrong) return 'empty';
    if (wrong > empty) return 'wrong';
    return 'mixed';
  }

  static int _round5(double v) => (v / 5).round() * 5;

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Ana oturum görevi. Konu süresi / soru sayısı; sınıf düzeyi (süre ve soru
  /// başına dakika), başarı (zayıf → daha çok konu, az soru; güçlü → çok soru),
  /// evre ve hata türüne göre hesaplanır.
  static String _mainTask({
    required int phase,
    required int minutes,
    required double mpq,
    required StudentSubjectReport s,
    StudentOutcomeResult? target,
  }) {
    // Hakimiyet: kazanım sonucu ders başarısıyla yumuşatılır (az soruda aşırı tepki olmasın).
    final mastery = target == null
        ? s.rate
        : (target.correct + 2 * s.rate) / (target.total + 2);
    final err = (target != null && target.wrong + target.empty > 0)
        ? _errorType(target.wrong, target.empty)
        : _errorType(s.stat.wrong, s.stat.empty);

    var topic = mastery < 0.40 ? 0.50 : (mastery < 0.70 ? 0.30 : 0.10);
    if (phase == 0) topic += 0.10;
    if (phase == 1) topic -= 0.10;
    if (err == 'empty') topic += 0.10;
    if (err == 'wrong') topic -= 0.05;
    topic = topic.clamp(0.05, phase == 2 ? 0.40 : 0.60).toDouble();
    final analysis = err == 'wrong' ? 0.15 : 0.0;

    final topicMin = _round5(minutes * topic);
    final analysisMin = _round5(minutes * analysis);
    final qMin = (minutes - topicMin - analysisMin)
        .clamp(minutes * 0.3, minutes.toDouble())
        .toDouble();
    final q0 = (qMin / mpq).round();
    final q = q0 < 4 ? 4 : q0;

    final head = target == null
        ? (phase == 0
            ? 'Karma soru çözümü'
            : phase == 1
                ? 'Zor soru çalışması'
                : 'Genel tekrar')
        : '${phase == 0 ? 'Kazanım' : phase == 1 ? 'Pekiştirme' : 'Genel tekrar'}: '
            '«${target.label}»';

    final parts = <String>[];
    if (topicMin >= 5) {
      if (phase == 2) {
        parts.add('kısa özet çıkar ($topicMin dk)');
      } else if (err == 'empty') {
        parts.add('konu anlatımını ders kitabından / videodan çalış ($topicMin dk)');
      } else {
        parts.add('konu özetini oku ($topicMin dk)');
      }
    }
    if (mastery < 0.40 && phase != 2) {
      parts.add('2 çözümlü örneği adım adım incele');
    }
    parts.add('$q soru çöz');
    switch (err) {
      case 'wrong':
        parts.add('yanlışlarını hata defterine yaz, soru kökünü yeniden okuyup '
            'hatanın nedenini not et${analysisMin >= 5 ? ' ($analysisMin dk)' : ''}');
        break;
      case 'empty':
        parts.add('boş bıraktığın soru tiplerini işaretle ve çözümlerini öğren');
        break;
      default:
        parts.add('yanlışlarını işaretle');
    }
    return '$head. ${_cap(parts.join(', '))}.';
  }

  /// Tekrar (ek) oturumu görevi: kazanıma değil, dersin genel tekrarına yöneliktir.
  static String _reviewTask({
    required int minutes,
    required double mpq,
    required bool fromSchool,
  }) {
    final noteMin = _round5(minutes * 0.3);
    final q0 = ((minutes - noteMin) / mpq).round();
    final q = q0 < 3 ? 3 : q0;
    if (fromSchool) {
      return 'Tekrar (bugün okulda işlendi): Derste işlenen konunun notlarını '
          'gözden geçir ($noteMin dk), aynı konudan $q soru çöz.';
    }
    return 'Tekrar: Önceki konuların notlarına göz at ($noteMin dk), '
        '$q karışık soru çöz.';
  }

  /// Okul ders adı ile sınav dersi aynı ders mi? ("T.C. İnkılap Tarihi ve
  /// Atatürkçülük" ↔ "İnkılap Tarihi", "Fen Bilimleri" ↔ "Fen" ...)
  static bool subjectMatchesLesson(String subject, String lesson) {
    final a = subjectRank(subject), b = subjectRank(lesson);
    if (a != 99 || b != 99) return a == b;
    final x = _fold(subject).replaceAll(RegExp(r'[^a-z0-9]'), '');
    final y = _fold(lesson).replaceAll(RegExp(r'[^a-z0-9]'), '');
    return x.isNotEmpty && y.isNotEmpty && (x == y || x.contains(y) || y.contains(x));
  }

  static List<StudyWeek> _plan(
    List<StudentSubjectReport> subs,
    int weeks, {
    int? grade,
    Map<String, List<String>>? schoolDays,
  }) {
    if (subs.isEmpty || weeks < 1) return [];
    final (mainMin, extraMin) = sessionMinutes(grade);
    final sundayMin = sundayMinutes(grade);
    final mpq = minutesPerQuestion(grade);
    final order = planOrder(subs);
    final n = order.length;

    // Haftalık 6 ana oturum: zayıf derse daha fazla (başarı yüzdesine göre).
    final weights = [for (final s in order) (1 - s.rate) + 0.2];
    final sum = weights.fold(0.0, (a, b) => a + b);
    final quota = [for (final w in weights) w / sum * 6];
    final slots = [for (final q in quota) q.floor()];
    var left = 6 - slots.fold(0, (a, b) => a + b);
    // Kalan oturumlar: kesir büyük olana; eşitse LGS katsayısı, sonra sıra.
    final byRem = List<int>.generate(n, (i) => i)
      ..sort((a, b) {
        final ra = quota[a] - quota[a].floor();
        final rb = quota[b] - quota[b].floor();
        if ((ra - rb).abs() > 1e-9) return rb.compareTo(ra);
        final k = lgsWeight(order[b].subject).compareTo(lgsWeight(order[a].subject));
        return k != 0 ? k : a.compareTo(b);
      });
    var k = 0;
    while (left > 0) {
      slots[byRem[k % n]]++;
      left--;
      k++;
    }
    final seq = <int>[];
    final rem = [...slots];
    while (seq.length < 6) {
      for (var i = 0; i < n && seq.length < 6; i++) {
        if (rem[i] > 0) {
          seq.add(i);
          rem[i]--;
        }
      }
    }

    // Her ders için kazanım döngüsü (öncelik puanına göre, tekrarlı).
    final rotations = [for (final s in order) _rotation(priorityOutcomes(s))];
    final used = List<int>.filled(n, 0);

    // Okul programı: her gün (Pzt..Cmt) o gün işlenen sınav dersleri (sırayla).
    final schoolByDay = List<List<int>>.generate(6, (_) => <int>[]);
    if (schoolDays != null && schoolDays.isNotEmpty) {
      final byFold = {for (final e in schoolDays.entries) _fold(e.key.trim()): e.value};
      for (var d = 0; d < 6; d++) {
        final lessons = byFold[_fold(_days[d])] ?? const <String>[];
        for (final l in lessons) {
          for (var i = 0; i < n; i++) {
            if (subjectMatchesLesson(order[i].subject, l) &&
                !schoolByDay[d].contains(i)) {
              schoolByDay[d].add(i);
            }
          }
        }
      }
    }

    int phaseOf(int w) {
      if (weeks == 1) return 0;
      if (w == weeks - 1) return 2;
      final firstCount = (weeks * 0.4).round().clamp(1, weeks - 1);
      return w < firstCount ? 0 : 1;
    }

    final result = <StudyWeek>[];
    for (var w = 0; w < weeks; w++) {
      final p = phaseOf(w);
      final sessions = <StudySession>[];
      final focusSubjects = <String>[];
      for (var d = 0; d < 6; d++) {
        // Ana oturum: zayıf derse ağırlıklı, öncelikli kazanım.
        final si = seq[(d + w) % 6];
        final subj = order[si].subject;
        if (!focusSubjects.contains(subj)) focusSubjects.add(subj);
        final rot = rotations[si];
        final target = rot.isEmpty ? null : rot[used[si] % rot.length];
        used[si]++;
        sessions.add(StudySession(
          _days[d],
          subj,
          _mainTask(phase: p, minutes: mainMin, mpq: mpq, s: order[si], target: target),
          mainMin,
        ));

        // Tekrar oturumu: ana dersten FARKLI bir ders. Okul programı varsa o gün
        // okulda işlenen derslerden biri (haftaya göre dönüşümlü), yoksa sırayla.
        final cands = [
          for (final i in schoolByDay[d])
            if (n == 1 || i != si) i,
        ];
        final fromSchool = cands.isNotEmpty;
        var ti = fromSchool ? cands[w % cands.length] : (w * 6 + d) % n;
        if (!fromSchool && n > 1 && ti == si) ti = (ti + 1) % n;
        sessions.add(StudySession(
          _days[d],
          order[ti].subject,
          _reviewTask(minutes: extraMin, mpq: mpq, fromSchool: fromSchool),
          extraMin,
          review: true,
          fromSchool: fromSchool,
        ));
      }
      sessions.add(StudySession(
        'Pazar',
        'Tüm dersler',
        'Haftalık genel tekrar: bu haftanın tüm derslerini gözden geçir; hata '
            'defterindeki ve çözemediğin soruların çözümünü öğren, ardından bu '
            'soruları yeniden çöz.',
        sundayMin,
        review: true,
      ));
      result.add(StudyWeek(
        week: w + 1,
        phase: _phaseTitles[p],
        objective: _phaseGoals[p],
        focus: focusSubjects.take(3).join(', '),
        sessions: sessions,
      ));
    }
    return result;
  }

  // ───────────────────────── PDF ─────────────────────────

  static PdfColor _rateColor(double r) {
    if (r >= 0.70) return PdfColors.green700;
    if (r >= 0.50) return PdfColors.orange700;
    return PdfColors.red600;
  }

  static pw.Widget _t(
    String s, {
    bool bold = false,
    double size = 9,
    PdfColor? color,
    pw.TextAlign? align,
  }) =>
      pw.Text(
        s,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColors.grey900,
        ),
      );

  static pw.Widget _cell(
    String s, {
    bool bold = false,
    double size = 8.5,
    PdfColor? color,
    pw.TextAlign? align,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
        child: _t(s, bold: bold, size: size, color: color, align: align),
      );

  static pw.Widget _bar(double rate, {double width = 70}) {
    final p = (rate * 100).round().clamp(0, 100);
    final color = _rateColor(rate);
    return pw.Container(
      width: width,
      height: 6,
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Row(
        children: [
          if (p > 0)
            pw.Expanded(
              flex: p,
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: pw.BorderRadius.circular(3),
                ),
              ),
            ),
          if (p < 100) pw.Expanded(flex: 100 - p, child: pw.SizedBox()),
        ],
      ),
    );
  }

  static pw.Widget _h(String s, {PdfColor color = PdfColors.indigo700}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
        child: pw.Row(
          children: [
            pw.Container(width: 4, height: 14, color: color),
            pw.SizedBox(width: 6),
            _t(s, bold: true, size: 12.5, color: color),
          ],
        ),
      );

  static pw.Widget _kpi(String label, String value, {PdfColor? color}) =>
      pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: pw.BoxDecoration(
            color: PdfColors.indigo50,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            children: [
              _t(value, bold: true, size: 17, color: color ?? PdfColors.indigo800),
              pw.SizedBox(height: 2),
              _t(label, size: 7.5, color: PdfColors.grey700, align: pw.TextAlign.center),
            ],
          ),
        ),
      );

  /// Uzun kazanım metinlerini kısaltır (tek sayfaya sığdırmak için).
  static String _cut(String s, [int max = 70]) =>
      s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}...';

  static pw.Widget _bullets(List<String> items, PdfColor dot,
          {double size = 8.8, double gap = 3}) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final i in items)
            pw.Padding(
              padding: pw.EdgeInsets.only(bottom: gap),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 3, right: 5),
                    child: pw.Container(
                      width: 4,
                      height: 4,
                      decoration: pw.BoxDecoration(color: dot, shape: pw.BoxShape.circle),
                    ),
                  ),
                  pw.Expanded(child: _t(i, size: size)),
                ],
              ),
            ),
        ],
      );

  static pw.Widget _box(String title, List<String> items, PdfColor bg, PdfColor fg) =>
      pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          padding: const pw.EdgeInsets.all(9),
          decoration: pw.BoxDecoration(
            color: bg,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _t(title, bold: true, size: 10, color: fg),
              pw.SizedBox(height: 5),
              _bullets(items, fg),
            ],
          ),
        ),
      );

  static String _numbers(List<int> l) => l.isEmpty ? '-' : l.join(', ');

  /// Plan açıklaması: süreler sınıf düzeyine göre değiştiği için plandan okunur.
  static String _planIntro(StudentReport r) {
    if (r.plan.isEmpty) return '';
    final ss = r.plan.first.sessions;
    int minOf(bool Function(StudySession) f, int def) {
      for (final s in ss) {
        if (f(s)) return s.minutes;
      }
      return def;
    }

    final mainMin = minOf((s) => !s.review, 0);
    final revMin = minOf((s) => s.review && s.day != 'Pazar', 0);
    final sunMin = minOf((s) => s.day == 'Pazar', 0);
    final school = r.plan.any((w) => w.sessions.any((s) => s.fromSchool));
    final hours = (r.plan.first.totalMinutes / 60).toStringAsFixed(1);
    return 'Plan: her gün bir ana çalışma oturumu ($mainMin dk; en çok soru '
        'kaybettiğin kazanımlar önce) ve farklı bir dersten tekrar oturumu '
        '($revMin dk${school ? '; mümkün olan günlerde o gün okulda işlenen ders' : ''}). '
        'Pazar günü tüm derslerin haftalık genel tekrarı ve çözemediğin soruların '
        'çözümü ($sunMin dk). Haftalık yaklaşık $hours saat. '
        'Her hafta AYRI bir sayfada; öğretmenlerinle bölüm bölüm paylaşabilirsin.';
  }

  /// Sınav sonucuna göre kişiselleştirilmiş yorumlar (plan öncesi sayfa).
  static List<pw.Widget> _comments(StudentReport r, String first, int weeks) {
    final out = <pw.Widget>[];
    final diff = ((r.overallRate - r.branchOverall) * 100).round();
    final pos = diff >= 5
        ? 'şube ortalamasının $diff puan üzerinde'
        : diff <= -5
            ? 'şube ortalamasının ${-diff} puan altında'
            : 'şube ortalamasına çok yakın';
    out.add(_t(
      '$first, bu sınavda genel başarın %${(r.overallRate * 100).round()} ve $pos. '
      'Aşağıda her dersteki sonuçlarını tek tek yorumladım; $weeks haftalık planın '
      'bu yorumlara göre hazırlandı.',
      size: 9.5,
    ));

    final counts = <String, int>{};
    final reviewCounts = <String, int>{};
    if (r.plan.isNotEmpty) {
      for (final s in r.plan.first.sessions) {
        if (s.day == 'Pazar') continue;
        final m = s.review ? reviewCounts : counts;
        m[s.subject] = (m[s.subject] ?? 0) + 1;
      }
    }

    final ordered = planOrder(r.subjects);
    for (final s in ordered) {
      final lines = <String>[];
      final rate = (s.rate * 100).round();
      final br = (s.branchRate * 100).round();
      final String levelText;
      if (s.rate >= 0.85) {
        levelText = 'Bu derste çok iyisin; amacın seviyeni korumak ve zor sorularda hata yapmamak.';
      } else if (s.rate >= 0.70) {
        levelText = 'Bu derste iyisin; birkaç kazanımı pekiştirince üst seviyeye çıkabilirsin.';
      } else if (s.rate >= 0.50) {
        levelText = 'Orta düzeydesin; temel kavramları oturtup soru çözümünü artırırsan hızla yükselebilirsin.';
      } else if (s.rate >= 0.30) {
        levelText = 'Bu ders şu an geliştirmen gereken alanlardan; temel konulara dönmek en verimli yol.';
      } else {
        levelText = 'Bu ders öncelikli çalışma alanın; konuları baştan, adım adım ve bol örnekle tekrar etmelisin.';
      }
      lines.add('Başarın %$rate (şube ortalaması %$br). $levelText');

      final c = s.stat.correct, w = s.stat.wrong, e = s.stat.empty;
      if (w + e == 0) {
        lines.add('Tüm soruları doğru yaptın, tebrikler.');
      } else if (e > w) {
        lines.add('$c doğru, $w yanlış, $e boş: boş sayın yanlışlarından fazla. Bu '
            'genellikle konu eksiğine ya da özgüven eksikliğine işaret eder; '
            'öğrendikçe boş bıraktığın soruları denemeye başla.');
      } else if (w >= 3 && w >= 2 * e) {
        lines.add('$c doğru, $w yanlış, $e boş: yanlış sayın boşlarından belirgin fazla. '
            'Acele, dikkatsizlik ya da yanlış öğrenilmiş bilgi olabilir; soruyu dikkatle '
            'oku ve işlem kontrolü yap.');
      } else {
        lines.add('$c doğru, $w yanlış, $e boş: yanıt dağılımın dengeli.');
      }

      final weak = priorityOutcomes(s).take(2).toList();
      if (weak.isNotEmpty) {
        final txt = weak
            .map((o) => '«${_cut(o.label)}» (${o.correct}/${o.total})')
            .join(' ve ');
        lines.add('En çok soru kaybettiğin kazanımlar $txt; planda bu kazanımlara '
            'öncelik verildi.');
      }
      final strong = s.outcomes.where((o) => o.total >= 2 && o.rate >= 1.0).toList();
      if (strong.isNotEmpty) {
        lines.add('Buna karşılık «${_cut(strong.first.label)}» kazanımında tam hakimiyetin var.');
      }
      final cnt = counts[s.subject] ?? 0;
      final rcnt = reviewCounts[s.subject] ?? 0;
      if (cnt > 0 || rcnt > 0) {
        lines.add('Planda bu derse haftada '
            '${[if (cnt > 0) '$cnt çalışma oturumu', if (rcnt > 0) '$rcnt tekrar oturumu'].join(' ve ')}'
            ' ayrıldı.');
      }

      out.add(pw.Container(
        margin: const pw.EdgeInsets.only(top: 6),
        padding: const pw.EdgeInsets.all(7),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _t(s.subject, bold: true, size: 10.5, color: PdfColors.indigo800),
                _t(level(s.rate),
                    bold: true, size: 9.5, color: _rateColor(s.rate)),
              ],
            ),
            pw.SizedBox(height: 4),
            _bullets(lines, PdfColors.indigo700, size: 8.2, gap: 1.5),
          ],
        ),
      ));
    }
    return out;
  }

  /// 'Hedeflerin' bölümü (çalışma planı seçiliyse son sayfada gösterilir).
  static List<pw.Widget> _goalsSection(StudentReport r, int weeks) => [
        pw.SizedBox(height: 10),
        _h('Hedeflerin', color: PdfColors.teal700),
        _t(
          '$weeks haftalık planı düzenli uygularsan ulaşmayı hedeflediğin başarı oranları:',
          size: 8.8,
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.4),
            bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FixedColumnWidth(70),
            2: const pw.FixedColumnWidth(70),
            3: const pw.FixedColumnWidth(120),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.teal50),
              children: [
                _cell('Ders', bold: true),
                _cell('Şu an', bold: true, align: pw.TextAlign.center),
                _cell('Hedef', bold: true, align: pw.TextAlign.center),
                _cell('Hedef çizgisi', bold: true),
              ],
            ),
            for (final g in r.goals)
              pw.TableRow(
                children: [
                  _cell(g.subject, bold: true),
                  _cell('%${(g.current * 100).round()}', align: pw.TextAlign.center),
                  _cell('%${(g.target * 100).round()}',
                      bold: true,
                      color: PdfColors.teal700,
                      align: pw.TextAlign.center),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: _bar(g.target, width: 100),
                  ),
                ],
              ),
          ],
        ),
      ];

  static pw.Widget _legend(String label, PdfColor color) => pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: 7,
            height: 7,
            decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
          ),
          pw.SizedBox(width: 3),
          _t(label, size: 8),
        ],
      );

  /// Zengin 'Sınav Alışkanlıkların' bölümü: cevap dağılımı çubuğu, davranış
  /// göstergeleri ve renkli alışkanlık kartları (ilk sayfayı doldurur).
  static List<pw.Widget> _habitsSection(StudentReport r) {
    final total = r.correct + r.wrong + r.empty;
    if (total == 0) return [];
    final attempted = r.correct + r.wrong;
    final answerRate = attempted / total;
    final acc = attempted == 0 ? 0.0 : r.correct / attempted;
    final netSum = r.subjects.fold<double>(0, (a, s) => a + s.stat.net);
    final lostRaw = r.correct - netSum;
    final lost = lostRaw < 0 ? 0.0 : lostRaw;
    int pct(int v) => (v * 100 / total).round();

    pw.Widget seg(int v, PdfColor c) => v <= 0
        ? pw.SizedBox()
        : pw.Expanded(flex: v, child: pw.Container(height: 11, color: c));

    final cards = <pw.Widget>[];
    for (var i = 0; i < r.habits.length && i < 6; i++) {
      final raw = r.habits[i];
      final positive = raw.startsWith('+');
      final text = raw.isNotEmpty && (raw[0] == '+' || raw[0] == '!')
          ? raw.substring(1)
          : raw;
      final accent = positive ? PdfColors.green600 : PdfColors.deepPurple600;
      cards.add(pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 3.5),
        padding: const pw.EdgeInsets.fromLTRB(8, 4.5, 8, 4.5),
        decoration: pw.BoxDecoration(
          color: positive ? PdfColors.green50 : PdfColors.deepPurple50,
          border: pw.Border(left: pw.BorderSide(color: accent, width: 3)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 14,
              child: _t(positive ? '+' : '!', bold: true, size: 9.5, color: accent),
            ),
            pw.Expanded(child: _t(text, size: 8.4)),
          ],
        ),
      ));
    }

    return [
      _h('Sınav Alışkanlıkların', color: PdfColors.deepPurple600),
      pw.ClipRRect(
        horizontalRadius: 5,
        verticalRadius: 5,
        child: pw.Row(children: [
          seg(r.correct, PdfColors.green600),
          seg(r.wrong, PdfColors.red500),
          seg(r.empty, PdfColors.orange400),
        ]),
      ),
      pw.SizedBox(height: 4),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _legend('Doğru ${r.correct} (%${pct(r.correct)})', PdfColors.green600),
          _legend('Yanlış ${r.wrong} (%${pct(r.wrong)})', PdfColors.red500),
          _legend('Boş ${r.empty} (%${pct(r.empty)})', PdfColors.orange400),
          _t('Toplam $total soru', size: 8, color: PdfColors.grey700),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Row(
        children: [
          _kpi('Cevaplama Oranı', '%${(answerRate * 100).round()}',
              color: answerRate >= 0.9 ? PdfColors.green700 : PdfColors.orange700),
          _kpi('İsabet Oranı', '%${(acc * 100).round()}',
              color: _rateColor(acc)),
          _kpi('Yanlışla Giden Net', lost.toStringAsFixed(1),
              color: lost >= 3 ? PdfColors.red600 : PdfColors.green700),
          _kpi('Toplam Net', netSum.toStringAsFixed(1)),
        ],
      ),
      pw.SizedBox(height: 7),
      ...cards,
    ];
  }

  static Future<Uint8List> buildPdf({
    required List<StudentReport> reports,
    required String examName,
    String? schoolName,
    required int weeks,
    bool withPlan = true,
    String brand = 'Performans Özeti',
  }) async {
    final font = await PdfGoogleFonts.robotoRegular();
    final bold = await PdfGoogleFonts.robotoBold();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: bold),
      title: '$brand - Öğrenci Raporu',
    );
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

    for (final r in reports) {
      final first = r.name.trim().split(' ').first;
      pw.Widget footerW() => pw.Container(
            padding: const pw.EdgeInsets.only(top: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _t('$brand  -  $examName', size: 7, color: PdfColors.grey600),
                _t('${r.name}  -  $dateStr', size: 7, color: PdfColors.grey600),
              ],
            ),
          );
      // 1. SAYFA: içerik uzunluğuna göre otomatik ölçeklenir; asla taşmaz.
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 30),
          build: (ctx) => pw.Column(children: [
            pw.Expanded(
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                alignment: pw.Alignment.topLeft,
                child: pw.SizedBox(
                  width: 539,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
            // Başlık (tam genişlik, alçak)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: pw.BoxDecoration(
                gradient: const pw.LinearGradient(
                  colors: [PdfColors.indigo700, PdfColors.deepPurple400],
                ),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _t(r.name, size: 17, bold: true, color: PdfColors.white),
                        pw.SizedBox(height: 2),
                        _t(
                          '${r.branch}  |  ${r.bookletLabel}  |  $examName'
                          '${schoolName == null || schoolName.isEmpty ? '' : '  |  $schoolName'}',
                          size: 8.5,
                          color: PdfColors.indigo100,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _t('KİŞİSEL PERFORMANS ÖZETİ',
                          size: 8, color: PdfColors.indigo100, bold: true),
                      pw.SizedBox(height: 2),
                      _t('Rapor tarihi: $dateStr', size: 8, color: PdfColors.indigo100),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            _t(
              'Merhaba $first, bu rapor $examName sınavındaki sonuçlarını ders ve '
              'kazanım bazında inceler; güçlü yönlerini ve geliştirmen gereken alanları '
              '${withPlan ? 've sana özel $weeks haftalık çalışma planını ' : ''}içerir.',
              size: 9.5,
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                _kpi('Genel Başarın', '%${(r.overallRate * 100).round()}',
                    color: _rateColor(r.overallRate)),
                _kpi('Doğru', '${r.correct}', color: PdfColors.green700),
                _kpi('Yanlış', '${r.wrong}', color: PdfColors.red600),
                _kpi('Boş', '${r.empty}', color: PdfColors.orange700),
                _kpi('Şube Ortalaması', '%${(r.branchOverall * 100).round()}'),
              ],
            ),

            // Ders tablosu
            _h('Derslere Göre Durumun'),
            pw.Table(
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.4),
                bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.2),
                1: const pw.FixedColumnWidth(28),
                2: const pw.FixedColumnWidth(28),
                3: const pw.FixedColumnWidth(28),
                4: const pw.FixedColumnWidth(38),
                5: const pw.FixedColumnWidth(100),
                6: const pw.FixedColumnWidth(44),
                7: const pw.FixedColumnWidth(62),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.indigo100),
                  children: [
                    _cell('Ders', bold: true),
                    _cell('D', bold: true, align: pw.TextAlign.center),
                    _cell('Y', bold: true, align: pw.TextAlign.center),
                    _cell('B', bold: true, align: pw.TextAlign.center),
                    _cell('Net', bold: true, align: pw.TextAlign.center),
                    _cell('Başarı', bold: true),
                    _cell('Şube', bold: true, align: pw.TextAlign.center),
                    _cell('Durum', bold: true),
                  ],
                ),
                for (final s in r.subjects)
                  pw.TableRow(
                    children: [
                      _cell(s.subject, bold: true),
                      _cell('${s.stat.correct}', align: pw.TextAlign.center),
                      _cell('${s.stat.wrong}', align: pw.TextAlign.center),
                      _cell('${s.stat.empty}', align: pw.TextAlign.center),
                      _cell(s.stat.net.toStringAsFixed(1), align: pw.TextAlign.center),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: pw.Row(
                          children: [
                            _bar(s.rate, width: 58),
                            pw.SizedBox(width: 4),
                            _t('%${(s.rate * 100).round()}',
                                size: 8, bold: true, color: _rateColor(s.rate)),
                          ],
                        ),
                      ),
                      _cell('%${(s.branchRate * 100).round()}',
                          align: pw.TextAlign.center, color: PdfColors.grey700),
                      _cell(level(s.rate), bold: true, color: _rateColor(s.rate)),
                    ],
                  ),
              ],
            ),

            // Güçlü / geliştirilecek
            pw.SizedBox(height: 12),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _box('Güçlü Yönlerin', r.strengths, PdfColors.green50, PdfColors.green800),
                _box('Geliştirmen Gereken Alanlar', r.focusAreas, PdfColors.red50,
                    PdfColors.red800),
              ],
            ),
            ..._habitsSection(r),
            ],
                ),
              ),
            ),
            ),
            footerW(),
          ]),
        ),
      );

      // Ders detayları (2. sayfadan başlar)
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 30),
          footer: (ctx) => footerW(),
          build: (ctx) => [
            _h('Ders Ders Ayrıntılar'),
            for (final s in r.subjects) ...[
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 6),
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: PdfColors.indigo50,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _t(s.subject, bold: true, size: 10.5, color: PdfColors.indigo800),
                    _t('%${(s.rate * 100).round()}  -  ${level(s.rate)}',
                        bold: true, size: 9.5, color: _rateColor(s.rate)),
                  ],
                ),
              ),
              pw.SizedBox(height: 3),
              if (s.outcomes.isNotEmpty)
                pw.Table(
                  border: const pw.TableBorder(
                    horizontalInside:
                        pw.BorderSide(color: PdfColors.grey300, width: 0.4),
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(4),
                    1: const pw.FixedColumnWidth(44),
                    2: const pw.FixedColumnWidth(84),
                    3: const pw.FixedColumnWidth(62),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        _cell('Kazanım', bold: true, size: 8, color: PdfColors.grey700),
                        _cell('Doğru', bold: true, size: 8,
                            color: PdfColors.grey700, align: pw.TextAlign.center),
                        _cell('Başarı', bold: true, size: 8, color: PdfColors.grey700),
                        _cell('Durum', bold: true, size: 8, color: PdfColors.grey700),
                      ],
                    ),
                    for (final o in s.outcomes)
                      pw.TableRow(
                        children: [
                          _cell(o.label, size: 8),
                          _cell('${o.correct}/${o.total}',
                              size: 8, align: pw.TextAlign.center),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4.5),
                            child: _bar(o.rate, width: 74),
                          ),
                          _cell(level(o.rate),
                              size: 8, bold: true, color: _rateColor(o.rate)),
                        ],
                      ),
                  ],
                )
              else
                _t('Bu ders için kazanım bilgisi girilmemiş; soru bazlı sonuçların aşağıda.',
                    size: 8, color: PdfColors.grey600),
              pw.SizedBox(height: 3),
              if (r.merged)
                _t(
                    'Yanlış: ${s.wrongQuestions.length} soru, boş: ${s.emptyQuestions.length} soru '
                    '(birleşik değerlendirmede tüm sınavlar toplanır).',
                    size: 8)
              else ...[
                _t('Yanlış yaptığın sorular (${r.bookletLabel} sırasına göre): ${_numbers(s.wrongQuestions)}', size: 8),
                _t('Boş bıraktığın sorular (${r.bookletLabel} sırasına göre): ${_numbers(s.emptyQuestions)}', size: 8),
              ],
            ],

            // Plan (yalnızca çalışma planı seçildiyse)
            if (withPlan) ...[
            pw.NewPage(),
            _h('$weeks Haftalık Kişisel Çalışma Planın', color: PdfColors.deepPurple600),
            _t('Sınav Sonucuna Göre Değerlendirmen',
                bold: true, size: 11, color: PdfColors.indigo800),
            pw.SizedBox(height: 3),
            _t(
              _planIntro(r),
              size: 8,
              color: PdfColors.grey700,
            ),
            // Yorumlar KESİNLİKLE tek sayfaya sığsın: içerik gerekirse otomatik küçültülür.
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.topLeft,
              child: pw.SizedBox(
                width: 535,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: _comments(r, first, weeks),
                ),
              ),
            ),
            pw.SizedBox(height: 2),
            for (final w in r.plan) ...[
              pw.NewPage(),
              _t('$weeks Haftalık Kişisel Çalışma Planın  -  ${r.name}',
                  size: 8, color: PdfColors.grey600),
              pw.Container(
                margin: const pw.EdgeInsets.only(top: 8),
                padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.deepPurple400,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _t('${w.week}. Hafta  -  ${w.phase}',
                        bold: true, size: 10.5, color: PdfColors.white),
                    _t('Odak: ${w.focus}', size: 8.5, color: PdfColors.deepPurple50),
                  ],
                ),
              ),
              pw.SizedBox(height: 3),
              _t('Hedef: ${w.objective}', size: 8.5, color: PdfColors.grey700),
              pw.SizedBox(height: 3),
              pw.Table(
                border: const pw.TableBorder(
                  horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.4),
                  bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
                ),
                columnWidths: {
                  0: const pw.FixedColumnWidth(58),
                  1: const pw.FixedColumnWidth(78),
                  2: const pw.FlexColumnWidth(),
                  3: const pw.FixedColumnWidth(34),
                },
                children: [
                  for (var i = 0; i < w.sessions.length; i++)
                    pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: w.sessions[i].day == 'Pazar'
                            ? PdfColors.amber50
                            : (i ~/ 2).isEven
                                ? PdfColors.white
                                : PdfColors.grey100,
                      ),
                      children: [
                        _cell(
                          i.isEven || w.sessions[i].day == 'Pazar'
                              ? w.sessions[i].day
                              : '',
                          bold: true,
                          size: 8,
                        ),
                        _cell(w.sessions[i].subject,
                            bold: true,
                            size: 8,
                            color: w.sessions[i].review
                                ? PdfColors.teal700
                                : PdfColors.indigo800),
                        _cell(w.sessions[i].task, size: 8),
                        _cell('${w.sessions[i].minutes} dk',
                            size: 8, align: pw.TextAlign.right),
                      ],
                    ),
                ],
              ),
            ],
            pw.NewPage(),
            _h('Plan Sonrası: Rotanı Çiz', color: PdfColors.teal700),
            _t(
              'Sana $weeks haftalık plan hazırladım. $weeks hafta sonunda bu planı al, '
              'kendine bir rota yap ve üstüne yenilerini koyarak devam et:',
              size: 9.5,
            ),
            pw.SizedBox(height: 6),
            _bullets(const [
              'Her haftanın sonunda hata defterindeki soruları yeniden çöz; çözemediklerini '
                  'bir sonraki haftanın planına taşı.',
              'Planı bitirince bu rapordaki zayıf kazanımları tekrar kontrol et: güçlendiklerini '
                  'listeden çıkar, yeni zayıf alanları ekle.',
              'Aynı düzeni (her gün en az 2 ders, pazar günü genel tekrar) koruyarak planı '
                  'kendi ihtiyacına göre uzat.',
              'Öğretmenlerinle görüşüp yeni hedefler belirle; sonraki sınav sonucunda '
                  'ilerlemeni bu raporla karşılaştır.',
            ], PdfColors.teal700),
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.indigo50,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _t('Başarı İçin Altın Kurallar',
                      bold: true, size: 10, color: PdfColors.indigo800),
                  pw.SizedBox(height: 4),
                  _bullets(const [
                    'Planı aksatma: düzenli kısa çalışma, nadir uzun çalışmadan daha etkilidir.',
                    'Her çalışma oturumundan sonra yanlış yaptığın soruları hata defterine yaz.',
                    'Telefonu ve dikkat dağıtıcıları çalışma süresince uzakta tut.',
                    'Uyku ve beslenmeni ihmal etme; dinlenmiş zihin daha iyi öğrenir.',
                    'Her pazar çözemediğin soruların çözümünü öğrenmeden haftayı kapatma.',
                  ], PdfColors.indigo700),
                  pw.SizedBox(height: 6),
                  _t('Başarılar $first! Küçük adımlar, büyük sonuçlar getirir.',
                      bold: true, size: 9.5, color: PdfColors.deepPurple600),
                ],
              ),
            ),
            ..._goalsSection(r, weeks),
            ],
          ],
        ),
      );
    }
    return doc.save();
  }
}
