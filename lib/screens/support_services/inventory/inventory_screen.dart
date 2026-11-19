import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/school/inventory_procurement_models.dart';
import '../../../services/inventory_procurement_service.dart';
import '../../../services/user_permission_service.dart';
import '../../../widgets/edukn_app_bar.dart';
import 'inventory_ui_widgets.dart';
import 'material_request_form_sheet.dart';
import 'procurement_settings_sheet.dart';
import 'quote_management_sheet.dart';
import 'teacher_material_requests_screen.dart';

/// Depo Yönetimi, Malzeme Talepleri, Çok Kademeli Onay ve Satın Alma Otomasyonu
class InventoryScreen extends StatefulWidget {
  final String? fixedSchoolTypeId;
  final String? fixedSchoolTypeName;
  final bool isStandalonePortal;
  final String standaloneMode; // '' | 'warehouse' | 'purchasing'
  final int? initialTabIndex;

  const InventoryScreen({
    super.key,
    this.fixedSchoolTypeId,
    this.fixedSchoolTypeName,
    this.isStandalonePortal = false,
    this.standaloneMode = '',
    this.initialTabIndex,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final InventoryProcurementService _service = InventoryProcurementService();
  final DateFormat _dateFmt = DateFormat('dd.MM.yyyy HH:mm');
  final NumberFormat _currencyFmt =
      NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

  bool _loading = true;
  bool _impersonating = false;
  int _activeTab = 0;

  String _institutionId = '';
  String _schoolDocId = '';
  String _schoolName = '';
  String _actorUid = '';
  String _actorName = 'Personel';
  String _actorRole = '';
  Map<String, dynamic>? _userData;
  List<({String id, String name})> _schoolTypes = [];

  // Sekme 0 (Depo & Stoklar) filtreleri
  String _selectedWarehouseId = ''; // '' => Görünür tüm depolar
  final TextEditingController _stockSearchCtrl = TextEditingController();
  String _stockSearch = '';
  String _selectedCategory = 'Tümü';
  bool _onlyCriticalStock = false;

  // Sekme 1 (Talepler & Teslimat) filtreleri
  String _requestFilter =
      'actionable'; // 'actionable' | 'supervisor' | 'upper' | 'warehouse_ops' | 'closed' | 'all'
  final Set<String> _expandedRequestIds = {};

  // Sekme 2 (Satın Alma & Teklifler) filtreleri
  String _procurementFilter =
      'active'; // 'active' | 'quotes' | 'approval' | 'ordered' | 'completed'

  bool get _isSchoolTypeScoped =>
      (widget.fixedSchoolTypeId ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.initialTabIndex != null) {
      _activeTab = widget.initialTabIndex!.clamp(0, 3);
    } else if (widget.standaloneMode == 'purchasing') {
      _activeTab = 2;
    } else {
      _activeTab = 0;
    }
    _bootstrap();
  }

  @override
  void dispose() {
    _stockSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final imp = prefs.getBool('is_impersonating') ?? false;

      final actor = await _service.resolveCurrentActor();
      final instId = actor.institutionId.trim();
      final schoolDocId = await _service.resolveSchoolDocId(instId);

      final isTeacherOnly =
          (actor.role == 'ogretmen' || actor.role == 'rehber_ogretmen') &&
              !InventoryProcurementService.canManageWarehouse(
                actor.userData,
                currentUid: actor.uid,
              ) &&
              !InventoryProcurementService.canManageProcurement(
                actor.userData,
              );

      if (!isTeacherOnly &&
          !_isSchoolTypeScoped &&
          instId.isNotEmpty &&
          schoolDocId.isNotEmpty) {
        await _service.ensureDefaultWarehouse(
          institutionId: instId,
          schoolDocId: schoolDocId,
        );
      }

      String schoolName = (widget.fixedSchoolTypeName ?? '').trim();
      if (schoolDocId.isNotEmpty) {
        try {
          final sDoc = await FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolDocId)
              .get();
          if (sDoc.exists) {
            final raw =
                (sDoc.data()?['schoolName'] ?? sDoc.data()?['name'] ?? '')
                    .toString()
                    .trim();
            if (raw.isNotEmpty) {
              schoolName = schoolName.isNotEmpty &&
                      !raw.toLowerCase().contains(schoolName.toLowerCase())
                  ? '$raw • $schoolName'
                  : raw;
            }
          }
        } catch (_) {}
      }

      final stMap = <String, String>{};
      if (instId.isNotEmpty) {
        final variants = {
          instId,
          instId.toUpperCase(),
          instId.toLowerCase(),
        }.toList();
        for (final col in const ['school_types', 'schoolTypes']) {
          try {
            final snap = await FirebaseFirestore.instance
                .collection(col)
                .where('institutionId', whereIn: variants)
                .get();
            for (final d in snap.docs) {
              final n =
                  (d.data()['name'] ?? d.data()['schoolTypeName'] ?? '')
                      .toString()
                      .trim();
              if (n.isNotEmpty) stMap[d.id] = n;
            }
          } catch (_) {}
        }
      }

      int computedTab = _activeTab;
      if (widget.initialTabIndex == null && widget.standaloneMode.isEmpty) {
        if (actor.role == 'satin_alma') {
          computedTab = 2;
        }
      }

      if (!mounted) return;
      setState(() {
        _impersonating = imp;
        _institutionId = instId;
        _schoolDocId = schoolDocId;
        _schoolName = schoolName.isNotEmpty ? schoolName : 'Depo & Satın Alma';
        _actorUid = actor.uid;
        _actorName = actor.name;
        _actorRole = actor.role;
        _userData = actor.userData;
        _schoolTypes = stMap.entries
            .map((e) => (id: e.key, name: e.value))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        _activeTab = computedTab;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            isError ? const Color(0xFFDC2626) : const Color(0xFF059669),
        content: Text(message),
      ),
    );
  }

  Future<void> _openUrl(String rawUrl) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return;
    final formatted =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
            ? trimmed
            : 'https://$trimmed';
    final uri = Uri.tryParse(formatted);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _previewImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Stack(
          children: [
            InteractiveViewer(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxHeight: 620, maxWidth: 800),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(40),
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 56,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STANDALONE PORTAL HESAP MENÜSÜ
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _exitImpersonation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_impersonating');
    await prefs.remove('impersonated_user_id');
    await prefs.remove('impersonated_user_email');
    await prefs.remove('impersonated_user_name');
    await prefs.setString('active_portal', 'manager');
    UserPermissionService.clearCache();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil('/school-dashboard', (_) => false);
  }

  Future<void> _confirmStandaloneLogout() async {
    final ok = await showInventoryBottomSheet<bool>(
      context: context,
      maxWidth: 480,
      builder: (ctx) => InventoryBottomSheetFrame(
        title: 'Güvenli Çıkış Yap',
        subtitle: 'Oturumunuzu kapatmak istediğinize emin misiniz?',
        icon: Icons.logout_rounded,
        accentColor: const Color(0xFFDC2626),
        footer: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Text('Vazgeç'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text(
                  'Çıkış Yap',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        child: const Text(
          'Açık kalan oturum bilgileriniz temizlenecek ve giriş ekranına yönlendirileceksiniz.',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
        ),
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_portal');
    await prefs.remove('is_impersonating');
    await prefs.remove('impersonated_user_id');
    await prefs.remove('impersonated_user_email');
    await prefs.remove('impersonated_user_name');
    UserPermissionService.clearCache();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil('/school-login', (_) => false);
  }

  Widget _buildStandaloneUserMenu(bool isMobile) {
    final portalLabel = widget.standaloneMode == 'purchasing'
        ? 'Satın Alma Portalı'
        : 'Depo Yönetim Portalı';
    return PopupMenuButton<String>(
      tooltip: 'Hesap ve Oturum İşlemleri',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      offset: const Offset(0, 46),
      onSelected: (val) async {
        if (val == 'profile') {
          Navigator.of(context).pushNamed('/profile-settings');
        } else if (val == 'exit_imp') {
          await _exitImpersonation();
        } else if (val == 'logout') {
          await _confirmStandaloneLogout();
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _actorName,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                portalLabel,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4F46E5),
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'profile',
          child: Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 18,
                color: Color(0xFF334155),
              ),
              SizedBox(width: 10),
              Text('Profil ve Şifre Ayarları', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        if (_impersonating)
          const PopupMenuItem<String>(
            value: 'exit_imp',
            child: Row(
              children: [
                Icon(Icons.undo_rounded, size: 18, color: Color(0xFFC2410C)),
                SizedBox(width: 10),
                Text(
                  'Yönetici Hesabına Dön',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFC2410C),
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 18, color: Color(0xFFDC2626)),
              SizedBox(width: 10),
              Text(
                'Güvenli Çıkış Yap',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFDC2626),
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding:
            EdgeInsets.symmetric(horizontal: isMobile ? 8 : 11, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFC7D2FE)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_rounded,
              size: 16,
              color: Color(0xFF4F46E5),
            ),
            if (!isMobile) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  _actorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF312E81),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: Color(0xFF4F46E5),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TAM ALTTAN AÇILAN DEPO İŞLEM PANELLERİ (Sıfır Ortalanmış Dialog!)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _quickCreateSchoolTypeWarehouse() async {
    final stId = (widget.fixedSchoolTypeId ?? '').trim();
    final stName = (widget.fixedSchoolTypeName ?? 'Okul Türü').trim();
    if (stId.isEmpty || _schoolDocId.isEmpty) return;

    final nameCtrl = TextEditingController(text: '$stName Deposu');
    final locCtrl = TextEditingController(text: stName);

    final ok = await showInventoryBottomSheet<bool>(
      context: context,
      maxWidth: 560,
      builder: (ctx) => InventoryBottomSheetFrame(
        title: 'Okul Türü Deposu Oluştur',
        subtitle: '$stName birimine özel müstakil depo tanımlayın.',
        icon: Icons.warehouse_rounded,
        accentColor: const Color(0xFF4F46E5),
        footer: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Text('Vazgeç'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: const Icon(Icons.add_business_rounded, size: 19),
                label: const Text(
                  'Depoyu Oluştur',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        child: Column(
          children: [
            InventoryTextField(
              controller: nameCtrl,
              label: 'Depo Adı',
              isRequired: true,
              icon: Icons.warehouse_outlined,
            ),
            const SizedBox(height: 14),
            InventoryTextField(
              controller: locCtrl,
              label: 'Bina / Kat / Konum',
              trailingText: 'Opsiyonel',
              icon: Icons.place_outlined,
            ),
          ],
        ),
      ),
    );

    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    try {
      await _service.saveWarehouse(
        schoolDocId: _schoolDocId,
        warehouse: WarehouseModel(
          id: '',
          institutionId: _institutionId,
          schoolDocId: _schoolDocId,
          name: nameCtrl.text.trim(),
          type: 'schoolType',
          schoolTypeId: stId,
          schoolTypeName: stName,
          location: locCtrl.text.trim(),
          createdAt: DateTime.now(),
        ),
      );
      _showSnack('"${nameCtrl.text.trim()}" başarıyla oluşturuldu.');
    } catch (e) {
      _showSnack('Depo oluşturulamadı: $e', isError: true);
    }
  }

  Future<void> _openAddOrEditItemSheet({
    required List<WarehouseModel> visibleWarehouses,
    InventoryItemModel? existing,
  }) async {
    if (visibleWarehouses.isEmpty) {
      _showSnack(
        'Önce malzeme eklenecek bir depo tanımlamanız gerekiyor.',
        isError: true,
      );
      return;
    }

    String chosenWhId = existing?.warehouseId ??
        (_selectedWarehouseId.isNotEmpty
            ? _selectedWarehouseId
            : visibleWarehouses.first.id);
    if (!visibleWarehouses.any((w) => w.id == chosenWhId)) {
      chosenWhId = visibleWarehouses.first.id;
    }

    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final qtyCtrl = TextEditingController(
      text: existing != null ? existing.formattedQty : '1',
    );
    final minCtrl = TextEditingController(
      text: existing != null ? existing.formattedMinQty : '5',
    );
    final shelfCtrl = TextEditingController(text: existing?.shelfLocation ?? '');
    final linkCtrl = TextEditingController(text: existing?.productLink ?? '');
    final priceCtrl = TextEditingController(
      text: existing != null && existing.lastUnitPrice > 0
          ? existing.lastUnitPrice.toStringAsFixed(2)
          : '',
    );

    String category =
        existing?.category ?? InventoryItemModel.defaultCategories.first;
    if (!InventoryItemModel.defaultCategories.contains(category)) {
      category = InventoryItemModel.defaultCategories.first;
    }
    String unit = existing?.unit ?? InventoryItemModel.defaultUnits.first;
    if (!InventoryItemModel.defaultUnits.contains(unit)) {
      unit = InventoryItemModel.defaultUnits.first;
    }
    String imageUrl = existing?.imageUrl ?? '';
    bool uploading = false;
    bool saving = false;

    await showInventoryBottomSheet<void>(
      context: context,
      maxWidth: 680,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> pickImage(bool fromCamera) async {
              try {
                setModalState(() => uploading = true);
                if (fromCamera && !kIsWeb) {
                  final xFile = await ImagePicker().pickImage(
                    source: ImageSource.camera,
                    imageQuality: 78,
                  );
                  if (xFile != null) {
                    final bytes = await xFile.readAsBytes();
                    imageUrl = await _service.uploadAttachmentBytes(
                      schoolDocId: _schoolDocId,
                      bytes: bytes,
                      fileName: xFile.name,
                    );
                  }
                } else {
                  final res = await FilePicker.pickFiles(
                    type: FileType.image,
                    withData: true,
                  );
                  if (res != null &&
                      res.files.isNotEmpty &&
                      res.files.first.bytes != null) {
                    imageUrl = await _service.uploadAttachmentBytes(
                      schoolDocId: _schoolDocId,
                      bytes: res.files.first.bytes!,
                      fileName: res.files.first.name,
                    );
                  }
                }
              } catch (e) {
                _showSnack('Görsel yüklenemedi: $e', isError: true);
              } finally {
                setModalState(() => uploading = false);
              }
            }

            return InventoryBottomSheetFrame(
              title: existing == null
                  ? 'Depoya Yeni Malzeme Kartı Ekle'
                  : 'Malzeme Kartını Düzenle',
              subtitle:
                  'Malzeme stok, birim, raf konumu ve kritik alt sınır bilgilerini girin.',
              icon: Icons.inventory_2_rounded,
              accentColor: const Color(0xFF4F46E5),
              footer: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          if (nameCtrl.text.trim().isEmpty) {
                            _showSnack(
                              'Lütfen malzeme adını giriniz.',
                              isError: true,
                            );
                            return;
                          }
                          setModalState(() => saving = true);
                          try {
                            final wh = visibleWarehouses.firstWhere(
                              (w) => w.id == chosenWhId,
                              orElse: () => visibleWarehouses.first,
                            );
                            final initQty = double.tryParse(
                                  qtyCtrl.text.replaceAll(',', '.').trim(),
                                ) ??
                                0;
                            final minQty = double.tryParse(
                                  minCtrl.text.replaceAll(',', '.').trim(),
                                ) ??
                                0;
                            final unitPrice = double.tryParse(
                                  priceCtrl.text.replaceAll(',', '.').trim(),
                                ) ??
                                0;

                            final model = InventoryItemModel(
                              id: existing?.id ?? '',
                              institutionId: _institutionId,
                              schoolDocId: _schoolDocId,
                              warehouseId: wh.id,
                              warehouseName: wh.name,
                              schoolTypeId: wh.schoolTypeId,
                              name: nameCtrl.text.trim(),
                              normalizedName: InventoryItemModel.normalizeTr(
                                nameCtrl.text,
                              ),
                              category: category,
                              unit: unit,
                              quantity: existing?.quantity ?? initQty,
                              minStockLevel: minQty,
                              shelfLocation: shelfCtrl.text.trim(),
                              productLink: linkCtrl.text.trim(),
                              imageUrl: imageUrl,
                              lastUnitPrice: unitPrice,
                              updatedAt: DateTime.now(),
                            );

                            await _service.saveInventoryItem(
                              schoolDocId: _schoolDocId,
                              item: model,
                              actorUid: _actorUid,
                              actorName: _actorName,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _showSnack(
                              existing == null
                                  ? 'Malzeme depoya kaydedildi.'
                                  : 'Malzeme kartı güncellendi.',
                            );
                          } catch (e) {
                            setModalState(() => saving = false);
                            _showSnack('Hata: $e', isError: true);
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.save_rounded, size: 19),
                  label: Text(
                    saving ? 'Kaydediliyor...' : 'Malzeme Kartını Kaydet',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (existing == null && visibleWarehouses.length > 1) ...[
                    InventoryDropdownField<String>(
                      label: 'Eklenecek Depo',
                      isRequired: true,
                      icon: Icons.warehouse_outlined,
                      value: chosenWhId,
                      items: visibleWarehouses
                          .map(
                            (w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(
                                w.isCentral
                                    ? '${w.name} (Merkez)'
                                    : '${w.name} (${w.schoolTypeName})',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setModalState(() => chosenWhId = v);
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                  InventoryTextField(
                    controller: nameCtrl,
                    label: 'Malzeme Adı',
                    isRequired: true,
                    hint: 'Örn: A4 Fotokopi Kağıdı (80 gr)',
                    icon: Icons.inventory_2_outlined,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: InventoryDropdownField<String>(
                          label: 'Kategori',
                          icon: Icons.category_outlined,
                          value: category,
                          items: InventoryItemModel.defaultCategories
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                    c,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setModalState(() => category = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: InventoryDropdownField<String>(
                          label: 'Birim',
                          icon: Icons.straighten_rounded,
                          value: unit,
                          items: InventoryItemModel.defaultUnits
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u,
                                  child: Text(u),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setModalState(() => unit = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (existing == null) ...[
                        Expanded(
                          child: InventoryTextField(
                            controller: qtyCtrl,
                            label: 'Başlangıç Stoğu',
                            icon: Icons.numbers_rounded,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: InventoryTextField(
                          controller: minCtrl,
                          label: 'Kritik Alt Sınır',
                          icon: Icons.warning_amber_rounded,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InventoryTextField(
                          controller: shelfCtrl,
                          label: 'Raf / Dolap Kodu',
                          hint: 'Örn: A-3',
                          icon: Icons.shelves,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: InventoryTextField(
                          controller: linkCtrl,
                          label: 'Referans Ürün Linki',
                          trailingText: 'Opsiyonel',
                          hint: 'https://...',
                          icon: Icons.link_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InventoryTextField(
                          controller: priceCtrl,
                          label: 'Birim Fiyat (₺)',
                          hint: '0.00',
                          icon: Icons.currency_lira_rounded,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const InventoryFieldLabel(
                    'Ürün Görseli',
                    trailingText: 'Opsiyonel',
                  ),
                  Row(
                    children: [
                      if (imageUrl.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            imageUrl,
                            width: 54,
                            height: 54,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.image_outlined),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      OutlinedButton.icon(
                        onPressed: uploading ? null : () => pickImage(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: uploading
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.photo_library_outlined,
                                size: 18,
                              ),
                        label: Text(
                          imageUrl.isEmpty ? 'Görsel Ekle' : 'Görseli Değiştir',
                        ),
                      ),
                      if (!kIsWeb) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: uploading ? null : () => pickImage(true),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(
                            Icons.camera_alt_outlined,
                            size: 18,
                          ),
                          label: const Text('Kamera'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openQuickStockDialog(
    InventoryItemModel item,
    String initialType, // 'in' | 'out' | 'adjustment'
  ) async {
    String mode = initialType;
    final qtyCtrl = TextEditingController(
      text: initialType == 'adjustment' ? item.formattedQty : '1',
    );
    final recipientCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final ok = await showInventoryBottomSheet<bool>(
      context: context,
      maxWidth: 580,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final accent = mode == 'out'
              ? const Color(0xFFDC2626)
              : mode == 'adjustment'
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFF059669);

          return InventoryBottomSheetFrame(
            title: item.name,
            subtitle:
                'Depo: ${item.warehouseName} • Mevcut Stok: ${item.formattedQty} ${item.unit}',
            icon: mode == 'out'
                ? Icons.outbox_rounded
                : mode == 'adjustment'
                    ? Icons.fact_check_outlined
                    : Icons.move_to_inbox_rounded,
            accentColor: accent,
            footer: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: const Text('Vazgeç'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 19),
                    label: const Text(
                      'Stok Hareketini Kaydet',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const InventoryFieldLabel('İşlem Türü'),
                Row(
                  children: [
                    Expanded(
                      child: _ModeSelectTile(
                        label: 'Giriş (+)',
                        icon: Icons.add_circle_outline_rounded,
                        selected: mode == 'in',
                        color: const Color(0xFF059669),
                        onTap: () {
                          setSheetState(() {
                            mode = 'in';
                            if (qtyCtrl.text == item.formattedQty) {
                              qtyCtrl.text = '1';
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ModeSelectTile(
                        label: 'Çıkış (-)',
                        icon: Icons.remove_circle_outline_rounded,
                        selected: mode == 'out',
                        color: const Color(0xFFDC2626),
                        onTap: () {
                          setSheetState(() {
                            mode = 'out';
                            if (qtyCtrl.text == item.formattedQty) {
                              qtyCtrl.text = '1';
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ModeSelectTile(
                        label: 'Sayım',
                        icon: Icons.fact_check_outlined,
                        selected: mode == 'adjustment',
                        color: const Color(0xFF4F46E5),
                        onTap: () {
                          setSheetState(() {
                            mode = 'adjustment';
                            qtyCtrl.text = item.formattedQty;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                InventoryTextField(
                  controller: qtyCtrl,
                  label: mode == 'adjustment'
                      ? 'Yeni Gerçek Stok Miktarı (${item.unit})'
                      : 'İşlem Miktarı (${item.unit})',
                  isRequired: true,
                  icon: Icons.numbers_rounded,
                  accentColor: accent,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                if (mode == 'out') ...[
                  const SizedBox(height: 14),
                  InventoryTextField(
                    controller: recipientCtrl,
                    label: 'Teslim Alan Kişi / Sınıf / Birim',
                    hint: 'Örn: 9-A Sınıfı / Kimya Laboratuvarı',
                    icon: Icons.person_outline_rounded,
                    accentColor: accent,
                  ),
                ],
                const SizedBox(height: 14),
                InventoryTextField(
                  controller: noteCtrl,
                  label: 'Açıklama / Not',
                  trailingText: 'Opsiyonel',
                  hint: 'İşlemle ilgili kısa açıklama...',
                  icon: Icons.notes_rounded,
                  accentColor: accent,
                ),
              ],
            ),
          );
        },
      ),
    );

    if (ok != true) return;
    final qty =
        double.tryParse(qtyCtrl.text.replaceAll(',', '.').trim()) ?? -1;
    if (qty < 0 || (mode != 'adjustment' && qty <= 0)) {
      _showSnack('Lütfen geçerli bir miktar giriniz.', isError: true);
      return;
    }

    try {
      await _service.recordManualStockMovement(
        schoolDocId: _schoolDocId,
        itemId: item.id,
        type: mode,
        quantity: qty,
        actorUid: _actorUid,
        actorName: _actorName,
        recipientName: recipientCtrl.text.trim(),
        note: noteCtrl.text.trim(),
      );
      _showSnack('Stok hareketi başarıyla kaydedildi.');
    } catch (e) {
      _showSnack('$e', isError: true);
    }
  }

  Future<void> _openTransferDialog(
    InventoryItemModel item,
    List<WarehouseModel> allWarehouses,
  ) async {
    final targets =
        allWarehouses.where((w) => w.id != item.warehouseId).toList();
    if (targets.isEmpty) {
      _showSnack(
        'Transfer yapılabilecek başka aktif depo bulunmuyor.',
        isError: true,
      );
      return;
    }

    WarehouseModel selectedTarget = targets.first;
    final qtyCtrl = TextEditingController(text: '1');
    final noteCtrl = TextEditingController();

    final ok = await showInventoryBottomSheet<bool>(
      context: context,
      maxWidth: 580,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => InventoryBottomSheetFrame(
          title: 'Depolar Arası Malzeme Transferi',
          subtitle:
              '${item.name} • Kaynak: ${item.warehouseName} (${item.formattedQty} ${item.unit})',
          icon: Icons.swap_horiz_rounded,
          accentColor: const Color(0xFF4F46E5),
          footer: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: const Text('Vazgeç'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 19),
                  label: const Text(
                    'Transferi Gerçekleştir',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InventoryDropdownField<String>(
                label: 'Hedef Depo',
                isRequired: true,
                icon: Icons.warehouse_outlined,
                value: selectedTarget.id,
                items: targets
                    .map(
                      (w) => DropdownMenuItem(value: w.id, child: Text(w.name)),
                    )
                    .toList(),
                onChanged: (v) {
                  final found = targets.where((w) => w.id == v).firstOrNull;
                  if (found != null) {
                    setSheetState(() => selectedTarget = found);
                  }
                },
              ),
              const SizedBox(height: 14),
              InventoryTextField(
                controller: qtyCtrl,
                label: 'Transfer Miktarı (${item.unit})',
                isRequired: true,
                icon: Icons.numbers_rounded,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 14),
              InventoryTextField(
                controller: noteCtrl,
                label: 'Transfer Notu',
                trailingText: 'Opsiyonel',
                hint: 'Örn: Okul açılışı kırtasiye takviyesi',
                icon: Icons.notes_rounded,
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;
    final qty =
        double.tryParse(qtyCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    try {
      await _service.transferBetweenWarehouses(
        schoolDocId: _schoolDocId,
        sourceItemId: item.id,
        targetWarehouse: selectedTarget,
        quantity: qty,
        actorUid: _actorUid,
        actorName: _actorName,
        note: noteCtrl.text.trim(),
      );
      _showSnack(
        '${InventoryItemModel.formatQty(qty)} ${item.unit} "${item.name}" → ${selectedTarget.name} deposuna aktarıldı.',
      );
    } catch (e) {
      _showSnack('$e', isError: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TALEP ONAY, MAL KABUL VE TESLİMAT PANELLERİ (Tam Alttan Açılan)
  // ═══════════════════════════════════════════════════════════════════════════

  List<InventoryItemModel> _findMatchingStockItems(
    MaterialRequestModel r,
    List<InventoryItemModel> allItems,
  ) {
    final matches = allItems.where((it) {
      if (r.linkedItemId.isNotEmpty && it.id == r.linkedItemId) return true;
      return it.normalizedName == r.normalizedItemName;
    }).toList();

    matches.sort((a, b) {
      final aSt =
          r.schoolTypeId.isNotEmpty && a.schoolTypeId == r.schoolTypeId ? 1 : 0;
      final bSt =
          r.schoolTypeId.isNotEmpty && b.schoolTypeId == r.schoolTypeId ? 1 : 0;
      if (aSt != bSt) return bSt - aSt;
      return b.quantity.compareTo(a.quantity);
    });
    return matches;
  }

  Future<void> _openFirstSupervisorApprovalDialog({
    required MaterialRequestModel request,
    required List<InventoryItemModel> allItems,
    required List<WarehouseModel> allWarehouses,
    required ProcurementConfigModel config,
  }) async {
    final stockMatches = _findMatchingStockItems(request, allItems)
        .where((i) => i.quantity > 0)
        .toList();
    InventoryItemModel? chosenStock =
        stockMatches.isNotEmpty ? stockMatches.first : null;

    final availQty = chosenStock?.quantity ?? 0;
    String route = availQty >= request.quantity
        ? 'warehouse'
        : (availQty > 0 ? 'split' : 'procurement');

    final noteCtrl = TextEditingController();

    final ok = await showInventoryBottomSheet<bool>(
      context: context,
      maxWidth: 640,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final curAvail = chosenStock?.quantity ?? 0;
          final canFullWarehouse = curAvail >= request.quantity;
          final canSplit = curAvail > 0 && curAvail < request.quantity;

          return InventoryBottomSheetFrame(
            title: '1. Kademe Amir Onayı & Yönlendirme',
            subtitle:
                '${request.itemName} (${request.formattedQty} ${request.unit}) • Talep Eden: ${request.requesterName}',
            icon: Icons.verified_user_rounded,
            accentColor: const Color(0xFF059669),
            footer: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: const Text('Vazgeç'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 19),
                    label: const Text(
                      'Onayla ve Birime Yönlendir',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stockMatches.length > 1) ...[
                  InventoryDropdownField<String>(
                    label: 'Stok Karşılanacak Depo',
                    icon: Icons.warehouse_outlined,
                    accentColor: const Color(0xFF059669),
                    value: chosenStock?.id,
                    items: stockMatches
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(
                              '${m.warehouseName} (${m.formattedQty} ${m.unit} mevcut)',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      final found =
                          stockMatches.where((m) => m.id == val).firstOrNull;
                      if (found != null) {
                        setSheetState(() {
                          chosenStock = found;
                          if (found.quantity >= request.quantity) {
                            route = 'warehouse';
                          } else if (found.quantity > 0) {
                            route = 'split';
                          } else {
                            route = 'procurement';
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                const InventoryFieldLabel('Karşılama Yöntemi Seçin'),
                if (canFullWarehouse) ...[
                  _RouteChoiceCard(
                    title: 'Depodan Teslim Edilsin (Stokta Mevcut)',
                    subtitle:
                        '${chosenStock!.warehouseName} stoğunda ${chosenStock!.formattedQty} ${chosenStock!.unit} mevcut. Doğrudan Depocuya düşer.',
                    icon: Icons.inventory_2_rounded,
                    selected: route == 'warehouse',
                    accentColor: const Color(0xFF059669),
                    onTap: () => setSheetState(() => route = 'warehouse'),
                  ),
                  const SizedBox(height: 10),
                ],
                if (canSplit) ...[
                  _RouteChoiceCard(
                    title:
                        'Kısmi Teslim + Satın Alma (${chosenStock!.formattedQty} Depodan, ${InventoryItemModel.formatQty(request.quantity - curAvail)} Satın Almadan)',
                    subtitle:
                        'Mevcut stok hemen Depocuya düşer, eksik kalan miktar için otomatik satın alma süreci başlatılır.',
                    icon: Icons.call_split_rounded,
                    selected: route == 'split',
                    accentColor: const Color(0xFFD97706),
                    onTap: () => setSheetState(() => route = 'split'),
                  ),
                  const SizedBox(height: 10),
                ],
                _RouteChoiceCard(
                  title: config.requireSecondLevelForPurchase
                      ? 'Üst Yetkili Oluru ile Satın Almaya Sevk Et'
                      : 'Doğrudan Satın Alma Birimine Sevk Et',
                  subtitle: curAvail <= 0
                      ? 'Depoda bu üründen stok görünmüyor. Tedarik süreci başlatılır.'
                      : 'Mevcut depo stoğunu kullanmadan tamamı için satın alma süreci başlatılır.',
                  icon: Icons.shopping_bag_outlined,
                  selected: route == 'procurement',
                  accentColor: const Color(0xFF4F46E5),
                  onTap: () => setSheetState(() => route = 'procurement'),
                ),
                const SizedBox(height: 16),
                InventoryTextField(
                  controller: noteCtrl,
                  label: 'Amir Notu',
                  trailingText: 'Opsiyonel',
                  hint: 'Depocu veya üst yönetici için kısa not...',
                  icon: Icons.notes_rounded,
                  accentColor: const Color(0xFF059669),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (ok != true) return;

    final actorIsAlsoUpper = InventoryProcurementService.canApproveUpperLevel(
      _userData,
      config,
      currentUid: _actorUid,
    );
    final skipUpper = !config.requireSecondLevelForPurchase || actorIsAlsoUpper;

    try {
      await _service.approveByFirstSupervisor(
        request: request,
        route: route,
        actorUid: _actorUid,
        actorName: _actorName,
        sendDirectlyToProcurementIfNoUpperNeeded: skipUpper,
        targetWarehouseId: chosenStock?.warehouseId ?? '',
        targetWarehouseName: chosenStock?.warehouseName ?? '',
        linkedItemId: chosenStock?.id ?? '',
        availableStockForSplit: chosenStock?.quantity ?? 0,
        note: noteCtrl.text.trim(),
      );
      _showSnack('Talep onaylandı ve ilgili birime yönlendirildi.');
    } catch (e) {
      _showSnack('Onay işlemi başarısız: $e', isError: true);
    }
  }

  Future<void> _confirmUpperProcurementApproval(
    MaterialRequestModel request,
  ) async {
    final noteCtrl = TextEditingController();
    final ok = await showInventoryBottomSheet<bool>(
      context: context,
      maxWidth: 580,
      builder: (ctx) => InventoryBottomSheetFrame(
        title: 'Üst Makam Satın Alma Oluru',
        subtitle:
            '${request.itemName} (${request.formattedQty} ${request.unit}) • Talep: ${request.requesterName}',
        icon: Icons.verified_rounded,
        accentColor: const Color(0xFF4F46E5),
        footer: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Text('Vazgeç'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: const Icon(Icons.verified_outlined, size: 19),
                label: const Text(
                  'Satın Alma Oluru Ver',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: Text(
                '"${request.itemName}" depoda yeterli miktarda bulunmadığı için Satın Alma biriminin tedarikçi fiyat teklifleri toplamasına olur veriyorsunuz.',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF312E81),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            InventoryTextField(
              controller: noteCtrl,
              label: 'Üst Yönetici / Bütçe Notu',
              trailingText: 'Opsiyonel',
              hint: 'Örn: En az 3 farklı firmadan teklif alınsın...',
              icon: Icons.notes_rounded,
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    try {
      await _service.approveForProcurementByUpperApprover(
        request: request,
        actorUid: _actorUid,
        actorName: _actorName,
        note: noteCtrl.text.trim(),
      );
      _showSnack('Satın alma oluru verildi, talep Satın Alma birimine düştü.');
    } catch (e) {
      _showSnack('Hata: $e', isError: true);
    }
  }

  Future<void> _openRejectDialog(MaterialRequestModel request) async {
    final reasonCtrl = TextEditingController();
    final ok = await showInventoryBottomSheet<bool>(
      context: context,
      maxWidth: 560,
      builder: (ctx) => InventoryBottomSheetFrame(
        title: 'Malzeme Talebini Reddet',
        subtitle:
            '${request.itemName} (${request.formattedQty} ${request.unit}) • ${request.requesterName}',
        icon: Icons.cancel_outlined,
        accentColor: const Color(0xFFDC2626),
        footer: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Text('Vazgeç'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: const Icon(Icons.close_rounded, size: 19),
                label: const Text(
                  'Talebi Reddet',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        child: InventoryTextField(
          controller: reasonCtrl,
          label: 'Red Gerekçesi',
          isRequired: true,
          hint: 'Talep sahibine iletilecek kısa açıklama...',
          icon: Icons.comment_outlined,
          accentColor: const Color(0xFFDC2626),
          maxLines: 3,
          minLines: 2,
        ),
      ),
    );

    if (ok != true) return;
    final reason = reasonCtrl.text.trim().isNotEmpty
        ? reasonCtrl.text.trim()
        : 'Onay makamı tarafından uygun görülmedi.';
    try {
      await _service.rejectMaterialRequest(
        request: request,
        actorUid: _actorUid,
        actorName: _actorName,
        reason: reason,
      );
      _showSnack('Talep reddedildi.');
    } catch (e) {
      _showSnack('Hata: $e', isError: true);
    }
  }

  Future<void> _confirmGoodsReceiptDialog({
    required MaterialRequestModel request,
    required List<WarehouseModel> allWarehouses,
  }) async {
    if (allWarehouses.isEmpty) {
      _showSnack('Mal kabul yapılacak aktif depo bulunamadı.', isError: true);
      return;
    }

    WarehouseModel targetWh = allWarehouses.firstWhere(
      (w) => w.id == request.targetWarehouseId,
      orElse: () => allWarehouses.first,
    );
    final noteCtrl = TextEditingController();
    final quote = request.approvedQuote;

    final ok = await showInventoryBottomSheet<bool>(
      context: context,
      maxWidth: 600,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => InventoryBottomSheetFrame(
          title: 'Depo Mal Kabul Onayı',
          subtitle:
              '${request.itemName} (${request.formattedQty} ${request.unit}) fiziksel olarak depoya ulaştı mı?',
          icon: Icons.move_to_inbox_rounded,
          accentColor: const Color(0xFF0284C7),
          footer: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: const Text('Vazgeç'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 19),
                  label: const Text(
                    'Geldi • Depoya Giriş Yap',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (quote != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
                  ),
                  child: Text(
                    'Tedarikçi: ${quote.supplierName}\nToplam Tutar: ${_currencyFmt.format(quote.totalPrice)}'
                    '${request.autoRecordExpense ? '\n• Mal kabul onaylandığında Mali İşler giderlerine otomatik işlenecektir.' : ''}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0369A1),
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (allWarehouses.length > 1) ...[
                InventoryDropdownField<String>(
                  label: 'Giriş Yapılacak Depo',
                  isRequired: true,
                  icon: Icons.warehouse_outlined,
                  accentColor: const Color(0xFF0284C7),
                  value: targetWh.id,
                  items: allWarehouses
                      .map(
                        (w) => DropdownMenuItem(value: w.id, child: Text(w.name)),
                      )
                      .toList(),
                  onChanged: (v) {
                    final found =
                        allWarehouses.where((w) => w.id == v).firstOrNull;
                    if (found != null) {
                      setSheetState(() => targetWh = found);
                    }
                  },
                ),
                const SizedBox(height: 14),
              ],
              InventoryTextField(
                controller: noteCtrl,
                label: 'İrsaliye No / Mal Kabul Notu',
                trailingText: 'Opsiyonel',
                hint: 'Örn: İrsaliye #4821 eksiksiz teslim alındı',
                icon: Icons.receipt_long_outlined,
                accentColor: const Color(0xFF0284C7),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;
    try {
      await _service.confirmWarehouseReceiptByKeeper(
        request: request,
        warehouse: targetWh,
        actorUid: _actorUid,
        actorName: _actorName,
        receiptNote: noteCtrl.text.trim(),
      );
      _showSnack(
        'Mal kabul onaylandı! Ürün "${targetWh.name}" stoğuna eklendi ve teslimata hazır.',
      );
    } catch (e) {
      _showSnack('$e', isError: true);
    }
  }

  Future<void> _confirmDeliveryDialog({
    required MaterialRequestModel request,
    required List<InventoryItemModel> allItems,
  }) async {
    final candidates = _findMatchingStockItems(request, allItems)
        .where((it) => it.quantity >= request.quantity)
        .toList();

    if (candidates.isEmpty) {
      _showSnack(
        'Depoda teslim edilecek yeterli stok bulunamadı (${request.formattedQty} ${request.unit} gerekli). Lütfen önce depo stoğunu kontrol ediniz.',
        isError: true,
      );
      return;
    }

    InventoryItemModel selectedStock = candidates.firstWhere(
      (c) => c.warehouseId == request.targetWarehouseId,
      orElse: () => candidates.first,
    );
    final noteCtrl = TextEditingController();

    final ok = await showInventoryBottomSheet<bool>(
      context: context,
      maxWidth: 600,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => InventoryBottomSheetFrame(
          title: 'Malzeme Teslim Onayı',
          subtitle:
              '${request.requesterName} adlı personele ${request.formattedQty} ${request.unit} "${request.itemName}" teslim edilecek.',
          icon: Icons.handshake_rounded,
          accentColor: const Color(0xFF059669),
          footer: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: const Text('Vazgeç'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: const Icon(Icons.task_alt_rounded, size: 19),
                  label: const Text(
                    'Teslim Et & Stoktan Düş',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (candidates.length > 1) ...[
                InventoryDropdownField<String>(
                  label: 'Düşülecek Depo Stoğu',
                  isRequired: true,
                  icon: Icons.warehouse_outlined,
                  accentColor: const Color(0xFF059669),
                  value: selectedStock.id,
                  items: candidates
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            '${c.warehouseName} (Mevcut: ${c.formattedQty} ${c.unit})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    final found =
                        candidates.where((c) => c.id == v).firstOrNull;
                    if (found != null) {
                      setSheetState(() => selectedStock = found);
                    }
                  },
                ),
                const SizedBox(height: 14),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Text(
                    'Çıkış Yapılacak Depo: ${selectedStock.warehouseName} (Mevcut: ${selectedStock.formattedQty} ${selectedStock.unit})',
                    style: const TextStyle(
                      fontSize: 12.8,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF047857),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              InventoryTextField(
                controller: noteCtrl,
                label: 'Teslimat Notu',
                trailingText: 'Opsiyonel',
                hint: 'Örn: İmza karşılığı elden teslim edildi',
                icon: Icons.notes_rounded,
                accentColor: const Color(0xFF059669),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true) return;
    try {
      await _service.deliverRequestToRequester(
        request: request,
        stockItem: selectedStock,
        actorUid: _actorUid,
        actorName: _actorName,
        deliveryNote: noteCtrl.text.trim(),
      );
      _showSnack(
        'Teslimat tamamlandı! Depo stoğundan ${request.formattedQty} ${request.unit} otomatik düşüldü.',
      );
    } catch (e) {
      _showSnack('$e', isError: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANA EKRAN İSKELETİ
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 720;
    final standalone =
        widget.isStandalonePortal || !Navigator.of(context).canPop();

    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F7FB),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Sıkı Öğretmen İzolasyonu: Öğretmen rolündeki kullanıcı kazara bu ekrana gelirse
    // yalnızca kendi "Malzeme Talep" ekranını görsün.
    if ((_actorRole == 'ogretmen' || _actorRole == 'rehber_ogretmen') &&
        !InventoryProcurementService.canManageWarehouse(
          _userData,
          currentUid: _actorUid,
        ) &&
        !InventoryProcurementService.canManageProcurement(_userData)) {
      return TeacherMaterialRequestsScreen(
        institutionId: _institutionId,
        fixedSchoolTypeId: widget.fixedSchoolTypeId,
        fixedSchoolTypeName: widget.fixedSchoolTypeName,
        initialSchoolTypes: _schoolTypes,
      );
    }

    if (_schoolDocId.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F7FB),
        appBar: EduknAppBar(
          title: 'Depo ve Satın Alma',
          showBackButton: !standalone,
          actions: standalone ? [_buildStandaloneUserMenu(isMobile)] : null,
        ),
        body: const InventoryEmptyState(
          icon: Icons.domain_disabled_rounded,
          title: 'Kurum Bilgisi Çözümlenemedi',
          subtitle: 'Lütfen oturumunuzu yenileyip tekrar deneyiniz.',
        ),
      );
    }

    return StreamBuilder<ProcurementConfigModel>(
      stream: _service.watchProcurementConfig(_schoolDocId),
      builder: (context, configSnap) {
        final config = configSnap.data ?? const ProcurementConfigModel();

        return StreamBuilder<List<WarehouseModel>>(
          stream: _service.watchAllWarehouses(_schoolDocId),
          builder: (context, allWhSnap) {
            final allWarehouses = allWhSnap.data ?? const <WarehouseModel>[];
            final visibleWarehouses = _isSchoolTypeScoped
                ? allWarehouses
                    .where(
                      (w) =>
                          w.schoolTypeId.trim() ==
                          widget.fixedSchoolTypeId!.trim(),
                    )
                    .toList()
                : allWarehouses;

            final visibleWhIds = visibleWarehouses.map((w) => w.id).toSet();
            if (_selectedWarehouseId.isNotEmpty &&
                !visibleWhIds.contains(_selectedWarehouseId)) {
              _selectedWarehouseId = '';
            }

            return StreamBuilder<List<InventoryItemModel>>(
              stream: _service.watchInventoryItems(schoolDocId: _schoolDocId),
              builder: (context, itemsSnap) {
                final allItems = itemsSnap.data ?? const <InventoryItemModel>[];
                final scopedItems = allItems
                    .where((i) => visibleWhIds.contains(i.warehouseId))
                    .toList();

                return StreamBuilder<List<MaterialRequestModel>>(
                  stream: _service.watchMaterialRequests(
                    schoolDocId: _schoolDocId,
                    fixedSchoolTypeId: widget.fixedSchoolTypeId,
                  ),
                  builder: (context, reqSnap) {
                    final requests =
                        reqSnap.data ?? const <MaterialRequestModel>[];

                    final canSettings =
                        InventoryProcurementService.canManageSettings(
                      _userData,
                    );
                    final canWh =
                        InventoryProcurementService.canManageWarehouse(
                      _userData,
                      currentUid: _actorUid,
                    );
                    final canProc =
                        InventoryProcurementService.canManageProcurement(
                      _userData,
                    );
                    final canFirst =
                        InventoryProcurementService.canApproveFirstLevel(
                      _userData,
                      config,
                      currentUid: _actorUid,
                    );
                    final canUpper =
                        InventoryProcurementService.canApproveUpperLevel(
                      _userData,
                      config,
                      currentUid: _actorUid,
                    );

                    final pendingReqBadge = requests
                        .where(
                          (r) =>
                              r.status == 'pending_supervisor' ||
                              r.status == 'pending_upper_approver' ||
                              r.status == 'approved_for_warehouse' ||
                              r.status == 'purchase_ordered',
                        )
                        .length;

                    final pendingProcBadge = requests
                        .where(
                          (r) =>
                              r.status == 'in_procurement' ||
                              r.status == 'quotes_submitted' ||
                              r.status == 'purchase_approved',
                        )
                        .length;

                    return Scaffold(
                      backgroundColor: const Color(0xFFF4F7FB),
                      appBar: EduknAppBar(
                        title: widget.standaloneMode == 'purchasing'
                            ? 'Satın Alma & Teklif Yönetimi'
                            : widget.standaloneMode == 'warehouse'
                                ? 'Depo & Stok Yönetimi'
                                : 'Depo ve Satın Alma Yönetimi',
                        subtitle: _schoolName,
                        showBackButton: !standalone,
                        actions: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilledButton.tonalIcon(
                              onPressed: () async {
                                final ok = await MaterialRequestFormSheet.show(
                                  context,
                                  institutionId: _institutionId,
                                  schoolDocId: _schoolDocId,
                                  fixedSchoolTypeId: widget.fixedSchoolTypeId,
                                  fixedSchoolTypeName:
                                      widget.fixedSchoolTypeName,
                                  schoolTypeOptions: _schoolTypes,
                                  catalogSuggestions: allItems,
                                );
                                if (ok == true) {
                                  _showSnack(
                                    'Yeni malzeme talebi oluşturuldu.',
                                  );
                                }
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFEEF2FF),
                                foregroundColor: const Color(0xFF4338CA),
                                padding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 10 : 14,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11),
                                ),
                              ),
                              icon: const Icon(
                                Icons.add_shopping_cart_rounded,
                                size: 17,
                              ),
                              label: Text(
                                isMobile ? 'Talep' : 'Malzeme İste',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.8,
                                ),
                              ),
                            ),
                          ),
                          if (canSettings)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: IconButton(
                                tooltip: 'Depo ve Onay Ayarları',
                                style: IconButton.styleFrom(
                                  backgroundColor: const Color(0xFFF8FAFC),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(11),
                                    side: const BorderSide(
                                      color: Color(0xFFE2E8F0),
                                    ),
                                  ),
                                ),
                                onPressed: () => ProcurementSettingsSheet.show(
                                  context,
                                  institutionId: _institutionId,
                                  schoolDocId: _schoolDocId,
                                  fixedSchoolTypeId: widget.fixedSchoolTypeId,
                                  fixedSchoolTypeName:
                                      widget.fixedSchoolTypeName,
                                  currentWarehouses: allWarehouses,
                                  currentConfig: config,
                                ),
                                icon: const Icon(
                                  Icons.tune_rounded,
                                  size: 20,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ),
                          if (standalone)
                            Padding(
                              padding:
                                  const EdgeInsets.only(right: 10, left: 2),
                              child: _buildStandaloneUserMenu(isMobile),
                            ),
                        ],
                      ),
                      body: Column(
                        children: [
                          _buildTopNavigationStrip(
                            isMobile: isMobile,
                            stockCount: scopedItems.length,
                            reqBadge: pendingReqBadge,
                            procBadge: pendingProcBadge,
                          ),
                          Expanded(
                            child: IndexedStack(
                              index: _activeTab,
                              children: [
                                _buildWarehouseStockTab(
                                  isMobile: isMobile,
                                  visibleWarehouses: visibleWarehouses,
                                  allWarehouses: allWarehouses,
                                  scopedItems: scopedItems,
                                  requests: requests,
                                  canManageWh: canWh,
                                  canManageSettings: canSettings,
                                ),
                                _buildRequestsAndDeliveryTab(
                                  isMobile: isMobile,
                                  requests: requests,
                                  allItems: allItems,
                                  allWarehouses: allWarehouses,
                                  config: config,
                                  canFirst: canFirst,
                                  canUpper: canUpper,
                                  canWh: canWh,
                                  canProc: canProc,
                                ),
                                _buildProcurementQuotesTab(
                                  isMobile: isMobile,
                                  requests: requests,
                                  allWarehouses: allWarehouses,
                                  canProc: canProc,
                                  canUpper: canUpper,
                                  canWh: canWh,
                                ),
                                _buildTransactionsAndSettingsTab(
                                  isMobile: isMobile,
                                  visibleWarehouses: visibleWarehouses,
                                  allWarehouses: allWarehouses,
                                  config: config,
                                  canSettings: canSettings,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTopNavigationStrip({
    required bool isMobile,
    required int stockCount,
    required int reqBadge,
    required int procBadge,
  }) {
    final tabs = [
      (
        idx: 0,
        label: 'Depo & Stoklar',
        icon: Icons.inventory_2_rounded,
        badge: stockCount,
        badgeIsAlert: false,
      ),
      (
        idx: 1,
        label: 'Talepler & Teslimat',
        icon: Icons.fact_check_rounded,
        badge: reqBadge,
        badgeIsAlert: true,
      ),
      (
        idx: 2,
        label: 'Satın Alma & Teklifler',
        icon: Icons.request_quote_rounded,
        badge: procBadge,
        badgeIsAlert: true,
      ),
      (
        idx: 3,
        label: 'Stok Hareketleri',
        icon: Icons.history_rounded,
        badge: 0,
        badgeIsAlert: false,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 20,
        vertical: 10,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.map((t) {
            final selected = _activeTab == t.idx;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () => setState(() => _activeTab = t.idx),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 13 : 17,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF4F46E5)
                          : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF4F46E5)
                                  .withValues(alpha: 0.22),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        t.icon,
                        size: 17,
                        color:
                            selected ? Colors.white : const Color(0xFF475569),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        t.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : const Color(0xFF334155),
                        ),
                      ),
                      if (t.badge > 0) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.22)
                                : (t.badgeIsAlert
                                    ? const Color(0xFFFEF2F2)
                                    : const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            t.badge.toString(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: selected
                                  ? Colors.white
                                  : (t.badgeIsAlert
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF475569)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 0: DEPO & STOKLAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildWarehouseStockTab({
    required bool isMobile,
    required List<WarehouseModel> visibleWarehouses,
    required List<WarehouseModel> allWarehouses,
    required List<InventoryItemModel> scopedItems,
    required List<MaterialRequestModel> requests,
    required bool canManageWh,
    required bool canManageSettings,
  }) {
    if (visibleWarehouses.isEmpty) {
      return InventoryEmptyState(
        icon: Icons.warehouse_rounded,
        title: _isSchoolTypeScoped
            ? '${widget.fixedSchoolTypeName ?? 'Bu okul türü'} için özel depo tanımlanmamış'
            : 'Henüz Tanımlı Bir Depo Bulunmuyor',
        subtitle: _isSchoolTypeScoped
            ? 'Bu okul türü malzemelerini Merkez Ana Depo üzerinden kullanıyorsa taleplerinizi "Talepler & Teslimat" sekmesinden yönetebilirsiniz. Bu okula özel müstakil depo açmak isterseniz aşağıdaki butonu kullanın.'
            : 'Stok kartlarını girmeye başlamak için ilk deponuzu oluşturun.',
        actionLabel: (canManageWh || canManageSettings)
            ? (_isSchoolTypeScoped
                ? '${widget.fixedSchoolTypeName ?? 'Okul Türü'} Deposu Aç'
                : 'Merkez Ana Depo Oluştur')
            : null,
        actionIcon: Icons.add_business_rounded,
        onAction: (canManageWh || canManageSettings)
            ? (_isSchoolTypeScoped
                ? _quickCreateSchoolTypeWarehouse
                : () => _service.ensureDefaultWarehouse(
                      institutionId: _institutionId,
                      schoolDocId: _schoolDocId,
                    ))
            : null,
      );
    }

    final warehouseFilteredItems = _selectedWarehouseId.isEmpty
        ? scopedItems
        : scopedItems
            .where((i) => i.warehouseId == _selectedWarehouseId)
            .toList();

    final searchNorm = InventoryItemModel.normalizeTr(_stockSearch);
    final displayedItems = warehouseFilteredItems.where((it) {
      if (_selectedCategory != 'Tümü' && it.category != _selectedCategory) {
        return false;
      }
      if (_onlyCriticalStock && !it.isCriticalStock && !it.isOutOfStock) {
        return false;
      }
      if (searchNorm.isNotEmpty &&
          !it.normalizedName.contains(searchNorm) &&
          !InventoryItemModel.normalizeTr(it.category).contains(searchNorm) &&
          !InventoryItemModel.normalizeTr(it.shelfLocation)
              .contains(searchNorm)) {
        return false;
      }
      return true;
    }).toList();

    final criticalCount = warehouseFilteredItems
        .where((i) => i.isCriticalStock || i.isOutOfStock)
        .length;
    final inStockCount =
        warehouseFilteredItems.where((i) => i.quantity > 0).length;
    final waitingDeliveryCount = requests
        .where((r) => r.status == 'approved_for_warehouse')
        .length;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWarehouseSelectorBar(
                      visibleWarehouses: visibleWarehouses,
                      scopedItems: scopedItems,
                    ),
                    const SizedBox(height: 14),
                    _buildStockKpiRow(
                      totalItems: warehouseFilteredItems.length,
                      inStock: inStockCount,
                      critical: criticalCount,
                      waitingDelivery: waitingDeliveryCount,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: isMobile ? double.infinity : 340,
                            child: InventorySearchField(
                              controller: _stockSearchCtrl,
                              value: _stockSearch,
                              hint: 'Malzeme adı, kategori veya raf kodu ara...',
                              onChanged: (v) =>
                                  setState(() => _stockSearch = v),
                              onClear: () {
                                _stockSearchCtrl.clear();
                                setState(() => _stockSearch = '');
                              },
                            ),
                          ),
                          SizedBox(
                            width: isMobile ? double.infinity : 230,
                            child: InventoryDropdownField<String>(
                              icon: Icons.category_outlined,
                              value: _selectedCategory,
                              items: [
                                const DropdownMenuItem(
                                  value: 'Tümü',
                                  child: Text('Tüm Kategoriler'),
                                ),
                                ...InventoryItemModel.defaultCategories.map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(
                                      c,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selectedCategory = v);
                                }
                              },
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(13),
                            onTap: () => setState(
                              () => _onlyCriticalStock = !_onlyCriticalStock,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: _onlyCriticalStock
                                    ? const Color(0xFFFEF2F2)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: _onlyCriticalStock
                                      ? const Color(0xFFF87171)
                                      : const Color(0xFFD5DFEC),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 17,
                                    color: _onlyCriticalStock
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    'Kritik / Tükenen ($criticalCount)',
                                    style: TextStyle(
                                      fontSize: 12.8,
                                      fontWeight: FontWeight.w700,
                                      color: _onlyCriticalStock
                                          ? const Color(0xFFB91C1C)
                                          : const Color(0xFF334155),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (canManageWh)
                            FilledButton.icon(
                              onPressed: () => _openAddOrEditItemSheet(
                                visibleWarehouses: visibleWarehouses,
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF4F46E5),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 13.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              icon: const Icon(Icons.add_box_rounded, size: 18),
                              label: const Text(
                                'Yeni Malzeme Gir',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (displayedItems.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: InventoryEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: warehouseFilteredItems.isEmpty
                      ? 'Bu Depoda Henüz Malzeme Kartı Yok'
                      : 'Arama Kriterlerine Uygun Malzeme Bulunamadı',
                  subtitle: warehouseFilteredItems.isEmpty
                      ? 'Depocu veya yetkili personel olarak ilk malzeme stok kartını ekleyerek envanter takibini başlatabilirsiniz.'
                      : 'Arama metnini veya kategori filtresini temizleyerek tüm stokları görüntüleyebilirsiniz.',
                  actionLabel: canManageWh ? 'Depoya Yeni Malzeme Ekle' : null,
                  actionIcon: Icons.add_box_rounded,
                  onAction: canManageWh
                      ? () => _openAddOrEditItemSheet(
                            visibleWarehouses: visibleWarehouses,
                          )
                      : null,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: isMobile ? 600 : 410,
                    mainAxisExtent: canManageWh ? 204 : 154,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, idx) => _buildStockItemCard(
                      item: displayedItems[idx],
                      visibleWarehouses: visibleWarehouses,
                      allWarehouses: allWarehouses,
                      canManageWh: canManageWh,
                    ),
                    childCount: displayedItems.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarehouseSelectorBar({
    required List<WarehouseModel> visibleWarehouses,
    required List<InventoryItemModel> scopedItems,
  }) {
    if (visibleWarehouses.length <= 1 && _isSchoolTypeScoped) {
      final wh = visibleWarehouses.first;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.warehouse_rounded,
                size: 18,
                color: Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Aktif Depo: ${wh.name}'
                '${wh.location.isNotEmpty ? ' • ${wh.location}' : ''}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _WarehouseFilterPill(
            label: 'Tüm Depolar (${scopedItems.length})',
            icon: Icons.layers_rounded,
            selected: _selectedWarehouseId.isEmpty,
            accentColor: const Color(0xFF4F46E5),
            onTap: () => setState(() => _selectedWarehouseId = ''),
          ),
          ...visibleWarehouses.map((wh) {
            final count =
                scopedItems.where((i) => i.warehouseId == wh.id).length;
            return _WarehouseFilterPill(
              label: '${wh.name} ($count)',
              icon: wh.isCentral ? Icons.domain_rounded : Icons.school_rounded,
              selected: _selectedWarehouseId == wh.id,
              accentColor: const Color(0xFF0D9488),
              onTap: () => setState(() => _selectedWarehouseId = wh.id),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStockKpiRow({
    required int totalItems,
    required int inStock,
    required int critical,
    required int waitingDelivery,
  }) {
    final kpis = [
      (
        label: 'Toplam Malzeme Çeşidi',
        val: totalItems.toString(),
        color: const Color(0xFF4F46E5),
        bg: const Color(0xFFEEF2FF),
        icon: Icons.category_rounded,
      ),
      (
        label: 'Stokta Mevcut',
        val: inStock.toString(),
        color: const Color(0xFF059669),
        bg: const Color(0xFFECFDF5),
        icon: Icons.check_circle_rounded,
      ),
      (
        label: 'Kritik / Tükenen',
        val: critical.toString(),
        color: const Color(0xFFDC2626),
        bg: const Color(0xFFFEF2F2),
        icon: Icons.warning_amber_rounded,
      ),
      (
        label: 'Teslim Bekleyen Talep',
        val: waitingDelivery.toString(),
        color: const Color(0xFF0284C7),
        bg: const Color(0xFFF0F9FF),
        icon: Icons.local_mall_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        final w = compact
            ? (constraints.maxWidth - 10) / 2
            : (constraints.maxWidth - 30) / 4;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: kpis.map((k) {
            return Container(
              width: w,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: k.bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(k.icon, color: k.color, size: 20),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          k.val,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: k.color,
                          ),
                        ),
                        Text(
                          k.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildStockItemCard({
    required InventoryItemModel item,
    required List<WarehouseModel> visibleWarehouses,
    required List<WarehouseModel> allWarehouses,
    required bool canManageWh,
  }) {
    final isAlert = item.isOutOfStock || item.isCriticalStock;
    final badgeBg = item.isOutOfStock
        ? const Color(0xFFFEE2E2)
        : item.isCriticalStock
            ? const Color(0xFFFEF3C7)
            : const Color(0xFFECFDF5);
    final badgeFg = item.isOutOfStock
        ? const Color(0xFFB91C1C)
        : item.isCriticalStock
            ? const Color(0xFFB45309)
            : const Color(0xFF047857);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isAlert ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.imageUrl.isNotEmpty)
                GestureDetector(
                  onTap: () => _previewImage(item.imageUrl),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      item.imageUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _defaultItemAvatar(),
                    ),
                  ),
                )
              else
                _defaultItemAvatar(),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item.warehouseName} • ${item.category}'
                      '${item.shelfLocation.isNotEmpty ? ' • ${item.shelfLocation}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${item.formattedQty} ${item.unit}',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: badgeFg,
                      ),
                    ),
                    if (item.minStockLevel > 0)
                      Text(
                        'Alt: ${item.formattedMinQty}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: badgeFg.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              if (item.lastUnitPrice > 0)
                Text(
                  'Son Alım: ${_currencyFmt.format(item.lastUnitPrice)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              const Spacer(),
              if (item.productLink.isNotEmpty)
                IconButton(
                  tooltip: 'Ürün Linki',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _openUrl(item.productLink),
                  icon: const Icon(
                    Icons.open_in_new_rounded,
                    size: 17,
                    color: Color(0xFF2563EB),
                  ),
                ),
            ],
          ),
          if (canManageWh) ...[
            const Divider(height: 14, color: Color(0xFFF1F5F9)),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openQuickStockDialog(item, 'in'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF059669),
                      backgroundColor: const Color(0xFFF0FDF4),
                      side: const BorderSide(color: Color(0xFFA7F3D0)),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text(
                      'Giriş',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openQuickStockDialog(item, 'out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      backgroundColor: const Color(0xFFFEF2F2),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.remove_rounded, size: 16),
                    label: const Text(
                      'Çıkış',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (allWarehouses.length > 1) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Başka Depoya Transfer Et',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openTransferDialog(item, allWarehouses),
                    icon: const Icon(
                      Icons.swap_horiz_rounded,
                      size: 19,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ],
                IconButton(
                  tooltip: 'Kartı Düzenle',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _openAddOrEditItemSheet(
                    visibleWarehouses: visibleWarehouses,
                    existing: item,
                  ),
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _defaultItemAvatar() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.inventory_2_outlined,
        color: Color(0xFF4F46E5),
        size: 22,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 1: TALEPLER, ONAYLAR, MAL KABUL & TESLİMAT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRequestsAndDeliveryTab({
    required bool isMobile,
    required List<MaterialRequestModel> requests,
    required List<InventoryItemModel> allItems,
    required List<WarehouseModel> allWarehouses,
    required ProcurementConfigModel config,
    required bool canFirst,
    required bool canUpper,
    required bool canWh,
    required bool canProc,
  }) {
    final supCount =
        requests.where((r) => r.status == 'pending_supervisor').length;
    final upperCount =
        requests.where((r) => r.status == 'pending_upper_approver').length;
    final whOpsCount = requests
        .where(
          (r) =>
              r.status == 'approved_for_warehouse' ||
              r.status == 'purchase_ordered',
        )
        .length;
    final closedCount = requests.where((r) => r.isClosed).length;

    final filtered = requests.where((r) {
      switch (_requestFilter) {
        case 'actionable':
          return !r.isClosed;
        case 'supervisor':
          return r.status == 'pending_supervisor';
        case 'upper':
          return r.status == 'pending_upper_approver';
        case 'warehouse_ops':
          return r.status == 'approved_for_warehouse' ||
              r.status == 'purchase_ordered';
        case 'closed':
          return r.isClosed;
        default:
          return true;
      }
    }).toList();

    final filterChips = [
      (
        key: 'actionable',
        label: 'Açık Süreçler (${requests.length - closedCount})',
      ),
      (key: 'warehouse_ops', label: 'Depo Mal Kabul & Teslimat ($whOpsCount)'),
      (key: 'supervisor', label: '1. Amir Onayı ($supCount)'),
      (key: 'upper', label: 'Üst Yetkili Oluru ($upperCount)'),
      (key: 'closed', label: 'Tamamlanan / Red ($closedCount)'),
      (key: 'all', label: 'Tümü (${requests.length})'),
    ];

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1060),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: filterChips.map((fc) {
                      final sel = _requestFilter == fc.key;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () =>
                              setState(() => _requestFilter = fc.key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9.5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  sel ? const Color(0xFF4F46E5) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sel
                                    ? const Color(0xFF4F46E5)
                                    : const Color(0xFFD5DFEC),
                              ),
                            ),
                            child: Text(
                              fc.label,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: sel
                                    ? Colors.white
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
            if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: InventoryEmptyState(
                  icon: Icons.assignment_turned_in_outlined,
                  title: 'Bekleyen Malzeme Talebi Bulunmuyor',
                  subtitle:
                      'Öğretmen veya personeller yeni bir malzeme talebi oluşturduğunda onay, mal kabul ve teslimat adımları burada listelenir.',
                  actionLabel: 'Yeni Malzeme Talebi Aç',
                  actionIcon: Icons.add_shopping_cart_rounded,
                  onAction: () async {
                    final ok = await MaterialRequestFormSheet.show(
                      context,
                      institutionId: _institutionId,
                      schoolDocId: _schoolDocId,
                      fixedSchoolTypeId: widget.fixedSchoolTypeId,
                      fixedSchoolTypeName: widget.fixedSchoolTypeName,
                      schoolTypeOptions: _schoolTypes,
                      catalogSuggestions: allItems,
                    );
                    if (ok == true) {
                      _showSnack('Yeni malzeme talebi oluşturuldu.');
                    }
                  },
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, idx) => _buildOperationalRequestCard(
                    request: filtered[idx],
                    allItems: allItems,
                    allWarehouses: allWarehouses,
                    config: config,
                    canFirst: canFirst,
                    canUpper: canUpper,
                    canWh: canWh,
                    canProc: canProc,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationalRequestCard({
    required MaterialRequestModel request,
    required List<InventoryItemModel> allItems,
    required List<WarehouseModel> allWarehouses,
    required ProcurementConfigModel config,
    required bool canFirst,
    required bool canUpper,
    required bool canWh,
    required bool canProc,
  }) {
    final stockMatches = _findMatchingStockItems(request, allItems);
    final totalMatchedStock =
        stockMatches.fold<double>(0, (sum, e) => sum + e.quantity);
    final bestStock = stockMatches.isNotEmpty ? stockMatches.first : null;
    final expanded = _expandedRequestIds.contains(request.id);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: request.isUrgent && !request.isClosed
              ? const Color(0xFFFCA5A5)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildStatusPill(request.status, request.statusLabel),
              if (request.isUrgent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'ACİL TALEP',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ),
              if (request.schoolTypeName.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    request.schoolTypeName,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4338CA),
                    ),
                  ),
                ),
              Text(
                '${request.requesterName} • ${_dateFmt.format(request.createdAt)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.itemName,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (request.description.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        request.description,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF334155),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD5DFEC)),
                ),
                child: Text(
                  '${request.formattedQty} ${request.unit}',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),

          if (!request.isClosed) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: totalMatchedStock >= request.quantity
                    ? const Color(0xFFECFDF5)
                    : totalMatchedStock > 0
                        ? const Color(0xFFFFFBEB)
                        : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: totalMatchedStock >= request.quantity
                      ? const Color(0xFFA7F3D0)
                      : totalMatchedStock > 0
                          ? const Color(0xFFFDE68A)
                          : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    totalMatchedStock >= request.quantity
                        ? Icons.check_circle_outline_rounded
                        : totalMatchedStock > 0
                            ? Icons.pie_chart_outline_rounded
                            : Icons.shopping_bag_outlined,
                    size: 17,
                    color: totalMatchedStock >= request.quantity
                        ? const Color(0xFF047857)
                        : totalMatchedStock > 0
                            ? const Color(0xFFB45309)
                            : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      totalMatchedStock >= request.quantity
                          ? 'Depoda Yeterli Stok Var: ${bestStock!.warehouseName} (${bestStock.formattedQty} ${bestStock.unit} mevcut)'
                          : totalMatchedStock > 0
                              ? 'Kısmi Stok Mevcut: Depolarda toplam ${InventoryItemModel.formatQty(totalMatchedStock)} ${request.unit} var (${InventoryItemModel.formatQty(request.quantity - totalMatchedStock)} ${request.unit} eksik)'
                              : 'Depolarda Bu Malzemeden Stok Yok (0 ${request.unit})',
                      style: TextStyle(
                        fontSize: 12.2,
                        fontWeight: FontWeight.w700,
                        color: totalMatchedStock >= request.quantity
                            ? const Color(0xFF065F46)
                            : totalMatchedStock > 0
                                ? const Color(0xFF92400E)
                                : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (request.productLink.isNotEmpty || request.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (request.productLink.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _openUrl(request.productLink),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.link_rounded, size: 16),
                    label: const Text(
                      'Ürün Linki',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ...request.imageUrls.map(
                  (url) => GestureDetector(
                    onTap: () => _previewImage(url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        url,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (request.status == 'pending_supervisor' && canFirst) ...[
                FilledButton.icon(
                  onPressed: () => _openFirstSupervisorApprovalDialog(
                    request: request,
                    allItems: allItems,
                    allWarehouses: allWarehouses,
                    config: config,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text(
                    'Onayla & Yönlendir',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openRejectDialog(request),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 17),
                  label: const Text('Reddet'),
                ),
              ],
              if (request.status == 'pending_upper_approver' && canUpper) ...[
                FilledButton.icon(
                  onPressed: () => _confirmUpperProcurementApproval(request),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text(
                    'Satın Alma Oluru Ver',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openRejectDialog(request),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 17),
                  label: const Text('Reddet'),
                ),
              ],
              if (request.status == 'purchase_ordered' && canWh)
                FilledButton.icon(
                  onPressed: () => _confirmGoodsReceiptDialog(
                    request: request,
                    allWarehouses: allWarehouses,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(Icons.move_to_inbox_rounded, size: 18),
                  label: const Text(
                    'Depoya Geldi • Mal Kabul Onayla',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              if (request.status == 'approved_for_warehouse' && canWh)
                FilledButton.icon(
                  onPressed: () => _confirmDeliveryDialog(
                    request: request,
                    allItems: allItems,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(Icons.handshake_rounded, size: 18),
                  label: const Text(
                    'Teslim Et (Stoktan Düş)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              if ((request.status == 'in_procurement' ||
                      request.status == 'quotes_submitted' ||
                      request.status == 'purchase_approved') &&
                  (canProc || canUpper))
                FilledButton.tonalIcon(
                  onPressed: () => QuoteManagementSheet.show(
                    context,
                    request: request,
                    allWarehouses: allWarehouses,
                    canManageProcurement: canProc,
                    canApproveUpper: canUpper,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEEF2FF),
                    foregroundColor: const Color(0xFF4338CA),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(Icons.request_quote_rounded, size: 18),
                  label: Text(
                    request.status == 'quotes_submitted' && canUpper
                        ? 'Teklifleri İncele & Onayla (${request.quotes.length})'
                        : 'Satın Alma & Teklifler (${request.quotes.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    if (expanded) {
                      _expandedRequestIds.remove(request.id);
                    } else {
                      _expandedRequestIds.add(request.id);
                    }
                  });
                },
                icon: Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.history_toggle_off_rounded,
                  size: 17,
                ),
                label: Text(
                  expanded
                      ? 'Tarihçeyi Gizle'
                      : 'Tarihçe (${request.timeline.length})',
                ),
              ),
            ],
          ),

          if (expanded && request.timeline.isNotEmpty) ...[
            const Divider(height: 20, color: Color(0xFFF1F5F9)),
            ...request.timeline.reversed.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${_dateFmt.format(t.timestamp)} — ${t.title} (${t.actorName})'
                  '${t.note.isNotEmpty ? ' [Not: ${t.note}]' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 2: SATIN ALMA & TEDARİKÇİ TEKLİFLERİ
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProcurementQuotesTab({
    required bool isMobile,
    required List<MaterialRequestModel> requests,
    required List<WarehouseModel> allWarehouses,
    required bool canProc,
    required bool canUpper,
    required bool canWh,
  }) {
    final procRequests = requests.where((r) {
      return r.status == 'in_procurement' ||
          r.status == 'quotes_submitted' ||
          r.status == 'purchase_approved' ||
          r.status == 'purchase_ordered' ||
          r.wasPurchased;
    }).toList();

    final filtered = procRequests.where((r) {
      switch (_procurementFilter) {
        case 'active':
          return !r.isClosed;
        case 'quotes':
          return r.status == 'in_procurement';
        case 'approval':
          return r.status == 'quotes_submitted';
        case 'ordered':
          return r.status == 'purchase_approved' ||
              r.status == 'purchase_ordered';
        case 'completed':
          return r.wasPurchased &&
              (r.status == 'approved_for_warehouse' || r.status == 'delivered');
        default:
          return true;
      }
    }).toList();

    final chips = [
      (key: 'active', label: 'Aktif Tedarik Süreçleri'),
      (key: 'quotes', label: 'Teklif Bekleyenler'),
      (key: 'approval', label: 'Üst Amir Teklif Seçimi'),
      (key: 'ordered', label: 'Sipariş & Yoldakiler'),
      (key: 'completed', label: 'Tamamlanan Satın Alımlar'),
    ];

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1060),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: chips.map((c) {
                      final sel = _procurementFilter == c.key;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () =>
                              setState(() => _procurementFilter = c.key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9.5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  sel ? const Color(0xFF4F46E5) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sel
                                    ? const Color(0xFF4F46E5)
                                    : const Color(0xFFD5DFEC),
                              ),
                            ),
                            child: Text(
                              c.label,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: sel
                                    ? Colors.white
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
            if (filtered.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: InventoryEmptyState(
                  icon: Icons.request_quote_outlined,
                  title: 'Bu Aşamada Satın Alma Kaydı Bulunmuyor',
                  subtitle:
                      'Depo stoğunda bulunmayan ve satın alma oluru verilen talepler burada teklif toplama ve sipariş adımlarıyla yönetilir.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, idx) {
                    final r = filtered[idx];
                    final approvedQ = r.approvedQuote;
                    final minQuotePrice = r.quotes.isEmpty
                        ? null
                        : r.quotes
                            .map((q) => q.totalPrice)
                            .reduce((a, b) => a < b ? a : b);

                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F172A)
                                .withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildStatusPill(r.status, r.statusLabel),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${r.quotes.length} Teklif Girildi',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ),
                              if (r.accountingTransactionId.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.account_balance_wallet_rounded,
                                        size: 13,
                                        color: Color(0xFF047857),
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Mali İşlere İşlendi',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF047857),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${r.itemName} (${r.formattedQty} ${r.unit})',
                                      style: const TextStyle(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Talep Eden: ${r.requesterName}'
                                      '${r.schoolTypeName.isNotEmpty ? ' • ${r.schoolTypeName}' : ''}'
                                      '${r.targetWarehouseName.isNotEmpty ? ' • Hedef Depo: ${r.targetWarehouseName}' : ''}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (approvedQ != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(11),
                                    border: Border.all(
                                      color: const Color(0xFFA7F3D0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _currencyFmt
                                            .format(approvedQ.totalPrice),
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF047857),
                                        ),
                                      ),
                                      Text(
                                        approvedQ.supplierName,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF065F46),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (minQuotePrice != null)
                                Text(
                                  'En Düşük: ${_currencyFmt.format(minQuotePrice)}',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF4F46E5),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: () => QuoteManagementSheet.show(
                                  context,
                                  request: r,
                                  allWarehouses: allWarehouses,
                                  canManageProcurement: canProc,
                                  canApproveUpper: canUpper,
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF4F46E5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.request_quote_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  r.status == 'in_procurement' && canProc
                                      ? 'Teklif Gir / Onaya Sun'
                                      : r.status == 'quotes_submitted' &&
                                              canUpper
                                          ? 'Teklif Seç & Alım Onayı Ver'
                                          : r.status == 'purchase_approved' &&
                                                  canProc
                                              ? 'Siparişi Geç & Depoya Bildir'
                                              : 'Teklif & Sipariş Detayı',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (r.status == 'purchase_ordered' && canWh)
                                FilledButton.icon(
                                  onPressed: () => _confirmGoodsReceiptDialog(
                                    request: r,
                                    allWarehouses: allWarehouses,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF0284C7),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.move_to_inbox_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Depoya Geldi • Mal Kabul Onayla',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              if (r.productLink.isNotEmpty)
                                OutlinedButton.icon(
                                  onPressed: () => _openUrl(r.productLink),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.open_in_new_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Talep Linki'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEKME 3: STOK HAREKETLERİ DENETİM İZİ
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTransactionsAndSettingsTab({
    required bool isMobile,
    required List<WarehouseModel> visibleWarehouses,
    required List<WarehouseModel> allWarehouses,
    required ProcurementConfigModel config,
    required bool canSettings,
  }) {
    final visibleIds = visibleWarehouses.map((w) => w.id).toSet();

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1060),
        child: StreamBuilder<List<StockTransactionModel>>(
          stream: _service.watchStockTransactions(
            schoolDocId: _schoolDocId,
            allowedWarehouseIds: visibleIds,
            selectedWarehouseId:
                _selectedWarehouseId.isNotEmpty ? _selectedWarehouseId : null,
          ),
          builder: (context, txSnap) {
            final txs = txSnap.data ?? const <StockTransactionModel>[];

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Son Stok Giriş, Çıkış, Transfer ve Teslimat Kayıtları',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        if (canSettings)
                          FilledButton.tonalIcon(
                            onPressed: () => ProcurementSettingsSheet.show(
                              context,
                              institutionId: _institutionId,
                              schoolDocId: _schoolDocId,
                              fixedSchoolTypeId: widget.fixedSchoolTypeId,
                              fixedSchoolTypeName: widget.fixedSchoolTypeName,
                              currentWarehouses: allWarehouses,
                              currentConfig: config,
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFEEF2FF),
                              foregroundColor: const Color(0xFF4338CA),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                            icon: const Icon(Icons.tune_rounded, size: 17),
                            label: const Text(
                              'Depo & Onay Ayarları',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (txs.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: InventoryEmptyState(
                      icon: Icons.history_rounded,
                      title: 'Henüz Stok Hareketi Kaydedilmemiş',
                      subtitle:
                          'Depoya yapılan her malzeme girişi, çıkışı, sayım düzeltmesi, transfer ve öğretmen teslimatı burada tarihçesiyle listelenir.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    sliver: SliverList.separated(
                      itemCount: txs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final tx = txs[idx];
                        final isAdd = tx.isAddition;
                        return Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isAdd
                                      ? const Color(0xFFECFDF5)
                                      : const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isAdd
                                      ? Icons.south_west_rounded
                                      : Icons.north_east_rounded,
                                  color: isAdd
                                      ? const Color(0xFF059669)
                                      : const Color(0xFFDC2626),
                                  size: 19,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${tx.itemName} • ${tx.typeLabel}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${tx.warehouseName} • İşlemi Yapan: ${tx.actorName}'
                                      '${tx.recipientName.isNotEmpty ? ' • Alıcı/Hedef: ${tx.recipientName}' : ''}'
                                      ' • ${_dateFmt.format(tx.createdAt)}',
                                      style: const TextStyle(
                                        fontSize: 11.8,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    if (tx.note.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Not: ${tx.note}',
                                        style: const TextStyle(
                                          fontSize: 11.8,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${isAdd ? '+' : '-'}${InventoryItemModel.formatQty(tx.quantity)} ${tx.unit}',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w900,
                                      color: isAdd
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFDC2626),
                                    ),
                                  ),
                                  Text(
                                    '${InventoryItemModel.formatQty(tx.previousQty)} → ${InventoryItemModel.formatQty(tx.newQty)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusPill(String status, String label) {
    Color bg = const Color(0xFFF1F5F9);
    Color fg = const Color(0xFF334155);
    switch (status) {
      case 'pending_supervisor':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        break;
      case 'pending_upper_approver':
        bg = const Color(0xFFFFEDD5);
        fg = const Color(0xFFC2410C);
        break;
      case 'in_procurement':
      case 'quotes_submitted':
        bg = const Color(0xFFE0E7FF);
        fg = const Color(0xFF4338CA);
        break;
      case 'purchase_approved':
      case 'purchase_ordered':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1D4ED8);
        break;
      case 'approved_for_warehouse':
        bg = const Color(0xFFCCFBF1);
        fg = const Color(0xFF0F766E);
        break;
      case 'delivered':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF047857);
        break;
      case 'rejected':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFB91C1C);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

class _WarehouseFilterPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _WarehouseFilterPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9.5),
          decoration: BoxDecoration(
            color: selected ? accentColor : Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? accentColor : const Color(0xFFD5DFEC),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : accentColor,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.8,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeSelectTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ModeSelectTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color:
              selected ? color.withValues(alpha: 0.10) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? color : const Color(0xFFD5DFEC),
            width: selected ? 1.7 : 1.1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? color : const Color(0xFF64748B),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected ? color : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _RouteChoiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: 0.07)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? accentColor : const Color(0xFFD5DFEC),
            width: selected ? 1.8 : 1.1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? accentColor
                    : accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                selected ? Icons.check_rounded : icon,
                size: 19,
                color: selected ? Colors.white : accentColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
