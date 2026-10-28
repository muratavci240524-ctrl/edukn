import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../models/school/butterfly_exam_model.dart';
import '../../../../services/user_permission_service.dart';
import '../../../../widgets/edukn_app_bar.dart';

/// Kelebek sınavında salon bazlı yoklama (geldi / gelmedi) ekranı.
/// Yoklama, sınav belgesindeki `attendance.{salonAnahtarı}.{öğrenciId}` alanına otomatik ve anlık kaydedilir.
enum _AttFilter { all, present, absent, pending }
enum _SyncState { idle, syncing, synced, error }

class ButterflyAttendanceScreen extends StatefulWidget {
  final ExamDistribution distribution;
  final String? initialClassroomName;
  final int? initialRoomIndex;
  final int? initialSessionIndex;

  const ButterflyAttendanceScreen({
    super.key,
    required this.distribution,
    this.initialClassroomName,
    this.initialRoomIndex,
    this.initialSessionIndex,
  });

  @override
  State<ButterflyAttendanceScreen> createState() => _ButterflyAttendanceScreenState();
}

class _ButterflyAttendanceScreenState extends State<ButterflyAttendanceScreen> {
  static const _indigo = Color(0xFF4F46E5);
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFEF4444);

  int _roomIndex = 0;
  int _sessionSlotIndex = 0;
  _AttFilter _filter = _AttFilter.all;
  bool _loading = true;
  _SyncState _syncState = _SyncState.idle;
  String? _syncError;
  DocumentReference<Map<String, dynamic>>? _docRef;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  /// salonAnahtarı -> { öğrenciId: true (geldi) / false (gelmedi) }
  final Map<String, Map<String, bool>> _attendance = {};

  ExamRoom get _room => widget.distribution.rooms[_roomIndex];

  String _roomKey(ExamRoom r, int index) {
    final base = r.id.isNotEmpty
        ? r.id
        : (r.classroomId.isNotEmpty ? r.classroomId : 'room_$index');
    if (widget.distribution.sessionSlots.length > 1) {
      final slots = widget.distribution.sessionSlots;
      if (_sessionSlotIndex >= 0 && _sessionSlotIndex < slots.length) {
        final sessIdx = slots[_sessionSlotIndex]['sessionIndex'] ?? _sessionSlotIndex;
        return '${base}_s$sessIdx';
      }
      return '${base}_s$_sessionSlotIndex';
    }
    return base;
  }

  String get _currentKey => _roomKey(_room, _roomIndex);

  bool get _isTeacher {
    final role = (UserPermissionService.cachedUserData?['role'] as String?)?.toLowerCase() ?? '';
    return role.contains('ogretmen') || role.contains('öğretmen') || role == 'teacher';
  }

  bool _isApproved() {
    final approvals = widget.distribution.instructionApprovals;
    if (approvals.isEmpty) return false;
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (authUid.isNotEmpty && approvals.containsKey(authUid)) return true;

    final userData = UserPermissionService.cachedUserData;
    final docId = userData?['id']?.toString();
    final authUserId = userData?['authUserId']?.toString();
    final tId = userData?['teacherId']?.toString();
    final staffId = userData?['staffId']?.toString();

    if (docId != null && docId.isNotEmpty && approvals.containsKey(docId)) return true;
    if (authUserId != null && authUserId.isNotEmpty && approvals.containsKey(authUserId)) return true;
    if (tId != null && tId.isNotEmpty && approvals.containsKey(tId)) return true;
    if (staffId != null && staffId.isNotEmpty && approvals.containsKey(staffId)) return true;

    return false;
  }

  void _showMandatoryInstructionModal() {
    final instructions = widget.distribution.instructions.isNotEmpty
        ? widget.distribution.instructions
        : [
            'Gözetmen öğretmenler sınav başlangıç saatinden 15 dakika önce sınav evraklarını idareden teslim almalıdır.',
            'Öğrenciler sınav salonuna cep telefonu, akıllı saat veya haberleşme araçlarıyla giremez.',
            'Sınav başlamadan önce öğrencilerin kimlik ve salon oturma planı kontrolleri eksiksiz yapılmalıdır.',
            'Sınav evrak poşeti öğrenciler huzurunda açılarak optik form ve kitapçıklar kontrol edilmelidir.',
            'Sınavın ilk 15 dakikası ve son 10 dakikası hiçbir öğrencinin salondan çıkışına izin verilmez.',
            'Sınav bitiminde sınav evrakları eksiksiz toplanarak salon yoklama tutanağı gözetmen tarafından imzalanmalıdır.',
          ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.82,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.gavel_rounded, color: Color(0xFF4F46E5), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sınav Uygulama Yönergesi',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                          ),
                          Text(
                            '${widget.distribution.title} • ${widget.distribution.lessonName}',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        if (!_isApproved() && mounted) {
                          Navigator.pop(context); // Onaylamadan çıkarsa yoklama ekranından ayrıl
                        }
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_rounded, color: Color(0xFFD97706), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Yoklama alabilmek için lütfen yönerge maddelerini okuyup en alttaki "Okudum, Onaylıyorum" butonuna basınız.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF92400E),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: instructions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4F46E5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${idx + 1}',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              instructions[idx],
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: const Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.2)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF64748B).withValues(alpha: 0.1),
                      blurRadius: 12,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                      label: Text(
                        'Okudum, Onaylıyorum',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      onPressed: () => _approveInstructionsFromAttendance(sheetCtx),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      if (!_isApproved() && mounted) {
        Navigator.pop(context); // Onaylanmadıysa yoklama ekranından çık
      }
    });
  }

  Future<void> _approveInstructionsFromAttendance(BuildContext sheetCtx) async {
    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final userData = UserPermissionService.cachedUserData;
      final teacherName = UserPermissionService.getUserDisplayName(userData);
      final approvalRecord = {
        'teacherId': authUid,
        'teacherName': teacherName,
        'approvedAt': Timestamp.now(),
      };

      final Map<String, dynamic> updateMap = {};
      if (authUid.isNotEmpty) updateMap[authUid] = approvalRecord;
      final docId = userData?['id']?.toString();
      if (docId != null && docId.isNotEmpty) updateMap[docId] = approvalRecord;
      final tId = userData?['teacherId']?.toString();
      if (tId != null && tId.isNotEmpty) updateMap[tId] = approvalRecord;

      final examId = widget.distribution.id ?? '';
      if (examId.isNotEmpty) {
        final db = FirebaseFirestore.instance;
        await db.collection('butterfly_exams').doc(examId).set({
          'instructionApprovals': updateMap,
        }, SetOptions(merge: true)).catchError((_) {});
        await db.collection('seating_plans').doc(examId).set({
          'instructionApprovals': updateMap,
        }, SetOptions(merge: true)).catchError((_) {});
      }

      widget.distribution.instructionApprovals.addAll(updateMap);

      if (sheetCtx.mounted) {
        Navigator.pop(sheetCtx);
      }

      if (mounted) {
        setState(() {}); // Ekranı güncelle
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sınav yönergesi okundu ve onaylandı olarak sisteme işlendi.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Onay işlemi kaydedilemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Oturum indeksini belirle
    if (widget.initialSessionIndex != null &&
        widget.initialSessionIndex! >= 0 &&
        widget.initialSessionIndex! < widget.distribution.sessionSlots.length) {
      _sessionSlotIndex = widget.initialSessionIndex!;
    }
    // İlk açılacak salonu belirle
    if (widget.initialRoomIndex != null &&
        widget.initialRoomIndex! >= 0 &&
        widget.initialRoomIndex! < widget.distribution.rooms.length) {
      _roomIndex = widget.initialRoomIndex!;
    } else if (widget.initialClassroomName != null &&
        widget.initialClassroomName!.isNotEmpty) {
      final target = widget.initialClassroomName!.trim().toLowerCase();
      final idx = widget.distribution.rooms.indexWhere((r) =>
          r.classroomName.trim().toLowerCase() == target ||
          r.classroomId.trim().toLowerCase() == target);
      if (idx != -1) _roomIndex = idx;
    }
    _initStream();

    // Öğretmen için yönerge onay zorunluluğu kapısı
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isTeacher && widget.distribution.instructions.isNotEmpty && !_isApproved()) {
        _showMandatoryInstructionModal();
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _initStream() async {
    final id = widget.distribution.id;
    if (id == null || id.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final db = FirebaseFirestore.instance;
      var ref = db.collection('butterfly_exams').doc(id);
      var snap = await ref.get();
      if (!snap.exists) {
        ref = db.collection('seating_plans').doc(id);
        snap = await ref.get();
      }
      _docRef = ref;

      _applySnapshot(snap);

      // Canlı dinleme başlat (diğer öğretmenler veya idarecinin anlık değişiklikleri düşer)
      _subscription?.cancel();
      _subscription = ref.snapshots().listen(
        (updatedSnap) {
          _applySnapshot(updatedSnap);
        },
        onError: (e) {
          debugPrint('Yoklama canlı dinleme hatası: $e');
          if (mounted) {
            setState(() {
              _syncState = _SyncState.error;
              _syncError = 'Bağlantı koptu';
            });
          }
        },
      );
    } catch (e) {
      debugPrint('Yoklama yüklenemedi: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _syncState = _SyncState.error;
          _syncError = 'Yüklenemedi';
        });
      }
    }
  }

  void _applySnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final rawApprovals = snap.data()?['instructionApprovals'];
    if (rawApprovals is Map) {
      rawApprovals.forEach((k, v) {
        widget.distribution.instructionApprovals[k.toString()] = v;
      });
    }
    final raw = snap.data()?['attendance'];
    final Map<String, Map<String, bool>> incoming = {};
    if (raw is Map) {
      raw.forEach((roomKey, v) {
        if (v is Map) {
          incoming[roomKey.toString()] = {
            for (final e in v.entries) e.key.toString(): e.value == true,
          };
        }
      });
    }
    if (mounted) {
      setState(() {
        _attendance.clear();
        _attendance.addAll(incoming);
        _loading = false;
        if (_syncState != _SyncState.syncing) {
          _syncState = _SyncState.synced;
        }
      });
    }
  }

  List<SeatCoordinate> _seatedSeats(ExamRoom r) {
    final list = r.seats.where((s) => s.student != null).toList();
    list.sort((a, b) => a.seatNumber.compareTo(b.seatNumber));
    return list;
  }

  /// Salon için işaretlenen (geldi, gelmedi) sayısı.
  (int, int, int) _counts(ExamRoom r, int index) {
    final seats = _seatedSeats(r);
    final map = _attendance[_roomKey(r, index)] ?? const {};
    var present = 0, absent = 0;
    for (final s in seats) {
      final v = map[s.student!.id];
      if (v == true) present++;
      if (v == false) absent++;
    }
    return (present, absent, seats.length);
  }

  /// Tek öğrenci için anında optimistik ve nokta atışı (FieldPath) otomatik kayıt.
  Future<void> _mark(String studentId, bool? value) async {
    // Öğretmen Yönerge Kontrolü: Onaylamadan yoklama işaretleyemez!
    if (_isTeacher && widget.distribution.instructions.isNotEmpty && !_isApproved()) {
      _showMandatoryInstructionModal();
      return;
    }

    // 1. Kullanıcı arayüzünde 0ms anında tepki
    setState(() {
      final map = _attendance.putIfAbsent(_currentKey, () => {});
      if (value == null) {
        map.remove(studentId);
      } else {
        map[studentId] = value;
      }
      _syncState = _SyncState.syncing;
      _syncError = null;
    });

    final ref = _docRef;
    if (ref == null) return;

    // 2. Nokta atışı Firestore güncellemesi (Diğer salonlar ve öğrenciler asla ezilmez)
    try {
      await ref.update({
        FieldPath(['attendance', _currentKey, studentId]):
            value ?? FieldValue.delete(),
        'attendanceUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => _syncState = _SyncState.synced);
    } catch (e) {
      // Eğer belgede henüz attendance map alanı yoksa set merge ile oluştur
      try {
        await ref.set({
          'attendance': {
            _currentKey: {
              studentId: value,
            },
          },
          'attendanceUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (mounted) setState(() => _syncState = _SyncState.synced);
      } catch (err2) {
        debugPrint('Yoklama otomatik kayıt hatası: $err2');
        if (mounted) {
          setState(() {
            _syncState = _SyncState.error;
            _syncError = 'Kaydedilemedi';
          });
        }
      }
    }
  }

  /// Salondaki tüm öğrencileri geldi/gelmedi yap (Sadece bu salonun haritasını günceller).
  Future<void> _markAll(bool value) async {
    final seats = _seatedSeats(_room);
    if (seats.isEmpty) return;

    setState(() {
      final map = _attendance.putIfAbsent(_currentKey, () => {});
      for (final s in seats) {
        map[s.student!.id] = value;
      }
      _syncState = _SyncState.syncing;
      _syncError = null;
    });

    final ref = _docRef;
    if (ref == null) return;

    final roomMap = <String, bool>{
      for (final s in seats) s.student!.id: value,
    };

    try {
      await ref.update({
        FieldPath(['attendance', _currentKey]): roomMap,
        'attendanceUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => _syncState = _SyncState.synced);
    } catch (e) {
      try {
        await ref.set({
          'attendance': {
            _currentKey: roomMap,
          },
          'attendanceUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (mounted) setState(() => _syncState = _SyncState.synced);
      } catch (err2) {
        if (mounted) {
          setState(() {
            _syncState = _SyncState.error;
            _syncError = 'Kaydedilemedi';
          });
        }
      }
    }
  }

  Widget _buildSyncBadge() {
    Color bg;
    Color fg;
    IconData icon;
    String text;

    switch (_syncState) {
      case _SyncState.syncing:
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF2563EB);
        icon = Icons.sync_rounded;
        text = 'Kaydediliyor...';
        break;
      case _SyncState.synced:
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF059669);
        icon = Icons.cloud_done_rounded;
        text = 'Otomatik Kaydedildi';
        break;
      case _SyncState.error:
        bg = const Color(0xFFFEF2F2);
        fg = const Color(0xFFDC2626);
        icon = Icons.cloud_off_rounded;
        text = _syncError ?? 'Hata';
        break;
      case _SyncState.idle:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF64748B);
        icon = Icons.cloud_queue_rounded;
        text = 'Canlı';
        break;
    }

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Center(
      child: Tooltip(
        message: text,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: isMobile
              ? const EdgeInsets.all(7)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            shape: isMobile ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isMobile ? null : BorderRadius.circular(20),
            border: Border.all(color: fg.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_syncState == _SyncState.syncing)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              else
                Icon(icon, size: 16, color: fg),
              if (!isMobile) ...[
                const SizedBox(width: 5),
                Text(
                  text,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.distribution;
    final dateStr = DateFormat('dd.MM.yyyy').format(d.examDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: 'Yoklama Al',
        subtitle: '${d.title} • $dateStr',
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        subtitleColor: const Color(0xFF64748B),
        backButtonColor: _indigo,
        borderColor: const Color(0xFFE2E8F0),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _buildSyncBadge(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _indigo))
          : Column(
              children: [
                // Başlık bölümü liste ile birlikte kayar; listeye daha çok yer kalır.
                Expanded(child: _studentList()),
                _bottomNav(),
              ],
            ),
    );
  }

  /// Tüm salonları kaydırmadan gösteren, ilerleme çubuklu çip ızgarası.
  Widget _roomGrid() {
    final rooms = widget.distribution.rooms;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (int i = 0; i < rooms.length; i++)
            Builder(builder: (_) {
              final (p, a, t) = _counts(rooms[i], i);
              final selected = i == _roomIndex;
              final done = t > 0 && p + a == t;
              final ratio = t == 0 ? 0.0 : (p + a) / t;
              final fg = selected ? Colors.white : const Color(0xFF1E293B);
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _roomIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 66,
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 5),
                  decoration: BoxDecoration(
                    color: selected ? _indigo : (done ? _green.withValues(alpha: 0.1) : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? _indigo : (done ? _green : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (done) ...[
                            Icon(Icons.check_circle_rounded, size: 12, color: selected ? Colors.white : _green),
                            const SizedBox(width: 3),
                          ],
                          Flexible(
                            child: Text(
                              rooms[i].classroomName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13.5, color: fg),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${p + a}/$t',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 10.5,
                          color: selected ? Colors.white70 : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 3.5,
                          backgroundColor: selected ? Colors.white24 : const Color(0xFFE2E8F0),
                          valueColor: AlwaysStoppedAnimation(selected ? Colors.white : (done ? _green : _indigo)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
      ),
    );
  }

  /// Sayılar aynı zamanda filtre görevi görür: Geldi / Gelmedi / Bekleyen.
  Widget _statFilters() {
    final (p, a, t) = _counts(_room, _roomIndex);
    final pending = t - p - a;

    Widget chip(_AttFilter f, String label, int value, Color c) {
      final on = _filter == f;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _filter = on ? _AttFilter.all : f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: on ? c : c.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$value',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900, fontSize: 16, color: on ? Colors.white : c)),
                const SizedBox(width: 5),
                Text(label,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700, fontSize: 10.5, color: on ? Colors.white : c)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(_AttFilter.present, 'Geldi', p, _green),
        const SizedBox(width: 6),
        chip(_AttFilter.absent, 'Gelmedi', a, _red),
        const SizedBox(width: 6),
        chip(_AttFilter.pending, 'Bekleyen', pending, const Color(0xFFF59E0B)),
        const SizedBox(width: 6),
        PopupMenuButton<String>(
          tooltip: 'Toplu işlem',
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
          onSelected: (v) {
            if (v == 'all') _markAll(true);
            if (v == 'pendingAbsent') _markPendingAbsent();
            if (v == 'reset') _resetRoom();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'all', child: Text('Hepsi geldi')),
            PopupMenuItem(value: 'pendingAbsent', child: Text('Bekleyenleri gelmedi yap')),
            PopupMenuItem(value: 'reset', child: Text('Salonu sıfırla')),
          ],
        ),
      ],
    );
  }

  Future<void> _markPendingAbsent() async {
    final seats = _seatedSeats(_room);
    if (seats.isEmpty) return;

    setState(() {
      final map = _attendance.putIfAbsent(_currentKey, () => {});
      for (final s in seats) {
        map.putIfAbsent(s.student!.id, () => false);
      }
      _syncState = _SyncState.syncing;
      _syncError = null;
    });

    final ref = _docRef;
    if (ref == null) return;

    final currentRoomMap = _attendance[_currentKey] ?? {};

    try {
      await ref.update({
        FieldPath(['attendance', _currentKey]): currentRoomMap,
        'attendanceUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => _syncState = _SyncState.synced);
    } catch (e) {
      try {
        await ref.set({
          'attendance': {
            _currentKey: currentRoomMap,
          },
          'attendanceUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (mounted) setState(() => _syncState = _SyncState.synced);
      } catch (err2) {
        if (mounted) {
          setState(() {
            _syncState = _SyncState.error;
            _syncError = 'Kaydedilemedi';
          });
        }
      }
    }
  }

  Future<void> _resetRoom() async {
    setState(() {
      _attendance[_currentKey] = {};
      _syncState = _SyncState.syncing;
      _syncError = null;
    });

    final ref = _docRef;
    if (ref == null) return;

    try {
      await ref.update({
        FieldPath(['attendance', _currentKey]): <String, dynamic>{},
        'attendanceUpdatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => _syncState = _SyncState.synced);
    } catch (e) {
      try {
        await ref.set({
          'attendance': {
            _currentKey: {},
          },
          'attendanceUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (mounted) setState(() => _syncState = _SyncState.synced);
      } catch (err2) {
        if (mounted) {
          setState(() {
            _syncState = _SyncState.error;
            _syncError = 'Sıfırlanamadı';
          });
        }
      }
    }
  }

  /// Alt gezinme: önceki / sonraki salon (tek elle hızlı geçiş).
  Widget _bottomNav() {
    final rooms = widget.distribution.rooms;
    final (p, a, t) = _counts(_room, _roomIndex);
    final hasPrev = _roomIndex > 0;
    final hasNext = _roomIndex < rooms.length - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton.filledTonal(
              onPressed: hasPrev ? () => setState(() => _roomIndex--) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_room.classroomName,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 15, color: const Color(0xFF1E293B))),
                  Builder(builder: (_) {
                    final (_, sup) = _room.getSupervisorForSlot(_sessionSlotIndex);
                    return Text(
                      '${p + a}/$t işaretlendi${sup != null && sup.isNotEmpty ? ' • $sup' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                    );
                  }),
                ],
              ),
            ),
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: _indigo),
              onPressed: hasNext ? () => setState(() => _roomIndex++) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionSlotBar() {
    final slots = widget.distribution.sessionSlots;
    if (slots.length <= 1) return const SizedBox.shrink();

    final (_, supName) = _room.getSupervisorForSlot(_sessionSlotIndex);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.access_time_filled_rounded, size: 16, color: _indigo),
              const SizedBox(width: 6),
              Text(
                'Sınav Oturumu',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              if (supName != null && supName.isNotEmpty) ...[
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_rounded, size: 13, color: Color(0xFF64748B)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            supName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF334155),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < slots.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Builder(builder: (_) {
                    final isSel = i == _sessionSlotIndex;
                    final slot = slots[i];
                    final label = slot['label']?.toString() ?? '${i + 1}. Oturum';
                    final sTime = slot['startTime']?.toString() ?? '';
                    final eTime = slot['endTime']?.toString() ?? '';
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _sessionSlotIndex = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSel ? _indigo : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSel ? _indigo : const Color(0xFFCBD5E1),
                            width: isSel ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isSel ? Colors.white : const Color(0xFF1E293B),
                              ),
                            ),
                            if (sTime.isNotEmpty && eTime.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '$sTime-$eTime',
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: isSel ? Colors.white70 : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentList() {
    final allSeats = _seatedSeats(_room);
    final map = _attendance[_currentKey] ?? const <String, bool>{};

    final seats = allSeats.where((s) {
      final v = map[s.student!.id];
      switch (_filter) {
        case _AttFilter.all:
          return true;
        case _AttFilter.present:
          return v == true;
        case _AttFilter.absent:
          return v == false;
        case _AttFilter.pending:
          return v == null;
      }
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      children: [
        _buildSessionSlotBar(),
        _roomGrid(),
        const SizedBox(height: 8),
        _statFilters(),
        const SizedBox(height: 10),
        if (allSeats.isEmpty)
          Padding(
            padding: const EdgeInsets.all(30),
            child: Center(
              child: Text('Bu salonda öğrenci yok.',
                  style: GoogleFonts.inter(color: const Color(0xFF64748B))),
            ),
          )
        else if (seats.isEmpty)
          Padding(
            padding: const EdgeInsets.all(30),
            child: Center(
              child: Text('Bu filtrede öğrenci yok.',
                  style: GoogleFonts.inter(color: const Color(0xFF64748B))),
            ),
          ),
        for (final seat in seats) ...[
          _studentRow(seat, map[seat.student!.id]),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _studentRow(SeatCoordinate seat, bool? v) {
    final s = seat.student!;
    final Color accent = v == null ? const Color(0xFFCBD5E1) : (v ? _green : _red);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: v == null ? Colors.white : accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: v == null ? 1 : 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _indigo.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${seat.seatNumber}',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12.5, color: _indigo),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, fontSize: 13.5, color: const Color(0xFF1E293B)),
                ),
                Text(
                  '${s.className} • No: ${s.studentNumber}',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _choice('Geldi', Icons.check_rounded, _green, v == true, () => _mark(s.id, v == true ? null : true)),
          const SizedBox(width: 6),
          _choice('Gelmedi', Icons.close_rounded, _red, v == false, () => _mark(s.id, v == false ? null : false)),
        ],
      ),
    );
  }

  Widget _choice(String label, IconData icon, Color color, bool selected, VoidCallback onTap) {
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? color : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : color),
              if (MediaQuery.of(context).size.width > 520) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      color: selected ? Colors.white : color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}