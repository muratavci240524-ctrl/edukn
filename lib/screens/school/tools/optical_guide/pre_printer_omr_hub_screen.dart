import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';
import '../../../../models/class_model.dart';
import '../../../../models/optical_form_template.dart';
import '../../../../widgets/edukn_app_bar.dart';
import '../../../../services/pre_printer_omr_pdf_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Ana Ekran
// ─────────────────────────────────────────────────────────────────────────────

/// Parametrik Optik Form Ön Kodlayıcı (Pre-printer OMR)
///
/// Seçilen şubedeki öğrencilerin Ad, Soyad ve Okul No bilgilerini
/// seçilen optik form şablonunun koordinatlarına göre boş formlara
/// basmak için PDF üretir.
///
/// Ana sekmeler:
/// 1. Şablon  — koordinat ve daire ayarları
/// 2. Kalibrasyon — yazıcı yönlendirme kayması
/// 3. Yazdır — şube seçimi ve toplu PDF üretimi
class PrePrinterOmrHubScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const PrePrinterOmrHubScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  });

  @override
  State<PrePrinterOmrHubScreen> createState() => _PrePrinterOmrHubScreenState();
}

class _PrePrinterOmrHubScreenState extends State<PrePrinterOmrHubScreen>
    with SingleTickerProviderStateMixin {
  // ── Renkler ───────────────────────────────────────────────────────────────
  static const _c1 = Color(0xFF6C63FF);   // indigo
  static const _c2 = Color(0xFF4B44D1);   // koyu indigo

  // ── Tab ───────────────────────────────────────────────────────────────────
  late TabController _tabCtrl;

  // ── Şablon ────────────────────────────────────────────────────────────────
  OpticalFormTemplate _template = OpticalFormTemplate.mebA4Portrait;

  // ── Kaydedilmiş şablonlar (Firestore) ────────────────────────────────────
  List<OpticalFormTemplate> _savedTemplates = [];
  bool _loadingTemplates = false;

  // ── Kalibrasyon ───────────────────────────────────────────────────────────
  PrinterCalibration _calibration = const PrinterCalibration();

  // ── Şube ve öğrenciler ────────────────────────────────────────────────────
  ClassModel? _selectedClass;
  List<Map<String, dynamic>> _students = [];
  bool _loadingStudents = false;
  final Set<String> _selectedIds = {};

  // ── PDF üretim durumu ─────────────────────────────────────────────────────
  bool _generating = false;

  // ── Firestore şablon koleksiyonu ──────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get _templatesRef =>
      FirebaseFirestore.instance
          .collection('institutions')
          .doc(widget.institutionId)
          .collection('optical_templates');

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadSavedTemplates();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Kaydedilmiş Şablon CRUD ───────────────────────────────────────────────

  Future<void> _loadSavedTemplates() async {
    if (!mounted) return;
    setState(() => _loadingTemplates = true);
    try {
      final snap = await _templatesRef.orderBy('name').get();
      if (mounted) {
        setState(() {
          _savedTemplates = snap.docs
              .map((d) => OpticalFormTemplate.fromMap(d.data(), docId: d.id))
              .toList();
          _loadingTemplates = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTemplates = false);
    }
  }

  Future<void> _showSaveDialog() async {
    final nameCtrl = TextEditingController(text: _template.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_c1, _c2]),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.save_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text('Şablonu Kaydet',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bu şablona bir isim verin:',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Örn: LGS 2025 Formu',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.label_rounded),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _c2,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Kaydet', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final templateName = nameCtrl.text.trim();
    if (templateName.isEmpty) return;

    try {
      final toSave = _template.copyWith(name: templateName).toMap();
      // id alanını Firestore doc ID'ye bırak
      toSave.remove('id');
      final docRef = await _templatesRef.add(toSave);
      if (mounted) {
        setState(() {
          _savedTemplates.add(
            OpticalFormTemplate.fromMap({...toSave, 'name': templateName}, docId: docRef.id),
          );
          _savedTemplates.sort((a, b) => a.name.compareTo(b.name));
        });
        _snack('"$templateName" kaydedildi ✓');
      }
    } catch (e) {
      if (mounted) _snack('Kayıt hatası: $e', error: true);
    }
  }

  Future<void> _deleteTemplate(OpticalFormTemplate tpl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Şablonu Sil?',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: Text('"${tpl.name}" kalıcı olarak silinecek.',
            style: GoogleFonts.inter(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Sil', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _templatesRef.doc(tpl.id).delete();
      if (mounted) {
        setState(() => _savedTemplates.removeWhere((t) => t.id == tpl.id));
        _snack('"${tpl.name}" silindi.');
      }
    } catch (e) {
      if (mounted) _snack('Silme hatası: $e', error: true);
    }
  }

  // ── Firestore ─────────────────────────────────────────────────────────────

  Stream<QuerySnapshot> _classesStream() => FirebaseFirestore.instance
      .collection('classes')
      .where('institutionId', isEqualTo: widget.institutionId)
      .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
      .snapshots();

  Future<void> _loadStudents(String classId) async {
    if (!mounted) return;
    setState(() {
      _loadingStudents = true;
      _students = [];
      _selectedIds.clear();
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('classId', isEqualTo: classId)
          .get();

      final list = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .where((s) => s['isActive'] != false)
          .toList()
        ..sort((a, b) {
          final la = (a['lastName'] ?? a['surname'] ?? '').toString();
          final lb = (b['lastName'] ?? b['surname'] ?? '').toString();
          return la.compareTo(lb);
        });

      if (mounted) {
        setState(() {
          _students = list;
          _selectedIds.addAll(list.map((s) => s['id'] as String));
          _loadingStudents = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingStudents = false);
        _snack('Öğrenciler yüklenemedi: $e', error: true);
      }
    }
  }

  // ── PDF ───────────────────────────────────────────────────────────────────

  Future<void> _generatePdf() async {
    if (_selectedClass == null) {
      _snack('Lütfen önce bir şube seçin.', error: true);
      return;
    }
    if (_selectedIds.isEmpty) {
      _snack('En az bir öğrenci seçin.', error: true);
      return;
    }

    setState(() => _generating = true);
    try {
      final students = _students
          .where((s) => _selectedIds.contains(s['id'] as String))
          .map((s) => OmrStudent(
                firstName: (s['firstName'] ?? s['name'] ?? '').toString().trim(),
                lastName: (s['lastName'] ?? s['surname'] ?? '').toString().trim(),
                studentNumber:
                    (s['studentNumber'] ?? s['studentNo'] ?? s['schoolNumber'] ?? '')
                        .toString()
                        .trim(),
                tcNo: (s['tcNo'] ?? s['tcIdentityNumber'] ?? s['tcKimlik'] ?? '')
                    .toString()
                    .trim(),
              ))
          .toList();

      final bytes = await PrePrinterOmrPdfService.generatePrePrintedOmrPdf(
        students: students,
        template: _template,
        calibration: _calibration,
        className: _selectedClass!.className,
      );

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _PdfPreviewPage(
            pdfBytes: bytes,
            title: 'OMR Baskı — ${_selectedClass!.className}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) _snack('PDF üretilemedi: $e', error: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ── Yardımcılar ───────────────────────────────────────────────────────────

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
      backgroundColor: error ? Colors.red.shade600 : _c2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(14),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FC),
      appBar: EduknAppBar(
        title: 'Parametrik OMR Ön Kodlayıcı',
        subtitle: '${widget.schoolTypeName} • Pre-Printer',
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E1B4B),
        subtitleColor: const Color(0xFF64748B),
        backButtonColor: _c2,
        borderColor: const Color(0xFFE2E8F0),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: _c2,
          unselectedLabelColor: Colors.grey.shade400,
          indicatorColor: _c1,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.grid_view_rounded, size: 18), text: 'Şablon'),
            Tab(icon: Icon(Icons.tune_rounded, size: 18), text: 'Kalibrasyon'),
            Tab(icon: Icon(Icons.print_rounded, size: 18), text: 'Yazdır'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _TemplateTab(
            template: _template,
            onChanged: (t) => setState(() => _template = t),
          ),
          _CalibrationTab(
            calibration: _calibration,
            onChanged: (c) => setState(() => _calibration = c),
          ),
          _PrintTab(
            institutionId: widget.institutionId,
            classesStream: _classesStream(),
            selectedClass: _selectedClass,
            onClassSelected: (cls) {
              setState(() => _selectedClass = cls);
              _loadStudents(cls.id!);
            },
            students: _students,
            loadingStudents: _loadingStudents,
            selectedIds: _selectedIds,
            onToggle: (id) => setState(() {
              if (_selectedIds.contains(id)) {
                _selectedIds.remove(id);
              } else {
                _selectedIds.add(id);
              }
            }),
            onToggleAll: (all) => setState(() {
              if (all) {
                _selectedIds.addAll(_students.map((s) => s['id'] as String));
              } else {
                _selectedIds.clear();
              }
            }),
            generating: _generating,
            onGenerate: _generatePdf,
            calibration: _calibration,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sekme 1 — Şablon
// ─────────────────────────────────────────────────────────────────────────────

class _TemplateTab extends StatefulWidget {
  final OpticalFormTemplate template;
  final ValueChanged<OpticalFormTemplate> onChanged;

  const _TemplateTab({required this.template, required this.onChanged});

  @override
  State<_TemplateTab> createState() => _TemplateTabState();
}

class _TemplateTabState extends State<_TemplateTab> {
  late OpticalFormTemplate _tpl;
  static const _c1 = Color(0xFF6C63FF);
  static const _c2 = Color(0xFF4B44D1);

  @override
  void initState() {
    super.initState();
    _tpl = widget.template;
  }

  void _update(OpticalFormTemplate t) {
    setState(() => _tpl = t);
    widget.onChanged(t);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Hazır şablon seçici
        _card(
          title: 'Hazır Şablonlar',
          icon: Icons.dashboard_customize_rounded,
          child: Column(
            children: OpticalFormTemplate.presets.map((p) {
              final isSelected = _tpl.id == p.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _update(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: isSelected ? _c1.withValues(alpha: 0.07) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? _c1 : Colors.grey.shade200,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                          color: isSelected ? _c1 : Colors.grey.shade400,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name,
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700, fontSize: 14,
                                      color: isSelected ? _c2 : const Color(0xFF1F2937))),
                              const SizedBox(height: 2),
                              Text(
                                '${p.paperWidthMm.toInt()} × ${p.paperHeightMm.toInt()} mm  •  ⌀ ${p.circleDiameterMm} mm',
                                style: GoogleFonts.inter(
                                    fontSize: 12, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        // Daire çapı
        _card(
          title: 'Daire Çapı',
          icon: Icons.circle_outlined,
          child: _mmSlider(
            label: 'Çap',
            value: _tpl.circleDiameterMm,
            min: 1.5, max: 6.0,
            onChanged: (v) => _update(_tpl.copyWith(circleDiameterMm: v)),
          ),
        ),
        const SizedBox(height: 12),
        // Alan koordinatları
        _fieldCard('AD Alanı', Icons.person_outline_rounded, _tpl.nameField,
            (f) => _update(_tpl.copyWith(nameField: f))),
        const SizedBox(height: 12),
        _fieldCard('SOYAD Alanı', Icons.person_rounded, _tpl.surnameField,
            (f) => _update(_tpl.copyWith(surnameField: f))),
        const SizedBox(height: 12),
        _fieldCard('OKUL NO Alanı', Icons.tag_rounded, _tpl.noField,
            (f) => _update(_tpl.copyWith(noField: f))),
        const SizedBox(height: 12),
        _fieldCard('T.C. KİMLİK NO Alanı', Icons.badge_rounded, _tpl.tcField,
            (f) => _update(_tpl.copyWith(tcField: f))),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _fieldCard(String title, IconData icon, FieldTemplate field,
      ValueChanged<FieldTemplate> onChanged) {
    return _card(
      title: title,
      icon: icon,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _mmInput('Başlangıç X (mm)', field.startXMm,
                  (v) => onChanged(field.copyWith(startXMm: v)))),
              const SizedBox(width: 8),
              Expanded(child: _mmInput('Başlangıç Y (mm)', field.startYMm,
                  (v) => onChanged(field.copyWith(startYMm: v)))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _mmInput('Yatay Aralık (mm)', field.colSpacingMm,
                  (v) => onChanged(field.copyWith(colSpacingMm: v)))),
              const SizedBox(width: 8),
              Expanded(child: _mmInput('Dikey Aralık (mm)', field.rowSpacingMm,
                  (v) => onChanged(field.copyWith(rowSpacingMm: v)))),
            ],
          ),
          const SizedBox(height: 8),
          _mmSlider(
            label: 'Maks. Sütun',
            value: field.maxCols.toDouble(),
            min: 1, max: 25,
            divisions: 24,
            isInt: true,
            onChanged: (v) => onChanged(field.copyWith(maxCols: v.round())),
          ),
        ],
      ),
    );
  }

  Widget _mmInput(String label, double value, ValueChanged<double> onChanged) {
    final ctrl = TextEditingController(text: value.toStringAsFixed(1));
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
        suffixText: 'mm',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        isDense: true,
      ),
      onSubmitted: (v) {
        final d = double.tryParse(v);
        if (d != null) onChanged(d);
      },
    );
  }

  Widget _mmSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    int? divisions,
    bool isInt = false,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions ?? ((max - min) / 0.1).round(),
            activeColor: _c1,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            isInt ? value.round().toString() : '${value.toStringAsFixed(1)} mm',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _c2),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _card({required String title, required IconData icon, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_c1, _c2]),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: const Color(0xFF1E1B4B))),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sekme 2 — Kalibrasyon
// ─────────────────────────────────────────────────────────────────────────────

class _CalibrationTab extends StatelessWidget {
  final PrinterCalibration calibration;
  final ValueChanged<PrinterCalibration> onChanged;

  const _CalibrationTab({required this.calibration, required this.onChanged});

  static const _c1 = Color(0xFF6C63FF);
  static const _c2 = Color(0xFF4B44D1);
  static const _step = 0.1; // mm
  static const _min = -10.0;
  static const _max = 10.0;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Bilgi kartı
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFEDE9FF), Color(0xFFE8F0FF)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _c1.withValues(alpha: 0.2)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.info_outline_rounded, color: _c2, size: 20),
                const SizedBox(width: 8),
                Text('Kalibrasyon Nasıl Yapılır?',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700, color: _c2, fontSize: 14)),
              ]),
              const SizedBox(height: 10),
              Text(
                '1. Önce tüm değerleri sıfırda bırakın ve 1 sayfalık test çıktısı alın.\n'
                '2. Boş bir optik form üzerine koyup ışığa tutun.\n'
                '3. Daireler formun sağında kaldıysa X\'i negatif yapın (sola kaydır).\n'
                '4. Daireler formun altında kaldıysa Y\'yi negatif yapın (yukarı kaydır).\n'
                '5. Her denemede 0.5–1 mm değiştirin, hassasiyetle yaklaşın.',
                style: GoogleFonts.inter(fontSize: 12, height: 1.7, color: const Color(0xFF374151)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // X ekseni
        _offsetCard(
          label: 'X — Yatay Kayma',
          subtitle: 'Pozitif → Sağa  |  Negatif → Sola',
          icon: Icons.swap_horiz_rounded,
          value: calibration.offsetXMm,
          onChanged: (v) => onChanged(calibration.copyWith(offsetXMm: v)),
        ),
        const SizedBox(height: 12),

        // Y ekseni
        _offsetCard(
          label: 'Y — Dikey Kayma',
          subtitle: 'Pozitif → Aşağı  |  Negatif → Yukarı',
          icon: Icons.swap_vert_rounded,
          value: calibration.offsetYMm,
          onChanged: (v) => onChanged(calibration.copyWith(offsetYMm: v)),
        ),
        const SizedBox(height: 16),

        // Özet
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.adjust_rounded, color: _c2, size: 20),
              const SizedBox(width: 8),
              Text('Aktif Kalibrasyon: $calibration',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, fontSize: 14, color: _c2)),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Sıfırla
        Center(
          child: OutlinedButton.icon(
            onPressed: () => onChanged(const PrinterCalibration()),
            icon: const Icon(Icons.refresh_rounded),
            label: Text('Kalibrasyonu Sıfırla', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _c2,
              side: const BorderSide(color: _c2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _offsetCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_c1, _c2]),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: const Color(0xFF1E1B4B))),
                Text(subtitle,
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ]),
          const SizedBox(height: 14),
          // Slider
          SliderTheme(
            data: SliderThemeData(
              thumbColor: _c1,
              activeTrackColor: _c1,
              inactiveTrackColor: Colors.grey.shade200,
              overlayColor: _c1.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: value.clamp(_min, _max),
              min: _min,
              max: _max,
              divisions: ((_max - _min) / _step).round(),
              onChanged: onChanged,
            ),
          ),
          // Değer göstergesi + butonlar
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _offsetBtn('-1 mm', () => onChanged((value - 1.0).clamp(_min, _max))),
              const SizedBox(width: 6),
              _offsetBtn('-0.5', () => onChanged((value - 0.5).clamp(_min, _max))),
              const SizedBox(width: 6),
              _offsetBtn('-0.1', () => onChanged((value - 0.1).clamp(_min, _max))),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _c1.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _c1.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} mm',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800, fontSize: 15, color: _c2),
                ),
              ),
              const SizedBox(width: 10),
              _offsetBtn('+0.1', () => onChanged((value + 0.1).clamp(_min, _max))),
              const SizedBox(width: 6),
              _offsetBtn('+0.5', () => onChanged((value + 0.5).clamp(_min, _max))),
              const SizedBox(width: 6),
              _offsetBtn('+1 mm', () => onChanged((value + 1.0).clamp(_min, _max))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _offsetBtn(String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151))),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sekme 3 — Yazdır
// ─────────────────────────────────────────────────────────────────────────────

class _PrintTab extends StatelessWidget {
  final String institutionId;
  final Stream<QuerySnapshot> classesStream;
  final ClassModel? selectedClass;
  final ValueChanged<ClassModel> onClassSelected;
  final List<Map<String, dynamic>> students;
  final bool loadingStudents;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final ValueChanged<bool> onToggleAll;
  final bool generating;
  final VoidCallback onGenerate;
  final PrinterCalibration calibration;

  const _PrintTab({
    required this.institutionId,
    required this.classesStream,
    required this.selectedClass,
    required this.onClassSelected,
    required this.students,
    required this.loadingStudents,
    required this.selectedIds,
    required this.onToggle,
    required this.onToggleAll,
    required this.generating,
    required this.onGenerate,
    required this.calibration,
  });

  static const _c1 = Color(0xFF6C63FF);
  static const _c2 = Color(0xFF4B44D1);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Şube seçici ─────────────────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_c1, _c2]),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.class_rounded, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 10),
                Text('Şube Seçin',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: const Color(0xFF1E1B4B))),
              ]),
              const SizedBox(height: 12),
              StreamBuilder<QuerySnapshot>(
                stream: classesStream,
                builder: (ctx, snap) {
                  if (snap.hasError) {
                    return Text('Hata: ${snap.error}',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade400));
                  }
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: _c1, strokeWidth: 2));
                  }
                  if (!snap.hasData || snap.data!.docs.isEmpty) {
                    return Text('Aktif şube bulunamadı.',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade400));
                  }
                  final classes = snap.data!.docs
                      .map((d) => ClassModel.fromMap(d.data() as Map<String, dynamic>, d.id))
                      .toList()
                    ..sort((a, b) => a.className.compareTo(b.className));

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: classes.map((cls) {
                        final sel = selectedClass?.id == cls.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: sel,
                            label: Text(cls.className),
                            labelStyle: GoogleFonts.inter(
                              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                              color: sel ? Colors.white : const Color(0xFF4B5563),
                              fontSize: 13,
                            ),
                            backgroundColor: Colors.grey.shade100,
                            selectedColor: _c2,
                            checkmarkColor: Colors.white,
                            side: BorderSide(color: sel ? _c2 : Colors.grey.shade300),
                            onSelected: (_) => onClassSelected(cls),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              // Kalibrasyon özeti
              if (calibration.offsetXMm != 0 || calibration.offsetYMm != 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE9FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.tune_rounded, size: 14, color: _c2),
                        const SizedBox(width: 6),
                        Text('Kalibrasyon: $calibration',
                            style: GoogleFonts.inter(
                                fontSize: 11, fontWeight: FontWeight.w600, color: _c2)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Öğrenci listesi ─────────────────────────────────────────────────
        Expanded(child: _buildStudentList()),

        // ── Alt buton ────────────────────────────────────────────────────────
        if (selectedClass != null)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: ElevatedButton.icon(
                onPressed: generating ? null : onGenerate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _c2,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                icon: generating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.print_rounded),
                label: Text(
                  generating
                      ? 'PDF Üretiliyor...'
                      : 'Toplu Baskı PDF  (${selectedIds.length} öğrenci)',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStudentList() {
    if (selectedClass == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.print_rounded, size: 64, color: Colors.grey.shade200),
            const SizedBox(height: 14),
            Text('Öğrencileri görmek için\nbir şube seçin',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    if (loadingStudents) {
      return const Center(child: CircularProgressIndicator(color: _c1));
    }

    if (students.isEmpty) {
      return Center(
        child: Text('Bu şubede öğrenci bulunamadı.',
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade400)),
      );
    }

    final allSel = selectedIds.length == students.length;

    return Column(
      children: [
        // Tümünü seç
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Checkbox(
                value: allSel,
                tristate: true,
                activeColor: _c2,
                onChanged: (v) => onToggleAll(v ?? false),
              ),
              Text('Tümünü Seç  (${students.length})',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              Text('${selectedIds.length} seçili',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: _c2)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
            separatorBuilder: (_, __) => const SizedBox(height: 5),
            itemCount: students.length,
            itemBuilder: (ctx, i) {
              final s = students[i];
              final id = s['id'] as String;
              final name = '${s['firstName'] ?? s['name'] ?? ''}  ${s['lastName'] ?? s['surname'] ?? ''}';
              final no = (s['studentNumber'] ?? s['studentNo'] ?? s['schoolNumber'] ?? '-').toString();
              final checked = selectedIds.contains(id);

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onToggle(id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: checked ? _c1.withValues(alpha: 0.06) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: checked ? _c1.withValues(alpha: 0.35) : Colors.grey.shade200,
                        width: checked ? 1.5 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 28, height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: checked ? _c2 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${i + 1}',
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: checked ? Colors.white : Colors.grey.shade500)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name.trim(),
                                  style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1F2937))),
                              Text('No: $no',
                                  style: GoogleFonts.inter(
                                      fontSize: 11, color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                        Checkbox(
                          value: checked,
                          activeColor: _c2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                          onChanged: (_) => onToggle(id),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PDF Önizleme
// ─────────────────────────────────────────────────────────────────────────────

class _PdfPreviewPage extends StatelessWidget {
  final Uint8List pdfBytes;
  final String title;

  const _PdfPreviewPage({required this.pdfBytes, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E1B4B),
        elevation: 1,
      ),
      body: PdfPreview(
        build: (_) async => pdfBytes,
        allowPrinting: true,
        allowSharing: true,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        actions: const [],
        pdfFileName: '${title.replaceAll(' ', '_').replaceAll('—', '-')}.pdf',
      ),
    );
  }
}
