import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/school/seating_plan_model.dart';
import '../../../../models/classroom_model.dart';
import '../../../../widgets/edukn_app_bar.dart';

class ClassroomLayoutEditorScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final ClassroomLayout? existingLayout;

  const ClassroomLayoutEditorScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.existingLayout,
  }) : super(key: key);

  @override
  State<ClassroomLayoutEditorScreen> createState() =>
      _ClassroomLayoutEditorScreenState();
}

class _ClassroomLayoutEditorScreenState
    extends State<ClassroomLayoutEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;

  int _rows = 4;
  int _cols = 3;
  DeskType _defaultDeskType = DeskType.double;
  List<DeskCell> _cells = [];

  List<ClassroomModel> _classrooms = [];
  String? _selectedClassroomId;
  String? _selectedClassroomName;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
        text: widget.existingLayout?.name ?? 'Standart Derslik Düzeni');

    if (widget.existingLayout != null) {
      _rows = widget.existingLayout!.rows;
      _cols = widget.existingLayout!.cols;
      _defaultDeskType = widget.existingLayout!.defaultDeskType;
      _cells = widget.existingLayout!.cells.map((c) => c.clone()).toList();
      _selectedClassroomId = widget.existingLayout!.classroomId;
      _selectedClassroomName = widget.existingLayout!.classroomName;
    } else {
      _initGrid();
    }

    _loadClassrooms();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _initGrid() {
    _cells.clear();
    for (int r = 0; r < _rows; r++) {
      for (int c = 0; c < _cols; c++) {
        _cells.add(DeskCell(
          row: r,
          col: c,
          cellType: CellType.desk,
          deskType: _defaultDeskType,
          customLabel: 'Masa ${r + 1}-${c + 1}',
        ));
      }
    }
  }

  void _resizeGrid(int newRows, int newCols) {
    final Map<String, DeskCell> existingMap = {
      for (var c in _cells) '${c.row}-${c.col}': c
    };

    final List<DeskCell> newCells = [];
    for (int r = 0; r < newRows; r++) {
      for (int c = 0; c < newCols; c++) {
        final existing = existingMap['$r-$c'];
        if (existing != null) {
          newCells.add(existing);
        } else {
          newCells.add(DeskCell(
            row: r,
            col: c,
            cellType: CellType.desk,
            deskType: _defaultDeskType,
            customLabel: 'Masa ${r + 1}-${c + 1}',
          ));
        }
      }
    }

    setState(() {
      _rows = newRows;
      _cols = newCols;
      _cells = newCells;
    });
  }

  Future<void> _loadClassrooms() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('classrooms')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final list = snap.docs
          .map((d) => ClassroomModel.fromMap(d.data(), d.id))
          .where((c) =>
              c.schoolTypeId == widget.schoolTypeId || c.schoolTypeId.isEmpty)
          .toList();

      list.sort((a, b) => a.classroomName.compareTo(b.classroomName));

      if (mounted) {
        setState(() {
          _classrooms = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyPreset(String presetType) {
    final preset = ClassroomLayout.createPreset(
      name: _nameController.text,
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
      presetType: presetType,
      classroomId: _selectedClassroomId,
      classroomName: _selectedClassroomName,
    );

    setState(() {
      _rows = preset.rows;
      _cols = preset.cols;
      _defaultDeskType = preset.defaultDeskType;
      _cells = preset.cells;
    });
  }

  void _toggleCell(DeskCell cell) {
    setState(() {
      if (cell.cellType == CellType.desk) {
        cell.cellType = CellType.aisle;
        cell.slots.clear();
      } else {
        cell.cellType = CellType.desk;
        cell.deskType = _defaultDeskType;
        cell.slots = _defaultDeskType == DeskType.double
            ? [SeatSlot(slotIndex: 0), SeatSlot(slotIndex: 1)]
            : [SeatSlot(slotIndex: 0)];
      }
    });
  }

  void _editCellDetails(DeskCell cell) {
    final labelCtrl = TextEditingController(text: cell.customLabel ?? '');
    DeskType selectedType = cell.deskType;
    CellType selectedCellType = cell.cellType;

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
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
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
                      color: const Color(0xFF5C6BC0).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tune_rounded, color: Color(0xFF5C6BC0), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Hücre Ayarları (${cell.row + 1}. Sıra, ${cell.col + 1}. Sütun)',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: labelCtrl,
                decoration: InputDecoration(
                  labelText: 'Masa Etiketi',
                  hintText: 'Örn: Ön Sıra Sol',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
              ),
              const SizedBox(height: 16),
              Text('Hücre Durumu:', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF475569))),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<CellType>(
                  segments: const [
                    ButtonSegment(value: CellType.desk, label: Text('Masa'), icon: Icon(Icons.table_restaurant_rounded)),
                    ButtonSegment(value: CellType.aisle, label: Text('Koridor'), icon: Icon(Icons.space_bar_rounded)),
                  ],
                  selected: {selectedCellType},
                  onSelectionChanged: (val) {
                    setDialogState(() => selectedCellType = val.first);
                  },
                ),
              ),
              if (selectedCellType == CellType.desk) ...[
                const SizedBox(height: 16),
                Text('Masa Tipi:', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF475569))),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<DeskType>(
                    segments: const [
                      ButtonSegment(value: DeskType.single, label: Text('Tekli (1 Kişi)')),
                      ButtonSegment(value: DeskType.double, label: Text('Çiftli (2 Kişi)')),
                    ],
                    selected: {selectedType},
                    onSelectionChanged: (val) {
                      setDialogState(() => selectedType = val.first);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('İptal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5C6BC0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        setState(() {
                          cell.customLabel = labelCtrl.text.trim().isEmpty ? null : labelCtrl.text.trim();
                          cell.cellType = selectedCellType;
                          cell.deskType = selectedType;
                          if (cell.cellType == CellType.desk) {
                            if (selectedType == DeskType.single && cell.slots.length != 1) {
                              cell.slots = [SeatSlot(slotIndex: 0)];
                            } else if (selectedType == DeskType.double && cell.slots.length != 2) {
                              cell.slots = [SeatSlot(slotIndex: 0), SeatSlot(slotIndex: 1)];
                            }
                          } else {
                            cell.slots.clear();
                          }
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text('Uygula'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveLayout() async {
    if (!_formKey.currentState!.validate()) return;

    final deskCount = _cells.where((c) => c.isDesk).length;
    if (deskCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir masa hücresi ekleyin!')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final layout = ClassroomLayout(
        id: widget.existingLayout?.id,
        name: _nameController.text.trim(),
        classroomId: _selectedClassroomId,
        classroomName: _selectedClassroomName,
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        rows: _rows,
        cols: _cols,
        defaultDeskType: _defaultDeskType,
        cells: _cells,
        createdAt: widget.existingLayout?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final colRef = FirebaseFirestore.instance
          .collection('seating_layouts');

      if (layout.id != null) {
        await colRef.doc(layout.id).update(layout.toMap());
      } else {
        await colRef.add(layout.toMap());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Masa düzeni başarıyla kaydedildi!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata oluştu: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1024;
    final totalCapacity = _cells.fold<int>(0, (s, c) => s + c.capacity);
    final totalDesks = _cells.where((c) => c.isDesk).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: EduknAppBar(
        title: widget.existingLayout == null ? 'Yeni Derslik Masa Düzeni' : 'Masa Düzenini Düzenle',
        subtitle: widget.schoolTypeName,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high_rounded, color: Colors.indigo),
            tooltip: 'Hazır Şablonlar',
            onPressed: _showPresetsDialog,
          ),
        ],
      ),
      floatingActionButton: isDesktop
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              elevation: 4,
              onPressed: _isSaving ? null : _saveLayout,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded, size: 20),
              label: Text(
                _isSaving ? 'Kaydediliyor...' : 'Şablonu Kaydet',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            )
          : null,
      bottomNavigationBar: isDesktop
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 1,
                    ),
                    onPressed: _isSaving ? null : _saveLayout,
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.save_rounded, size: 20),
                    label: Text(
                      _isSaving ? 'Kaydediliyor...' : 'Şablonu Kaydet',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Form & Controls Card
                  _buildControlsCard(totalDesks, totalCapacity),
                  const SizedBox(height: 20),

                  // Interactive Grid Section
                  _buildInteractiveBoard(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  void _changeDefaultDeskType(DeskType newType) {
    setState(() {
      _defaultDeskType = newType;
      for (var cell in _cells) {
        if (cell.cellType == CellType.desk) {
          cell.deskType = newType;
          if (newType == DeskType.single) {
            cell.slots = [SeatSlot(slotIndex: 0)];
          } else if (newType == DeskType.double) {
            cell.slots = [SeatSlot(slotIndex: 0), SeatSlot(slotIndex: 1)];
          }
        }
      }
    });
  }

  Widget _buildControlsCard(int totalDesks, int totalCapacity) {
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
      padding: EdgeInsets.all(isMobile ? 16 : 22),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMobile) ...[
              TextFormField(
                controller: _nameController,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                decoration: InputDecoration(
                  labelText: 'Düzen Adı *',
                  labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                  hintText: 'Örn: 9-A Sınıfı Masa Düzeni',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  prefixIcon: const Icon(Icons.grid_view_rounded, color: Color(0xFF5C6BC0), size: 20),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Lütfen bir ad girin' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedClassroomId,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(16),
                decoration: InputDecoration(
                  labelText: 'İlişkili Derslik (Opsiyonel)',
                  labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  prefixIcon: const Icon(Icons.meeting_room_rounded, color: Color(0xFF5C6BC0), size: 20),
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text('Genel Şablon (Bağımsız)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                  ..._classrooms.map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text('${c.classroomName} (${c.capacity} Kişilik)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      )),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedClassroomId = val;
                    final match = _classrooms.where((c) => c.id == val).toList();
                    _selectedClassroomName = match.isNotEmpty ? match.first.classroomName : null;
                  });
                },
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Layout Name
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _nameController,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                      decoration: InputDecoration(
                        labelText: 'Düzen Adı *',
                        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                        hintText: 'Örn: 9-A Sınıfı Standart Masa Düzeni',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFF5C6BC0), width: 1.8),
                        ),
                        prefixIcon: Container(
                          margin: const EdgeInsets.only(left: 12, right: 10),
                          child: const Icon(Icons.grid_view_rounded, color: Color(0xFF5C6BC0), size: 20),
                        ),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Lütfen bir ad girin' : null,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Classroom Association (Optional)
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: _selectedClassroomId,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                      dropdownColor: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF5C6BC0)),
                      decoration: InputDecoration(
                        labelText: 'İlişkili Derslik (Opsiyonel)',
                        labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFF5C6BC0), width: 1.8),
                        ),
                        prefixIcon: Container(
                          margin: const EdgeInsets.only(left: 12, right: 10),
                          child: const Icon(Icons.meeting_room_rounded, color: Color(0xFF5C6BC0), size: 20),
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text('Genel Şablon (Bağımsız)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                        ..._classrooms.map((c) => DropdownMenuItem(
                              value: c.id,
                              child: Text('${c.classroomName} (${c.capacity} Kişilik)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                            )),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedClassroomId = val;
                          final match = _classrooms.where((c) => c.id == val).toList();
                          _selectedClassroomName = match.isNotEmpty ? match.first.classroomName : null;
                        });
                      },
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 18),

            // Grid Dimensions & Controls
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Row count
                _buildCounter('Satır (Derinlik)', _rows, 2, 8, (val) => _resizeGrid(val, _cols)),
                // Col count
                _buildCounter('Sütun (Genişlik)', _cols, 2, 8, (val) => _resizeGrid(_rows, val)),

                // Default Desk Type Toggle
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Masa Tipi: ', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: const Color(0xFF475569))),
                      const SizedBox(width: 6),
                      SegmentedButton<DeskType>(
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: const Color(0xFF5C6BC0),
                          selectedForegroundColor: Colors.white,
                          foregroundColor: const Color(0xFF475569),
                          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: DeskType.double,
                            label: Text('Çiftli'),
                            icon: Icon(Icons.people_outline_rounded, size: 14),
                          ),
                          ButtonSegment(
                            value: DeskType.single,
                            label: Text('Tekli'),
                            icon: Icon(Icons.person_outline_rounded, size: 14),
                          ),
                        ],
                        selected: {_defaultDeskType},
                        onSelectionChanged: (val) => _changeDefaultDeskType(val.first),
                      ),
                    ],
                  ),
                ),

                // Quick Stats Chips
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFC7D2FE)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.table_restaurant_rounded, size: 16, color: Color(0xFF4338CA)),
                      const SizedBox(width: 4),
                      Text('$totalDesks Masa',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: const Color(0xFF3730A3))),
                      const SizedBox(width: 10),
                      Container(width: 1, height: 14, color: const Color(0xFFA5B4FC)),
                      const SizedBox(width: 10),
                      const Icon(Icons.event_seat_rounded, size: 16, color: Color(0xFF4338CA)),
                      const SizedBox(width: 4),
                      Text('$totalCapacity Koltuk',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: const Color(0xFF3730A3))),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCounter(String label, int value, int min, int max, Function(int) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: const Color(0xFF475569))),
          const SizedBox(width: 2),
          InkWell(
            onTap: value > min ? () => onChanged(value - 1) : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: value > min ? const Color(0xFFE2E8F0) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.remove, size: 13, color: value > min ? const Color(0xFF334155) : const Color(0xFF94A3B8)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$value', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B))),
          ),
          InkWell(
            onTap: value < max ? () => onChanged(value + 1) : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: value < max ? const Color(0xFFE2E8F0) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.add, size: 13, color: value < max ? const Color(0xFF334155) : const Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveBoard() {
    final Map<String, DeskCell> cellMap = {
      for (var c in _cells) '${c.row}-${c.col}': c
    };
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 24),
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
        children: [
          // Blackboard / Teacher Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF263238), Color(0xFF37474F)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.edit_note_rounded, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Text(
                  'YAZI TAHTASI / ÖĞRETMEN KÜRSÜSÜ',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: isMobile ? 12 : 14,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '💡 İpucu: Hücreye dokunarak Masa/Koridor durumunu değiştirebilir, uzun basarak masa etiketini düzenleyebilirsiniz.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 18),

          // Grid Layout wrapped with horizontal scrolling if columns exceed mobile width
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: isMobile ? (_cols * 105.0 + 40) : (screenWidth - 80).clamp(300, 1200),
              ),
              child: Column(
                children: [
                  for (int r = 0; r < _rows; r++) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Row Number Indicator
                        Container(
                          width: 32,
                          alignment: Alignment.center,
                          child: Text(
                            '${r + 1}. Sıra',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Desks in row
                        for (int c = 0; c < _cols; c++) ...[
                          SizedBox(
                            width: isMobile ? 100 : 120,
                            child: _buildGridCell(cellMap['$r-$c']!),
                          ),
                          if (c < _cols - 1) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    if (r < _rows - 1) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridCell(DeskCell cell) {
    final isDesk = cell.isDesk;
    final isDouble = cell.deskType == DeskType.double;

    return InkWell(
      onTap: () => _toggleCell(cell),
      onLongPress: () => _editCellDetails(cell),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 78,
        decoration: BoxDecoration(
          color: isDesk ? Colors.white : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDesk ? const Color(0xFF5C6BC0) : const Color(0xFFCBD5E1),
            width: isDesk ? 1.5 : 1.0,
          ),
          boxShadow: isDesk
              ? [
                  BoxShadow(
                    color: const Color(0xFF5C6BC0).withOpacity(0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: isDesk
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isDouble ? Icons.people_rounded : Icons.person_rounded,
                        size: 15,
                        color: const Color(0xFF5C6BC0),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isDouble ? 'Çiftli' : 'Tekli',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF5C6BC0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      cell.customLabel ?? 'Masa ${cell.row + 1}-${cell.col + 1}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.space_bar_rounded, size: 16, color: Color(0xFFCBD5E1)),
                    Text(
                      'Koridor',
                      style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  void _showPresetsDialog() {
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
                    child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF5C6BC0), size: 22),
                  ),
                  const SizedBox(width: 10),
                  Text('Hazır Masa Şablonları', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17, color: const Color(0xFF1E293B))),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildPresetOption(
                        title: '5x5 Izgara Düzeni (24 Masa - Sol Alt Kapalı)',
                        subtitle: '5 Satır x 5 Sütun (Sol alt köşe kapalı/geçiş, 24 Tekli Masa)',
                        icon: Icons.grid_view_rounded,
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyPreset('5x5_single_24');
                        },
                      ),
                      const Divider(height: 1),
                      _buildPresetOption(
                        title: 'Standart 3 Blok Çiftli Sıra',
                        subtitle: '4 Satır x 3 Sütun (24 Kişilik klasik sınıf düzeni)',
                        icon: Icons.view_column_rounded,
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyPreset('3_col_double');
                        },
                      ),
                      const Divider(height: 1),
                      _buildPresetOption(
                        title: 'Koridorlu 3 Blok Düzeni',
                        subtitle: '4 Satır x 5 Sütun (Masalar arasında 2 koridor boşluğu)',
                        icon: Icons.grid_on_rounded,
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyPreset('3_col_double_with_aisles');
                        },
                      ),
                      const Divider(height: 1),
                      _buildPresetOption(
                        title: 'Klasik U Düzeni',
                        subtitle: 'Etkileşimli seminer / atölye U yerleşimi (Tekli masalar)',
                        icon: Icons.crop_square_rounded,
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyPreset('u_shape');
                        },
                      ),
                      const Divider(height: 1),
                      _buildPresetOption(
                        title: '2 Blok Tekli Sıra (Bireysel)',
                        subtitle: '5 Satır x 3 Sütun tekli sınav/çalışma düzeni',
                        icon: Icons.table_restaurant_rounded,
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyPreset('2_col_single');
                        },
                      ),
                      const Divider(height: 1),
                      _buildPresetOption(
                        title: 'Grup Çalışma Masaları',
                        subtitle: '3x3 grid üzerinde 4 adet büyük küme masası',
                        icon: Icons.groups_rounded,
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyPreset('group_tables');
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Kapat'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF5C6BC0).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF5C6BC0), size: 22),
      ),
      title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
