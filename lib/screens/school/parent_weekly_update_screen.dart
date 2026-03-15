import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ParentWeeklyUpdateScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? periodId;

  final String classId;
  final String lessonId;

  final String className;
  final String lessonName;

  final DateTime? initialDate;

  const ParentWeeklyUpdateScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    this.periodId,
    required this.classId,
    required this.lessonId,
    required this.className,
    required this.lessonName,
    this.initialDate,
  });

  @override
  State<ParentWeeklyUpdateScreen> createState() =>
      _ParentWeeklyUpdateScreenState();
}

class _ParentWeeklyUpdateScreenState extends State<ParentWeeklyUpdateScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _loadedExisting = false;

  DateTime _weekStart = DateTime.now();
  String? _docId;

  final TextEditingController _content = TextEditingController();

  List<Map<String, String>> _similarClasses = [];
  final Set<String> _selectedClassIds = {};

  @override
  void initState() {
    super.initState();

    final base = widget.initialDate ?? DateTime.now();
    _weekStart = _startOfWeek(base);
    _load();
    _findSimilarClasses();
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  DateTime _startOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
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

  String _weekKey(DateTime weekStart) {
    final d = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  String _docKey(DateTime weekStart, {String? classIdOverride}) {
    final period = (widget.periodId ?? '').trim().isEmpty
        ? '__none__'
        : widget.periodId!.trim();
    final cId = classIdOverride ?? widget.classId;
    return '${widget.institutionId}__${widget.schoolTypeId}__${period}__${cId}__${widget.lessonId}__${_weekKey(weekStart)}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadedExisting = false;
      _docId = null;
    });

    try {
      final id = _docKey(_weekStart);
      final doc = await FirebaseFirestore.instance
          .collection('parentWeeklyUpdates')
          .doc(id)
          .get();

      if (!mounted) return;

      if (!doc.exists) {
        setState(() {
          _content.text = '';
          _loadedExisting = false;
          _docId = id;
          _loading = false;
        });
        return;
      }

      final data = doc.data() ?? <String, dynamic>{};

      setState(() {
        _docId = id;
        _content.text = (data['content'] ?? '').toString();
        _loadedExisting = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _content.text = '';
        _loadedExisting = false;
        _docId = null;
        _loading = false;
      });
    }
  }

  Future<void> _findSimilarClasses() async {
    try {
      // 1. Get current class level
      final doc = await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.classId)
          .get();
      if (!doc.exists) return;

      final currentLevelData = doc.data()?['classLevel'];
      if (currentLevelData == null) return;
      final currentLevel = currentLevelData.toString();

      // 2. Find assignments for the same lesson
      var q = FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('lessonId', isEqualTo: widget.lessonId);

      final assignments = await q.get();

      final classIds = assignments.docs
          .map((d) => d.data()['classId'] as String?)
          .where((id) => id != null && id != widget.classId)
          .toSet()
          .toList();

      if (classIds.isEmpty) return;

      final results = <Map<String, String>>[];

      // 3. Fetch class details
      for (var i = 0; i < classIds.length; i += 10) {
        final batch = classIds.sublist(
          i,
          i + 10 > classIds.length ? classIds.length : i + 10,
        );
        final snap = await FirebaseFirestore.instance
            .collection('classes')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final cd in snap.docs) {
          final data = cd.data();
          final lvl = data['classLevel']?.toString();

          if (lvl == currentLevel) {
            results.add({
              'id': cd.id,
              'className': (data['className'] ?? '').toString(),
            });
          }
        }
      }

      // 4. Sort results alphanumerically by className
      results.sort(
        (a, b) => (a['className'] ?? '').compareTo(b['className'] ?? ''),
      );

      if (mounted) {
        setState(() {
          _similarClasses = results;
        });
      }
    } catch (e) {
      debugPrint('Similar classes error: $e');
    }
  }

  Future<void> _shiftWeek(int deltaWeeks) async {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * deltaWeeks));
    });
    await _load();
  }

  Future<void> _save() async {
    if (_saving) return;

    final text = _content.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Metin boş olamaz')));
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oturum bilgisi bulunamadı')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final now = DateTime.now();
      final weekStartKey = _weekKey(_weekStart);
      final id = _docId ?? _docKey(_weekStart);

      // First attempt: try with the actual period ID
      final safePeriodId = (widget.periodId?.trim().isEmpty ?? true)
          ? null
          : widget.periodId;

      Map<String, dynamic> createPayload(String? pId) {
        return {
          'institutionId': widget.institutionId,
          'schoolTypeId': widget.schoolTypeId,
          'periodId': pId,
          'classId': widget.classId,
          'lessonId': widget.lessonId,
          'className': widget.className,
          'lessonName': widget.lessonName,
          'weekStart': weekStartKey,
          'content': text,

          'teacherId': uid,
          'authorId': uid,
          'updatedBy': uid,

          'updatedAt': now.toIso8601String(),
          if (!_loadedExisting) 'createdAt': now.toIso8601String(),
        };
      }

      Future<void> performBatch(String? pId) async {
        final batch = FirebaseFirestore.instance.batch();
        final payload = createPayload(pId);

        // Main update
        final currentRef = FirebaseFirestore.instance
            .collection('parentWeeklyUpdates')
            .doc(id);
        batch.set(currentRef, payload, SetOptions(merge: true));

        // Similar classes updates
        for (final selectedId in _selectedClassIds) {
          final similarClass = _similarClasses.firstWhere(
            (e) => e['id'] == selectedId,
            orElse: () => {},
          );
          if (similarClass.isEmpty) continue;

          final otherClassName = similarClass['className'];
          final otherDocId = _docKey(_weekStart, classIdOverride: selectedId);

          final otherPayload = Map<String, dynamic>.from(payload);
          otherPayload['classId'] = selectedId;
          otherPayload['className'] = otherClassName;

          final otherRef = FirebaseFirestore.instance
              .collection('parentWeeklyUpdates')
              .doc(otherDocId);
          batch.set(otherRef, otherPayload, SetOptions(merge: true));
        }

        await batch.commit();
      }

      try {
        await performBatch(safePeriodId);
      } on FirebaseException catch (e) {
        // Fallback: If permission denied and we used a non-null periodId, try with null.
        // This handles cases where the period might be inactive or check fails.
        if (e.code == 'permission-denied' && safePeriodId != null) {
          debugPrint(
            'Permission denied with periodId $safePeriodId. Retrying with null periodId...',
          );
          await performBatch(null);
        } else {
          rethrow;
        }
      }

      if (!mounted) return;
      setState(() {
        _saving = false;
        _loadedExisting = true;
        _docId = id;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kaydedildi')));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = (e.message ?? e.code).toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme sırasında hata oluştu: $msg')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme sırasında hata oluştu: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekLabel = _formatWeekRangeTr(_weekStart);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Veli Bilgilendirme',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              '${widget.className} • ${widget.lessonName}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
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
                          ),
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
                                Text(
                                  'Seçili Hafta',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  weekLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
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
                          ),
                        ],
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.mail_outline,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Haftalık Veli Mektubu',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.grey.shade900,
                                  ),
                                ),
                              ),
                              if (!_loadedExisting)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.orange.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    'Yeni',
                                    style: TextStyle(
                                      color: Colors.orange.shade800,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (!_loadedExisting)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Center(
                                child: Text(
                                  'Bu haftaya ait kayıt yok. Yeni bir bilgilendirme yazısı oluşturabilirsin.',
                                  style: TextStyle(color: Colors.grey.shade700),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          if (!_loadedExisting) const SizedBox(height: 10),
                          TextField(
                            controller: _content,
                            maxLines: 10,
                            minLines: 8,
                            decoration: InputDecoration(
                              hintText:
                                  'Bu hafta neler yaptınız?\n\nÖrnek:\n- Konu: ...\n- Etkinlik: ...\n- Ödev: ...\n- Not: ...',
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.blue.shade200,
                                  width: 1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.blue.shade600,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_similarClasses.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Center(
                                child: Text(
                                  'Aşağıdaki şubeler için de kaydedilsin:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ),
                            Center(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: _similarClasses.map((c) {
                                  final id = c['id']!;
                                  final name = c['className']!;
                                  final isSelected = _selectedClassIds.contains(
                                    id,
                                  );
                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        if (isSelected) {
                                          _selectedClassIds.remove(id);
                                        } else {
                                          _selectedClassIds.add(id);
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(20),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.blue.shade600
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.blue.shade600
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Text(
                                        name,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : _save,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.center,
                                  child: Text(
                                    _saving ? 'Kaydediliyor...' : 'Kaydet',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade600,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
