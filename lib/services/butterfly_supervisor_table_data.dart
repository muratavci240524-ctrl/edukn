import '../models/school/butterfly_exam_model.dart';

/// Gözetmen çizelgesi (salon x oturum/devre) için ortak veri katmanı.
/// Hem ekrandaki tablo hem de PDF çıktısı bu sınıfı kullanır.
class SupSeg {
  final int start;
  final int end;
  const SupSeg(this.start, this.end);
}

class SupSession {
  final int index;
  final String title;
  final int start;
  final int end;
  final int breakAfter;
  final List<SupSeg> globalSegs;
  List<SupSeg> columns = [];

  SupSession({
    required this.index,
    required this.title,
    required this.start,
    required this.end,
    required this.breakAfter,
    required this.globalSegs,
  });
}

class SupCell {
  final SupSeg seg;
  final String name;
  final bool custom;
  const SupCell({required this.seg, required this.name, required this.custom});
}

class SupervisorTableData {
  final List<SupSession> sessions;
  final List<ExamRoom> rooms;

  SupervisorTableData._(this.sessions, this.rooms);

  static String fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  static int? _toMin(String? s) {
    if (s == null) return null;
    final m = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch(s);
    if (m == null) return null;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  static int _roomNo(String name) {
    final m = RegExp(r'\d+').firstMatch(name);
    return m == null ? 1 << 30 : int.parse(m.group(0)!);
  }

  int get totalColumns => sessions.fold<int>(0, (a, s) => a + s.columns.length);

  int get totalCells {
    int n = 0;
    for (final r in rooms) {
      for (final s in sessions) {
        n += cellsFor(r, s).length;
      }
    }
    return n;
  }

  int get assignedCells {
    int n = 0;
    for (final r in rooms) {
      for (final s in sessions) {
        n += cellsFor(r, s).where((c) => c.name.isNotEmpty).length;
      }
    }
    return n;
  }

  factory SupervisorTableData.from(ExamDistribution exam) {
    final Map<int, List<Map<String, dynamic>>> grouped = {};
    for (int i = 0; i < exam.sessionSlots.length; i++) {
      final s = Map<String, dynamic>.from(exam.sessionSlots[i]);
      final idx = (s['sessionIndex'] as num?)?.toInt() ?? i;
      grouped.putIfAbsent(idx, () => []).add(s);
    }

    final List<SupSession> sessions = [];
    if (grouped.isEmpty) {
      final parts = exam.examTime.split('-');
      final st = _toMin(parts.first) ?? 0;
      final en = parts.length > 1 ? (_toMin(parts[1]) ?? st + 40) : st + 40;
      sessions.add(SupSession(
        index: 0,
        title: '1. Oturum',
        start: st,
        end: en,
        breakAfter: 0,
        globalSegs: [SupSeg(st, en)],
      ));
    } else {
      final keys = grouped.keys.toList()..sort();
      for (final k in keys) {
        final slots = grouped[k]!;
        slots.sort((a, b) => ((a['dutyIndex'] as num?)?.toInt() ?? 0)
            .compareTo((b['dutyIndex'] as num?)?.toInt() ?? 0));
        final segs = <SupSeg>[];
        for (final s in slots) {
          final st = _toMin(s['startTime']?.toString());
          final en = _toMin(s['endTime']?.toString());
          if (st != null && en != null && en > st) segs.add(SupSeg(st, en));
        }
        if (segs.isEmpty) segs.add(const SupSeg(0, 40));
        String title = (slots.first['sessionTitle'] ?? slots.first['label'] ?? '${k + 1}. Oturum')
            .toString()
            .replaceAll(RegExp(r'\s*\(\d+\.\s*Devre\)\s*$', caseSensitive: false), '')
            .trim();
        if (title.isEmpty) title = '${k + 1}. Oturum';
        sessions.add(SupSession(
          index: k,
          title: title,
          start: segs.first.start,
          end: segs.last.end,
          breakAfter: (slots.last['breakMinutes'] as num?)?.toInt() ?? 0,
          globalSegs: segs,
        ));
      }
    }

    final rooms = List<ExamRoom>.from(exam.rooms)
      ..sort((a, b) {
        final c = _roomNo(a.classroomName).compareTo(_roomNo(b.classroomName));
        return c != 0 ? c : a.classroomName.compareTo(b.classroomName);
      });

    // Salona özel bölmeleri de içerecek şekilde sütun sınırlarını birleştir
    for (final s in sessions) {
      final points = <int>{s.start, s.end};
      for (final g in s.globalSegs) {
        points
          ..add(g.start)
          ..add(g.end);
      }
      for (final r in rooms) {
        for (final seg in _roomSegs(r, s)) {
          points
            ..add(seg.start)
            ..add(seg.end);
        }
      }
      final sorted = points.where((p) => p >= s.start && p <= s.end).toList()..sort();
      final cols = <SupSeg>[];
      for (int i = 0; i < sorted.length - 1; i++) {
        if (sorted[i + 1] > sorted[i]) cols.add(SupSeg(sorted[i], sorted[i + 1]));
      }
      s.columns = cols.isEmpty ? [SupSeg(s.start, s.end)] : cols;
    }

    return SupervisorTableData._(sessions, rooms);
  }

  static List<SupSeg> _roomSegs(ExamRoom room, SupSession s) {
    final split = room.sessionSplits['${s.index}'];
    if (split is Map) {
      final count = ((split['splitCount'] as num?)?.toInt() ?? 1).clamp(1, 4);
      if (count <= 1) return [SupSeg(s.start, s.end)];
      final total = s.end - s.start;
      List<int> d;
      final raw = split['durations'];
      if (raw is List && raw.length == count) {
        d = raw.map((e) => ((e as num?)?.toInt() ?? (total ~/ count))).toList();
      } else {
        d = List.generate(count, (_) => total ~/ count);
      }
      final diff = total - d.fold<int>(0, (a, b) => a + b);
      d[count - 1] += diff;
      final segs = <SupSeg>[];
      int cur = s.start;
      for (final dur in d) {
        final next = (cur + dur).clamp(cur, s.end);
        segs.add(SupSeg(cur, next));
        cur = next;
      }
      return segs;
    }
    return s.globalSegs;
  }

  static bool _differs(List<SupSeg> a, List<SupSeg> b) {
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      if (a[i].start != b[i].start || a[i].end != b[i].end) return true;
    }
    return false;
  }

  static String _clean(String? n) {
    final t = (n ?? '').trim();
    return t == 'Gözetmen Öğretmen' ? '' : t;
  }

  /// Bir salonun bir oturumdaki hücreleri (devre sayısı kadar).
  List<SupCell> cellsFor(ExamRoom room, SupSession s) {
    final segs = _roomSegs(room, s);
    final custom = room.sessionSplits.containsKey('${s.index}') && _differs(segs, s.globalSegs);
    final entries = room.supervisors.where((e) {
      final si = e['sessionIndex'];
      return si is num && si.toInt() == s.index;
    }).toList();

    final cells = <SupCell>[];
    for (int p = 0; p < segs.length; p++) {
      final seg = segs[p];
      String name = '';
      bool found = false;
      for (final e in entries) {
        if (_toMin(e['startTime']?.toString()) == seg.start) {
          name = _clean(e['supervisorName']?.toString());
          found = true;
          break;
        }
      }
      if (!found) {
        for (final e in entries) {
          if (((e['dutyIndex'] as num?)?.toInt() ?? 0) == p) {
            name = _clean(e['supervisorName']?.toString());
            found = true;
            break;
          }
        }
      }
      if (!found && entries.isEmpty && s.index == 0 && segs.length == 1) {
        name = _clean(room.supervisorName);
      }
      cells.add(SupCell(seg: seg, name: name, custom: custom));
    }
    return cells;
  }

  /// Bir hücrenin kaç sütun kapladığını döner.
  int spanOf(SupSession s, SupSeg seg) {
    final n = s.columns.where((c) => c.start >= seg.start && c.end <= seg.end).length;
    return n < 1 ? 1 : n;
  }
}

