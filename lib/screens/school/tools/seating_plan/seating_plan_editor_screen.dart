import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../../models/school/seating_plan_model.dart';
import '../../../../models/class_model.dart';
import '../../../../services/seating_distribution_service.dart';
import '../../../../services/seating_pdf_service.dart';
import '../../../../widgets/edukn_app_bar.dart';
import 'classroom_layout_editor_screen.dart';

class SeatingPlanEditorScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final SeatingPlan? existingPlan;
  final String? initialClassId;
  final List<String>? allowedClassIds;

  const SeatingPlanEditorScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.existingPlan,
    this.initialClassId,
    this.allowedClassIds,
  }) : super(key: key);

  @override
  State<SeatingPlanEditorScreen> createState() =>
      _SeatingPlanEditorScreenState();
}

class _SeatingPlanEditorScreenState extends State<SeatingPlanEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _notesController;

  DateTime _planDate = DateTime.now();
  String? _selectedClassId;
  String? _selectedClassName;
  String? _selectedLayoutId;

  List<ClassModel> _classes = [];
  List<ClassroomLayout> _layouts = [];
  List<SeatingStudentItem> _allStudents = [];
  List<DeskCell> _cells = [];
  List<SeatingPlan> _historicalPlans = [];

  bool _isLoading = true;
  bool _isLoadingStudents = false;
  bool _isSaving = false;
  bool _isDistributing = false;
  bool _hasChanges = false;

  DistributionOptions _distributionOptions = const DistributionOptions();
  double? _lastPenaltyScore;
  String _studentSearchQuery = '';
  String _studentFilterMode = 'all'; // 'all', 'unassigned', 'assigned'

  // Dokunarak yerleştirme için seçili öğrenci
  SeatingStudentItem? _selectedStudentForPlacement;

  // Öğrenci Oturma Kriterleri & Kısıtlamaları (Birlikte oturmama, sıra tercihi)
  Map<String, StudentSeatingConstraint> _studentConstraints = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final defaultTitle =
        '${now.year}-${now.year + 1} Sınıf Oturma Planı (${DateFormat('dd.MM.yyyy').format(now)})';

    _titleController = TextEditingController(
      text: widget.existingPlan?.title ?? defaultTitle,
    );
    _notesController = TextEditingController(
      text: widget.existingPlan?.notes ?? '',
    );

    if (widget.existingPlan != null) {
      _planDate = widget.existingPlan!.planDate;
      _selectedClassId = widget.existingPlan!.classId;
      _selectedClassName = widget.existingPlan!.className;
      _selectedLayoutId = widget.existingPlan!.layoutId;
      _cells = widget.existingPlan!.cells.map((c) => c.clone()).toList();
      _lastPenaltyScore = widget.existingPlan!.penaltyScore;
      _studentConstraints = widget.existingPlan!.studentConstraints.map(
        (k, v) => MapEntry(k, v.clone()),
      );
    } else if (widget.initialClassId != null) {
      _selectedClassId = widget.initialClassId;
    }

    _initialLoad();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _initialLoad() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadClasses(),
      _loadLayouts(),
    ]);

    if (_selectedClassId != null) {
      await _loadStudentsForClass(_selectedClassId!);
      await _loadHistoricalPlans(_selectedClassId!);
    } else if (_classes.isNotEmpty && _classes.first.id != null) {
      final firstClass = _classes.first;
      setState(() {
        _selectedClassId = firstClass.id;
        _selectedClassName = firstClass.className;
      });
      await _loadStudentsForClass(firstClass.id!);
      await _loadHistoricalPlans(firstClass.id!);
    }

    // Şablon seçimi
    if (_selectedLayoutId == null && _layouts.isNotEmpty) {
      _applyLayout(_layouts.first);
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadClasses() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      var list = snap.docs
          .map((d) => ClassModel.fromMap(d.data(), d.id))
          .where((c) =>
              c.schoolTypeId == widget.schoolTypeId || c.schoolTypeId.isEmpty)
          .toList();

      if (widget.allowedClassIds != null) {
        list = list.where((c) => widget.allowedClassIds!.contains(c.id)).toList();
      }

      list.sort((a, b) => a.className.compareTo(b.className));

      if (mounted) {
        setState(() {
          _classes = list;
        });
      }
    } catch (e) {
      debugPrint('Sınıf yükleme hatası: $e');
    }
  }

  Future<void> _loadLayouts() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('seating_layouts')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final list = snap.docs
          .map((d) => ClassroomLayout.fromMap(d.data(), d.id))
          .where((l) =>
              l.schoolTypeId == widget.schoolTypeId || l.schoolTypeId.isEmpty)
          .toList();

      if (mounted) {
        setState(() {
          _layouts = list;
          if (_layouts.isEmpty) {
            // Hiç şablon yoksa varsayılan 4x3 şablonu oluştur
            final defaultL = ClassroomLayout.createPreset(
              name: 'Standart Sınıf Düzeni (24 Kişi)',
              institutionId: widget.institutionId,
              schoolTypeId: widget.schoolTypeId,
              presetType: '3_col_double',
            );
            _layouts.add(defaultL);
          }
        });
      }
    } catch (e) {
      debugPrint('Şablon yükleme hatası: $e');
    }
  }

  Future<void> _loadStudentsForClass(String classId) async {
    setState(() => _isLoadingStudents = true);
    try {
      final matchingClass = _classes.where((c) => c.id == classId).toList();
      final className = matchingClass.isNotEmpty ? matchingClass.first.className : '';

      // 1. Query by classId & institutionId
      var snap = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('classId', isEqualTo: classId)
          .get();

      // Fallback: only by classId
      if (snap.docs.isEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('students')
            .where('classId', isEqualTo: classId)
            .get();
      }

      // 2. Fallback: by className if needed
      if (snap.docs.isEmpty && className.isNotEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('className', isEqualTo: className)
            .get();

        if (snap.docs.isEmpty) {
          snap = await FirebaseFirestore.instance
              .collection('students')
              .where('className', isEqualTo: className)
              .get();
        }
      }

      final list = snap.docs.map((d) {
        final data = d.data();
        final firstName = (data['firstName'] ?? data['name'] ?? '').toString();
        final lastName = (data['lastName'] ?? data['surname'] ?? '').toString();
        final fullName = (data['fullName'] != null && data['fullName'].toString().trim().isNotEmpty)
            ? data['fullName'].toString().trim()
            : '$firstName $lastName'.trim().isEmpty
                ? 'Öğrenci'
                : '$firstName $lastName'.trim();

        return SeatingStudentItem(
          id: d.id,
          fullName: fullName,
          studentNumber: (data['studentNumber'] ?? data['number'] ?? data['no'] ?? '').toString(),
          gender: data['gender']?.toString(),
          photoUrl: data['photoUrl']?.toString(),
        );
      }).where((s) => s.fullName.isNotEmpty).toList();

      list.sort((a, b) => a.fullName.compareTo(b.fullName));

      if (mounted) {
        setState(() {
          _allStudents = list;
          _isLoadingStudents = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingStudents = false);
      debugPrint('Öğrenci yükleme hatası: $e');
    }
  }

  Future<void> _loadHistoricalPlans(String classId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('seating_plans')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('classId', isEqualTo: classId)
          .get();

      final list = snap.docs
          .map((d) => SeatingPlan.fromMap(d.data(), d.id))
          .where((p) => p.id != widget.existingPlan?.id)
          .toList();

      list.sort((a, b) => b.planDate.compareTo(a.planDate));
      final recentList = list.take(5).toList();

      if (mounted) {
        setState(() {
          _historicalPlans = recentList;
        });
      }
    } catch (e) {
      debugPrint('Geçmiş plan yükleme hatası: $e');
    }
  }

  void _applyLayout(ClassroomLayout layout) {
    setState(() {
      _selectedLayoutId = layout.id;
      _cells = layout.cells.map((c) => c.clone()).toList();
      _hasChanges = true;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _planDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('tr', 'TR'),
    );
    if (picked != null) {
      setState(() {
        _planDate = picked;
        _hasChanges = true;
      });
    }
  }

  /// Öğrenciyi koltuğa yerleştir
  void _assignStudentToSlot(DeskCell cell, SeatSlot slot, SeatingStudentItem student) {
    setState(() {
      // Önce bu öğrencinin başka bir masada olup olmadığını kontrol et ve kaldır
      for (var c in _cells) {
        for (var s in c.slots) {
          if (s.studentId == student.id) {
            s.studentId = null;
            s.studentName = null;
            s.studentNumber = null;
            s.gender = null;
            s.photoUrl = null;
            s.isPinned = false;
          }
        }
      }

      slot.studentId = student.id;
      slot.studentName = student.fullName;
      slot.studentNumber = student.studentNumber;
      slot.gender = student.gender;
      slot.photoUrl = student.photoUrl;
      _selectedStudentForPlacement = null;
      _hasChanges = true;
    });
  }

  /// Henüz hiçbir koltuğa oturmamış öğrencileri filtreler
  List<SeatingStudentItem> get _unassignedStudents {
    final Set<String> assignedIds = {};
    for (var cell in _cells) {
      if (!cell.isDesk) continue;
      for (var slot in cell.slots) {
        if (slot.isOccupied) {
          assignedIds.add(slot.studentId!);
        }
      }
    }

    var list = _allStudents.where((s) => !assignedIds.contains(s.id)).toList();
    if (_studentSearchQuery.isNotEmpty) {
      final q = _studentSearchQuery.toLowerCase();
      list = list.where((s) =>
          s.fullName.toLowerCase().contains(q) ||
          (s.studentNumber != null && s.studentNumber!.contains(q))).toList();
    }
    return list;
  }

  /// Koltuğu boşalt
  void _clearSlot(SeatSlot slot) {
    setState(() {
      slot.studentId = null;
      slot.studentName = null;
      slot.studentNumber = null;
      slot.gender = null;
      slot.photoUrl = null;
      slot.isPinned = false;
      _hasChanges = true;
    });
  }

  /// Koltuktaki öğrenciyi sabitle / kaldır (Pin / Unpin)
  void _togglePin(SeatSlot slot) {
    if (!slot.isOccupied) return;
    setState(() {
      slot.isPinned = !slot.isPinned;
      _hasChanges = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          slot.isPinned
              ? '📌 ${slot.studentName} bu masaya sabitlendi! Dağıtımlarda yeri korunacak.'
              : '🔓 ${slot.studentName} için sabitleme kaldırıldı.',
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: slot.isPinned ? const Color(0xFFE65100) : const Color(0xFF5C6BC0),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Akıllı Dağıtım Algoritmasını Çalıştır
  Future<void> _runSmartDistribution() async {
    if (_allStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sınıfta kayıtlı öğrenci bulunamadı!')),
      );
      return;
    }

    setState(() => _isDistributing = true);

    // Hafif animasyon hissi
    await Future.delayed(const Duration(milliseconds: 300));

    final service = SeatingDistributionService();
    final result = service.distributeStudents(
      currentCells: _cells,
      allStudents: _allStudents,
      historicalPlans: _historicalPlans,
      options: _distributionOptions,
      studentConstraints: _studentConstraints,
    );

    setState(() {
      _cells = result.updatedCells;
      _lastPenaltyScore = result.totalPenalty;
      _isDistributing = false;
      _hasChanges = true;
    });

    _showDistributionSummaryDialog(result);
  }

  void _showDistributionSummaryDialog(DistributionResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF2E7D32), size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Akıllı Dağıtım Tamamlandı', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17, color: const Color(0xFF1E293B))),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildDialogStatRow('Yerleştirilen Öğrenci', '${result.assignedCount} / ${_allStudents.length}'),
              _buildDialogStatRow('Sabit Kalan (Pinli)', '${result.pinnedCount} Öğrenci'),
              _buildDialogStatRow('Taranan Geçmiş Plan', '${_historicalPlans.length} Adet'),
              if (_studentConstraints.isNotEmpty)
                _buildDialogStatRow('Özel Kural Uygulanan', '${_studentConstraints.length} Öğrenci'),
              _buildDialogStatRow(
                'Uyum Skoru (Ceza)',
                result.totalPenalty == 0
                    ? '0.0 (Mükemmel Uyum)'
                    : result.totalPenalty < 30
                        ? '${result.totalPenalty.toStringAsFixed(1)} (Çok İyi)'
                        : '${result.totalPenalty.toStringAsFixed(1)} (Düşük Ceza = İyi)',
                color: result.totalPenalty < 50 ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text('Algoritma Notları:', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF334155))),
              const SizedBox(height: 4),
              ...result.logs.take(4).map((log) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('• $log', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade700)),
                  )),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Harika, Tamam'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDialogStatRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(label, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade700)),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: color ?? const Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tüm koltukları boşalt (Sabitleri koruyarak veya tümü)
  void _clearAllSeats({bool keepPinned = true}) {
    setState(() {
      for (var cell in _cells) {
        for (var slot in cell.slots) {
          if (!keepPinned || !slot.isPinned) {
            slot.studentId = null;
            slot.studentName = null;
            slot.studentNumber = null;
            slot.gender = null;
            slot.photoUrl = null;
            if (!keepPinned) slot.isPinned = false;
          }
        }
      }
    });
  }

  /// Planı Kaydet
  Future<void> _savePlan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir şube seçin!')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final plan = SeatingPlan(
        id: widget.existingPlan?.id,
        title: _titleController.text.trim(),
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        classId: _selectedClassId!,
        className: _selectedClassName ?? '',
        layoutId: _selectedLayoutId,
        planDate: _planDate,
        cells: _cells,
        createdAt: widget.existingPlan?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        penaltyScore: _lastPenaltyScore,
        studentConstraints: _studentConstraints,
      );

      final colRef = FirebaseFirestore.instance
          .collection('seating_plans');

      if (plan.id != null) {
        await colRef.doc(plan.id).update(plan.toMap());
      } else {
        await colRef.add(plan.toMap());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sınıf oturma planı başarıyla kaydedildi!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıt hatası: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// PDF Önizleme & Yazdırma
  Future<void> _printOrExportPdf() async {
    final plan = SeatingPlan(
      title: _titleController.text.trim(),
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
      schoolTypeName: widget.schoolTypeName,
      classId: _selectedClassId ?? '',
      className: _selectedClassName ?? '',
      planDate: _planDate,
      cells: _cells,
      createdAt: DateTime.now(),
    );

    final pdfBytes = await SeatingPdfService.generateSeatingPlanPdf(plan: plan);
    await Printing.layoutPdf(onLayout: (_) => pdfBytes);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1024;

    final Set<String> assignedIds = {};
    int occupiedSeats = 0;
    for (var cell in _cells) {
      if (!cell.isDesk) continue;
      for (var slot in cell.slots) {
        if (slot.isOccupied) {
          assignedIds.add(slot.studentId!);
          occupiedSeats++;
        }
      }
    }
    final unassignedCount = _allStudents.where((s) => !assignedIds.contains(s.id)).length;
    final showSaveButton = _hasChanges || (widget.existingPlan != null && occupiedSeats > 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: EduknAppBar(
        title: widget.existingPlan == null ? 'Sınıf Oturma Planı Oluştur' : 'Oturma Planını Düzenle',
        subtitle: widget.schoolTypeName,
        actions: [
          // 3 Nokta Popup Menüsü (Yazdır & Dağıtım Ayarları)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.indigo, size: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            tooltip: 'Seçenekler',
            onSelected: (val) {
              if (val == 'print') {
                _printOrExportPdf();
              } else if (val == 'settings') {
                _showDistributionOptionsDialog();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'print',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5C6BC0).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.print_rounded, size: 18, color: Color(0xFF5C6BC0)),
                    ),
                    const SizedBox(width: 10),
                    Text('Yazdır / PDF İndir', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5C6BC0).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.tune_rounded, size: 18, color: Color(0xFF5C6BC0)),
                    ),
                    const SizedBox(width: 10),
                    Text('Dağıtım Ayarları', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          if (isDesktop && showSaveButton)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                ),
                onPressed: _isSaving ? null : _savePlan,
                icon: _isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(_isSaving ? 'Kaydediliyor...' : 'Kaydet', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    // Öğrenci Tepsisini Aç Butonu (Değişiklik yokken tam genişlik, değişiklik varken flex: 3)
                    Expanded(
                      flex: showSaveButton ? 3 : 1,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5C6BC0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: _showStudentListBottomSheet,
                        icon: const Icon(Icons.people_alt_rounded, size: 18),
                        label: Text(
                          'Öğrenciler ($unassignedCount Boşta)',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                      ),
                    ),

                    // Dağıtım veya Değişiklik Yapıldığında Görünen Kaydet Butonu
                    if (showSaveButton) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 1,
                          ),
                          onPressed: _isSaving ? null : _savePlan,
                          icon: _isSaving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.save_rounded, size: 18),
                          label: Text(
                            _isSaving ? '...' : 'Kaydet',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sol: Ana Oturma Tahtası & Ayarlar
                    Expanded(
                      flex: 7,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            _buildPlanHeaderCard(),
                            const SizedBox(height: 16),
                            _buildSeatingBoardCard(),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),

                    // Sağ: Öğrenci Listesi Paneli (Unassigned Tray)
                    Container(
                      width: 340,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(left: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: _buildStudentSidebar(),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _buildPlanHeaderCard(),
                      const SizedBox(height: 14),
                      _buildSeatingBoardCard(),
                      const SizedBox(height: 90),
                    ],
                  ),
                ),
    );
  }

  void _showStudentListBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDrawerState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SafeArea(
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: _buildStudentSidebar(
                    onStudentSelected: (st) {
                      Navigator.pop(ctx);
                      setState(() {
                        _selectedStudentForPlacement = st;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('👉 "${st.fullName}" seçildi. Oturtmak istediğiniz masaya dokunun.'),
                          duration: const Duration(seconds: 4),
                          backgroundColor: const Color(0xFF5C6BC0),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanHeaderCard() {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E293B).withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Plan Başlığı
            TextFormField(
              controller: _titleController,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
              decoration: InputDecoration(
                labelText: 'Plan Başlığı *',
                labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                hintText: 'Örn: 1. Dönem Oturma Planı',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                prefixIcon: const Icon(Icons.title_rounded, color: Color(0xFF5C6BC0), size: 20),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Lütfen başlık girin' : null,
            ),
            const SizedBox(height: 12),

            // Şube ve Tarih
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 420) {
                  return Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedClassId,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Şube *',
                          labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          prefixIcon: const Icon(Icons.groups_rounded, color: Color(0xFF5C6BC0), size: 18),
                        ),
                        items: _classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.className, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)))).toList(),
                        onChanged: (val) {
                          if (val == null || val == _selectedClassId) return;
                          setState(() {
                            _selectedClassId = val;
                            final match = _classes.where((c) => c.id == val).toList();
                            _selectedClassName = match.isNotEmpty ? match.first.className : '';
                            _hasChanges = true;
                          });
                          _loadStudentsForClass(val);
                          _loadHistoricalPlans(val);
                        },
                      ),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF5C6BC0)),
                              const SizedBox(width: 8),
                              Text(
                                'Tarih: ${DateFormat('dd.MM.yyyy').format(_planDate)}',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: _selectedClassId,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Şube *',
                          labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          prefixIcon: const Icon(Icons.groups_rounded, color: Color(0xFF5C6BC0), size: 18),
                        ),
                        items: _classes.map((c) => DropdownMenuItem(value: c.id, child: Text(c.className, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)))).toList(),
                        onChanged: (val) {
                          if (val == null || val == _selectedClassId) return;
                          setState(() {
                            _selectedClassId = val;
                            final match = _classes.where((c) => c.id == val).toList();
                            _selectedClassName = match.isNotEmpty ? match.first.className : '';
                            _hasChanges = true;
                          });
                          _loadStudentsForClass(val);
                          _loadHistoricalPlans(val);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF5C6BC0)),
                            const SizedBox(width: 6),
                            Text(
                              DateFormat('dd.MM.yyyy').format(_planDate),
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5, color: const Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),

            // Şablon Seçimi & Yeni Şablon Butonu
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) {
                  return Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _layouts.any((l) => l.id == _selectedLayoutId) ? _selectedLayoutId : null,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Derslik Masa Şablonu',
                          labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          prefixIcon: const Icon(Icons.grid_4x4_rounded, color: Color(0xFF5C6BC0), size: 18),
                        ),
                        items: [
                          ..._layouts.map((l) => DropdownMenuItem(
                                value: l.id,
                                child: Text('${l.name} (${l.totalCapacity} Kişi)', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                              )),
                        ],
                        onChanged: (val) {
                          final layout = _layouts.firstWhere((l) => l.id == val);
                          _applyLayout(layout);
                        },
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4338CA),
                            side: const BorderSide(color: Color(0xFFC7D2FE)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            final updated = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ClassroomLayoutEditorScreen(
                                  institutionId: widget.institutionId,
                                  schoolTypeId: widget.schoolTypeId,
                                  schoolTypeName: widget.schoolTypeName,
                                ),
                              ),
                            );
                            if (updated == true) _loadLayouts();
                          },
                          icon: const Icon(Icons.design_services_rounded, size: 16),
                          label: Text('Yeni Şablon Tasarla', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
                        ),
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _layouts.any((l) => l.id == _selectedLayoutId) ? _selectedLayoutId : null,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Derslik Masa Şablonu',
                          labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          prefixIcon: const Icon(Icons.grid_4x4_rounded, color: Color(0xFF5C6BC0), size: 18),
                        ),
                        items: [
                          ..._layouts.map((l) => DropdownMenuItem(
                                value: l.id,
                                child: Text('${l.name} (${l.totalCapacity} Kişilik)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                              )),
                        ],
                        onChanged: (val) {
                          final layout = _layouts.firstWhere((l) => l.id == val);
                          _applyLayout(layout);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEEF2FF),
                        foregroundColor: const Color(0xFF4338CA),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Color(0xFFC7D2FE)),
                        ),
                      ),
                      onPressed: () async {
                        final updated = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClassroomLayoutEditorScreen(
                              institutionId: widget.institutionId,
                              schoolTypeId: widget.schoolTypeId,
                              schoolTypeName: widget.schoolTypeName,
                            ),
                          ),
                        );
                        if (updated == true) _loadLayouts();
                      },
                      icon: const Icon(Icons.design_services_rounded, size: 18),
                      label: Text('Yeni Şablon Tasarla', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeatingBoardCard() {
    int totalSeats = 0;
    int occupiedSeats = 0;
    int pinnedCount = 0;

    for (var cell in _cells) {
      if (cell.isDesk) {
        totalSeats += cell.capacity;
        for (var s in cell.slots) {
          if (s.isOccupied) {
            occupiedSeats++;
            if (s.isPinned) pinnedCount++;
          }
        }
      }
    }

    // Koordinat Map'i
    int maxR = 0;
    int maxC = 0;
    final Map<String, DeskCell> cellMap = {};
    for (var c in _cells) {
      if (c.row > maxR) maxR = c.row;
      if (c.col > maxC) maxC = c.col;
      cellMap['${c.row}-${c.col}'] = c;
    }
    final rowsCount = maxR + 1;
    final colsCount = maxC + 1;

    final isMobile = MediaQuery.of(context).size.width < 768;
    final hasOccupied = occupiedSeats > 0;

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Action Buttons Bar (Tekli Dinamik Dağıt/Karıştır Butonu + Temizleme Menüsü)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Akıllı Dağıt / Karıştır Dinamik Butonu
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasOccupied ? const Color(0xFF1E88E5) : const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                ),
                onPressed: _isDistributing ? null : _runSmartDistribution,
                icon: _isDistributing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Icon(hasOccupied ? Icons.shuffle_rounded : Icons.auto_awesome_rounded, size: 16),
                label: Text(
                  hasOccupied
                      ? (isMobile ? 'Karıştır' : 'Karıştır (Yeniden Dağıt)')
                      : (isMobile ? 'Akıllı Dağıt' : 'Akıllı Dağıt (Geçmişe Duyarlı)'),
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
              ),

              // Temizleme Menüsü
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (val) {
                  if (val == 'clear_unpinned') {
                    _clearAllSeats(keepPinned: true);
                  } else if (val == 'clear_all') {
                    _clearAllSeats(keepPinned: false);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'clear_unpinned',
                    child: Row(
                      children: [
                        Icon(Icons.cleaning_services_rounded, size: 18, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('Sabitler Hariç Koltukları Boşalt'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear_all',
                    child: Row(
                      children: [
                        Icon(Icons.delete_sweep_rounded, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Tüm Koltukları ve Sabitleri Boşalt'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Status & Stats bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F6FA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Yerleşen: ', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600)),
                    Text('$occupiedSeats / $totalSeats',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A2E))),
                    const SizedBox(width: 10),
                    Text('Sabit: ', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600)),
                    Text('$pinnedCount',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFFE65100))),
                  ],
                ),
                if (_lastPenaltyScore != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _lastPenaltyScore! < 50 ? Colors.green.shade100 : Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Ceza: ${_lastPenaltyScore!.toStringAsFixed(1)}',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _lastPenaltyScore! < 50 ? Colors.green.shade900 : Colors.amber.shade900,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Selected Student Banner for Click-to-Place
          if (_selectedStudentForPlacement != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE7F6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF7E57C2), width: 1.2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.touch_app_rounded, color: Color(0xFF7E57C2), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Seçili: "${_selectedStudentForPlacement!.fullName}" — Boş masaya dokunun.',
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFF4A148C)),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _selectedStudentForPlacement = null),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16, color: Color(0xFF4A148C)),
                    ),
                  ),
                ],
              ),
            ),

          // Blackboard Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF263238), Color(0xFF37474F)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                'TAHTA / ÖĞRETMEN KÜRSÜSÜ',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                  letterSpacing: 1.8,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Horizontal scroll hint for mobile if multiple columns
          if (colsCount > 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swipe_left_rounded, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    'Masaları görmek için sağa / sola kaydırın',
                    style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.swipe_right_rounded, size: 14, color: Colors.grey.shade500),
                ],
              ),
            ),

          // Seating Grid - wrapped in horizontal scroll with fixed comfortable desk width (125-135px)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int r = 0; r < rowsCount; r++) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Row Label
                        Container(
                          width: 36,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${r + 1}. Sıra',
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                          ),
                        ),
                        const SizedBox(width: 4),

                        // Cells
                        for (int c = 0; c < colsCount; c++) ...[
                          SizedBox(
                            width: isMobile ? 122 : 135,
                            child: _buildDeskCellWidget(cellMap['$r-$c']),
                          ),
                          if (c < colsCount - 1) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    if (r < rowsCount - 1) const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addAvoidPair(String studentIdA, String studentIdB) {
    final sA = _allStudents.firstWhere(
      (s) => s.id == studentIdA,
      orElse: () => SeatingStudentItem(id: studentIdA, fullName: 'Öğrenci'),
    );
    final sB = _allStudents.firstWhere(
      (s) => s.id == studentIdB,
      orElse: () => SeatingStudentItem(id: studentIdB, fullName: 'Öğrenci'),
    );

    final cA = _studentConstraints.putIfAbsent(
      studentIdA,
      () => StudentSeatingConstraint(studentId: studentIdA, studentName: sA.fullName),
    );
    cA.avoidStudentIds.add(studentIdB);

    // Çift yönlü ekle
    final cB = _studentConstraints.putIfAbsent(
      studentIdB,
      () => StudentSeatingConstraint(studentId: studentIdB, studentName: sB.fullName),
    );
    cB.avoidStudentIds.add(studentIdA);
  }

  void _removeAvoidPair(String studentIdA, String studentIdB) {
    _studentConstraints[studentIdA]?.avoidStudentIds.remove(studentIdB);
    _studentConstraints[studentIdB]?.avoidStudentIds.remove(studentIdA);
  }

  Widget _buildDeskCellWidget(DeskCell? cell) {
    if (cell == null || cell.isAisle) {
      return Container(
        height: 90,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Center(
          child: Text('· · ·', style: GoogleFonts.inter(color: const Color(0xFFCBD5E1), fontSize: 16)),
        ),
      );
    }

    return Container(
      height: 94,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Desk Label
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  cell.customLabel ?? 'Masa ${cell.row + 1}-${cell.col + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),

          // Seat Slots
          Expanded(
            child: Row(
              children: cell.slots.map((slot) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _buildSeatSlotWidget(cell, slot),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeatSlotWidget(DeskCell cell, SeatSlot slot) {
    if (!slot.isOccupied) {
      final isSelectedForThis = _selectedStudentForPlacement != null;
      return InkWell(
        onTap: () {
          if (_selectedStudentForPlacement != null) {
            _assignStudentToSlot(cell, slot, _selectedStudentForPlacement!);
          } else {
            _showSeatAssignmentDialog(cell, slot);
          }
        },
        borderRadius: BorderRadius.circular(9),
        child: Container(
          decoration: BoxDecoration(
            color: isSelectedForThis ? const Color(0xFFEEF2FF) : Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isSelectedForThis ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
              width: isSelectedForThis ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelectedForThis ? Icons.touch_app_rounded : Icons.add_rounded,
                  size: 12,
                  color: isSelectedForThis ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    isSelectedForThis ? 'Otur' : 'Boş',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: isSelectedForThis ? FontWeight.bold : FontWeight.w600,
                      color: isSelectedForThis ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Occupied Slot
    final constraint = _studentConstraints[slot.studentId];
    final hasCriteria = constraint != null &&
        (constraint.avoidStudentIds.isNotEmpty ||
            constraint.isFrontRowRequired ||
            constraint.rowZonePreference != RowZonePreference.any);

    // Cinsiyet kontrolü (Kız -> Belirgin Canlı Pastel Pembe / Erkek -> Mavi / Belirtilmemiş -> Nötr Temiz Beyaz)
    final genderStr = (slot.gender ?? '').trim().toLowerCase();
    final isGirl = genderStr.startsWith('k') || genderStr.startsWith('f') || genderStr == 'kadın' || genderStr == 'kız' || genderStr == 'girl' || genderStr == 'female';
    final isBoy = genderStr.startsWith('e') || genderStr.startsWith('m') || genderStr == 'erkek' || genderStr == 'boy' || genderStr == 'male';

    final Color bgColor;
    final Color borderColor;
    final Color numberBgColor;
    final Color numberTextColor;
    final Color nameTextColor;

    if (slot.isPinned) {
      bgColor = const Color(0xFFFFFBEB);
      borderColor = const Color(0xFFF59E0B);
      numberBgColor = const Color(0xFFFEF3C7);
      numberTextColor = const Color(0xFFD97706);
      nameTextColor = const Color(0xFF92400E);
    } else if (isGirl) {
      bgColor = const Color(0xFFFDF2F8); // Net ve Çok Tatlı Pastel Pembe
      borderColor = const Color(0xFFF472B6); // Belirgin Pembe Çerçeve
      numberBgColor = const Color(0xFFFCE7F3); // Pembe Numara Rozet Arka Planı
      numberTextColor = const Color(0xFFDB2777); // Canlı Pembe Numara
      nameTextColor = const Color(0xFF9D174D); // Okunaklı Koyu Pembe/Magenta İsim
    } else if (isBoy) {
      bgColor = const Color(0xFFEFF6FF); // Pastel Mavi
      borderColor = const Color(0xFF93C5FD); // Mavi Çerçeve
      numberBgColor = const Color(0xFFDBEAFE);
      numberTextColor = const Color(0xFF2563EB); // Koyu Mavi Numara
      nameTextColor = const Color(0xFF1E3A8A); // Okunaklı Koyu Lacivert İsim
    } else {
      // Cinsiyet belirtilmemiş veya boşsa nötr tema
      bgColor = Colors.white;
      borderColor = const Color(0xFFCBD5E1);
      numberBgColor = const Color(0xFFF1F5F9);
      numberTextColor = const Color(0xFF475569);
      nameTextColor = const Color(0xFF1E293B);
    }

    return InkWell(
      onTap: () => _showOccupiedSeatActionsDialog(cell, slot),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: borderColor,
            width: slot.isPinned ? 1.6 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Üst Rozet Satırı: Numara + Kriter + Pin
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasCriteria) ...[
                  const Icon(Icons.tune_rounded, size: 8.5, color: Color(0xFFD97706)),
                  const SizedBox(width: 2),
                ],
                if (slot.studentNumber != null && slot.studentNumber!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                    decoration: BoxDecoration(
                      color: numberBgColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#${slot.studentNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: numberTextColor,
                      ),
                    ),
                  ),
                if (slot.isPinned) ...[
                  const SizedBox(width: 2),
                  const Icon(Icons.push_pin_rounded, size: 9.5, color: Color(0xFFD97706)),
                ],
              ],
            ),
            const SizedBox(height: 2),

            // Ortalı Öğrenci Adı Soyadı
            Text(
              slot.studentName ?? '',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 9.2,
                fontWeight: FontWeight.w700,
                color: nameTextColor,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOccupiedSeatActionsDialog(DeskCell cell, SeatSlot slot) {
    final student = _allStudents.firstWhere(
      (s) => s.id == slot.studentId,
      orElse: () => SeatingStudentItem(
        id: slot.studentId ?? '',
        fullName: slot.studentName ?? 'Öğrenci',
        studentNumber: slot.studentNumber,
        gender: slot.gender,
      ),
    );

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: ((student.gender ?? '').toLowerCase().startsWith('k') || (student.gender ?? '').toLowerCase().startsWith('f'))
                      ? const Color(0xFFFCE7F3)
                      : const Color(0xFFDBEAFE),
                  child: Text(
                    student.fullName.isNotEmpty ? student.fullName[0] : '?',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      color: ((student.gender ?? '').toLowerCase().startsWith('k') || (student.gender ?? '').toLowerCase().startsWith('f'))
                          ? const Color(0xFFDB2777)
                          : const Color(0xFF2563EB),
                    ),
                  ),
                ),
                title: Text(student.fullName, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: Text(
                  '${cell.customLabel ?? "Masa ${cell.row + 1}-${cell.col + 1}"} • ${slot.slotIndex == 0 ? "Sol" : "Sağ"} Koltuk',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              const Divider(),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.tune_rounded, color: Color(0xFF4F46E5)),
                ),
                title: Text('Öğrenci Kriterleri & Tercihleri', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text('Şunla oturmasın, sıra tercihi, ön sıra zorunluluğu', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showStudentCriteriaDialog(student);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: slot.isPinned ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    slot.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    color: slot.isPinned ? const Color(0xFFD97706) : const Color(0xFF64748B),
                  ),
                ),
                title: Text(
                  slot.isPinned ? 'Sabitlemeyi Kaldır (Serbest Bırak)' : 'Bu Koltukta Sabitle (Pin)',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: Text(
                  slot.isPinned
                      ? 'Algoritma bu öğrencinin yerini artık değiştirebilir.'
                      : 'Algoritma bu öğrencinin yerini asla değiştiremez.',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _togglePin(slot);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_remove_rounded, color: Color(0xFFEF4444)),
                ),
                title: Text('Koltuğu Boşalt', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: const Color(0xFFEF4444))),
                subtitle: Text('Öğrenciyi masadan kaldırıp boştaki listeye aktarır', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _clearSlot(slot);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSeatAssignmentDialog(DeskCell cell, SeatSlot slot) {
    String query = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final unassigned = _unassignedStudents.where((s) {
            if (query.isEmpty) return true;
            final q = query.toLowerCase();
            return s.fullName.toLowerCase().contains(q) ||
                (s.studentNumber != null && s.studentNumber!.contains(q));
          }).toList();

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5C6BC0).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.person_add_rounded, color: Color(0xFF5C6BC0), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Öğrenci Seç',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                            ),
                            Text(
                              '${cell.customLabel ?? "Masa ${cell.row + 1}-${cell.col + 1}"} (${slot.slotIndex == 0 ? "Sol" : "Sağ"} Koltuk)',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.grey),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Öğrenci ara (Ad veya No)...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      isDense: true,
                    ),
                    onChanged: (v) => setDialogState(() => query = v),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: unassigned.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_off_rounded, size: 40, color: Colors.grey.shade300),
                                const SizedBox(height: 8),
                                Text(
                                  'Boşta uygun öğrenci bulunamadı.',
                                  style: GoogleFonts.inter(color: Colors.grey.shade500, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            itemCount: unassigned.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final st = unassigned[idx];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                leading: CircleAvatar(
                                  radius: 17,
                                  backgroundColor: ((st.gender ?? '').toLowerCase().startsWith('k') || (st.gender ?? '').toLowerCase().startsWith('f'))
                                      ? const Color(0xFFFCE7F3)
                                      : const Color(0xFFDBEAFE),
                                  child: Text(
                                    st.fullName.isNotEmpty ? st.fullName[0] : '?',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: ((st.gender ?? '').toLowerCase().startsWith('k') || (st.gender ?? '').toLowerCase().startsWith('f'))
                                          ? const Color(0xFFDB2777)
                                          : const Color(0xFF2563EB),
                                    ),
                                  ),
                                ),
                                title: Text(st.fullName, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                subtitle: st.studentNumber != null ? Text('#${st.studentNumber}', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600)) : null,
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF5C6BC0).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('Oturt', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF5C6BC0))),
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _assignStudentToSlot(cell, slot, st);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showStudentCriteriaDialog(SeatingStudentItem student) {
    final constraint = _studentConstraints.putIfAbsent(
      student.id,
      () => StudentSeatingConstraint(studentId: student.id, studentName: student.fullName),
    );

    String? currentPlacementInfo;
    SeatSlot? currentSlot;
    for (var cell in _cells) {
      if (!cell.isDesk) continue;
      for (var s in cell.slots) {
        if (s.studentId == student.id) {
          currentPlacementInfo = '${cell.customLabel ?? "Masa ${cell.row + 1}-${cell.col + 1}"} (${s.slotIndex == 0 ? "Sol" : "Sağ"})';
          currentSlot = s;
          break;
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final avoidList = constraint.avoidStudentIds
              .map((id) => _allStudents.firstWhere((s) => s.id == id, orElse: () => SeatingStudentItem(id: id, fullName: 'Öğrenci #$id')))
              .toList();

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.90,
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: ((student.gender ?? '').toLowerCase().startsWith('k') || (student.gender ?? '').toLowerCase().startsWith('f'))
                            ? const Color(0xFFFCE7F3)
                            : const Color(0xFFDBEAFE),
                        child: Text(
                          student.fullName.isNotEmpty ? student.fullName[0] : '?',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: ((student.gender ?? '').toLowerCase().startsWith('k') || (student.gender ?? '').toLowerCase().startsWith('f'))
                                ? const Color(0xFFDB2777)
                                : const Color(0xFF2563EB),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(student.fullName, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B))),
                            Text(
                              currentPlacementInfo != null ? 'Konum: $currentPlacementInfo' : 'Konum: Boşta (Yerleşmedi)',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.grey),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Birlikte Oturamaz Bölümü
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          const Icon(Icons.person_off_rounded, color: Color(0xFFDC2626), size: 20),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              'Birlikte Oturamaz',
                                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF991B1B)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFDC2626),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () {
                                        _showPickAvoidStudentDialog(
                                          currentStudent: student,
                                          alreadyAvoidedIds: constraint.avoidStudentIds,
                                          onSelected: (other) {
                                            setState(() {
                                              _addAvoidPair(student.id, other.id);
                                            });
                                            setDialogState(() {});
                                          },
                                        );
                                      },
                                      icon: const Icon(Icons.add, size: 14),
                                      label: Text('Ekle', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '💡 Seçilen öğrenciler bu öğrenciyle aynı masada yan yana oturtulmaz.',
                                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFB91C1C)),
                                ),
                                const SizedBox(height: 10),
                                if (avoidList.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Text(
                                      'Henüz engellenen öğrenci yok.',
                                      style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                                    ),
                                  )
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: avoidList.map((other) {
                                      return Chip(
                                        backgroundColor: Colors.white,
                                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                                        avatar: CircleAvatar(
                                          backgroundColor: other.gender == 'K' ? Colors.pink.shade50 : Colors.blue.shade50,
                                          child: Text(other.fullName.isNotEmpty ? other.fullName[0] : '?', style: const TextStyle(fontSize: 10)),
                                        ),
                                        label: Text(
                                          other.fullName,
                                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF991B1B)),
                                        ),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFDC2626)),
                                        onDeleted: () {
                                          setState(() {
                                            _removeAvoidPair(student.id, other.id);
                                          });
                                          setDialogState(() {});
                                        },
                                      );
                                    }).toList(),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Sıra / Bölge Tercihi
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.place_rounded, color: Color(0xFF4F46E5), size: 20),
                                    const SizedBox(width: 8),
                                    Text('Tercih Edilen Sıra / Bölge', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF1E293B))),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<RowZonePreference>(
                                  value: constraint.rowZonePreference,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: RowZonePreference.any, child: Text('Farketmez (Genel Dağıtım)')),
                                    DropdownMenuItem(value: RowZonePreference.frontRow, child: Text('Ön Sıralar (1. ve 2. Sıra)')),
                                    DropdownMenuItem(value: RowZonePreference.middleRow, child: Text('Orta Sıralar (2. - 4. Sıra)')),
                                    DropdownMenuItem(value: RowZonePreference.backRow, child: Text('Arka Sıralar (Uzun Boy)')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => constraint.rowZonePreference = val);
                                      setDialogState(() {});
                                    }
                                  },
                                ),
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('Ön Sıra Kesin Zorunlu', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: Text('Görme / İşitme nedeniyle mutlaka ön sıraya verilsin', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
                                  value: constraint.isFrontRowRequired,
                                  onChanged: (v) {
                                    setState(() => constraint.isFrontRowRequired = v);
                                    setDialogState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Mevcut Koltukta Sabitleme
                          if (currentSlot != null)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('Mevcut Koltukta Sabitle (Pin)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF92400E))),
                                subtitle: Text('Algoritma çalışırken bu öğrencinin masası asla değiştirilmez.', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFB45309))),
                                value: currentSlot.isPinned,
                                onChanged: (v) {
                                  setState(() => currentSlot!.isPinned = v);
                                  setDialogState(() {});
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {});
                      },
                      child: const Text('Tamam'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showPickAvoidStudentDialog({
    required SeatingStudentItem currentStudent,
    required Set<String> alreadyAvoidedIds,
    required Function(SeatingStudentItem) onSelected,
  }) {
    String search = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final eligible = _allStudents.where((s) {
            if (s.id == currentStudent.id) return false;
            if (alreadyAvoidedIds.contains(s.id)) return false;
            if (search.isNotEmpty) {
              final q = search.toLowerCase();
              return s.fullName.toLowerCase().contains(q) ||
                  (s.studentNumber != null && s.studentNumber!.contains(q));
            }
            return true;
          }).toList();

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.80,
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.person_off_rounded, color: Color(0xFFDC2626), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Birlikte Oturmayacak Öğrenciyi Seç',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: const Color(0xFF1E293B)),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.grey),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Öğrenci ara...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      isDense: true,
                    ),
                    onChanged: (v) => setDialogState(() => search = v),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: eligible.isEmpty
                        ? Center(
                            child: Text(
                              'Seçilebilecek öğrenci kalmadı.',
                              style: GoogleFonts.inter(color: Colors.grey, fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            itemCount: eligible.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final st = eligible[idx];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                leading: CircleAvatar(
                                  radius: 15,
                                  backgroundColor: ((st.gender ?? '').toLowerCase().startsWith('k') || (st.gender ?? '').toLowerCase().startsWith('f'))
                                      ? const Color(0xFFFCE7F3)
                                      : const Color(0xFFDBEAFE),
                                  child: Text(
                                    st.fullName.isNotEmpty ? st.fullName[0] : '?',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: ((st.gender ?? '').toLowerCase().startsWith('k') || (st.gender ?? '').toLowerCase().startsWith('f'))
                                          ? const Color(0xFFDB2777)
                                          : const Color(0xFF2563EB),
                                    ),
                                  ),
                                ),
                                title: Text(st.fullName, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                                subtitle: st.studentNumber != null ? Text('#${st.studentNumber}', style: GoogleFonts.inter(fontSize: 11)) : null,
                                trailing: const Icon(Icons.add_circle_outline, color: Color(0xFFDC2626)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  onSelected(st);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStudentSidebar({void Function(SeatingStudentItem)? onStudentSelected}) {
    final Set<String> assignedIds = {};
    for (var cell in _cells) {
      if (!cell.isDesk) continue;
      for (var slot in cell.slots) {
        if (slot.isOccupied) {
          assignedIds.add(slot.studentId!);
        }
      }
    }

    var list = _allStudents.toList();
    if (_studentFilterMode == 'unassigned') {
      list = list.where((s) => !assignedIds.contains(s.id)).toList();
    } else if (_studentFilterMode == 'assigned') {
      list = list.where((s) => assignedIds.contains(s.id)).toList();
    }

    if (_studentSearchQuery.isNotEmpty) {
      final q = _studentSearchQuery.toLowerCase();
      list = list.where((s) =>
          s.fullName.toLowerCase().contains(q) ||
          (s.studentNumber != null && s.studentNumber!.contains(q))).toList();
    }

    final unassignedCount = _allStudents.where((s) => !assignedIds.contains(s.id)).length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Öğrenci Listesi',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: const Color(0xFF1E293B)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: unassignedCount == 0 ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$unassignedCount Boşta',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: unassignedCount == 0 ? const Color(0xFF166534) : const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Search Field
          TextField(
            decoration: InputDecoration(
              hintText: 'Öğrenci ara...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _studentSearchQuery = v),
          ),
          const SizedBox(height: 10),

          // Filter Segment
          Row(
            children: [
              _buildFilterTab('all', 'Tümü (${_allStudents.length})'),
              const SizedBox(width: 4),
              _buildFilterTab('unassigned', 'Boşta ($unassignedCount)'),
              const SizedBox(width: 4),
              _buildFilterTab('assigned', 'Oturan (${assignedIds.length})'),
            ],
          ),
          const SizedBox(height: 10),

          // Student List
          Expanded(
            child: _isLoadingStudents
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? Center(
                        child: Text(
                          'Öğrenci bulunamadı.',
                          style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        physics: const BouncingScrollPhysics(),
                        itemBuilder: (context, index) {
                          final student = list[index];
                          final isAssigned = assignedIds.contains(student.id);
                          final isSelected = _selectedStudentForPlacement?.id == student.id;

                          // Öğrencinin kısıtlamaları var mı?
                          final constraint = _studentConstraints[student.id];
                          final hasAvoid = constraint != null && constraint.avoidStudentIds.isNotEmpty;
                          final hasFrontReq = constraint != null && constraint.isFrontRowRequired;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
                                width: isSelected ? 1.6 : 1,
                              ),
                            ),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                              leading: CircleAvatar(
                                radius: 15,
                                backgroundColor: ((student.gender ?? '').toLowerCase().startsWith('k') || (student.gender ?? '').toLowerCase().startsWith('f'))
                                    ? const Color(0xFFFCE7F3)
                                    : const Color(0xFFDBEAFE),
                                child: Text(
                                  student.fullName.isNotEmpty ? student.fullName[0] : '?',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: ((student.gender ?? '').toLowerCase().startsWith('k') || (student.gender ?? '').toLowerCase().startsWith('f'))
                                        ? const Color(0xFFDB2777)
                                        : const Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                              title: Text(
                                student.fullName,
                                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                              ),
                              subtitle: Row(
                                children: [
                                  if (student.studentNumber != null)
                                    Text('#${student.studentNumber} • ', style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey.shade600)),
                                  if (isAssigned)
                                    Text('Oturtuldu', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A)))
                                  else
                                    Text('Boşta', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFFD97706))),
                                  if (hasAvoid) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF2F2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '🚫 ${constraint.avoidStudentIds.length}',
                                        style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.bold, color: const Color(0xFFDC2626)),
                                      ),
                                    ),
                                  ],
                                  if (hasFrontReq) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEEF2FF),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '👁️ Ön',
                                        style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.more_vert_rounded, size: 20, color: Color(0xFF64748B)),
                                onPressed: () => _showStudentCriteriaDialog(student),
                              ),
                              onTap: () {
                                if (onStudentSelected != null) {
                                  onStudentSelected(student);
                                } else {
                                  setState(() {
                                    if (_selectedStudentForPlacement?.id == student.id) {
                                      _selectedStudentForPlacement = null;
                                    } else {
                                      _selectedStudentForPlacement = student;
                                    }
                                  });
                                }
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String mode, String label) {
    final isSelected = _studentFilterMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _studentFilterMode = mode),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showDistributionOptionsDialog() {
    bool avoidSameSeat = _distributionOptions.avoidSameSeat;
    bool avoidSameDesk = _distributionOptions.avoidSameDesk;
    bool avoidSameNeighbor = _distributionOptions.avoidSameNeighbor;
    bool prioritizeSpecial = _distributionOptions.prioritizeSpecialNeedsInFront;
    bool balanceGender = _distributionOptions.balanceGender;
    int depth = _distributionOptions.historyDepth;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5C6BC0).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.tune_rounded, color: Color(0xFF5C6BC0), size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Akıllı Dağıtım Ayarları', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17, color: const Color(0xFF1E293B))),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Geçmişteki Aynı Koltuğu Önle', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5)),
                          subtitle: Text('Son planlarda oturduğu birebir aynı sandalyeye verilmesin', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600)),
                          value: avoidSameSeat,
                          onChanged: (v) => setDialogState(() => avoidSameSeat = v),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Aynı Masayı Önle', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5)),
                          subtitle: Text('Son oturduğu masanın diğer koltuğuna da verilmesin', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600)),
                          value: avoidSameDesk,
                          onChanged: (v) => setDialogState(() => avoidSameDesk = v),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Aynı Sıra Arkadaşını Önle', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5)),
                          subtitle: Text('Daha önce yan yana oturan öğrenciler tekrar eşleşmesin', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600)),
                          value: avoidSameNeighbor,
                          onChanged: (v) => setDialogState(() => avoidSameNeighbor = v),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Özel Durumlu Öğrencileri Ön Sıraya Al', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5)),
                          subtitle: Text('Görme/işitme veya özel gereksinimi olanlar ön 2 sıraya verilsin', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600)),
                          value: prioritizeSpecial,
                          onChanged: (v) => setDialogState(() => prioritizeSpecial = v),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Kız-Erkek Dengesi Gözet', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13.5)),
                          subtitle: Text('Çiftli sıralarda karma oturma düzeni tercih edilsin', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600)),
                          value: balanceGender,
                          onChanged: (v) => setDialogState(() => balanceGender = v),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Geçmiş Plan Derinliği:', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF1E293B))),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF5C6BC0),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text('$depth Plan', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white)),
                                  ),
                                ],
                              ),
                              Slider(
                                value: depth.toDouble(),
                                min: 1,
                                max: 10,
                                divisions: 9,
                                activeColor: const Color(0xFF5C6BC0),
                                label: '$depth',
                                onChanged: (v) => setDialogState(() => depth = v.round()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5C6BC0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      setState(() {
                        _distributionOptions = DistributionOptions(
                          avoidSameSeat: avoidSameSeat,
                          avoidSameDesk: avoidSameDesk,
                          avoidSameNeighbor: avoidSameNeighbor,
                          prioritizeSpecialNeedsInFront: prioritizeSpecial,
                          balanceGender: balanceGender,
                          historyDepth: depth,
                        );
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Ayarları Kaydet ve Kapat'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
