import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edukn/models/assessment/trial_exam_model.dart';

import '../../evaluation_models.dart';
import '../models/odak_models.dart';

/// Sınav seçim listesi için özet bilgi.
class OdakExamInfo {
  final String id;
  final String name;
  final DateTime? date;

  /// Sınavın sınıf seviyesi (ör. "8" veya "8. Sınıf"); yoksa boş.
  final String classLevel;

  const OdakExamInfo({
    required this.id,
    required this.name,
    this.date,
    this.classLevel = '',
  });
}

/// Seçilen sınavın analiz için hazırlanmış verisi.
class OdakExamData {
  final TrialExam exam;
  final List<OdakExamResult> results;
  final List<String> subjects;

  const OdakExamData({
    required this.exam,
    required this.results,
    required this.subjects,
  });

  Map<String, Map<String, List<String>>> get outcomes => exam.outcomes;
}

class OdakRepository {
  final _db = FirebaseFirestore.instance;

  /// Sadece sonuçları yüklenmiş sınavları ve yalnızca geçerli dönemi listeler.
  /// Başka dönemlerin sınavları buraya sızmaz (termId birebir eşleşmeli).
  Future<List<OdakExamInfo>> loadExams(
    String institutionId,
    String? termId,
  ) async {
    if (termId == null || termId.isEmpty) return [];
    final snap = await _db
        .collection('trial_exams')
        .where('institutionId', isEqualTo: institutionId)
        .get();

    final list = <OdakExamInfo>[];
    for (final d in snap.docs) {
      final data = d.data();
      if (data['isActive'] == false) continue;
      final rj = data['resultsJson'];
      if (rj is! String || rj.isEmpty) continue;

      if ((data['termId'] ?? '').toString() != termId) continue;

      list.add(
        OdakExamInfo(
          id: d.id,
          name: (data['name'] ?? 'İsimsiz Sınav').toString(),
          date: (data['date'] as Timestamp?)?.toDate(),
          classLevel: (data['classLevel'] ?? '').toString().trim(),
        ),
      );
    }
    list.sort((a, b) {
      final da = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return list;
  }

  Future<OdakExamData> loadExam(String examId) async {
    final doc = await _db.collection('trial_exams').doc(examId).get();
    if (!doc.exists) throw Exception('Sınav bulunamadı.');

    final exam = TrialExam.fromMap(doc.data()!, doc.id);
    final raw = exam.resultsJson;
    if (raw == null || raw.isEmpty) {
      throw Exception('Bu sınavın sonuçları henüz yüklenmemiş.');
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    final seen = <String>{};
    final results = <OdakExamResult>[];
    final subjects = <String>[];

    for (final item in decoded) {
      final r = OdakExamResult.fromStudentResult(
        StudentResult.fromJson(Map<String, dynamic>.from(item as Map)),
      );
      if (r.subjects.isEmpty) continue;
      if (!seen.add(r.student.id)) continue;
      results.add(r);
      for (final s in r.subjects.keys) {
        if (!subjects.contains(s)) subjects.add(s);
      }
    }

    return OdakExamData(exam: exam, results: results, subjects: subjects);
  }

  /// Birden fazla sınavı öğrenci bazında BİRLEŞTİRİR (birleşik değerlendirme).
  /// - Ders doğru/yanlış/boş/net değerleri toplanır.
  /// - Cevap ve anahtar dizileri sınav sırasıyla art arda eklenir; kazanım
  ///   listeleri de aynı sırada birleştirilir (öğrenciye özel '#' anahtarlı).
  static OdakExamData merge(List<OdakExamData> list) {
    if (list.length == 1) return list.first;

    final subjects = <String>[];
    for (final d in list) {
      for (final s in d.subjects) {
        if (!subjects.contains(s)) subjects.add(s);
      }
    }

    // Öğrenci id -> sınav indeksi -> sonuç
    final order = <String>[];
    final byStudent = <String, Map<int, OdakExamResult>>{};
    for (var i = 0; i < list.length; i++) {
      for (final r in list[i].results) {
        if (!byStudent.containsKey(r.student.id)) order.add(r.student.id);
        byStudent.putIfAbsent(r.student.id, () => {})[i] = r;
      }
    }

    final outcomes = <String, Map<String, List<String>>>{};
    final results = <OdakExamResult>[];

    List<String>? outcomeList(OdakExamData d, String letter, String subject) {
      final l = d.outcomes[letter]?[subject];
      if (l != null) return l;
      for (final m in d.outcomes.values) {
        final x = m[subject];
        if (x != null) return x;
      }
      return null;
    }

    for (final id in order) {
      final per = byStudent[id]!;
      // Öğrencinin bilgileri: en son sınavdaki kayıt esas alınır.
      final latestIdx = per.keys.reduce((a, b) => a > b ? a : b);
      final student = per[latestIdx]!.student;

      final letters = [
        for (var i = 0; i < list.length; i++)
          per[i] == null ? '-' : per[i]!.bookletLetter,
      ];
      final key = '#${letters.join(',')}';

      final stats = <String, OdakSubjectStat>{};
      final answers = <String, String>{};
      final correct = <String, String>{};
      final outList = <String, List<String>>{};

      for (final subject in subjects) {
        var c = 0, w = 0, e = 0;
        var net = 0.0;
        var has = false;
        final ans = StringBuffer();
        final ref = StringBuffer();
        final outs = <String>[];
        for (var i = 0; i < list.length; i++) {
          final r = per[i];
          final st = r?.subjects[subject];
          if (r == null || st == null) continue;
          has = true;
          c += st.correct;
          w += st.wrong;
          e += st.empty;
          net += st.net;
          final refStr = r.correctAnswers[subject] ?? '';
          final ansStr = r.answers[subject] ?? '';
          ref.write(refStr);
          ans.write(ansStr.length >= refStr.length
              ? ansStr.substring(0, refStr.length)
              : ansStr.padRight(refStr.length));
          final ol = outcomeList(list[i], r.bookletLetter, subject) ?? const [];
          for (var q = 0; q < refStr.length; q++) {
            outs.add(q < ol.length ? ol[q] : '');
          }
        }
        if (!has) continue;
        stats[subject] =
            OdakSubjectStat(correct: c, wrong: w, empty: e, net: net);
        answers[subject] = ans.toString();
        correct[subject] = ref.toString();
        outList[subject] = outs;
      }
      if (stats.isEmpty) continue;
      outcomes.putIfAbsent(key, () => {}).addAll(outList);
      results.add(OdakExamResult(
        student: student,
        booklet: key,
        subjects: stats,
        answers: answers,
        correctAnswers: correct,
      ));
    }

    final names = list.map((d) => d.exam.name).join(' + ');
    return OdakExamData(
      exam: list.first.exam.copyWith(name: names, outcomes: outcomes),
      results: results,
      subjects: subjects,
    );
  }
}
