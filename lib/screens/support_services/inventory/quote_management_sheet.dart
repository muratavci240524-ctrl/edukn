import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/school/inventory_procurement_models.dart';
import '../../../services/inventory_procurement_service.dart';
import 'inventory_ui_widgets.dart';

/// Satın Alma Teklif Toplama, Üst Amir Teklif Seçimi ve Sipariş Geçme Paneli (Tam Alttan Açılan Modern Tasarım)
class QuoteManagementSheet extends StatefulWidget {
  final MaterialRequestModel request;
  final List<WarehouseModel> allWarehouses;
  final bool canManageProcurement;
  final bool canApproveUpper;

  const QuoteManagementSheet({
    super.key,
    required this.request,
    required this.allWarehouses,
    required this.canManageProcurement,
    required this.canApproveUpper,
  });

  static Future<bool?> show(
    BuildContext context, {
    required MaterialRequestModel request,
    required List<WarehouseModel> allWarehouses,
    required bool canManageProcurement,
    required bool canApproveUpper,
  }) {
    return showInventoryBottomSheet<bool>(
      context: context,
      maxWidth: 760,
      builder: (_) => QuoteManagementSheet(
        request: request,
        allWarehouses: allWarehouses,
        canManageProcurement: canManageProcurement,
        canApproveUpper: canApproveUpper,
      ),
    );
  }

  @override
  State<QuoteManagementSheet> createState() => _QuoteManagementSheetState();
}

class _QuoteManagementSheetState extends State<QuoteManagementSheet> {
  final _service = InventoryProcurementService();
  final _currencyFmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

  late List<SupplierQuoteModel> _quotes;
  bool _addingNewQuote = false;
  bool _saving = false;
  bool _uploadingDoc = false;

  // Yeni teklif form alanları
  final _supplierCtrl = TextEditingController();
  final _unitPriceCtrl = TextEditingController();
  final _deliveryCtrl = TextEditingController(text: '2 İş Günü');
  final _linkCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int _vatRate = 20;
  bool _vatIncluded = true;
  bool _isRecommended = false;
  String _attachmentUrl = '';

  // Sipariş aşaması alanları (purchase_approved -> purchase_ordered)
  List<Map<String, dynamic>> _cashes = [];
  String _selectedWarehouseId = '';
  String _selectedKasaId = '';
  bool _autoRecordExpense = true;
  final _orderNoteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _quotes = List<SupplierQuoteModel>.from(widget.request.quotes);
    _autoRecordExpense = widget.request.autoRecordExpense;

    if (widget.request.targetWarehouseId.isNotEmpty &&
        widget.allWarehouses
            .any((w) => w.id == widget.request.targetWarehouseId)) {
      _selectedWarehouseId = widget.request.targetWarehouseId;
    } else if (widget.request.schoolTypeId.isNotEmpty) {
      final stWh = widget.allWarehouses
          .where((w) => w.schoolTypeId == widget.request.schoolTypeId)
          .firstOrNull;
      _selectedWarehouseId = stWh?.id ??
          (widget.allWarehouses.isNotEmpty
              ? widget.allWarehouses.first.id
              : '');
    } else if (widget.allWarehouses.isNotEmpty) {
      _selectedWarehouseId = widget.allWarehouses.first.id;
    }

    if (_quotes.isEmpty &&
        widget.canManageProcurement &&
        widget.request.status == 'in_procurement') {
      _addingNewQuote = true;
    }

    if (widget.request.status == 'purchase_approved') {
      _loadCashes();
    }
  }

  Future<void> _loadCashes() async {
    final cashes =
        await _service.fetchInstitutionCashes(widget.request.institutionId);
    if (!mounted) return;
    setState(() {
      _cashes = cashes;
      if (widget.request.selectedKasaId.isNotEmpty &&
          cashes.any((c) => c['id'] == widget.request.selectedKasaId)) {
        _selectedKasaId = widget.request.selectedKasaId;
      } else if (cashes.isNotEmpty) {
        _selectedKasaId = cashes.first['id'].toString();
      }
    });
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _unitPriceCtrl.dispose();
    _deliveryCtrl.dispose();
    _linkCtrl.dispose();
    _noteCtrl.dispose();
    _orderNoteCtrl.dispose();
    super.dispose();
  }

  double _parsePriceInput() {
    final raw = _unitPriceCtrl.text.trim();
    if (raw.isEmpty) return 0;
    return double.tryParse(raw.replaceAll(',', '.')) ??
        double.tryParse(raw.replaceAll('.', '').replaceAll(',', '.')) ??
        0;
  }

  double _computeCalculatedTotal() {
    final up = _parsePriceInput();
    final sub = up * widget.request.quantity;
    if (_vatIncluded) return sub;
    return sub * (1 + (_vatRate / 100.0));
  }

  Future<void> _pickQuoteAttachment() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final f = picked.files.first;
      if (f.bytes == null) return;

      setState(() => _uploadingDoc = true);
      final url = await _service.uploadAttachmentBytes(
        schoolDocId: widget.request.schoolDocId,
        bytes: f.bytes!,
        fileName: f.name,
      );
      if (mounted) {
        setState(() {
          _attachmentUrl = url;
          _uploadingDoc = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingDoc = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dosya yüklenemedi: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _addQuoteToList() async {
    final supplier = _supplierCtrl.text.trim();
    final up = _parsePriceInput();
    if (supplier.isEmpty || up <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tedarikçi adı ve geçerli birim fiyat zorunludur.'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }

    final actor = await _service.resolveCurrentActor(
      fallbackInstitutionId: widget.request.institutionId,
    );

    final q = SupplierQuoteModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      supplierName: supplier,
      unitPrice: up,
      quantity: widget.request.quantity,
      vatRate: _vatRate,
      vatIncluded: _vatIncluded,
      totalPrice: _computeCalculatedTotal(),
      deliveryInfo: _deliveryCtrl.text.trim(),
      productLink: _linkCtrl.text.trim(),
      attachmentUrl: _attachmentUrl,
      note: _noteCtrl.text.trim(),
      isRecommended: _isRecommended,
      addedByUid: actor.uid,
      addedByName: actor.name,
      createdAt: DateTime.now(),
    );

    setState(() {
      if (_isRecommended) {
        _quotes = _quotes
            .map(
              (old) => SupplierQuoteModel(
                id: old.id,
                supplierName: old.supplierName,
                unitPrice: old.unitPrice,
                quantity: old.quantity,
                vatRate: old.vatRate,
                vatIncluded: old.vatIncluded,
                totalPrice: old.totalPrice,
                deliveryInfo: old.deliveryInfo,
                productLink: old.productLink,
                attachmentUrl: old.attachmentUrl,
                note: old.note,
                isRecommended: false,
                addedByUid: old.addedByUid,
                addedByName: old.addedByName,
                createdAt: old.createdAt,
              ),
            )
            .toList();
      }
      _quotes.add(q);
      _supplierCtrl.clear();
      _unitPriceCtrl.clear();
      _linkCtrl.clear();
      _noteCtrl.clear();
      _attachmentUrl = '';
      _isRecommended = false;
      _addingNewQuote = false;
    });

    await _persistQuotes(submitForApproval: false);
  }

  Future<void> _persistQuotes({required bool submitForApproval}) async {
    if (_quotes.isEmpty && submitForApproval) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Üst onaya göndermek için en az 1 teklif ekleyiniz.'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final actor = await _service.resolveCurrentActor(
        fallbackInstitutionId: widget.request.institutionId,
      );
      await _service.saveQuotes(
        request: widget.request,
        quotes: _quotes,
        submitForApproval: submitForApproval,
        actorUid: actor.uid,
        actorName: actor.name,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (submitForApproval) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Teklifler üst yetkili onayına sunuldu.'),
            backgroundColor: Color(0xFF059669),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _approveQuote(SupplierQuoteModel q) async {
    setState(() => _saving = true);
    try {
      final actor = await _service.resolveCurrentActor(
        fallbackInstitutionId: widget.request.institutionId,
      );
      await _service.approveSupplierQuote(
        request: widget.request,
        selectedQuote: q,
        actorUid: actor.uid,
        actorName: actor.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${q.supplierName}" teklifi onaylandı.'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _placeOrderAndNotifyWarehouse() async {
    final wh = widget.allWarehouses
        .where((w) => w.id == _selectedWarehouseId)
        .firstOrNull;
    if (wh == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen ürünün gireceği depoyu seçiniz.'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final actor = await _service.resolveCurrentActor(
        fallbackInstitutionId: widget.request.institutionId,
      );
      final selectedKasa = _cashes
          .where((c) => c['id'].toString() == _selectedKasaId)
          .firstOrNull;

      await _service.markPurchaseOrdered(
        request: widget.request,
        targetWarehouse: wh,
        selectedKasaId: _selectedKasaId,
        selectedKasaName: (selectedKasa?['name'] ?? '').toString(),
        autoRecordExpense: _autoRecordExpense,
        actorUid: actor.uid,
        actorName: actor.name,
        orderNote: _orderNoteCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sipariş kaydedildi. Ürün "${wh.name}" deposuna ulaştığında depocu mal kabul onayı verecek.',
          ),
          backgroundColor: const Color(0xFF0284C7),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  Future<void> _openUrl(String rawUrl) async {
    final clean = rawUrl.trim();
    if (clean.isEmpty) return;
    final uri = Uri.tryParse(
      clean.startsWith('http') ? clean : 'https://$clean',
    );
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final canEditQuotes = widget.canManageProcurement &&
        (req.status == 'in_procurement' || req.status == 'quotes_submitted');

    double? minTotal;
    for (final q in _quotes) {
      if (minTotal == null || q.totalPrice < minTotal) {
        minTotal = q.totalPrice;
      }
    }

    final showSubmitFooter = canEditQuotes &&
        _quotes.isNotEmpty &&
        req.status == 'in_procurement' &&
        !_addingNewQuote;

    return InventoryBottomSheetFrame(
      title: req.itemName,
      subtitle:
          'İstenen: ${req.formattedQty} ${req.unit} • ${req.requesterName}${req.schoolTypeName.isNotEmpty ? ' (${req.schoolTypeName})' : ''}',
      icon: Icons.request_quote_rounded,
      accentColor: const Color(0xFFD97706),
      iconBgColor: const Color(0xFFFEF3C7),
      footer: showSubmitFooter
          ? SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed:
                    _saving ? null : () => _persistQuotes(submitForApproval: true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.fact_check_rounded, size: 19),
                label: Text(
                  _saving
                      ? 'Gönderiliyor...'
                      : 'Teklifleri Üst Yetkili Onayına Sun',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (req.productLink.isNotEmpty || req.description.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (req.description.isNotEmpty)
                    Text(
                      'Talep Açıklaması: ${req.description}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF334155),
                        height: 1.35,
                      ),
                    ),
                  if (req.productLink.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                        top: req.description.isNotEmpty ? 8 : 0,
                      ),
                      child: InkWell(
                        onTap: () => _openUrl(req.productLink),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 16,
                              color: Color(0xFF4F46E5),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Talep Edilen Örnek Ürün Linkini Görüntüle',
                              style: TextStyle(
                                fontSize: 12.8,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4F46E5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // SİPARİŞ GEÇME PANELİ (Üst amir teklifi onayladıysa)
          if (req.status == 'purchase_approved' &&
              widget.canManageProcurement) ...[
            _buildOrderPlacementSection(),
            const SizedBox(height: 18),
          ],

          // TEKLİFLER BAŞLIĞI
          Row(
            children: [
              Text(
                'Tedarikçi Teklifleri (${_quotes.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              if (canEditQuotes && !_addingNewQuote)
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _addingNewQuote = true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEEF2FF),
                    foregroundColor: const Color(0xFF4F46E5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text(
                    'Yeni Teklif Gir',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (_quotes.isEmpty && !_addingNewQuote)
            const InventoryEmptyState(
              icon: Icons.request_quote_outlined,
              title: 'Henüz Tedarikçi Teklifi Girilmemiş',
              subtitle:
                  'Satın alma birimi fiyat araştırmasını tamamlayıp teklifleri buraya eklediğinde karşılaştırmalı olarak listelenir.',
              accentColor: Color(0xFFD97706),
            ),

          // GİRİLEN TEKLİF KARTLARI
          ..._quotes.map((q) {
            final isCheapest = _quotes.length > 1 &&
                minTotal != null &&
                (q.totalPrice - minTotal).abs() < 0.01;
            final isApproved = req.approvedQuoteId == q.id;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isApproved ? const Color(0xFFECFDF5) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isApproved
                      ? const Color(0xFF10B981)
                      : (q.isRecommended
                          ? const Color(0xFF6366F1)
                          : const Color(0xFFE2E8F0)),
                  width: isApproved || q.isRecommended ? 1.8 : 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.025),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Icon(
                        Icons.storefront_rounded,
                        size: 18,
                        color: Color(0xFF334155),
                      ),
                      Text(
                        q.supplierName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (isApproved)
                        _buildBadge(
                          'ONAYLANAN TEKLİF',
                          const Color(0xFF059669),
                          const Color(0xFFD1FAE5),
                        ),
                      if (isCheapest)
                        _buildBadge(
                          'En Uygun Fiyat',
                          const Color(0xFF047857),
                          const Color(0xFFECFDF5),
                        ),
                      if (q.isRecommended)
                        _buildBadge(
                          'Satın Alma Önerisi',
                          const Color(0xFF4338CA),
                          const Color(0xFFEEF2FF),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Birim Fiyat: ${_currencyFmt.format(q.unitPrice)} (${q.vatIncluded ? 'KDV Dahil' : '+%${q.vatRate} KDV'})',
                              style: const TextStyle(
                                fontSize: 12.8,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                            if (q.deliveryInfo.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Teslim Süresi: ${q.deliveryInfo}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Toplam Tutar',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            Text(
                              _currencyFmt.format(q.totalPrice),
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (q.note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      q.note,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (q.productLink.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _openUrl(q.productLink),
                          icon: const Icon(Icons.link_rounded, size: 16),
                          label: const Text(
                            'Satış Linki',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      if (q.attachmentUrl.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _openUrl(q.attachmentUrl),
                          icon: const Icon(
                            Icons.receipt_long_rounded,
                            size: 16,
                          ),
                          label: const Text(
                            'Proforma / Belge',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      if (canEditQuotes && req.approvedQuoteId.isEmpty)
                        IconButton(
                          tooltip: 'Teklifi Sil',
                          onPressed: () async {
                            setState(() {
                              _quotes.removeWhere((item) => item.id == q.id);
                            });
                            await _persistQuotes(submitForApproval: false);
                          },
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFDC2626),
                            size: 20,
                          ),
                        ),
                      if (widget.canApproveUpper &&
                          (req.status == 'quotes_submitted' ||
                              req.status == 'in_procurement') &&
                          !isApproved)
                        FilledButton.icon(
                          onPressed: _saving ? null : () => _approveQuote(q),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 17,
                          ),
                          label: const Text(
                            'Bu Teklifi Onayla',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),

          // YENİ TEKLİF EKLEME FORMU
          if (_addingNewQuote && canEditQuotes) _buildAddQuoteCard(),
        ],
      ),
    );
  }

  Widget _buildAddQuoteCard() {
    final calcTotal = _computeCalculatedTotal();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC7D2FE), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.add_business_rounded,
                  size: 17,
                  color: Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Yeni Tedarikçi Teklifi Ekle',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              if (_quotes.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _addingNewQuote = false),
                  child: const Text('Kapat'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          InventoryTextField(
            controller: _supplierCtrl,
            label: 'Tedarikçi / Firma / Mağaza Adı',
            isRequired: true,
            hint: 'Örn: OfisMarket A.Ş., Hepsiburada Kurumsal...',
            icon: Icons.storefront_rounded,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: InventoryTextField(
                  controller: _unitPriceCtrl,
                  label: 'Birim Fiyat (₺)',
                  isRequired: true,
                  hint: '0.00',
                  icon: Icons.currency_lira_rounded,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: InventoryDropdownField<int>(
                  label: 'KDV Oranı',
                  icon: Icons.percent_rounded,
                  value: _vatRate,
                  items: const [0, 1, 10, 20]
                      .map((v) => DropdownMenuItem(value: v, child: Text('%$v')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _vatRate = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InventoryToggleCard(
            icon: Icons.calculate_outlined,
            accentColor: const Color(0xFF059669),
            title: 'Girilen birim fiyata KDV dahil',
            subtitle:
                'Hesaplanan Toplam (${widget.request.formattedQty} ${widget.request.unit}): ${_currencyFmt.format(calcTotal)}',
            value: _vatIncluded,
            onChanged: (v) => setState(() => _vatIncluded = v),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InventoryTextField(
                  controller: _deliveryCtrl,
                  label: 'Teslim Süresi',
                  hint: 'Örn: 2 İş Günü',
                  icon: Icons.local_shipping_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InventoryTextField(
                  controller: _linkCtrl,
                  label: 'Satış Linki',
                  trailingText: 'Opsiyonel',
                  hint: 'https://...',
                  icon: Icons.link_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          InventoryTextField(
            controller: _noteCtrl,
            label: 'Teklif Notu / Marka & Garanti Bilgisi',
            trailingText: 'Opsiyonel',
            hint: 'Örn: Orijinal kutulu, kargo ücretsiz...',
            icon: Icons.notes_rounded,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _uploadingDoc ? null : _pickQuoteAttachment,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFFD5DFEC)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _uploadingDoc
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _attachmentUrl.isNotEmpty
                              ? Icons.check_circle_rounded
                              : Icons.attach_file_rounded,
                          size: 18,
                          color: _attachmentUrl.isNotEmpty
                              ? const Color(0xFF059669)
                              : const Color(0xFF4F46E5),
                        ),
                  label: Text(
                    _attachmentUrl.isNotEmpty
                        ? 'Proforma Eklendi'
                        : 'Proforma / PDF Ekle',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _isRecommended = !_isRecommended),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 11,
                      horizontal: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _isRecommended
                          ? const Color(0xFFEEF2FF)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isRecommended
                            ? const Color(0xFF4F46E5)
                            : const Color(0xFFD5DFEC),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isRecommended
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 18,
                          color: _isRecommended
                              ? const Color(0xFF4F46E5)
                              : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Önerilen Teklif',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _isRecommended
                                ? const Color(0xFF312E81)
                                : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: _saving ? null : _addQuoteToList,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: const Icon(Icons.playlist_add_check_rounded, size: 19),
              label: const Text(
                'Teklifi Listeye Ekle',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderPlacementSection() {
    final approved = widget.request.approvedQuote;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF7DD3FC), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: Color(0xFF0284C7),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Siparişi Geç & Depocu Mal Kabulüne Bildir'
                  '${approved != null ? ' (${_currencyFmt.format(approved.totalPrice)})' : ''}',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0C4A6E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          InventoryDropdownField<String>(
            label: 'Ürünün Teslim Alınacağı Hedef Depo',
            isRequired: true,
            icon: Icons.warehouse_outlined,
            accentColor: const Color(0xFF0284C7),
            value: widget.allWarehouses.any((w) => w.id == _selectedWarehouseId)
                ? _selectedWarehouseId
                : null,
            items: widget.allWarehouses
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
              if (v != null) setState(() => _selectedWarehouseId = v);
            },
          ),
          const SizedBox(height: 12),
          InventoryToggleCard(
            icon: Icons.account_balance_wallet_outlined,
            accentColor: const Color(0xFF0284C7),
            title:
                'Depocu mal kabul onayı verdiğinde Mali İşlere otomatik gider işle',
            value: _autoRecordExpense,
            onChanged: (v) => setState(() => _autoRecordExpense = v),
          ),
          if (_autoRecordExpense && _cashes.isNotEmpty) ...[
            const SizedBox(height: 12),
            InventoryDropdownField<String>(
              label: 'Ödemenin Çıkacağı Kasa / Banka Hesabı',
              icon: Icons.account_balance_rounded,
              accentColor: const Color(0xFF0284C7),
              value: _cashes.any((c) => c['id'].toString() == _selectedKasaId)
                  ? _selectedKasaId
                  : null,
              items: _cashes
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: c['id'].toString(),
                      child: Text((c['name'] ?? 'Kasa').toString()),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedKasaId = v);
              },
            ),
          ],
          const SizedBox(height: 12),
          InventoryTextField(
            controller: _orderNoteCtrl,
            label: 'Sipariş / Kargo Notu',
            trailingText: 'Opsiyonel',
            hint: 'Örn: Fatura kesildi, Çarşamba günü teslim edilecek...',
            icon: Icons.receipt_long_outlined,
            accentColor: const Color(0xFF0284C7),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _saving ? null : _placeOrderAndNotifyWarehouse,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: const Icon(Icons.send_and_archive_rounded, size: 19),
              label: const Text(
                'Sipariş Verildi İşaretle • Depoya Bildir',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.8,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}
