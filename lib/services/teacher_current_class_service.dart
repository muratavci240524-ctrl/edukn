import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Öğretmenin ders programına göre "şu an" hangi şubede olduğunu bulur.
class CurrentLessonInfo {
  CurrentLessonInfo({
    required this.classId,
    required this.className,
    required this.hourNumber,
    required this.isNow,
  });
  final String classId;
  final String className;

  /// 1 tabanlı ders saati.
  final int hourNumber;

  /// true: ders şu an sürüyor; false: bir sonraki ders.
  final bool isNow;
}

class TeacherCurrentClassService {
  TeacherCurrentClassService._();

  static const _dayNames = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];

  static int _min(dynamic h, dynamic m) =>
      (int.tryParse('${h ?? 0}') ?? 0) * 60 + (int.tryParse('${m ?? 0}') ?? 0);

  /// Bugünün ders saatleri: [başlangıç dk, bitiş dk] listesi (0 tabanlı index).
  static List<List<int>> _todayTimes(
    Map<String, dynamic> period,
    String dayName,
  ) {
    final lh = period['lessonHours'];
    if (lh is! Map) return [];
    final raw = lh['lessonTimes'];
    if (raw is! Map || raw.isEmpty) return [];
    final map = Map<String, dynamic>.from(raw);
    final out = <List<int>>[];
    if (int.tryParse(map.keys.first) != null) {
      final keys = map.keys.toList()
        ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
      for (final k in keys) {
        final t = Map<String, dynamic>.from(map[k] as Map);
        out.add([
          _min(t['startHour'], t['startMinute']),
          _min(t['endHour'], t['endMinute']),
        ]);
      }
    } else {
      final list = map[dayName];
      if (list is List) {
        for (final e in list) {
          final t = Map<String, dynamic>.from(e as Map);
          out.add([
            _min(t['startHour'], t['startMinute']),
            _min(t['endHour'], t['endMinute']),
          ]);
        }
      }
    }
    return out;
  }

  /// Şu anki (yoksa bir sonraki) dersin şubesini döndürür; bulunamazsa null.
  static Future<CurrentLessonInfo?> find({
    required String institutionId,
    String schoolTypeId = '',
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || institutionId.isEmpty) return null;
      final db = FirebaseFirestore.instance;
      final now = DateTime.now();
      final dayName = _dayNames[now.weekday - 1];
      final nowMin = now.hour * 60 + now.minute;

      // 1) Bugünü kapsayan yayınlanmış dönem
      final ids = {institutionId, institutionId.toLowerCase()}.toList();
      final ps = await db
          .collection('workPeriods')
          .where('institutionId', whereIn: ids)
          .get();
      QueryDocumentSnapshot<Map<String, dynamic>>? period;
      for (final d in ps.docs) {
        final data = d.data();
        final pub =
            data['schedulePublished'] == true || data['isPublished'] == true;
        if (!pub || data['isActive'] == false) continue;
        if (schoolTypeId.isNotEmpty &&
            (data['schoolTypeId'] ?? '').toString() != schoolTypeId) {
          continue;
        }
        final s = (data['startDate'] as Timestamp?)?.toDate();
        final e = (data['endDate'] as Timestamp?)?.toDate();
        if (s == null || e == null) continue;
        final sd = DateTime(s.year, s.month, s.day);
        final ed = DateTime(e.year, e.month, e.day, 23, 59, 59);
        if (!now.isBefore(sd) && !now.isAfter(ed)) {
          period = d;
          break;
        }
      }
      if (period == null) return null;
      final times = _todayTimes(period.data(), dayName);
      if (times.isEmpty) return null;

      // 2) Şu anki / sonraki ders saati
      int idx = -1;
      bool isNow = false;
      for (int i = 0; i < times.length; i++) {
        if (nowMin >= times[i][0] && nowMin <= times[i][1] + 5) {
          idx = i;
          isNow = true;
          break;
        }
      }

      // 3) Öğretmenin bugünkü programı
      final snaps = await Future.wait([
        db
            .collection('classSchedules')
            .where('teacherIds', arrayContains: uid)
            .get(),
        db
            .collection('classSchedules')
            .where('teacherId', isEqualTo: uid)
            .get(),
      ]);
      final byHour = <int, Map<String, dynamic>>{};
      for (final s in snaps) {
        for (final d in s.docs) {
          final data = d.data();
          if (data['isActive'] == false) continue;
          if ((data['day'] ?? '').toString() != dayName) continue;
          final pid = (data['periodId'] ?? '').toString();
          if (pid.isNotEmpty && pid != period.id) continue;
          final h = data['hourIndex'];
          final hi = h is int ? h : int.tryParse('$h');
          if (hi == null) continue;
          byHour.putIfAbsent(hi, () => data);
        }
      }
      if (byHour.isEmpty) return null;

      Map<String, dynamic>? slot;
      if (isNow) slot = byHour[idx];
      if (slot == null) {
        // Şu an ders yok / boş ders: bir sonraki dersi al
        final upcoming =
            byHour.keys
                .where((h) => h < times.length && times[h][0] > nowMin)
                .toList()
              ..sort();
        if (upcoming.isNotEmpty) {
          idx = upcoming.first;
          slot = byHour[idx];
          isNow = false;
        }
      }
      if (slot == null) {
        // Gün bitmiş: günün son dersi
        final all = byHour.keys.toList()..sort();
        idx = all.last;
        slot = byHour[idx];
        isNow = false;
      }
      final classId = (slot?['classId'] ?? '').toString();
      if (classId.isEmpty) return null;
      var className = (slot?['className'] ?? '').toString();
      if (className.isEmpty) {
        final c = await db.collection('classes').doc(classId).get();
        className = (c.data()?['className'] ?? c.data()?['name'] ?? '')
            .toString();
      }
      return CurrentLessonInfo(
        classId: classId,
        className: className,
        hourNumber: idx + 1,
        isNow: isNow,
      );
    } catch (_) {
      return null;
    }
  }
}
