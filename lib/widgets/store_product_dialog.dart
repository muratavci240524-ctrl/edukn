import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/store/store_models.dart';

/// Mağaza ürün görsellerini hem Firebase Storage hem de dış web bağlantılarında
/// (CORS engeline takılmadan) güvenle gösteren ortak bileşen.
class StoreProductImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? fallback;

  const StoreProductImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final cleanUrl = StoreImageUrlHelper.normalize(url);
    final fallbackWidget =
        fallback ??
        Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade400),
        );
    if (cleanUrl.isEmpty) return fallbackWidget;

    final isFirebaseStorage =
        cleanUrl.contains('firebasestorage.googleapis.com') ||
        cleanUrl.contains('.firebasestorage.app');

    return IgnorePointer(
      child: Image.network(
        cleanUrl,
        key: ValueKey(cleanUrl),
        width: width,
        height: height,
        fit: fit,
        webHtmlElementStrategy: isFirebaseStorage
            ? WebHtmlElementStrategy.fallback
            : WebHtmlElementStrategy.prefer,
        errorBuilder: (_, __, ___) => fallbackWidget,
      ),
    );
  }
}

/// Ürün formundaki tüm değerleri taşıyan veri nesnesi.
class ProductFormData {
  String title = '';
  String description = '';
  String category;
  double price = 0;
  double? discountedPrice;
  int vatRate;
  int stock = 0;
  bool isActive;
  List<String> variants;
  List<String> imageUrls;
  Set<String> targetRoles;
  bool targetAllSchools;
  Set<String> targetSchoolIds;
  bool targetAllSchoolTypes;
  Set<String> targetCategories;
  Set<String> targetSchoolTypeIds;
  bool targetAllClassLevels;
  Set<String> targetClassLevels;
  bool targetAllClasses;
  Set<String> targetClassIds;
  Set<String> targetClassNames;
  bool allowPickupAtSchool;
  bool allowHomeDelivery;
  bool isMandatory;
  Set<String> mandatoryRoles;

  ProductFormData({
    required this.category,
    required this.vatRate,
    required this.isActive,
    required this.variants,
    required this.imageUrls,
    required this.targetRoles,
    required this.targetAllSchools,
    required this.targetSchoolIds,
    required this.targetAllSchoolTypes,
    required this.targetCategories,
    required this.targetSchoolTypeIds,
    this.targetAllClassLevels = true,
    Set<String>? targetClassLevels,
    this.targetAllClasses = true,
    Set<String>? targetClassIds,
    Set<String>? targetClassNames,
    this.allowPickupAtSchool = true,
    this.allowHomeDelivery = true,
    this.isMandatory = false,
    Set<String>? mandatoryRoles,
  }) : targetClassLevels = targetClassLevels ?? <String>{},
       targetClassIds = targetClassIds ?? <String>{},
       targetClassNames = targetClassNames ?? <String>{},
       mandatoryRoles =
           mandatoryRoles ??
           <String>{StoreBuyerRoles.veli, StoreBuyerRoles.ogrenci};
}

typedef ProductImageUploader =
    Future<String> Function(Uint8List bytes, String fileName);
typedef ProductSaveHandler = Future<void> Function(ProductFormData data);
typedef ProductTargetingBuilder =
    Widget Function(
      BuildContext context,
      ProductFormData data,
      VoidCallback refresh,
    );

/// Mağaza ürünü ekleme / düzenleme diyaloğu (HQ ve okul için ortak).
class StoreProductDialog extends StatefulWidget {
  final StoreProduct? existing;
  final String title;
  final String subtitle;
  final String defaultCategory;
  final int defaultStock;
  final ProductImageUploader uploadImage;
  final ProductSaveHandler onSave;
  final ProductTargetingBuilder targetingBuilder;
  final List<MapEntry<String, List<String>>> variantPresets;
  final List<StoreClassOption> availableClasses;

  const StoreProductDialog({
    super.key,
    required this.existing,
    required this.title,
    required this.subtitle,
    required this.defaultCategory,
    required this.defaultStock,
    required this.uploadImage,
    required this.onSave,
    required this.targetingBuilder,
    this.variantPresets = const [],
    this.availableClasses = const [],
  });

  @override
  State<StoreProductDialog> createState() => _StoreProductDialogState();
}

class _StoreProductDialogState extends State<StoreProductDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _discCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _variantCtrl;
  late final TextEditingController _imageUrlCtrl;
  late final TextEditingController _customClassCtrl;
  late final ProductFormData _data;

  bool _uploading = false;
  bool _saving = false;
  bool _showUrlField = false;
  String? _titleErr;
  String? _priceErr;
  String? _stockErr;
  String? _imageErr;
  String? _saveErr;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _priceCtrl = TextEditingController(
      text: e != null ? e.price.toStringAsFixed(2) : '',
    );
    _discCtrl = TextEditingController(
      text: e?.discountedPrice != null
          ? e!.discountedPrice!.toStringAsFixed(2)
          : '',
    );
    _stockCtrl = TextEditingController(
      text: (e?.stock ?? widget.defaultStock).toString(),
    );
    _variantCtrl = TextEditingController();
    _imageUrlCtrl = TextEditingController();
    _customClassCtrl = TextEditingController();
    _data = ProductFormData(
      category: e?.category ?? widget.defaultCategory,
      vatRate: e?.vatRate ?? 10,
      isActive: e?.isActive ?? true,
      variants: List<String>.from(e?.variants ?? []),
      imageUrls: StoreImageUrlHelper.normalizeList(e?.imageUrls ?? const []),
      targetRoles: Set<String>.from(e?.targetRoles ?? StoreBuyerRoles.all),
      targetAllSchools: e?.targetAllSchools ?? true,
      targetSchoolIds: Set<String>.from(e?.targetSchoolIds ?? []),
      targetAllSchoolTypes: e?.targetAllSchoolTypes ?? true,
      targetCategories: Set<String>.from(e?.targetSchoolTypeCategories ?? []),
      targetSchoolTypeIds: Set<String>.from(e?.targetSchoolTypeIds ?? []),
      targetAllClassLevels: e?.targetAllClassLevels ?? true,
      targetClassLevels: Set<String>.from(e?.targetClassLevels ?? []),
      targetAllClasses: e?.targetAllClasses ?? true,
      targetClassIds: Set<String>.from(e?.targetClassIds ?? []),
      targetClassNames: Set<String>.from(
        (e?.targetClassNames ?? const []).map(
          StoreClassLevels.normalizeClassToken,
        ),
      ),
      allowPickupAtSchool: e?.allowPickupAtSchool ?? true,
      allowHomeDelivery: e?.allowHomeDelivery ?? true,
      isMandatory: e?.isMandatory ?? false,
      mandatoryRoles: Set<String>.from(
        e?.mandatoryRoles ??
            const [StoreBuyerRoles.veli, StoreBuyerRoles.ogrenci],
      ),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _discCtrl.dispose();
    _stockCtrl.dispose();
    _variantCtrl.dispose();
    _imageUrlCtrl.dispose();
    _customClassCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  Future<void> _pickImage() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.first;
      if (file.bytes == null) return;
      setState(() {
        _uploading = true;
        _imageErr = null;
      });
      final url = await widget.uploadImage(file.bytes!, file.name);
      if (!mounted) return;
      final norm = StoreImageUrlHelper.normalize(url);
      setState(() {
        if (norm.isNotEmpty && !_data.imageUrls.contains(norm)) {
          _data.imageUrls.add(norm);
        }
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _imageErr = 'Görsel yüklenemedi: ${_readable(e)}';
      });
    }
  }

  bool _addUrl({bool silentIfEmpty = false}) {
    final raw = _imageUrlCtrl.text.trim();
    if (raw.isEmpty) {
      if (!silentIfEmpty) {
        setState(
          () => _imageErr = 'Lütfen geçerli bir resim bağlantısı girin.',
        );
      }
      return true;
    }
    final normalized = StoreImageUrlHelper.normalize(raw);
    if (normalized.isEmpty) {
      setState(() {
        _imageErr =
            'Geçersiz görsel bağlantısı. Lütfen https:// ile başlayan bir resim adresi yapıştırın.';
      });
      return false;
    }
    setState(() {
      if (!_data.imageUrls.contains(normalized)) {
        _data.imageUrls.add(normalized);
      }
      _imageUrlCtrl.clear();
      _showUrlField = false;
      _imageErr = null;
    });
    return true;
  }

  void _addCustomClassToken() {
    final raw = _customClassCtrl.text.trim();
    if (raw.isEmpty) return;
    final parts = raw
        .split(RegExp(r'[,;]+'))
        .map(StoreClassLevels.normalizeClassToken)
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    setState(() {
      _data.targetAllClasses = false;
      for (final p in parts) {
        _data.targetClassNames.add(p);
        for (final c in widget.availableClasses) {
          if (StoreClassLevels.normalizeClassToken(c.name) == p) {
            _data.targetClassIds.add(c.id);
          }
        }
      }
      _customClassCtrl.clear();
    });
  }

  String _readable(Object e) {
    var s = e.toString();
    if (s.startsWith('Exception: ')) s = s.substring(11);
    return s;
  }

  String _saveMessage(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('permission-denied') ||
        s.contains('permission_denied') ||
        s.contains('insufficient permissions')) {
      return 'Yetki hatası: Firestore kuralları güncel değil veya oturum yetkisi yok';
    }
    if (s.contains('network') || s.contains('unavailable')) {
      return 'Bağlantı hatası: İnternet bağlantınızı kontrol edip tekrar deneyin.';
    }
    return 'Ürün kaydedilemedi: ${_readable(e)}';
  }

  Future<void> _submit() async {
    // Bağlantı alanında yazılı kalmış URL varsa otomatik olarak ürün görsellerine dahil et
    if (_imageUrlCtrl.text.trim().isNotEmpty) {
      final ok = _addUrl(silentIfEmpty: true);
      if (!ok) return;
    }
    // Özel şube alanında yazılı kalmış şube kodu varsa otomatik dahil et
    if (!_data.targetAllClasses && _customClassCtrl.text.trim().isNotEmpty) {
      _addCustomClassToken();
    }

    final title = _titleCtrl.text.trim();
    final price = _parse(_priceCtrl.text);
    final stock = int.tryParse(_stockCtrl.text.trim());

    String? targetValidationErr;
    if (!_data.allowPickupAtSchool && !_data.allowHomeDelivery) {
      targetValidationErr =
          'Lütfen en az bir teslimat seçeneği (Okuldan Teslim veya Adrese Kargo) aktif bırakın.';
    } else if (_data.isMandatory && _data.mandatoryRoles.isEmpty) {
      targetValidationErr =
          'Zorunlu ürün seçildiğinde en az bir hedef rol (örn. Veli veya Öğrenci) işaretlenmelidir.';
    } else if (!_data.targetAllSchoolTypes &&
        _data.targetSchoolTypeIds.isEmpty &&
        _data.targetCategories.isEmpty) {
      targetValidationErr =
          'Lütfen en az bir okul türü (kademe) seçin veya "Tüm Okul Türlerine Göster" seçeneğini açın.';
    } else if (!_data.targetAllClassLevels && _data.targetClassLevels.isEmpty) {
      targetValidationErr =
          'Lütfen en az bir sınıf seviyesi seçin (örn. 5. Sınıf) veya "Tüm Sınıf Seviyelerine Göster" seçeneğini açın.';
    } else if (!_data.targetAllClasses &&
        _data.targetClassIds.isEmpty &&
        _data.targetClassNames.isEmpty) {
      targetValidationErr =
          'Lütfen en az bir şube seçin (örn. 5-A) veya "Tüm Şubelere Göster" seçeneğini açın.';
    }

    setState(() {
      _saveErr = targetValidationErr;
      _titleErr = title.isEmpty ? 'Ürün adı zorunludur' : null;
      _priceErr = (price == null || price <= 0)
          ? "Fiyat 0'dan büyük olmalıdır"
          : null;
      _stockErr = (stock == null || stock < 0)
          ? "Stok 0 veya daha büyük olmalıdır"
          : null;
    });
    if (_titleErr != null ||
        _priceErr != null ||
        _stockErr != null ||
        targetValidationErr != null) {
      return;
    }

    final disc = _parse(_discCtrl.text);
    _data
      ..title = title
      ..description = _descCtrl.text.trim()
      ..price = price!
      ..discountedPrice = (disc != null && disc > 0 && disc < price)
          ? disc
          : null
      ..stock = stock!;

    setState(() => _saving = true);
    try {
      await widget.onSave(_data);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveErr = _saveMessage(e);
      });
    }
  }

  // ───────────────────────── UI helpers ─────────────────────────

  InputDecoration _dec(
    String label, {
    String? hint,
    String? errorText,
    String? helperText,
    String? prefixText,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    OutlineInputBorder b(Color c, [double w = 1.1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );
    final primary = Theme.of(context).colorScheme.primary;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      errorMaxLines: 2,
      helperText: helperText,
      helperMaxLines: 2,
      prefixText: prefixText,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 19, color: primary.withValues(alpha: 0.78))
          : null,
      suffixIcon: suffixIcon,
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      labelStyle: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: Color(0xFF475569),
      ),
      floatingLabelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: b(const Color(0xFFCBD5E1)),
      enabledBorder: b(const Color(0xFFCBD5E1)),
      focusedBorder: b(primary, 1.8),
      errorBorder: b(Colors.red.shade400),
      focusedErrorBorder: b(Colors.red.shade600, 1.8),
      disabledBorder: b(const Color(0xFFE2E8F0)),
    );
  }

  ButtonStyle get _compactFilled => FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    minimumSize: const Size(0, 44),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );

  ButtonStyle get _compactText => TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    minimumSize: const Size(0, 44),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  );

  Widget _sectionLabel(String text, {IconData? icon, Widget? trailing}) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: primary),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _netImage(String url, {BoxFit fit = BoxFit.cover, double? size}) {
    return StoreProductImage(url: url, width: size, height: size, fit: fit);
  }

  Widget _buildImageArea() {
    final primary = Theme.of(context).colorScheme.primary;
    final urls = _data.imageUrls;
    final pendingTypedUrl = StoreImageUrlHelper.normalize(_imageUrlCtrl.text);
    final hasSavedImages = urls.isNotEmpty;
    final previewUrl = hasSavedImages
        ? urls.first
        : (pendingTypedUrl.isNotEmpty ? pendingTypedUrl : null);

    final hero = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.05),
          border: Border.all(color: primary.withValues(alpha: 0.18)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (previewUrl != null)
              _netImage(previewUrl)
            else
              InkWell(
                onTap: _uploading ? null : _pickImage,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 40,
                      color: primary.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ürün görseli ekle',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Bilgisayardan yükleyin veya bağlantı yapıştırın',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            if (previewUrl != null)
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    hasSavedImages ? 'Kapak' : 'Bağlantı Önizleme',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            if (_uploading)
              Container(
                color: Colors.white70,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );

    Widget thumb(String u, int i) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Stack(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: i == 0
                  ? null
                  : () => setState(() {
                      urls.remove(u);
                      urls.insert(0, u);
                    }),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: i == 0 ? primary : Colors.grey.shade300,
                    width: i == 0 ? 2 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _netImage(u, size: 60),
                ),
              ),
            ),
            Positioned(
              right: 2,
              top: 2,
              child: InkWell(
                onTap: () => setState(() => urls.remove(u)),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        hero,
        if (hasSavedImages) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 62,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < urls.length; i++) thumb(urls[i], i),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              style: _compactFilled,
              onPressed: _uploading ? null : _pickImage,
              icon: const Icon(Icons.upload_rounded, size: 18),
              label: Text(
                hasSavedImages ? 'Bilgisayardan Ekle' : 'Bilgisayardan Yükle',
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => setState(() {
                _showUrlField = !_showUrlField;
                _imageErr = null;
              }),
              icon: const Icon(Icons.add_link_rounded, size: 18),
              label: const Text(
                'Bağlantıdan Resim Yükle',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        if (_showUrlField) ...[
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final urlInput = TextField(
                controller: _imageUrlCtrl,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() => _imageErr = null),
                onSubmitted: (_) => _addUrl(),
                decoration: _dec(
                  'Görsel Bağlantısı (URL)',
                  hint: 'https://ornek.com/urun-gorseli.jpg',
                  prefixIcon: Icons.link_rounded,
                  helperText:
                      'Resim linkini yapıştırıp "Resmi Kullan" butonuna basın (veya doğrudan yayınlayın).',
                  suffixIcon: _imageUrlCtrl.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'Temizle',
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => setState(() {
                            _imageUrlCtrl.clear();
                            _imageErr = null;
                          }),
                        )
                      : null,
                ),
              );
              final useBtn = FilledButton.icon(
                style: _compactFilled,
                onPressed: _addUrl,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Resmi Kullan'),
              );
              if (c.maxWidth < 430) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [urlInput, const SizedBox(height: 8), useBtn],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: urlInput),
                  const SizedBox(width: 8),
                  useBtn,
                ],
              );
            },
          ),
        ],
        if (_imageErr != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _imageErr!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildBasics() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('Temel Bilgiler', icon: Icons.shopping_bag_outlined),
          TextField(
            controller: _titleCtrl,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_titleErr != null) setState(() => _titleErr = null);
            },
            decoration: _dec(
              'Ürün Adı *',
              hint: 'Örn: 5. Sınıf Eğitim Seti / Okul Lakost Tişört',
              prefixIcon: Icons.label_outline_rounded,
              errorText: _titleErr,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _data.category,
            isExpanded: true,
            decoration: _dec('Kategori', prefixIcon: Icons.category_outlined),
            borderRadius: BorderRadius.circular(14),
            items: StoreCategories.all
                .map(
                  (c) => DropdownMenuItem(
                    value: c,
                    child: Text(c, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _data.category = v);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: _dec(
              'Kısa Açıklama',
              hint: 'Ürün içeriği, kumaş veya paket detayı...',
              prefixIcon: Icons.notes_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricing() {
    final price = _parse(_priceCtrl.text);
    final disc = _parse(_discCtrl.text);
    final validDisc =
        price != null && price > 0 && disc != null && disc > 0 && disc < price;
    final pct = validDisc ? ((1 - disc / price) * 100).round() : 0;
    final discInvalid =
        price != null && disc != null && disc > 0 && disc >= price;

    final priceField = TextField(
      controller: _priceCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() => _priceErr = null),
      decoration: _dec(
        'Liste Fiyatı *',
        prefixIcon: Icons.sell_outlined,
        prefixText: '₺ ',
        errorText: _priceErr,
      ),
    );
    final discField = TextField(
      controller: _discCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
      decoration: _dec(
        'İndirimli Fiyat',
        prefixIcon: Icons.discount_outlined,
        prefixText: '₺ ',
        helperText: discInvalid ? 'Liste fiyatından düşük olmalı' : null,
      ),
    );
    final stockField = TextField(
      controller: _stockCtrl,
      keyboardType: TextInputType.number,
      onChanged: (_) {
        if (_stockErr != null) setState(() => _stockErr = null);
      },
      decoration: _dec(
        'Stok Adedi *',
        prefixIcon: Icons.inventory_2_outlined,
        errorText: _stockErr,
      ),
    );
    final vat = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'KDV Oranı',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            segments: const [
              ButtonSegment(value: 0, label: Text('%0')),
              ButtonSegment(value: 10, label: Text('%10')),
              ButtonSegment(value: 20, label: Text('%20')),
            ],
            selected: {_data.vatRate},
            onSelectionChanged: (s) => setState(() => _data.vatRate = s.first),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(
            'Fiyat & Stok',
            icon: Icons.payments_outlined,
            trailing: pct > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      '%$pct indirim',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.green.shade800,
                      ),
                    ),
                  )
                : null,
          ),
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [priceField, const SizedBox(height: 12), discField],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: priceField),
                  const SizedBox(width: 12),
                  Expanded(child: discField),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              if (c.maxWidth < 440) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [stockField, const SizedBox(height: 12), vat],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: stockField),
                  const SizedBox(width: 12),
                  Expanded(child: vat),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _chipLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      t,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );

  List<StoreClassOption> _filteredClassesForSelection() {
    var list = widget.availableClasses;
    final distinctInsts = list
        .map((c) => c.institutionId)
        .where((s) => s.isNotEmpty)
        .toSet();
    if (_data.targetAllSchools && distinctInsts.length > 1) {
      // Genel Merkez tüm okulları hedefliyorsa tekil kurum şubeleri yerine genel şube harfleri gösterilir
      return const [];
    }
    if (!_data.targetAllSchools && _data.targetSchoolIds.isNotEmpty) {
      final upperIds = _data.targetSchoolIds
          .map((e) => e.trim().toUpperCase())
          .toSet();
      final byInst = list
          .where((c) => upperIds.contains(c.institutionId))
          .toList();
      if (byInst.isNotEmpty) {
        list = byInst;
      } else if (distinctInsts.length > 1) {
        return const [];
      }
    }
    if (!_data.targetAllSchoolTypes) {
      if (_data.targetSchoolTypeIds.isNotEmpty) {
        final byType = list
            .where(
              (c) =>
                  c.schoolTypeId.isEmpty ||
                  _data.targetSchoolTypeIds.contains(c.schoolTypeId),
            )
            .toList();
        if (byType.isNotEmpty) {
          list = byType;
        }
      } else if (_data.targetCategories.isNotEmpty) {
        final normCats = _data.targetCategories
            .map(StoreSchoolTypeCategories.normalize)
            .whereType<String>()
            .toSet();
        final byCat = list.where((c) {
          final cCat = StoreSchoolTypeCategories.normalize(c.schoolTypeName);
          if (cCat != null && normCats.contains(cCat)) return true;
          if (normCats.contains(StoreSchoolTypeCategories.anaokulu) &&
              c.classLevel == StoreClassLevels.anaokulu) {
            return true;
          }
          if (normCats.contains(StoreSchoolTypeCategories.ilkokul) &&
              StoreClassLevels.ilkokulGrades.contains(c.classLevel)) {
            return true;
          }
          if (normCats.contains(StoreSchoolTypeCategories.ortaokul) &&
              StoreClassLevels.ortaokulGrades.contains(c.classLevel)) {
            return true;
          }
          if (normCats.contains(StoreSchoolTypeCategories.lise) &&
              StoreClassLevels.liseGrades.contains(c.classLevel)) {
            return true;
          }
          return false;
        }).toList();
        if (byCat.isNotEmpty) {
          list = byCat;
        }
      }
    }
    if (!_data.targetAllClassLevels && _data.targetClassLevels.isNotEmpty) {
      list = list
          .where(
            (c) =>
                c.classLevel.isEmpty ||
                _data.targetClassLevels.contains(c.classLevel),
          )
          .toList();
    }
    final seenNames = <String>{};
    final deduped = <StoreClassOption>[];
    for (final c in list) {
      final norm = StoreClassLevels.normalizeClassToken(c.name);
      if (norm.isEmpty) continue;
      final key = '${c.institutionId}__$norm';
      if (seenNames.add(key)) {
        deduped.add(c);
      }
    }
    return deduped;
  }

  String _audienceSummaryBadge() {
    final parts = <String>[];
    if (!_data.targetAllSchoolTypes) {
      parts.add(
        _data.targetCategories.isNotEmpty
            ? _data.targetCategories.join('/')
            : '${_data.targetSchoolTypeIds.length} Okul Türü',
      );
    }
    if (!_data.targetAllClassLevels && _data.targetClassLevels.isNotEmpty) {
      final sorted = StoreClassLevels.all
          .where(_data.targetClassLevels.contains)
          .map(StoreClassLevels.labelOf)
          .toList();
      parts.add(
        sorted.take(3).join(', ') +
            (sorted.length > 3 ? ' +${sorted.length - 3}' : ''),
      );
    }
    if (!_data.targetAllClasses &&
        (_data.targetClassNames.isNotEmpty ||
            _data.targetClassIds.isNotEmpty)) {
      final names = _data.targetClassNames.toList()..sort();
      if (names.isNotEmpty) {
        parts.add(
          names.take(3).join(', ') +
              (names.length > 3 ? ' +${names.length - 3}' : ''),
        );
      } else {
        parts.add('${_data.targetClassIds.length} Şube');
      }
    }
    return parts.isEmpty ? 'Tüm Kademe & Sınıflar' : parts.join(' • ');
  }

  Widget _buildTargetingSection() {
    final primary = Theme.of(context).colorScheme.primary;
    final filteredClasses = _filteredClassesForSelection();
    final standardBranchLetters = const ['A', 'B', 'C', 'D', 'E', 'F'];

    void applyLevelGroup(List<String> group) {
      setState(() {
        _data.targetAllClassLevels = false;
        final allIn = group.every(_data.targetClassLevels.contains);
        if (allIn) {
          _data.targetClassLevels.removeAll(group);
        } else {
          _data.targetClassLevels.addAll(group);
        }
      });
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50.withValues(alpha: 0.6),
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_2_outlined, size: 20, color: primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Hedef Kitle (Okul Türü, Sınıf Seviyesi & Şube)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Seçili Kapsam: ${_audienceSummaryBadge()}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 1) Alıcı Rolleri
          _chipLabel('Bu ürünü kimler görebilir ve satın alabilir?'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: StoreBuyerRoles.all.map((r) {
              final sel = _data.targetRoles.contains(r);
              return FilterChip(
                selected: sel,
                label: Text(StoreBuyerRoles.labelOf(r)),
                onSelected: (v) => setState(() {
                  if (v) {
                    _data.targetRoles.add(r);
                  } else if (_data.targetRoles.length > 1) {
                    _data.targetRoles.remove(r);
                  }
                }),
              );
            }).toList(),
          ),
          const Divider(height: 22),

          // 2) Okul & Okul Türü (Kademe) — Üst ekranın sağladığı builder
          widget.targetingBuilder(context, _data, _refresh),
          const Divider(height: 20),

          // 3) Sınıf Seviyesi Hedefleme (Örn: Sadece 5. Sınıflar)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _data.targetAllClassLevels,
            onChanged: (v) => setState(() {
              _data.targetAllClassLevels = v;
              if (_saveErr != null) _saveErr = null;
            }),
            title: const Text(
              'Tüm Sınıf Seviyelerine Göster',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              _data.targetAllClassLevels
                  ? 'Kapattığınızda ürünü yalnızca seçtiğiniz sınıflara (örn. sadece 5. Sınıflar) açabilirsiniz.'
                  : 'Yalnızca aşağıda seçtiğiniz sınıf seviyelerindeki öğrenci ve veliler bu ürünü görür.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          if (!_data.targetAllClassLevels) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.layers_outlined, size: 15),
                  label: const Text('İlkokul (1-4)'),
                  onPressed: () =>
                      applyLevelGroup(StoreClassLevels.ilkokulGrades),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.layers_outlined, size: 15),
                  label: const Text('Ortaokul (5-8)'),
                  onPressed: () =>
                      applyLevelGroup(StoreClassLevels.ortaokulGrades),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.layers_outlined, size: 15),
                  label: const Text('Lise (Hazırlık & 9-12)'),
                  onPressed: () => applyLevelGroup(StoreClassLevels.liseGrades),
                ),
                if (_data.targetClassLevels.isNotEmpty)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('Seçimi Temizle'),
                    onPressed: () =>
                        setState(() => _data.targetClassLevels.clear()),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: StoreClassLevels.all.map((lvl) {
                final sel = _data.targetClassLevels.contains(lvl);
                return FilterChip(
                  visualDensity: VisualDensity.compact,
                  selected: sel,
                  label: Text(StoreClassLevels.labelOf(lvl)),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _data.targetClassLevels.add(lvl);
                      _saveErr = null;
                    } else {
                      _data.targetClassLevels.remove(lvl);
                    }
                  }),
                );
              }).toList(),
            ),
          ],
          const Divider(height: 20),

          // 4) Şube / Sınıf Hedefleme (Örn: 5-A, 5-B veya A Şubesi)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _data.targetAllClasses,
            onChanged: (v) => setState(() {
              _data.targetAllClasses = v;
              if (_saveErr != null) _saveErr = null;
            }),
            title: const Text(
              'Tüm Şubelere Göster',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              _data.targetAllClasses
                  ? 'Kapattığınızda belirli şubeleri (örn. 5-A, 5-B) hedefleyebilirsiniz.'
                  : 'Yalnızca aşağıda seçtiğiniz şubelerdeki öğrenci ve veliler bu ürünü görür.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          if (!_data.targetAllClasses) ...[
            const SizedBox(height: 6),
            if (filteredClasses.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tanımlı Şubeler (${filteredClasses.length}):',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => setState(() {
                      for (final c in filteredClasses) {
                        _data.targetClassIds.add(c.id);
                        _data.targetClassNames.add(
                          StoreClassLevels.normalizeClassToken(c.name),
                        );
                      }
                      _saveErr = null;
                    }),
                    child: const Text('Tümünü Seç'),
                  ),
                  if (_data.targetClassIds.isNotEmpty ||
                      _data.targetClassNames.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => setState(() {
                        _data.targetClassIds.clear();
                        _data.targetClassNames.clear();
                      }),
                      child: const Text('Temizle'),
                    ),
                ],
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: () {
                      final multiInst =
                          filteredClasses
                              .map((e) => e.institutionId)
                              .where((s) => s.isNotEmpty)
                              .toSet()
                              .length >
                          1;
                      return filteredClasses.map((c) {
                        final normName = StoreClassLevels.normalizeClassToken(
                          c.name,
                        );
                        final sel =
                            _data.targetClassIds.contains(c.id) ||
                            (!multiInst &&
                                _data.targetClassNames.contains(normName));
                        return FilterChip(
                          visualDensity: VisualDensity.compact,
                          selected: sel,
                          label: Text(
                            multiInst && c.institutionId.isNotEmpty
                                ? '${c.name} (${c.institutionId})'
                                : c.name,
                          ),
                          onSelected: (v) => setState(() {
                            if (v) {
                              _data.targetClassIds.add(c.id);
                              _data.targetClassNames.add(normName);
                              _saveErr = null;
                            } else {
                              _data.targetClassIds.remove(c.id);
                              final anyRemainingWithSameName = filteredClasses
                                  .any(
                                    (other) =>
                                        other.id != c.id &&
                                        _data.targetClassIds.contains(
                                          other.id,
                                        ) &&
                                        StoreClassLevels.normalizeClassToken(
                                              other.name,
                                            ) ==
                                            normName,
                                  );
                              if (!anyRemainingWithSameName) {
                                _data.targetClassNames.remove(normName);
                              }
                            }
                          }),
                        );
                      }).toList();
                    }(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ] else ...[
              Text(
                'Hızlı Şube Harfi Seçimi:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: standardBranchLetters.map((b) {
                  final sel = _data.targetClassNames.contains(b);
                  return FilterChip(
                    visualDensity: VisualDensity.compact,
                    selected: sel,
                    label: Text('$b Şubesi'),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _data.targetClassNames.add(b);
                        _saveErr = null;
                      } else {
                        _data.targetClassNames.remove(b);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customClassCtrl,
                    onSubmitted: (_) => _addCustomClassToken(),
                    decoration: _dec(
                      'Özel sınıf / şube kodu ekle',
                      hint: 'Örn: 5-A, 5-B veya A',
                      prefixIcon: Icons.meeting_room_outlined,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  style: _compactFilled,
                  onPressed: _addCustomClassToken,
                  child: const Text('Ekle'),
                ),
              ],
            ),
            if (_data.targetClassNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _data.targetClassNames.map((token) {
                  return InputChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(token),
                    onDeleted: () => setState(() {
                      _data.targetClassNames.remove(token);
                      for (final c in widget.availableClasses) {
                        if (StoreClassLevels.normalizeClassToken(c.name) ==
                            token) {
                          _data.targetClassIds.remove(c.id);
                        }
                      }
                    }),
                  );
                }).toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildDeliveryAndMandatorySection() {
    final primary = Theme.of(context).colorScheme.primary;

    Widget deliveryOptionTile({
      required bool selected,
      required IconData icon,
      required String title,
      required String subtitle,
      required ValueChanged<bool> onChanged,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          onChanged(!selected);
          if (_saveErr != null) setState(() => _saveErr = null);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? primary.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? primary : Colors.grey.shade300,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? primary : Colors.grey.shade500,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? primary : Colors.black87,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: selected,
                visualDensity: VisualDensity.compact,
                onChanged: (v) {
                  onChanged(v ?? false);
                  if (_saveErr != null) setState(() => _saveErr = null);
                },
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50.withValues(alpha: 0.6),
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined, size: 20, color: primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Teslimat Seçenekleri & Zorunlu Ürün Ayarı',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Bu ürünün alıcıya hangi yöntemlerle teslim edilebileceğini ve ilk alışverişte zorunlu olup olmadığını belirleyin.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final pickupTile = deliveryOptionTile(
                selected: _data.allowPickupAtSchool,
                icon: Icons.school_outlined,
                title: 'Okuldan Teslim',
                subtitle: 'Okul teslim noktasından ücretsiz teslim',
                onChanged: (v) => setState(() => _data.allowPickupAtSchool = v),
              );
              final cargoTile = deliveryOptionTile(
                selected: _data.allowHomeDelivery,
                icon: Icons.local_shipping_outlined,
                title: 'Adrese Kargo',
                subtitle: 'Alıcının adresine kargo ile gönderim',
                onChanged: (v) => setState(() => _data.allowHomeDelivery = v),
              );
              if (c.maxWidth < 460) {
                return Column(
                  children: [pickupTile, const SizedBox(height: 8), cargoTile],
                );
              }
              return Row(
                children: [
                  Expanded(child: pickupTile),
                  const SizedBox(width: 10),
                  Expanded(child: cargoTile),
                ],
              );
            },
          ),
          const Divider(height: 22),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _data.isMandatory,
            onChanged: (v) => setState(() {
              _data.isMandatory = v;
              if (v && _data.mandatoryRoles.isEmpty) {
                _data.mandatoryRoles.addAll([
                  StoreBuyerRoles.veli,
                  StoreBuyerRoles.ogrenci,
                ]);
              }
              if (_saveErr != null) _saveErr = null;
            }),
            title: Row(
              children: [
                Icon(
                  Icons.lock_person_rounded,
                  size: 18,
                  color: _data.isMandatory
                      ? Colors.deepOrange.shade700
                      : Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Zorunlu Ürün (İlk Alışverişte Otomatik Sepete Ekle)',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              _data.isMandatory
                  ? 'Aktif: Bu ürünü henüz satın almamış hedef veli/öğrencilerin ilk alışverişinde otomatik sepete eklenir ve sepetten çıkarılamaz. Bir kez satın alındıktan sonraki alışverişlerde tekrar zorunlu tutulmaz.'
                  : 'Kapalı: Alıcı ürünü isteğe bağlı olarak sepetine ekleyip çıkarabilir.',
              style: TextStyle(
                fontSize: 12,
                color: _data.isMandatory
                    ? Colors.deepOrange.shade900
                    : Colors.grey.shade600,
              ),
            ),
          ),
          if (_data.isMandatory) ...[
            const SizedBox(height: 8),
            Text(
              'Hangi Alıcı Rolleri İçin İlk Alışverişte Zorunlu Olsun?',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: StoreBuyerRoles.all.map((role) {
                final sel = _data.mandatoryRoles.contains(role);
                return FilterChip(
                  visualDensity: VisualDensity.compact,
                  selected: sel,
                  label: Text(StoreBuyerRoles.labelOf(role)),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _data.mandatoryRoles.add(role);
                      _saveErr = null;
                    } else if (_data.mandatoryRoles.length > 1) {
                      _data.mandatoryRoles.remove(role);
                    }
                  }),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVariantsAndPublishSection() {
    final variants = _data.variants;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: variants.isNotEmpty || !_data.isActive,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Icon(Icons.style_outlined, color: Colors.grey.shade700),
          title: const Text(
            'Varyantlar & Yayın Durumu',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          subtitle: Text(
            variants.isNotEmpty
                ? '${variants.length} seçenek tanımlı • ${_data.isActive ? "Satışta" : "Pasif"}'
                : 'Beden / paket seçenekleri (opsiyonel) ve satış durumu',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          children: [
            _chipLabel('Varyantlar (opsiyonel)'),
            if (widget.variantPresets.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in widget.variantPresets)
                    ActionChip(
                      label: Text(p.key),
                      onPressed: () => setState(() {
                        for (final v in p.value) {
                          if (!variants.contains(v)) variants.add(v);
                        }
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _variantCtrl,
                    onSubmitted: (_) => _addVariant(),
                    decoration: _dec(
                      'Özel seçenek',
                      hint: 'Örn: XL veya 2. Dönem Seti',
                      prefixIcon: Icons.style_outlined,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  style: _compactFilled,
                  onPressed: _addVariant,
                  child: const Text('Ekle'),
                ),
              ],
            ),
            if (variants.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in variants)
                    InputChip(
                      label: Text(v),
                      onDeleted: () => setState(() => variants.remove(v)),
                    ),
                ],
              ),
            ],
            const Divider(height: 22),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _data.isActive,
              onChanged: (v) => setState(() => _data.isActive = v),
              title: const Text(
                'Ürün Satışta / Aktif',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addVariant() {
    final v = _variantCtrl.text.trim();
    if (v.isNotEmpty && !_data.variants.contains(v)) {
      setState(() {
        _data.variants.add(v);
        _variantCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isNew = widget.existing == null;
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        backgroundColor: const Color(0xFFF8FAFC),
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Başlık
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [primary, primary.withValues(alpha: 0.75)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isNew
                            ? Icons.add_business_rounded
                            : Icons.edit_note_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: _buildImageArea(),
                      ),
                      const SizedBox(height: 16),
                      _buildBasics(),
                      const SizedBox(height: 16),
                      _buildPricing(),
                      const SizedBox(height: 16),
                      _buildDeliveryAndMandatorySection(),
                      const SizedBox(height: 14),
                      _buildTargetingSection(),
                      const SizedBox(height: 14),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: _buildVariantsAndPublishSection(),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_saveErr != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 18,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _saveErr!,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          style: _compactText,
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Vazgeç'),
                        ),
                        FilledButton.icon(
                          style: _compactFilled.copyWith(
                            backgroundColor: WidgetStatePropertyAll(primary),
                          ),
                          onPressed: (_saving || _uploading) ? null : _submit,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  isNew
                                      ? Icons.rocket_launch_rounded
                                      : Icons.check_circle_outline_rounded,
                                  size: 18,
                                ),
                          label: Text(isNew ? 'Ürünü Yayınla' : 'Güncelle'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
