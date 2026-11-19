import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/school/student_movement_model.dart';
import '../../services/student_movement_service.dart';
import '../../widgets/edukn_app_bar.dart';

class ParentEarlyPickupScreen extends StatefulWidget {
  final String institutionId;
  final String studentId;
  final Map<String, dynamic>? initialStudentData;

  const ParentEarlyPickupScreen({
    super.key,
    required this.institutionId,
    required this.studentId,
    this.initialStudentData,
  });

  @override
  State<ParentEarlyPickupScreen> createState() =>
      _ParentEarlyPickupScreenState();
}

class _ParentEarlyPickupScreenState extends State<ParentEarlyPickupScreen> {
  static const Color _accent = Color(0xFF0D9488);

  final StudentMovementService _service = StudentMovementService();

  bool _isLoading = true;
  bool _isSubmitting = false;
  String _schoolDocId = '';
  Map<String, dynamic> _student = {};
  List<ResolvedLessonSlot> _slots = [];
  int _selectedLessonHour = 1;

  bool _arrivedNowMode = false;
  String _receiverRelation = 'Velisi (Kendim Teslim Alacağım)';
  String _selectedReason = 'Hastane / Doktor / Diş Hekimi Randevusu';

  final TextEditingController _plannedTimeCtrl = TextEditingController();
  final TextEditingController _receiverNameCtrl = TextEditingController();
  final TextEditingController _receiverPhoneCtrl = TextEditingController();
  final TextEditingController _vehiclePlateCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _plannedTimeCtrl.text = DateFormat(
      'HH:mm',
    ).format(DateTime.now().add(const Duration(minutes: 45)));
    _bootstrap();
  }

  @override
  void dispose() {
    _plannedTimeCtrl.dispose();
    _receiverNameCtrl.dispose();
    _receiverPhoneCtrl.dispose();
    _vehiclePlateCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _isLoading = true);
    try {
      _schoolDocId = await _service.resolveSchoolDocId(widget.institutionId);

      Map<String, dynamic> stData = widget.initialStudentData != null
          ? Map<String, dynamic>.from(widget.initialStudentData!)
          : {};
      if (stData.isEmpty && widget.studentId.isNotEmpty) {
        final stDoc = await FirebaseFirestore.instance
            .collection('students')
            .doc(widget.studentId)
            .get();
        if (stDoc.exists) {
          stData = {...stDoc.data()!, 'id': stDoc.id};
        }
      } else if (widget.studentId.isNotEmpty) {
        stData['id'] = widget.studentId;
      }
      _student = stData;

      // Veli bilgilerini varsayılan doldur
      final authUser = FirebaseAuth.instance.currentUser;
      String pName = (stData['parentName'] ?? '').toString().trim();
      String pPhone = (stData['parentPhone'] ?? '').toString().trim();
      if (authUser != null) {
        try {
          final uDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(authUser.uid)
              .get();
          if (uDoc.exists) {
            final u = uDoc.data()!;
            final full =
                (u['fullName'] ??
                        '${u['name'] ?? ''} ${u['surname'] ?? ''}'.trim())
                    .toString()
                    .trim();
            final ph = (u['phone'] ?? '').toString().trim();
            if (full.isNotEmpty) pName = full;
            if (ph.isNotEmpty) pPhone = ph;
          }
        } catch (_) {}
      }
      if (pName.isEmpty &&
          stData['parents'] is Iterable &&
          (stData['parents'] as Iterable).isNotEmpty) {
        final first = (stData['parents'] as Iterable).first;
        if (first is Map) {
          pName = '${first['name'] ?? ''} ${first['surname'] ?? ''}'.trim();
          if (pPhone.isEmpty) {
            pPhone = (first['phone'] ?? '').toString().trim();
          }
        }
      }
      _receiverNameCtrl.text = pName;
      _receiverPhoneCtrl.text = pPhone;

      final schoolTypeId = (stData['schoolTypeId'] ?? '').toString();
      final classId = (stData['classId'] ?? '').toString();

      final sched = await _service.resolveTodayScheduleForStudent(
        institutionId: widget.institutionId,
        schoolTypeId: schoolTypeId,
        classId: classId,
        studentId: widget.studentId,
      );

      _slots = sched.slots;
      _selectedLessonHour = sched.currentLessonHour;
      final activeSlot = _slots.where(
        (s) => s.lessonHour == _selectedLessonHour,
      );
      if (activeSlot.isNotEmpty && activeSlot.first.startTime.isNotEmpty) {
        _plannedTimeCtrl.text = activeSlot.first.endTime.isNotEmpty
            ? activeSlot.first.endTime
            : activeSlot.first.startTime;
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _studentDisplayName {
    final full = (_student['fullName'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    return '${_student['name'] ?? ''} ${_student['surname'] ?? ''}'.trim();
  }

  String get _studentClass => (_student['className'] ?? '').toString().trim();

  String get _studentNo =>
      (_student['studentNo'] ??
              _student['studentNumber'] ??
              _student['no'] ??
              '')
          .toString()
          .trim();

  Future<void> _submitEarlyPickup() async {
    if (widget.studentId.isEmpty || _student.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Öğrenci bilgisi bulunamadı.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final maxH = _slots.isNotEmpty ? _slots.last.lessonHour : 8;
      final remainingHours = [
        for (int h = _selectedLessonHour; h <= maxH; h++) h,
      ];
      final slotMatch = _slots.where(
        (s) => s.lessonHour == _selectedLessonHour,
      );
      final targetSlot = slotMatch.isNotEmpty ? slotMatch.first : null;

      await _service.createEarlyPickupNotice(
        institutionId: widget.institutionId,
        schoolTypeId: (_student['schoolTypeId'] ?? '').toString(),
        schoolTypeName: (_student['schoolTypeName'] ?? '').toString(),
        student: _student,
        targetLessonHour: _selectedLessonHour,
        remainingHours: remainingHours,
        reason: _selectedReason,
        plannedPickupTime: _arrivedNowMode
            ? DateFormat('HH:mm').format(DateTime.now())
            : _plannedTimeCtrl.text.trim(),
        receiverName: _receiverNameCtrl.text.trim(),
        receiverRelation: _receiverRelation,
        receiverPhone: _receiverPhoneCtrl.text.trim(),
        vehiclePlate: _vehiclePlateCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        arrivedNow: _arrivedNowMode,
        requestSource: 'parent_portal',
        targetSlot: targetSlot,
      );

      _notesCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          content: Text(
            _arrivedNowMode
                ? '✓ Okula geldiğiniz dersi olan öğretmene, idareye ve güvenliğe anında bildirildi! Öğrenciniz hazırlanıyor.'
                : '✓ Erken alma ön bildiriminiz okul idaresine ve güvenlik birimine iletildi. Okula ulaştığınızda "Okula Geldim" butonuna basabilirsiniz.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _triggerArrivedNow(StudentMovementRecord record) async {
    setState(() => _isSubmitting = true);
    try {
      await _service.notifyParentArrivedAtSchool(record: record);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF059669),
          content: Text(
            '📍 Okula geldiğiniz dersi olan öğretmene ve güvenliğe anlık olarak iletildi! Öğrenciniz çıkışa yönlendiriliyor.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        institutionId: widget.institutionId,
        title: 'Erken Alma & Okula Geldim Bildirimi',
        subtitle: _studentDisplayName.isNotEmpty
            ? '${_studentNo.isNotEmpty ? "$_studentNo • " : ""}$_studentDisplayName${_studentClass.isNotEmpty ? " ($_studentClass)" : ""}'
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<StudentMovementRecord>>(
              stream: _service.watchStudentEarlyPickupsForToday(
                schoolDocId: _schoolDocId,
                studentId: widget.studentId,
              ),
              builder: (context, snap) {
                final todayRecords =
                    snap.data ?? const <StudentMovementRecord>[];
                final activeRecords = todayRecords
                    .where((r) => r.status != StudentMovementStatus.cancelled)
                    .toList();

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
                      children: [
                        _buildHowItWorksBanner(),
                        if (activeRecords.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ...activeRecords.map(_buildLivePickupStatusCard),
                        ],
                        const SizedBox(height: 16),
                        _buildEarlyPickupFormCard(),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildHowItWorksBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.directions_car_filled_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Öğrencinizi Beklemeden, Tam Zamanında Teslim Alın',
                  style: GoogleFonts.inter(
                    fontSize: 14.2,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '1) Önceden alacağınız saati haber verin • 2) Okul kapısına ulaştığınızda "Okula Geldim" butonuna dokunun • 3) Ders öğretmenine otomatik hazırlık bildirimi gitsin, güvenlik onayıyla kalan dersler izinli yazılsın.',
                  style: GoogleFonts.inter(
                    fontSize: 11.8,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePickupStatusCard(StudentMovementRecord r) {
    int currentStep = 1;
    if (r.status == StudentMovementStatus.parentArrived) {
      currentStep = 2;
    } else if (r.status == StudentMovementStatus.pendingGate) {
      currentStep = 3;
    } else if (r.status == StudentMovementStatus.exitedSchool) {
      currentStep = 4;
    }

    final steps = [
      '1. Okula Haber Verildi (${r.plannedExitTime.isNotEmpty ? r.plannedExitTime : DateFormat("HH:mm").format(r.createdAt)})',
      '2. Okula Geldim — Ders Öğretmenine Çağrı İletildi',
      '3. Öğrenciniz Çıkış / Güvenlik Noktasına Yönlendirildi',
      '4. Güvenli Teslimat Tamamlandı (Kalan Dersler İzinli)',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: currentStep == 4
              ? const Color(0xFF0284C7).withValues(alpha: 0.4)
              : _accent.withValues(alpha: 0.45),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: r.status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  r.status.label,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: r.status.color,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Planlanan: ${r.plannedExitTime}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF475569),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${r.studentName} (${r.className}) — ${r.reason}',
            style: GoogleFonts.inter(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < steps.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0xFFE2E8F0),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9.5,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          (i + 1) <= currentStep
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 19,
                          color: (i + 1) <= currentStep
                              ? const Color(0xFF059669)
                              : const Color(0xFFCBD5E1),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            steps[i],
                            style: GoogleFonts.inter(
                              fontSize: 12.4,
                              fontWeight: (i + 1) == currentStep
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: (i + 1) <= currentStep
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (r.status == StudentMovementStatus.earlyPickupNotified) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : () => _triggerArrivedNow(r),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    vertical: 15,
                    horizontal: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.location_on_rounded, size: 21),
                label: Text(
                  'OKULA GELDİM — ÖĞRENCİMİ ÇIKIŞA HAZIRLAYIN',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
          if (r.status != StudentMovementStatus.exitedSchool) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _service.cancelMovement(r),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text(
                  'Bildirimi İptal Et',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEarlyPickupFormCard() {
    const reasons = [
      'Hastane / Doktor / Diş Hekimi Randevusu',
      'Ailevi Mazeret / Özel Durum',
      'Sağlık / İstirahat İhtiyacı',
      'Şehir Dışı Seyahat / Ulaşım Planı',
      'Resmi Kurum / Spor Lisans / Müsabaka İşlemi',
    ];

    const relations = [
      'Velisi (Kendim Teslim Alacağım)',
      'Anne / Baba',
      'Veli Onaylı Yakını / Aile Büyüğü',
    ];

    final slots = _slots.isNotEmpty
        ? _slots
        : List.generate(
            8,
            (i) => ResolvedLessonSlot(
              lessonHour: i + 1,
              lessonId: '',
              lessonName: '${i + 1}. Ders',
            ),
          );

    final now = DateTime.now();
    final dayLabel = StudentMovementService.dayNameTr(now.weekday);
    final nowClockStr = DateFormat('dd.MM.yyyy').format(now);
    final nowHmStr = DateFormat('HH:mm').format(now);
    final schedDay = slots.isNotEmpty && slots.first.scheduleDayName.isNotEmpty
        ? slots.first.scheduleDayName
        : dayLabel;

    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return Container(
      padding: EdgeInsets.all(isMobile ? 15 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Yeni Erken Alma Bildirimi Oluştur',
            style: GoogleFonts.inter(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Önceden saat bildirebilir veya şu an okul kapısındaysanız doğrudan çağrı gönderebilirsiniz.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDFA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF99F6E4)),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.access_time_filled_rounded,
                      size: 16,
                      color: _accent,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'İşlem Zamanı: $nowClockStr $dayLabel • Saat $nowHmStr',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '• $schedDay Programı (${slots.length} Ders)',
                  style: GoogleFonts.inter(
                    fontSize: 11.8,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 16),

          // 1. Zamanlama Modu (Alt Alta Çeklist)
          _buildChecklistGroup<bool>(
            label: '1. Bildirim Durumu',
            selectedValue: _arrivedNowMode,
            items: const [
              (
                value: false,
                title: 'Önceden Haber Veriyorum (Belirttiğim Saatte Alacağım)',
                badge: 'Planlı Bildirim',
              ),
              (
                value: true,
                title:
                    'Şu An Okula Geldim / Kapıdayım (Öğrencim Hemen Hazırlansın)',
                badge: 'Anlık Çağrı',
              ),
            ],
            onSelected: (v) => setState(() => _arrivedNowMode = v),
          ),
          const SizedBox(height: 16),

          // 2. Ders Saati Seçimi (Alt Alta Çeklist)
          if (!_arrivedNowMode) ...[
            _buildChecklistGroup<int>(
              label:
                  '2. Hangi Ders Saatinde Alacaksınız? ($schedDay • Toplam ${slots.length} Ders)',
              selectedValue: _selectedLessonHour,
              items: slots.map((s) {
                final timeRange = s.startTime.isNotEmpty
                    ? (s.endTime.isNotEmpty
                          ? '${s.startTime} - ${s.endTime}'
                          : s.startTime)
                    : null;
                final hasLesson =
                    s.lessonName.isNotEmpty &&
                    s.lessonName != '${s.lessonHour}. Ders';
                return (
                  value: s.lessonHour,
                  title:
                      '${s.lessonHour}. Ders${timeRange != null ? "  •  $timeRange" : ""}',
                  badge: hasLesson
                      ? '${s.lessonName}${s.teacherNames.isNotEmpty ? " • ${s.teacherNames.join(", ")}" : ""}'
                      : timeRange,
                );
              }).toList(),
              onSelected: (h) {
                setState(() {
                  _selectedLessonHour = h;
                  final m = slots.where((s) => s.lessonHour == h);
                  if (m.isNotEmpty && m.first.startTime.isNotEmpty) {
                    _plannedTimeCtrl.text = m.first.startTime;
                  }
                });
              },
            ),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _plannedTimeCtrl,
              label: 'Planlanan Okuldan Alış Saati (SS:DD)',
              hint: 'Örn: 14:30',
              icon: Icons.access_time_rounded,
            ),
            const SizedBox(height: 16),
          ],

          // 3. Teslim Alacak Kişi (Alt Alta Çeklist)
          _buildChecklistGroup<String>(
            label: _arrivedNowMode
                ? '2. Öğrenciyi Teslim Alacak Kişi'
                : '3. Öğrenciyi Teslim Alacak Kişi',
            selectedValue: _receiverRelation,
            items: relations
                .map(
                  (r) => (
                    value: r,
                    title: r,
                    badge: _receiverRelation == r ? 'Seçili' : null,
                  ),
                )
                .toList(),
            onSelected: (v) => setState(() => _receiverRelation = v),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _receiverNameCtrl,
            label: 'Teslim Alacak Kişi Adı Soyadı',
            hint: 'Ad Soyad',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _receiverPhoneCtrl,
            label: 'İletişim Telefonu',
            hint: '05XX XXX XX XX',
            icon: Icons.phone_outlined,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _vehiclePlateCtrl,
            label: 'Araç Plakası / Kapı Bilgisi (İsteğe Bağlı)',
            hint: 'Örn: 06 ABC 123 • Ana giriş kapısındayım',
            icon: Icons.directions_car_outlined,
          ),
          const SizedBox(height: 16),

          // 4. Erken Alma Nedeni (Alt Alta Çeklist)
          _buildChecklistGroup<String>(
            label: _arrivedNowMode
                ? '3. Erken Alma Nedeni'
                : '4. Erken Alma Nedeni',
            selectedValue: _selectedReason,
            items: reasons
                .map(
                  (r) => (
                    value: r,
                    title: r,
                    badge: _selectedReason == r ? 'Seçili' : null,
                  ),
                )
                .toList(),
            onSelected: (v) => setState(() => _selectedReason = v),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _notesCtrl,
            label: 'Ek Açıklama / Öğretmene veya İdareye Not (İsteğe Bağlı)',
            hint:
                'Örn: Beslenme çantasını ve montunu yanına almasını rica ederim...',
            icon: Icons.edit_note_rounded,
          ),
          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitEarlyPickup,
              style: ElevatedButton.styleFrom(
                backgroundColor: _arrivedNowMode
                    ? const Color(0xFF059669)
                    : _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _arrivedNowMode
                          ? Icons.location_on_rounded
                          : Icons.notifications_active_rounded,
                      size: 20,
                    ),
              label: Text(
                _arrivedNowMode
                    ? 'ŞU AN OKULDAYIM — ÖĞRETMENE & GÜVENLİĞE BİLDİR'
                    : 'ERKEN ALMA ÖN BİLDİRİMİNİ OKULA GÖNDER',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistGroup<T>({
    required String label,
    required T selectedValue,
    required List<({T value, String title, String? badge})> items,
    required ValueChanged<T> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 7, left: 2),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.4,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF334155),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF1F5F9),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isSel = selectedValue == items[i].value;
                    final badgeText = items[i].badge;
                    final hasBadge = badgeText != null && badgeText.isNotEmpty;
                    final stackBadge =
                        hasBadge &&
                        constraints.maxWidth < 460 &&
                        badgeText.length > 14;

                    Widget buildBadgeChip({double maxWidth = 240}) {
                      return Container(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? _accent.withValues(alpha: 0.14)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badgeText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSel ? _accent : const Color(0xFF475569),
                          ),
                        ),
                      );
                    }

                    return Material(
                      color: isSel
                          ? _accent.withValues(alpha: 0.065)
                          : Colors.white,
                      child: InkWell(
                        onTap: () => onSelected(items[i].value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10.5,
                          ),
                          child: Row(
                            crossAxisAlignment: stackBadge
                                ? CrossAxisAlignment.start
                                : CrossAxisAlignment.center,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  top: stackBadge ? 2 : 0,
                                ),
                                child: Icon(
                                  isSel
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  size: 20,
                                  color: isSel
                                      ? _accent
                                      : const Color(0xFFCBD5E1),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      items[i].title,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: isSel
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: isSel
                                            ? _accent
                                            : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    if (stackBadge) ...[
                                      const SizedBox(height: 5),
                                      buildBadgeChip(
                                        maxWidth: constraints.maxWidth - 48,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (hasBadge && !stackBadge) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  flex: 0,
                                  child: buildBadgeChip(
                                    maxWidth: constraints.maxWidth < 460
                                        ? 135
                                        : 240,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.2,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF334155),
            ),
          ),
        ),
        TextField(
          controller: controller,
          textAlignVertical: TextAlignVertical.center,
          style: GoogleFonts.inter(
            fontSize: 13.4,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              fontSize: 12.8,
              color: const Color(0xFF94A3B8),
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 10, right: 8),
              child: Center(
                widthFactor: 1,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16.5, color: _accent),
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 48,
              minHeight: 44,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFE2E8F0),
                width: 1.2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _accent, width: 1.8),
            ),
          ),
        ),
      ],
    );
  }
}
