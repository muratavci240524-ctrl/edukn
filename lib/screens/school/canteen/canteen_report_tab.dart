import 'package:flutter/material.dart';

import '../../../services/canteen_service.dart';
import 'canteen_common.dart';

/// Rapor & Analitik sekmesi — KantiN Studio.
class CanteenReportTab extends StatefulWidget {
  final String institutionId;
  const CanteenReportTab({super.key, required this.institutionId});

  @override
  State<CanteenReportTab> createState() => _CanteenReportTabState();
}

class _CanteenReportTabState extends State<CanteenReportTab>
    with AutomaticKeepAliveClientMixin {
  final CanteenService _svc = CanteenService.instance;

  String _period = '7d'; // 7d | month | 30d | custom
  late DateTimeRange _range;
  Future<CanteenReport>? _future;

  String get _inst => widget.institutionId.trim();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _applyPreset('7d', reload: false);
    _load();
  }

  @override
  void didUpdateWidget(covariant CanteenReportTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId) _load();
  }

  void _applyPreset(String preset, {bool reload = true}) {
    final today = cnStartOfDay(DateTime.now());
    switch (preset) {
      case 'month':
        _range = DateTimeRange(
          start: DateTime(today.year, today.month, 1),
          end: today,
        );
        break;
      case '30d':
        _range = DateTimeRange(
          start: today.subtract(const Duration(days: 29)),
          end: today,
        );
        break;
      case '7d':
      default:
        _range = DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        );
        break;
    }
    _period = preset;
    if (reload) {
      setState(_load);
    }
  }

  void _load() {
    if (_inst.isEmpty) {
      _future = null;
      return;
    }
    _future = _svc.buildReport(
      _inst,
      cnStartOfDay(_range.start),
      cnEndOfDay(_range.end),
    );
  }

  Future<void> _pick() async {
    final r = await cnPickRange(context, _range);
    if (r == null || !mounted) return;
    setState(() {
      _range = r;
      _period = 'custom';
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hızlı Dönem Hapları + Yenile
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
                    _periodPill('7d', 'Son 7 Gün'),
                    _periodPill('month', 'Bu Ay'),
                    _periodPill('30d', 'Son 30 Gün'),
                    OutlinedButton.icon(
                      style: cnOutlineBtn(
                        color: _period == 'custom'
                            ? CnColors.brand
                            : CnColors.slate,
                      ),
                      onPressed: _pick,
                      icon: const Icon(Icons.date_range_rounded, size: 17),
                      label: Text(
                        'Tarih Seç (${cnDate(_range.start)} - ${cnDate(_range.end)})',
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: cnPrimaryBtn(),
                  onPressed: _inst.isEmpty ? null : () => setState(_load),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Raporu Yenile'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Rapor İçeriği
          Expanded(
            child: _future == null
                ? const CnError('Kurum bilgisi bulunamadı.')
                : FutureBuilder<CanteenReport>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: CnColors.brand,
                          ),
                        );
                      }
                      if (snap.hasError) {
                        return CnError(
                          cnErr(snap.error!),
                          onRetry: () => setState(_load),
                        );
                      }
                      final r = snap.data;
                      if (r == null) return const CnEmpty('Rapor verisi yok.');
                      return _reportBody(r);
                    },
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

  Widget _reportBody(CanteenReport r) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 960 ? 4 : (c.maxWidth >= 540 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        final twoCol = c.maxWidth >= 900;

        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            // 4 Ana KPI Kartı
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: w,
                  child: CnKpi(
                    label: 'Net Satış Cirosu',
                    value: cnMoney(r.netSales),
                    subtitle: r.totalRefunds > 0
                        ? 'Brüt: ${cnMoney(r.totalSales)} • İade: ${cnMoney(r.totalRefunds)}'
                        : 'Toplam kasa satışı',
                    icon: Icons.point_of_sale_rounded,
                    color: CnColors.brand,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: CnKpi(
                    label: 'Satış Adedi',
                    value: '${r.saleCount} İşlem',
                    subtitle: 'Ort. Sepet: ${cnMoney(r.averageSale)}',
                    icon: Icons.shopping_basket_outlined,
                    color: CnColors.warn,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: CnKpi(
                    label: 'Kart Bakiye Yükleme',
                    value: cnMoney(r.totalTopUps),
                    subtitle: 'Cüzdanlara yüklenen',
                    icon: Icons.add_card_rounded,
                    color: CnColors.ok,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: CnKpi(
                    label: 'Defter Net Kasa',
                    value: cnMoney(r.ledgerNet),
                    subtitle:
                        'Gelir: ${cnMoney(r.ledgerIncome)} • Gider: ${cnMoney(r.ledgerExpense)}',
                    icon: Icons.account_balance_wallet_rounded,
                    color: CnColors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Günlük Ciro Sütun Grafiği + Ödeme Yöntemi Dağılımı
            if (twoCol)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: _sectionCard(
                      title: 'Günlük Ciro Grafiği',
                      subtitle: '${r.dailyRevenue.length} günlük satış trendi',
                      icon: Icons.bar_chart_rounded,
                      child: _dailyChart(r),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 4,
                    child: _sectionCard(
                      title: 'Ödeme Yöntemi Dağılımı',
                      subtitle: 'Tahsilat kanallarına göre oranlar',
                      icon: Icons.pie_chart_outline_rounded,
                      child: _paymentBreakdown(r),
                    ),
                  ),
                ],
              )
            else ...[
              _sectionCard(
                title: 'Günlük Ciro Grafiği',
                subtitle: '${r.dailyRevenue.length} günlük satış trendi',
                icon: Icons.bar_chart_rounded,
                child: _dailyChart(r),
              ),
              const SizedBox(height: 14),
              _sectionCard(
                title: 'Ödeme Yöntemi Dağılımı',
                subtitle: 'Tahsilat kanallarına göre oranlar',
                icon: Icons.pie_chart_outline_rounded,
                child: _paymentBreakdown(r),
              ),
            ],
            const SizedBox(height: 14),

            // En Çok Satan Ürünler + Kritik Stok Listesi
            if (twoCol)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: _sectionCard(
                      title: 'En Çok Satan Ürünler',
                      subtitle: 'Adet ve ciro bazında ilk 10 ürün',
                      icon: Icons.emoji_events_outlined,
                      child: _topProductsList(r),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 4,
                    child: _sectionCard(
                      title: 'Kritik Stok Uyarıları (${r.lowStock.length})',
                      subtitle: 'Minimum stok eşiğine ulaşan aktif ürünler',
                      icon: Icons.warning_amber_rounded,
                      child: _criticalStockList(r),
                    ),
                  ),
                ],
              )
            else ...[
              _sectionCard(
                title: 'En Çok Satan Ürünler',
                subtitle: 'Adet ve ciro bazında ilk 10 ürün',
                icon: Icons.emoji_events_outlined,
                child: _topProductsList(r),
              ),
              const SizedBox(height: 14),
              _sectionCard(
                title: 'Kritik Stok Uyarıları (${r.lowStock.length})',
                subtitle: 'Minimum stok eşiğine ulaşan aktif ürünler',
                icon: Icons.warning_amber_rounded,
                child: _criticalStockList(r),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return CnPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CnColors.pinkBg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: CnColors.brand, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: CnColors.text,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: CnColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _paymentBreakdown(CanteenReport r) {
    if (r.salesByMethod.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'Seçili dönemde satış kaydı bulunmuyor.',
          style: TextStyle(color: CnColors.muted, fontSize: 13),
        ),
      );
    }

    final entries = r.salesByMethod.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sum = entries.fold<double>(0, (s, e) => s + e.value);

    Color methodCol(String m) {
      switch (m) {
        case 'card':
          return CnColors.brand;
        case 'qr':
        case 'mobile':
          return CnColors.indigo;
        case 'pos':
          return const Color(0xFF0284C7);
        case 'cash':
          return CnColors.okDark;
        default:
          return CnColors.warnDark;
      }
    }

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final e = entries[i];
              final ratio = sum > 0 ? (e.value / sum).clamp(0.0, 1.0) : 0.0;
              final pct = (ratio * 100).toStringAsFixed(1);
              final col = methodCol(e.key);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(cnMethodIcon(e.key), size: 17, color: col),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          cnMethodLabel(e.key),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: CnColors.text,
                          ),
                        ),
                      ),
                      Text(
                        '%$pct',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: CnColors.muted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        cnMoney(e.value),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: col,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 8,
                      backgroundColor: CnColors.surfaceAlt,
                      color: col,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _dailyChart(CanteenReport r) {
    if (r.dailyRevenue.isEmpty) {
      return const Text(
        'Günlük ciro verisi yok.',
        style: TextStyle(color: CnColors.muted),
      );
    }

    double maxV = 0;
    for (final d in r.dailyRevenue) {
      if (d.revenue > maxV) maxV = d.revenue;
    }
    if (maxV <= 0) maxV = 1;

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: CnColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CnColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, chartBox) {
          final barMaxH = (chartBox.maxHeight - 46).clamp(24.0, 160.0);
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: r.dailyRevenue.length,
            itemBuilder: (context, i) {
              final d = r.dailyRevenue[i];
              final h = (d.revenue / maxV) * barMaxH;
              final isPeak = d.revenue > 0 && (d.revenue - maxV).abs() < 0.01;
              final dayLabel =
                  '${d.day.day.toString().padLeft(2, '0')}.${d.day.month.toString().padLeft(2, '0')}';
              final revLabel = d.revenue <= 0
                  ? ''
                  : (d.revenue - d.revenue.roundToDouble()).abs() < 0.01
                      ? d.revenue.toStringAsFixed(0)
                      : d.revenue.toStringAsFixed(1);

              return Tooltip(
                message: '$dayLabel: ${cnMoney(d.revenue)}',
                child: SizedBox(
                  width: 52,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 15,
                        child: Center(
                          child: Text(
                            revLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.1,
                              fontWeight:
                                  isPeak ? FontWeight.w800 : FontWeight.w600,
                              color: isPeak ? CnColors.brand : CnColors.muted,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 24,
                        height: d.revenue <= 0 ? 4 : h.clamp(6.0, barMaxH),
                        decoration: BoxDecoration(
                          gradient: d.revenue > 0 ? CnColors.gradient : null,
                          color: d.revenue > 0 ? null : CnColors.border,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8),
                            bottom: Radius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 15,
                        child: Center(
                          child: Text(
                            dayLabel,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 10.5,
                              height: 1.1,
                              fontWeight: FontWeight.w600,
                              color: CnColors.slate,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _topProductsList(CanteenReport r) {
    if (r.topProducts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Seçili dönemde ürün satışı yapılmadı.',
          style: TextStyle(color: CnColors.muted, fontSize: 13),
        ),
      );
    }

    final maxQ = r.topProducts.fold<int>(1, (m, e) => e.qty > m ? e.qty : m);

    Color rankColor(int idx) {
      if (idx == 0) return const Color(0xFFD97706); // Altın
      if (idx == 1) return const Color(0xFF475569); // Gümüş
      if (idx == 2) return const Color(0xFFB45309); // Bronz
      return CnColors.brand;
    }

    return Column(
      children: [
        for (var i = 0; i < r.topProducts.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Builder(
            builder: (context) {
              final p = r.topProducts[i];
              final col = rankColor(i);
              return Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: col.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '#${i + 1}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: col,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: CnColors.text,
                                ),
                              ),
                            ),
                            Text(
                              '${p.qty} adet • ${cnMoney(p.revenue)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: CnColors.slate,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: (p.qty / maxQ).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: CnColors.surfaceAlt,
                            color: CnColors.brand,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _criticalStockList(CanteenReport r) {
    if (r.lowStock.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CnColors.okSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CnColors.ok.withValues(alpha: 0.25)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: CnColors.okDark, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tüm aktif ürünlerin stok seviyesi yeterli.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: CnColors.okDark,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < r.lowStock.length; i++) ...[
          if (i > 0) const Divider(height: 12, color: Color(0xFFF1F5F9)),
          Row(
            children: [
              CnProductAvatar(
                imageUrl: r.lowStock[i].imageUrl,
                category: r.lowStock[i].category,
                width: 36,
                height: 36,
                radius: 9,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.lowStock[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: CnColors.text,
                      ),
                    ),
                    Text(
                      'Min. Eşik: ${r.lowStock[i].minStock} ${r.lowStock[i].unit}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: CnColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              CnBadge(
                '${r.lowStock[i].stock} ${r.lowStock[i].unit}',
                color: r.lowStock[i].stock <= 0
                    ? Colors.red.shade700
                    : CnColors.warnDark,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
