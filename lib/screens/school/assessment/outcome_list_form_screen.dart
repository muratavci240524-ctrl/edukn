import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // for compute
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'dart:typed_data';
import '../../../services/assessment_service.dart';
import '../../../models/assessment/outcome_list_model.dart';

class OutcomeListForm extends StatefulWidget {
  final String institutionId;
  final OutcomeList? outcomeList;
  final VoidCallback onSaved;
  final VoidCallback onCancelled;

  const OutcomeListForm({
    Key? key,
    required this.institutionId,
    this.outcomeList,
    required this.onSaved,
    required this.onCancelled,
  }) : super(key: key);

  @override
  _OutcomeListFormState createState() => _OutcomeListFormState();
}

class _OutcomeListFormState extends State<OutcomeListForm> {
  final _formKey = GlobalKey<FormState>();
  final AssessmentService _service = AssessmentService();

  late TextEditingController _nameController;
  String? _selectedClassLevel;
  String? _selectedBranch;

  List<OutcomeItem> _outcomes = [];
  List<String> _availableBranches = [];
  List<String> _classLevels = [
    '1. Sınıf',
    '2. Sınıf',
    '3. Sınıf',
    '4. Sınıf',
    '5. Sınıf',
    '6. Sınıf',
    '7. Sınıf',
    '8. Sınıf',
    '9. Sınıf',
    '10. Sınıf',
    '11. Sınıf',
    '12. Sınıf',
    'Hazırlık',
    'Mezun',
  ];

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initForm();
    _loadBranches();
  }

  @override
  void didUpdateWidget(covariant OutcomeListForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.outcomeList?.id != widget.outcomeList?.id) {
      _initForm();
    }
  }

  void _initForm() {
    _nameController = TextEditingController(
      text: widget.outcomeList?.name ?? '',
    );

    if (widget.outcomeList != null) {
      _selectedClassLevel = widget.outcomeList!.classLevel;
      _selectedBranch = widget.outcomeList!.branchName;
      _outcomes = List.from(widget.outcomeList!.outcomes);
    } else {
      _selectedClassLevel = null;
      _selectedBranch = null;
      _outcomes = [];
    }
    if (widget.outcomeList == null) {
      _nameController.text = '';
    }
  }

  Future<void> _loadBranches() async {
    final branches = await _service.getAvailableBranches(widget.institutionId);
    if (mounted) {
      setState(() {
        _availableBranches = branches;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addOutcome() {
    setState(() {
      int newDepth = _outcomes.isNotEmpty ? _outcomes.last.depth : 1;
      _outcomes.add(
        OutcomeItem(code: '', description: '', depth: newDepth, k12Code: ''),
      );
    });
  }

  void _removeOutcome(int index) {
    setState(() {
      _outcomes.removeAt(index);
    });
  }

  void _updateOutcome(
    int index, {
    String? code,
    String? description,
    int? depth,
    String? k12Code,
  }) {
    final old = _outcomes[index];
    final newItem = OutcomeItem(
      code: code ?? old.code,
      description: description ?? old.description,
      depth: depth ?? old.depth,
      k12Code: k12Code ?? old.k12Code,
    );

    _outcomes[index] = newItem;

    // Only rebuild if visual structure changes (depth affects indentation/style)
    if (depth != null && depth != old.depth) {
      setState(() {});
    }
  }

  // --- Excel Operations ---

  void _clearList() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Listeyi Temizle'),
        content: Text('Tüm kazanımlar silinecek. Emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _outcomes.clear();
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Temizle'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadTemplate() async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Sheet1'];

    // Headers
    List<TextCellValue> headers = [
      TextCellValue('Derinlik'),
      TextCellValue('K12 Kodu'),
      TextCellValue('Kod'),
      TextCellValue('Açıklama'),
    ];
    sheetObject.appendRow(headers);

    // Sample Data
    List<TextCellValue> row1 = [
      TextCellValue('1'),
      TextCellValue(''), // Topic Heading usually has no K12 Code
      TextCellValue('M.8.1'),
      TextCellValue('Çarpanlar ve Katlar (Konu Başlığı)'),
    ];
    sheetObject.appendRow(row1);

    List<TextCellValue> row2 = [
      TextCellValue('2'),
      TextCellValue('M.8.1.1.1'),
      TextCellValue('1.1'),
      TextCellValue('Üslü ifadelerle ilgili temel kuralları anlar.'),
    ];
    sheetObject.appendRow(row2);

    var fileBytes = excel.save();
    if (fileBytes != null) {
      await FileSaver.instance.saveFile(
        name: 'kazanim_sablon',
        bytes: Uint8List.fromList(fileBytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  Future<void> _exportExcel() async {
    if (_outcomes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dışa aktarılacak kazanım yok.')));
      return;
    }

    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Sheet1'];

    // Headers
    List<TextCellValue> headers = [
      TextCellValue('Derinlik'),
      TextCellValue('K12 Kodu'),
      TextCellValue('Kod'),
      TextCellValue('Açıklama'),
    ];
    sheetObject.appendRow(headers);

    for (var outcome in _outcomes) {
      List<TextCellValue> row = [
        TextCellValue(outcome.depth.toString()),
        TextCellValue(outcome.k12Code),
        TextCellValue(outcome.code),
        TextCellValue(outcome.description),
      ];
      sheetObject.appendRow(row);
    }

    String fileName = _nameController.text.isNotEmpty
        ? _nameController.text
        : 'kazanim_listesi';

    var fileBytes = excel.save();
    if (fileBytes != null) {
      await FileSaver.instance.saveFile(
        name: fileName,
        bytes: Uint8List.fromList(fileBytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  Future<void> _importExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result != null) {
        setState(() {
          _isLoading = true;
        });

        // Short delay to allow UI to update
        await Future.delayed(Duration(milliseconds: 100));

        var bytes = result.files.single.bytes;
        if (bytes != null) {
          // Offload parsing to isolate
          List<OutcomeItem> newOutcomes = await compute(
            _parseExcelContent,
            bytes,
          );

          if (newOutcomes.isNotEmpty) {
            setState(() {
              _outcomes.addAll(newOutcomes);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${newOutcomes.length} kazanım eklendi.')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Dosyadan okunacak veri bulunamadı.')),
            );
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      String name = _nameController.text.trim();
      if (name.isEmpty) {
        name = '$_selectedClassLevel - $_selectedBranch Kazanımları';
      }

      final list = OutcomeList(
        id: widget.outcomeList?.id ?? '',
        institutionId: widget.institutionId,
        name: name,
        branchName: _selectedBranch!,
        classLevel: _selectedClassLevel!,
        outcomes: _outcomes,
        isActive: true,
      );

      await _service.saveOutcomeList(list);
      widget.onSaved();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kazanım listesi kaydedildi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        return Column(
          children: [
            // Header (Action Bar)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.outcomeList == null
                          ? 'Yeni Kazanım Listesi'
                          : 'Listeyi Düzenle',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  SizedBox(width: 8),
                  if (isMobile)
                    IconButton(
                      onPressed: widget.onCancelled,
                      icon: Icon(Icons.close, color: Colors.grey[700]),
                      tooltip: 'Vazgeç',
                    )
                  else
                    TextButton(
                      onPressed: widget.onCancelled,
                      child: Text(
                        'Vazgeç',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ),
                  SizedBox(width: isMobile ? 4 : 12),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _save,
                    icon: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(Icons.save),
                    label: Text(isMobile ? 'Kaydet' : 'Kaydet'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 12 : 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Body (Virtualizing List)
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'İşlem yapılıyor, lütfen bekleyin...',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : Form(
                      key: _formKey,
                      child: ReorderableListView.builder(
                        padding: EdgeInsets.only(bottom: 100),
                        buildDefaultDragHandles: false,
                        header: Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.all(24),
                              child: _buildGeneralInfoCard(isMobile),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 8,
                              ),
                              child: _buildToolbar(isMobile),
                            ),
                          ],
                        ),
                        itemCount: _outcomes.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = _outcomes.removeAt(oldIndex);
                            _outcomes.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final outcome = _outcomes[index];
                          final isTopic = outcome.depth == 1;
                          return Padding(
                            key: ValueKey(outcome.hashCode),
                            padding: EdgeInsets.symmetric(horizontal: 24),
                            child: _buildOutcomeItem(
                              index,
                              outcome,
                              isTopic,
                              isMobile,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  InputDecoration _inputDecoration(
    String label, {
    String? hint,
    String? helper,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.indigo, width: 2),
      ),
    );
  }

  Widget _buildGeneralInfoCard(bool isMobile) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.info_outline, color: Colors.indigo),
                ),
                SizedBox(width: 12),
                Text(
                  'Genel Bilgiler',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            Divider(height: 32),
            if (isMobile) ...[
              DropdownButtonFormField<String>(
                value: _selectedClassLevel,
                decoration: _inputDecoration('Sınıf Seviyesi'),
                items: _classLevels
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedClassLevel = v),
                validator: (v) => v == null ? 'Zorunlu' : null,
              ),
              SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedBranch,
                decoration: _inputDecoration('Ders (Branş)'),
                isExpanded: true,
                items: _availableBranches
                    .map(
                      (b) => DropdownMenuItem(
                        value: b,
                        child: Text(b, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedBranch = v),
                validator: (v) => v == null ? 'Zorunlu' : null,
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedClassLevel,
                      decoration: _inputDecoration('Sınıf Seviyesi'),
                      items: _classLevels
                          .map(
                            (l) => DropdownMenuItem(value: l, child: Text(l)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedClassLevel = v),
                      validator: (v) => v == null ? 'Zorunlu' : null,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedBranch,
                      decoration: _inputDecoration('Ders (Branş)'),
                      isExpanded: true,
                      items: _availableBranches
                          .map(
                            (b) => DropdownMenuItem(
                              value: b,
                              child: Text(b, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedBranch = v),
                      validator: (v) => v == null ? 'Zorunlu' : null,
                    ),
                  ),
                ],
              ),
            SizedBox(height: 20),
            TextFormField(
              controller: _nameController,
              decoration: _inputDecoration(
                'Liste Adı (Opsiyonel)',
                hint: 'Örn: 8. Sınıf Matematik 1. Dönem Kazanımları',
                helper: 'Boş bırakılırsa "Sınıf - Ders" olarak adlandırılır',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(bool isMobile) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.list_alt, color: Colors.teal),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Kazanımlar (${_outcomes.length})',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                SizedBox(width: 8),
                if (isMobile)
                  IconButton(
                    onPressed: _addOutcome,
                    icon: Icon(Icons.add_circle, color: Colors.teal, size: 30),
                    tooltip: 'Kazanım Ekle',
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _addOutcome,
                    icon: Icon(Icons.add, size: 20),
                    label: Text('Kazanım Ekle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                SizedBox(width: 8),

                // Removed Match Button
                SizedBox(width: 8),

                // More Options (Excel + Clear)
                PopupMenuButton<String>(
                  icon: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.more_vert, color: Colors.grey[700]),
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'template':
                        _downloadTemplate();
                        break;
                      case 'upload':
                        _importExcel();
                        break;
                      case 'download':
                        _exportExcel();
                        break;
                      case 'clear':
                        _clearList();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'template',
                      child: Row(
                        children: [
                          Icon(
                            Icons.file_download,
                            size: 20,
                            color: Colors.grey[700],
                          ),
                          SizedBox(width: 8),
                          Text('Örnek Şablon İndir'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'upload',
                      child: Row(
                        children: [
                          Icon(Icons.upload_file, size: 20, color: Colors.teal),
                          SizedBox(width: 8),
                          Text('Excel Yükle'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'download',
                      child: Row(
                        children: [
                          Icon(Icons.download, size: 20, color: Colors.indigo),
                          SizedBox(width: 8),
                          Text('Excel Olarak İndir'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'clear',
                      child: Row(
                        children: [
                          Icon(Icons.delete_sweep, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text(
                            'Listeyi Temizle',
                            style: TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Divider(height: 24),
            if (_outcomes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.format_list_bulleted_add,
                      size: 48,
                      color: Colors.grey[300],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Henüz kazanım eklenmemiş.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutcomeItem(
    int index,
    OutcomeItem outcome,
    bool isTopic,
    bool isMobile,
  ) {
    // Common Widgets
    Widget dragHandle = !isMobile
        ? ReorderableDragStartListener(
            index: index,
            child: Container(
              width: 32,
              height: 32,
              margin: EdgeInsets.only(top: 8, right: 8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.drag_indicator,
                color: Colors.grey[400],
                size: 20,
              ),
            ),
          )
        : SizedBox.shrink();

    Widget deleteButton = Container(
      margin: EdgeInsets.only(top: 4, left: isMobile ? 8 : 4),
      child: IconButton(
        icon: Icon(Icons.delete_rounded, color: Colors.red.shade300, size: 22),
        constraints: BoxConstraints(),
        padding: EdgeInsets.all(8),
        style: IconButton.styleFrom(
          backgroundColor: Colors.red.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () => _removeOutcome(index),
      ),
    );

    Widget depthDropdown = SizedBox(
      width: 80,
      child: DropdownButtonFormField<int>(
        value: outcome.depth,
        decoration: _inputDecoration('Tip').copyWith(
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        ),
        isExpanded: true,
        icon: Icon(Icons.arrow_drop_down, size: 20),
        items: List.generate(5, (i) {
          final val = i + 1;
          return DropdownMenuItem(
            value: val,
            child: Center(
              child: Text(
                "$val",
                style: TextStyle(
                  fontWeight: val == 1 ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
          );
        }),
        onChanged: (val) {
          if (val != null) {
            _updateOutcome(index, depth: val);
          }
        },
      ),
    );

    Widget k12Input = TextFormField(
      initialValue: outcome.k12Code,
      decoration: _inputDecoration('K12', hint: 'M.8.1...'),
      style: TextStyle(fontSize: 14),
      onChanged: (v) => _updateOutcome(index, k12Code: v),
    );

    Widget codeInput = TextFormField(
      initialValue: outcome.code,
      decoration: _inputDecoration('Kod', hint: '1.1'),
      style: TextStyle(
        fontSize: 14,
        fontWeight: isTopic ? FontWeight.bold : FontWeight.normal,
      ),
      onChanged: (v) => _updateOutcome(index, code: v),
    );

    Widget descInput = TextFormField(
      initialValue: outcome.description,
      decoration: _inputDecoration(
        'Açıklama',
        hint: isTopic ? 'Konu Başlığı' : 'Tanım',
      ),
      maxLines: null,
      minLines: 1,
      style: TextStyle(
        fontSize: 14,
        fontWeight: isTopic ? FontWeight.bold : FontWeight.normal,
      ),
      onChanged: (v) => _updateOutcome(index, description: v),
    );

    return Container(
      margin: EdgeInsets.only(bottom: 12, left: (outcome.depth - 1) * 24.0),
      decoration: BoxDecoration(
        color: isTopic ? Colors.blue.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTopic ? Colors.blue.shade200 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
        child: isMobile
            ? Column(
                children: [
                  Row(
                    children: [
                      if (!isMobile)
                        dragHandle, // Shouldn't happen based on logic but safe
                      Expanded(child: depthDropdown),
                      SizedBox(width: 8),
                      Expanded(child: k12Input),
                      SizedBox(width: 8),
                      Expanded(child: codeInput),
                      if (isMobile) deleteButton,
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(children: [Expanded(child: descInput)]),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  dragHandle,
                  // Depth
                  depthDropdown,
                  SizedBox(width: 8),
                  // K12
                  SizedBox(width: 100, child: k12Input),
                  SizedBox(width: 8),
                  // Code
                  SizedBox(width: isMobile ? 70 : 80, child: codeInput),
                  SizedBox(width: 8),
                  // Description
                  Expanded(child: descInput),
                  SizedBox(width: 4),
                  deleteButton,
                ],
              ),
      ),
    );
  }
}

List<OutcomeItem> _parseExcelContent(List<int> bytes) {
  var excel = Excel.decodeBytes(bytes);
  var table = excel.tables.keys.first;
  var sheet = excel.tables[table];

  if (sheet == null) return [];

  List<OutcomeItem> newOutcomes = [];

  // Determine start row and column mapping
  int startRow = 0;
  bool hasHeader = false;
  int colDepth = 0;
  int colK12 = -1;
  int colCode = 1; // Default if no K12
  int colDesc = 2; // Default if no K12

  if (sheet.maxRows > 0) {
    var firstRow = sheet.row(0);
    // Simple header check
    if (firstRow.isNotEmpty &&
        (firstRow[0]?.value?.toString().toLowerCase() ?? '').contains(
          'derinlik',
        )) {
      startRow = 1;
      hasHeader = true;

      // Dynamic column finding
      for (int c = 0; c < firstRow.length; c++) {
        String header = firstRow[c]?.value?.toString().toLowerCase() ?? '';
        if (header.contains('derinlik'))
          colDepth = c;
        else if (header.contains('k12'))
          colK12 = c;
        else if (header == 'kod')
          colCode = c;
        else if (header.contains('açıklama'))
          colDesc = c;
      }
    }
  }

  // Fallback for old template (Depth, Code, Description)
  if (hasHeader && colK12 == -1) {
    // If header exists but no K12 found, assume standard 3 col
    // We already mapped them above if names matched, otherwise defaults apply
  }

  for (int i = startRow; i < sheet.maxRows; i++) {
    var row = sheet.row(i);
    if (row.isEmpty) continue;

    try {
      // Safe access
      String getValue(int idx) {
        if (idx >= 0 && idx < row.length) {
          return row[idx]?.value?.toString() ?? '';
        }
        return '';
      }

      String depthStr = getValue(colDepth);
      if (depthStr.isEmpty) depthStr = '2'; // Default

      String k12Code = colK12 != -1 ? getValue(colK12) : '';
      String code = getValue(colCode);
      String description = getValue(colDesc);

      // If no dynamic mapping (no header found), assume:
      // 3 cols: Depth, Code, Desc
      // 2 cols: Code, Desc
      if (!hasHeader) {
        if (row.length >= 3) {
          depthStr = row[0]?.value.toString() ?? '2';
          code = row[1]?.value.toString() ?? '';
          description = row[2]?.value.toString() ?? '';
        } else if (row.length >= 2) {
          code = row[0]?.value.toString() ?? '';
          description = row[1]?.value.toString() ?? '';
          depthStr = '2';
        }
      }

      int depth = int.tryParse(depthStr) ?? 2;

      if (code.isNotEmpty || description.isNotEmpty || k12Code.isNotEmpty) {
        newOutcomes.add(
          OutcomeItem(
            code: code,
            description: description,
            depth: depth,
            k12Code: k12Code,
          ),
        );
      }
    } catch (e) {
      print("Row parse error: $e");
    }
  }
  return newOutcomes;
}
