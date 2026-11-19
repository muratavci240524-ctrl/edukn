import 'dart:math' as math;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../utils/gercek_kazanim_mapper.dart';

/// 5 zengin vektörel kapak teması.
enum CoverThemePreset {
  midnightAcademic,
  emeraldFocus,
  royalPurple,
  orangeEnergy,
  minimalCorporate,
}

extension CoverThemePresetExt on CoverThemePreset {
  String get key {
    switch (this) {
      case CoverThemePreset.midnightAcademic:
        return 'midnight_academic';
      case CoverThemePreset.emeraldFocus:
        return 'emerald_focus';
      case CoverThemePreset.royalPurple:
        return 'royal_purple';
      case CoverThemePreset.orangeEnergy:
        return 'orange_energy';
      case CoverThemePreset.minimalCorporate:
        return 'minimal_corporate';
    }
  }

  String get label {
    switch (this) {
      case CoverThemePreset.midnightAcademic:
        return 'Gece Mavisi Akademik';
      case CoverThemePreset.emeraldFocus:
        return 'Zümrüt Odak';
      case CoverThemePreset.royalPurple:
        return 'Kraliyet Moru';
      case CoverThemePreset.orangeEnergy:
        return 'Turuncu Enerji';
      case CoverThemePreset.minimalCorporate:
        return 'Minimal Kurumsal';
    }
  }

  String get subtitle {
    switch (this) {
      case CoverThemePreset.midnightAcademic:
        return 'Lacivert prestij ve altın-camgöbeği vurgu';
      case CoverThemePreset.emeraldFocus:
        return 'Odaklanmayı artıran derin zümrüt yeşili';
      case CoverThemePreset.royalPurple:
        return 'Derece hedefli modern mor & kehribar';
      case CoverThemePreset.orangeEnergy:
        return 'Motivasyon odaklı dinamik turuncu & antrasit';
      case CoverThemePreset.minimalCorporate:
        return 'Beyaz zeminli sade kurumsal akademik çizgi';
    }
  }

  int get primaryHex {
    switch (this) {
      case CoverThemePreset.midnightAcademic:
        return 0xFF0F172A;
      case CoverThemePreset.emeraldFocus:
        return 0xFF064E3B;
      case CoverThemePreset.royalPurple:
        return 0xFF3B0764;
      case CoverThemePreset.orangeEnergy:
        return 0xFF9A3412;
      case CoverThemePreset.minimalCorporate:
        return 0xFF1E293B;
    }
  }

  int get secondaryHex {
    switch (this) {
      case CoverThemePreset.midnightAcademic:
        return 0xFF1E3A8A;
      case CoverThemePreset.emeraldFocus:
        return 0xFF047857;
      case CoverThemePreset.royalPurple:
        return 0xFF6B21A8;
      case CoverThemePreset.orangeEnergy:
        return 0xFFEA580C;
      case CoverThemePreset.minimalCorporate:
        return 0xFF334155;
    }
  }

  int get accentHex {
    switch (this) {
      case CoverThemePreset.midnightAcademic:
        return 0xFF38BDF8;
      case CoverThemePreset.emeraldFocus:
        return 0xFF34D399;
      case CoverThemePreset.royalPurple:
        return 0xFFFBBF24;
      case CoverThemePreset.orangeEnergy:
        return 0xFFFACC15;
      case CoverThemePreset.minimalCorporate:
        return 0xFF4F46E5;
    }
  }

  int get softTintHex {
    switch (this) {
      case CoverThemePreset.midnightAcademic:
        return 0xFFEFF6FF;
      case CoverThemePreset.emeraldFocus:
        return 0xFFECFDF5;
      case CoverThemePreset.royalPurple:
        return 0xFFFAF5FF;
      case CoverThemePreset.orangeEnergy:
        return 0xFFFFF7ED;
      case CoverThemePreset.minimalCorporate:
        return 0xFFF8FAFC;
    }
  }

  bool get isLightCover => this == CoverThemePreset.minimalCorporate;

  Color get primaryColor => Color(primaryHex);
  Color get secondaryColor => Color(secondaryHex);
  Color get accentColor => Color(accentHex);
  Color get softTintColor => Color(softTintHex);

  static CoverThemePreset fromKey(String? raw) {
    for (final v in CoverThemePreset.values) {
      if (v.key == raw || v.name == raw) return v;
    }
    return CoverThemePreset.midnightAcademic;
  }
}

/// Ön Söz ekleme modu.
enum PrefaceMode { none, manual, uploadedPdf }

extension PrefaceModeExt on PrefaceMode {
  String get key {
    switch (this) {
      case PrefaceMode.none:
        return 'none';
      case PrefaceMode.manual:
        return 'manual';
      case PrefaceMode.uploadedPdf:
        return 'uploaded_pdf';
    }
  }

  String get label {
    switch (this) {
      case PrefaceMode.none:
        return 'Yok (Ekleme)';
      case PrefaceMode.manual:
        return 'Manuel Ön Söz Yaz';
      case PrefaceMode.uploadedPdf:
        return 'Ek PDF Dosyası Yükle';
    }
  }

  static PrefaceMode fromKey(String? raw) {
    for (final v in PrefaceMode.values) {
      if (v.key == raw || v.name == raw) return v;
    }
    return PrefaceMode.manual;
  }
}

/// Öğrencinin kazanım hakimiyet bandı.
enum MasteryBand {
  foundation, // < 40%: Temel Güçlendirme (Çok Kolay & Kolay sorular: diff 61..100)
  reinforcement, // 40%..75%: Pekiştirme (Kolay & Orta sorular: diff 41..80)
  advanced, // > 75%: İleri Seviye / Derece (Zor & Çok Zor sorular: diff 0..40)
}

extension MasteryBandExt on MasteryBand {
  String get label {
    switch (this) {
      case MasteryBand.foundation:
        return 'Temel Güçlendirme (Çok Kolay / Kolay)';
      case MasteryBand.reinforcement:
        return 'Pekiştirme (Kolay / Orta)';
      case MasteryBand.advanced:
        return 'İleri Seviye / Derece (Zor / Çok Zor)';
    }
  }

  String get shortLabel {
    switch (this) {
      case MasteryBand.foundation:
        return 'Temel (Çok Kolay/Kolay)';
      case MasteryBand.reinforcement:
        return 'Pekiştirme (Kolay/Orta)';
      case MasteryBand.advanced:
        return 'İleri (Zor/Çok Zor)';
    }
  }

  /// Havuzda difficulty 0..100 (% doğru yapılma oranı: yüksek = daha kolay, düşük = daha zor).
  double get minPreferredDifficulty {
    switch (this) {
      case MasteryBand.foundation:
        return 61.0;
      case MasteryBand.reinforcement:
        return 41.0;
      case MasteryBand.advanced:
        return 0.0;
    }
  }

  double get maxPreferredDifficulty {
    switch (this) {
      case MasteryBand.foundation:
        return 100.0;
      case MasteryBand.reinforcement:
        return 80.0;
      case MasteryBand.advanced:
        return 40.0;
    }
  }

  double get centerPreferredDifficulty =>
      (minPreferredDifficulty + maxPreferredDifficulty) / 2.0;

  Color get color {
    switch (this) {
      case MasteryBand.foundation:
        return const Color(0xFFDC2626);
      case MasteryBand.reinforcement:
        return const Color(0xFFD97706);
      case MasteryBand.advanced:
        return const Color(0xFF059669);
    }
  }

  static MasteryBand fromPercent(double masteryPercent) {
    if (masteryPercent < 40.0) return MasteryBand.foundation;
    if (masteryPercent <= 75.0) return MasteryBand.reinforcement;
    return MasteryBand.advanced;
  }
}

/// Türkçe metin ve branş normalizasyon yardımcıları.
class FokusTextUtils {
  static String normTr(String input) {
    return input
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
        .toLowerCase();
  }

  static String normAlnum(String input) {
    return normTr(input).replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static const Set<String> standardSchoolSubjects = {
    'Türkçe',
    'Türk Dili ve Edebiyatı',
    'Matematik',
    'Geometri',
    'Fen Bilimleri',
    'T.C. İnkılap Tarihi',
    'Sosyal Bilgiler',
    'Din Kültürü ve Ahlak Bilgisi',
    'İngilizce',
    'Almanca',
    'Fransızca',
    'Fizik',
    'Kimya',
    'Biyoloji',
    'Tarih',
    'Coğrafya',
    'Felsefe',
    'Psikoloji',
    'Sosyoloji',
    'Mantık',
    'Hayat Bilgisi',
  };

  static String canonicalSubject(String raw) {
    final n = normTr(raw);
    if (n.contains('turkce')) return 'Türkçe';
    if (n.contains('edebiyat')) return 'Türk Dili ve Edebiyatı';
    if (n.contains('matematik') || n == 'mat') return 'Matematik';
    if (n.contains('geometri')) return 'Geometri';
    if (n.contains('fen')) return 'Fen Bilimleri';
    if (n.contains('inkilap')) return 'T.C. İnkılap Tarihi';
    if (n.contains('sosyal') && !n.contains('sosyoloji')) {
      return 'Sosyal Bilgiler';
    }
    if (n.contains('din')) return 'Din Kültürü ve Ahlak Bilgisi';
    if (n.contains('ingilizce') || n.contains('yabanci')) return 'İngilizce';
    if (n.contains('almanca')) return 'Almanca';
    if (n.contains('fransizca')) return 'Fransızca';
    if (n.contains('fizik')) return 'Fizik';
    if (n.contains('kimya')) return 'Kimya';
    if (n.contains('biyoloji')) return 'Biyoloji';
    if (n.contains('tarih')) return 'Tarih';
    if (n.contains('cografya')) return 'Coğrafya';
    if (n.contains('felsefe')) return 'Felsefe';
    if (n.contains('psikoloji')) return 'Psikoloji';
    if (n.contains('sosyoloji')) return 'Sosyoloji';
    if (n.contains('mantik')) return 'Mantık';
    if (n.contains('hayat bilgisi')) return 'Hayat Bilgisi';
    return raw.trim().isEmpty ? 'Genel' : raw.trim();
  }

  /// Metnin gerçek bir ders/branş adı olup olmadığını doğrular
  /// (`"Saatler: Tam ve Yarım Saatler"` gibi kazanımların branş sanılmasını önler).
  static bool isKnownSchoolSubject(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > 36) return false;
    final canon = canonicalSubject(trimmed);
    return standardSchoolSubjects.contains(canon);
  }

  /// Sınıf seviyesi / sınav grubu uyumluluk kümesi üretir:
  /// `'8'` <-> `'8. Sınıf'` <-> `'LGS'` ve `'11'`/`'12'` <-> `'TYT'`/`'AYT'`/`'YKS'`/`'YDT'`.
  static Set<String> expandClassTokens(String raw) {
    final n = normTr(raw);
    if (n.isEmpty || n == 'genel' || n == 'tumu') return const {};

    final Set<String> tokens = {};
    final numMatches = RegExp(r'(?<!\d)(1[0-2]|[1-9])(?!\d)').allMatches(n);
    for (final m in numMatches) {
      final g = m.group(1)!;
      tokens.add('g_$g');
      if (g == '8') {
        tokens.add('exam_lgs');
      } else if (g == '11' || g == '12') {
        tokens.addAll(const ['exam_tyt', 'exam_ayt', 'exam_yks', 'exam_ydt']);
      }
    }

    if (n.contains('lgs')) {
      tokens.addAll(const ['g_8', 'exam_lgs']);
    }
    if (n.contains('tyt')) {
      tokens.addAll(const ['g_11', 'g_12', 'exam_tyt', 'exam_yks']);
    }
    if (n.contains('ayt')) {
      tokens.addAll(const ['g_11', 'g_12', 'exam_ayt', 'exam_yks']);
    }
    if (n.contains('yks') || n.contains('mezun')) {
      tokens.addAll(const ['g_11', 'g_12', 'exam_tyt', 'exam_ayt', 'exam_yks']);
    }
    if (n.contains('ydt')) {
      tokens.addAll(const ['g_11', 'g_12', 'exam_ydt', 'exam_yks']);
    }
    if (n.contains('bursluluk') || n.contains('iokbs')) {
      tokens.add('exam_bursluluk');
    }

    if (tokens.isEmpty) {
      final alnum = normAlnum(raw);
      if (alnum.isNotEmpty) tokens.add(alnum);
    }
    return tokens;
  }

  static bool classLevelsCompatible(String a, String b) {
    if (a.trim().isEmpty || b.trim().isEmpty) return true;
    final ta = expandClassTokens(a);
    final tb = expandClassTokens(b);
    if (ta.isEmpty || tb.isEmpty) return true;
    return ta.intersection(tb).isNotEmpty;
  }

  /// Deneme sınavının okul türünün izinli sınıf seviyeleriyle uyumlu olup olmadığını kontrol eder.
  static bool examMatchesAllowedGrades({
    required List<String>? allowedGrades,
    required String classLevel,
    String examName = '',
    String examTypeName = '',
  }) {
    if (allowedGrades == null || allowedGrades.isEmpty) return true;
    final List<String> probes = [];
    if (classLevel.trim().isNotEmpty) {
      probes.add(classLevel.trim());
    }
    if (examTypeName.trim().isNotEmpty) {
      final tn = normTr(examTypeName);
      if (tn.contains('lgs') ||
          tn.contains('tyt') ||
          tn.contains('ayt') ||
          tn.contains('yks') ||
          tn.contains('ydt') ||
          RegExp(r'(1[0-2]|[1-9])\.\s*sinif').hasMatch(tn)) {
        probes.add(examTypeName.trim());
      }
    }
    if (examName.trim().isNotEmpty) {
      final en = normTr(examName);
      final sinifMatch = RegExp(
        r'(1[0-2]|[1-9])\.\s*sinif',
      ).firstMatch(en)?.group(0);
      if (sinifMatch != null) probes.add(sinifMatch);
      for (final kw in const ['lgs', 'tyt', 'ayt', 'yks', 'ydt']) {
        if (en.contains(kw)) probes.add(kw);
      }
    }
    if (probes.isEmpty) return true;
    for (final g in allowedGrades) {
      for (final p in probes) {
        if (classLevelsCompatible(g, p)) return true;
      }
    }
    return false;
  }

  static String buildOutcomeKey(String subject, String outcome) {
    final s = normAlnum(canonicalSubject(subject));
    final o = normAlnum(outcome);
    return '$s::${o.isEmpty ? 'genel' : o}';
  }

  static bool outcomesMatch(String a, String b) {
    final ra = GercekKazanimMapper.resolve(outcome: a);
    final rb = GercekKazanimMapper.resolve(outcome: b);
    if (ra.code.isNotEmpty && rb.code.isNotEmpty && ra.code == rb.code) {
      return true;
    }
    final na = normAlnum(ra.outcome.isNotEmpty ? ra.outcome : a);
    final nb = normAlnum(rb.outcome.isNotEmpty ? rb.outcome : b);
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    if (na.length >= 12 && nb.length >= 12) {
      if (na.contains(nb) || nb.contains(na)) return true;
    }
    return false;
  }

  static int subjectSortRank(String subject) {
    const order = [
      'Türkçe',
      'Matematik',
      'Geometri',
      'Fen Bilimleri',
      'Sosyal Bilgiler',
      'T.C. İnkılap Tarihi',
      'Din Kültürü ve Ahlak Bilgisi',
      'İngilizce',
      'Türk Dili ve Edebiyatı',
      'Fizik',
      'Kimya',
      'Biyoloji',
      'Tarih',
      'Coğrafya',
      'Felsefe',
    ];
    final canon = canonicalSubject(subject);
    final idx = order.indexOf(canon);
    return idx == -1 ? 999 : idx;
  }
}

/// Öğrencinin tek bir (Branş, Kazanım) bazındaki istatistiği.
class OutcomeMasteryStat {
  final String key;
  final String subject;
  final String outcome;
  int totalAsked;
  int correct;
  int wrong;
  int empty;

  OutcomeMasteryStat({
    required this.key,
    required this.subject,
    required this.outcome,
    this.totalAsked = 0,
    this.correct = 0,
    this.wrong = 0,
    this.empty = 0,
  });

  double get masteryPercent =>
      totalAsked > 0 ? (correct / totalAsked * 100.0).clamp(0.0, 100.0) : 0.0;

  MasteryBand get band => MasteryBandExt.fromPercent(masteryPercent);
}

/// Öğrencinin branş bazlı toplam özeti.
class SubjectSummaryStat {
  final String subject;
  int total;
  int correct;
  int wrong;
  int empty;

  SubjectSummaryStat({
    required this.subject,
    this.total = 0,
    this.correct = 0,
    this.wrong = 0,
    this.empty = 0,
  });

  double get net => (correct - (wrong / 3.0)).clamp(0.0, total.toDouble());

  double get masteryPercent =>
      total > 0 ? (correct / total * 100.0).clamp(0.0, 100.0) : 0.0;
}

/// Öğrencinin seçili sınavlardaki tüm kazanım ve seviye profili.
class StudentMasteryProfile {
  final String id;
  final String name;
  final String studentNo;
  final String tcNo;
  final String classLevel;
  final String branch;
  final List<String> participatedExamIds;
  final List<String> participatedExamNames;
  final Map<String, OutcomeMasteryStat> outcomeStats;
  final Map<String, SubjectSummaryStat> subjectStats;

  /// Öğrencinin sınavlarda ZATEN DOĞRU cevapladığı soruların tekil anahtarları:
  /// `${examId}_${normSubject}_${masterQNo}`
  final Set<String> answeredCorrectKeys;

  /// Öğrencinin sınavlarda YANLIŞ veya BOŞ bıraktığı soruların tekil anahtarları.
  final Set<String> answeredWrongOrEmptyKeys;

  int totalAsked;
  int totalCorrect;
  int totalWrong;
  int totalEmpty;

  StudentMasteryProfile({
    required this.id,
    required this.name,
    required this.studentNo,
    required this.tcNo,
    required this.classLevel,
    required this.branch,
    List<String>? participatedExamIds,
    List<String>? participatedExamNames,
    Map<String, OutcomeMasteryStat>? outcomeStats,
    Map<String, SubjectSummaryStat>? subjectStats,
    Set<String>? answeredCorrectKeys,
    Set<String>? answeredWrongOrEmptyKeys,
    this.totalAsked = 0,
    this.totalCorrect = 0,
    this.totalWrong = 0,
    this.totalEmpty = 0,
  }) : participatedExamIds = participatedExamIds ?? [],
       participatedExamNames = participatedExamNames ?? [],
       outcomeStats = outcomeStats ?? {},
       subjectStats = subjectStats ?? {},
       answeredCorrectKeys = answeredCorrectKeys ?? {},
       answeredWrongOrEmptyKeys = answeredWrongOrEmptyKeys ?? {};

  double get overallAbilityPercent => totalAsked > 0
      ? (totalCorrect / totalAsked * 100.0).clamp(0.0, 100.0)
      : 0.0;

  MasteryBand get overallBand =>
      MasteryBandExt.fromPercent(overallAbilityPercent);

  List<OutcomeMasteryStat> get weakestOutcomes {
    final list = outcomeStats.values.toList()
      ..sort((a, b) {
        final cmp = a.masteryPercent.compareTo(b.masteryPercent);
        if (cmp != 0) return cmp;
        return b.totalAsked.compareTo(a.totalAsked);
      });
    return list;
  }

  int get weakOutcomeCount =>
      outcomeStats.values.where((o) => o.masteryPercent < 60.0).length;

  int get fullMasteryOutcomeCount =>
      outcomeStats.values.where((o) => o.masteryPercent >= 99.9).length;
}

/// Soru havuzundan yüklenen tekil soru modeli.
class PoolQuestionItem {
  final String poolKey; // "${containerExamId}/${docId}"
  final String examId;
  final String examName;
  final String docId;
  final String subject;
  final String rawSubject;
  final String outcome;
  final String normalizedOutcomeKey;
  final String classLevel;
  final int questionNo;
  final String correctAnswer;
  final double difficulty; // 0..100 (% doğru oranı: yüksek=kolay, düşük=zor)
  final bool isWide;
  final bool isCritical;
  final String? base64Image;
  final String? imageUrl;
  final String? driveFileId;
  final String? k12Code;
  final String? kazanimCode;
  final String? legacyOutcome;
  final String? passageId;
  final String? passageBase64;
  final bool isCentralPool;
  final String questionType;
  final String sourceType;

  /// Önbelleğe alınmış görsel baytları ve en/boy oranı (`height / width`).
  Uint8List? cachedImageBytes;
  Uint8List? cachedPassageBytes;
  double? cachedAspectRatio;
  double? cachedPassageAspectRatio;

  PoolQuestionItem({
    required this.poolKey,
    required this.examId,
    required this.examName,
    required this.docId,
    required this.subject,
    required this.rawSubject,
    required this.outcome,
    required this.normalizedOutcomeKey,
    required this.classLevel,
    required this.questionNo,
    required this.correctAnswer,
    this.difficulty = 50.0,
    this.isWide = false,
    this.isCritical = false,
    this.base64Image,
    this.imageUrl,
    this.driveFileId,
    this.k12Code,
    this.kazanimCode,
    this.legacyOutcome,
    this.passageId,
    this.passageBase64,
    this.isCentralPool = false,
    this.questionType = 'Çoktan Seçmeli',
    this.sourceType = '',
  });

  /// Egzersiz / Etkinlik sorusu mu?
  bool get isExerciseQuestion {
    final t = FokusTextUtils.normTr(questionType);
    return t.contains('egzersiz') || t.contains('etkinlik');
  }

  /// Deneme sınavı (Hata Kitapçığı) sorusu mu?
  bool get isTrialExamQuestion {
    if (isExerciseQuestion) return false;
    final src = sourceType.trim().toLowerCase();
    if (src == 'google_sheets' || src == 'pool_manual') return false;
    if (docId.startsWith('sheet_')) return false;
    final eid = examId.trim();
    if (eid.isNotEmpty &&
        !eid.startsWith('pool_') &&
        !eid.startsWith('inst_qpool_')) {
      return true;
    }
    if (isCentralPool &&
        !eid.startsWith('pool_') &&
        !eid.startsWith('inst_qpool_')) {
      return true;
    }
    final eName = FokusTextUtils.normTr(examName);
    if (eName.contains('deneme')) return true;
    return false;
  }

  /// Fokus Kitap şablonundaki Egzersiz / Deneme anahtarlarına göre bu soru kullanılabilir mi?
  bool isAllowedByConfig(PersonalizedBookConfig config) {
    if (isExerciseQuestion) return config.includeExerciseQuestions;
    if (isTrialExamQuestion) return config.includeTrialExamQuestions;
    return true;
  }

  bool matchesOutcomeTextOrK12(String targetOutcome) {
    final resolvedSelf = GercekKazanimMapper.resolve(
      outcome: outcome,
      kazanimCode: kazanimCode,
      k12Code: k12Code,
      legacyOutcome: legacyOutcome,
    );
    final resolvedTarget = GercekKazanimMapper.resolve(outcome: targetOutcome);
    if (resolvedSelf.code.isNotEmpty &&
        resolvedTarget.code.isNotEmpty &&
        resolvedSelf.code == resolvedTarget.code) {
      return true;
    }
    if (FokusTextUtils.outcomesMatch(outcome, targetOutcome)) return true;
    if (legacyOutcome != null &&
        legacyOutcome!.trim().isNotEmpty &&
        FokusTextUtils.outcomesMatch(legacyOutcome!, targetOutcome)) {
      return true;
    }
    if (k12Code != null &&
        k12Code!.trim().isNotEmpty &&
        targetOutcome.trim() == k12Code!.trim()) {
      return true;
    }
    if (kazanimCode != null &&
        kazanimCode!.trim().isNotEmpty &&
        FokusTextUtils.normAlnum(targetOutcome)
            .startsWith(FokusTextUtils.normAlnum(kazanimCode!))) {
      return true;
    }
    return false;
  }

  /// Öğrencinin sınavda yanıtladığı soruyla eşleştirmek için anahtar.
  String get examQuestionIdentity =>
      '${examId}_${FokusTextUtils.normAlnum(subject)}_$questionNo';
}

/// Seçili denemelerdeki her bir (Branş, Kazanım) satırı ve öğretmen kuralları.
class ExamOutcomeTopicRule {
  final String key;
  final String subject;
  final String outcome;
  final int examQuestionCount;
  int poolExactCount;
  int poolSubjectTotalCount;
  final double avgClassMastery;
  int minQuestions;
  bool isEnabled;

  ExamOutcomeTopicRule({
    required this.key,
    required this.subject,
    required this.outcome,
    required this.examQuestionCount,
    required this.poolExactCount,
    required this.poolSubjectTotalCount,
    required this.avgClassMastery,
    this.minQuestions = 0,
    this.isEnabled = true,
  });
}

/// Canlı Sayfa Bütçesi (Page Budget) dağılımı.
class PageBudgetBreakdown {
  final int targetPageCount;
  final int coverPages;
  final int prefacePages;
  final int tocPages;
  final int answerKeyPages;

  const PageBudgetBreakdown({
    required this.targetPageCount,
    required this.coverPages,
    required this.prefacePages,
    required this.tocPages,
    required this.answerKeyPages,
  });

  int get fixedPages => coverPages + prefacePages + tocPages + answerKeyPages;

  int get remainingQuestionPages => targetPageCount - fixedPages;

  bool get isValid => remainingQuestionPages >= 1;
}

/// Fokus Kitap tasarım ve üretim şablonu.
class PersonalizedBookConfig {
  static const String defaultPrefaceBody =
      'Bu kitap, katıldığın deneme sınavlarındaki yanıtların yapay zeka destekli '
      'kazanım analiz motoru tarafından tek tek incelenerek yalnızca senin için '
      'hazırlandı.\n\n'
      'Güçlü olduğun konularda gereksiz soru tekrarı yapmak yerine, gelişime açık '
      'olduğun {zayifKonular} başta olmak üzere tüm öncelikli kazanımların senin '
      'mevcut başarı seviyene uygun zorluk derecesindeki sorularla bir araya getirildi.\n\n'
      'Her bir soruyu dikkatle çözmeni, takıldığın kazanımları öğretmenlerinle '
      'paylaşmanı ve hedeflerine kararlılıkla yürümeni diliyoruz. Başarı seninle olsun!';

  String id;
  String templateName;
  String institutionId;
  String schoolTypeId;
  List<String> selectedExamIds;
  List<String> selectedExamNames;

  // Sayfa yapısı
  int targetPageCount;
  bool padShortBooksWithStudyNotes;

  // Kapak ayarları
  bool includeCover;
  CoverThemePreset coverTheme;
  String bookTitle;
  String bookSubtitle;
  String institutionDisplayName;
  Uint8List? customCoverImageBytes;
  String? customCoverImageName;

  // Ön söz ayarları
  PrefaceMode prefaceMode;
  String manualPrefaceTitle;
  String manualPrefaceBody;
  String manualPrefaceAuthor;
  List<Uint8List> uploadedPrefacePagePngs;
  String? uploadedPrefaceFileName;
  int uploadedPrefacePageCount;

  // İçindekiler & Cevap Anahtarı
  bool includeToc;
  bool includeAnswerKey;

  bool get includeTableOfContents => includeToc;

  // Kazanım & Adaptif Zorluk kuralları (5 Kademeli: Çok Kolay, Kolay, Orta, Zor, Çok Zor)
  bool skipZeroMinOnHighMastery;
  double highMasteryZeroThreshold; // Varsayılan 100.0 (%100 başarıda 0 soru)
  bool allowSubjectFallbackWhenOutcomePoolShort;
  bool includeExerciseQuestions; // Varsayılan false (Egzersiz sorularını da ekle)
  bool includeTrialExamQuestions; // Varsayılan false (Deneme sorularını da ekle)
  double veryEasyDifficultyWeight;
  double easyDifficultyWeight;
  double mediumDifficultyWeight;
  double hardDifficultyWeight;
  double veryHardDifficultyWeight;
  Map<String, int> minQuestionsByOutcomeKey;
  Set<String> disabledOutcomeKeys;

  DateTime createdAt;

  PersonalizedBookConfig({
    this.id = '',
    this.templateName = 'Standart Fokus Kitap Şablonu',
    required this.institutionId,
    required this.schoolTypeId,
    List<String>? selectedExamIds,
    List<String>? selectedExamNames,
    this.targetPageCount = 24,
    this.padShortBooksWithStudyNotes = true,
    this.includeCover = true,
    this.coverTheme = CoverThemePreset.midnightAcademic,
    this.bookTitle = 'FOKUS KİTAP',
    this.bookSubtitle =
        'Kişiye Özel Akıllı Soru Bankası & Kazanım Güçlendirme Kitabı',
    this.institutionDisplayName = 'eduKN Eğitim Kurumları',
    this.customCoverImageBytes,
    this.customCoverImageName,
    this.prefaceMode = PrefaceMode.manual,
    this.manualPrefaceTitle = 'Sevgili {ogrenci},',
    this.manualPrefaceBody = defaultPrefaceBody,
    this.manualPrefaceAuthor = 'Ölçme ve Değerlendirme Birimi',
    List<Uint8List>? uploadedPrefacePagePngs,
    this.uploadedPrefaceFileName,
    this.uploadedPrefacePageCount = 0,
    this.includeToc = true,
    this.includeAnswerKey = true,
    this.skipZeroMinOnHighMastery = true,
    this.highMasteryZeroThreshold = 100.0,
    this.allowSubjectFallbackWhenOutcomePoolShort = true,
    this.includeExerciseQuestions = false,
    this.includeTrialExamQuestions = false,
    this.veryEasyDifficultyWeight = 1.0,
    this.easyDifficultyWeight = 1.0,
    this.mediumDifficultyWeight = 1.0,
    this.hardDifficultyWeight = 1.0,
    this.veryHardDifficultyWeight = 1.0,
    Map<String, int>? minQuestionsByOutcomeKey,
    Set<String>? disabledOutcomeKeys,
    DateTime? createdAt,
  }) : selectedExamIds = selectedExamIds ?? [],
       selectedExamNames = selectedExamNames ?? [],
       uploadedPrefacePagePngs = uploadedPrefacePagePngs ?? [],
       minQuestionsByOutcomeKey = minQuestionsByOutcomeKey ?? {},
       disabledOutcomeKeys = disabledOutcomeKeys ?? {},
       createdAt = createdAt ?? DateTime.now();

  /// 0..100 zorluk puanına göre 5 kademeli ağırlık çarpanını döner:
  /// 81-100: Çok Kolay, 61-80: Kolay, 41-60: Orta, 21-40: Zor, 0-20: Çok Zor.
  double weightForDifficulty(double difficulty) {
    if (difficulty >= 81.0) return veryEasyDifficultyWeight;
    if (difficulty >= 61.0) return easyDifficultyWeight;
    if (difficulty >= 41.0) return mediumDifficultyWeight;
    if (difficulty >= 21.0) return hardDifficultyWeight;
    return veryHardDifficultyWeight;
  }

  static const int kTocRowsPerPage = 24;

  PageBudgetBreakdown computeBudget({
    int estimatedTocEntries = 18,
    int estimatedTotalQuestions = 80,
    List<int>? subjectQuestionCounts,
  }) {
    final int cover = includeCover ? 1 : 0;
    int preface = 0;
    if (prefaceMode == PrefaceMode.manual) {
      preface = 1;
    } else if (prefaceMode == PrefaceMode.uploadedPdf) {
      preface = uploadedPrefacePagePngs.isNotEmpty
          ? uploadedPrefacePagePngs.length
          : uploadedPrefacePageCount;
    }
    final int toc = includeTableOfContents
        ? math.max(1, (estimatedTocEntries / kTocRowsPerPage).ceil())
        : 0;
    final List<int> countsForAns =
        (subjectQuestionCounts != null && subjectQuestionCounts.isNotEmpty)
        ? subjectQuestionCounts
        : FokusLayoutLimits.synthesizeSubjectCounts(estimatedTotalQuestions);
    final int ans = FokusLayoutLimits.computeAnswerKeyPageCountFromCounts(
      includeAnswerKey: includeAnswerKey,
      subjectQuestionCounts: countsForAns,
    );
    return PageBudgetBreakdown(
      targetPageCount: targetPageCount,
      coverPages: cover,
      prefacePages: preface,
      tocPages: toc,
      answerKeyPages: ans,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'templateName': templateName,
      'institutionId': institutionId,
      'schoolTypeId': schoolTypeId,
      'selectedExamIds': selectedExamIds,
      'selectedExamNames': selectedExamNames,
      'targetPageCount': targetPageCount,
      'padShortBooksWithStudyNotes': padShortBooksWithStudyNotes,
      'includeCover': includeCover,
      'coverTheme': coverTheme.key,
      'bookTitle': bookTitle,
      'bookSubtitle': bookSubtitle,
      'institutionDisplayName': institutionDisplayName,
      'customCoverImageName': customCoverImageName,
      'prefaceMode': prefaceMode == PrefaceMode.uploadedPdf
          ? PrefaceMode.manual.key
          : prefaceMode.key,
      'manualPrefaceTitle': manualPrefaceTitle,
      'manualPrefaceBody': manualPrefaceBody,
      'manualPrefaceAuthor': manualPrefaceAuthor,
      'includeToc': includeToc,
      'includeAnswerKey': includeAnswerKey,
      'skipZeroMinOnHighMastery': skipZeroMinOnHighMastery,
      'highMasteryZeroThreshold': highMasteryZeroThreshold,
      'allowSubjectFallbackWhenOutcomePoolShort':
          allowSubjectFallbackWhenOutcomePoolShort,
      'includeExerciseQuestions': includeExerciseQuestions,
      'includeTrialExamQuestions': includeTrialExamQuestions,
      'veryEasyDifficultyWeight': veryEasyDifficultyWeight,
      'easyDifficultyWeight': easyDifficultyWeight,
      'mediumDifficultyWeight': mediumDifficultyWeight,
      'hardDifficultyWeight': hardDifficultyWeight,
      'veryHardDifficultyWeight': veryHardDifficultyWeight,
      'minQuestionsByOutcomeKey': minQuestionsByOutcomeKey,
      'disabledOutcomeKeys': disabledOutcomeKeys.toList(),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory PersonalizedBookConfig.fromMap(Map<String, dynamic> map, String id) {
    final rawMin = map['minQuestionsByOutcomeKey'];
    final parsedMin = <String, int>{};
    if (rawMin is Map) {
      rawMin.forEach((k, v) {
        parsedMin[k.toString()] = (num.tryParse('$v') ?? 0).toInt();
      });
    }
    final rawDisabled = map['disabledOutcomeKeys'];
    final parsedDisabled = <String>{};
    if (rawDisabled is List) {
      for (final item in rawDisabled) {
        parsedDisabled.add(item.toString());
      }
    }
    return PersonalizedBookConfig(
      id: id,
      templateName: (map['templateName'] ?? 'Kayıtlı Şablon').toString(),
      institutionId: (map['institutionId'] ?? '').toString(),
      schoolTypeId: (map['schoolTypeId'] ?? '').toString(),
      selectedExamIds: (map['selectedExamIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      selectedExamNames: (map['selectedExamNames'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      targetPageCount: (map['targetPageCount'] as num?)?.toInt() ?? 24,
      padShortBooksWithStudyNotes: map['padShortBooksWithStudyNotes'] != false,
      includeCover: map['includeCover'] != false,
      coverTheme: CoverThemePresetExt.fromKey(map['coverTheme']?.toString()),
      bookTitle: (map['bookTitle'] ?? 'FOKUS KİTAP').toString(),
      bookSubtitle:
          (map['bookSubtitle'] ??
                  'Kişiye Özel Akıllı Soru Bankası & Kazanım Güçlendirme Kitabı')
              .toString(),
      institutionDisplayName:
          (map['institutionDisplayName'] ?? 'eduKN Eğitim Kurumları')
              .toString(),
      customCoverImageName: map['customCoverImageName']?.toString(),
      prefaceMode: PrefaceModeExt.fromKey(map['prefaceMode']?.toString()),
      manualPrefaceTitle: (map['manualPrefaceTitle'] ?? 'Sevgili {ogrenci},')
          .toString(),
      manualPrefaceBody: (map['manualPrefaceBody'] ?? defaultPrefaceBody)
          .toString(),
      manualPrefaceAuthor:
          (map['manualPrefaceAuthor'] ?? 'Ölçme ve Değerlendirme Birimi')
              .toString(),
      includeToc: map['includeToc'] != false,
      includeAnswerKey: map['includeAnswerKey'] != false,
      skipZeroMinOnHighMastery: map['skipZeroMinOnHighMastery'] != false,
      highMasteryZeroThreshold:
          (map['highMasteryZeroThreshold'] as num?)?.toDouble() ?? 100.0,
      allowSubjectFallbackWhenOutcomePoolShort:
          map['allowSubjectFallbackWhenOutcomePoolShort'] != false,
      includeExerciseQuestions: map['includeExerciseQuestions'] == true,
      includeTrialExamQuestions: map['includeTrialExamQuestions'] == true,
      veryEasyDifficultyWeight:
          ((map['veryEasyDifficultyWeight'] as num?)?.toDouble() ??
                  (map['easyDifficultyWeight'] as num?)?.toDouble() ??
                  1.0)
              .clamp(0.2, 2.0),
      easyDifficultyWeight:
          ((map['easyDifficultyWeight'] as num?)?.toDouble() ?? 1.0).clamp(
            0.2,
            2.0,
          ),
      mediumDifficultyWeight:
          ((map['mediumDifficultyWeight'] as num?)?.toDouble() ?? 1.0).clamp(
            0.2,
            2.0,
          ),
      hardDifficultyWeight:
          ((map['hardDifficultyWeight'] as num?)?.toDouble() ?? 1.0).clamp(
            0.2,
            2.0,
          ),
      veryHardDifficultyWeight:
          ((map['veryHardDifficultyWeight'] as num?)?.toDouble() ??
                  (map['hardDifficultyWeight'] as num?)?.toDouble() ??
                  1.0)
              .clamp(0.2, 2.0),
      minQuestionsByOutcomeKey: parsedMin,
      disabledOutcomeKeys: parsedDisabled,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Üretim geçmişi kaydı (`institutions/{institutionId}/personalized_books`).
class PersonalizedBookHistoryRecord {
  final String id;
  final String institutionId;
  final String bookTitle;
  final List<String> examNames;
  final int studentCount;
  final int targetPageCount;
  final String exportMode; // 'single', 'zip', 'combined_pdf'
  final String coverThemeKey;
  final DateTime createdAt;

  PersonalizedBookHistoryRecord({
    required this.id,
    this.institutionId = '',
    required this.bookTitle,
    required this.examNames,
    required this.studentCount,
    required this.targetPageCount,
    required this.exportMode,
    required this.coverThemeKey,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'institutionId': institutionId,
    'bookTitle': bookTitle,
    'examNames': examNames,
    'studentCount': studentCount,
    'targetPageCount': targetPageCount,
    'exportMode': exportMode,
    'coverThemeKey': coverThemeKey,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory PersonalizedBookHistoryRecord.fromMap(
    Map<String, dynamic> map,
    String id,
  ) {
    return PersonalizedBookHistoryRecord(
      id: id,
      institutionId: (map['institutionId'] ?? '').toString(),
      bookTitle: (map['bookTitle'] ?? 'FOKUS KİTAP').toString(),
      examNames: (map['examNames'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      studentCount: (map['studentCount'] as num?)?.toInt() ?? 1,
      targetPageCount: (map['targetPageCount'] as num?)?.toInt() ?? 24,
      exportMode: (map['exportMode'] ?? 'single').toString(),
      coverThemeKey: (map['coverThemeKey'] ?? 'midnight_academic').toString(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Kitap içindekiler (TOC) satırı — gerçek sayfa numarası ile.
class TocEntryItem {
  final String subject;
  final String outcome;
  final int questionCount;
  final double? studentMasteryPercent;
  final int startPageNumber;
  final bool isSubjectFirstEntry;

  const TocEntryItem({
    required this.subject,
    required this.outcome,
    required this.questionCount,
    required this.studentMasteryPercent,
    required this.startPageNumber,
    required this.isSubjectFirstEntry,
  });
}

/// Cevap Anahtarı tekil kutu bloğu (100 soruyu aşan branşlar otomatik bölünür).
class AnswerKeyBlockPlan {
  final String subject;
  final String titleLabel;
  final List<PlacedBookQuestion> questions;
  final double estimatedHeight;

  const AnswerKeyBlockPlan({
    required this.subject,
    required this.titleLabel,
    required this.questions,
    required this.estimatedHeight,
  });
}

/// TOC ve Cevap Anahtarı deterministik sayfalama sabitleri & yardımcıları.
class FokusLayoutLimits {
  static const int kTocRowsPerPage = 24;
  static const int kAnswerKeyMaxSubjectSlice = 100;
  static const int kAnswerKeyMaxCellsPerPage = 120;
  static const double kAnswerKeyMaxPageHeight = 680.0;

  static int computeTocPageCount({
    required bool includeToc,
    required int entryCount,
  }) {
    if (!includeToc) return 0;
    return math.max(1, (entryCount / kTocRowsPerPage).ceil());
  }

  /// 10 hücre/satır üzerinden tek bir cevap anahtarı bloğunun dikey yüksekliğini hesaplar.
  static double estimateAnswerBlockHeight(int cellCount) {
    final int rows = math.max(1, (cellCount / 10).ceil());
    return 58.0 + (rows * 22.0);
  }

  static List<int> synthesizeSubjectCounts(int estimatedTotalQuestions) {
    if (estimatedTotalQuestions <= 0) return const [];
    if (estimatedTotalQuestions <= 40) return [estimatedTotalQuestions];
    const int estSubjects = 4;
    final int base = estimatedTotalQuestions ~/ estSubjects;
    final int rem = estimatedTotalQuestions % estSubjects;
    return List<int>.generate(estSubjects, (i) => base + (i < rem ? 1 : 0));
  }

  static int computeAnswerKeyPageCountFromCounts({
    required bool includeAnswerKey,
    required List<int> subjectQuestionCounts,
  }) {
    if (!includeAnswerKey) return 0;
    final List<int> sliceCounts = [];
    for (final rawCount in subjectQuestionCounts) {
      if (rawCount <= 0) continue;
      int rem = rawCount;
      while (rem > 0) {
        final take = math.min(rem, kAnswerKeyMaxSubjectSlice);
        sliceCounts.add(take);
        rem -= take;
      }
    }
    if (sliceCounts.isEmpty) return 1;

    int pages = 1;
    double curHeight = 0.0;
    int curCells = 0;
    for (final count in sliceCounts) {
      final h = estimateAnswerBlockHeight(count);
      if (curCells > 0 &&
          (curHeight + h > kAnswerKeyMaxPageHeight ||
              curCells + count > kAnswerKeyMaxCellsPerPage)) {
        pages++;
        curHeight = 0.0;
        curCells = 0;
      }
      curHeight += h;
      curCells += count;
    }
    return pages;
  }

  static List<List<AnswerKeyBlockPlan>> paginateAnswerKeyBlocks(
    Map<String, List<PlacedBookQuestion>> questionsBySubject,
  ) {
    final subjects = questionsBySubject.keys.toList()
      ..sort((a, b) {
        final rCmp = FokusTextUtils.subjectSortRank(
          a,
        ).compareTo(FokusTextUtils.subjectSortRank(b));
        return rCmp != 0 ? rCmp : a.compareTo(b);
      });

    final List<AnswerKeyBlockPlan> allBlocks = [];
    for (final sub in subjects) {
      final qList = questionsBySubject[sub];
      if (qList == null || qList.isEmpty) continue;
      if (qList.length <= kAnswerKeyMaxSubjectSlice) {
        allBlocks.add(
          AnswerKeyBlockPlan(
            subject: sub,
            titleLabel: '${sub.toUpperCase()} (${qList.length} SORU)',
            questions: qList,
            estimatedHeight: estimateAnswerBlockHeight(qList.length),
          ),
        );
      } else {
        for (
          int start = 0;
          start < qList.length;
          start += kAnswerKeyMaxSubjectSlice
        ) {
          final int end = math.min(
            qList.length,
            start + kAnswerKeyMaxSubjectSlice,
          );
          final slice = qList.sublist(start, end);
          final int firstNo = slice.first.sequenceNoInSubject > 0
              ? slice.first.sequenceNoInSubject
              : (start + 1);
          final int lastNo = slice.last.sequenceNoInSubject > 0
              ? slice.last.sequenceNoInSubject
              : end;
          allBlocks.add(
            AnswerKeyBlockPlan(
              subject: sub,
              titleLabel: '${sub.toUpperCase()} ($firstNo-$lastNo)',
              questions: slice,
              estimatedHeight: estimateAnswerBlockHeight(slice.length),
            ),
          );
        }
      }
    }

    if (allBlocks.isEmpty) {
      return const [<AnswerKeyBlockPlan>[]];
    }

    final List<List<AnswerKeyBlockPlan>> pages = [];
    List<AnswerKeyBlockPlan> curPage = [];
    double curHeight = 0.0;
    int curCells = 0;

    for (final block in allBlocks) {
      final int c = block.questions.length;
      if (curPage.isNotEmpty &&
          (curHeight + block.estimatedHeight > kAnswerKeyMaxPageHeight ||
              curCells + c > kAnswerKeyMaxCellsPerPage)) {
        pages.add(curPage);
        curPage = [];
        curHeight = 0.0;
        curCells = 0;
      }
      curPage.add(block);
      curHeight += block.estimatedHeight;
      curCells += c;
    }
    if (curPage.isNotEmpty) {
      pages.add(curPage);
    }
    return pages;
  }
}

/// Bir soru sayfası içerisindeki blok türleri.
enum QuestionBlockKind {
  twoColumnSection,
  wideQuestion,
  sharedPassageGroup,
  studyNotesPad,
}

/// Kitaptaki yerleştirilmiş tekil soru örneği (sıra numarası atanmış).
class PlacedBookQuestion {
  final PoolQuestionItem item;
  final String subject;
  final String outcome;
  final double? studentOutcomeMastery;
  int sequenceNoInSubject;

  PlacedBookQuestion({
    required this.item,
    required this.subject,
    required this.outcome,
    required this.studentOutcomeMastery,
    this.sequenceNoInSubject = 1,
  });
}

/// Sayfa içine yerleştirilmiş tek bir görsel dizgi bloğu.
class PackedPageBlock {
  final QuestionBlockKind kind;
  final String subject;
  final String outcome;
  final bool showSubjectBanner;
  final bool showOutcomeRibbon;
  final double? studentOutcomeMastery;
  final List<PlacedBookQuestion> leftColumn;
  final List<PlacedBookQuestion> rightColumn;
  final List<PlacedBookQuestion> fullWidthQuestions;
  final double allocatedHeight;

  const PackedPageBlock({
    required this.kind,
    required this.subject,
    required this.outcome,
    this.showSubjectBanner = false,
    this.showOutcomeRibbon = false,
    this.studentOutcomeMastery,
    this.leftColumn = const [],
    this.rightColumn = const [],
    this.fullWidthQuestions = const [],
    required this.allocatedHeight,
  });
}

/// Birebir 1 fiziksel A4 sayfasına karşılık gelen paketlenmiş soru sayfası.
class PackedQuestionPage {
  final String primarySubject;
  final List<PackedPageBlock> blocks;
  final bool isStudyNotePadPage;

  const PackedQuestionPage({
    required this.primarySubject,
    required this.blocks,
    this.isStudyNotePadPage = false,
  });
}

/// Bir öğrenci için üretilen tüm kitabın iki aşamalı (two-pass) sayfa planı.
class StudentBookPlan {
  final StudentMasteryProfile student;
  final int coverPages;
  final int prefacePages;
  final int tocPages;
  final int questionPagesCount;
  final int studyNotePadPagesCount;
  final int answerKeyPages;
  final int totalPages;
  final int totalQuestionCount;
  final int skippedMasteredOutcomeCount;
  final List<TocEntryItem> tocEntries;
  final int? answerKeyStartPage;
  final List<PackedQuestionPage> packedPages;
  final Map<String, List<PlacedBookQuestion>> questionsBySubject;
  final List<List<AnswerKeyBlockPlan>> answerKeyPageBlocks;

  const StudentBookPlan({
    required this.student,
    required this.coverPages,
    required this.prefacePages,
    required this.tocPages,
    required this.questionPagesCount,
    required this.studyNotePadPagesCount,
    required this.answerKeyPages,
    required this.totalPages,
    required this.totalQuestionCount,
    required this.skippedMasteredOutcomeCount,
    required this.tocEntries,
    required this.answerKeyStartPage,
    required this.packedPages,
    required this.questionsBySubject,
    this.answerKeyPageBlocks = const [],
  });

  PageBudgetBreakdown get budget => PageBudgetBreakdown(
    targetPageCount: totalPages,
    coverPages: coverPages,
    prefacePages: prefacePages,
    tocPages: tocPages,
    answerKeyPages: answerKeyPages,
  );
}
