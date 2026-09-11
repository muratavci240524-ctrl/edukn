import 'dart:math';
import 'package:flutter/material.dart';
import '../models/school/student_grouping_model.dart';

/// Akıllı Öğrenci Gruplama Servisi ve Dağıtım Algoritmaları
class StudentGroupingService {
  /// Gruplara atanacak modern, canlı ve ayırt edici renk paleti
  static const List<Color> groupPalette = [
    Color(0xFF4F46E5), // İndigo / Gece Mavisi
    Color(0xFF059669), // Zümrüt Yeşili
    Color(0xFFD97706), // Kehribar Sarısı
    Color(0xFFDC2626), // Mercan Kırmızısı
    Color(0xFF0284C7), // Okyanus Mavisi
    Color(0xFF7C3AED), // Kraliyet Moru
    Color(0xFFDB2777), // Canlı Pembe
    Color(0xFF0D9488), // Teal / Turkuaz
    Color(0xFFEA580C), // Sıcak Turuncu
    Color(0xFF65A30D), // Fıstık Yeşili
    Color(0xFF475569), // Çelik Grisi
    Color(0xFF9333EA), // Fuşya Mor
  ];

  /// Öğrencileri belirlenen kurallara ve moda göre gruplara dağıtan ana fonksiyon.
  ///
  /// [students]: Sınıftaki tüm aktif öğrenciler.
  /// [targetGroupCount]: İstenen toplam grup sayısı.
  /// [mode]: [GroupingMode.random], [GroupingMode.balanced], [GroupingMode.tiered].
  /// [blacklistRules]: Birlikte aynı grupta olmaması gereken öğrenci çiftleri.
  /// [balanceGender]: Gruplar arası kız-erkek dengesini de gözetme opsiyonu.
  static List<StudentGroup> generateGroups({
    required List<GroupingStudent> students,
    required int targetGroupCount,
    required GroupingMode mode,
    List<BlacklistRule> blacklistRules = const [],
    List<String> spreadStudentIds = const [], // Haşarı / Enerjik ayrık dağıtılacak öğrenci ID'leri
    bool balanceGender = false,
  }) {
    if (students.isEmpty || targetGroupCount <= 0) return [];

    // İstenen grup sayısı öğrenci sayısından fazlaysa, grup sayısını öğrenci sayısına sınırla
    final actualGroupCount = min(targetGroupCount, students.length);

    // Boş grupları başlat
    final List<StudentGroup> groups = List.generate(actualGroupCount, (index) {
      final color = groupPalette[index % groupPalette.length];
      return StudentGroup(
        id: 'group_${index + 1}',
        groupName: '${index + 1}. Grup',
        groupColor: color,
        students: [],
      );
    });

    // Öğrenci listesinin bir kopyasını al (orijinal listeyi bozmamak için)
    final pool = students.map((s) => s.clone()).toList();

    // -------------------------------------------------------------------------
    // 0. ADIM: AYRIK DAĞITILACAK (HAŞARI / ENERJİK) ÖĞRENCİLERİ PAYLAŞTIR
    // -------------------------------------------------------------------------
    if (spreadStudentIds.isNotEmpty) {
      final spreadSet = spreadStudentIds.toSet();
      final spreadList = pool.where((s) => spreadSet.contains(s.id)).toList();
      pool.removeWhere((s) => spreadSet.contains(s.id));

      // Enerjik / haşarı öğrencileri gruplara döngüsel (round-robin) olarak eşit paylaştır
      for (int i = 0; i < spreadList.length; i++) {
        final targetGroupIndex = i % groups.length;
        groups[targetGroupIndex].students.add(spreadList[i]);
      }
    }

    // -------------------------------------------------------------------------
    // 1. DAĞITIM ADIMI (KALAN ÖĞRENCİLERİ SEÇİLEN MODA GÖRE GRUPLARA YERLEŞTİRME)
    // -------------------------------------------------------------------------
    switch (mode) {
      case GroupingMode.random:
        _distributeRandom(pool, groups);
        break;

      case GroupingMode.balanced:
        _distributeBalancedSerpentine(pool, groups, balanceGender);
        break;

      case GroupingMode.tiered:
        _distributeTiered(pool, groups);
        break;
    }

    // -------------------------------------------------------------------------
    // 2. KURAL (BİRLİKTE OLSUN / OLMASIN) KONTROLÜ VE DÜZELTME
    // -------------------------------------------------------------------------
    if (blacklistRules.isNotEmpty) {
      _resolveGroupingRules(groups, blacklistRules, mode);
    }

    return groups;
  }

  // ===========================================================================
  // ALGORİTMA 1: RASTGELE DAĞITIM (RANDOM)
  // ===========================================================================
  /// Öğrencileri tamamen karıştırır ve round-robin (döngüsel) sırayla
  /// gruplara birer birer paylaştırır. Artık öğrenciler de gruplara eşit dağılır.
  static void _distributeRandom(List<GroupingStudent> pool, List<StudentGroup> groups) {
    final random = Random();
    pool.shuffle(random);

    for (int i = 0; i < pool.length; i++) {
      final targetGroupIndex = i % groups.length;
      groups[targetGroupIndex].students.add(pool[i]);
    }
  }

  // ===========================================================================
  // ALGORİTMA 2: DENGELİ / HETEROJEN DAĞITIM (SERPENTINE / YILAN DRAFT)
  // ===========================================================================
  /// [Serpentine (Yılan) Draft Algoritması Mantığı]:
  /// 1. Tüm öğrenciler başarı puanlarına göre yüksekten düşüğe (azalan) sıralanır:
  ///    [100, 95, 90, 85, 80, 75, 70, 65, 60, 55, 50, 45...]
  ///
  /// 2. Gruplara dağıtım tek yönlü değil "YILAN (Zig-Zag)" şeklinde yapılır:
  ///    - 1. Tur (İleri): Grup 1 -> Grup 2 -> Grup 3 -> Grup 4
  ///      (En yüksek 4 puan sırasıyla gruplara verilir)
  ///    - 2. Tur (Geri): Grup 4 -> Grup 3 -> Grup 2 -> Grup 1
  ///      (Sıradaki en yüksek puan en zayıf kalan Grup 4'e verilerek denge korunur)
  ///    - 3. Tur (İleri): Grup 1 -> Grup 2 -> Grup 3 -> Grup 4
  ///    - 4. Tur (Geri): Grup 4 -> Grup 3 -> Grup 2 -> Grup 1
  ///
  /// Bu sayede her grupta hem en başarılı hem orta hem de desteğe ihtiyacı olan
  /// öğrenciler dengeli toplanır ve grupların not ortalamaları (GPA) neredeyse eşitlenir.
  static void _distributeBalancedSerpentine(
    List<GroupingStudent> pool,
    List<StudentGroup> groups,
    bool balanceGender,
  ) {
    if (balanceGender) {
      // Cinsiyet dengeli serpentine dağıtım
      final girls = pool.where((s) => s.isFemale).toList()
        ..sort((a, b) => b.academicScore.compareTo(a.academicScore));
      final boys = pool.where((s) => s.isMale).toList()
        ..sort((a, b) => b.academicScore.compareTo(a.academicScore));
      final others = pool.where((s) => !s.isFemale && !s.isMale).toList()
        ..sort((a, b) => b.academicScore.compareTo(a.academicScore));

      _applySerpentineToSublist(girls, groups);
      _applySerpentineToSublist(boys, groups);
      _applySerpentineToSublist(others, groups);
    } else {
      // Sadece akademik puana göre saf serpentine
      pool.sort((a, b) => b.academicScore.compareTo(a.academicScore));
      _applySerpentineToSublist(pool, groups);
    }
  }

  /// Bir alt öğrenci listesini yılan düzeninde gruplara paylaştırır
  static void _applySerpentineToSublist(List<GroupingStudent> sublist, List<StudentGroup> groups) {
    final groupCount = groups.length;
    if (groupCount == 0 || sublist.isEmpty) return;

    int currentGroupIdx = 0;
    bool movingForward = true;

    for (int i = 0; i < sublist.length; i++) {
      groups[currentGroupIdx].students.add(sublist[i]);

      if (movingForward) {
        if (currentGroupIdx == groupCount - 1) {
          // Son gruba ulaşıldı, yön değiştir ve aynı gruptan geri dön
          movingForward = false;
        } else {
          currentGroupIdx++;
        }
      } else {
        if (currentGroupIdx == 0) {
          // İlk gruba ulaşıldı, yön değiştir ve ileri devam et
          movingForward = true;
        } else {
          currentGroupIdx--;
        }
      }
    }
  }

  // ===========================================================================
  // ALGORİTMA 3: SEVİYE ODAKLI / HOMOJEN DAĞITIM (TIERED / SEVİYE KÜMELEME)
  // ===========================================================================
  /// [Tiered / Homojen Dağıtım Mantığı]:
  /// 1. Tüm öğrenciler başarı puanına göre azalan sırada sıralanır.
  /// 2. Grup kapasitesi hesaplanır (örn: 24 öğrenci / 4 grup = 6'şar kişi).
  /// 3. Grup 1'e en yüksek ilk N öğrenci (İleri Düzey), Grup 2'ye sonraki N öğrenci,
  ///    Grup 4'e ise desteğe ihtiyacı olan öğrenciler atanır.
  /// 4. Artık öğrenciler grupların kapasitelerine göre sırayla eklenir.
  static void _distributeTiered(List<GroupingStudent> pool, List<StudentGroup> groups) {
    pool.sort((a, b) => b.academicScore.compareTo(a.academicScore));

    final totalStudents = pool.length;
    final groupCount = groups.length;
    final baseSize = totalStudents ~/ groupCount;
    final remainder = totalStudents % groupCount;

    int studentIndex = 0;
    for (int g = 0; g < groupCount; g++) {
      // Artık öğrencileri ilk gruplara birer birer ekle
      final targetSizeForThisGroup = baseSize + (g < remainder ? 1 : 0);

      for (int i = 0; i < targetSizeForThisGroup && studentIndex < totalStudents; i++) {
        groups[g].students.add(pool[studentIndex]);
        studentIndex++;
      }
    }
  }

  // ===========================================================================
  // KURAL ÇÖZÜCÜ (BİRLİKTE OLSUN 🟢 & BİRLİKTE OLMASIN 🔴)
  // ===========================================================================
  static void _resolveGroupingRules(
    List<StudentGroup> groups,
    List<BlacklistRule> rules,
    GroupingMode mode,
  ) {
    if (groups.length <= 1) return;

    int maxIterations = 25;

    while (maxIterations > 0) {
      maxIterations--;
      bool changesMade = false;

      // 1. ÖNCE "BİRLİKTE OLSUN (TOGETHER / WHITELIST 🟢)" KURALLARINI ÇÖZ
      for (var rule in rules.where((r) => r.isTogether)) {
        int g1Idx = groups.indexWhere((g) => g.students.any((s) => s.id == rule.student1Id));
        int g2Idx = groups.indexWhere((g) => g.students.any((s) => s.id == rule.student2Id));

        if (g1Idx != -1 && g2Idx != -1 && g1Idx != g2Idx) {
          // Öğrenciler farklı gruplarda, bir araya getir
          final g1 = groups[g1Idx];
          final g2 = groups[g2Idx];

          final s2 = g2.students.firstWhere((s) => s.id == rule.student2Id);

          // g1'den s2 ile takas edilecek uygun bir öğrenci ara
          GroupingStudent? swapCandidate;
          for (var cand in g1.students) {
            if (cand.id == rule.student1Id) continue;
            // Takas bu kuralı veya başka bir kuralı bozar mı?
            final g2WouldCollide = _wouldCollideIfAdded(g2, cand, rules, ignoreStudentId: s2.id);
            final g1WouldCollide = _wouldCollideIfAdded(g1, s2, rules, ignoreStudentId: cand.id);

            if (!g2WouldCollide && !g1WouldCollide) {
              swapCandidate = cand;
              break;
            }
          }

          if (swapCandidate != null) {
            g2.students.removeWhere((s) => s.id == s2.id);
            g1.students.removeWhere((s) => s.id == swapCandidate!.id);

            g1.students.add(s2);
            g2.students.add(swapCandidate);
            changesMade = true;
          } else if (g1.students.length <= g2.students.length) {
            // Direkt taşı
            g2.students.removeWhere((s) => s.id == s2.id);
            g1.students.add(s2);
            changesMade = true;
          }
        }
      }

      // 2. SONRA "BİRLİKTE OLMASIN (APART / BLACKLIST 🔴)" KURALLARINI ÇÖZ
      for (int gIdx = 0; gIdx < groups.length; gIdx++) {
        final currentGroup = groups[gIdx];
        final apartCollisions = findApartCollisionsInGroup(currentGroup, rules);

        if (apartCollisions.isNotEmpty) {
          changesMade = true;
          final rule = apartCollisions.first;

          final studentToMove = currentGroup.students.firstWhere(
            (s) => s.id == rule.student2Id,
            orElse: () => currentGroup.students.firstWhere((s) => s.id == rule.student1Id),
          );

          int? bestTargetGroupIdx;
          int? bestSwapStudentIdx;
          double bestScoreDiff = double.infinity;

          for (int targetGIdx = 0; targetGIdx < groups.length; targetGIdx++) {
            if (targetGIdx == gIdx) continue;

            final targetGroup = groups[targetGIdx];

            // Direkt taşıma
            if (targetGroup.students.length < currentGroup.students.length) {
              final wouldCollide = _wouldCollideIfAdded(targetGroup, studentToMove, rules);
              if (!wouldCollide) {
                bestTargetGroupIdx = targetGIdx;
                bestSwapStudentIdx = null;
                break;
              }
            }

            // Takas
            for (int sIdx = 0; sIdx < targetGroup.students.length; sIdx++) {
              final candidateStudent = targetGroup.students[sIdx];

              final targetWouldCollide = _wouldCollideIfAdded(
                targetGroup,
                studentToMove,
                rules,
                ignoreStudentId: candidateStudent.id,
              );

              final sourceWouldCollide = _wouldCollideIfAdded(
                currentGroup,
                candidateStudent,
                rules,
                ignoreStudentId: studentToMove.id,
              );

              if (!targetWouldCollide && !sourceWouldCollide) {
                final scoreDiff = (candidateStudent.academicScore - studentToMove.academicScore).abs();
                if (scoreDiff < bestScoreDiff) {
                  bestScoreDiff = scoreDiff;
                  bestTargetGroupIdx = targetGIdx;
                  bestSwapStudentIdx = sIdx;
                }
              }
            }
          }

          if (bestTargetGroupIdx != null) {
            final targetGroup = groups[bestTargetGroupIdx];
            currentGroup.students.removeWhere((s) => s.id == studentToMove.id);

            if (bestSwapStudentIdx != null && bestSwapStudentIdx < targetGroup.students.length) {
              final swappedStudent = targetGroup.students.removeAt(bestSwapStudentIdx);
              currentGroup.students.add(swappedStudent);
            }
            targetGroup.students.add(studentToMove);
          }
        }
      }

      if (!changesMade) break;
    }
  }

  /// Verilen bir grupta "Birlikte Olmasın 🔴" kuralını ihlal eden çiftleri bulur
  static List<BlacklistRule> findApartCollisionsInGroup(
    StudentGroup group,
    List<BlacklistRule> rules,
  ) {
    final List<BlacklistRule> triggeredRules = [];
    final studentIds = group.students.map((s) => s.id).toSet();

    for (var rule in rules.where((r) => r.isApart)) {
      if (studentIds.contains(rule.student1Id) && studentIds.contains(rule.student2Id)) {
        triggeredRules.add(rule);
      }
    }
    return triggeredRules;
  }

  /// Geriye uyumluluk için alias
  static List<BlacklistRule> findCollisionsInGroup(
    StudentGroup group,
    List<BlacklistRule> rules,
  ) {
    return findApartCollisionsInGroup(group, rules);
  }

  /// Bir öğrenci belirli bir gruba eklenirse herhangi bir "Birlikte Olmasın 🔴" kuralı bozulur mu?
  static bool _wouldCollideIfAdded(
    StudentGroup group,
    GroupingStudent newStudent,
    List<BlacklistRule> rules, {
    String? ignoreStudentId,
  }) {
    for (var s in group.students) {
      if (s.id == ignoreStudentId) continue;
      for (var rule in rules.where((r) => r.isApart)) {
        if (rule.conflicts(newStudent.id, s.id)) {
          return true;
        }
      }
    }
    return false;
  }
}
