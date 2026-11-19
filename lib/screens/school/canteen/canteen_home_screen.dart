import 'package:flutter/material.dart';

import '../../../widgets/school_pos_settings_dialog.dart';
import 'canteen_balance_tab.dart';
import 'canteen_cards_tab.dart';
import 'canteen_common.dart';
import 'canteen_ledger_tab.dart';
import 'canteen_pos_tab.dart';
import 'canteen_report_tab.dart';
import 'canteen_stock_tab.dart';

/// Kantin (okul tarafı) ana ekranı — KantiN Studio tasarımı.
///
/// [allowedSubModules] verilirse yalnızca izin verilen alt modüllere ait
/// sekmeler gösterilir (örn. `kantin_satis`). `null` = hepsi.
class CanteenHomeScreen extends StatefulWidget {
  final String institutionId;
  final String schoolName;
  final Set<String>? allowedSubModules;

  /// Açılışta seçilecek alt modül anahtarı (örn. `kantin_stok`).
  final String? initialSubModule;

  const CanteenHomeScreen({
    super.key,
    required this.institutionId,
    this.schoolName = '',
    this.allowedSubModules,
    this.initialSubModule,
  });

  @override
  State<CanteenHomeScreen> createState() => _CanteenHomeScreenState();
}

class _Section {
  final String subKey;
  final String title;
  final IconData icon;
  final Widget Function(String inst) builder;
  const _Section(this.subKey, this.title, this.icon, this.builder);
}

class _CanteenHomeScreenState extends State<CanteenHomeScreen>
    with TickerProviderStateMixin {
  late List<_Section> _sections;
  TabController? _tabs;

  static final List<_Section> _all = [
    _Section(
      'kantin_satis',
      'Satış (POS)',
      Icons.point_of_sale_rounded,
      (i) => CanteenPosTab(institutionId: i),
    ),
    _Section(
      'kantin_kart',
      'Kart Tanımlama',
      Icons.credit_card_rounded,
      (i) => CanteenCardsTab(institutionId: i),
    ),
    _Section(
      'kantin_bakiye',
      'Bakiye',
      Icons.account_balance_wallet_rounded,
      (i) => CanteenBalanceTab(institutionId: i),
    ),
    _Section(
      'kantin_stok',
      'Stok',
      Icons.inventory_2_rounded,
      (i) => CanteenStockTab(institutionId: i),
    ),
    _Section(
      'kantin_muhasebe',
      'Muhasebe',
      Icons.receipt_long_rounded,
      (i) => CanteenLedgerTab(institutionId: i),
    ),
    _Section(
      'kantin_rapor',
      'Rapor',
      Icons.analytics_rounded,
      (i) => CanteenReportTab(institutionId: i),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void didUpdateWidget(covariant CanteenHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.allowedSubModules != widget.allowedSubModules) {
      _disposeTabs();
      _setup();
    }
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  void _disposeTabs() {
    _tabs?.removeListener(_onTabChanged);
    _tabs?.dispose();
    _tabs = null;
  }

  void _setup() {
    final allowed = widget.allowedSubModules;
    _sections = _all
        .where((s) => allowed == null || allowed.contains(s.subKey))
        .toList();
    var initial = 0;
    final want = widget.initialSubModule;
    if (want != null) {
      final idx = _sections.indexWhere((s) => s.subKey == want);
      if (idx >= 0) initial = idx;
    }
    if (_sections.isNotEmpty) {
      _tabs = TabController(
        length: _sections.length,
        vsync: this,
        initialIndex: initial,
      )..addListener(_onTabChanged);
    }
  }

  @override
  void dispose() {
    _disposeTabs();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inst = widget.institutionId.trim();
    return Scaffold(
      backgroundColor: CnColors.bg,
      body: Column(
        children: [
          _buildStudioTopBar(context, inst),
          Expanded(
            child: inst.isEmpty
                ? const CnError('Kurum bilgisi bulunamadı.')
                : _tabs == null
                ? const CnEmpty(
                    'Bu modül için yetkiniz bulunmuyor.',
                    icon: Icons.lock_outline_rounded,
                  )
                : TabBarView(
                    controller: _tabs,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [for (final s in _sections) s.builder(inst)],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudioTopBar(BuildContext context, String inst) {
    final canPop = Navigator.of(context).canPop();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: CnColors.border)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, c) {
            final desktop = c.maxWidth >= 1020;
            if (desktop) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    _brandHeader(context, canPop, inst),
                    const SizedBox(width: 20),
                    if (_tabs != null) Expanded(child: _pillNavBar()),
                    const SizedBox(width: 10),
                    _posSettingsButton(context, inst, compact: false),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Row(
                    children: [
                      Expanded(child: _brandHeader(context, canPop, inst)),
                      const SizedBox(width: 8),
                      _posSettingsButton(context, inst, compact: true),
                    ],
                  ),
                ),
                if (_tabs != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: _pillNavBar(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _posSettingsButton(
    BuildContext context,
    String inst, {
    required bool compact,
  }) {
    if (inst.isEmpty) return const SizedBox.shrink();
    return OutlinedButton.icon(
      onPressed: () => SchoolPosSettingsDialog.show(
        context,
        institutionId: inst,
        institutionTitle: widget.schoolName,
        initialTab: 2,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: CnColors.brand,
        side: const BorderSide(color: CnColors.borderStrong),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 13,
          vertical: compact ? 8 : 10,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.point_of_sale_rounded, size: 17),
      label: Text(
        compact ? 'POS Ayarları' : 'Kantin POS Ayarları',
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _brandHeader(BuildContext context, bool canPop, String inst) {
    final subtitle = widget.schoolName.trim().isNotEmpty
        ? widget.schoolName.trim()
        : (inst.isNotEmpty ? 'Kurum: ${inst.toUpperCase()}' : 'Okul Kantini');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canPop) ...[
          Material(
            color: CnColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CnColors.border),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 17,
                  color: CnColors.slate,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        // KantiN Gradyan Rozeti
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            gradient: CnColors.gradient,
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: CnColors.brand.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_rounded, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text(
                'KantiN',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Kantin Yönetimi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: CnColors.text,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: CnColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _pillNavBar() {
    final activeIdx = _tabs?.index ?? 0;
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: CnColors.surfaceAlt,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: CnColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _sections.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                _pillItem(_sections[i], i == activeIdx, () {
                  _tabs?.animateTo(i);
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pillItem(_Section s, bool active, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            gradient: active ? CnColors.gradient : null,
            color: active ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: CnColors.brand.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                s.icon,
                size: 17,
                color: active ? Colors.white : CnColors.slate,
              ),
              const SizedBox(width: 7),
              Text(
                s.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? Colors.white : CnColors.slate,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
