import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../../models/school/butterfly_exam_model.dart';
import '../../../../models/school/seating_plan_model.dart';
import '../../../../services/butterfly_pdf_service.dart';
import '../../../../services/butterfly_distribution_service.dart';
import '../../../../widgets/edukn_app_bar.dart';
import 'butterfly_exam_wizard_screen.dart';

/// Kelebek Sınav Detay, Kroki, Sürükle-Bırak Düzenleyici ve PDF Önizleme Ekranı
class ButterflyExamDetailScreen extends StatefulWidget {
  final ExamDistribution distribution;
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final bool isDraft;

  const ButterflyExamDetailScreen({
    super.key,
    required this.distribution,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.isDraft = false,
  });

  @override
  State<ButterflyExamDetailScreen> createState() => _ButterflyExamDetailScreenState();
}

class _ButterflyExamDetailScreenState extends State<ButterflyExamDetailScreen>
    with SingleTickerProviderStateMixin {
  late ExamDistribution _currentDistribution;
  late TabController _tabController;
  late bool _isDraft;
  int _selectedRoomIndex = 0;

  // Manuel Müdahale (Yer Değiştirme / Swap Seçimi)
  SeatCoordinate? _selectedSeatForSwap;
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;
  bool _isPublishing = false;

  // Kapı Listesi Arama
  String _gateSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _currentDistribution = widget.distribution.clone();
    _isDraft = widget.isDraft || (_currentDistribution.id == null || _currentDistribution.id!.isEmpty);
    if (!_isDraft && widget.distribution.updatedAt != null) {
      _hasUnsavedChanges = true;
    }
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  ExamRoom get _currentRoom =>
      _currentDistribution.rooms[_selectedRoomIndex.clamp(0, _currentDistribution.rooms.length - 1)];

  // ===========================================================================
  // ARAYÜZ (DETAY GÖVDE)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final dateStr = DateFormat('dd.MM.yyyy').format(_currentDistribution.examDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: _currentDistribution.title,
        subtitle: '${_currentDistribution.lessonName} • $dateStr (${_currentDistribution.examTime})',
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        subtitleColor: const Color(0xFF64748B),
        backButtonColor: const Color(0xFF4F46E5),
        borderColor: const Color(0xFFE2E8F0),
        actions: [
          // Farklı Dağıt (Yeniden Karıştır) Butonu
          if (_isDraft)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4F46E5),
                  side: const BorderSide(color: Color(0xFF818CF8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isSaving ? null : _reshuffleDistribution,
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: const Text('Farklı Dağıt', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          // Değişiklikleri Kaydet Butonu
          if (_isDraft || _hasUnsavedChanges)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isSaving ? null : _saveChangesToFirestore,
                icon: _isSaving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(
                  _isSaving ? 'Kaydediliyor...' : (_isDraft ? 'Oturumu Kaydet' : 'Kaydet'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Önizleme / Kaydedilmemiş Değişiklik Bilgi Şeridi
            if (_isDraft || _hasUnsavedChanges)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: const Color(0xFFEFF6FF),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isDraft
                            ? '✨ Dağıtım önizlemesi hazır. Koltuklara dokunarak öğrencileri takas edebilir, ardından "Oturumu Kaydet" butonuna basabilirsiniz.'
                            : 'Oturma planında kaydedilmemiş değişiklikler var.',
                        style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF1E40AF), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            // Üst Sekmeler: 1. Sınav Krokisi, 2. Kapı Listesi, 3. PDF Önizleme & Çıktı
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF4F46E5),
                indicatorWeight: 3,
                labelColor: const Color(0xFF4F46E5),
                unselectedLabelColor: const Color(0xFF64748B),
                labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
                unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(icon: Icon(Icons.grid_on_rounded, size: 18), text: 'Gözetmen Krokisi'),
                  Tab(icon: Icon(Icons.door_front_door_outlined, size: 18), text: 'Kapı Listesi'),
                  Tab(icon: Icon(Icons.picture_as_pdf_rounded, size: 18), text: 'PDF Çıktıları'),
                ],
              ),
            ),

            // Gözetmenlik Yayınlama Durumu & Sınav Yönergesi Kontrol Paneli
            _buildProctoringPublishBanner(isMobile),

            // Salon Seçim Çubuğu (Tüm Sekmeler İçin Ortak)
            _buildRoomSelectorBar(isMobile),

            // Sekme İçerikleri
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSupervisorGridTab(isMobile),
                  _buildGateListTab(isMobile),
                  _buildPdfPreviewTab(isMobile),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: (!_currentDistribution.isProctoringPublished || _isDraft)
          ? _buildBottomDistributionToolbar(isMobile)
          : null,
    );
  }

  // ===========================================================================
  // DAĞITIM ÖNCESİNE DÖNÜŞ (ALT ARAÇ ÇUBUĞU)
  // ===========================================================================
  Widget _buildBottomDistributionToolbar(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 20,
        vertical: isMobile ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: isMobile
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const Icon(Icons.settings_backup_restore_rounded, size: 20),
                    label: Text(
                      'Dağıtım Öncesine Dön (Adı, Saati, Salonlar)',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    onPressed: _returnToDistributionWizard,
                  ),
                ],
              )
            : Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tune_rounded, color: Color(0xFF4F46E5), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sınav Parametreleri Düzenleme Modu',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
                        ),
                        Text(
                          'Sınav adı, saati, şubeler, salonlar ve gözetmenlik ayarlarını değiştirebilirsiniz.',
                          style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
                    label: Text(
                      'Dağıtım Öncesine Dön',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    onPressed: _returnToDistributionWizard,
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _returnToDistributionWizard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.settings_backup_restore_rounded, color: Color(0xFF4F46E5), size: 22),
            ),
            const SizedBox(width: 12),
            Text('Dağıtım Öncesine Dön', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Sınav sihirbazına dönerek sınav adını, saatini, dahil edilen şubeleri ve sınav salonlarını dilediğiniz gibi düzenleyebilir, ardından yeni dağıtımı oluşturabilirsiniz.\n\nDevam etmek istiyor musunuz?',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Vazgeç', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Evet, Dağıtım Öncesine Dön', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ButterflyExamWizardScreen(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          existingDistribution: _currentDistribution,
        ),
      ),
    );
  }

  // ===========================================================================
  // GÖZETMENLİK YAYIN DURUMU & YÖNERGE KONTROL ŞERİDİ
  // ===========================================================================
  Widget _buildProctoringPublishBanner(bool isMobile) {
    if (_isDraft) return const SizedBox.shrink();

    final isPublished = _currentDistribution.isProctoringPublished;
    final hasInstructions = _currentDistribution.instructions.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isPublished ? const Color(0xFFF0FDF4) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPublished ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A),
        ),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isPublished ? Icons.check_circle_rounded : Icons.schedule_rounded,
                      color: isPublished ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isPublished
                            ? 'Gözetmenlikler Yayınlandı & Aktif'
                            : 'Gözetmenlikler Henüz Yayınlanmadı',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isPublished ? const Color(0xFF15803D) : const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (hasInstructions) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.gavel_rounded, size: 14),
                          label: Text(
                            'Yönerge (${_currentDistribution.instructions.length})',
                            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _showExamInstructionsModal,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: isPublished
                          ? OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _isPublishing ? null : _unpublishProctoringDuties,
                              child: _isPublishing
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text('Yayından Kaldır', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            )
                          : ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4F46E5),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: _isPublishing
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.send_rounded, size: 14),
                              label: Text('Gözetmenlikleri Yayınla', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold)),
                              onPressed: _isPublishing ? null : _publishProctoringDuties,
                            ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Icon(
                  isPublished ? Icons.check_circle_rounded : Icons.schedule_rounded,
                  color: isPublished ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPublished
                            ? 'Gözetmenlik Görevleri Öğretmen Panellerinde Yayınlandı'
                            : 'Gözetmenlik Görevleri Henüz Yayınlanmadı (Taslak)',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isPublished ? const Color(0xFF15803D) : const Color(0xFFB45309),
                        ),
                      ),
                      Text(
                        isPublished
                            ? 'Öğretmenler takvimlerinde görevi görebilir, yönergeyi inceleyebilir ve canlı yoklama alabilir.'
                            : 'Öğretmenlerin takviminde görünmez. Planlamanızı bitirdiğinizde dilediğiniz zaman yayınlayabilirsiniz.',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (hasInstructions) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.gavel_rounded, size: 16),
                    label: Text(
                      'Sınav Yönergesi (${_currentDistribution.instructions.length} Madde)',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _showExamInstructionsModal,
                  ),
                  const SizedBox(width: 8),
                ],
                if (isPublished)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.unpublished_outlined, size: 16),
                    label: const Text('Yayından Kaldır', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _isPublishing ? null : _unpublishProctoringDuties,
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isPublishing
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.campaign_rounded, size: 18),
                    label: Text(
                      _isPublishing ? 'Yayınlanıyor...' : 'Gözetmenlikleri Yayınla & Bildir',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isPublishing ? null : _publishProctoringDuties,
                  ),
              ],
            ),
    );
  }

  // ===========================================================================
  // SALON SEÇİM ŞERİDİ
  // ===========================================================================
  Widget _buildRoomSelectorBar(bool isMobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _currentDistribution.rooms.asMap().entries.map((entry) {
            final idx = entry.key;
            final room = entry.value;
            final isSelected = _selectedRoomIndex == idx;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.meeting_room_rounded,
                      size: 15,
                      color: isSelected ? Colors.white : const Color(0xFF4F46E5),
                    ),
                    const SizedBox(width: 6),
                    Text('${room.classroomName} (${room.seatedStudentCount}/${room.totalCapacity})'),
                  ],
                ),
                selected: isSelected,
                selectedColor: const Color(0xFF4F46E5),
                backgroundColor: const Color(0xFFF1F5F9),
                labelStyle: GoogleFonts.inter(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 12.5,
                  color: isSelected ? Colors.white : const Color(0xFF334155),
                ),
                onSelected: (_) {
                  setState(() {
                    _selectedRoomIndex = idx;
                    _selectedSeatForSwap = null;
                  });
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. SEKME: GÖZETMEN KROKİSİ & SÜRÜKLE-BIRAK / SWAP DÜZENLEYİCİ
  // ===========================================================================
  Widget _buildSupervisorGridTab(bool isMobile) {
    final room = _currentRoom;
    final layout = room.layoutSnapshot;

    final Map<String, DeskCell> cellMap = {
      for (final c in layout.cells) '${c.row}-${c.col}': c,
    };

    final Map<String, SeatCoordinate> seatMap = {
      for (final s in room.seats) '${s.row}-${s.col}-${s.slotIndex}': s,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Swap / Yer Değiştirme Bilgi Kartı
          if (_selectedSeatForSwap != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz_rounded, color: Color(0xFFD97706), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Seçili: ${_selectedSeatForSwap!.student?.fullName ?? "Sıra ${_selectedSeatForSwap!.seatNumber}"} -> Yerini değiştirmek istediğiniz diğer sıraya dokunun.',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF92400E)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectedSeatForSwap = null),
                    child: const Text('İptal Et', style: TextStyle(color: Color(0xFFB45309))),
                  ),
                ],
              ),
            ),

          // Öğretmen Kürsüsü / Yazı Tahtası
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF334155), Color(0xFF1E293B)]),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
                bottomLeft: Radius.circular(22),
                bottomRight: Radius.circular(22),
              ),
              boxShadow: [
                BoxShadow(color: const Color(0xFF1E293B).withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.co_present_rounded, size: 16, color: Color(0xFFFCD34D)),
                  const SizedBox(width: 8),
                  Text(
                    'ÖĞRETMEN KÜRSÜSÜ  •  YAZI TAHTASI',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      color: Colors.white,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Fiziksel Masa Düzeni Matrisi
          ...List.generate(layout.rows, (rowIndex) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: List.generate(layout.cols, (colIndex) {
                  final cell = cellMap['$rowIndex-$colIndex'];

                  // Koridor / Boşluk
                  if (cell == null || cell.isAisle) {
                    return Expanded(
                      child: Container(
                        height: isMobile ? 70 : 85,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0), style: BorderStyle.none),
                        ),
                        child: Center(
                          child: Text(
                            'KORİDOR',
                            style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFCBD5E1), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    );
                  }

                  // Masa Hücresi
                  final isDouble = cell.deskType == DeskType.double;
                  final leftSeat = seatMap['$rowIndex-$colIndex-0'];
                  final rightSeat = isDouble ? seatMap['$rowIndex-$colIndex-1'] : null;

                  return Expanded(
                    child: Container(
                      height: isMobile ? 70 : 85,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFC7D2FE), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: isDouble
                          ? Row(
                              children: [
                                Expanded(child: _buildInteractiveSeat(leftSeat, isMobile)),
                                Container(width: 1, color: const Color(0xFFE2E8F0), margin: const EdgeInsets.symmetric(horizontal: 2)),
                                Expanded(child: _buildInteractiveSeat(rightSeat, isMobile)),
                              ],
                            )
                          : _buildInteractiveSeat(leftSeat, isMobile),
                    ),
                  );
                }),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ===========================================================================
  // İNTERAKTİF KOLTUK BİLEŞENİ (DOKUN-DEĞİŞTİR / SWAP DESTEKLİ)
  // ===========================================================================
  static const List<Color> _classAccents = [
    Color(0xFF4F46E5),
    Color(0xFF0D9488),
    Color(0xFFEA580C),
    Color(0xFF9333EA),
    Color(0xFF2563EB),
    Color(0xFF15803D),
    Color(0xFFDB2777),
    Color(0xFFB45309),
    Color(0xFF0E7490),
    Color(0xFF78350F),
  ];

  Color _classAccent(String className) {
    var h = 0;
    for (final u in className.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return _classAccents[h % _classAccents.length];
  }

  Widget _buildInteractiveSeat(SeatCoordinate? seat, bool isMobile) {
    if (seat == null) return const SizedBox();

    final student = seat.student;
    final isSelectedForSwap = _selectedSeatForSwap == seat;
    final accent = student != null ? _classAccent(student.className) : const Color(0xFF94A3B8);

    return InkWell(
      onTap: () => _handleSeatTap(seat),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isSelectedForSwap
              ? const Color(0xFFFEF3C7)
              : (student != null ? Colors.white : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelectedForSwap ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
            width: isSelectedForSwap ? 2 : 1,
          ),
          boxShadow: student != null
              ? [BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 6, offset: const Offset(0, 2))]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 5, 4),
                child: student == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${seat.seatNumber}',
                                style: GoogleFonts.inter(
                                    fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFFA7B1C2))),
                            Text('BOŞ',
                                style: GoogleFonts.inter(
                                    fontSize: 8.5, fontWeight: FontWeight.w700, color: const Color(0xFFA7B1C2))),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                                child: Text('${seat.seatNumber}',
                                    style: GoogleFonts.inter(
                                        fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(student.className,
                                    style: GoogleFonts.inter(
                                        fontSize: 8.5, fontWeight: FontWeight.w800, color: accent)),
                              ),
                            ],
                          ),
                          Text(
                            student.fullName,
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: isMobile ? 9 : 10.5,
                                height: 1.1,
                                color: const Color(0xFF1E293B)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text('No: ${student.studentNumber}',
                              style: GoogleFonts.inter(fontSize: 8, color: const Color(0xFF64748B))),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSeatTap(SeatCoordinate tappedSeat) {
    if (_selectedSeatForSwap == null) {
      // İlk koltuk seçimi
      setState(() => _selectedSeatForSwap = tappedSeat);
    } else {
      // İkinci koltuk seçimi -> Değiştir (Swap)
      if (_selectedSeatForSwap != tappedSeat) {
        final updated = ButterflyDistributionService.swapStudents(
          distribution: _currentDistribution,
          sourceRoomId: _selectedSeatForSwap!.roomId,
          sourceSeatNumber: _selectedSeatForSwap!.seatNumber,
          targetRoomId: tappedSeat.roomId,
          targetSeatNumber: tappedSeat.seatNumber,
        );

        setState(() {
          _currentDistribution = updated;
          _selectedSeatForSwap = null;
          _hasUnsavedChanges = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Öğrencilerin yerleri başarıyla değiştirildi. Değişiklikleri kaydetmeyi unutmayın.')),
        );
      } else {
        setState(() => _selectedSeatForSwap = null);
      }
    }
  }

  // ===========================================================================
  // 2. SEKME: KAPI LİSTESİ TABLOSU
  // ===========================================================================
  Widget _buildGateListTab(bool isMobile) {
    final room = _currentRoom;
    final students = List<ExamStudent>.from(room.seatedStudents);
    students.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

    final filtered = students.where((s) {
      if (_gateSearchQuery.isEmpty) return true;
      final q = _gateSearchQuery.toLowerCase();
      return s.fullName.toLowerCase().contains(q) ||
          s.studentNumber.contains(q) ||
          s.className.toLowerCase().contains(q);
    }).toList();

    // Koltuk numaralarını eşleştir
    final Map<String, int> seatMap = {};
    for (final seat in room.seats) {
      if (seat.student != null) {
        seatMap[seat.student!.id] = seat.seatNumber;
      }
    }

    return Column(
      children: [
        // Arama Kutusu & PDF Yazdır Butonu
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (val) => setState(() => _gateSearchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Öğrenci adı, no veya şube ara...',
                    hintStyle: GoogleFonts.inter(fontSize: 12.5),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _printRoomGateList(room),
                icon: const Icon(Icons.print_rounded, size: 16),
                label: const Text('Yazdır'),
              ),
            ],
          ),
        ),

        // Tablo
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final student = filtered[index];
              final seatNo = seatMap[student.id]?.toString() ?? '-';

              return Container(
                color: index % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEEF2FF),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF4F46E5)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            student.fullName,
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
                          ),
                          Text(
                            'Okul No: ${student.studentNumber} • Şube: ${student.className}',
                            style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFC7D2FE)),
                      ),
                      child: Text(
                        'Sıra $seatNo',
                        style: GoogleFonts.robotoMono(fontWeight: FontWeight.w900, color: const Color(0xFF312E81), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 3. SEKME: PDF ÖNİZLEME & TOPLU ÇIKTILAR (PREMIUM RAPOR MERKEZİ)
  // ===========================================================================
  Widget _buildPdfPreviewTab(bool isMobile) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. BÖLÜM: TÜM SINAV OTURUMU TOPLU RAPORLARI
          _buildSectionHeader('Tüm Sınav Oturumu Toplu Raporları', 'Sınavın tamamına ait toplu listeleri ve krokileri tek tıkla PDF olarak yazdırın.'),
          const SizedBox(height: 10),

          // PDF Başlığında Sınav Adını Gösterme / Gizleme Switch'i
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF64748B).withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF4F46E5), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PDF Başlığında Gerçek Sınav Adını Göster',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
                      ),
                      Text(
                        _currentDistribution.showExamTitleOnPdf
                            ? 'PDF çıktılarında "${_currentDistribution.title}" yazılacak'
                            : 'PDF çıktılarında sınav adı gizlenecek, sadece "Deneme Sınavı" yazacak',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _currentDistribution.showExamTitleOnPdf,
                  activeTrackColor: const Color(0xFFC7D2FE),
                  activeThumbColor: const Color(0xFF4F46E5),
                  onChanged: (val) {
                    setState(() {
                      final updated = _currentDistribution.toMap();
                      updated['showExamTitleOnPdf'] = val;
                      _currentDistribution = ExamDistribution.fromMap(updated, _currentDistribution.id ?? '');
                    });
                  },
                ),
              ],
            ),
          ),

          // 2x2 Kompakt ve Şık Rapor Kartları
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              // 1. GENEL ALFABETİK LİSTE (A-Z)
              SizedBox(
                width: isMobile ? double.infinity : (MediaQuery.of(context).size.width - 64) / 2,
                child: _buildReportActionCard(
                  title: 'Genel Alfabetik Yerleşim Listesi',
                  subtitle: 'Tüm okul / öğrencilerin A-Z isim sırasına göre salon ve sıra numaraları',
                  icon: Icons.sort_by_alpha_rounded,
                  iconColor: const Color(0xFF4F46E5),
                  badgeText: 'A - Z Liste',
                  badgeColor: const Color(0xFFEEF2FF),
                  onTap: _printMasterAlphabeticalList,
                ),
              ),

              // 2. TÜM KAPI LİSTELERİ
              SizedBox(
                width: isMobile ? double.infinity : (MediaQuery.of(context).size.width - 64) / 2,
                child: _buildReportActionCard(
                  title: 'Tüm Salonların Kapı Listeleri',
                  subtitle: 'Her salon için kapıya asılacak öğrenci listeleri tek dosyada',
                  icon: Icons.door_front_door_rounded,
                  iconColor: const Color(0xFF0284C7),
                  badgeText: '${_currentDistribution.rooms.length} Salon',
                  badgeColor: const Color(0xFFE0F2FE),
                  onTap: _printAllGateLists,
                ),
              ),

              // 3. TÜM YOKLAMA LİSTELERİ (+/-)
              SizedBox(
                width: isMobile ? double.infinity : (MediaQuery.of(context).size.width - 64) / 2,
                child: _buildReportActionCard(
                  title: 'Tüm Salon Yoklama Listeleri',
                  subtitle: 'Gözetmenlerin yoklama alıp (+ / -) imzalayacağı resmi tutanak listeleri',
                  icon: Icons.fact_check_rounded,
                  iconColor: const Color(0xFFD97706),
                  badgeText: 'Yoklama & İmza',
                  badgeColor: const Color(0xFFFEF3C7),
                  onTap: _printAllAttendanceLists,
                ),
              ),

              // 4. TÜM GÖZETMEN KROKİLERİ
              SizedBox(
                width: isMobile ? double.infinity : (MediaQuery.of(context).size.width - 64) / 2,
                child: _buildReportActionCard(
                  title: 'Tüm Gözetmen Krokileri',
                  subtitle: 'Her salonun kuşbakışı fiziksel masa oturma planı (İmzasız temiz görünüm)',
                  icon: Icons.grid_view_rounded,
                  iconColor: const Color(0xFF059669),
                  badgeText: 'Kuşbakışı',
                  badgeColor: const Color(0xFFECFDF5),
                  onTap: _printAllSupervisorPlans,
                ),
              ),

              // 5. TÜM SINAV DAVRANIŞLARI GÖZLEM FORMLARI (YATAY)
              SizedBox(
                width: isMobile ? double.infinity : (MediaQuery.of(context).size.width - 64) / 2,
                child: _buildReportActionCard(
                  title: 'Sınav Davranışları Gözlem Formları',
                  subtitle: 'Her salon için yatay, 25 öğrencilik gözlem kâğıdı (gözetmen doldurur)',
                  icon: Icons.visibility_rounded,
                  iconColor: const Color(0xFF9333EA),
                  badgeText: 'Gözlem Formu',
                  badgeColor: const Color(0xFFF3E8FF),
                  onTap: _printAllObservationForms,
                ),
              ),

              // 6. TÜM SINAV PAKETİ (TEK PDF)
              SizedBox(
                width: isMobile ? double.infinity : (MediaQuery.of(context).size.width - 64) / 2,
                child: _buildReportActionCard(
                  title: 'Tüm Sınav Paketini Yazdır',
                  subtitle: 'Alfabetik liste, kapı listeleri, yoklama listeleri, gözetmen krokileri ve gözlem formları tek PDF\'de',
                  icon: Icons.print_rounded,
                  iconColor: const Color(0xFFE11D48),
                  badgeText: 'Tek PDF',
                  badgeColor: const Color(0xFFFFE4E6),
                  onTap: _printFullExamPackage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 2. BÖLÜM: SEÇİLİ SALONUN ÖZEL ÇIKTILARI
          _buildSectionHeader(
            '${_currentRoom.classroomName} Salonu Çıktıları',
            'Sadece aktif seçili olan bu salona ait belgeleri ayrı ayrı yazdırın.',
          ),
          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF64748B).withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.meeting_room_rounded, color: Color(0xFF4F46E5), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentRoom.classroomName,
                            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: const Color(0xFF1E293B)),
                          ),
                          Text(
                            'Kapasite: ${_currentRoom.totalCapacity} | Oturan: ${_currentRoom.seatedStudentCount} Öğrenci ${_currentRoom.supervisorName != null && _currentRoom.supervisorName!.isNotEmpty ? "• Gözetmen: ${_currentRoom.supervisorName}" : ""}',
                            style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        foregroundColor: const Color(0xFF4F46E5),
                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _printRoomGateList(_currentRoom),
                      icon: const Icon(Icons.door_front_door_outlined, size: 16),
                      label: const Text('Bu Salonun Kapı Listesi', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        foregroundColor: const Color(0xFFD97706),
                        side: const BorderSide(color: Color(0xFFFDE68A)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _printRoomAttendanceList(_currentRoom),
                      icon: const Icon(Icons.fact_check_outlined, size: 16),
                      label: const Text('Bu Salonun Yoklama Listesi', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        foregroundColor: const Color(0xFF0284C7),
                        side: const BorderSide(color: Color(0xFFBAE6FD)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _printRoomSupervisorPlan(_currentRoom),
                      icon: const Icon(Icons.grid_on_rounded, size: 16),
                      label: const Text('Bu Salonun Krokisi', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        foregroundColor: const Color(0xFF9333EA),
                        side: const BorderSide(color: Color(0xFFE9D5FF)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _printRoomObservationForm(_currentRoom),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('Bu Salonun Gözlem Formu', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required String badgeText,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF64748B).withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          badgeText,
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 9.5, color: iconColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.print_rounded, color: Color(0xFF94A3B8), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
        ),
      ],
    );
  }

  // ===========================================================================
  // ÖĞRENCİLERİ YENİDEN RASTGELE DAĞIT (RE-SHUFFLE)
  // ===========================================================================
  Future<void> _reshuffleDistribution() async {
    final allStudents = _currentDistribution.rooms
        .expand((r) => r.seats)
        .where((s) => s.student != null)
        .map((s) => s.student!)
        .toList();

    if (allStudents.isEmpty) return;

    final roomConfigs = _currentDistribution.rooms.map((r) => {
      'classroomId': r.classroomId,
      'classroomName': r.classroomName,
      'layout': r.layoutSnapshot,
      'customCapacity': r.seats.length,
      'supervisorId': r.supervisorId,
      'supervisorName': r.supervisorName,
    }).toList();

    final params = ButterflyDistributionParams(
      title: _currentDistribution.title,
      lessonName: _currentDistribution.lessonName,
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
      schoolTypeName: widget.schoolTypeName,
      examDate: _currentDistribution.examDate,
      examTime: _currentDistribution.examTime,
      selectedClassIds: _currentDistribution.selectedClassIds,
      selectedClassNames: _currentDistribution.selectedClassNames,
      gradeLevels: _currentDistribution.gradeLevels,
      students: allStudents,
      roomConfigs: roomConfigs,
      notes: _currentDistribution.notes,
      showExamTitleOnPdf: _currentDistribution.showExamTitleOnPdf,
    );

    setState(() => _isSaving = true);
    try {
      final newDist = await ButterflyDistributionService.distributeExam(params);
      setState(() {
        _currentDistribution = newDist;
        _hasUnsavedChanges = true;
        _selectedSeatForSwap = null;
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎲 Öğrenciler tamamen yeni bir rastgele dizilimle yeniden dağıtıldı!'),
            backgroundColor: Color(0xFF4F46E5),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yeniden dağıtım hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ===========================================================================
  // FIRESTORE'A DEĞİŞİKLİKLERİ KAYDETME
  // ===========================================================================
  Future<void> _saveChangesToFirestore() async {
    setState(() => _isSaving = true);

    try {
      String savedId = _currentDistribution.id ?? '';
      final examMap = _currentDistribution.toMap();
      examMap['institutionId'] = widget.institutionId;

      try {
        if (savedId.isEmpty) {
          final docRef = await FirebaseFirestore.instance
              .collection('butterfly_exams')
              .add(examMap);
          savedId = docRef.id;
        } else {
          await FirebaseFirestore.instance
              .collection('butterfly_exams')
              .doc(savedId)
              .set(examMap, SetOptions(merge: true));
        }
      } catch (colErr) {
        debugPrint('butterfly_exams save fallback: $colErr');
        examMap['isButterflyExam'] = true;
        examMap['type'] = 'butterfly_exam';

        if (savedId.isEmpty) {
          final docRef = await FirebaseFirestore.instance
              .collection('seating_plans')
              .add(examMap);
          savedId = docRef.id;
        } else {
          await FirebaseFirestore.instance
              .collection('seating_plans')
              .doc(savedId)
              .set(examMap, SetOptions(merge: true));
        }
      }

      // Gözetmen görevlendirmeleri manuel yayınlama butonuna basıldığında iletilecek.
      // Sınav kaydedildiğinde öğretmenlere otomatik düşmez (idareci kontrolünde yayınlanır).

      _currentDistribution = ExamDistribution.fromMap(_currentDistribution.toMap(), savedId);

      setState(() {
        _isDraft = false;
        _hasUnsavedChanges = false;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sınav oturumu ve oturma planları başarıyla kaydedildi!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      debugPrint('Kaydetme hatası: $e');
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydetme hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ===========================================================================
  // GÖZETMENLİK YAYINLAMA & YÖNERGE İŞLEMLERİ (MANUEL KONTROL)
  // ===========================================================================
  Future<void> _publishProctoringDuties() async {
    final savedId = _currentDistribution.id;
    if (savedId == null || savedId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen önce sınav oturumunu kaydedin.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
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
          'Gözetmenlik görevleri atanmış tüm öğretmenlerin görev takvimine işlenecek ve bildirim kutularına gönderilecektir. Öğretmenler kendi panellerinden sınav yönergesini inceleyip salonda yoklama alabileceklerdir.\n\nOnaylıyor musunuz?',
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

    if (confirmed != true) return;

    setState(() => _isPublishing = true);

    try {
      final slots = _currentDistribution.sessionSlots;
      int publishedCount = 0;

      for (final room in _currentDistribution.rooms) {
        if (room.supervisors.isNotEmpty) {
          for (final supEntry in room.supervisors) {
            final tId = supEntry['supervisorId']?.toString() ?? '';
            final tName = supEntry['supervisorName']?.toString() ?? '';
            final sIdx = (supEntry['slotIndex'] as int?) ?? 0;
            if (tId.isEmpty) continue;

            final slotInfo = (sIdx >= 0 && sIdx < slots.length) ? slots[sIdx] : null;
            final slotLabel = slotInfo?['label']?.toString() ?? '${sIdx + 1}. Oturum';
            final slotTime = (slotInfo != null && slotInfo['startTime'] != null)
                ? '${slotInfo['startTime']} - ${slotInfo['endTime']}'
                : _currentDistribution.examTime;

            final dutyTitle = 'Sınav Gözetmenliği: ${_currentDistribution.title} ($slotLabel)';

            // 1. Takvim Kaydı
            await FirebaseFirestore.instance.collection('dutyScheduleItems').add({
              'institutionId': widget.institutionId,
              'teacherId': tId,
              'teacherName': tName,
              'dutyTitle': dutyTitle,
              'locationName': room.classroomName,
              'dutyDate': Timestamp.fromDate(_currentDistribution.examDate),
              'dutyTime': slotTime,
              'examDistributionId': savedId,
              'roomId': room.id,
              'roomName': room.classroomName,
              'slotIndex': sIdx,
              'slotLabel': slotLabel,
              'instructions': _currentDistribution.instructions,
              'createdAt': Timestamp.now(),
              'attendanceCompleted': false,
            });

            // 2. Gözetmenlik Görevleri Sayfası Slotu
            await FirebaseFirestore.instance.collection('proctoringSlots').add({
              'institutionId': widget.institutionId,
              'teacherId': tId,
              'teacherName': tName,
              'examId': savedId,
              'examName': _currentDistribution.title,
              'className': room.classroomName,
              'roomId': room.id,
              'slotIndex': sIdx,
              'slotLabel': slotLabel,
              'startTime': slotInfo?['startTime']?.toString() ?? '',
              'endTime': slotInfo?['endTime']?.toString() ?? '',
              'examDate': Timestamp.fromDate(_currentDistribution.examDate),
              'isPublished': true,
              'instructions': _currentDistribution.instructions,
              'createdAt': Timestamp.now(),
            });

            // 3. Bildirim
            await FirebaseFirestore.instance.collection('notifications').add({
              'institutionId': widget.institutionId,
              'userId': tId,
              'title': 'Sınav Gözetmenlik Görevi',
              'body': '${DateFormat("dd.MM.yyyy").format(_currentDistribution.examDate)} $slotTime saatinde ${room.classroomName} salonunda $slotLabel gözetmenlik göreviniz bulunmaktadır.',
              'type': 'exam_supervisor_duty',
              'examDistributionId': savedId,
              'roomName': room.classroomName,
              'slotIndex': sIdx,
              'createdAt': Timestamp.now(),
              'isRead': false,
            });

            publishedCount++;
          }
        } else if (room.supervisorId != null && room.supervisorId!.isNotEmpty) {
          final tId = room.supervisorId!;
          final tName = room.supervisorName ?? '';

          await FirebaseFirestore.instance.collection('dutyScheduleItems').add({
            'institutionId': widget.institutionId,
            'teacherId': tId,
            'teacherName': tName,
            'dutyTitle': 'Sınav Gözetmenliği: ${_currentDistribution.title}',
            'locationName': room.classroomName,
            'dutyDate': Timestamp.fromDate(_currentDistribution.examDate),
            'dutyTime': _currentDistribution.examTime,
            'examDistributionId': savedId,
            'roomId': room.id,
            'roomName': room.classroomName,
            'slotIndex': 0,
            'instructions': _currentDistribution.instructions,
            'createdAt': Timestamp.now(),
            'attendanceCompleted': false,
          });

          await FirebaseFirestore.instance.collection('proctoringSlots').add({
            'institutionId': widget.institutionId,
            'teacherId': tId,
            'teacherName': tName,
            'examId': savedId,
            'examName': _currentDistribution.title,
            'className': room.classroomName,
            'roomId': room.id,
            'slotIndex': 0,
            'startTime': _currentDistribution.examTime,
            'endTime': '',
            'examDate': Timestamp.fromDate(_currentDistribution.examDate),
            'isPublished': true,
            'instructions': _currentDistribution.instructions,
            'createdAt': Timestamp.now(),
          });

          await FirebaseFirestore.instance.collection('notifications').add({
            'institutionId': widget.institutionId,
            'userId': tId,
            'title': 'Sınav Gözetmenlik Görevi',
            'body': '${DateFormat("dd.MM.yyyy").format(_currentDistribution.examDate)} ${_currentDistribution.examTime} tarihinde ${room.classroomName} salonunda gözetmenlik göreviniz bulunmaktadır.',
            'type': 'exam_supervisor_duty',
            'examDistributionId': savedId,
            'roomName': room.classroomName,
            'slotIndex': 0,
            'createdAt': Timestamp.now(),
            'isRead': false,
          });

          publishedCount++;
        }
      }

      await FirebaseFirestore.instance.collection('butterfly_exams').doc(savedId).update({
        'isProctoringPublished': true,
        'proctoringPublishedAt': Timestamp.now(),
      });

      final updatedMap = _currentDistribution.toMap();
      updatedMap['isProctoringPublished'] = true;
      _currentDistribution = ExamDistribution.fromMap(updatedMap, savedId);

      setState(() => _isPublishing = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Toplam $publishedCount gözetmenlik görevi yayınlandı ve öğretmenlere bildirildi!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      debugPrint('Gözetmenlik yayınlama hatası: $e');
      setState(() => _isPublishing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yayınlama hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _unpublishProctoringDuties() async {
    final savedId = _currentDistribution.id;
    if (savedId == null || savedId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Gözetmenlikleri Yayından Kaldır'),
        content: const Text(
          'Gözetmenlik görevleri öğretmenlerin takvim ve panelinden kaldırılacaktır. Onaylıyor musunuz?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yayından Kaldır'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isPublishing = true);

    try {
      final dutySnaps = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('examDistributionId', isEqualTo: savedId)
          .get();
      for (final doc in dutySnaps.docs) {
        await doc.reference.delete();
      }

      final procSnaps = await FirebaseFirestore.instance
          .collection('proctoringSlots')
          .where('examId', isEqualTo: savedId)
          .get();
      for (final doc in procSnaps.docs) {
        await doc.reference.delete();
      }

      await FirebaseFirestore.instance.collection('butterfly_exams').doc(savedId).update({
        'isProctoringPublished': false,
      });

      final updatedMap = _currentDistribution.toMap();
      updatedMap['isProctoringPublished'] = false;
      _currentDistribution = ExamDistribution.fromMap(updatedMap, savedId);

      setState(() => _isPublishing = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gözetmenlik görevleri yayından kaldırıldı.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Yayından kaldırma hatası: $e');
      setState(() => _isPublishing = false);
    }
  }

  void _showExamInstructionsModal() {
    final rules = _currentDistribution.instructions;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.70,
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
                            'Gözetmen öğretmenlerin ve öğrencilerin uyması gereken kurallar',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
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
              Expanded(
                child: rules.isEmpty
                    ? Center(
                        child: Text(
                          'Bu sınav için özel yönerge maddesi belirlenmemiş.',
                          style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: rules.length,
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
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${idx + 1}',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12, color: const Color(0xFF4F46E5)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    rules[idx],
                                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1E293B), height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // PDF YAZDIRMA İŞLEVLERİ (TÜM LİSTELER & KROKİLER)
  // ===========================================================================
  Future<void> _printRoomGateList(ExamRoom room) async {
    try {
      final bytes = await ButterflyPdfService.generateGateListPdf(
        distribution: _currentDistribution,
        room: room,
      );
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${_currentDistribution.title}_${room.classroomName}_Kapi_Listesi.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printRoomAttendanceList(ExamRoom room) async {
    try {
      final bytes = await ButterflyPdfService.generateAttendanceListPdf(
        distribution: _currentDistribution,
        room: room,
      );
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${_currentDistribution.title}_${room.classroomName}_Yoklama_Listesi.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printRoomSupervisorPlan(ExamRoom room) async {
    try {
      final bytes = await ButterflyPdfService.generateSupervisorSeatingPlanPdf(
        distribution: _currentDistribution,
        room: room,
      );
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${_currentDistribution.title}_${room.classroomName}_Gozetmen_Krokisi.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printRoomObservationForm(ExamRoom room) async {
    try {
      final bytes = await ButterflyPdfService.generateObservationFormPdf(
        distribution: _currentDistribution,
        room: room,
      );
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${_currentDistribution.title}_${room.classroomName}_Gozlem_Formu.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printFullExamPackage() async {
    try {
      final bytes = await ButterflyPdfService.generateFullExamPackagePdf(
        distribution: _currentDistribution,
      );
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${_currentDistribution.title}_Tum_Sinav_Paketi.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printAllObservationForms() async {
    try {
      final bytes = await ButterflyPdfService.generateAllObservationFormsPdf(
        distribution: _currentDistribution,
      );
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${_currentDistribution.title}_Tum_Gozlem_Formlari.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printAllGateLists() async {
    try {
      final bytes = await ButterflyPdfService.generateAllGateListsPdf(
        distribution: _currentDistribution,
      );
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${_currentDistribution.title}_Tum_Kapi_Listeleri.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printAllAttendanceLists() async {
    try {
      final bytes = await ButterflyPdfService.generateAllAttendanceListsPdf(
        distribution: _currentDistribution,
      );
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${_currentDistribution.title}_Tum_Yoklama_Listeleri.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printAllSupervisorPlans() async {
    try {
      final bytes = await ButterflyPdfService.generateAllSupervisorPlansPdf(
        distribution: _currentDistribution,
      );
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${_currentDistribution.title}_Tum_Gozetmen_Krokileri.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printMasterAlphabeticalList() async {
    try {
      final bytes = await ButterflyPdfService.generateMasterAlphabeticalListPdf(
        distribution: _currentDistribution,
      );
      await Printing.layoutPdf(
        onLayout: (_) => bytes,
        name: '${_currentDistribution.title}_Genel_Alfabetik_Yerlesim_Listesi.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
