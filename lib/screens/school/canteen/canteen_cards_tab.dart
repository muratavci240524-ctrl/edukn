import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../models/canteen/canteen_models.dart';
import '../../../services/canteen_service.dart';
import 'canteen_common.dart';

class _StudentLite {
  final String id;
  final String name;
  final String number;
  final String className;
  final List<String> parentUids;
  final String parentEmail;

  const _StudentLite({
    required this.id,
    required this.name,
    required this.number,
    required this.className,
    required this.parentUids,
    required this.parentEmail,
  });
}

/// Kart Tanımlama sekmesi — KantiN Studio.
class CanteenCardsTab extends StatefulWidget {
  final String institutionId;
  const CanteenCardsTab({super.key, required this.institutionId});

  @override
  State<CanteenCardsTab> createState() => _CanteenCardsTabState();
}

class _CanteenCardsTabState extends State<CanteenCardsTab>
    with AutomaticKeepAliveClientMixin {
  final CanteenService _svc = CanteenService.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  StreamSubscription<List<CanteenCard>>? _sub;
  List<CanteenCard> _cards = const [];
  bool _loading = true;
  String? _error;

  String _statusFilter = 'all'; // all | active | passive
  Future<List<_StudentLite>>? _studentsFuture;

  String get _inst => widget.institutionId.trim();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant CanteenCardsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId) _init();
  }

  void _init() {
    _sub?.cancel();
    _sub = null;
    _studentsFuture = null;
    if (_inst.isEmpty) {
      _loading = false;
      _error = 'Kurum bilgisi bulunamadı.';
      return;
    }
    _loading = true;
    _error = null;
    _sub = _svc
        .watchCards(_inst)
        .listen(
          (l) {
            if (!mounted) return;
            setState(() {
              _cards = l;
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

  Future<List<_StudentLite>> _loadStudents() {
    return _studentsFuture ??= _fetchStudents();
  }

  Future<List<_StudentLite>> _fetchStudents() async {
    final rawInst = widget.institutionId.trim();
    final upInst = rawInst.toUpperCase();
    final docsById = <String, Map<String, dynamic>>{};

    final col = FirebaseFirestore.instance.collection('students');
    final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[
      col.where('institutionId', isEqualTo: rawInst).get(),
      if (upInst != rawInst)
        col.where('institutionId', isEqualTo: upInst).get(),
    ];

    final snaps = await Future.wait(queries);
    for (final s in snaps) {
      for (final d in s.docs) {
        docsById[d.id] = d.data();
      }
    }

    String pickStr(Map<String, dynamic> m, List<String> keys) {
      for (final k in keys) {
        final v = (m[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final list = <_StudentLite>[];
    docsById.forEach((docId, m) {
      if (m['isActive'] == false) return;

      var name = pickStr(m, ['fullName', 'name']);
      if (name.isEmpty) {
        final fn = (m['firstName'] ?? '').toString().trim();
        final ln = (m['lastName'] ?? '').toString().trim();
        name = '$fn $ln'.trim();
      }
      if (name.isEmpty) return;

      final number = pickStr(m, ['studentNumber', 'schoolNo', 'number']);
      var className = pickStr(m, ['className', 'classLabel']);
      if (className.isEmpty) {
        final lvl = (m['classLevel'] ?? '').toString().trim();
        final br = (m['branch'] ?? '').toString().trim();
        className = [if (lvl.isNotEmpty) lvl, if (br.isNotEmpty) br].join('-');
      }

      // Veli UID'leri
      final uids = <String>{};
      void addUid(dynamic v) {
        if (v is Iterable) {
          for (final item in v) {
            final s = (item ?? '').toString().trim();
            if (s.isNotEmpty) uids.add(s);
          }
        } else if (v != null) {
          final s = v.toString().trim();
          if (s.isNotEmpty) uids.add(s);
        }
      }

      addUid(m['parentIds']);
      addUid(m['parentUids']);
      addUid(m['parentUid']);

      String parentMail = pickStr(m, [
        'parentEmail',
        'guardianEmail',
        'motherEmail',
        'fatherEmail',
      ]);

      final parentsList = m['parents'];
      if (parentsList is Iterable) {
        for (final p in parentsList) {
          if (p is Map) {
            addUid(p['uid']);
            addUid(p['userId']);
            if (parentMail.isEmpty) {
              final em = (p['email'] ?? '').toString().trim();
              if (em.isNotEmpty) parentMail = em;
            }
          }
        }
      }

      list.add(
        _StudentLite(
          id: docId,
          name: name,
          number: number,
          className: className,
          parentUids: uids.toList(),
          parentEmail: parentMail,
        ),
      );
    });

    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openDialog([CanteenCard? card]) async {
    if (_inst.isEmpty) return;
    final res = await showDialog<CanteenCard>(
      context: context,
      builder: (_) => _CardDialog(
        existing: card,
        loadStudents: _loadStudents,
        cards: _cards,
      ),
    );
    if (res == null || !mounted) return;
    try {
      await _svc.saveCard(_inst, res);
      if (mounted) {
        cnSnack(
          context,
          card == null
              ? 'Yeni kantin kartı başarıyla tanımlandı.'
              : 'Kantin kartı güncellendi.',
        );
      }
    } catch (e) {
      if (mounted) cnSnack(context, cnErr(e), error: true);
    }
  }

  Future<void> _toggle(CanteenCard c, bool v) async {
    try {
      await _svc.setCardActive(_inst, c.cardNo, v);
      if (mounted) {
        cnSnack(
          context,
          v ? '${c.studentName} kartı aktifleştirildi.' : 'Kart pasife alındı.',
        );
      }
    } catch (e) {
      if (mounted) cnSnack(context, cnErr(e), error: true);
    }
  }

  List<CanteenCard> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _cards.where((c) {
      if (_statusFilter == 'active' && !c.isActive) return false;
      if (_statusFilter == 'passive' && c.isActive) return false;
      if (q.isEmpty) return true;
      return c.studentName.toLowerCase().contains(q) ||
          c.cardNo.toLowerCase().contains(q) ||
          c.className.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final list = _filtered;
    final totalCards = _cards.length;
    final activeCards = _cards.where((c) => c.isActive).length;
    final passiveCards = totalCards - activeCards;
    final totalBalance = _cards.fold<double>(0, (s, c) => s + c.balance);
    final limitedCards = _cards.where((c) => c.dailyLimit > 0).length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Üst 4 KPI Özet Kartı
          _buildKpiRow(
            totalCards: totalCards,
            activeCards: activeCards,
            totalBalance: totalBalance,
            limitedCards: limitedCards,
          ),
          const SizedBox(height: 12),

          // Arama + Durum Hapları + Yeni Kart Tanımla (her zaman mount kalır)
          CnPanel(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, c) {
                final searchBox = TextField(
                  controller: _searchCtrl,
                  decoration: cnInput(
                    'Öğrenci adı, kart no veya sınıf ara...',
                    prefix: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: CnColors.muted,
                    ),
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

                final pillsAndBtn = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _statusPill('all', 'Tümü ($totalCards)'),
                    _statusPill('active', 'Aktif ($activeCards)'),
                    _statusPill('passive', 'Pasif ($passiveCards)'),
                    ElevatedButton.icon(
                      style: cnPrimaryBtn(),
                      onPressed: _inst.isEmpty ? null : () => _openDialog(),
                      icon: const Icon(Icons.add_card_rounded, size: 18),
                      label: const Text('Yeni Kart Tanımla'),
                    ),
                  ],
                );

                if (c.maxWidth < 780) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchBox,
                      const SizedBox(height: 10),
                      pillsAndBtn,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: searchBox),
                    const SizedBox(width: 12),
                    pillsAndBtn,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Sanal Kartlar Izgarası
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: CnColors.brand),
                  )
                : _error != null
                ? CnError(_error!, onRetry: _init)
                : list.isEmpty
                ? CnEmpty(
                    _cards.isEmpty
                        ? 'Henüz tanımlı kantin kartı yok.'
                        : 'Arama kriterlerine uygun kart bulunamadı.',
                    subtitle: _cards.isEmpty
                        ? 'Öğrencilere temassız veya QR kantin kartı tanımlayarak harcama limiti ve cüzdan takibini başlatın.'
                        : 'Farklı bir anahtar kelime veya durum filtresi deneyin.',
                    icon: Icons.credit_card_off_rounded,
                    action: _cards.isEmpty && _inst.isNotEmpty
                        ? ElevatedButton.icon(
                            style: cnPrimaryBtn(),
                            onPressed: () => _openDialog(),
                            icon: const Icon(Icons.add_card_rounded, size: 18),
                            label: const Text('İlk Kartı Tanımla'),
                          )
                        : null,
                  )
                : _buildCardsGrid(list),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow({
    required int totalCards,
    required int activeCards,
    required double totalBalance,
    required int limitedCards,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 980 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: w,
              child: CnKpi(
                label: 'Toplam Kart',
                value: '$totalCards',
                icon: Icons.credit_card_rounded,
                color: CnColors.brand,
              ),
            ),
            SizedBox(
              width: w,
              child: CnKpi(
                label: 'Aktif Kart',
                value: '$activeCards',
                icon: Icons.verified_user_outlined,
                color: CnColors.ok,
              ),
            ),
            SizedBox(
              width: w,
              child: CnKpi(
                label: 'Toplam Cüzdan Bakiyesi',
                value: cnMoney(totalBalance),
                icon: Icons.account_balance_wallet_outlined,
                color: CnColors.indigo,
              ),
            ),
            SizedBox(
              width: w,
              child: CnKpi(
                label: 'Limitli Kart',
                value: '$limitedCards',
                icon: Icons.speed_rounded,
                color: CnColors.warn,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statusPill(String key, String label) {
    final sel = _statusFilter == key;
    return Material(
      color: sel ? CnColors.brand : CnColors.surfaceAlt,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _statusFilter = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
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

  Widget _buildCardsGrid(List<CanteenCard> list) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1100 ? 3 : (c.maxWidth >= 680 ? 2 : 1);
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 12),
          itemCount: list.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisExtent: 196,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, i) => _studentCardTile(list[i]),
        );
      },
    );
  }

  Widget _studentCardTile(CanteenCard c) {
    final active = c.isActive;
    return Container(
      decoration: BoxDecoration(
        color: active ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? CnColors.border : CnColors.borderStrong,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Üst vurgu şeridi
            Container(
              height: 5,
              decoration: BoxDecoration(
                gradient: active
                    ? CnColors.gradient
                    : CnColors.passiveCardGradient,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Öğrenci Avatar + İsim + Sınıf + Çip/Düzenle
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: active ? CnColors.gradient : null,
                            color: active ? null : CnColors.borderStrong,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Center(
                            child: Text(
                              cnInitials(c.studentName),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.studentName.trim().isEmpty
                                    ? '(İsimsiz Kart)'
                                    : c.studentName.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: active
                                      ? CnColors.text
                                      : CnColors.muted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.contactless_outlined,
                                    size: 13,
                                    color: CnColors.muted,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      c.cardNo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w700,
                                        color: CnColors.slate,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (c.className.trim().isNotEmpty)
                          CnBadge(
                            c.className.trim(),
                            color: active ? CnColors.brand : CnColors.muted,
                          ),
                      ],
                    ),
                    const Spacer(),
                    // Bakiye + Limit / Kısıtlama rozetleri
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CÜZDAN BAKİYESİ',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: CnColors.muted,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  cnMoney(c.balance),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: active
                                        ? CnColors.text
                                        : CnColors.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 6,
                          children: [
                            CnBadge(
                              c.dailyLimit > 0
                                  ? 'Limit: ${cnMoney(c.dailyLimit)}'
                                  : 'Limitsiz',
                              color: c.dailyLimit > 0
                                  ? CnColors.warnDark
                                  : CnColors.okDark,
                              icon: Icons.speed_rounded,
                            ),
                            if (c.blockedCategories.isNotEmpty)
                              CnBadge(
                                '${c.blockedCategories.length} Kısıt',
                                color: Colors.purple.shade700,
                                icon: Icons.block_rounded,
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 4),
                    // Alt Aksiyon Çubuğu
                    Row(
                      children: [
                        CnBadge(
                          active ? 'Aktif' : 'Pasif',
                          color: active ? CnColors.okDark : CnColors.muted,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          style: cnTextBtn(),
                          onPressed: () => _openDialog(c),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Düzenle'),
                        ),
                        SizedBox(
                          height: 28,
                          child: FittedBox(
                            child: Switch(
                              value: active,
                              activeTrackColor: CnColors.brand,
                              onChanged: (v) => _toggle(c, v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// YENİ KART TANIMLA / DÜZENLE MODALI (CnDialogShell)
// ═════════════════════════════════════════════════════════════════════════════

class _CardDialog extends StatefulWidget {
  final CanteenCard? existing;
  final Future<List<_StudentLite>> Function() loadStudents;
  final List<CanteenCard> cards;

  const _CardDialog({
    required this.existing,
    required this.loadStudents,
    required this.cards,
  });

  @override
  State<_CardDialog> createState() => _CardDialogState();
}

class _CardDialogState extends State<_CardDialog> {
  static const List<double> _limitPresets = [0, 50, 100, 150, 250, 500];

  late final TextEditingController _cardNo;
  late final TextEditingController _name;
  late final TextEditingController _class;
  late final TextEditingController _limit;
  late final TextEditingController _parentMail;
  final TextEditingController _studentSearch = TextEditingController();

  late bool _active;
  String _studentId = '';
  String _studentNumber = '';
  List<String> _parentUids = const [];
  late Set<String> _blockedCats;
  bool _showAdvanced = false;
  String? _err;
  Future<List<_StudentLite>>? _future;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _cardNo = TextEditingController(text: e?.cardNo ?? '');
    _name = TextEditingController(text: e?.studentName ?? '');
    _class = TextEditingController(text: e?.className ?? '');
    _limit = TextEditingController(
      text: (e != null && e.dailyLimit > 0)
          ? (e.dailyLimit == e.dailyLimit.roundToDouble()
                ? e.dailyLimit.toInt().toString()
                : e.dailyLimit.toStringAsFixed(2))
          : '',
    );
    _parentMail = TextEditingController(text: e?.parentEmail ?? '');
    _active = e?.isActive ?? true;
    _studentId = e?.studentId ?? '';
    _parentUids = List<String>.from(e?.parentUids ?? const []);
    _blockedCats = Set<String>.from(e?.blockedCategories ?? const []);
    _showAdvanced =
        _parentMail.text.trim().isNotEmpty || _blockedCats.isNotEmpty;
    if (!_isEdit) _future = widget.loadStudents();
  }

  @override
  void dispose() {
    _cardNo.dispose();
    _name.dispose();
    _class.dispose();
    _limit.dispose();
    _parentMail.dispose();
    _studentSearch.dispose();
    super.dispose();
  }

  void _generateCardNo() {
    final existingNos = widget.cards.map((c) => c.cardNo.toUpperCase()).toSet();
    final rnd = Random();
    String candidate = '';
    for (var i = 0; i < 40; i++) {
      final code = 100000 + rnd.nextInt(900000);
      candidate = 'KNT-$code';
      if (!existingNos.contains(candidate)) break;
    }
    setState(() {
      _cardNo.text = candidate;
      _err = null;
    });
  }

  void _pickStudent(_StudentLite s) {
    setState(() {
      _studentId = s.id;
      _studentNumber = s.number;
      _name.text = s.name;
      _class.text = s.className;
      _parentUids = s.parentUids;
      if (s.parentEmail.isNotEmpty && _parentMail.text.trim().isEmpty) {
        _parentMail.text = s.parentEmail;
      }
      if (_cardNo.text.trim().isEmpty) {
        final existingNos = widget.cards
            .map((c) => c.cardNo.toUpperCase())
            .toSet();
        final candidate = s.number.isNotEmpty ? 'KNT-${s.number}' : '';
        if (candidate.isNotEmpty && !existingNos.contains(candidate)) {
          _cardNo.text = candidate;
        } else {
          _generateCardNo();
        }
      }
      _studentSearch.clear();
      _err = null;
    });
  }

  void _clearStudent() {
    setState(() {
      _studentId = '';
      _studentNumber = '';
      _parentUids = const [];
    });
  }

  CanteenCard get _previewCard {
    return CanteenCard(
      cardNo: _cardNo.text.trim().isEmpty ? 'KNT-000000' : _cardNo.text.trim(),
      studentId: _studentId,
      studentName: _name.text.trim().isEmpty
          ? 'Öğrenci Adı Soyadı'
          : _name.text.trim(),
      className: _class.text.trim(),
      balance: widget.existing?.balance ?? 0,
      isActive: _active,
      dailyLimit: cnParseMoney(_limit.text),
      blockedCategories: _blockedCats.toList(),
    );
  }

  void _save() {
    final no = _cardNo.text.trim();
    if (no.isEmpty) {
      setState(
        () => _err =
            'Kart numarası zorunludur ("Otomatik Üret" kullanabilirsiniz).',
      );
      return;
    }
    if (no.contains('/')) {
      setState(() => _err = 'Kart numarası "/" karakteri içeremez.');
      return;
    }
    if (!_isEdit) {
      final dup = widget.cards.any(
        (c) => c.cardNo.toLowerCase() == no.toLowerCase(),
      );
      if (dup) {
        setState(() => _err = 'Bu kart numarası ($no) zaten kullanımda.');
        return;
      }
    }
    if (_name.text.trim().isEmpty) {
      setState(
        () => _err = 'Lütfen listeden bir öğrenci seçin veya ad soyad girin.',
      );
      return;
    }
    if (_studentId.isNotEmpty) {
      for (final c in widget.cards) {
        if (c.studentId == _studentId && c.cardNo != no) {
          setState(
            () => _err =
                'Seçilen öğrencinin zaten aktif bir kantin kartı var (${c.cardNo}).',
          );
          return;
        }
      }
    }

    final base = widget.existing ?? CanteenCard(cardNo: no);
    Navigator.pop(
      context,
      base.copyWith(
        cardNo: no,
        studentId: _studentId,
        studentName: _name.text.trim(),
        className: _class.text.trim(),
        isActive: _active,
        dailyLimit: cnParseMoney(_limit.text),
        blockedCategories: _blockedCats.toList(),
        parentUids: _parentUids,
        parentEmail: _parentMail.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final curLimit = cnParseMoney(_limit.text);

    return CnDialogShell(
      title: _isEdit ? 'Kantin Kartını Düzenle' : 'Yeni Kantin Kartı Tanımla',
      subtitle: _isEdit
          ? 'Kart limiti, durum ve öğrenci bilgilerini güncelleyin'
          : 'Öğrenci seçerek veya manuel bilgi girerek cüzdan kartı oluşturun',
      icon: _isEdit ? Icons.edit_note_rounded : Icons.add_card_rounded,
      maxWidth: 620,
      errorText: _err,
      primaryLabel: _isEdit ? 'Değişiklikleri Kaydet' : 'Kartı Oluştur',
      primaryIcon: Icons.check_circle_outline_rounded,
      onPrimary: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Canlı Sanal Kart Önizlemesi
          CnVirtualCard(card: _previewCard, compact: true),
          const SizedBox(height: 18),

          // Öğrenci Seçici (Yeni kart tanımlarken)
          if (!_isEdit) ...[
            const CnSectionLabel('ÖĞRENCİ SEÇİMİ', icon: Icons.school_outlined),
            _buildStudentSelector(),
            const SizedBox(height: 16),
          ],

          // Kart Numarası + Otomatik Üret
          const CnSectionLabel(
            'KART KİMLİĞİ & ÖĞRENCİ BİLGİSİ',
            icon: Icons.badge_outlined,
          ),
          TextField(
            controller: _cardNo,
            enabled: !_isEdit,
            onChanged: (_) => setState(() {}),
            decoration: cnInput(
              'Kart Numarası *',
              hint: 'Örn. KNT-849201 veya RFID seri no',
              prefix: const Icon(
                Icons.credit_card_rounded,
                size: 20,
                color: CnColors.brand,
              ),
              suffix: _isEdit
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: TextButton.icon(
                        style: cnTextBtn(),
                        onPressed: _generateCardNo,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                        label: const Text('Otomatik Üret'),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),

          // Öğrenci Adı & Sınıf (Geniş ekranda yan yana)
          LayoutBuilder(
            builder: (context, c) {
              final nameField = TextField(
                controller: _name,
                onChanged: (_) => setState(() {}),
                decoration: cnInput(
                  'Öğrenci Adı Soyadı *',
                  prefix: const Icon(Icons.person_outline_rounded, size: 20),
                ),
              );
              final classField = TextField(
                controller: _class,
                onChanged: (_) => setState(() {}),
                decoration: cnInput(
                  'Sınıf / Şube',
                  hint: 'Örn. 8-A',
                  prefix: const Icon(Icons.class_outlined, size: 20),
                ),
              );

              if (c.maxWidth < 430) {
                return Column(
                  children: [nameField, const SizedBox(height: 12), classField],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 3, child: nameField),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: classField),
                ],
              );
            },
          ),
          const SizedBox(height: 18),

          // Günlük Harcama Limiti Hızlı Seçim Hapları + Özel Tutar
          const CnSectionLabel(
            'GÜNLÜK HARCAMA LİMİTİ',
            icon: Icons.speed_rounded,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _limitPresets)
                _limitChip(
                  label: preset == 0 ? 'Limitsiz' : '${preset.toInt()} ₺',
                  selected:
                      (preset == 0 && curLimit == 0) ||
                      (preset > 0 && (curLimit - preset).abs() < 0.01),
                  onTap: () {
                    setState(() {
                      _limit.text = preset == 0
                          ? ''
                          : preset.toInt().toString();
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _limit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: cnInput(
              'Özel Günlük Limit (₺)',
              hint: 'Boş veya 0 bırakılırsa limitsiz olur',
              prefix: const Icon(Icons.currency_lira_rounded, size: 19),
            ),
          ),
          const SizedBox(height: 14),

          // Gelişmiş / Veli & Kategori Kısıtlama (Açılır Bölüm)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _showAdvanced
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: CnColors.brand,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Veli Bağlantısı & Kategori Kısıtlamaları (Opsiyonel)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: CnColors.brand,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showAdvanced) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _parentMail,
              keyboardType: TextInputType.emailAddress,
              decoration: cnInput(
                'Veli E-posta (Opsiyonel)',
                hint: 'veli@ornek.com',
                prefix: const Icon(Icons.alternate_email_rounded, size: 19),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Öğrenciye Kısıtlanan Kategoriler:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: CnColors.slate,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final cat in kCnPresetCategories)
                  FilterChip(
                    label: Text(cat),
                    selected: _blockedCats.contains(cat),
                    showCheckmark: false,
                    selectedColor: Colors.red.shade50,
                    backgroundColor: CnColors.surfaceAlt,
                    side: BorderSide(
                      color: _blockedCats.contains(cat)
                          ? Colors.red.shade400
                          : CnColors.border,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _blockedCats.contains(cat)
                          ? Colors.red.shade700
                          : CnColors.slate,
                    ),
                    avatar: Icon(
                      _blockedCats.contains(cat)
                          ? Icons.block_rounded
                          : cnCategoryIcon(cat),
                      size: 15,
                      color: _blockedCats.contains(cat)
                          ? Colors.red.shade700
                          : cnCategoryColor(cat),
                    ),
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _blockedCats.add(cat);
                        } else {
                          _blockedCats.remove(cat);
                        }
                      });
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),

          // Kart Aktif Anahtar Kartı
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: CnColors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: CnColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  _active
                      ? Icons.check_circle_outline_rounded
                      : Icons.pause_circle_outline_rounded,
                  color: _active ? CnColors.ok : CnColors.muted,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kart Kullanıma Açık',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: CnColors.text,
                        ),
                      ),
                      Text(
                        _active
                            ? 'Kasada satış ve bakiye yükleme yapılabilir'
                            : 'Kart geçici olarak donduruldu / bloke edildi',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: CnColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _active,
                  activeTrackColor: CnColors.brand,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _limitChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? CnColors.brand : CnColors.surfaceAlt,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? CnColors.brand : CnColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : CnColors.slate,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentSelector() {
    if (_studentId.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: CnColors.pinkBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CnColors.pink),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: CnColors.brand,
              child: Text(
                cnInitials(_name.text),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: CnColors.text,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    [
                      if (_studentNumber.isNotEmpty) 'No: $_studentNumber',
                      if (_class.text.isNotEmpty) _class.text,
                      if (_parentUids.isNotEmpty) 'Veli bağlı',
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: CnColors.slate,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              style: cnTextBtn(),
              onPressed: _clearStudent,
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: const Text('Değiştir'),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<List<_StudentLite>>(
      future: _future,
      builder: (context, snap) {
        final waiting = snap.connectionState != ConnectionState.done;
        final all = snap.data ?? const <_StudentLite>[];
        final q = _studentSearch.text.trim().toLowerCase();
        final matches = q.isEmpty
            ? all.take(5).toList()
            : all
                  .where(
                    (s) =>
                        s.name.toLowerCase().contains(q) ||
                        s.number.toLowerCase().contains(q) ||
                        s.className.toLowerCase().contains(q),
                  )
                  .take(8)
                  .toList();

        final assignedIds = {
          for (final c in widget.cards)
            if (c.studentId.isNotEmpty) c.studentId: c.cardNo,
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _studentSearch,
              decoration: cnInput(
                'Kayıtlı Öğrenci Ara (Ad, Okul No veya Sınıf)',
                hint: waiting
                    ? 'Öğrenci listesi yükleniyor...'
                    : '${all.length} kayıtlı öğrenci içinde arayın...',
                prefix: const Icon(
                  Icons.person_search_rounded,
                  size: 20,
                  color: CnColors.brand,
                ),
                suffix: waiting
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: CnColors.brand,
                          ),
                        ),
                      )
                    : (_studentSearch.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _studentSearch.clear();
                                setState(() {});
                              },
                            )),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (!waiting && snap.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Öğrenci listesi alınamadı (${cnErr(snap.error!)}). Manuel giriş yapabilirsiniz.',
                  style: const TextStyle(fontSize: 12, color: CnColors.muted),
                ),
              )
            else if (!waiting && matches.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                constraints: const BoxConstraints(maxHeight: 168),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CnColors.border),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: matches.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, i) {
                    final s = matches[i];
                    final existingCard = assignedIds[s.id];
                    return InkWell(
                      onTap: existingCard != null
                          ? null
                          : () => _pickStudent(s),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: existingCard != null
                                  ? CnColors.surfaceAlt
                                  : CnColors.pinkBg,
                              child: Text(
                                cnInitials(s.name),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: existingCard != null
                                      ? CnColors.muted
                                      : CnColors.brand,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: existingCard != null
                                          ? CnColors.muted
                                          : CnColors.text,
                                    ),
                                  ),
                                  Text(
                                    [
                                      if (s.number.isNotEmpty)
                                        'No: ${s.number}',
                                      if (s.className.isNotEmpty) s.className,
                                    ].join(' • '),
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
                            if (existingCard != null)
                              CnBadge(
                                'Kartlı: $existingCard',
                                color: CnColors.muted,
                              )
                            else
                              const Icon(
                                Icons.add_circle_outline_rounded,
                                size: 18,
                                color: CnColors.brand,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
