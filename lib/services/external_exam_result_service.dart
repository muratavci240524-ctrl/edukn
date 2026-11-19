import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/assessment/external_exam_model.dart';
import '../models/assessment/external_exam_registration_model.dart';
import '../models/assessment/external_exam_result_model.dart';
import '../models/assessment/optical_form_model.dart';
import '../models/assessment/trial_exam_model.dart';
import 'optical_line_edits.dart';
import '../screens/school/assessment/exam_report_card_service.dart';

/// Optik dosyada başvuru ile eşleştirilemeyen satır.
class UnmatchedOpticalRow {
  final int lineNo;
  final String name;
  final String tc;
  final String reason;
  const UnmatchedOpticalRow({
    required this.lineNo,
    required this.name,
    required this.tc,
    required this.reason,
  });
}

/// Optik dosya okuma sonucu (henüz kaydedilmemiş / sıralanmamış).
class ExternalOpticalReadReport {
  final List<ExternalExamResult> results;
  final List<UnmatchedOpticalRow> unmatched;
  final List<String> warnings;
  final int totalLines;

  /// Başvuruyla eşleşmeyen ama puanlanmış adaylar (Öğrenci Eşleme ekranı için).
  final List<OrphanCandidate> orphans;
  const ExternalOpticalReadReport({
    required this.results,
    required this.unmatched,
    required this.warnings,
    required this.totalLines,
    this.orphans = const [],
  });
}

/// Optik dosyada okunan, başvuruyla eşleşmemiş aday.
class OrphanCandidate {
  final String key;
  final String name;
  final String tc;
  final String studentNo;
  final List<int> sessions;
  final List<ExternalSubjectResult> subjects;
  final String trialExamId;
  const OrphanCandidate({
    required this.key,
    required this.name,
    required this.tc,
    required this.studentNo,
    required this.sessions,
    required this.subjects,
    this.trialExamId = '',
  });

  double get net => subjects.fold(0.0, (a, s) => a + s.net);
}

/// Dış katılımlı sınav: sınav tanımı kaydı, optik okuma, puan / sıralama / burs hesabı ve karne verisi.
class ExternalExamResultService {
  static const String examsCollection = 'external_exams';
  static const String resultsCollection = 'external_exam_results';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ───────────────────────── Sınav tanımı ─────────────────────────

  Future<void> saveLevelDefinition(
    String examId,
    String grade,
    ExternalLevelDefinition def,
  ) async {
    await _db.collection(examsCollection).doc(examId).update({
      'levelDefinitions.$grade': def.toMap(),
    });
  }

  // ───────────────────────── Sonuç okuma / listeleme ─────────────────────────

  Stream<List<ExternalExamResult>> streamResults(String examId) {
    return _db
        .collection(resultsCollection)
        .where('examId', isEqualTo: examId)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => ExternalExamResult.fromMap(d.data()))
              .toList(),
        );
  }

  /// Genel (herkese açık) sorgulama: doküman kimliği `{examId}_{tc}`.
  Future<ExternalExamResult?> getResult(String examId, String tcNo) async {
    final doc = await _db
        .collection(resultsCollection)
        .doc(ExternalExamResult.docIdFor(examId, tcNo.trim()))
        .get();
    if (doc.exists && doc.data() != null) {
      final r = ExternalExamResult.fromMap(doc.data()!);
      return r.shared ? r : null;
    }
    // TC'si dosyada olmayan başvurusuz adaylar okul numarasıyla kaydedilir.
    final alt = await _db
        .collection(resultsCollection)
        .doc(ExternalExamResult.docIdFor(examId, 'NOTC-${tcNo.trim()}'))
        .get();
    if (!alt.exists || alt.data() == null) return null;
    final r = ExternalExamResult.fromMap(alt.data()!);
    return r.shared ? r : null;
  }

  Future<void> deleteGradeResults(String examId, String grade) async {
    final snap = await _db
        .collection(resultsCollection)
        .where('examId', isEqualTo: examId)
        .get();
    final refs = snap.docs
        .where((d) => (d.data()['gradeLevel'] ?? '').toString() == grade)
        .map((d) => d.reference)
        .toList();
    for (int i = 0; i < refs.length; i += 400) {
      final batch = _db.batch();
      for (final r in refs.sublist(
        i,
        i + 400 > refs.length ? refs.length : i + 400,
      )) {
        batch.delete(r);
      }
      await batch.commit();
    }
  }

  // ───────────────────────── Kaydet + sırala + burs ─────────────────────────

  /// Yeni okunan sonuçları o sınıf seviyesindeki mevcut sonuçlarla birleştirir
  /// (aynı TC'li aday varsa yenisi geçerli), tüm seviyeyi yeniden sıralar ve bursu hesaplar.
  Future<int> saveGradeResults({
    required ExternalExam exam,
    required String grade,
    required List<ExternalExamResult> newResults,
  }) async {
    final examId = exam.id ?? '';
    final existingSnap = await _db
        .collection(resultsCollection)
        .where('examId', isEqualTo: examId)
        .get();
    final Map<String, ExternalExamResult> merged = {};
    for (final d in existingSnap.docs) {
      final r = ExternalExamResult.fromMap(d.data());
      if (r.gradeLevel == grade) merged[r.docId] = r;
    }
    // Aynı aday önceki okumalarda varsa dersler birleştirilir (yeni okuma, aynı dersi
    // ezer; diğer oturum/dersler korunur). Böylece birden fazla .dat eklenebilir.
    for (final n in newResults) {
      final old = merged[n.docId];
      merged[n.docId] = old == null ? n : _mergeResults(old, n);
    }
    // Paylaşım durumu seviye bazındadır: mevcut sonuçlar paylaşıldıysa yeniler de paylaşılır.
    final shared = existingSnap.docs.any((d) =>
        (d.data()['gradeLevel'] ?? '').toString() == grade && d.data()['shared'] == true);
    final ranked = rankAndAward(exam, grade, merged.values.toList())
        .map((r) => r.withShared(shared))
        .toList();
    await _writeAll(ranked);
    return ranked.length;
  }

  /// Bir seviyenin tüm sonuçlarını paylaşır (aday sorgulamasında görünür) ya da paylaşımı geri alır.
  Future<int> setGradeShared(String examId, String grade, bool shared) async {
    final snap = await _db.collection(resultsCollection).where('examId', isEqualTo: examId).get();
    final refs = snap.docs
        .where((d) => (d.data()['gradeLevel'] ?? '').toString() == grade)
        .map((d) => d.reference)
        .toList();
    for (int i = 0; i < refs.length; i += 400) {
      final batch = _db.batch();
      for (final r in refs.sublist(i, i + 400 > refs.length ? refs.length : i + 400)) {
        batch.update(r, {'shared': shared});
      }
      await batch.commit();
    }
    return refs.length;
  }

  /// Burs kademeleri değiştiğinde ya da yeniden hesaplamak için.
  Future<int> recomputeRanking(ExternalExam exam, String grade) async {
    final snap = await _db
        .collection(resultsCollection)
        .where('examId', isEqualTo: exam.id ?? '')
        .get();
    final list = snap.docs
        .map((d) => ExternalExamResult.fromMap(d.data()))
        .where((r) => r.gradeLevel == grade)
        .toList();
    if (list.isEmpty) return 0;
    final ranked = rankAndAward(exam, grade, list);
    await _writeAll(ranked);
    return ranked.length;
  }

  Future<void> _writeAll(List<ExternalExamResult> list) async {
    for (int i = 0; i < list.length; i += 400) {
      final batch = _db.batch();
      for (final r in list.sublist(
        i,
        i + 400 > list.length ? list.length : i + 400,
      )) {
        batch.set(_db.collection(resultsCollection).doc(r.docId), r.toMap());
      }
      await batch.commit();
    }
  }

  /// Puana göre sıralar (listede eşit puanda net, sonra doğru sayısı belirleyicidir ama
  /// SIRA numarası yalnızca puana bakar: eşit puanlılar aynı sırayı alır) ve sınıf seviyesinin burs kademesine göre bursu belirler.
  static List<ExternalExamResult> rankAndAward(
    ExternalExam exam,
    String grade,
    List<ExternalExamResult> list,
  ) {
    final sorted = List<ExternalExamResult>.from(list)
      ..sort((a, b) {
        int c = b.score.compareTo(a.score);
        if (c != 0) return c;
        c = b.net.compareTo(a.net);
        if (c != 0) return c;
        return b.correct.compareTo(a.correct);
      });

    final tiers = exam.scholarshipEnabled
        ? (exam.scholarshipConfig[grade] ?? const <ScholarshipTier>[])
        : const <ScholarshipTier>[];

    final out = <ExternalExamResult>[];
    int currentRank = 0;
    for (int i = 0; i < sorted.length; i++) {
      final r = sorted[i];
      final prev = i > 0 ? sorted[i - 1] : null;
      // Aynı puanı alan adaylar AYNI sırayı alır (yarışma sıralaması: 1, 2, 2, 4 ...).
      final tie = prev != null && prev.score == r.score;
      if (!tie) currentRank = i + 1;

      int rate = 0;
      String text = '';
      for (final t in tiers) {
        if (currentRank >= t.minRank &&
            currentRank <= t.maxRank &&
            t.rate > rate) {
          rate = t.rate;
          text = t.displayText;
        }
      }
      out.add(
        r.withRanking(
          rank: currentRank,
          totalInGrade: sorted.length,
          scholarshipRate: rate,
          scholarshipText: text,
        ),
      );
    }
    return out;
  }

  // ───────────────────────── Optik dosya işleme ─────────────────────────

  static String _fold(String s) => s
      .trim()
      .replaceAll('İ', 'i')
      .replaceAll('I', 'i')
      .replaceAll('ı', 'i')
      .replaceAll('Ş', 's')
      .replaceAll('ş', 's')
      .replaceAll('Ğ', 'g')
      .replaceAll('ğ', 'g')
      .replaceAll('Ü', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('Ö', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('Ç', 'c')
      .replaceAll('ç', 'c')
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  static String _extract(String line, OpticalField f, {bool trim = true}) {
    if (f.length <= 0) return '';
    final s = f.start > 0 ? f.start - 1 : 0;
    String r;
    if (line.length >= s + f.length) {
      r = line.substring(s, s + f.length);
    } else if (line.length > s) {
      r = line.substring(s).padRight(f.length, ' ');
    } else {
      r = ''.padRight(f.length, ' ');
    }
    return trim ? r.trim() : r;
  }

  static OpticalField? _subjectField(OpticalForm form, String subject) {
    final direct = form.subjectFields[subject];
    if (direct != null) return direct;
    final n = _fold(subject);
    for (final e in form.subjectFields.entries) {
      if (_fold(e.key) == n) return e.value;
    }
    return null;
  }

  /// Optik form tanımındaki ders alanlarından, sınav tanımının ders listesini üretir
  /// (soru sayısı = alan uzunluğu). Mevcut cevap anahtarı / katsayı korunur.
  static List<ExternalLevelSubject> subjectsFromForm(
    OpticalForm form,
    List<ExternalLevelSubject> existing,
  ) {
    final result = <ExternalLevelSubject>[];
    for (final e in form.subjectFields.entries) {
      if (e.value.length <= 0) continue;
      final old = existing.where((s) => _fold(s.name) == _fold(e.key));
      if (old.isNotEmpty) {
        final o = old.first;
        result.add(
          o.copyWith(
            questionCount: e.value.length,
            answerKey: o.answerKey.length > e.value.length
                ? o.answerKey.substring(0, e.value.length)
                : o.answerKey,
          ),
        );
      } else {
        result.add(ExternalLevelSubject(name: e.key, questionCount: e.value.length));
      }
    }
    return result;
  }

  static ExternalOpticalReadReport processOpticalText({
    required String text,
    required OpticalForm form,
    required ExternalLevelDefinition def,
    required List<ExternalExamRegistration> registrations,
    required ExternalExam exam,
    required String grade,
  }) {
    final warnings = <String>[];
    final unmatched = <UnmatchedOpticalRow>[];
    final results = <String, ExternalExamResult>{};

    // Aday dizinleri
    final byTc = <String, ExternalExamRegistration>{};
    final byNo = <String, ExternalExamRegistration>{};
    final byName = <String, ExternalExamRegistration>{};
    for (final r in registrations) {
      if (r.status == RegistrationStatus.cancelled) continue;
      if (r.studentTcNo.trim().isNotEmpty) byTc[r.studentTcNo.trim()] = r;
      final no = (r.studentNumber ?? '').trim();
      if (no.isNotEmpty) byNo[no] = r;
      byName[_fold(r.fullName)] = r;
    }

    // Ders alanları
    final fields = <ExternalLevelSubject, OpticalField>{};
    for (final s in def.subjects) {
      final f = _subjectField(form, s.name);
      if (f == null) {
        warnings.add(
          '"${s.name}" dersi seçili optik formda bulunamadı; bu ders boş sayıldı.',
        );
      } else {
        fields[s] = f;
      }
    }

    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.replaceAll('\r', ''))
        .toList();
    int total = 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      total++;

      final tc = _extract(line, form.identityNo).replaceAll(RegExp(r'[^0-9]'), '');
      final no = _extract(line, form.studentNo);
      final name = _extract(line, form.studentNameField);

      ExternalExamRegistration? reg;
      if (tc.isNotEmpty) reg = byTc[tc];
      if (reg == null && no.isNotEmpty) reg = byNo[no];
      if (reg == null && name.isNotEmpty) reg = byName[_fold(name)];

      if (reg == null) {
        unmatched.add(
          UnmatchedOpticalRow(
            lineNo: i + 1,
            name: name,
            tc: tc,
            reason: 'Başvuru listesinde eşleşen aday bulunamadı',
          ),
        );
        continue;
      }
      if (reg.gradeLevel != grade) {
        unmatched.add(
          UnmatchedOpticalRow(
            lineNo: i + 1,
            name: reg.fullName,
            tc: reg.studentTcNo,
            reason: 'Aday ${reg.gradeLevel}. sınıf başvurusu yapmış, bu seviye $grade.',
          ),
        );
        continue;
      }
      final docId = ExternalExamResult.docIdFor(exam.id ?? '', reg.studentTcNo.trim());
      if (results.containsKey(docId)) {
        unmatched.add(
          UnmatchedOpticalRow(
            lineNo: i + 1,
            name: reg.fullName,
            tc: reg.studentTcNo,
            reason: 'Aynı aday dosyada birden fazla kez var (ilk okuma geçerli)',
          ),
        );
        continue;
      }

      // Ders ders puanlama
      final subjectResults = <ExternalSubjectResult>[];
      int tCorrect = 0, tWrong = 0, tEmpty = 0;
      double tNet = 0, weighted = 0, maxWeighted = 0;
      for (final s in def.subjects) {
        final f = fields[s];
        final sAns = f == null
            ? ''.padRight(s.questionCount, ' ')
            : _extract(line, f, trim: false).toUpperCase();
        int c = 0, w = 0, e = 0;
        for (int q = 0; q < s.questionCount; q++) {
          final key = q < s.answerKey.length ? s.answerKey[q].toUpperCase() : '';
          final ch = q < sAns.length ? sAns[q] : ' ';
          if (key == '#') {
            c++; // iptal soru: herkese doğru
            continue;
          }
          final marked = 'ABCDE'.contains(ch) && ch.trim().isNotEmpty;
          if (!marked) {
            e++;
          } else if (ch == key) {
            c++;
          } else {
            w++;
          }
        }
        final net = c - (def.penaltyDivisor > 0 ? w / def.penaltyDivisor : 0);
        subjectResults.add(
          ExternalSubjectResult(
            name: s.name,
            questionCount: s.questionCount,
            correct: c,
            wrong: w,
            empty: e,
            net: double.parse(net.toStringAsFixed(2)),
          ),
        );
        tCorrect += c;
        tWrong += w;
        tEmpty += e;
        tNet += net;
        weighted += net * s.coefficient;
        maxWeighted += s.questionCount * s.coefficient;
      }
      double score = maxWeighted > 0 ? (weighted / maxWeighted) * 100 : 0;
      if (score < 0) score = 0;

      results[docId] = ExternalExamResult(
        examId: exam.id ?? '',
        institutionId: exam.institutionId,
        registrationId: reg.id ?? '',
        tcNo: reg.studentTcNo.trim(),
        fullName: reg.fullName,
        gradeLevel: grade,
        currentSchool: reg.currentSchool,
        subjects: subjectResults,
        correct: tCorrect,
        wrong: tWrong,
        empty: tEmpty,
        net: double.parse(tNet.toStringAsFixed(2)),
        score: double.parse(score.toStringAsFixed(2)),
      );
    }

    return ExternalOpticalReadReport(
      results: results.values.toList(),
      unmatched: unmatched,
      warnings: warnings,
      totalLines: total,
    );
  }

  // ───────────────────── Deneme sınavına bağlı okuma ─────────────────────

  /// Deneme sınavının (ilk kitapçığa göre) dersleri ve soru sayıları.
  static Map<String, int> trialSubjectQuestionCounts(TrialExam t) {
    final out = <String, int>{};
    if (t.answerKeys.isEmpty) return out;
    final first = t.answerKeys.values.first;
    first.forEach((k, v) => out[k] = v.length);
    return out;
  }

  static int trialTotalQuestions(TrialExam t) {
    final counts = trialSubjectQuestionCounts(t);
    final allowed = <String>{};
    for (final s in t.sessions) {
      allowed.addAll(s.selectedSubjects);
    }
    return counts.entries
        .where((e) => allowed.isEmpty || allowed.contains(e.key))
        .fold(0, (a, e) => a + e.value);
  }

  /// Bağlı denemeyi Firestore'dan (güncel cevap anahtarıyla) okur.
  Future<TrialExam?> loadTrialExam(String id) async {
    final doc = await _db.collection('trial_exams').doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    return TrialExam.fromMap(doc.data()!, doc.id);
  }

  /// Ders sonuçlarından (başvuru ile ya da başvurusuz) aday sonucu üretir.
  static ExternalExamResult buildResult({
    required ExternalExam exam,
    required String grade,
    required List<ExternalSubjectResult> subjects,
    ExternalExamRegistration? reg,
    String fallbackName = '',
    String fallbackTc = '',
    String fallbackNo = '',
    String trialExamId = '',
  }) {
    int c = 0, w = 0, e = 0, q = 0;
    double net = 0;
    for (final s in subjects) {
      c += s.correct;
      w += s.wrong;
      e += s.empty;
      q += s.questionCount;
      net += s.net;
    }
    double score = q > 0 ? (net / q) * 100 : 0;
    if (score < 0) score = 0;
    String tc = reg?.studentTcNo.trim() ?? fallbackTc.trim();
    if (tc.isEmpty) {
      tc = 'NOTC-${fallbackNo.isNotEmpty ? fallbackNo : _fold(fallbackName).replaceAll(' ', '')}';
    }
    return ExternalExamResult(
      examId: exam.id ?? '',
      institutionId: exam.institutionId,
      registrationId: reg?.id ?? '',
      tcNo: tc,
      fullName: reg?.fullName ?? fallbackName,
      gradeLevel: grade,
      currentSchool: reg?.currentSchool ?? '',
      subjects: subjects,
      correct: c,
      wrong: w,
      empty: e,
      net: double.parse(net.toStringAsFixed(2)),
      score: double.parse(score.toStringAsFixed(2)),
      trialExamId: trialExamId,
    );
  }

  /// Deneme sınavının oturumlarındaki optik dosyaları (oturum no -> dosya metni)
  /// başvurularla eşleştirip puanlar. Cevap anahtarı, kitapçık türü, oturumdaki
  /// ders seçimi ve satır düzeltmeleri deneme sınavı modülündeki gibi uygulanır.
  ///
  /// Başvuruyla eşleşmeyen adaylar atılmaz: puanlanıp `orphans` listesine konur,
  /// böylece "Öğrenci Eşleme" ekranında elle eşlenebilir.
  static ExternalOpticalReadReport processTrialExamSessions({
    required Map<int, String> sessionTexts,
    required TrialExam trial,
    required Map<String, OpticalForm> forms,
    required List<ExternalExamRegistration> registrations,
    required ExternalExam exam,
    required String grade,
    required double penaltyDivisor,
    /// Sınav türündeki ders sırası (karne ders sıralaması için).
    List<String> subjectOrder = const [],
  }) {
    final warnings = <String>[];
    final unmatched = <UnmatchedOpticalRow>[];
    int total = 0;

    final byTc = <String, ExternalExamRegistration>{};
    final byNo = <String, ExternalExamRegistration>{};
    final byName = <String, ExternalExamRegistration>{};
    for (final r in registrations) {
      if (r.status == RegistrationStatus.cancelled) continue;
      if (r.studentTcNo.trim().isNotEmpty) byTc[r.studentTcNo.trim()] = r;
      final no = (r.studentNumber ?? '').trim();
      if (no.isNotEmpty) byNo[no] = r;
      byName[_fold(r.fullName)] = r;
    }

    if (trial.answerKeys.isEmpty) {
      warnings.add('Seçili deneme sınavında cevap anahtarı tanımlı değil.');
    }
    final counts = trialSubjectQuestionCounts(trial);

    // anahtar -> ders adı -> sonuç
    final subjByKey = <String, Map<String, ExternalSubjectResult>>{};
    final regByKey = <String, ExternalExamRegistration>{};
    final orphanMeta = <String, List<String>>{}; // key -> [name, tc, no]
    final orphanSessions = <String, Set<int>>{};

    final sessions = [...trial.sessions]
      ..sort((a, b) => a.sessionNumber.compareTo(b.sessionNumber));

    for (final session in sessions) {
      final text = sessionTexts[session.sessionNumber];
      if (text == null || text.trim().isEmpty) continue;
      final form = forms[session.opticalFormId ?? ''];
      if (form == null) {
        warnings.add('${session.sessionNumber}. oturum: optik form bulunamadı, atlandı.');
        continue;
      }
      final rawLines = text.split('\n').map((l) => l.replaceAll('\r', '')).toList();
      final lines = OpticalLineEdits.apply(rawLines, form, session.lineEdits);
      final allowed = session.selectedSubjects.isNotEmpty
          ? session.selectedSubjects.toSet()
          : null;
      final seenInSession = <String>{};

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().isEmpty) continue;
        total++;
        final tc = _extract(line, form.identityNo).replaceAll(RegExp(r'[^0-9]'), '');
        final no = _extract(line, form.studentNo);
        final name = _extract(line, form.studentNameField);

        ExternalExamRegistration? reg;
        if (tc.isNotEmpty) reg = byTc[tc];
        if (reg == null && no.isNotEmpty) reg = byNo[no];
        if (reg == null && name.isNotEmpty) reg = byName[_fold(name)];

        String key;
        if (reg != null) {
          if (reg.gradeLevel != grade) {
            unmatched.add(UnmatchedOpticalRow(
              lineNo: i + 1,
              name: '${session.sessionNumber}. oturum  ${reg.fullName}',
              tc: reg.studentTcNo,
              reason: 'Aday ${reg.gradeLevel}. sınıf başvurusu yapmış, bu seviye $grade.',
            ));
            continue;
          }
          key = ExternalExamResult.docIdFor(exam.id ?? '', reg.studentTcNo.trim());
          regByKey[key] = reg;
        } else {
          final id = tc.isNotEmpty
              ? tc
              : no.isNotEmpty
                  ? 'no$no'
                  : _fold(name).replaceAll(' ', '');
          if (id.isEmpty) continue;
          key = 'orphan:$id';
          orphanMeta.putIfAbsent(key, () => [name, tc, no]);
          orphanSessions.putIfAbsent(key, () => {}).add(session.sessionNumber);
        }

        if (!seenInSession.add(key)) {
          unmatched.add(UnmatchedOpticalRow(
            lineNo: i + 1,
            name: '${session.sessionNumber}. oturum  ${reg?.fullName ?? name}',
            tc: reg?.studentTcNo ?? tc,
            reason: 'Aynı aday bu oturum dosyasında birden fazla (ilk okuma geçerli)',
          ));
          continue;
        }

        // Kitapçık
        String booklet = trial.answerKeys.keys.isNotEmpty ? trial.answerKeys.keys.first : 'A';
        if (form.bookletType.length > 0) {
          final b = _extract(line, form.bookletType).trim().toUpperCase();
          if (b.isNotEmpty) booklet = b;
        }
        if (!trial.answerKeys.containsKey(booklet)) {
          if (trial.answerKeys.isEmpty) continue;
          booklet = trial.answerKeys.keys.first;
        }
        final keyMap = trial.answerKeys[booklet]!;
        final subj = subjByKey.putIfAbsent(key, () => {});

        form.subjectFields.forEach((subjectName, field) {
          if (allowed != null && !allowed.contains(subjectName)) return;
          final cAns = keyMap[subjectName];
          if (cAns == null || cAns.isEmpty) return;
          final sAns = _extract(line, field, trim: false);
          int c = 0, w = 0, e = 0;
          for (int q = 0; q < cAns.length; q++) {
            final k = cAns[q].toUpperCase();
            final s = q < sAns.length ? sAns[q].toUpperCase() : ' ';
            if (k == 'S') {
              c++;
            } else if (k == '#') {
              e++;
            } else if (k == 'X') {
              // iptal: yok sayılır
            } else if (!'ABCDE'.contains(s) || s.trim().isEmpty) {
              e++;
            } else if (s == k) {
              c++;
            } else {
              w++;
            }
          }
          final net = c - (penaltyDivisor > 0 ? w / penaltyDivisor : 0);
          subj[subjectName] = ExternalSubjectResult(
            name: subjectName,
            questionCount: counts[subjectName] ?? cAns.length,
            correct: c,
            wrong: w,
            empty: e,
            net: double.parse(net.toStringAsFixed(2)),
            answers: sAns,
            key: cAns,
            booklet: booklet,
            outcomes: trial.outcomes[booklet]?[subjectName] ?? const [],
            order: ExamReportCardService.getSubjectOrderIndex(subjectName, definedOrder: subjectOrder),
          );
        });
      }
    }

    final results = <ExternalExamResult>[];
    final orphans = <OrphanCandidate>[];
    subjByKey.forEach((key, subjMap) {
      final list = subjMap.values.toList();
      if (list.isEmpty) return;
      final reg = regByKey[key];
      if (reg != null) {
        results.add(buildResult(exam: exam, grade: grade, subjects: list, reg: reg, trialExamId: trial.id));
      } else {
        final m = orphanMeta[key] ?? ['', '', ''];
        orphans.add(OrphanCandidate(
          key: key,
          name: m[0],
          tc: m[1],
          studentNo: m[2],
          sessions: (orphanSessions[key] ?? {}).toList()..sort(),
          subjects: list,
          trialExamId: trial.id,
        ));
      }
    });
    orphans.sort((a, b) => a.name.compareTo(b.name));

    return ExternalOpticalReadReport(
      results: results,
      unmatched: unmatched,
      warnings: warnings,
      totalLines: total,
      orphans: orphans,
    );
  }

  /// Başvuru listesinden, dosyadaki ada en çok benzeyen (kelime örtüşmesi) aday.
  static ExternalExamRegistration? suggestRegistration(
    OrphanCandidate o,
    List<ExternalExamRegistration> candidates,
  ) {
    final tokens = _fold(o.name).split(' ').where((t) => t.length > 1).toSet();
    if (tokens.isEmpty) return null;
    ExternalExamRegistration? best;
    int bestScore = 0;
    for (final r in candidates) {
      final rt = _fold(r.fullName).split(' ').toSet();
      final sc = tokens.where(rt.contains).length;
      if (sc > bestScore) {
        bestScore = sc;
        best = r;
      }
    }
    return bestScore >= 1 ? best : null;
  }

  /// Arama için ad katlama (Türkçe karakter duyarsız).
  static String foldText(String s) => _fold(s);

  /// Optik okuyucu dosyaları genelde Windows-1254 (Türkçe ANSI) kodludur.
  /// UTF-8 değilse baytlar cp1254'e göre çözülür: İ ı Ş ş Ğ ğ doğru okunur
  /// (Latin-1 ile okununca Ý ý Þ þ Ð ð çıkıyordu).
  static String decodeLegacyTurkish(List<int> bytes) {
    const map = <int, String>{
      0xD0: 'Ğ', 0xF0: 'ğ',
      0xDD: 'İ', 0xFD: 'ı',
      0xDE: 'Ş', 0xFE: 'ş',
    };
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(map[b] ?? String.fromCharCode(b));
    }
    return sb.toString();
  }

  static ExternalExamResult _mergeResults(ExternalExamResult old, ExternalExamResult nw) {
    final map = <String, ExternalSubjectResult>{
      for (final s in old.subjects) s.name: s,
    };
    for (final s in nw.subjects) {
      map[s.name] = s;
    }
    final list = map.values.toList();
    int c = 0, w = 0, e = 0, q = 0;
    double net = 0;
    for (final s in list) {
      c += s.correct;
      w += s.wrong;
      e += s.empty;
      q += s.questionCount;
      net += s.net;
    }
    double score = q > 0 ? (net / q) * 100 : 0;
    if (score < 0) score = 0;
    return ExternalExamResult(
      examId: nw.examId,
      institutionId: nw.institutionId,
      registrationId: nw.registrationId.isNotEmpty ? nw.registrationId : old.registrationId,
      tcNo: nw.tcNo,
      fullName: nw.fullName.isNotEmpty ? nw.fullName : old.fullName,
      gradeLevel: nw.gradeLevel,
      currentSchool: nw.currentSchool.isNotEmpty ? nw.currentSchool : old.currentSchool,
      subjects: list,
      correct: c,
      wrong: w,
      empty: e,
      net: double.parse(net.toStringAsFixed(2)),
      score: double.parse(score.toStringAsFixed(2)),
      trialExamId: nw.trialExamId.isNotEmpty ? nw.trialExamId : old.trialExamId,
    );
  }

  /// Bir sınıf seviyesinin burs kademelerini (ve burs açık/kapalı durumunu) kaydeder; güncel sınavı döndürür.
  Future<ExternalExam?> saveScholarship(
    String examId,
    String grade,
    List<ScholarshipTier> tiers,
    bool enabled,
  ) async {
    await _db.collection(examsCollection).doc(examId).update({
      'scholarshipConfig.$grade': tiers.map((t) => t.toMap()).toList(),
      'scholarshipEnabled': enabled,
    });
    final d = await _db.collection(examsCollection).doc(examId).get();
    if (!d.exists || d.data() == null) return null;
    return ExternalExam.fromMap(d.data()!, d.id);
  }
}