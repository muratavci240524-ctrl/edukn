import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Şubelerin haftalık OKUL ders programını yükler:
/// şube anahtarı -> (gün adı -> o gün işlenen ders adları, ders saati sırasıyla).
///
/// Çalışma planında "tekrar" oturumunu, öğrencinin o gün okulda gördüğü
/// dersten seçmek için kullanılır. Veri yoksa ya da hata olursa boş döner;
/// plan bu durumda eski (sıralı) tekrar dağıtımına düşer.
///
/// Not: Aynı sınav + aynı ders programı her zaman aynı planı üretir
/// (tamamen deterministik).
class SchoolTimetableLoader {
  SchoolTimetableLoader._();

  /// Şube adlarını karşılaştırmak için sadeleştirir ("8-A", "8/A", "8 A" -> "8a").
  static String key(String s) => s
      .replaceAll('İ', 'i')
      .replaceAll('I', 'i')
      .replaceAll('ı', 'i')
      .toLowerCase()
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static Future<Map<String, Map<String, List<String>>>> load({
    required String institutionId,
    required String schoolTypeId,
    required Iterable<String> branchNames,
  }) async {
    final out = <String, Map<String, List<String>>>{};
    if (institutionId.isEmpty || schoolTypeId.isEmpty) return out;
    try {
      final db = FirebaseFirestore.instance;
      final instIds =
          {institutionId.toUpperCase(), institutionId.toLowerCase()}.toList();

      // 1) Aktif ve yayınlanmış dönem (bugünü kapsayan; yoksa en son başlayan).
      final periods = await db
          .collection('workPeriods')
          .where('schoolTypeId', isEqualTo: schoolTypeId)
          .where('institutionId', whereIn: instIds)
          .where('isActive', isEqualTo: true)
          .where('schedulePublished', isEqualTo: true)
          .get();
      if (periods.docs.isEmpty) return out;

      DateTime? startOf(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
          (d.data()['startDate'] as Timestamp?)?.toDate();
      DateTime? endOf(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
          (d.data()['endDate'] as Timestamp?)?.toDate();

      final now = DateTime.now();
      QueryDocumentSnapshot<Map<String, dynamic>>? period;
      for (final d in periods.docs) {
        final s = startOf(d), e = endOf(d);
        if (s != null &&
            e != null &&
            !now.isBefore(s.subtract(const Duration(days: 1))) &&
            !now.isAfter(e.add(const Duration(days: 1)))) {
          period = d;
          break;
        }
      }
      if (period == null) {
        final sorted = [...periods.docs]..sort((a, b) {
            final sa = startOf(a), sb = startOf(b);
            if (sa == null && sb == null) return a.id.compareTo(b.id);
            if (sa == null) return 1;
            if (sb == null) return -1;
            return sb.compareTo(sa);
          });
        period = sorted.first;
      }

      // 2) Şube adı -> classId eşlemesi.
      final classes = await db
          .collection('classes')
          .where('schoolTypeId', isEqualTo: schoolTypeId)
          .where('institutionId', whereIn: instIds)
          .where('isActive', isEqualTo: true)
          .get();
      final docs = [...classes.docs]..sort((a, b) => a.id.compareTo(b.id));
      final idByKey = <String, String>{};
      for (final c in docs) {
        final d = c.data();
        final name = (d['className'] ?? d['name'] ?? '').toString();
        final level = (d['classLevel'] ?? '').toString();
        final keys = <String>{
          key('$level$name'),
          // Yalnız "A" gibi seviyesiz adlar farklı seviyelerle çakışmasın.
          if (level.isEmpty || RegExp(r'\d').hasMatch(name)) key(name),
        };
        for (final k in keys) {
          if (k.isNotEmpty) idByKey.putIfAbsent(k, () => c.id);
        }
      }

      // 3) Her şubenin programı (paralel).
      final periodId = period.id;
      final branchKeys = {for (final b in branchNames) key(b)}
        ..removeWhere((k) => k.isEmpty);
      await Future.wait(branchKeys.map((bk) async {
        final cid = idByKey[bk];
        if (cid == null) return;
        final snap = await db
            .collection('classSchedules')
            .where('periodId', isEqualTo: periodId)
            .where('classId', isEqualTo: cid)
            .get();
        final byDay = <String, List<(int, String)>>{};
        for (final doc in snap.docs) {
          final d = doc.data();
          if (d['isActive'] == false) continue;
          final day = d['day']?.toString();
          final h = d['hourIndex'];
          final lesson = (d['lessonName'] ?? '').toString().trim();
          if (day == null || h is! int || lesson.isEmpty) continue;
          byDay.putIfAbsent(day, () => []).add((h, lesson));
        }
        if (byDay.isEmpty) return;
        out[bk] = {
          for (final e in byDay.entries)
            e.key: ([...e.value]..sort((a, b) => a.$1.compareTo(b.$1)))
                .map((x) => x.$2)
                .toList(),
        };
      }));
    } catch (e) {
      debugPrint('SchoolTimetableLoader: ders programı yüklenemedi: $e');
    }
    return out;
  }
}
