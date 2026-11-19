import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/school/inventory_procurement_models.dart';
import '../../../services/inventory_procurement_service.dart';
import 'inventory_ui_widgets.dart';

/// Öğretmen ve personelin saniyeler içinde malzeme talebi oluşturabileceği tam alttan açılan modern form.
class MaterialRequestFormSheet extends StatefulWidget {
  final String institutionId;
  final String schoolDocId;
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;
  final List<({String id, String name})> schoolTypeOptions;
  final List<InventoryItemModel> catalogSuggestions;
  final bool isTeacherMode;

  const MaterialRequestFormSheet({
    super.key,
    required this.institutionId,
    required this.schoolDocId,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
    this.schoolTypeOptions = const [],
    this.catalogSuggestions = const [],
    this.isTeacherMode = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String institutionId,
    required String schoolDocId,
    String? fixedSchoolTypeId,
    String? fixedSchoolTypeName,
    List<({String id, String name})> schoolTypeOptions = const [],
    List<InventoryItemModel> catalogSuggestions = const [],
    bool isTeacherMode = false,
  }) {
    return showInventoryBottomSheet<bool>(
      context: context,
      maxWidth: 680,
      builder: (_) => MaterialRequestFormSheet(
        institutionId: institutionId,
        schoolDocId: schoolDocId,
        fixedSchoolTypeId: fixedSchoolTypeId,
        fixedSchoolTypeName: fixedSchoolTypeName,
        schoolTypeOptions: schoolTypeOptions,
        catalogSuggestions: isTeacherMode ? const [] : catalogSuggestions,
        isTeacherMode: isTeacherMode,
      ),
    );
  }

  @override
  State<MaterialRequestFormSheet> createState() =>
      _MaterialRequestFormSheetState();
}

class _MaterialRequestFormSheetState extends State<MaterialRequestFormSheet> {
  static const List<({String name, String unit, String category})>
      _teacherQuickPresets = [
    (
      name: 'Beyaz Tahta Kalemi',
      unit: 'Kutu',
      category: 'Kırtasiye & Ofis',
    ),
    (
      name: 'A4 Fotokopi Kağıdı',
      unit: 'Top',
      category: 'Kırtasiye & Ofis',
    ),
    (
      name: 'Tahta Silgisi',
      unit: 'Adet',
      category: 'Kırtasiye & Ofis',
    ),
    (
      name: 'Fon Kartonu',
      unit: 'Paket',
      category: 'Kırtasiye & Ofis',
    ),
    (
      name: 'Kırmızı Kalem',
      unit: 'Adet',
      category: 'Kırtasiye & Ofis',
    ),
    (
      name: 'Kalem Pil (AA / AAA)',
      unit: 'Paket',
      category: 'Bilişim & Elektronik',
    ),
  ];

  final _formKey = GlobalKey<FormState>();
  final _service = InventoryProcurementService();

  final _itemNameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _linkCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _selectedUnit = 'Adet';
  String _selectedCategory = InventoryItemModel.defaultCategories.first;
  String _urgency = 'normal';
  String _selectedSchoolTypeId = '';
  String _selectedSchoolTypeName = '';

  InventoryItemModel? _matchedCatalogItem;
  final List<String> _uploadedImageUrls = [];
  bool _uploadingImage = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedSchoolTypeId = (widget.fixedSchoolTypeId ?? '').trim();
    _selectedSchoolTypeName = (widget.fixedSchoolTypeName ?? '').trim();
    if (_selectedSchoolTypeId.isEmpty && widget.schoolTypeOptions.isNotEmpty) {
      _selectedSchoolTypeId = widget.schoolTypeOptions.first.id;
      _selectedSchoolTypeName = widget.schoolTypeOptions.first.name;
    }
  }

  @override
  void dispose() {
    _itemNameCtrl.dispose();
    _qtyCtrl.dispose();
    _linkCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _stepQuantity(int delta) {
    final cur =
        double.tryParse(_qtyCtrl.text.replaceAll(',', '.').trim()) ?? 1;
    final next = (cur + delta).clamp(1, 99999).toDouble();
    setState(() {
      _qtyCtrl.text = InventoryItemModel.formatQty(next);
    });
  }

  List<InventoryItemModel> _getMatchingCatalogItems() {
    if (widget.isTeacherMode || widget.catalogSuggestions.isEmpty) {
      return const [];
    }
    final q = InventoryItemModel.normalizeTr(_itemNameCtrl.text);
    final seen = <String>{};
    final res = <InventoryItemModel>[];
    for (final item in widget.catalogSuggestions) {
      if ((q.isEmpty || item.normalizedName.contains(q)) &&
          seen.add(item.normalizedName)) {
        res.add(item);
        if (res.length >= 6) break;
      }
    }
    return res;
  }

  Future<void> _pickFromCamera() async {
    if (kIsWeb) {
      await _pickFromGalleryOrFiles();
      return;
    }
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 78,
        maxWidth: 1600,
      );
      if (xfile == null) return;
      setState(() => _uploadingImage = true);
      final bytes = await xfile.readAsBytes();
      final url = await _service.uploadAttachmentBytes(
        schoolDocId: widget.schoolDocId,
        bytes: bytes,
        fileName: xfile.name.isNotEmpty ? xfile.name : 'photo.jpg',
      );
      if (mounted) {
        setState(() {
          _uploadedImageUrls.add(url);
          _uploadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf yüklenemedi: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _pickFromGalleryOrFiles() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      if (file.bytes == null) return;

      setState(() => _uploadingImage = true);
      final url = await _service.uploadAttachmentBytes(
        schoolDocId: widget.schoolDocId,
        bytes: file.bytes!,
        fileName: file.name,
      );
      if (mounted) {
        setState(() {
          _uploadedImageUrls.add(url);
          _uploadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Görsel yüklenemedi: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final qty =
        double.tryParse(_qtyCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen geçerli bir miktar giriniz.'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final actor = await _service.resolveCurrentActor(
        fallbackInstitutionId: widget.institutionId,
      );

      await _service.createMaterialRequest(
        institutionId: widget.institutionId,
        schoolDocId: widget.schoolDocId,
        schoolTypeId: _selectedSchoolTypeId,
        schoolTypeName: _selectedSchoolTypeName,
        requesterUid: actor.uid,
        requesterName: actor.name,
        requesterRole: actor.role,
        linkedItemId: widget.isTeacherMode ? '' : (_matchedCatalogItem?.id ?? ''),
        targetWarehouseId:
            widget.isTeacherMode ? '' : (_matchedCatalogItem?.warehouseId ?? ''),
        targetWarehouseName: widget.isTeacherMode
            ? ''
            : (_matchedCatalogItem?.warehouseName ?? ''),
        itemName: _itemNameCtrl.text.trim(),
        category: _selectedCategory,
        quantity: qty,
        unit: _selectedUnit,
        urgency: _urgency,
        productLink: _linkCtrl.text.trim(),
        imageUrls: _uploadedImageUrls,
        description: _descCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogSuggestions = _getMatchingCatalogItems();
    final showStaticPresets = catalogSuggestions.isEmpty;

    return InventoryBottomSheetFrame(
      title: widget.isTeacherMode
          ? 'Yeni Malzeme Talebi'
          : 'Malzeme / Satın Alma Talebi',
      subtitle: widget.isTeacherMode
          ? 'İhtiyacınız olan malzeme bilgilerini girerek talebinizi iletin.'
          : 'Depoda varsa depodan teslim edilir, yoksa onay ile satın alınır.',
      icon: Icons.add_shopping_cart_rounded,
      accentColor: const Color(0xFF4F46E5),
      footer: SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton.icon(
          onPressed: (_submitting || _uploadingImage) ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send_rounded, size: 19),
          label: Text(
            _submitting ? 'Talebiniz İletiliyor...' : 'Talebi Oluştur ve Gönder',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Birden fazla okul türü varsa seçim
            if ((widget.fixedSchoolTypeId ?? '').isEmpty &&
                widget.schoolTypeOptions.length > 1) ...[
              InventoryDropdownField<String>(
                label: 'İlgili Okul Türü / Birim',
                icon: Icons.apartment_rounded,
                value: _selectedSchoolTypeId.isNotEmpty
                    ? _selectedSchoolTypeId
                    : null,
                items: widget.schoolTypeOptions
                    .map(
                      (st) => DropdownMenuItem(
                        value: st.id,
                        child: Text(st.name),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  final found = widget.schoolTypeOptions
                      .where((e) => e.id == val)
                      .firstOrNull;
                  setState(() {
                    _selectedSchoolTypeId = val;
                    _selectedSchoolTypeName = found?.name ?? '';
                  });
                },
              ),
              const SizedBox(height: 16),
            ],

            // Malzeme Adı
            InventoryTextField(
              controller: _itemNameCtrl,
              label: 'İstenen Malzeme Adı',
              isRequired: true,
              hint: 'Örn: Beyaz Tahta Kalemi, A4 Kağıt, Deney Tüpü...',
              icon: Icons.inventory_2_outlined,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Lütfen malzeme adını yazınız'
                  : null,
              onChanged: (v) {
                if (widget.isTeacherMode) {
                  setState(() {});
                  return;
                }
                final norm = InventoryItemModel.normalizeTr(v);
                final exact = widget.catalogSuggestions
                    .where((e) => e.normalizedName == norm)
                    .firstOrNull;
                setState(() {
                  _matchedCatalogItem = exact;
                  if (exact != null) {
                    _selectedUnit = exact.unit;
                    _selectedCategory = exact.category;
                  }
                });
              },
            ),

            // Hızlı Seçim Çipleri (Öğretmen modunda statik, yönetim modunda katalog)
            const SizedBox(height: 10),
            if (showStaticPresets)
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: _teacherQuickPresets.map((preset) {
                  final active =
                      _itemNameCtrl.text.trim() == preset.name;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        _itemNameCtrl.text = preset.name;
                        _selectedUnit = preset.unit;
                        _selectedCategory = preset.category;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFEEF2FF)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active
                              ? const Color(0xFF6366F1)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            active
                                ? Icons.check_circle_rounded
                                : Icons.auto_awesome_rounded,
                            size: 13.5,
                            color: active
                                ? const Color(0xFF4F46E5)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            preset.name,
                            style: TextStyle(
                              fontSize: 11.8,
                              fontWeight:
                                  active ? FontWeight.w700 : FontWeight.w600,
                              color: active
                                  ? const Color(0xFF312E81)
                                  : const Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              )
            else
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: catalogSuggestions.map((item) {
                  final isSelected = _matchedCatalogItem?.id == item.id;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        _matchedCatalogItem = item;
                        _itemNameCtrl.text = item.name;
                        _selectedUnit = item.unit;
                        _selectedCategory = item.category;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFEEF2FF)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF6366F1)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        '${item.name} (${item.unit})',
                        style: TextStyle(
                          fontSize: 11.8,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: 18),

            // Miktar + Birim Satırı
            const InventoryFieldLabel('Miktar ve Birim', isRequired: true),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 49,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFD5DFEC),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StepperIconButton(
                        icon: Icons.remove_rounded,
                        onTap: () => _stepQuantity(-1),
                      ),
                      SizedBox(
                        width: 68,
                        child: TextFormField(
                          controller: _qtyCtrl,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      _StepperIconButton(
                        icon: Icons.add_rounded,
                        onTap: () => _stepQuantity(1),
                        isPrimary: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InventoryDropdownField<String>(
                    icon: Icons.straighten_rounded,
                    value: InventoryItemModel.defaultUnits
                            .contains(_selectedUnit)
                        ? _selectedUnit
                        : InventoryItemModel.defaultUnits.first,
                    items: InventoryItemModel.defaultUnits
                        .map(
                          (u) => DropdownMenuItem(value: u, child: Text(u)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedUnit = v);
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Kategori & Aciliyet Durumu
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 460;
                final categoryField = InventoryDropdownField<String>(
                  label: 'Malzeme Kategorisi',
                  icon: Icons.category_outlined,
                  value: InventoryItemModel.defaultCategories
                          .contains(_selectedCategory)
                      ? _selectedCategory
                      : InventoryItemModel.defaultCategories.first,
                  items: InventoryItemModel.defaultCategories
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedCategory = v);
                  },
                );

                final urgencySelector = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const InventoryFieldLabel('Öncelik Durumu'),
                    Row(
                      children: [
                        Expanded(
                          child: _UrgencyOptionTile(
                            label: 'Normal',
                            icon: Icons.schedule_rounded,
                            selected: _urgency == 'normal',
                            activeColor: const Color(0xFF4F46E5),
                            onTap: () => setState(() => _urgency = 'normal'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _UrgencyOptionTile(
                            label: 'Acil',
                            icon: Icons.bolt_rounded,
                            selected: _urgency == 'urgent',
                            activeColor: const Color(0xFFDC2626),
                            onTap: () => setState(() => _urgency = 'urgent'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );

                if (narrow) {
                  return Column(
                    children: [
                      categoryField,
                      const SizedBox(height: 14),
                      urgencySelector,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: categoryField),
                    const SizedBox(width: 12),
                    Expanded(flex: 4, child: urgencySelector),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),

            // Örnek Ürün Linki
            InventoryTextField(
              controller: _linkCtrl,
              label: 'Örnek Ürün Linki',
              trailingText: 'İsteğe Bağlı',
              hint: 'https://... (Varsa marka/model referans linki)',
              icon: Icons.link_rounded,
              keyboardType: TextInputType.url,
            ),

            const SizedBox(height: 16),

            // Açıklama
            InventoryTextField(
              controller: _descCtrl,
              label: 'Açıklama / Kullanım Notu',
              trailingText: 'İsteğe Bağlı',
              hint:
                  'Örn: 8-A sınıfı fen deneyi için Perşembe gününe kadar gerekli...',
              icon: Icons.notes_rounded,
              maxLines: 3,
              minLines: 2,
            ),

            const SizedBox(height: 16),

            // Görsel / Fotoğraf Yükleme Alanı
            const InventoryFieldLabel(
              'Görsel veya Fotoğraf Ekle',
              trailingText: 'İsteğe Bağlı',
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD5DFEC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (!kIsWeb) ...[
                        Expanded(
                          child: _UploadActionButton(
                            icon: Icons.camera_alt_outlined,
                            label: 'Fotoğraf Çek',
                            onTap: _uploadingImage ? null : _pickFromCamera,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: _UploadActionButton(
                          icon: Icons.add_photo_alternate_outlined,
                          label: kIsWeb
                              ? 'Bilgisayardan Görsel Seç'
                              : 'Galeriden Seç',
                          onTap:
                              _uploadingImage ? null : _pickFromGalleryOrFiles,
                        ),
                      ),
                    ],
                  ),
                  if (_uploadingImage) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(minHeight: 3),
                  ],
                  if (_uploadedImageUrls.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _uploadedImageUrls.asMap().entries.map((entry) {
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                entry.value,
                                width: 68,
                                height: 68,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 68,
                                  height: 68,
                                  color: const Color(0xFFE2E8F0),
                                  child: const Icon(Icons.image_outlined),
                                ),
                              ),
                            ),
                            Positioned(
                              top: -6,
                              right: -6,
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _uploadedImageUrls.removeAt(entry.key);
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFDC2626),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _StepperIconButton({
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFFEEF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isPrimary
                ? const Color(0xFFC7D2FE)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: Icon(
          icon,
          size: 19,
          color: isPrimary ? const Color(0xFF4F46E5) : const Color(0xFF334155),
        ),
      ),
    );
  }
}

class _UrgencyOptionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  const _UrgencyOptionTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 49,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.10)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? activeColor : const Color(0xFFD5DFEC),
            width: selected ? 1.7 : 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? activeColor : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected ? activeColor : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _UploadActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF4F46E5)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.8,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
