import 'dart:async';
import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MODELLER
// ═══════════════════════════════════════════════════════════════════════════════

class ProctoringSlot {
  final String id;
  final String classId;
  final String className;
  final int slotIndex;
  final String? teacherId;
  final String? teacherName;
  final bool? notificationSent;
  final bool? isPublished;
  final String? startTime;
  final String? endTime;
  final String? slotLabel;

  const ProctoringSlot({
    required this.id,
    required this.classId,
    required this.className,
    required this.slotIndex,
    this.teacherId,
    this.teacherName,
    this.notificationSent,
    this.isPublished,
    this.startTime,
    this.endTime,
    this.slotLabel,
  });

  factory ProctoringSlot.fromMap(Map<String, dynamic> data, String docId) {
    return ProctoringSlot(
      id: docId,
      classId: data['classId'] as String? ?? '',
      className: data['className'] as String? ?? '',
      slotIndex: (data['slotIndex'] as num?)?.toInt() ?? 0,
      teacherId: data['teacherId'] as String?,
      teacherName: data['teacherName'] as String?,
      notificationSent: data['notificationSent'] as bool?,
      isPublished: data['isPublished'] as bool?,
      startTime: data['startTime'] as String?,
      endTime: data['endTime'] as String?,
      slotLabel: data['slotLabel'] as String?,
    );
  }
}

class ProctoringTimeSlot {
  final String label;
  final String startTime;
  final String endTime;

  const ProctoringTimeSlot({
    required this.label,
    required this.startTime,
    required this.endTime,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// EKRAN
// ═══════════════════════════════════════════════════════════════════════════════

class ProctoringSessionScreen extends StatefulWidget {
  final String examId;
  final String examName;
  final DateTime examDate;
  final String institutionId;
  final String? schoolTypeId;
  final String? schoolTypeName;

  const ProctoringSessionScreen({
    super.key,
    required this.examId,
    required this.examName,
    required this.examDate,
    required this.institutionId,
    this.schoolTypeId,
    this.schoolTypeName,
  });

  @override
  State<ProctoringSessionScreen> createState() =>
      _ProctoringSessionScreenState();
}

class _ProctoringSessionScreenState extends State<ProctoringSessionScreen>
    with SingleTickerProviderStateMixin {
  // ─── State ─────────────────────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isSharing = false;
  bool _isPublished = false;   // Sınav yayınlandı mı?
  bool _isFabMenuOpen = false; // FAB menüsü açık mı?

  // Tüm sınıflar havuzu
  List<Map<String, dynamic>> _allClasses = [];
  // Seçili sınıflar (sınav için) — ham liste, sırasız
  List<Map<String, dynamic>> _selectedClasses = [];

  /// Seçili sınıfları seviye → alfabetik sırayla döndürür (grid/PDF için)
  List<Map<String, dynamic>> get _sortedSelectedClasses {
    final copy = List<Map<String, dynamic>>.from(_selectedClasses);
    copy.sort((a, b) {
      final foundA =
          _allClasses.where((c) => c['id'] == a['id']).firstOrNull;
      final foundB =
          _allClasses.where((c) => c['id'] == b['id']).firstOrNull;
      final lvA = (foundA?['classLevel'] ?? '').toString();
      final lvB = (foundB?['classLevel'] ?? '').toString();
      final numA = int.tryParse(lvA) ?? 99;
      final numB = int.tryParse(lvB) ?? 99;
      if (numA != numB) return numA.compareTo(numB);
      return (a['name'] as String).compareTo(b['name'] as String);
    });
    return copy;
  }

  // Öğretmen havuzu
  List<QueryDocumentSnapshot> _teachers = [];

  // Slot atamaları: "classId_slotIndex" → ProctoringSlot
  Map<String, ProctoringSlot> _assignments = {};

  // Saat dilimleri
  List<ProctoringTimeSlot> _timeSlots = [];
  // Her slot için ayrı başlangıç/bitiş (manuel giriş)
  int _slotCount = 4;
  // _manualSlots[i] = {start: '09:00', end: '09:40'}
  List<Map<String, String>> _manualSlots = [];

  StreamSubscription<QuerySnapshot>? _slotsSub;
  late TabController _tabController;

  final _df = DateFormat('dd MMMM yyyy', 'tr_TR');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _slotsSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ─── Yükleme ───────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadExamData(),
        _loadAllClasses(),
        _loadTeachers(),
        _loadSettings(),
      ]);
      _rebuildTimeSlots();
      _initSlotsStream();
      // Arka planda mevcut kayıtlı slotların saatlerini de güncel saat ayarlarıyla senkronize et
      _syncAllSlotTimes(silent: true);
    } catch (e) {
      debugPrint('ProctoringSessionScreen error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadExamData() async {
    final doc = await FirebaseFirestore.instance
        .collection('proctoringExams')
        .doc(widget.examId)
        .get();
    if (!doc.exists) return;
    final data = doc.data()!;
    final ids = List<String>.from(data['classIds'] as List? ?? []);
    final names = List<String>.from(data['classNames'] as List? ?? []);
    _selectedClasses = List.generate(ids.length, (i) => {
      'id': ids[i],
      'name': i < names.length ? names[i] : ids[i],
    });
    _isPublished = data['isPublished'] == true;
  }

  Future<void> _loadAllClasses() async {
    Query query = FirebaseFirestore.instance
        .collection('classes')
        .where('institutionId', isEqualTo: widget.institutionId);
    if (widget.schoolTypeId != null && widget.schoolTypeId!.isNotEmpty) {
      query = query.where('schoolTypeId', isEqualTo: widget.schoolTypeId);
    }
    final snap = await query.get();
    final list = snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      return {
        'id': d.id,
        'name': (data['className'] ?? data['name'] ?? 'İsimsiz').toString(),
        'classLevel': (data['classLevel'] ?? '').toString(),
      };
    }).toList();

    list.sort((a, b) {
      final lvA = int.tryParse(a['classLevel'] as String) ?? 0;
      final lvB = int.tryParse(b['classLevel'] as String) ?? 0;
      if (lvA != lvB) return lvA.compareTo(lvB);
      return (a['name'] as String).compareTo(b['name'] as String);
    });

    // Tekilleştir
    final seen = <String>{};
    _allClasses = list.where((c) => seen.add(c['name'] as String)).toList();
  }

  Future<void> _loadTeachers() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('type', whereIn: ['teacher', 'staff', 'admin']).get();
    _teachers = snap.docs.where((d) => _isActive(d.data())).toList();
  }

  Future<void> _loadSettings() async {
    try {
      DocumentSnapshot<Map<String, dynamic>>? doc;
      // 1. Önce proctoringSettings dokümanına bak
      try {
        final d = await FirebaseFirestore.instance
            .collection('proctoringSettings')
            .doc('${widget.institutionId}_${widget.examId}')
            .get();
        if (d.exists) doc = d;
      } catch (e) {
        debugPrint('[Proctoring] doc1 error: $e');
      }

      // 2. Fallback: doc(examId)
      if (doc == null || !doc.exists) {
        try {
          final d = await FirebaseFirestore.instance
              .collection('proctoringSettings')
              .doc(widget.examId)
              .get();
          if (d.exists) doc = d;
        } catch (e) {
          debugPrint('[Proctoring] doc2 error: $e');
        }
      }

      // 3. Fallback: proctoringExams dokümanının kendisi
      if (doc == null || !doc.exists) {
        try {
          final d = await FirebaseFirestore.instance
              .collection('proctoringExams')
              .doc(widget.examId)
              .get();
          if (d.exists && (d.data()?['manualSlots'] != null || d.data()?['slotCount'] != null)) {
            doc = d;
          }
        } catch (e) {
          debugPrint('[Proctoring] doc3 error: $e');
        }
      }

      if (doc != null && doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final raw = (data['manualSlots'] ?? data['timeSlots']) as List? ?? [];
        if (raw.isNotEmpty) {
          _manualSlots = raw.map((e) {
            if (e is Map) {
              return {
                'start': (e['start'] ?? e['startTime'] ?? '09:00').toString(),
                'end': (e['end'] ?? e['endTime'] ?? '09:40').toString(),
              };
            }
            return {'start': '09:00', 'end': '09:40'};
          }).toList();
          _slotCount = _manualSlots.length;
          return;
        }
        final count = (data['slotCount'] as num?)?.toInt();
        if (count != null && count > 0) {
          _slotCount = count;
          _manualSlots = _defaultSlots(count);
          return;
        }
      }
      _manualSlots = _defaultSlots(_slotCount);
    } catch (e) {
      debugPrint('[Proctoring] _loadSettings fallback error: $e');
      _manualSlots = _defaultSlots(_slotCount);
    }
  }

  /// Varsayılan boş slot listesi
  List<Map<String, String>> _defaultSlots(int count) {
    return List.generate(
        count, (i) => {'start': '09:00', 'end': '09:40'});
  }

  void _rebuildTimeSlots() {
    _timeSlots = _manualSlots.asMap().entries.map((e) {
      return ProctoringTimeSlot(
        label: '${e.key + 1}. Saat',
        startTime: e.value['start'] ?? '',
        endTime: e.value['end'] ?? '',
      );
    }).toList();
  }

  /// Tüm kayıtlı slotları güncel _timeSlots saatlerine senkronize eder.
  Future<void> _syncAllSlotTimes({bool silent = false}) async {
    if (_timeSlots.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('proctoringSlots')
          .where('examId', isEqualTo: widget.examId)
          .get();

      if (snap.docs.isEmpty) return;

      WriteBatch? batch;
      int updatedCount = 0;

      for (final doc in snap.docs) {
        final d = doc.data();
        final slotIdx = (d['slotIndex'] as num?)?.toInt() ?? 0;
        if (slotIdx >= 0 && slotIdx < _timeSlots.length) {
          final target = _timeSlots[slotIdx];
          final curStart = d['startTime']?.toString() ?? '';
          final curEnd = d['endTime']?.toString() ?? '';
          final curLabel = d['slotLabel']?.toString() ?? '';

          if (curStart != target.startTime ||
              curEnd != target.endTime ||
              curLabel != target.label) {
            batch ??= FirebaseFirestore.instance.batch();
            batch.update(doc.reference, {
              'slotLabel': target.label,
              'startTime': target.startTime,
              'endTime': target.endTime,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            updatedCount++;
          }
        }
      }

      if (batch != null && updatedCount > 0) {
        await batch.commit();
        debugPrint('[Proctoring] $updatedCount adet slotun saati başarıyla senkronize edildi.');
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$updatedCount öğretmenin gözetmenlik saatleri güncellendi.'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ));
        }
      }
    } catch (e) {
      debugPrint('[Proctoring] _syncAllSlotTimes error: $e');
    }
  }

  void _initSlotsStream() {
    _slotsSub?.cancel();
    _slotsSub = FirebaseFirestore.instance
        .collection('proctoringSlots')
        .where('examId', isEqualTo: widget.examId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final map = <String, ProctoringSlot>{};
      for (var doc in snap.docs) {
        final slot = ProctoringSlot.fromMap(doc.data(), doc.id);
        map['${slot.classId}_${slot.slotIndex}'] = slot;
      }
      setState(() => _assignments = map);
    });
  }

  // ─── Yardımcı ──────────────────────────────────────────────────────────────

  bool _isActive(Map<String, dynamic> data) {
    if (data['isActive'] == false || data['isPassive'] == true) return false;
    final s = (data['status'] ?? '').toString().toLowerCase();
    return s != 'passive' && s != 'pasif' && s != 'inactive';
  }

  String _teacherName(Map<String, dynamic> d) =>
      (d['fullName'] ?? d['name'] ?? 'İsimsiz').toString().trim();

  String _teacherBranch(Map<String, dynamic> d) {
    if (d['branches'] is List && (d['branches'] as List).isNotEmpty) {
      return (d['branches'] as List).first.toString();
    }
    return d['branch']?.toString() ?? d['title']?.toString() ?? 'Öğretmen';
  }

  bool _isClassSelected(String classId) =>
      _selectedClasses.any((c) => c['id'] == classId);

  // ─── Sınıf Seçme/Kaldırma ─────────────────────────────────────────────────

  Future<void> _toggleClass(Map<String, dynamic> cls) async {
    final id = cls['id'] as String;
    final name = cls['name'] as String;
    final wasSelected = _isClassSelected(id);

    setState(() {
      if (wasSelected) {
        _selectedClasses.removeWhere((c) => c['id'] == id);
      } else {
        _selectedClasses.add({'id': id, 'name': name});
      }
    });

    // Firestore'a kaydet
    await FirebaseFirestore.instance
        .collection('proctoringExams')
        .doc(widget.examId)
        .update({
      'classIds': _selectedClasses.map((c) => c['id']).toList(),
      'classNames': _selectedClasses.map((c) => c['name']).toList(),
    });
  }

  // ─── Öğretmen Atama ────────────────────────────────────────────────────────

  Future<void> _showTeacherPicker(
      String classId, String className, int slotIndex) async {
    final key = '${classId}_$slotIndex';
    final current = _assignments[key];
    String query = '';
    final ctrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final filtered = _teachers.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final n = _teacherName(data).toLowerCase();
          final b = _teacherBranch(data).toLowerCase();
          return n.contains(query) || b.contains(query);
        }).toList();

        return Container(
          height: MediaQuery.of(context).size.height * 0.78,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$className – ${_timeSlots[slotIndex].label}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                    Text(
                      '${_timeSlots[slotIndex].startTime} – ${_timeSlots[slotIndex].endTime}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: ctrl,
                  onChanged: (v) => set(() => query = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Öğretmen ara...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              if (current?.teacherId != null)
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.person_remove_outlined,
                        color: Colors.red.shade400, size: 20),
                  ),
                  title: Text('Öğretmeni Kaldır',
                      style: TextStyle(
                          color: Colors.red.shade500,
                          fontWeight: FontWeight.w600)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _removeAssignment(key, current!.id);
                  },
                ),
              const Divider(height: 1),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text('Öğretmen bulunamadı',
                            style: TextStyle(color: Colors.grey.shade400)))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final data =
                              filtered[i].data() as Map<String, dynamic>;
                          final name = _teacherName(data);
                          final branch = _teacherBranch(data);
                          final uid = filtered[i].id;
                          final isSelected =
                              current?.teacherId == uid;
                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF7C3AED)
                                        .withValues(alpha: 0.12)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.person_outline,
                                color: isSelected
                                    ? const Color(0xFF7C3AED)
                                    : Colors.grey.shade500,
                                size: 20,
                              ),
                            ),
                            title: Text(name,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? const Color(0xFF7C3AED)
                                      : const Color(0xFF1E293B),
                                )),
                            subtitle: Text(branch,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500)),
                            onTap: () async {
                              Navigator.pop(ctx);
                              // ── Çakışma kontrolü ──────────────────
                              final conflict = _assignments.entries
                                  .where((e) =>
                                      e.value.teacherId == uid &&
                                      e.value.slotIndex == slotIndex &&
                                      e.value.classId != classId)
                                  .firstOrNull;

                              if (conflict != null) {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(20)),
                                    title: Row(children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(Icons.warning_amber_rounded,
                                            color: Colors.orange.shade600,
                                            size: 22),
                                      ),
                                      const SizedBox(width: 10),
                                      const Text('Çakışma Uyarısı',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16)),
                                    ]),
                                    content: RichText(
                                      text: TextSpan(
                                        style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 14,
                                            height: 1.5),
                                        children: [
                                          TextSpan(
                                              text: name,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF7C3AED))),
                                          const TextSpan(
                                              text: ' bu saatte zaten '),
                                          TextSpan(
                                              text: conflict.value.className,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.black)),
                                          const TextSpan(
                                              text:
                                                  ' sınıfına atanmış.\n\nYine de '),
                                          TextSpan(
                                              text: className,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.black)),
                                          const TextSpan(
                                              text: ' sınıfına da atar mısın?'),
                                        ],
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Vazgeç')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.orange.shade600,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Yine de Ata'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                              }

                              await _saveAssignment(
                                key: key,
                                classId: classId,
                                className: className,
                                slotIndex: slotIndex,
                                teacherId: uid,
                                teacherName: name,
                                existingSlotId: current?.id,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _saveAssignment({
    required String key,
    required String classId,
    required String className,
    required int slotIndex,
    required String teacherId,
    required String teacherName,
    String? existingSlotId,
  }) async {
    final String label = (slotIndex >= 0 && slotIndex < _timeSlots.length)
        ? _timeSlots[slotIndex].label
        : '${slotIndex + 1}. Saat';
    final String start = (slotIndex >= 0 && slotIndex < _timeSlots.length)
        ? _timeSlots[slotIndex].startTime
        : (_manualSlots.length > slotIndex ? (_manualSlots[slotIndex]['start'] ?? '09:00') : '09:00');
    final String end = (slotIndex >= 0 && slotIndex < _timeSlots.length)
        ? _timeSlots[slotIndex].endTime
        : (_manualSlots.length > slotIndex ? (_manualSlots[slotIndex]['end'] ?? '09:40') : '09:40');

    final data = {
      'institutionId': widget.institutionId,
      'schoolTypeId': widget.schoolTypeId ?? '',
      'examId': widget.examId,
      'examName': widget.examName,
      'examDate': Timestamp.fromDate(widget.examDate),
      'classId': classId,
      'className': className,
      'slotIndex': slotIndex,
      'slotLabel': label,
      'startTime': start,
      'endTime': end,
      'teacherId': teacherId,
      'teacherName': teacherName,
      'isPublished': _isPublished,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      if (existingSlotId != null) {
        await FirebaseFirestore.instance
            .collection('proctoringSlots')
            .doc(existingSlotId)
            .update(data);
      } else {
        await FirebaseFirestore.instance.collection('proctoringSlots').add(
            {...data, 'createdAt': FieldValue.serverTimestamp()});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _removeAssignment(String key, String slotId) async {
    await FirebaseFirestore.instance
        .collection('proctoringSlots')
        .doc(slotId)
        .delete();
  }

  // ─── PDF Yazdır ────────────────────────────────────────────────────────────

  Future<void> _printSchedule() async {
    if (_selectedClasses.isEmpty || _timeSlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Yazdırmak için önce sınıf ve saat ayarı yapınız.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    // ── Türkçe destekli fontları yükle (Noto Sans) ───────────────────────
    final fontRegular = await PdfGoogleFonts.notoSansRegular();
    final fontBold    = await PdfGoogleFonts.notoSansBold();

    final pdf         = pw.Document();
    final purple      = PdfColor.fromHex('#7C3AED');
    final purpleLight = PdfColor.fromHex('#EDE9FE');
    final grey100     = PdfColor.fromHex('#F8F7FF');
    final grey400     = PdfColor.fromHex('#94A3B8');
    final examDateStr = DateFormat('dd.MM.yyyy').format(widget.examDate);
    final printedAt   = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

    // Sınıfları seviyeye göre grupla (sıralı)
    final Map<String, List<Map<String, dynamic>>> levelGroups = {};
    for (final cls in _sortedSelectedClasses) {
      final found = _allClasses.where((c) => c['id'] == cls['id']).firstOrNull;
      final lv = (found?['classLevel'] ?? '').toString();
      levelGroups.putIfAbsent(lv, () => []).add(cls);
    }

    // ── Her seviye için ayrı sayfa ──────────────────────────────────────
    for (final entry in levelGroups.entries) {
      final lv       = entry.key;
      final classes  = entry.value;
      final lvLabel  = lv.isNotEmpty ? '$lv. Sinif' : 'Diger';

      // Bu sayfadaki atama istatistikleri
      final lvTotalSlots = classes.length * _timeSlots.length;
      final lvAssigned = _assignments.values
          .where((s) =>
              s.teacherId != null &&
              classes.any((c) => c['id'] == s.classId))
          .length;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── Başlık ──────────────────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'GOZETMENLIK CIZELGESI',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 18,
                          color: purple,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        widget.examName,
                        style: pw.TextStyle(font: fontBold, fontSize: 13),
                      ),
                      pw.Text(
                        'Sinav Tarihi: $examDateStr',
                        style: pw.TextStyle(
                            font: fontRegular, fontSize: 10, color: grey400),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'eduKN',
                        style: pw.TextStyle(
                            font: fontBold, fontSize: 20, color: purple),
                      ),
                      pw.SizedBox(height: 4),
                      // Seviye badge
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: purple,
                          borderRadius:
                              const pw.BorderRadius.all(pw.Radius.circular(6)),
                        ),
                        child: pw.Text(
                          lvLabel,
                          style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 11,
                              color: PdfColors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(color: purple, thickness: 1.5),
              pw.SizedBox(height: 10),

              // ── Tablo ───────────────────────────────────────────────
              pw.Expanded(
                child: pw.Table(
                  border: pw.TableBorder.all(
                    color: PdfColor.fromHex('#E2E8F0'),
                    width: 0.5,
                  ),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(55),
                    for (int i = 1; i <= _timeSlots.length; i++)
                      i: const pw.FlexColumnWidth(1),
                  },
                  children: [
                    // Header
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: purple),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 9),
                          child: pw.Text(
                            'SINIF',
                            style: pw.TextStyle(
                                font: fontBold,
                                color: PdfColors.white,
                                fontSize: 10),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        ..._timeSlots.map((slot) => pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 9),
                              child: pw.Column(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.center,
                                children: [
                                  pw.Text(
                                    slot.label,
                                    style: pw.TextStyle(
                                        font: fontBold,
                                        color: PdfColors.white,
                                        fontSize: 10),
                                    textAlign: pw.TextAlign.center,
                                  ),
                                  pw.Text(
                                    '${slot.startTime}-${slot.endTime}',
                                    style: pw.TextStyle(
                                        font: fontRegular,
                                        color: PdfColors.white,
                                        fontSize: 8),
                                    textAlign: pw.TextAlign.center,
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                    // Veri satırları
                    ...classes.asMap().entries.map((entry) {
                      final idx     = entry.key;
                      final cls     = entry.value;
                      final classId = cls['id'] as String;
                      final name    = cls['name'] as String;

                      return pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: idx.isEven ? PdfColors.white : grey100,
                        ),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 6, vertical: 10),
                            child: pw.Text(
                              name,
                              style: pw.TextStyle(
                                  font: fontBold, fontSize: 10),
                            ),
                          ),
                          ..._timeSlots.asMap().entries.map((e) {
                            final slotIdx    = e.key;
                            final assignment =
                                _assignments['${classId}_$slotIdx'];
                            final hasTeacher =
                                assignment?.teacherId != null;

                            return pw.Container(
                              padding: const pw.EdgeInsets.all(5),
                              child: hasTeacher
                                  ? pw.Center(
                                      child: pw.Container(
                                        padding:
                                            const pw.EdgeInsets.symmetric(
                                                horizontal: 5, vertical: 4),
                                        decoration: pw.BoxDecoration(
                                          color: purpleLight,
                                          borderRadius:
                                              const pw.BorderRadius.all(
                                                  pw.Radius.circular(5)),
                                        ),
                                        child: pw.Text(
                                          assignment!.teacherName ?? '',
                                          style: pw.TextStyle(
                                              font: fontBold,
                                              fontSize: 8,
                                              color: purple),
                                          textAlign: pw.TextAlign.center,
                                        ),
                                      ),
                                    )
                                  : pw.Center(
                                      child: pw.Text(
                                        '-',
                                        style: pw.TextStyle(
                                            font: fontRegular,
                                            color: PdfColors.grey400,
                                            fontSize: 10),
                                      ),
                                    ),
                            );
                          }),
                        ],
                      );
                    }),
                  ],
                ),
              ),

              pw.SizedBox(height: 12),

              // ── Alt: özet + footer ──────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // Özet kutular
                  pw.Row(children: [
                    _pdfStat(fontBold, fontRegular, purple, purpleLight,
                        'Sinif', '${classes.length}'),
                    pw.SizedBox(width: 10),
                    _pdfStat(fontBold, fontRegular, purple, purpleLight,
                        'Toplam Slot', '$lvTotalSlots'),
                    pw.SizedBox(width: 10),
                    _pdfStat(fontBold, fontRegular, purple, purpleLight,
                        'Atandi', '$lvAssigned'),
                    pw.SizedBox(width: 10),
                    _pdfStat(fontBold, fontRegular, purple, purpleLight,
                        'Bos', '${lvTotalSlots - lvAssigned}'),
                  ]),
                  // Sayfa ve tarih
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Yazdirma: $printedAt',
                        style: pw.TextStyle(
                            font: fontRegular, fontSize: 8, color: grey400),
                      ),
                      pw.Text(
                        '${ctx.pageNumber} / ${ctx.pagesCount}',
                        style: pw.TextStyle(
                            font: fontRegular, fontSize: 8, color: grey400),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: '${widget.examName}_$examDateStr',
    );
  }

  pw.Widget _pdfStat(
    pw.Font fontBold,
    pw.Font fontRegular,
    PdfColor purple,
    PdfColor light,
    String label,
    String value,
  ) {
    return pw.Container(
      padding:
          const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: pw.BoxDecoration(
        color: light,
        borderRadius:
            const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(children: [
        pw.Text(value,
            style: pw.TextStyle(
                font: fontBold, fontSize: 16, color: purple)),
        pw.Text(label,
            style: pw.TextStyle(
                font: fontRegular,
                fontSize: 8,
                color: PdfColors.grey600)),
      ]),
    );
  }

  // ─── Paylaş ────────────────────────────────────────────────────────────────

  Future<void> _shareSchedule() async {
    final assigned =
        _assignments.values.where((s) => s.teacherId != null).toList();
    if (assigned.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Önce en az bir gözetmen ataması yapınız.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Çizelgeyi Paylaş',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
            '${assigned.length} öğretmene gözetmenlik bildirimi gönderilecek. Devam edilsin mi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Paylaş'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    setState(() => _isSharing = false);
  }

  // ─── Saat Ayarları ────────────────────────────────────────────────────────

  Future<void> _showSettings() async {
    // Çalışma kopyaları
    int tCount = _slotCount;
    final tSlots = List<Map<String, String>>.from(
        _manualSlots.map((s) => Map<String, String>.from(s)));

    // Eksik slotları tamamla
    while (tSlots.length < tCount) {
      tSlots.add({'start': '09:00', 'end': '09:40'});
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        // Slot sayısı değişince listeyi güncelle
        void syncSlots() {
          while (tSlots.length < tCount) {
            final last = tSlots.isNotEmpty
                ? tSlots.last
                : {'start': '09:00', 'end': '09:40'};
            tSlots.add(Map<String, String>.from(last));
          }
          while (tSlots.length > tCount) {
            tSlots.removeLast();
          }
        }

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Handle ──────────────────────────────────────────
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Saat Ayarları',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),

                // ── Saat Sayısı seçici ───────────────────────────────
                _SettingsRow(
                  label: 'Saat Sayısı',
                  value: '$tCount saat',
                  onIncrease: () => set(() {
                    tCount = (tCount + 1).clamp(1, 15);
                    syncSlots();
                  }),
                  onDecrease: () => set(() {
                    tCount = (tCount - 1).clamp(1, 15);
                    syncSlots();
                  }),
                ),
                const SizedBox(height: 20),

                // ── Her slot için başlangıç/bitiş ────────────────────
                ...List.generate(tCount, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F7FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFF7C3AED).withValues(alpha: 0.15)),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}. Saat',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF7C3AED)),
                          ),
                          const SizedBox(height: 10),
                          Row(children: [
                            // Başlangıç
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  final parts = tSlots[i]['start']!.split(':');
                                  final initial = TimeOfDay(
                                      hour: int.tryParse(parts[0]) ?? 9,
                                      minute: int.tryParse(parts[1]) ?? 0);
                                  final picked = await showTimePicker(
                                      context: ctx, initialTime: initial);
                                  if (picked != null) {
                                    set(() => tSlots[i]['start'] =
                                        '${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}');
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.grey.shade300),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Başlangıç',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade500)),
                                          Text(tSlots[i]['start']!,
                                              style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                      Icon(Icons.access_time_rounded,
                                          size: 18,
                                          color: const Color(0xFF7C3AED)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(Icons.arrow_forward_rounded,
                                size: 18, color: Colors.grey),
                            const SizedBox(width: 10),
                            // Bitiş
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  final parts = tSlots[i]['end']!.split(':');
                                  final initial = TimeOfDay(
                                      hour: int.tryParse(parts[0]) ?? 9,
                                      minute: int.tryParse(parts[1]) ?? 40);
                                  final picked = await showTimePicker(
                                      context: ctx, initialTime: initial);
                                  if (picked != null) {
                                    set(() => tSlots[i]['end'] =
                                        '${picked.hour.toString().padLeft(2,'0')}:${picked.minute.toString().padLeft(2,'0')}');
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.grey.shade300),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Bitiş',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade500)),
                                          Text(tSlots[i]['end']!,
                                              style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                      Icon(Icons.access_time_rounded,
                                          size: 18,
                                          color: const Color(0xFF7C3AED)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 8),
                // ── Kaydet ──────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      setState(() {
                        _slotCount = tCount;
                        _manualSlots = List.from(tSlots);
                        _rebuildTimeSlots();
                      });

                      try {
                        final settingsData = {
                          'institutionId': widget.institutionId,
                          'examId': widget.examId,
                          'slotCount': tCount,
                          'manualSlots': tSlots,
                          'updatedAt': FieldValue.serverTimestamp(),
                        };

                        await FirebaseFirestore.instance
                            .collection('proctoringSettings')
                            .doc('${widget.institutionId}_${widget.examId}')
                            .set(settingsData, SetOptions(merge: true));

                        await FirebaseFirestore.instance
                            .collection('proctoringSettings')
                            .doc(widget.examId)
                            .set(settingsData, SetOptions(merge: true));

                        await FirebaseFirestore.instance
                            .collection('proctoringExams')
                            .doc(widget.examId)
                            .set({
                          'slotCount': tCount,
                          'manualSlots': tSlots,
                        }, SetOptions(merge: true));
                      } catch (e) {
                        debugPrint('[Proctoring] Saat ayarları kayıt hatası: $e');
                      }

                      // Mevcut tüm atanmış slotların saatlerini yeni ayarlara senkronize et
                      await _syncAllSlotTimes();
                    },
                    child: const Text('Kaydet',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: EduknAppBar(
        title: widget.examName,
        subtitle: _df.format(widget.examDate),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded,
                color: Color(0xFF64748B)),
            tooltip: 'PDF Yazdır',
            onPressed: _printSchedule,
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded,
                color: Color(0xFF64748B)),
            tooltip: 'Saat Ayarları',
            onPressed: _showSettings,
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF7C3AED),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF7C3AED),
          tabs: const [
            Tab(icon: Icon(Icons.class_outlined), text: 'Sınıflar'),
            Tab(icon: Icon(Icons.grid_on_rounded), text: 'Çizelge'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: () {
                if (_isFabMenuOpen) setState(() => _isFabMenuOpen = false);
              },
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildClassSelector(),
                  _buildGrid(),
                ],
              ),
            ),
      floatingActionButton: _buildFab(),
    );
  }

  // ─── Expandable FAB ────────────────────────────────────────────────────────

  Widget _buildFab() {
    // Bildirim bekleyen atamalar (notificationSent=false olan)
    final pendingNotif = _assignments.values
        .where((s) => s.teacherId != null && s.notificationSent != true)
        .length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_isFabMenuOpen) ...[
          // 1. Yayınla / Yayından Kaldır
          _buildSpeedDialItem(
            label: _isPublished ? 'Yayından Kaldır' : 'Yayınla',
            icon: _isPublished
                ? Icons.visibility_off_rounded
                : Icons.publish_rounded,
            color: _isPublished
                ? const Color(0xFFEF4444)
                : const Color(0xFF10B981),
            onTap: () {
              setState(() => _isFabMenuOpen = false);
              _togglePublish();
            },
          ),
          const SizedBox(height: 10),

          // 2. Bildirim Gönder
          _buildSpeedDialItem(
            label: pendingNotif > 0
                ? 'Bildirim Gönder ($pendingNotif)'
                : 'Bildirim Gönder',
            icon: Icons.notifications_active_rounded,
            color: const Color(0xFFF59E0B),
            badgeCount: pendingNotif,
            onTap: () {
              setState(() => _isFabMenuOpen = false);
              _showSendNotificationDialog();
            },
          ),
          const SizedBox(height: 10),

          // 3. Çizelgeyi Boşalt
          _buildSpeedDialItem(
            label: 'Tüm Atamaları Sil',
            icon: Icons.delete_sweep_rounded,
            color: const Color(0xFFEF4444),
            onTap: () {
              setState(() => _isFabMenuOpen = false);
              _clearAllAssignments();
            },
          ),
          const SizedBox(height: 12),
        ],

        // Ana FAB
        FloatingActionButton(
          heroTag: 'proctoring_fab_main',
          backgroundColor: _isFabMenuOpen
              ? Colors.grey.shade800
              : const Color(0xFF7C3AED),
          foregroundColor: Colors.white,
          elevation: 6,
          tooltip: _isFabMenuOpen ? 'Kapat' : 'Gözetmenlik İşlemleri',
          onPressed: () => setState(() => _isFabMenuOpen = !_isFabMenuOpen),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isFabMenuOpen
                ? const Icon(Icons.close_rounded,
                    key: ValueKey('close'), size: 26)
                : Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        _isPublished
                            ? Icons.check_circle_outline_rounded
                            : Icons.menu_rounded,
                        key: const ValueKey('menu'),
                        size: 26,
                      ),
                      if (pendingNotif > 0)
                        Positioned(
                          top: -3,
                          right: -3,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedDialItem({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Etiket
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ),
        const SizedBox(width: 8),
        // Mini FAB
        FloatingActionButton.small(
          heroTag: label,
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 4,
          onPressed: onTap,
          child: Icon(icon, size: 20),
        ),
      ],
    );
  }

  // ─── Çizelgeyi Boşalt ──────────────────────────────────────────────────────

  Future<void> _clearAllAssignments() async {
    final assignedSlots = _assignments.values
        .where((s) => s.teacherId != null && s.id.isNotEmpty)
        .toList();

    if (assignedSlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Çizelgede silinecek atama bulunmuyor.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.delete_sweep_rounded,
                color: Colors.red.shade600, size: 22),
          ),
          const SizedBox(width: 10),
          const Text(
            'Çizelgeyi Boşalt',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${assignedSlots.length} öğretmen atamasının tamamı silinecek.',
              style: TextStyle(
                  color: Colors.grey.shade700, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.red.shade700, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Bu işlem geri alınamaz.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: Text('Tümünü Sil (${assignedSlots.length})'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Loading snackbar
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Row(children: [
        SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white)),
        SizedBox(width: 12),
        Text('Atamalar siliniyor...'),
      ]),
      duration: Duration(seconds: 6),
    ));

    try {
      // Firestore batch delete (max 500/batch)
      const batchSize = 400;
      for (int i = 0; i < assignedSlots.length; i += batchSize) {
        final chunk = assignedSlots.skip(i).take(batchSize);
        final batch = FirebaseFirestore.instance.batch();
        for (final slot in chunk) {
          batch.delete(FirebaseFirestore.instance
              .collection('proctoringSlots')
              .doc(slot.id));
        }
        await batch.commit();
      }

      // Lokal state temizle
      if (mounted) {
        setState(() {
          _assignments.clear();
          _isPublished = false;
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${assignedSlots.length} atama silindi. Çizelge temizlendi.'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Silme hatası: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ─── Yayınla / Yayından Kaldır ─────────────────────────────────────────────

  Future<void> _togglePublish() async {
    final newState = !_isPublished;
    final assignedCount =
        _assignments.values.where((s) => s.teacherId != null).length;

    if (newState && assignedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Yayınlamak için en az bir öğretmen ataması yapınız.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: newState
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              newState ? Icons.publish_rounded : Icons.visibility_off_rounded,
              color: newState ? Colors.green.shade700 : Colors.red.shade600,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            newState ? 'Çizelgeyi Yayınla' : 'Yayından Kaldır',
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ]),
        content: Text(
          newState
              ? 'Bu çizelge öğretmenlerin takviminde görünür hale gelecek. Devam?'
              : 'Çizelge öğretmenlerin takviminden kaldırılacak. Devam?',
          style: TextStyle(
              color: Colors.grey.shade700, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  newState ? Colors.green.shade600 : Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(newState ? 'Yayınla' : 'Kaldır'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isPublished = newState);

    // Firestore'da examı güncelle
    await FirebaseFirestore.instance
        .collection('proctoringExams')
        .doc(widget.examId)
        .update({'isPublished': newState});

    // Tüm slot'ları da güncelle (öğretmen sorgulayabilsin)
    final batch = FirebaseFirestore.instance.batch();
    for (final slot in _assignments.values) {
      if (slot.teacherId != null) {
        final timeSlot = (slot.slotIndex >= 0 && slot.slotIndex < _timeSlots.length)
            ? _timeSlots[slot.slotIndex]
            : null;
        batch.update(
          FirebaseFirestore.instance.collection('proctoringSlots').doc(slot.id),
          {
            'isPublished': newState,
            if (timeSlot != null) ...{
              'slotLabel': timeSlot.label,
              'startTime': timeSlot.startTime,
              'endTime': timeSlot.endTime,
            },
          },
        );
      }
    }
    await batch.commit();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newState
            ? 'Çizelge yayınlandı! Öğretmenler takvimlerinde görebilir.'
            : 'Çizelge yayından kaldırıldı.'),
        backgroundColor:
            newState ? const Color(0xFF10B981) : Colors.orange,
      ));
    }
  }

  // ─── Bildirim Gönder ───────────────────────────────────────────────────────

  Future<void> _showSendNotificationDialog() async {
    final allAssigned = _assignments.values
        .where((s) => s.teacherId != null)
        .toList();

    if (allAssigned.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Bildirim göndermek için önce öğretmen ataması yapın.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final pending = allAssigned
        .where((s) => s.notificationSent != true)
        .toList();
    bool forceSendAll = false;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final targets = forceSendAll ? allAssigned : pending;
          final count = targets.length;

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.notifications_active_rounded,
                    color: Color(0xFFF59E0B), size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Gözetmenlik Bildirimi',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ]),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pending.isEmpty && !forceSendAll) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(children: [
                        Icon(Icons.check_circle_rounded,
                            color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tüm atanmış öğretmenlere bildirim gönderildi.',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade900,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Text(
                      forceSendAll
                          ? 'Tüm gözetmenlere (${allAssigned.length} kişi) bildirim gönderilecek:'
                          : 'Bildirim gitmemiş / değişen $count öğretmen:',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 240),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (int i = 0; i < targets.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: const Color(0xFF7C3AED)
                                      .withValues(alpha: 0.12),
                                  child: Text(
                                    (targets[i].teacherName ?? '?')
                                        .substring(0, 1)
                                        .toUpperCase(),
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF7C3AED)),
                                  ),
                                ),
                                title: Text(targets[i].teacherName ?? '',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  '${targets[i].className}  ·  ${_timeSlots.length > targets[i].slotIndex ? _timeSlots[targets[i].slotIndex].label : ''}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B)),
                                ),
                                trailing: targets[i].notificationSent == true
                                    ? const Icon(Icons.done_all,
                                        size: 16, color: Colors.green)
                                    : Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade100,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text('Yeni / Değişen',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    Colors.amber.shade900)),
                                      ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: forceSendAll,
                    activeColor: const Color(0xFF7C3AED),
                    title: Text(
                      'Tüm gözetmenlere tekrar gönder (${allAssigned.length} kişi)',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    onChanged: (v) => setDlg(() => forceSendAll = v ?? false),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('İptal')),
              ElevatedButton.icon(
                onPressed: (pending.isEmpty && !forceSendAll)
                    ? null
                    : () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.send_rounded, size: 16),
                label: Text(forceSendAll
                    ? 'Tümüne Gönder (${allAssigned.length})'
                    : 'Gönder ($count)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirm != true) return;

    final allAssigned2 = _assignments.values
        .where((s) => s.teacherId != null)
        .toList();
    final pending2 =
        allAssigned2.where((s) => s.notificationSent != true).toList();
    final targets =
        (pending2.isEmpty ? allAssigned2 : pending2);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 12),
          Text('Bildirimler iletiliyor...'),
        ]),
        duration: Duration(seconds: 4),
      ));
    }

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final slot in targets) {
        if (slot.id.isNotEmpty) {
          batch.update(
            FirebaseFirestore.instance
                .collection('proctoringSlots')
                .doc(slot.id),
            {
              'sendNotification': true,
              'notificationSent': true,
              'notifiedTeacherId': slot.teacherId,
              'notificationRequestedAt': FieldValue.serverTimestamp(),
            },
          );
        }
      }
      await batch.commit();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${targets.length} öğretmene gözetmenlik bildirimi gönderildi.'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Bildirim hatası: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ─── Tab 1: Sınıf Seçici ─────────────────────────────────────────────────

  Widget _buildClassSelector() {
    if (_allClasses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.class_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('Sınıf bulunamadı.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // Seviye bazlı grupla (sıralı)
    final levelMap = <String, List<Map<String, dynamic>>>{};
    for (final c in _allClasses) {
      final lv = c['classLevel'] as String;
      levelMap.putIfAbsent(lv, () => []).add(c);
    }
    final sortedLevels = levelMap.keys.toList()
      ..sort((a, b) {
        final ia = int.tryParse(a) ?? 99;
        final ib = int.tryParse(b) ?? 99;
        return ia.compareTo(ib);
      });

    final totalCount = _allClasses.length;
    final selCount = _selectedClasses.length;

    return Column(
      children: [
        // ── Üst özet bar ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
          ),
          child: Row(
            children: [
              // Seçili sayaç
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: selCount > 0
                      ? const Color(0xFF7C3AED).withValues(alpha: 0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  selCount > 0 ? '$selCount / $totalCount seçili' : 'Sınıf seçilmedi',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: selCount > 0 ? const Color(0xFF7C3AED) : Colors.grey,
                  ),
                ),
              ),
              const Spacer(),
              // Tümünü seç / kaldır
              if (selCount == totalCount)
                TextButton.icon(
                  onPressed: _clearAllClasses,
                  icon: const Icon(Icons.deselect, size: 16),
                  label: const Text('Temizle'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                )
              else
                TextButton.icon(
                  onPressed: _selectAllClasses,
                  icon: const Icon(Icons.select_all, size: 16),
                  label: const Text('Tümünü Seç'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF7C3AED)),
                ),
            ],
          ),
        ),

        // ── Seviye grupları ────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            itemCount: sortedLevels.length,
            itemBuilder: (ctx, i) {
              final lv = sortedLevels[i];
              final classes = levelMap[lv]!;
              final lvLabel = lv.isNotEmpty ? '$lv. Sınıf' : 'Diğer';
              final allLvSelected =
                  classes.every((c) => _isClassSelected(c['id'] as String));
              final someLvSelected =
                  classes.any((c) => _isClassSelected(c['id'] as String));
              final lvSelCount =
                  classes.where((c) => _isClassSelected(c['id'] as String)).length;

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Seviye başlığı (tıklanabilir) ──────────────
                    GestureDetector(
                      onTap: () => _toggleLevel(classes, allLvSelected),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: allLvSelected
                              ? const LinearGradient(
                                  colors: [Color(0xFF7C3AED), Color(0xFF9F67FA)],
                                )
                              : someLvSelected
                                  ? LinearGradient(
                                      colors: [
                                        const Color(0xFF7C3AED).withValues(alpha: 0.15),
                                        const Color(0xFF9F67FA).withValues(alpha: 0.08),
                                      ],
                                    )
                                  : null,
                          color: (!allLvSelected && !someLvSelected)
                              ? Colors.grey.shade100
                              : null,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            // İkon
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: allLvSelected
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : const Color(0xFF7C3AED).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(
                                allLvSelected
                                    ? Icons.check_circle_rounded
                                    : someLvSelected
                                        ? Icons.indeterminate_check_box_rounded
                                        : Icons.school_outlined,
                                size: 18,
                                color: allLvSelected
                                    ? Colors.white
                                    : const Color(0xFF7C3AED),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Etiket
                            Text(
                              lvLabel,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: allLvSelected
                                    ? Colors.white
                                    : const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Sayaç badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: allLvSelected
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : const Color(0xFF7C3AED).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$lvSelCount/${classes.length}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: allLvSelected
                                      ? Colors.white
                                      : const Color(0xFF7C3AED),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              allLvSelected
                                  ? Icons.remove_circle_outline_rounded
                                  : Icons.add_circle_outline_rounded,
                              size: 18,
                              color: allLvSelected
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : const Color(0xFF7C3AED),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── Sınıf chip'leri ──────────────────────────────
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: classes.map((cls) {
                        final id = cls['id'] as String;
                        final name = cls['name'] as String;
                        final selected = _isClassSelected(id);
                        return GestureDetector(
                          onTap: () => _toggleClass(cls),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF7C3AED)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF7C3AED)
                                    : Colors.grey.shade200,
                                width: selected ? 0 : 1.5,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF7C3AED)
                                            .withValues(alpha: 0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      )
                                    ]
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.04),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      )
                                    ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (selected) ...[
                                  const Icon(Icons.check,
                                      size: 13, color: Colors.white),
                                  const SizedBox(width: 5),
                                ],
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // ── Alt buton ─────────────────────────────────────────────
        if (_selectedClasses.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              border:
                  Border(top: BorderSide(color: Colors.grey.shade100)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.grid_on_rounded, size: 18),
                label: Text(
                  'Çizelgeye Geç  ·  ${_selectedClasses.length} sınıf',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                onPressed: () => _tabController.animateTo(1),
              ),
            ),
          ),
      ],
    );
  }

  // Seviye tümünü seç/kaldır
  Future<void> _toggleLevel(
      List<Map<String, dynamic>> classes, bool allSelected) async {
    setState(() {
      if (allSelected) {
        _selectedClasses
            .removeWhere((s) => classes.any((c) => c['id'] == s['id']));
      } else {
        for (final cls in classes) {
          if (!_isClassSelected(cls['id'] as String)) {
            _selectedClasses.add({'id': cls['id'], 'name': cls['name']});
          }
        }
      }
    });
    await _saveSelectedClasses();
  }

  Future<void> _selectAllClasses() async {
    setState(() {
      _selectedClasses.clear();
      _selectedClasses.addAll(_allClasses
          .map((c) => {'id': c['id'], 'name': c['name']}));
    });
    await _saveSelectedClasses();
  }

  Future<void> _clearAllClasses() async {
    setState(() => _selectedClasses.clear());
    await _saveSelectedClasses();
  }

  Future<void> _saveSelectedClasses() async {
    await FirebaseFirestore.instance
        .collection('proctoringExams')
        .doc(widget.examId)
        .update({
      'classIds': _selectedClasses.map((c) => c['id']).toList(),
      'classNames': _selectedClasses.map((c) => c['name']).toList(),
    });
  }

  // ─── Tab 2: Çizelge ───────────────────────────────────────────────────────

  Widget _buildGrid() {
    if (_selectedClasses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_box_outline_blank,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('Önce sınıf seçimi yapınız.',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _tabController.animateTo(0),
              icon: const Icon(Icons.class_outlined),
              label: const Text('Sınıf Seçimine Git'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    if (_timeSlots.isEmpty) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: _showSettings,
          icon: const Icon(Icons.tune_rounded),
          label: const Text('Saat Ayarlarını Aç'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    final assignedCount =
        _assignments.values.where((s) => s.teacherId != null).length;
    final totalSlots = _selectedClasses.length * _timeSlots.length;

    return Column(
      children: [
        // Özet bar
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white,
          child: Row(
            children: [
              _LegendChip(
                  color: const Color(0xFF7C3AED),
                  label: 'Atandı ($assignedCount)'),
              const SizedBox(width: 8),
              _LegendChip(
                  color: Colors.grey.shade300,
                  label: 'Boş (${totalSlots - assignedCount})'),
              const Spacer(),
              Text(
                '${_selectedClasses.length} sınıf · ${_timeSlots.length} saat',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildTable(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    const double colW = 130.0;
    const double rowH = 70.0;
    const double headerH = 66.0;
    const double classColW = 110.0;

    return Table(
      defaultColumnWidth: const FixedColumnWidth(colW),
      columnWidths: {0: const FixedColumnWidth(classColW)},
      border: TableBorder.all(color: Colors.grey.shade200, width: 0.5),
      children: [
        // Header
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFF7C3AED)),
          children: [
            SizedBox(
              height: headerH,
              child: const Center(
                child: Text('Sınıf',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ),
            ..._timeSlots.map((slot) => SizedBox(
                  height: headerH,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(slot.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(slot.startTime,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                      Text(slot.endTime,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                )),
          ],
        ),
        // Satırlar
        ..._sortedSelectedClasses.asMap().entries.map((entry) {
          final idx = entry.key;
          final cls = entry.value;
          final classId = cls['id'] as String;
          final className = cls['name'] as String;

          return TableRow(
            decoration: BoxDecoration(
              color: idx.isEven ? Colors.white : const Color(0xFFFAF9FF),
            ),
            children: [
              SizedBox(
                height: rowH,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      className,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Color(0xFF1E293B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              ..._timeSlots.asMap().entries.map((e) {
                final slotIdx = e.key;
                final key = '${classId}_$slotIdx';
                final assignment = _assignments[key];
                final has = assignment?.teacherId != null;

                // Çakışma kontrolü: bu öğretmen aynı saatte başka sınıfta da var mı?
                final isConflict = has &&
                    _assignments.entries.any((x) =>
                        x.value.teacherId == assignment!.teacherId &&
                        x.value.slotIndex == slotIdx &&
                        x.value.classId != classId);

                return SizedBox(
                  height: rowH,
                  child: InkWell(
                    onTap: () =>
                        _showTeacherPicker(classId, className, slotIdx),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isConflict
                            ? Colors.orange.shade50
                            : has
                                ? const Color(0xFF7C3AED).withValues(alpha: 0.08)
                                : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isConflict
                              ? Colors.orange.shade400
                              : has
                                  ? const Color(0xFF7C3AED).withValues(alpha: 0.3)
                                  : Colors.grey.shade200,
                          width: (has || isConflict) ? 1.5 : 1,
                        ),
                      ),
                      child: has
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isConflict
                                      ? Icons.warning_amber_rounded
                                      : Icons.person,
                                  size: 14,
                                  color: isConflict
                                      ? Colors.orange.shade600
                                      : const Color(0xFF7C3AED),
                                ),
                                const SizedBox(height: 2),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  child: Text(
                                    assignment!.teacherName ?? '',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: isConflict
                                            ? Colors.orange.shade700
                                            : const Color(0xFF5B21B6)),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            )
                          : Center(
                              child: Icon(Icons.add,
                                  size: 16,
                                  color: Colors.grey.shade400)),
                    ),
                  ),
                );
              }),
            ],
          );
        }),
      ],
    );
  }
}

// ─── Yardımcı Widget'lar ─────────────────────────────────────────────────────

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
    ]);
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;

  const _SettingsRow(
      {required this.label,
      required this.value,
      this.onIncrease,
      this.onDecrease}) : onTap = null;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF1E293B))),
              ],
            ),
          ),
          if (onTap != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: const Color(0xFF7C3AED),
              onPressed: onTap,
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 22),
              color: Colors.grey.shade500,
              onPressed: onDecrease,
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 22),
              color: const Color(0xFF7C3AED),
              onPressed: onIncrease,
            ),
          ],
        ],
      ),
    );
  }
}
