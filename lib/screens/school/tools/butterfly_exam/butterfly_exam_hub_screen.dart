import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../services/web_share/web_file_share.dart';
import '../../../../models/school/butterfly_exam_model.dart';
import '../../../../services/butterfly_pdf_service.dart';
import '../../../../services/user_permission_service.dart';
import '../../../../widgets/edukn_app_bar.dart';
import 'butterfly_exam_wizard_screen.dart';
import 'butterfly_exam_detail_screen.dart';
import 'butterfly_attendance_screen.dart';

/// Kelebek Sınav Dağıtıcı Ana Merkezi
class ButterflyExamHubScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final bool? isTeacher;

  const ButterflyExamHubScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.isTeacher,
  });

  @override
  State<ButterflyExamHubScreen> createState() => _ButterflyExamHubScreenState();
}

class _ButterflyExamHubScreenState extends State<ButterflyExamHubScreen> {
  bool _showCompleted = false; // false: Aktif, true: Pasif (tamamlanan)
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  bool get _isTeacher {
    if (widget.isTeacher != null) return widget.isTeacher!;
    final role = (UserPermissionService.cachedUserData?['role'] as String?)?.toLowerCase() ?? '';
    return role.contains('ogretmen') || role.contains('öğretmen') || role == 'teacher';
  }

  bool get _canViewReports => UserPermissionService.canViewExamReports();
  bool get _canCompleteExam => UserPermissionService.canCompleteExam();
  bool get _canPublish => UserPermissionService.canPublishExam();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: 'Kelebek Sınav Dağıtıcı',
        subtitle: '${widget.schoolTypeName} • Çapraz Dağıtım & PDF Jeneratörü',
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        subtitleColor: const Color(0xFF64748B),
        backButtonColor: const Color(0xFF4F46E5),
        borderColor: const Color(0xFFE2E8F0),
        actions: [
          if (!_isTeacher || _canPublish)
            IconButton(
              tooltip: 'Yeni Sınav Oluştur',
              icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF4F46E5), size: 24),
              onPressed: _navigateToCreateWizard,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Üst Bilgi ve Arama Çubuğu
            _buildSearchAndInfoBar(isMobile),

            // Sınav Listesi
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('butterfly_exams')
                    .where('institutionId', isEqualTo: widget.institutionId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final errStr = snapshot.error.toString();
                    if (errStr.contains('permission-denied')) {
                      // Fallback stream from seating_plans
                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('seating_plans')
                            .where('institutionId', isEqualTo: widget.institutionId)
                            .where('type', isEqualTo: 'butterfly_exam')
                            .snapshots(),
                        builder: (ctx2, snap2) {
                          if (snap2.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
                          }
                          final docs2 = snap2.data?.docs ?? [];
                          final exams2 = docs2
                              .map((d) => ExamDistribution.fromMap(d.data() as Map<String, dynamic>, d.id))
                              .toList();
                          exams2.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                          return _buildExamsListView(exams2, isMobile);
                        },
                      );
                    }
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
                  }

                  final docs = snapshot.data?.docs ?? [];
                  final exams = docs
                      .map((d) => ExamDistribution.fromMap(d.data() as Map<String, dynamic>, d.id))
                      .toList();

                  // Tarihe göre yeniden eskiye sırala
                  exams.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                  return _buildExamsListView(exams, isMobile);
                },
              ),
            ),
          ],
        ),
      ),
      // Yeni Sınav Başlat Butonu
      bottomNavigationBar: (!_isTeacher || _canPublish)
          ? Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 24,
                vertical: isMobile ? 12 : 14,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.2)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF64748B).withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _navigateToCreateWizard,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'YENİ KELEBEK SINAV DAĞITIMI BAŞLAT',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.4),
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  // ===========================================================================
  // AKTİF / PASİF SEKMELERİ
  // ===========================================================================
  Widget _buildStatusTabs() {
    Widget tab(String label, IconData icon, bool completed, Color color) {
      final on = _showCompleted == completed;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _showCompleted = completed),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: on
                  ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: on ? Colors.white : const Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: on ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8ECF4),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          tab('Aktif', Icons.play_circle_outline_rounded, false, const Color(0xFF4F46E5)),
          tab('Pasif', Icons.inventory_2_outlined, true, const Color(0xFF64748B)),
        ],
      ),
    );
  }

  Widget _buildNoResultState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_showCompleted ? Icons.inventory_2_outlined : Icons.search_off_rounded,
                size: 44, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 10),
            Text(
              _showCompleted ? 'Tamamlanan sınav yok' : 'Aktif sınav bulunamadı',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, color: const Color(0xFF334155)),
            ),
            const SizedBox(height: 4),
            Text(
              _showCompleted
                  ? 'Yoklaması alınan sınavları "Tamamla" ile buraya taşıyabilirsiniz.'
                  : 'Aramanızı değiştirin veya yeni bir sınav oluşturun.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmComplete(ExamDistribution exam) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Sınavı Tamamla', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
        content: Text(
          '"${exam.title}" çalışması tamamlandı olarak işaretlenecek ve Pasif sekmesine taşınacak. Dilediğiniz zaman Aktife alabilirsiniz.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tamamla'),
          ),
        ],
      ),
    );
    if (ok == true) await _setCompleted(exam, true);
  }

  Future<void> _setCompleted(ExamDistribution exam, bool completed) async {
    final id = exam.id;
    if (id == null || id.isEmpty) return;
    try {
      final db = FirebaseFirestore.instance;
      var ref = db.collection('butterfly_exams').doc(id);
      if (!(await ref.get()).exists) ref = db.collection('seating_plans').doc(id);
      await ref.set({
        'isCompleted': completed,
        'completedAt': completed ? Timestamp.now() : null,
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(completed ? 'Sınav tamamlandı, Pasif sekmesine taşındı.' : 'Sınav tekrar Aktif.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Öğretmenin yönergeyi onaylayıp onaylamadığını doğrular (tüm geçerli ID varyantlarını tarar)
  bool _isTeacherApproved(ExamDistribution exam) {
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

  /// Sınav Uygulama Yönergesi Modalı
  /// Öğretmen: "Okudum, Onaylıyorum" butonu
  /// İdareci: "Yönergeyi Paylaş" (Şık PDF) + "Kopyala" (Metin) + "Göz Butonu" (Yeşil/Turuncu/Kırmızı Onay Takibi)
  void _showExamInstructionsModal(
    ExamDistribution exam, {
    VoidCallback? onApproved,
    bool showApprovalPrompt = false,
  }) {
    final instructions = exam.instructions.isNotEmpty
        ? exam.instructions
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
                      child: const Icon(Icons.menu_book_rounded, color: Color(0xFF4F46E5), size: 20),
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
                            '${exam.title} • ${exam.lessonName}',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(sheetCtx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Yoklama alma yönlendirmesi uyarısı (Öğretmen onaylamadan yoklamaya bastığında)
              if (showApprovalPrompt)
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

              // Altta Sabit Eylem Alanı
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
                  child: _isTeacher
                      ? _buildTeacherInstructionAction(exam, sheetCtx, onApproved: onApproved)
                      : _buildAdminInstructionActions(exam, instructions, sheetCtx),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Öğretmen Alt Eylemi: Okudum Onaylıyorum Butonu
  Widget _buildTeacherInstructionAction(
    ExamDistribution exam,
    BuildContext sheetCtx, {
    VoidCallback? onApproved,
  }) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isApproved = _isTeacherApproved(exam);
    final approvals = exam.instructionApprovals;
    Map? approvalData;
    if (approvals.containsKey(currentUid)) {
      approvalData = approvals[currentUid] as Map?;
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
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: const Color(0xFF065F46),
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
        label: Text(
          'Okudum, Onaylıyorum',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        onPressed: () => _approveExamInstructions(exam, currentUid, sheetCtx, onApproved: onApproved),
      ),
    );
  }

  /// Öğretmenin Yönergeyi Onaylama İşlemi
  Future<void> _approveExamInstructions(
    ExamDistribution exam,
    String teacherId,
    BuildContext sheetCtx, {
    VoidCallback? onApproved,
  }) async {
    try {
      final userData = UserPermissionService.cachedUserData;
      final teacherName = UserPermissionService.getUserDisplayName(userData);
      final approvalRecord = {
        'teacherId': teacherId,
        'teacherName': teacherName,
        'approvedAt': Timestamp.now(),
      };

      final Map<String, dynamic> updateMap = {
        teacherId: approvalRecord,
      };
      final docId = userData?['id']?.toString();
      if (docId != null && docId.isNotEmpty) {
        updateMap[docId] = approvalRecord;
      }
      final tId = userData?['teacherId']?.toString();
      if (tId != null && tId.isNotEmpty) {
        updateMap[tId] = approvalRecord;
      }

      final db = FirebaseFirestore.instance;
      final examId = exam.id ?? '';
      if (examId.isNotEmpty) {
        await db.collection('butterfly_exams').doc(examId).set({
          'instructionApprovals': updateMap,
        }, SetOptions(merge: true)).catchError((_) {});
        await db.collection('seating_plans').doc(examId).set({
          'instructionApprovals': updateMap,
        }, SetOptions(merge: true)).catchError((_) {});
      }

      // Bellek içi haritayı da anında güncelle
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

      // Onay sonrası bekleyen bir eylem (örn. Yoklama alma) varsa doğrudan çalıştır
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

  /// Sınavdaki Benzersiz Gözetmenleri Çıkarır (ID -> Bilgi)
  Map<String, Map<String, String>> _getExamProctors(ExamDistribution exam) {
    final Map<String, Map<String, String>> map = {};
    for (final room in exam.rooms) {
      if (room.supervisors.isNotEmpty) {
        for (final s in room.supervisors) {
          final sId = s['supervisorId']?.toString().trim() ?? '';
          final sName = s['supervisorName']?.toString().trim() ?? '';
          final slotLabel = s['slotLabel']?.toString() ?? '1. Oturum';
          if (sId.isNotEmpty) {
            map[sId] = {
              'name': sName.isNotEmpty ? sName : 'Öğretmen ($sId)',
              'room': '${room.classroomName} ($slotLabel)',
            };
          }
        }
      } else if (room.supervisorId != null && room.supervisorId!.trim().isNotEmpty) {
        final sId = room.supervisorId!.trim();
        final sName = room.supervisorName?.trim() ?? '';
        map[sId] = {
          'name': sName.isNotEmpty ? sName : 'Öğretmen ($sId)',
          'room': room.classroomName,
        };
      }
    }
    return map;
  }

  /// İdareci Alt Eylemleri: Paylaş (Şık PDF), Kopyala (Metin), Göz Butonu (Onay Takibi)
  Widget _buildAdminInstructionActions(
    ExamDistribution exam,
    List<String> instructions,
    BuildContext sheetCtx,
  ) {
    final proctors = _getExamProctors(exam);
    final totalProctors = proctors.length;
    final approvals = exam.instructionApprovals;
    final approvedCount = proctors.keys.where((id) => approvals.containsKey(id)).length;

    Color eyeColor;
    Color eyeBg;
    Color eyeBorder;
    String eyeTooltip;

    if (totalProctors == 0) {
      eyeColor = const Color(0xFF64748B);
      eyeBg = const Color(0xFFF1F5F9);
      eyeBorder = const Color(0xFFCBD5E1);
      eyeTooltip = 'Henüz gözetmen atanmamış';
    } else if (approvedCount == 0) {
      // KİMSE ONAYLAMADIYSA KIRMIZI GÖZ 🔴
      eyeColor = Colors.red.shade700;
      eyeBg = const Color(0xFFFEF2F2);
      eyeBorder = const Color(0xFFFCA5A5);
      eyeTooltip = '0/$totalProctors Gözetmen Onayladı (Kimse Onaylamadı)';
    } else if (approvedCount < totalProctors) {
      // BİR KISMI ONAYLADIYSA TURUNCU GÖZ 🟠
      eyeColor = Colors.orange.shade800;
      eyeBg = const Color(0xFFFFFBEB);
      eyeBorder = const Color(0xFFFCD34D);
      eyeTooltip = '$approvedCount/$totalProctors Gözetmen Onayladı (Kısmi Onay)';
    } else {
      // HERKES ONAYLADIYSA YEŞİL GÖZ 🟢
      eyeColor = const Color(0xFF16A34A);
      eyeBg = const Color(0xFFF0FDF4);
      eyeBorder = const Color(0xFF86EFAC);
      eyeTooltip = 'Tüm Gözetmenler Onayladı ($approvedCount/$totalProctors)';
    }

    return Row(
      children: [
        // Geniş Paylaş Butonu (Şık PDF olarak paylaşır - Mail/SMS/WhatsApp/Drive)
        Expanded(
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.share_rounded, size: 19),
              label: Text(
                'Yönergeyi Paylaş',
                style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              onPressed: () => _shareInstructionPdf(exam, instructions),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Metin Olarak Panoya Kopyala Butonu
        Tooltip(
          message: 'Metin Olarak Kopyala',
          child: SizedBox(
            height: 48,
            width: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: const Color(0xFF475569),
                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final text = _buildInstructionsShareText(exam, instructions);
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('📋 Yönerge metni panoya kopyalandı.'),
                    backgroundColor: Color(0xFF1E293B),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Icon(Icons.copy_rounded, size: 19),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // GÖZ BUTONU: Kimlerin onayladığını gösterir (Yeşil, Turuncu, Kırmızı)
        Tooltip(
          message: eyeTooltip,
          child: SizedBox(
            height: 48,
            width: 48,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: eyeBg,
                foregroundColor: eyeColor,
                side: BorderSide(color: eyeBorder, width: 1.6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _showInstructionApprovalsDialog(exam, proctors, approvals),
              child: Icon(Icons.visibility_rounded, size: 22, color: eyeColor),
            ),
          ),
        ),
      ],
    );
  }

  /// Gözetmen Onay Takibi İletişim Kutusu
  void _showInstructionApprovalsDialog(
    ExamDistribution exam,
    Map<String, Map<String, String>> proctors,
    Map<String, dynamic> approvals,
  ) {
    final totalProctors = proctors.length;
    final approvedProctors = proctors.entries.where((e) => approvals.containsKey(e.key)).toList();
    final pendingProctors = proctors.entries.where((e) => !approvals.containsKey(e.key)).toList();
    final approvedCount = approvedProctors.length;
    final ratio = totalProctors > 0 ? (approvedCount / totalProctors) : 0.0;

    Color progressColor;
    if (totalProctors == 0) {
      progressColor = const Color(0xFF64748B);
    } else if (approvedCount == 0) {
      progressColor = Colors.red.shade600;
    } else if (approvedCount < totalProctors) {
      progressColor = Colors.orange.shade700;
    } else {
      progressColor = const Color(0xFF16A34A);
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: progressColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.visibility_rounded, color: progressColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Yönerge Onay Takibi',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  Text(
                    exam.title,
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              // İlerleme Çubuğu ve Özet Sayaç
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Onaylayan Gözetmenler',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF334155)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: progressColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$approvedCount / $totalProctors',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: progressColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 7,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (totalProctors == 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Bu sınava henüz gözetmen öğretmen atanmamış.',
                      style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.42),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      // Onaylayanlar
                      if (approvedProctors.isNotEmpty) ...[
                        Text(
                          'Onaylayanlar (${approvedProctors.length})',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11.5, color: const Color(0xFF16A34A)),
                        ),
                        const SizedBox(height: 6),
                        ...approvedProctors.map((entry) {
                          final pId = entry.key;
                          final info = entry.value;
                          final appData = approvals[pId] as Map?;
                          DateTime? at;
                          final rawAt = appData?['approvedAt'];
                          if (rawAt is Timestamp) at = rawAt.toDate();
                          if (rawAt is DateTime) at = rawAt;
                          final dateStr = at != null ? DateFormat('dd.MM.yyyy HH:mm').format(at) : '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFBBF7D0)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        info['name'] ?? '',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
                                      ),
                                      Text(
                                        info['room'] ?? '',
                                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (dateStr.isNotEmpty)
                                  Text(
                                    dateStr,
                                    style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFF15803D)),
                                  ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 10),
                      ],

                      // Henüz Onaylamayanlar
                      if (pendingProctors.isNotEmpty) ...[
                        Text(
                          'Henüz Onaylamayanlar (${pendingProctors.length})',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11.5, color: Colors.red.shade700),
                        ),
                        const SizedBox(height: 6),
                        ...pendingProctors.map((entry) {
                          final info = entry.value;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.pending_actions_rounded, color: Colors.red.shade700, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        info['name'] ?? '',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
                                      ),
                                      Text(
                                        info['room'] ?? '',
                                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Bekliyor',
                                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  /// Şık Yönerge PDF Belgesini Oluşturur ve Paylaşım İletişim Kutusunu Açar
  Future<void> _shareInstructionPdf(ExamDistribution exam, List<String> instructions) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
        ),
      );

      final bytes = await ButterflyPdfService.generateInstructionPdf(
        distribution: exam,
        instructions: instructions,
      );

      if (mounted) {
        Navigator.pop(context); // Dialogu kapat
      }

      final fileName = sanitizeFileName('${exam.title}_Sinav_Uygulama_Yonergesi.pdf');
      final shareText = 'Sınav Uygulama Yönergesi: ${exam.title} (${exam.lessonName})';

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ButterflyPdfPreviewScreen(
            title: 'Sınav Uygulama Yönergesi',
            subTitle: '${exam.title} • ${exam.lessonName}',
            fileName: fileName,
            shareText: shareText,
            pdfBytes: bytes,
            onGeneratePdf: () => ButterflyPdfService.generateInstructionPdf(
              distribution: exam,
              instructions: instructions,
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yönerge PDF oluşturma hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Yönerge Metnini Paylaşım İçin Formatlama (Metin Kopyalama İçin)
  String _buildInstructionsShareText(ExamDistribution exam, List<String> instructions) {
    final buffer = StringBuffer();
    buffer.writeln('📋 *${exam.title.toUpperCase()}*');
    buffer.writeln('📚 *Ders:* ${exam.lessonName}');
    buffer.writeln('📅 *Tarih:* ${DateFormat("dd.MM.yyyy").format(exam.examDate)} (${exam.examTime})');
    buffer.writeln('');
    buffer.writeln('📝 *SINAV UYGULAMA YÖNERGESİ & GÖZETMEN KURALLARI*');
    buffer.writeln('────────────────────────');
    for (int i = 0; i < instructions.length; i++) {
      buffer.writeln('${i + 1}. ${instructions[i]}');
    }
    buffer.writeln('────────────────────────');
    buffer.writeln('ℹ️ _Tüm gözetmen öğretmenlerimizin ve sınav görevlilerimizin sınav yönergesine titizlikle uyması önemle rica olunur._');
    return buffer.toString();
  }

  /// Gözetmenlikleri Yayınlama İşlemi
  Future<void> _publishExamSupervisors(ExamDistribution exam) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.campaign_rounded, color: Color(0xFF4F46E5)),
            const SizedBox(width: 8),
            Text('Gözetmenlikleri Yayınla', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Gözetmenlik görevleri atanmış tüm öğretmenlerin görev takvimine işlenecek ve bildirim kutularına gönderilecektir.\n\nOnaylıyor musunuz?',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155), height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, Yayınla & Bildir'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final examId = exam.id;
      if (examId == null || examId.isEmpty) return;

      int publishedCount = 0;
      for (final room in exam.rooms) {
        if (room.supervisors.isNotEmpty) {
          for (final supEntry in room.supervisors) {
            final tId = supEntry['supervisorId']?.toString() ?? '';
            if (tId.isEmpty) continue;

            await FirebaseFirestore.instance.collection('notifications').add({
              'institutionId': widget.institutionId,
              'userId': tId,
              'title': 'Sınav Gözetmenlik Görevi',
              'body': '${DateFormat("dd.MM.yyyy").format(exam.examDate)} ${exam.examTime} tarihinde ${room.classroomName} salonunda gözetmenlik göreviniz bulunmaktadır.',
              'type': 'exam_supervisor_duty',
              'examDistributionId': examId,
              'roomName': room.classroomName,
              'slotIndex': supEntry['slotIndex'] ?? 0,
              'createdAt': Timestamp.now(),
              'isRead': false,
            });
            publishedCount++;
          }
        }
      }

      await FirebaseFirestore.instance.collection('butterfly_exams').doc(examId).set({
        'isProctoringPublished': true,
        'proctoringPublishedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Gözetmenlik görevleri yayınlandı ($publishedCount görevlendirildi)!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yayınlama hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Gözetmenlikleri Yayından Kaldırma İşlemi
  Future<void> _unpublishExamSupervisors(ExamDistribution exam) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Gözetmenlikleri Yayından Kaldır'),
        content: const Text(
          'Gözetmenlik görevleri taslak durumuna getirilecek. Öğretmenler bu sınav için aktif gözetmenlik görmeyecektir.\n\nOnaylıyor musunuz?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yayından Kaldır'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final examId = exam.id;
      if (examId == null || examId.isEmpty) return;

      await FirebaseFirestore.instance.collection('butterfly_exams').doc(examId).set({
        'isProctoringPublished': false,
        'proctoringUnpublishedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gözetmenlik görevleri yayından kaldırıldı.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  // ===========================================================================
  // ARAMA VE BİLGİ ŞERİDİ
  // ===========================================================================
  Widget _buildSearchAndInfoBar(bool isMobile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          _buildStatusTabs(),
          const SizedBox(height: 10),
          // Arama Girişi
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF64748B).withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Sınav adı, ders veya şube ara...',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SINAV LİSTESİ GÖRÜNÜMÜ
  // ===========================================================================
  Widget _buildExamsListView(List<ExamDistribution> exams, bool isMobile) {
    final filteredExams = exams.where((e) {
      if (e.isCompleted != _showCompleted) return false;
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return e.title.toLowerCase().contains(query) ||
          e.lessonName.toLowerCase().contains(query) ||
          e.selectedClassNames.any((c) => c.toLowerCase().contains(query));
    }).toList();

    if (filteredExams.isEmpty) {
      if (exams.isNotEmpty || _showCompleted) return _buildNoResultState();
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: filteredExams.length,
      itemBuilder: (context, index) {
        final exam = filteredExams[index];
        return _buildExamCard(exam, isMobile);
      },
    );
  }

  // ===========================================================================
  // TEKİL SINAV KARTI
  // ===========================================================================
  Widget _buildExamCard(ExamDistribution exam, bool isMobile) {
    final dateStr = DateFormat('dd.MM.yyyy').format(exam.examDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _navigateToDetail(exam),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst Satır: Sınav Adı & Tarih
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.view_module_rounded, color: Color(0xFF4F46E5), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exam.title,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Text(
                              exam.lessonName,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: const Color(0xFF4F46E5),
                              ),
                            ),
                            const Text('•', style: TextStyle(color: Color(0xFF94A3B8))),
                            Text(
                              '$dateStr (${exam.examTime})',
                              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                            ),
                            // Yayın / Taslak Rozeti
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: exam.isProctoringPublished
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: exam.isProctoringPublished
                                      ? const Color(0xFF86EFAC)
                                      : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    exam.isProctoringPublished ? Icons.check_circle_rounded : Icons.edit_note_rounded,
                                    size: 11,
                                    color: exam.isProctoringPublished ? const Color(0xFF166534) : const Color(0xFF475569),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    exam.isProctoringPublished ? 'Yayında' : 'Taslak',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: exam.isProctoringPublished ? const Color(0xFF166534) : const Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Menü Butonu (Sil / Düzenle / Yönerge / Rapor / Yayınla / Tamamla)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8), size: 20),
                    onSelected: (val) {
                      if (val == 'view') _navigateToDetail(exam);
                      if (val == 'edit_wizard') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ButterflyExamWizardScreen(
                              institutionId: widget.institutionId,
                              schoolTypeId: widget.schoolTypeId,
                              schoolTypeName: widget.schoolTypeName,
                              existingDistribution: exam,
                            ),
                          ),
                        );
                      }
                      if (val == 'instructions') _showExamInstructionsModal(exam);
                      if (val == 'attendance') _navigateToAttendance(exam);
                      if (val == 'report') _printAttendanceReport(exam);
                      if (val == 'publish') _publishExamSupervisors(exam);
                      if (val == 'unpublish') _unpublishExamSupervisors(exam);
                      if (val == 'complete') {
                        exam.isCompleted ? _setCompleted(exam, false) : _confirmComplete(exam);
                      }
                      if (val == 'delete') _confirmDeleteExam(exam);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            Icon(
                              (!_isTeacher || _canPublish) ? Icons.edit_outlined : Icons.remove_red_eye_outlined,
                              size: 18,
                              color: const Color(0xFF4F46E5),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              (!_isTeacher || _canPublish) ? 'Düzenle (Kroki ve Detay)' : 'Krokiyi ve Detayları Gör',
                              style: GoogleFonts.inter(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      if ((!_isTeacher || _canPublish) && !exam.isProctoringPublished)
                        PopupMenuItem(
                          value: 'edit_wizard',
                          child: Row(
                            children: [
                              const Icon(Icons.settings_backup_restore_rounded, size: 18, color: Color(0xFFD97706)),
                              const SizedBox(width: 8),
                              Text('Dağıtım Öncesine Dön (Ayarlar)', style: GoogleFonts.inter(fontSize: 13)),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'instructions',
                        child: Row(
                          children: [
                            const Icon(Icons.menu_book_rounded, size: 18, color: Color(0xFF0284C7)),
                            const SizedBox(width: 8),
                            Text(
                              exam.instructions.isNotEmpty ? 'Sınav Yönergesi (${exam.instructions.length})' : 'Sınav Yönergesi',
                              style: GoogleFonts.inter(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      if (!_isTeacher || _canPublish)
                        PopupMenuItem(
                          value: exam.isProctoringPublished ? 'unpublish' : 'publish',
                          child: Row(
                            children: [
                              Icon(
                                exam.isProctoringPublished ? Icons.unpublished_outlined : Icons.campaign_rounded,
                                size: 18,
                                color: exam.isProctoringPublished ? Colors.orange.shade800 : const Color(0xFF4F46E5),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                exam.isProctoringPublished ? 'Gözetmenlikleri Yayından Kaldır' : 'Gözetmenlikleri Yayınla & Bildir',
                                style: GoogleFonts.inter(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      if (!_isTeacher || _canViewReports)
                        PopupMenuItem(
                          value: 'report',
                          child: Row(
                            children: [
                              const Icon(Icons.assignment_outlined, size: 18, color: Color(0xFF4F46E5)),
                              const SizedBox(width: 8),
                              Text('Yoklama Raporu (PDF)', style: GoogleFonts.inter(fontSize: 13)),
                            ],
                          ),
                        ),
                      if (!_isTeacher || _canCompleteExam)
                        PopupMenuItem(
                          value: 'complete',
                          child: Row(
                            children: [
                              Icon(
                                exam.isCompleted ? Icons.unarchive_outlined : Icons.task_alt_rounded,
                                size: 18,
                                color: exam.isCompleted ? const Color(0xFFF59E0B) : const Color(0xFF0F766E),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                exam.isCompleted ? 'Sınavı Aktife Al' : 'Sınavı Tamamla',
                                style: GoogleFonts.inter(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      if (!_isTeacher || _canPublish)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                              const SizedBox(width: 8),
                              Text('Sınav Oturumunu Sil', style: GoogleFonts.inter(fontSize: 13, color: Colors.red)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Alt Eylem Butonları:
              // Mobilde SADECE "Yoklama Al" ve "Yönerge" (diğerleri 3 nokta menüsünde)
              if (isMobile)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          backgroundColor: const Color(0xFF10B981),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _navigateToAttendance(exam),
                        icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                        label: Text('Yoklama Al',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        foregroundColor: const Color(0xFF0284C7),
                        side: const BorderSide(color: Color(0xFFBAE6FD)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _showExamInstructionsModal(exam),
                      icon: const Icon(Icons.menu_book_rounded, size: 16),
                      label: Text(
                        exam.instructions.isNotEmpty ? 'Yönerge (${exam.instructions.length})' : 'Yönerge',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                )
              else
                // Geniş Ekran (Masaüstü/Tablet): Yoklama Al, Yönerge, Rapor, Yayınla, Tamamla
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          backgroundColor: const Color(0xFF10B981),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _navigateToAttendance(exam),
                        icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                        label: Text('Yoklama Al',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Yönerge butonu (Yoklama Al ile Rapor Al arasında)
                    Tooltip(
                      message: 'Sınav Uygulama Yönergesi & Kuralları',
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          foregroundColor: const Color(0xFF0284C7),
                          side: const BorderSide(color: Color(0xFFBAE6FD)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _showExamInstructionsModal(exam),
                        icon: const Icon(Icons.menu_book_rounded, size: 16),
                        label: Text(
                          exam.instructions.isNotEmpty ? 'Yönerge (${exam.instructions.length})' : 'Yönerge',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    // Rapor butonu (Yetki tanımlamada öğretmen için açılıp kapatılabilir)
                    if (!_isTeacher || _canViewReports) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Yoklama Raporu Al (PDF)',
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            foregroundColor: const Color(0xFF4F46E5),
                            side: const BorderSide(color: Color(0xFFC7D2FE)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => _printAttendanceReport(exam),
                          icon: const Icon(Icons.assignment_outlined, size: 16),
                          label: Text('Rapor',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                    // Yayınla butonu (Yetki tanımlamada öğretmen için açılıp kapatılabilir)
                    if (!_isTeacher || _canPublish) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: exam.isProctoringPublished
                            ? 'Gözetmenlikler yayında (Tıklayarak kaldırabilirsiniz)'
                            : 'Gözetmenlik görevlerini öğretmenlere yayınla ve bildir',
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            foregroundColor: exam.isProctoringPublished ? const Color(0xFF166534) : const Color(0xFF4F46E5),
                            side: BorderSide(
                              color: exam.isProctoringPublished ? const Color(0xFF86EFAC) : const Color(0xFFC7D2FE),
                            ),
                            backgroundColor: exam.isProctoringPublished ? const Color(0xFFF0FDF4) : Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => exam.isProctoringPublished
                              ? _unpublishExamSupervisors(exam)
                              : _publishExamSupervisors(exam),
                          icon: Icon(
                            exam.isProctoringPublished ? Icons.check_circle_rounded : Icons.campaign_rounded,
                            size: 16,
                          ),
                          label: Text(
                            exam.isProctoringPublished ? 'Yayında' : 'Yayınla',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                    // Tamamla butonu (Yetki tanımlamada öğretmen için açılıp kapatılabilir)
                    if (!_isTeacher || _canCompleteExam) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: exam.isCompleted ? 'Aktife Al' : 'Sınavı Tamamla (Pasife Al)',
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            foregroundColor: exam.isCompleted ? const Color(0xFFF59E0B) : const Color(0xFF0F766E),
                            side: BorderSide(
                              color: exam.isCompleted ? const Color(0xFFFDE68A) : const Color(0xFF99F6E4),
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => exam.isCompleted ? _setCompleted(exam, false) : _confirmComplete(exam),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(exam.isCompleted ? Icons.unarchive_outlined : Icons.task_alt_rounded, size: 16),
                              const SizedBox(width: 4),
                              Text(exam.isCompleted ? 'Aktife Al' : 'Tamamla',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // BOŞ DURUM
  // ===========================================================================
  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.view_module_rounded, size: 56, color: Color(0xFF4F46E5)),
            ),
            const SizedBox(height: 18),
            Text(
              'Henüz Kelebek Sınavı Oluşturulmamış',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: const Color(0xFF1E293B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Farklı şube ve sınıf seviyelerindeki öğrencileri çapraz algoritmayla derslik oturma planlarına yerleştirmek için hemen yeni bir sınav dağıtımı başlatın.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), height: 1.45),
              textAlign: TextAlign.center,
            ),
            if (!_isTeacher || _canPublish) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _navigateToCreateWizard,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('Yeni Sınav Dağıtımı Başlat', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // NAVİGASYON VE EYLEMLER
  // ===========================================================================
  void _navigateToCreateWizard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ButterflyExamWizardScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
        ),
      ),
    );
  }

  void _navigateToDetail(ExamDistribution exam) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ButterflyExamDetailScreen(
          distribution: exam,
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
        ),
      ),
    );
  }

  void _navigateToAttendance(ExamDistribution exam) {
    // Öğretmen kontrolü: Yönergeyi okuyup onaylamadan yoklama alamaz!
    if (_isTeacher && exam.instructions.isNotEmpty) {
      if (!_isTeacherApproved(exam)) {
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
        _showExamInstructionsModal(
          exam,
          showApprovalPrompt: true,
          onApproved: () => _navigateToAttendance(exam),
        );
        return;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ButterflyAttendanceScreen(distribution: exam)),
    );
  }

  Future<void> _printAttendanceReport(ExamDistribution exam) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
        ),
      );

      Map<String, Map<String, bool>> attendance = {};
      final id = exam.id;
      if (id != null && id.isNotEmpty) {
        final db = FirebaseFirestore.instance;
        var snap = await db.collection('butterfly_exams').doc(id).get();
        if (!snap.exists) snap = await db.collection('seating_plans').doc(id).get();
        final raw = snap.data()?['attendance'];
        if (raw is Map) {
          raw.forEach((roomKey, v) {
            if (v is Map) {
              attendance[roomKey.toString()] = {
                for (final e in v.entries) e.key.toString(): e.value == true,
              };
            }
          });
        }
      }
      final bytes = await ButterflyPdfService.generateAttendanceReportPdf(
        distribution: exam,
        attendance: attendance,
      );
      print('🔥 generateAttendanceReportPdf tamamlandı: ${bytes.length} bayt');

      if (mounted) {
        Navigator.pop(context); // Yükleniyor göstergesini kapat
      }

      if (!mounted) return;

      // Kullanıcının raporu doğrudan görmesi için önizleme ekranını aç
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ButterflyAttendanceReportPreviewScreen(
            exam: exam,
            pdfBytes: bytes,
            attendance: attendance,
          ),
        ),
      );

    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rapor oluşturulurken hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDeleteExam(ExamDistribution exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sınav Oturumunu Sil', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text(
          '"${exam.title}" sınav oturumunu silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed == true && exam.id != null) {
      await FirebaseFirestore.instance.collection('butterfly_exams').doc(exam.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sınav oturumu başarıyla silindi.')),
        );
      }
    }
  }
}

/// Kelebek Sınav Belgeleri Canlı Önizleme Ekranı
/// (Yoklama Raporu, Sınav Uygulama Yönergesi vb. belgeleri ekranda gösterir + Paylaş / İndir / Yazdır eylemleri)
class ButterflyPdfPreviewScreen extends StatefulWidget {
  final String title;
  final String subTitle;
  final String fileName;
  final String shareText;
  final Uint8List pdfBytes;
  final Future<Uint8List> Function()? onGeneratePdf;

  const ButterflyPdfPreviewScreen({
    super.key,
    required this.title,
    required this.subTitle,
    required this.fileName,
    required this.shareText,
    required this.pdfBytes,
    this.onGeneratePdf,
  });

  @override
  State<ButterflyPdfPreviewScreen> createState() => _ButterflyPdfPreviewScreenState();
}

class _ButterflyPdfPreviewScreenState extends State<ButterflyPdfPreviewScreen> {
  Uint8List? _validBytes;

  @override
  void initState() {
    super.initState();
    if (widget.pdfBytes.isNotEmpty) {
      _validBytes = Uint8List.fromList(widget.pdfBytes);
    }
  }

  Future<Uint8List> _ensureBytes() async {
    // 1. Eğer elimizdeki kopya sağlamsa klonunu dön (Web Worker buffer detach etkisini sıfırlar)
    if (_validBytes != null && _validBytes!.isNotEmpty) {
      return Uint8List.fromList(_validBytes!);
    }
    // 2. Generator fonksiyonu tanımlıysa tekrar üret
    if (widget.onGeneratePdf != null) {
      try {
        print('🔄 PDF tekrar üretiliyor...');
        final fresh = await widget.onGeneratePdf!();
        if (fresh.isNotEmpty) {
          _validBytes = Uint8List.fromList(fresh);
          return Uint8List.fromList(_validBytes!);
        }
      } catch (e) {
        print('PDF yeniden üretim hatası: $e');
      }
    }
    // 3. Widget'tan gelen orijinal byte'lar
    if (widget.pdfBytes.isNotEmpty) {
      _validBytes = Uint8List.fromList(widget.pdfBytes);
      return Uint8List.fromList(_validBytes!);
    }
    return Uint8List(0);
  }

  Future<void> _downloadPdf(BuildContext context) async {
    try {
      final bytes = await _ensureBytes();
      print('📥 PDF İndir tıklandı: ${widget.fileName} (${bytes.length} bayt)');
      if (bytes.isEmpty) {
        throw Exception('PDF verisi boş üretildi (0 bayt).');
      }
      await downloadFileUniversal(
        bytes: bytes,
        fileName: widget.fileName,
        mimeType: 'application/pdf',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.fileName} başarıyla indirildi (${(bytes.length / 1024).toStringAsFixed(1)} KB).'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İndirme hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printPdf(BuildContext context) async {
    try {
      final bytes = await _ensureBytes();
      print('🖨️ PDF Yazdır tıklandı: ${widget.fileName} (${bytes.length} bayt)');
      if (bytes.isEmpty) {
        throw Exception('PDF verisi boş üretildi (0 bayt).');
      }
      await printFileUniversal(
        bytes: bytes,
        fileName: widget.fileName,
        mimeType: 'application/pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yazdırma hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sharePdf(BuildContext context) async {
    final bytes = await _ensureBytes();
    // 1. Önce cihazın/tarayıcının yerel dosya paylaşımını dene (Mobil/Tablet veya Web Share API)
    var ok = false;
    try {
      if (bytes.isNotEmpty) {
        ok = await shareFileWeb(
          bytes: bytes,
          fileName: widget.fileName,
          mimeType: 'application/pdf',
          title: widget.title,
          text: widget.shareText,
        );
      }
    } catch (_) {}

    if (ok) return;

    if (!context.mounted) return;

    // 2. Masaüstü webde ASLA dosya indirmeden doğrudan paylaşım seçeneklerini sun
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.share_rounded, color: Color(0xFF4F46E5), size: 22),
                  const SizedBox(width: 10),
                  Text('Raporu Paylaş', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Paylaşmak istediğiniz yöntemi seçiniz:',
                style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF16A34A), size: 22),
                ),
                title: Text('WhatsApp ile Paylaş', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('WhatsApp Web\'de mesaj olarak açar', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final waUrl = 'https://wa.me/?text=${Uri.encodeComponent(widget.shareText)}';
                  await launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
                },
              ),
              const Divider(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.copy_rounded, color: Color(0xFF4F46E5), size: 22),
                ),
                title: Text('Metni Panoya Kopyala', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('Rapor özet metnini kopyalar', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Clipboard.setData(ClipboardData(text: widget.shareText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('📋 Paylaşım metni panoya kopyalandı.')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 1,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            Text(
              widget.subTitle,
              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          // Paylaş Butonu (Web Share / WhatsApp Yönlendirme)
          if (isMobile)
            IconButton(
              tooltip: 'Paylaş',
              icon: const Icon(Icons.share_rounded, color: Color(0xFF16A34A)),
              onPressed: () => _sharePdf(context),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.share_rounded, size: 16),
                label: Text('Paylaş', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5)),
                onPressed: () => _sharePdf(context),
              ),
            ),

          // İndir Butonu
          if (isMobile)
            IconButton(
              tooltip: 'PDF İndir',
              icon: const Icon(Icons.download_rounded, color: Color(0xFF4F46E5)),
              onPressed: () => _downloadPdf(context),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4F46E5),
                  side: const BorderSide(color: Color(0xFFC7D2FE)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: Text('İndir', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5)),
                onPressed: () => _downloadPdf(context),
              ),
            ),

          // Yazdır Butonu
          if (isMobile)
            IconButton(
              tooltip: 'Yazdır',
              icon: const Icon(Icons.print_rounded, color: Color(0xFF334155)),
              onPressed: () => _printPdf(context),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF334155),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.print_rounded, size: 16),
                label: Text('Yazdır', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5)),
                onPressed: () => _printPdf(context),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: PdfPreview(
        build: (_) async => await _ensureBytes(),
        allowPrinting: true,
        allowSharing: true,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: widget.fileName,
      ),
    );
  }
}

/// Geriye dönük uyumluluk için Sınav Yoklama Raporu sarmalayıcısı
class ButterflyAttendanceReportPreviewScreen extends StatelessWidget {
  final ExamDistribution exam;
  final Uint8List pdfBytes;
  final Map<String, Map<String, bool>>? attendance;

  const ButterflyAttendanceReportPreviewScreen({
    super.key,
    required this.exam,
    required this.pdfBytes,
    this.attendance,
  });

  @override
  Widget build(BuildContext context) {
    final fileName = sanitizeFileName('${exam.title}_Yoklama_Raporu.pdf');
    final shareText = 'Sınav Yoklama Raporu: ${exam.title}';
    return ButterflyPdfPreviewScreen(
      title: 'Yoklama Raporu Önizleme',
      subTitle: '${exam.title} • ${exam.lessonName}',
      fileName: fileName,
      shareText: shareText,
      pdfBytes: pdfBytes,
      onGeneratePdf: () => ButterflyPdfService.generateAttendanceReportPdf(
        distribution: exam,
        attendance: attendance ?? const {},
      ),
    );
  }
}
