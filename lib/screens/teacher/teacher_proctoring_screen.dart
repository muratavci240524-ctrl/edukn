import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/user_permission_service.dart';
import '../school/tools/butterfly_exam/butterfly_attendance_screen.dart';
import '../../models/school/butterfly_exam_model.dart';

class TeacherProctoringScreen extends StatefulWidget {
  final String institutionId;

  const TeacherProctoringScreen({
    Key? key,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<TeacherProctoringScreen> createState() => _TeacherProctoringScreenState();
}

class _TeacherProctoringScreenState extends State<TeacherProctoringScreen> {
  static List<Map<String, dynamic>>? _cachedMyProctoring;

  bool _isLoading = true;
  List<Map<String, dynamic>> _myProctoring = [];

  @override
  void initState() {
    super.initState();
    if (_cachedMyProctoring != null) {
      _myProctoring = List.from(_cachedMyProctoring!);
      _isLoading = false;
    } else {
      _loadFromDiskCache();
    }
    _loadData(isBackground: _cachedMyProctoring != null);
  }

  Future<void> _loadFromDiskCache() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final prefs = await SharedPreferences.getInstance();
      final key = 'edukn_proctoring_${user.uid}_${widget.institutionId}';
      final cachedStr = prefs.getString(key);
      if (cachedStr != null) {
        final List<dynamic> decoded = json.decode(cachedStr);
        final list = decoded.map<Map<String, dynamic>>((e) {
          final m = Map<String, dynamic>.from(e as Map);
          m.forEach((k, v) {
            if (v is Map && v['__ts'] is int) {
              m[k] = Timestamp.fromMillisecondsSinceEpoch(v['__ts'] as int);
            }
          });
          return m;
        }).toList();
        if (mounted && _myProctoring.isEmpty) {
          setState(() {
            _myProctoring = list;
            _isLoading = false;
          });
        }
      }
    } catch (silentError) { debugPrint('[teacher_proctoring_screen] hata yutuldu: $silentError'); }
  }

  Future<void> _loadData({bool isBackground = false}) async {
    if (!isBackground && mounted) setState(() => _isLoading = true);
    try {
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid == null) return;

      final userData = await UserPermissionService.loadUserData();
      final String instId = (userData?['institutionId'] ?? widget.institutionId).toString().toUpperCase();
      final instIds = [instId, instId.toLowerCase()].toSet().toList();

      // Takvimle aynı validTeacherIds mantığı — tüm ID varyantları
      final docId = userData?['id']?.toString();
      final authUserId = userData?['authUserId']?.toString();
      final tId = userData?['teacherId']?.toString();
      final staffId = userData?['staffId']?.toString();
      final username = userData?['username']?.toString();

      final validTeacherIds = <String>{
        if (authUid.isNotEmpty) authUid,
        if (docId != null && docId.isNotEmpty) docId,
        if (authUserId != null && authUserId.isNotEmpty) authUserId,
        if (tId != null && tId.isNotEmpty) tId,
        if (staffId != null && staffId.isNotEmpty) staffId,
        if (username != null && username.isNotEmpty) username,
      }.toList();

      if (validTeacherIds.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final List<Future<QuerySnapshot<Map<String, dynamic>>>> queries = [];
      for (final inst in instIds) {
        for (int i = 0; i < validTeacherIds.length; i += 10) {
          final chunk = validTeacherIds.skip(i).take(10).toList();
          queries.add(FirebaseFirestore.instance
              .collection('proctoringSlots')
              .where('institutionId', isEqualTo: inst)
              .where('teacherId', whereIn: chunk)
              .where('isPublished', isEqualTo: true)
              .get()
              .catchError((_) => FirebaseFirestore.instance
                  .collection('proctoringSlots')
                  .where(FieldPath.documentId, isEqualTo: 'NO_MATCH_DUMMY_ID')
                  .limit(1)
                  .get()));
        }
      }

      final snaps = await Future.wait(queries);
      final seen = <String>{};
      final List<Map<String, dynamic>> list = [];
      final Set<String> examIds = {};
      for (final s in snaps) {
        for (var d in s.docs) {
          if (seen.add(d.id)) {
            final map = {...d.data(), 'id': d.id};
            list.add(map);
            final eId = map['examId']?.toString();
            if (eId != null && eId.isNotEmpty) examIds.add(eId);
          }
        }
      }

      // Güncel saat ayarlarını çek
      if (examIds.isNotEmpty) {
        final Map<String, List<Map<String, String>>> examManualSlotsMap = {};
        final List<Future<void>> settingsFutures = [];
        for (final eId in examIds) {
          settingsFutures.add(
            FirebaseFirestore.instance
                .collection('proctoringSettings')
                .where('examId', isEqualTo: eId)
                .limit(1)
                .get()
                .then((snap) {
              if (snap.docs.isNotEmpty) {
                final sData = snap.docs.first.data();
                final raw = (sData['manualSlots'] ?? sData['timeSlots']) as List? ?? [];
                if (raw.isNotEmpty) {
                  examManualSlotsMap[eId] = raw.map((e) {
                    if (e is Map) {
                      return {
                        'start': (e['start'] ?? e['startTime'] ?? '').toString(),
                        'end': (e['end'] ?? e['endTime'] ?? '').toString(),
                      };
                    }
                    return {'start': '', 'end': ''};
                  }).toList();
                }
              }
            }).catchError((_) {}),
          );
        }
        try {
          await Future.wait(settingsFutures).timeout(const Duration(seconds: 3));
        } catch (_) {}

        // Listeyi güncel saatlerle zenginleştir
        for (final item in list) {
          final eId = item['examId']?.toString() ?? '';
          final sIdx = (item['slotIndex'] as num?)?.toInt() ?? 0;
          if (examManualSlotsMap.containsKey(eId)) {
            final mSlots = examManualSlotsMap[eId]!;
            if (sIdx >= 0 && sIdx < mSlots.length) {
              final configuredStart = mSlots[sIdx]['start'] ?? '';
              final configuredEnd = mSlots[sIdx]['end'] ?? '';
              if (configuredStart.isNotEmpty && configuredEnd.isNotEmpty) {
                item['startTime'] = configuredStart;
                item['endTime'] = configuredEnd;
                item['slotLabel'] = '${sIdx + 1}. Saat';
              }
            }
          }
        }
      }

      // Sınav tarihi → slotIndex sırası
      list.sort((a, b) {
        DateTime? da;
        final av = a['examDate'];
        if (av is Timestamp) da = av.toDate();
        if (av is String) da = DateTime.tryParse(av);
        DateTime? db;
        final bv = b['examDate'];
        if (bv is Timestamp) db = bv.toDate();
        if (bv is String) db = DateTime.tryParse(bv);
        if (da != null && db != null) {
          final c = da.compareTo(db);
          if (c != 0) return c;
        }
        return (a['slotIndex'] as int? ?? 0).compareTo(b['slotIndex'] as int? ?? 0);
      });

      _cachedMyProctoring = List.from(list);

      // Diske yaz
      SharedPreferences.getInstance().then((prefs) {
        try {
          prefs.setString(
              'edukn_proctoring_${authUid}_${widget.institutionId}',
              json.encode(list.map((e) {
                final copy = Map<String, dynamic>.from(e);
                copy.forEach((k, v) {
                  if (v is Timestamp) copy[k] = {'__ts': v.millisecondsSinceEpoch};
                });
                return copy;
              }).toList()));
        } catch (silentError) { debugPrint('[teacher_proctoring_screen] hata yutuldu: $silentError'); }
      }).catchError((_) {});

      if (mounted) {
        setState(() {
          _myProctoring = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Proctoring load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getMonthName(int month) {
    const months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(title: 'Gözetmenlik Görevlerim'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  // ─ Başlık ─
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.purple.shade50, Colors.indigo.shade50],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.purple.shade200.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.supervised_user_circle_rounded, size: 18, color: Colors.purple.shade700),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Gözetmenlik Görevlerim',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.purple.shade800.withValues(alpha: 0.8))),
                                const SizedBox(height: 2),
                                Text('${_myProctoring.length} görev listeleniyor',
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF4C1D95)),
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(color: Colors.purple.shade600, borderRadius: BorderRadius.circular(20)),
                            child: const Text('Sınav', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ─ Boş durum ─
                  if (_myProctoring.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade100),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(color: Colors.purple.shade50, shape: BoxShape.circle),
                              child: Icon(Icons.supervised_user_circle_rounded, size: 44, color: Colors.purple.shade200),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Yayınlanmış gözetmenlik göreviniz bulunmuyor',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Sınav gözetmenlik çizelgesi yayınlandığında görevleriniz burada görünecek.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...List.generate(_myProctoring.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: _buildProctoringCard(_myProctoring[index]),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Future<void> _openAttendance(Map<String, dynamic> slotData) async {
    final examId = slotData['examId']?.toString();
    final className = slotData['className']?.toString();
    if (examId == null || examId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sınav planı kimliği bulunamadı.')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF4F46E5)),
                SizedBox(height: 14),
                Text('Yoklama listesi hazırlanıyor...', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final db = FirebaseFirestore.instance;
      var snap = await db.collection('butterfly_exams').doc(examId).get();
      if (!snap.exists) {
        snap = await db.collection('seating_plans').doc(examId).get();
      }

      if (mounted) Navigator.pop(context); // Dialog'u kapat

      if (!snap.exists || snap.data() == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sınav oturum planı bulunamadı.')),
          );
        }
        return;
      }

      final dist = ExamDistribution.fromMap(snap.data()!, snap.id);

      // Öğretmen Yönerge Kontrolü: Okuyup onaylamadan yoklama alamaz!
      if (dist.instructions.isNotEmpty && !_isTeacherApprovedForExam(dist)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Yoklama alabilmek için öncelikle sınav uygulama yönergesini okuyup onaylamanız gerekmektedir.',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: Color(0xFFD97706),
              duration: Duration(seconds: 4),
            ),
          );

          _showInstructionDialog(
            dist.instructions,
            exam: dist,
            showApprovalPrompt: true,
            onApproved: () {
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ButterflyAttendanceScreen(
                      distribution: dist,
                      initialClassroomName: className,
                    ),
                  ),
                );
              }
            },
          );
        }
        return;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ButterflyAttendanceScreen(
              distribution: dist,
              initialClassroomName: className,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dialog'u kapat
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yoklama yüklenemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildProctoringCard(Map<String, dynamic> data) {
    final examName = data['examName']?.toString() ?? 'Sınav';
    final className = data['className']?.toString() ?? '';
    final slotLabel = data['slotLabel']?.toString() ?? '';
    final startTime = data['startTime']?.toString() ?? '';
    final endTime = data['endTime']?.toString() ?? '';

    DateTime? examDate;
    final dv = data['examDate'];
    if (dv is Timestamp) examDate = dv.toDate();
    if (dv is String) examDate = DateTime.tryParse(dv);
    if (dv is Map && dv['__ts'] is int) {
      examDate = DateTime.fromMillisecondsSinceEpoch(dv['__ts'] as int);
    }

    final now = DateTime.now();
    final isToday = examDate != null &&
        examDate.year == now.year &&
        examDate.month == now.month &&
        examDate.day == now.day;
    final isPast = examDate != null && !isToday && examDate.isBefore(DateTime(now.year, now.month, now.day));

    final accentColor = isToday ? const Color(0xFF16A34A) : isPast ? Colors.grey.shade600 : const Color(0xFF7C3AED);
    final bgColor = isToday ? const Color(0xFFDCFCE7) : isPast ? Colors.grey.shade100 : const Color(0xFFF5F3FF);
    final borderColor = isToday ? const Color(0xFF86EFAC) : isPast ? Colors.grey.shade300 : const Color(0xFFDDD6FE);

    final hasExamId = data['examId'] != null && data['examId'].toString().isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: isToday ? 2 : 0,
      shadowColor: isToday ? Colors.green.withValues(alpha: 0.2) : Colors.transparent,
      color: isPast ? Colors.grey.shade50 : Colors.white,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isToday ? 2 : 1.5),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Tarih kutusu
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        examDate != null ? DateFormat('dd').format(examDate) : '??',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: accentColor),
                      ),
                      Text(
                        examDate != null ? _getMonthName(examDate.month) : '',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accentColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // İçerik
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(examName,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          overflow: TextOverflow.ellipsis),
                      if (className.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(children: [
                          Icon(Icons.class_rounded, size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(className, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                        ]),
                      ],
                      if (slotLabel.isNotEmpty || (startTime.isNotEmpty && endTime.isNotEmpty)) ...[
                        const SizedBox(height: 3),
                        Row(children: [
                          Icon(Icons.access_time_rounded, size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            [if (slotLabel.isNotEmpty) slotLabel, if (startTime.isNotEmpty && endTime.isNotEmpty) '$startTime – $endTime'].join(' · '),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),

                // Durum badge
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF86EFAC))),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.fiber_manual_record, size: 8, color: Color(0xFF15803D)),
                      SizedBox(width: 4),
                      Text('Bugün', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                    ]),
                  )
                else if (isPast)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                    child: const Text('Tamamlandı', style: TextStyle(fontSize: 10.5, color: Colors.grey, fontWeight: FontWeight.w500)),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFDDD6FE))),
                    child: const Text('Planlandı', style: TextStyle(fontSize: 10.5, color: Color(0xFF7C3AED), fontWeight: FontWeight.w600)),
                  ),
              ],
            ),

            // Yoklama Al & Yönerge butonları
            if (hasExamId) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: borderColor.withValues(alpha: 0.6)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.meeting_room_rounded, size: 15, color: Colors.grey.shade600),
                      const SizedBox(width: 5),
                      Text(
                        className.isNotEmpty ? 'Salon: $className' : 'Salon Sınavı',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (data['instructions'] is List && (data['instructions'] as List).isNotEmpty) ...[
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4F46E5),
                            side: const BorderSide(color: Color(0xFFC7D2FE)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.gavel_rounded, size: 15),
                          label: const Text(
                            'Yönerge',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => _openInstructionsFromCard(data),
                        ),
                        const SizedBox(width: 8),
                      ],
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: isToday ? const Color(0xFF16A34A) : const Color(0xFF4F46E5),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.fact_check_rounded, size: 16),
                        label: const Text(
                          'Yoklama Al',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _openAttendance(data),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isTeacherApprovedForExam(ExamDistribution exam) {
    final approvals = exam.instructionApprovals;
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

  Future<void> _openInstructionsFromCard(Map<String, dynamic> data) async {
    final examId = data['examId']?.toString();
    final instructionsRaw = data['instructions'];
    List<dynamic> list = instructionsRaw is List ? List.from(instructionsRaw) : [];

    ExamDistribution? dist;
    if (examId != null && examId.isNotEmpty) {
      try {
        final db = FirebaseFirestore.instance;
        var snap = await db.collection('butterfly_exams').doc(examId).get();
        if (!snap.exists) snap = await db.collection('seating_plans').doc(examId).get();
        if (snap.exists && snap.data() != null) {
          dist = ExamDistribution.fromMap(snap.data()!, snap.id);
          if (dist.instructions.isNotEmpty) {
            list = dist.instructions;
          }
        }
      } catch (e) {
        debugPrint('Yönerge sınav belgesi çekilemedi: $e');
      }
    }

    if (list.isEmpty) {
      list = [
        'Gözetmen öğretmenler sınav başlangıç saatinden 15 dakika önce sınav evraklarını idareden teslim almalıdır.',
        'Öğrenciler sınav salonuna cep telefonu, akıllı saat veya haberleşme araçlarıyla giremez.',
        'Sınav başlamadan önce öğrencilerin kimlik ve salon oturma planı kontrolleri eksiksiz yapılmalıdır.',
        'Sınav evrak poşeti öğrenciler huzurunda açılarak optik form ve kitapçıklar kontrol edilmelidir.',
        'Sınavın ilk 15 dakikası ve son 10 dakikası hiçbir öğrencinin salondan çıkışına izin verilmez.',
        'Sınav bitiminde sınav evrakları eksiksiz toplanarak salon yoklama tutanağı gözetmen tarafından imzalanmalıdır.',
      ];
    }

    if (!mounted) return;
    _showInstructionDialog(list, exam: dist);
  }

  void _showInstructionDialog(
    List<dynamic> instructions, {
    ExamDistribution? exam,
    bool showApprovalPrompt = false,
    VoidCallback? onApproved,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.78,
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
                          const Text(
                            'Sınav Uygulama Yönergesi',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                          ),
                          Text(
                            exam != null ? '${exam.title} • ${exam.lessonName}' : 'Gözetmen öğretmenlerin uyması gereken kurallar',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Yoklama alma yönlendirme uyarısı
              if (showApprovalPrompt)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_rounded, color: Color(0xFFD97706), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Yoklama alabilmek için lütfen yönerge maddelerini okuyup en alttaki "Okudum, Onaylıyorum" butonuna basınız.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF92400E),
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
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              instructions[idx].toString(),
                              style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Altta Sabit Eylem Alanı (Öğretmen Okudum Onaylıyorum Butonu)
              if (exam != null)
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
                    child: _buildTeacherActionInDialog(exam, ctx, onApproved: onApproved),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTeacherActionInDialog(ExamDistribution exam, BuildContext sheetCtx, {VoidCallback? onApproved}) {
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isApproved = _isTeacherApprovedForExam(exam);
    final approvals = exam.instructionApprovals;
    Map? approvalData;
    if (approvals.containsKey(authUid)) {
      approvalData = approvals[authUid] as Map?;
    } else {
      for (final v in approvals.values) {
        if (v is Map) {
          approvalData = v;
          break;
        }
      }
    }
    DateTime? approvedAt;
    final rawAt = approvalData?['approvedAt'];
    if (rawAt is Timestamp) approvedAt = rawAt.toDate();
    if (rawAt is DateTime) approvedAt = rawAt;

    if (isApproved) {
      final dateStr = approvedAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(approvedAt) : '';
      return Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF6EE7B7), width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 20),
            const SizedBox(width: 8),
            Text(
              'Yönergeyi Okudunuz ve Onayladınız ${dateStr.isNotEmpty ? '($dateStr)' : ''}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: Color(0xFF065F46),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
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
        label: const Text(
          'Okudum, Onaylıyorum',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        onPressed: () => _approveExamInstructions(exam, sheetCtx, onApproved: onApproved),
      ),
    );
  }

  Future<void> _approveExamInstructions(
    ExamDistribution exam,
    BuildContext sheetCtx, {
    VoidCallback? onApproved,
  }) async {
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

      final examId = exam.id ?? '';
      if (examId.isNotEmpty) {
        final db = FirebaseFirestore.instance;
        await db.collection('butterfly_exams').doc(examId).set({
          'instructionApprovals': updateMap,
        }, SetOptions(merge: true)).catchError((_) {});
        await db.collection('seating_plans').doc(examId).set({
          'instructionApprovals': updateMap,
        }, SetOptions(merge: true)).catchError((_) {});
      }

      exam.instructionApprovals.addAll(updateMap);

      if (sheetCtx.mounted) {
        Navigator.pop(sheetCtx);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sınav yönergesi okundu ve onaylandı olarak sisteme işlendi.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }

      if (onApproved != null) {
        onApproved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Onay işlemi kaydedilemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
