import 'package:flutter/material.dart';

import '../models/pos/pos_config_model.dart';
import '../services/payment_gateway_service.dart';

/// Kurum / Okul Mağazası / Kantin / Genel Merkez Sanal POS Yapılandırma Diyaloğu.
///
/// Bir okulun:
/// 1) **Kurum Ana POS** (Muhasebe, eğitim ücreti ve ortak tahsilatlar)
/// 2) **Okul Mağazası POS** (Kurum POS'unu miras alabilir veya mağazaya özel ayrı POS olabilir)
/// 3) **Kantin POS** (Kantin işletmecisine ait ayrı POS veya Kurum POS'u olabilir)
/// ayarlarını tek merkezden güvenle yönetmesini sağlar.
class SchoolPosSettingsDialog extends StatefulWidget {
  final String institutionId;
  final String institutionTitle;
  final bool isHq;
  final int initialTab; // 0: Kurum Ana POS, 1: Mağaza POS, 2: Kantin POS

  const SchoolPosSettingsDialog({
    super.key,
    required this.institutionId,
    this.institutionTitle = '',
    this.isHq = false,
    this.initialTab = 0,
  });

  static Future<InstitutionPosConfig?> show(
    BuildContext context, {
    required String institutionId,
    String institutionTitle = '',
    bool isHq = false,
    int initialTab = 0,
  }) {
    return showDialog<InstitutionPosConfig>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SchoolPosSettingsDialog(
        institutionId: institutionId,
        institutionTitle: institutionTitle,
        isHq: isHq,
        initialTab: initialTab,
      ),
    );
  }

  @override
  State<SchoolPosSettingsDialog> createState() =>
      _SchoolPosSettingsDialogState();
}

class _ProfileControllers {
  bool enabled;
  String provider;
  String environment;
  final TextEditingController titleCtrl;
  final TextEditingController apiKeyCtrl;
  final TextEditingController secretKeyCtrl;
  final TextEditingController baseUrlCtrl;
  final TextEditingController subMerchantCtrl;
  final TextEditingController noteCtrl;
  bool allowInstallments;
  final Set<int> installments;
  bool obscureSecret = true;

  _ProfileControllers(PosCredentialProfile p)
    : enabled = p.enabled,
      provider = p.provider,
      environment = p.environment,
      titleCtrl = TextEditingController(text: p.merchantTitle),
      apiKeyCtrl = TextEditingController(text: p.apiKey),
      secretKeyCtrl = TextEditingController(text: p.secretKey),
      baseUrlCtrl = TextEditingController(text: p.baseUrl),
      subMerchantCtrl = TextEditingController(text: p.subMerchantKey),
      noteCtrl = TextEditingController(text: p.terminalNote),
      allowInstallments = p.allowInstallments,
      installments = Set<int>.from(p.enabledInstallments)..add(1);

  PosCredentialProfile toProfile() {
    final sorted = <int>{1, if (allowInstallments) ...installments}.toList()
      ..sort();
    return PosCredentialProfile(
      enabled: enabled,
      provider: provider,
      environment: environment,
      merchantTitle: titleCtrl.text.trim(),
      apiKey: apiKeyCtrl.text.trim(),
      secretKey: secretKeyCtrl.text.trim(),
      baseUrl: baseUrlCtrl.text.trim(),
      subMerchantKey: subMerchantCtrl.text.trim(),
      allowInstallments: allowInstallments,
      enabledInstallments: allowInstallments ? sorted : const [1],
      terminalNote: noteCtrl.text.trim(),
    );
  }

  void dispose() {
    titleCtrl.dispose();
    apiKeyCtrl.dispose();
    secretKeyCtrl.dispose();
    baseUrlCtrl.dispose();
    subMerchantCtrl.dispose();
    noteCtrl.dispose();
  }
}

class _SchoolPosSettingsDialogState extends State<SchoolPosSettingsDialog>
    with SingleTickerProviderStateMixin {
  final PaymentGatewayService _gateway = PaymentGatewayService.instance;

  TabController? _tabController;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  late _ProfileControllers _defaultCtrl;
  late _ProfileControllers _storeCustomCtrl;
  late _ProfileControllers _canteenCustomCtrl;

  String _storeMode = PosChannelModes.inheritSchool;
  String _canteenMode = PosChannelModes.inheritSchool;

  String get _instUpper =>
      widget.isHq ? 'SUPER_ADMIN' : widget.institutionId.trim().toUpperCase();

  @override
  void initState() {
    super.initState();
    _defaultCtrl = _ProfileControllers(const PosCredentialProfile());
    _storeCustomCtrl = _ProfileControllers(const PosCredentialProfile());
    _canteenCustomCtrl = _ProfileControllers(
      const PosCredentialProfile(
        allowInstallments: false,
        enabledInstallments: [1],
      ),
    );
    if (!widget.isHq) {
      _tabController = TabController(
        length: 3,
        vsync: this,
        initialIndex: widget.initialTab.clamp(0, 2),
      );
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cfg = await _gateway.getPosConfig(_instUpper);
      if (!mounted) return;
      _defaultCtrl.dispose();
      _storeCustomCtrl.dispose();
      _canteenCustomCtrl.dispose();

      _defaultCtrl = _ProfileControllers(cfg.defaultPos);
      _storeCustomCtrl = _ProfileControllers(cfg.storePos.customProfile);
      _canteenCustomCtrl = _ProfileControllers(cfg.canteenPos.customProfile);
      _storeMode = cfg.storePos.mode;
      _canteenMode = cfg.canteenPos.mode;

      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'POS ayarları okunamadı: $e';
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _defaultCtrl.dispose();
    _storeCustomCtrl.dispose();
    _canteenCustomCtrl.dispose();
    super.dispose();
  }

  String? _validateProfile(_ProfileControllers c, String sectionName) {
    if (!c.enabled) return null;
    if (c.apiKeyCtrl.text.trim().isEmpty ||
        c.secretKeyCtrl.text.trim().isEmpty) {
      return '$sectionName aktif edildiğinde API Key ve Secret Key alanları zorunludur.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;

    // Özel mod seçildiyse otomatik olarak profili aktif kabul et
    if (_storeMode == PosChannelModes.custom) {
      _storeCustomCtrl.enabled = true;
    }
    if (_canteenMode == PosChannelModes.custom) {
      _canteenCustomCtrl.enabled = true;
    }

    final errDefault = _validateProfile(
      _defaultCtrl,
      widget.isHq ? 'Genel Merkez POS' : 'Kurum Ana POS',
    );
    final errStore = _storeMode == PosChannelModes.custom
        ? _validateProfile(_storeCustomCtrl, 'Okul Mağazası Özel POS')
        : null;
    final errCanteen = _canteenMode == PosChannelModes.custom
        ? _validateProfile(_canteenCustomCtrl, 'Kantin Özel POS')
        : null;

    final firstErr = errDefault ?? errStore ?? errCanteen;
    if (firstErr != null) {
      setState(() => _error = firstErr);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final defaultProfile = _defaultCtrl.toProfile();
      final cfg = InstitutionPosConfig(
        institutionId: _instUpper,
        defaultPos: defaultProfile,
        storePos: PosChannelConfig(
          mode: widget.isHq ? PosChannelModes.inheritSchool : _storeMode,
          customProfile: _storeCustomCtrl.toProfile(),
        ),
        canteenPos: PosChannelConfig(
          mode: widget.isHq ? PosChannelModes.inheritSchool : _canteenMode,
          customProfile: _canteenCustomCtrl.toProfile(),
        ),
        accountingPos: const PosChannelConfig(
          mode: PosChannelModes.inheritSchool,
        ),
        updatedAt: DateTime.now(),
      );
      await _gateway.savePosConfig(cfg);
      if (!mounted) return;
      Navigator.pop(context, cfg);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'POS ayarları kaydedilemedi: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.isHq
        ? 'Genel Merkez Mağazası & Merkezi Tahsilat Altyapısı'
        : '${widget.institutionTitle.isNotEmpty ? widget.institutionTitle : _instUpper} • Kurum, Mağaza ve Kantin POS Yönetimi';

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(subtitle),
            if (!widget.isHq && _tabController != null)
              Container(
                color: Colors.indigo.shade50.withValues(alpha: 0.45),
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.indigo.shade900,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: Colors.indigo.shade700,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.account_balance_rounded, size: 18),
                      text: '1. Kurum Ana POS',
                    ),
                    Tab(
                      icon: Icon(Icons.storefront_rounded, size: 18),
                      text: '2. Okul Mağazası POS',
                    ),
                    Tab(
                      icon: Icon(Icons.restaurant_rounded, size: 18),
                      text: '3. Kantin POS',
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            if (_error != null)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: Colors.red.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : (widget.isHq
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: _buildDefaultPosSection(
                              title: 'Genel Merkez Sanal POS Hesabı',
                              description:
                                  'Genel Merkez ürünlerinin online satışlarında ve özel POS tanımlamayan okulların merkezi tahsilatlarında kullanılır.',
                            ),
                          )
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: _buildDefaultPosSection(
                                  title:
                                      'Okul / Kurum Ana Sanal POS Hesabı (Genel & Muhasebe)',
                                  description:
                                      'Okulunuzun ana sanal POS hesabıdır. Mağaza ve Kantin sekmelerinde "Kurum Ana POS Hesabını Kullan" seçildiğinde tüm ödemeler bu hesaba aktarılır.',
                                ),
                              ),
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: _buildChannelPosSection(
                                  moduleLabel: 'Okul Mağazası',
                                  moduleDescription:
                                      'Okul Mağazası kitap, kıyafet ve materyal satışlarında hangi POS hesabının kullanılacağını belirleyin. Genel Merkez ürünleri kendi POS hesabından, Okul ürünleri ise buradaki POS hesabınızdan tahsil edilir.',
                                  mode: _storeMode,
                                  onModeChanged: (v) =>
                                      setState(() => _storeMode = v),
                                  customCtrl: _storeCustomCtrl,
                                ),
                              ),
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: _buildChannelPosSection(
                                  moduleLabel: 'Okul Kantini',
                                  moduleDescription:
                                      'Kantin işletmesi ayrı bir firmaya aitse veya ayrı banka POS hesabı kullanıyorsa "Okul Kantini İçin Ayrı Özel POS Kullan" seçeneğiyle veli bakiye yüklemelerini ve Mobil QR kart ödemelerini doğrudan kantin POS hesabına yönlendirebilirsiniz.',
                                  mode: _canteenMode,
                                  onModeChanged: (v) =>
                                      setState(() => _canteenMode = v),
                                  customCtrl: _canteenCustomCtrl,
                                ),
                              ),
                            ],
                          )),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Vazgeç'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _loading || _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(
                      _saving ? 'Kaydediliyor...' : 'POS Ayarlarını Kaydet',
                      style: const TextStyle(fontWeight: FontWeight.w700),
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

  Widget _buildHeader(String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.point_of_sale_rounded,
              color: Colors.indigo.shade700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isHq
                      ? 'Genel Merkez Sanal POS Yapılandırması'
                      : 'Kurum, Mağaza & Kantin Sanal POS Ayarları',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.indigo.shade900,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultPosSection({
    required String title,
    required String description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.indigo.shade100),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.shield_outlined,
                color: Colors.indigo.shade700,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  description,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.indigo.shade900,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _defaultCtrl.enabled,
          onChanged: (v) => setState(() => _defaultCtrl.enabled = v),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          subtitle: Text(
            _defaultCtrl.enabled
                ? 'Aktif — Aşağıdaki API anahtarları ile tahsilat yapılır.'
                : 'Kapalı — Açıldığında kurumunuza özel POS anahtarları devreye girer.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        const SizedBox(height: 8),
        _buildCredentialForm(_defaultCtrl),
      ],
    );
  }

  Widget _buildChannelPosSection({
    required String moduleLabel,
    required String moduleDescription,
    required String mode,
    required ValueChanged<String> onModeChanged,
    required _ProfileControllers customCtrl,
  }) {
    final modes = [
      MapEntry(
        PosChannelModes.inheritSchool,
        'Kurum Ana POS Hesabını Kullan (${_defaultCtrl.enabled ? (_defaultCtrl.titleCtrl.text.trim().isNotEmpty ? _defaultCtrl.titleCtrl.text.trim() : "Tanımlı") : "Henüz Tanımlanmadı"})',
      ),
      MapEntry(
        PosChannelModes.custom,
        '$moduleLabel İçin Ayrı Özel Sanal POS Tanımla',
      ),
      const MapEntry(
        PosChannelModes.platformDefault,
        'Merkezi / Test Platform POS Altyapısını Kullan',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Colors.amber.shade900,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  moduleDescription,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.amber.shade900,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '$moduleLabel POS Çalışma Modu',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ...modes.map((entry) {
          final selected = mode == entry.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (entry.key == PosChannelModes.custom) {
                  customCtrl.enabled = true;
                }
                onModeChanged(entry.key);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.indigo.shade50.withValues(alpha: 0.7)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? Colors.indigo.shade600
                        : Colors.grey.shade300,
                    width: selected ? 1.6 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: selected
                          ? Colors.indigo.shade700
                          : Colors.grey.shade500,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selected
                              ? Colors.indigo.shade900
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        if (mode == PosChannelModes.platformDefault) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFF059669),
                  size: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Test Platform POS Aktif: Herhangi bir banka/iyzico API anahtarı tanımlamanıza gerek kalmadan alışveriş ve ödemeler test modunda hatasız olarak onaylanır ve sipariş/bakiye kayıtlarına işlenir.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF065F46),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (mode == PosChannelModes.custom) ...[
          const Divider(height: 24),
          Text(
            '$moduleLabel Özel POS Kimlik Bilgileri',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: Colors.indigo.shade900,
            ),
          ),
          const SizedBox(height: 10),
          _buildCredentialForm(customCtrl),
        ],
      ],
    );
  }

  Widget _buildCredentialForm(_ProfileControllers c) {
    OutlineInputBorder b(Color col, [double w = 1.1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: col, width: w),
    );
    InputDecoration dec(
      String label, {
      String? hint,
      IconData? prefixIcon,
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 19, color: Colors.indigo.shade600)
            : null,
        suffixIcon: suffixIcon,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        labelStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF475569),
        ),
        floatingLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.indigo.shade700,
        ),
        hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: b(const Color(0xFFCBD5E1)),
        enabledBorder: b(const Color(0xFFCBD5E1)),
        focusedBorder: b(Colors.indigo.shade600, 1.8),
      );
    }

    final providerDropdown = DropdownButtonFormField<String>(
      initialValue: PosProviders.all.contains(c.provider)
          ? c.provider
          : PosProviders.iyzico,
      borderRadius: BorderRadius.circular(14),
      isExpanded: true,
      decoration: dec('POS Sağlayıcısı', prefixIcon: Icons.credit_card_rounded),
      items: PosProviders.all
          .map(
            (p) => DropdownMenuItem(
              value: p,
              child: Text(
                PosProviders.labelOf(p),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => c.provider = v);
      },
    );

    final envDropdown = DropdownButtonFormField<String>(
      initialValue: c.environment == 'production' ? 'production' : 'sandbox',
      borderRadius: BorderRadius.circular(14),
      isExpanded: true,
      decoration: dec('Çalışma Ortamı', prefixIcon: Icons.cloud_done_outlined),
      items: const [
        DropdownMenuItem(
          value: 'sandbox',
          child: Text(
            'Sandbox (Test Ortamı)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DropdownMenuItem(
          value: 'production',
          child: Text(
            'Canlı (Production)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      onChanged: (v) {
        if (v != null) {
          setState(() {
            c.environment = v;
            if (c.baseUrlCtrl.text.trim().isEmpty ||
                c.baseUrlCtrl.text.contains('iyzipay.com')) {
              c.baseUrlCtrl.text = v == 'production'
                  ? 'https://api.iyzipay.com'
                  : 'https://sandbox-api.iyzipay.com';
            }
          });
        }
      },
    );

    final apiKeyField = TextField(
      controller: c.apiKeyCtrl,
      decoration: dec(
        'API Key (Üye İşyeri Anahtarı) *',
        hint: 'sandbox-xxxx veya live-xxxx',
        prefixIcon: Icons.vpn_key_outlined,
      ),
    );

    final secretKeyField = TextField(
      controller: c.secretKeyCtrl,
      obscureText: c.obscureSecret,
      decoration: dec(
        'Secret Key (Gizli Anahtar) *',
        hint: '••••••••••••',
        prefixIcon: Icons.lock_outline_rounded,
        suffixIcon: IconButton(
          icon: Icon(
            c.obscureSecret
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 18,
          ),
          onPressed: () => setState(() => c.obscureSecret = !c.obscureSecret),
        ),
      ),
    );

    final baseUrlField = TextField(
      controller: c.baseUrlCtrl,
      decoration: dec(
        'API Sunucu Adresi',
        hint: c.environment == 'production'
            ? 'https://api.iyzipay.com'
            : 'https://sandbox-api.iyzipay.com',
        prefixIcon: Icons.dns_outlined,
      ),
    );

    final subMerchantField = TextField(
      controller: c.subMerchantCtrl,
      decoration: dec(
        'Alt Üye İşyeri Key (Opsiyonel)',
        hint: 'SubMerchant Key',
        prefixIcon: Icons.hub_outlined,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNarrow) ...[
              providerDropdown,
              const SizedBox(height: 12),
              envDropdown,
            ] else
              Row(
                children: [
                  Expanded(child: providerDropdown),
                  const SizedBox(width: 12),
                  Expanded(child: envDropdown),
                ],
              ),
            const SizedBox(height: 12),
            TextField(
              controller: c.titleCtrl,
              decoration: dec(
                'Üye İşyeri / POS Görünen Adı',
                hint: 'Örn: ABC Okulları Mağaza POS veya Kantin İşletmesi POS',
                prefixIcon: Icons.storefront_outlined,
              ),
            ),
            const SizedBox(height: 12),
            if (isNarrow) ...[
              apiKeyField,
              const SizedBox(height: 12),
              secretKeyField,
            ] else
              Row(
                children: [
                  Expanded(child: apiKeyField),
                  const SizedBox(width: 12),
                  Expanded(child: secretKeyField),
                ],
              ),
            const SizedBox(height: 12),
            if (isNarrow) ...[
              baseUrlField,
              const SizedBox(height: 12),
              subMerchantField,
            ] else
              Row(
                children: [
                  Expanded(child: baseUrlField),
                  const SizedBox(width: 12),
                  Expanded(child: subMerchantField),
                ],
              ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: c.allowInstallments,
              onChanged: (v) => setState(() => c.allowInstallments = v),
              title: const Text(
                'Kredi Kartına Taksit Seçeneklerini Aç',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            if (c.allowInstallments)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: PosCredentialProfile.allInstallmentOptions.map((
                  inst,
                ) {
                  final sel = inst == 1 || c.installments.contains(inst);
                  return FilterChip(
                    visualDensity: VisualDensity.compact,
                    selected: sel,
                    label: Text(inst == 1 ? 'Tek Çekim' : '$inst Taksit'),
                    onSelected: inst == 1
                        ? null
                        : (v) => setState(() {
                            if (v) {
                              c.installments.add(inst);
                            } else {
                              c.installments.remove(inst);
                            }
                          }),
                  );
                }).toList(),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: c.noteCtrl,
              decoration: dec(
                'Fiziksel POS Cihazı / Banka / Muhasebe Notu (Opsiyonel)',
                hint: 'Örn: Ziraat Fiziksel POS #2 / Kantin İşletmesi Hesabı',
                prefixIcon: Icons.notes_rounded,
              ),
            ),
          ],
        );
      },
    );
  }
}
