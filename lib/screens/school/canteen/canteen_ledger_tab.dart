import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/canteen/canteen_models.dart';
import '../../../services/canteen_service.dart';
import 'canteen_common.dart';

/// Muhasebe (Gelir - Gider Defteri) sekmesi — KantiN Studio.
class CanteenLedgerTab extends StatefulWidget {
  final String institutionId;
  const CanteenLedgerTab({super.key, required this.institutionId});

  @override
  State<CanteenLedgerTab> createState() => _CanteenLedgerTabState();
}

class _CanteenLedgerTabState extends State<CanteenLedgerTab>
    with AutomaticKeepAliveClientMixin {
  final CanteenService _svc = CanteenService.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  StreamSubscription<List<CanteenLedgerEntry>>? _sub;
  List<CanteenLedgerEntry> _entries = const [];
  bool _loading = true;
  String? _error;

  String _period = 'month'; // today | week | month | custom
  String _typeFilter = 'all'; // all | income | expense
  late DateTimeRange _range;

  String get _inst => widget.institutionId.trim();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _applyPreset('month', subscribe: false);
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant CanteenLedgerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId) _subscribe();
  }

  void _applyPreset(String preset, {bool subscribe = true}) {
    final today = cnStartOfDay(DateTime.now());
    switch (preset) {
      case 'today':
        _range = DateTimeRange(start: today, end: today);
        break;
      case 'week':
        final weekday = today.weekday; // 1 = Pazartesi
        _range = DateTimeRange(
          start: today.subtract(Duration(days: weekday - 1)),
          end: today,
        );
        break;
      case 'month':
      default:
        _range = DateTimeRange(
          start: DateTime(today.year, today.month, 1),
          end: today,
        );
        break;
    }
    _period = preset;
    if (subscribe) {
      setState(() {});
      _subscribe();
    }
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = null;
    if (_inst.isEmpty) {
      _loading = false;
      _error = 'Kurum bilgisi bulunamadı.';
      return;
    }
    _loading = true;
    _error = null;
    _sub = _svc
        .watchLedger(
          _inst,
          from: cnStartOfDay(_range.start),
          to: cnEndOfDay(_range.end),
        )
        .listen(
          (l) {
            if (!mounted) return;
            setState(() {
              _entries = l;
              _loading = false;
              _error = null;
            });
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _error = cnErr(e);
            });
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final r = await cnPickRange(context, _range);
    if (r == null || !mounted) return;
    setState(() {
      _range = r;
      _period = 'custom';
    });
    _subscribe();
  }

  Future<void> _add() async {
    if (_inst.isEmpty) return;
    final res = await showDialog<CanteenLedgerEntry>(
      context: context,
      builder: (_) => const _LedgerDialog(),
    );
    if (res == null || !mounted) return;
    try {
      await _svc.addLedgerEntry(_inst, res);
      if (mounted) {
        cnSnack(
          context,
          res.isIncome ? 'Gelir kaydı eklendi.' : 'Gider kaydı eklendi.',
        );
      }
    } catch (e) {
      if (mounted) cnSnack(context, cnErr(e), error: true);
    }
  }

  List<CanteenLedgerEntry> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _entries.where((e) {
      if (_typeFilter == 'income' && !e.isIncome) return false;
      if (_typeFilter == 'expense' && e.isIncome) return false;
      if (q.isEmpty) return true;
      return e.category.toLowerCase().contains(q) ||
          e.note.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    double income = 0, expense = 0;
    int incCount = 0, expCount = 0;
    for (final e in _entries) {
      if (e.isIncome) {
        income += e.amount;
        incCount++;
      } else {
        expense += e.amount;
        expCount++;
      }
    }
    final list = _filtered;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Üst Dönem Hapları + Ekle Butonu
          CnPanel(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _periodPill('today', 'Bugün'),
                    _periodPill('week', 'Bu Hafta'),
                    _periodPill('month', 'Bu Ay'),
                    OutlinedButton.icon(
                      style: cnOutlineBtn(
                        color: _period == 'custom'
                            ? CnColors.brand
                            : CnColors.slate,
                      ),
                      onPressed: _pickRange,
                      icon: const Icon(Icons.date_range_rounded, size: 17),
                      label: Text(
                        _period == 'custom'
                            ? '${cnDate(_range.start)} - ${cnDate(_range.end)}'
                            : 'Tarih Seç (${cnDate(_range.start)} - ${cnDate(_range.end)})',
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: cnPrimaryBtn(),
                  onPressed: _inst.isEmpty ? null : _add,
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('Gelir / Gider Ekle'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3 KPI Kartı: Toplam Gelir (Yeşil), Toplam Gider (Kırmızı), Net Kasa (İndigo)
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 760 ? 3 : 1;
              final w = (c.maxWidth - (cols - 1) * 10) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: w,
                    child: CnKpi(
                      label: 'Toplam Gelir',
                      value: cnMoney(income),
                      subtitle: '$incCount kayıt',
                      icon: Icons.trending_up_rounded,
                      color: CnColors.ok,
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: CnKpi(
                      label: 'Toplam Gider',
                      value: cnMoney(expense),
                      subtitle: '$expCount kayıt',
                      icon: Icons.trending_down_rounded,
                      color: CnColors.brand,
                    ),
                  ),
                  SizedBox(
                    width: w,
                    child: CnKpi(
                      label: 'Net Kasa',
                      value: cnMoney(income - expense),
                      subtitle: income - expense >= 0
                          ? 'Pozitif bakiye'
                          : 'Gider fazlası',
                      icon: Icons.account_balance_wallet_rounded,
                      color: CnColors.indigo,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),

          // Tür Filtresi Hapları + Arama
          CnPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: LayoutBuilder(
              builder: (context, c) {
                final filterRow = Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _typePill(
                      'all',
                      'Tümü (${_entries.length})',
                      CnColors.slate,
                    ),
                    _typePill(
                      'income',
                      'Gelirler ($incCount)',
                      CnColors.okDark,
                    ),
                    _typePill(
                      'expense',
                      'Giderler ($expCount)',
                      CnColors.brand,
                    ),
                  ],
                );
                final searchBox = TextField(
                  controller: _searchCtrl,
                  decoration: cnInput(
                    'Kategori veya açıklama ara...',
                    prefix: const Icon(Icons.search_rounded, size: 19),
                    suffix: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                );

                if (c.maxWidth < 680) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [filterRow, const SizedBox(height: 8), searchBox],
                  );
                }
                return Row(
                  children: [
                    filterRow,
                    const SizedBox(width: 12),
                    Expanded(child: searchBox),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Defter Kayıtları Listesi
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: CnColors.brand),
                  )
                : _error != null
                ? CnError(_error!, onRetry: _subscribe)
                : list.isEmpty
                ? const CnEmpty(
                    'Seçili dönemde muhasebe kaydı bulunamadı.',
                    subtitle:
                        'Satışlar, bakiye yüklemeleri ve manuel gelir/gider kayıtları bu defterde otomatik toplanır.',
                    icon: Icons.receipt_long_outlined,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _ledgerRow(list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _periodPill(String key, String label) {
    final sel = _period == key;
    return Material(
      color: sel ? CnColors.brand : CnColors.surfaceAlt,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _applyPreset(key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: sel ? CnColors.brand : CnColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: sel ? Colors.white : CnColors.slate,
            ),
          ),
        ),
      ),
    );
  }

  Widget _typePill(String key, String label, Color activeColor) {
    final sel = _typeFilter == key;
    return Material(
      color: sel ? activeColor : CnColors.surfaceAlt,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _typeFilter = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: sel ? activeColor : CnColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: sel ? Colors.white : CnColors.slate,
            ),
          ),
        ),
      ),
    );
  }

  Widget _ledgerRow(CanteenLedgerEntry e) {
    final inc = e.isIncome;
    final col = inc ? CnColors.okDark : CnColors.brand;
    final bg = inc ? CnColors.okSoft : CnColors.pinkBg;
    final cat = e.category.trim().isEmpty
        ? (inc ? 'Genel Gelir' : 'Genel Gider')
        : e.category.trim();

    return CnPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              inc ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: col,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CnBadge(inc ? 'Gelir' : 'Gider', color: col),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        cat,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: CnColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    cnDateTime(e.date ?? e.createdAt),
                    if (e.note.trim().isNotEmpty) e.note.trim(),
                  ].join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: CnColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${inc ? '+' : '-'}${cnMoney(e.amount)}',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15.5,
              color: col,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MANUEL GELİR / GİDER MODALI (CnDialogShell)
// ═════════════════════════════════════════════════════════════════════════════

class _LedgerDialog extends StatefulWidget {
  const _LedgerDialog();

  @override
  State<_LedgerDialog> createState() => _LedgerDialogState();
}

class _LedgerDialogState extends State<_LedgerDialog> {
  static const List<String> _expenseCats = [
    'Tedarik Ödemesi',
    'Personel & Maaş',
    'Fatura & Kira',
    'Ekipman & Bakım',
    'Fire & İmha',
    'Diğer Gider',
  ];
  static const List<String> _incomeCats = [
    'Nakit Satış',
    'Toplu Etkinlik / İkram',
    'Tedarikçi İadesi',
    'Diğer Gelir',
  ];

  final TextEditingController _category = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();

  String _type = 'expense';
  DateTime _date = DateTime.now();
  String? _err;

  @override
  void dispose() {
    _category.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: CnColors.brand,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: CnColors.text,
            ),
          ),
          child: child!,
        );
      },
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  void _save() {
    final a = cnParseMoney(_amount.text);
    if (a <= 0) {
      setState(() => _err = 'Lütfen sıfırdan büyük bir tutar girin.');
      return;
    }
    final now = DateTime.now();
    Navigator.pop(
      context,
      CanteenLedgerEntry(
        type: _type,
        category: _category.text.trim(),
        amount: a,
        note: _note.text.trim(),
        date: DateTime(
          _date.year,
          _date.month,
          _date.day,
          now.hour,
          now.minute,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isInc = _type == 'income';
    final presets = isInc ? _incomeCats : _expenseCats;

    return CnDialogShell(
      title: 'Manuel Gelir / Gider Kaydı',
      subtitle: 'Kantin kasa defterine yeni muhasebe hareketi ekleyin',
      icon: isInc ? Icons.trending_up_rounded : Icons.trending_down_rounded,
      iconColor: isInc ? CnColors.okDark : CnColors.brand,
      maxWidth: 520,
      errorText: _err,
      primaryLabel: isInc ? 'Geliri Kaydet' : 'Gideri Kaydet',
      primaryColor: isInc ? CnColors.okDark : CnColors.brand,
      onPrimary: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _typeCard(
                  key: 'expense',
                  label: 'Gider Kaydı',
                  icon: Icons.north_east_rounded,
                  color: CnColors.brand,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _typeCard(
                  key: 'income',
                  label: 'Gelir Kaydı',
                  icon: Icons.south_west_rounded,
                  color: CnColors.okDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const CnSectionLabel('KATEGORİ', icon: Icons.category_outlined),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in presets)
                ChoiceChip(
                  label: Text(c),
                  selected: _category.text.trim() == c,
                  showCheckmark: false,
                  selectedColor: isInc ? CnColors.okDark : CnColors.brand,
                  backgroundColor: CnColors.surfaceAlt,
                  side: BorderSide(
                    color: _category.text.trim() == c
                        ? (isInc ? CnColors.okDark : CnColors.brand)
                        : CnColors.border,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _category.text.trim() == c
                        ? Colors.white
                        : CnColors.slate,
                  ),
                  onSelected: (_) => setState(() => _category.text = c),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _category,
            onChanged: (_) => setState(() {}),
            decoration: cnInput(
              'Kategori Başlığı',
              hint: 'Örn. Tedarik Ödemesi, Maaş, Fatura',
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final amountBox = TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: cnInput(
                  'Tutar (₺) *',
                  prefix: const Icon(Icons.currency_lira_rounded, size: 19),
                ),
              );
              final dateBtn = OutlinedButton.icon(
                style: cnOutlineBtn(
                  color: CnColors.slate,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                ),
                onPressed: _pickDate,
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('Tarih: ${cnDate(_date)}'),
              );
              if (c.maxWidth < 400) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [amountBox, const SizedBox(height: 10), dateBtn],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 3, child: amountBox),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: dateBtn),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: cnInput(
              'Açıklama / Fatura Notu',
              hint: 'İsteğe bağlı açıklama ekleyin...',
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeCard({
    required String key,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final sel = _type == key;
    return Material(
      color: sel ? color.withValues(alpha: 0.10) : CnColors.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _type = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: sel ? color : CnColors.border,
              width: sel ? 1.6 : 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: sel ? color : CnColors.slate),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: sel ? color : CnColors.slate,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
