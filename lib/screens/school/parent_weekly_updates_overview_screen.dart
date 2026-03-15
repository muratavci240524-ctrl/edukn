import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'parent_weekly_update_detail_screen.dart';

class ParentWeeklyUpdatesOverviewScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? periodId;

  final String classId;
  final String className;

  final DateTime? initialDate;

  const ParentWeeklyUpdatesOverviewScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    this.periodId,
    required this.classId,
    required this.className,
    this.initialDate,
  });

  @override
  State<ParentWeeklyUpdatesOverviewScreen> createState() => _ParentWeeklyUpdatesOverviewScreenState();
}

class _ParentWeeklyUpdatesOverviewScreenState extends State<ParentWeeklyUpdatesOverviewScreen> {
  bool _loading = true;
  DateTime _weekStart = DateTime.now();

  final List<_LessonItem> _lessons = [];
  final Map<String, _WeeklyUpdateMeta> _metaByLessonId = {};

  @override
  void initState() {
    super.initState();
    final base = widget.initialDate ?? DateTime.now();
    _weekStart = _startOfWeek(base);
    _load();
  }

  DateTime _startOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  String _weekKey(DateTime weekStart) {
    final d = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  String _docKey({required String lessonId, required DateTime weekStart}) {
    final period = (widget.periodId ?? '').trim().isEmpty ? '__none__' : widget.periodId!.trim();
    return '${widget.institutionId}__${widget.schoolTypeId}__${period}__${widget.classId}__${lessonId}__${_weekKey(weekStart)}';
  }

  String _formatWeekRangeTr(DateTime weekStart) {
    String monthNameTr(int month) {
      const months = <String>[
        'Ocak',
        'Şubat',
        'Mart',
        'Nisan',
        'Mayıs',
        'Haziran',
        'Temmuz',
        'Ağustos',
        'Eylül',
        'Ekim',
        'Kasım',
        'Aralık',
      ];
      if (month < 1 || month > 12) return '';
      return months[month - 1];
    }

    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 6));

    if (start.month == end.month && start.year == end.year) {
      return '${start.day} - ${end.day} ${monthNameTr(end.month)} ${end.year}';
    }
    return '${start.day} ${monthNameTr(start.month)} - ${end.day} ${monthNameTr(end.month)} ${end.year}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('classSchedules')
          .where('classId', isEqualTo: widget.classId)
          .where('isActive', isEqualTo: true);
      if ((widget.periodId ?? '').toString().isNotEmpty) {
        q = q.where('periodId', isEqualTo: widget.periodId);
      }
      final scheduleSnap = await q.get();

      final Map<String, _LessonItem> unique = {};
      for (final doc in scheduleSnap.docs) {
        final data = doc.data();
        final lessonId = (data['lessonId'] ?? '').toString();
        final lessonName = (data['lessonName'] ?? '').toString();
        if (lessonId.isEmpty) continue;
        unique.putIfAbsent(lessonId, () => _LessonItem(lessonId: lessonId, lessonName: lessonName));
      }

      final lessons = unique.values.toList()
        ..sort((a, b) => a.lessonName.compareTo(b.lessonName));

      final metas = <String, _WeeklyUpdateMeta>{};
      final weekStart = _weekStart;

      await Future.wait(
        lessons.map((l) async {
          final id = _docKey(lessonId: l.lessonId, weekStart: weekStart);
          final doc = await FirebaseFirestore.instance.collection('parentWeeklyUpdates').doc(id).get();
          if (!doc.exists) {
            metas[l.lessonId] = _WeeklyUpdateMeta(exists: false, preview: '');
            return;
          }
          final data = doc.data() ?? <String, dynamic>{};
          final content = (data['content'] ?? '').toString().trim();
          final preview = content.length > 90 ? '${content.substring(0, 90)}…' : content;
          metas[l.lessonId] = _WeeklyUpdateMeta(exists: true, preview: preview);
        }),
      );

      if (!mounted) return;
      setState(() {
        _lessons
          ..clear()
          ..addAll(lessons);
        _metaByLessonId
          ..clear()
          ..addAll(metas);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lessons.clear();
        _metaByLessonId.clear();
        _loading = false;
      });
    }
  }

  Future<void> _shiftWeek(int deltaWeeks) async {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * deltaWeeks));
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final weekLabel = _formatWeekRangeTr(_weekStart);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Veli Bilgilendirme Mektupları', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(widget.className, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          )
                        ],
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Önceki hafta',
                            onPressed: () => _shiftWeek(-1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text('Seçili Hafta', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                const SizedBox(height: 2),
                                Text(
                                  weekLabel,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Sonraki hafta',
                            onPressed: () => _shiftWeek(1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_lessons.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(
                          'Bu sınıf için ders bulunamadı.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ..._lessons.map((l) {
                        final meta = _metaByLessonId[l.lessonId] ?? const _WeeklyUpdateMeta(exists: false, preview: '');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: meta.exists
                                ? () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ParentWeeklyUpdateDetailScreen(
                                          institutionId: widget.institutionId,
                                          schoolTypeId: widget.schoolTypeId,
                                          periodId: widget.periodId,
                                          classId: widget.classId,
                                          className: widget.className,
                                          lessonId: l.lessonId,
                                          lessonName: l.lessonName,
                                          weekStart: _weekStart,
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 6)),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      meta.exists ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
                                      color: meta.exists ? Colors.green.shade700 : Colors.grey.shade500,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (l.lessonName.isNotEmpty ? l.lessonName : 'Ders'),
                                          style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          meta.exists ? meta.preview : 'Bu hafta mektup yok',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Icon(
                                    meta.exists ? Icons.chevron_right : Icons.lock_outline,
                                    color: Colors.grey.shade500,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
    );
  }
}

class _LessonItem {
  final String lessonId;
  final String lessonName;

  const _LessonItem({required this.lessonId, required this.lessonName});
}

class _WeeklyUpdateMeta {
  final bool exists;
  final String preview;

  const _WeeklyUpdateMeta({required this.exists, required this.preview});
}
