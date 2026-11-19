import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../services/teacher_current_class_service.dart';
import '../../../../services/term_service.dart';

class _Stu {
  _Stu(this.id, this.name, this.no);
  final String id;
  final String name;
  final String no;
}

/// Rastgele öğrenci seçici: şube seçilir (varsayılan: ders programındaki şu anki şube),
/// "Seç" ile rastgele öğrenci çıkar, çıkanlar havuzdan ayıklanır, "Sıfırla" hepsini geri getirir.
class WbStudentPicker extends StatefulWidget {
  const WbStudentPicker({
    super.key,
    required this.institutionId,
    this.schoolTypeId = '',
    this.allowedClassIds,
  });
  final String institutionId;
  final String schoolTypeId;
  final List<String>? allowedClassIds;

  @override
  State<WbStudentPicker> createState() => _WbStudentPickerState();
}

class _WbStudentPickerState extends State<WbStudentPicker> {
  /// Panel kapatılıp açılsa da seçilenler şube bazında hatırlanır.
  static final Map<String, Set<String>> _pickedMemory = {};

  final _rng = math.Random();
  Timer? _spin;
  bool _loading = true;
  bool _loadingStudents = false;
  List<Map<String, dynamic>> _classes = [];
  String? _classId;
  String _autoNote = '';
  List<_Stu> _students = [];
  final List<_Stu> _order = []; // seçilme sırası
  _Stu? _shown;
  bool _spinning = false;

  Set<String> get _picked =>
      _pickedMemory.putIfAbsent(_classId ?? '', () => <String>{});

  List<_Stu> get _remaining =>
      _students.where((s) => !_picked.contains(s.id)).toList();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _spin?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    if (widget.institutionId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      String? termId;
      try {
        termId =
            await TermService().getSelectedTermId() ??
            await TermService().getActiveTermId();
      } catch (_) {}
      final allowed = widget.allowedClassIds;
      final list = snap.docs
          .where((d) => d.data()['isActive'] != false)
          .where((d) {
            if (termId == null || termId.isEmpty) return true;
            final t = (d.data()['termId'] ?? '').toString();
            return t.isEmpty || t == termId;
          })
          .where(
            (d) => allowed == null || allowed.isEmpty || allowed.contains(d.id),
          )
          .map((d) => {'id': d.id, ...d.data()})
          .toList();
      list.sort(
        (a, b) => (a['className'] ?? '').toString().compareTo(
          (b['className'] ?? '').toString(),
        ),
      );
      _classes = list;

      final cur = await TeacherCurrentClassService.find(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
      );
      if (cur != null && list.any((c) => c['id'] == cur.classId)) {
        _classId = cur.classId;
        _autoNote = cur.isNow
            ? 'Ders programınızdaki şu anki ders: ${cur.hourNumber}. ders'
            : 'Ders programınızdaki sıradaki ders: ${cur.hourNumber}. ders';
      } else if (list.isNotEmpty) {
        _classId = list.first['id'].toString();
        _autoNote = 'Şu an için ders programında şube bulunamadı; şube seçin';
      }
      if (mounted) setState(() => _loading = false);
      if (_classId != null) await _loadStudents();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadStudents() async {
    final cid = _classId;
    if (cid == null) return;
    setState(() {
      _loadingStudents = true;
      _students = [];
      _shown = null;
    });
    try {
      final db = FirebaseFirestore.instance;
      var snap = await db
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('classId', isEqualTo: cid)
          .get();
      if (snap.docs.isEmpty) {
        final cn = _classes
            .firstWhere((c) => c['id'] == cid)['className']
            ?.toString();
        if (cn != null && cn.isNotEmpty) {
          snap = await db
              .collection('students')
              .where('institutionId', isEqualTo: widget.institutionId)
              .where('className', isEqualTo: cn)
              .get();
        }
      }
      final list = <_Stu>[];
      for (final d in snap.docs) {
        final m = d.data();
        if (m['isActive'] == false) continue;
        final st = (m['status'] ?? '').toString().toLowerCase();
        if (st == 'pasif' || st == 'passive' || st == 'inactive') continue;
        final first = (m['firstName'] ?? m['name'] ?? '').toString();
        final last = (m['lastName'] ?? m['surname'] ?? '').toString();
        var name = '$first $last'.trim();
        if (name.isEmpty) name = 'Öğrenci';
        list.add(
          _Stu(
            d.id,
            name,
            (m['studentNumber'] ?? m['schoolNumber'] ?? m['no'] ?? '')
                .toString(),
          ),
        );
      }
      list.sort((a, b) => a.name.compareTo(b.name));
      // Hafızadaki seçilenleri sıraya yansıt
      final picked = _picked;
      _order
        ..clear()
        ..addAll(list.where((s) => picked.contains(s.id)));
      // Sınıftan çıkmış öğrencileri hafızadan temizle
      picked.removeWhere((id) => !list.any((s) => s.id == id));
      if (mounted) {
        setState(() {
          _students = list;
          _loadingStudents = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  void _pick() {
    final pool = _remaining;
    if (pool.isEmpty || _spinning) return;
    final winner = pool[_rng.nextInt(pool.length)];
    int n = 0;
    _spin?.cancel();
    setState(() => _spinning = true);
    _spin = Timer.periodic(const Duration(milliseconds: 70), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      n++;
      if (n >= 16) {
        t.cancel();
        setState(() {
          _shown = winner;
          _picked.add(winner.id);
          _order.add(winner);
          _spinning = false;
        });
      } else {
        setState(() => _shown = pool[_rng.nextInt(pool.length)]);
      }
    });
  }

  void _reset() {
    _spin?.cancel();
    setState(() {
      _picked.clear();
      _order.clear();
      _shown = null;
      _spinning = false;
    });
  }

  void _giveBack(_Stu s) {
    setState(() {
      _picked.remove(s.id);
      _order.removeWhere((e) => e.id == s.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(30),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.institutionId.isEmpty || _classes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          'Şube listesi bulunamadı. Bu aracı Araçlar menüsünden açın.',
          textAlign: TextAlign.center,
        ),
      );
    }
    final remaining = _remaining;
    final total = _students.length;
    final done = total > 0 && remaining.isEmpty;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('cls_$_classId'),
            initialValue: _classId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Sınıf / Şube',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final c in _classes)
                DropdownMenuItem(
                  value: c['id'].toString(),
                  child: Text((c['className'] ?? '').toString()),
                ),
            ],
            onChanged: (v) {
              if (v == null || v == _classId) return;
              setState(() {
                _classId = v;
                _autoNote = '';
              });
              _loadStudents();
            },
          ),
          if (_autoNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _autoNote,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            height: 96,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDDD6FE)),
            ),
            child: _loadingStudents
                ? const CircularProgressIndicator()
                : total == 0
                ? const Text('Bu şubede öğrenci yok')
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _shown?.name ?? (done ? 'Hepsi seçildi 🎉' : '?'),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: _spinning
                                ? Colors.grey.shade500
                                : const Color(0xFF7C3AED),
                          ),
                        ),
                      ),
                      if (_shown != null && _shown!.no.isNotEmpty && !_spinning)
                        Text(
                          'No: ${_shown!.no}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            'Kalan: ${remaining.length} / $total',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: (remaining.isEmpty || _spinning) ? null : _pick,
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Seç'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: _order.isEmpty ? null : _reset,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Sıfırla'),
                ),
              ),
            ],
          ),
          if (_order.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Seçilenler (ayıklananlar) — dokununca havuza geri döner',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (int i = 0; i < _order.length; i++)
                      InputChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${i + 1}. ${_order[i].name}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () => _giveBack(_order[i]),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

