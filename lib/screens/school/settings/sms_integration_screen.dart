import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/sms_settings_model.dart';
import '../../../services/sms_service.dart';
import '../../../services/user_permission_service.dart';

class SmsIntegrationScreen extends StatefulWidget {
  const SmsIntegrationScreen({Key? key}) : super(key: key);

  @override
  State<SmsIntegrationScreen> createState() => _SmsIntegrationScreenState();
}

class _SmsIntegrationScreenState extends State<SmsIntegrationScreen> {
  final _smsService = SmsService();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  String? _schoolId;
  String? _userEmail;

  // Form fields
  SmsProvider _selectedProvider = SmsProvider.netgsm;
  final _apiKeyController = TextEditingController();
  final _apiSecretController = TextEditingController();
  final _originatorController = TextEditingController();
  final _customUrlController = TextEditingController();
  final _testPhoneController = TextEditingController();
  bool _isActive = false;
  bool _showApiKey = false;
  bool _showApiSecret = false;

  // Existing settings
  SmsSettings? _existingSettings;
  String? _testResult;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    _originatorController.dispose();
    _customUrlController.dispose();
    _testPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      _userEmail = user.email;

      final userData = await UserPermissionService.loadUserData();
      final instId = await UserPermissionService.resolveInstitutionId(
        user.email!,
        userData: userData,
      );

      if (instId.isNotEmpty) {
        final schoolQuery = await FirebaseFirestore.instance
            .collection('schools')
            .where('institutionId', isEqualTo: instId)
            .limit(1)
            .get();

        if (schoolQuery.docs.isNotEmpty) {
          _schoolId = schoolQuery.docs.first.id;
          final settings = await _smsService.loadSmsSettings(_schoolId!);
          if (settings != null) {
            _existingSettings = settings;
            _selectedProvider = settings.provider;
            _apiKeyController.text = settings.apiKey;
            _apiSecretController.text = settings.apiSecret;
            _originatorController.text = settings.originator;
            _customUrlController.text = settings.customApiUrl ?? '';
            _isActive = settings.isActive;
          }
        }
      }
    } catch (e) {
      debugPrint('SMS Entegrasyon yüklenirken hata: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_schoolId == null) return;

    setState(() => _isSaving = true);
    try {
      final settings = SmsSettings(
        provider: _selectedProvider,
        apiKey: _apiKeyController.text.trim(),
        apiSecret: _apiSecretController.text.trim(),
        originator: _originatorController.text.trim(),
        customApiUrl: _selectedProvider == SmsProvider.custom
            ? _customUrlController.text.trim()
            : null,
        isActive: _isActive,
        lastTestedAt: _existingSettings?.lastTestedAt,
        lastTestResult: _existingSettings?.lastTestResult,
        updatedBy: _userEmail,
        schoolId: _schoolId,
      );

      await _smsService.saveSmsSettings(_schoolId!, settings, _userEmail ?? '');
      _existingSettings = settings;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS ayarları başarıyla kaydedildi.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kaydetme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testConnection() async {
    if (_testPhoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen test için bir telefon numarası girin.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
    });

    try {
      final settings = SmsSettings(
        provider: _selectedProvider,
        apiKey: _apiKeyController.text.trim(),
        apiSecret: _apiSecretController.text.trim(),
        originator: _originatorController.text.trim(),
        customApiUrl: _selectedProvider == SmsProvider.custom
            ? _customUrlController.text.trim()
            : null,
        isActive: true,
        schoolId: _schoolId,
      );

      final result = await _smsService.testConnection(
        settings,
        _testPhoneController.text.trim(),
      );

      final success = result['success'] as bool? ?? false;

      // Save test result to Firestore if schoolId available
      if (_schoolId != null) {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(_schoolId)
            .set({
          'smsSettings': {
            'lastTestedAt': FieldValue.serverTimestamp(),
            'lastTestResult': success ? 'success' : 'failed',
          }
        }, SetOptions(merge: true));
      }

      setState(() {
        _testSuccess = success;
        _testResult = result['message'] as String? ?? '';
        _isTesting = false;
      });
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = 'Hata: $e';
        _isTesting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'SMS Entegrasyonu',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blueGrey.shade700,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _isSaving ? null : _save,
              backgroundColor: Colors.blueGrey.shade700,
              foregroundColor: Colors.white,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                _isSaving ? 'Kaydediliyor...' : 'Kaydet',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _schoolId == null
              ? Center(
                  child: Text(
                    'Kurum bilgisi bulunamadı.',
                    style: GoogleFonts.inter(color: Colors.grey),
                  ),
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16 : 32,
                    vertical: 24,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildStatusCard(),
                            const SizedBox(height: 24),
                            _buildSettingsCard(),
                            const SizedBox(height: 24),
                            _buildTestCard(),
                            const SizedBox(height: 24),
                            _buildHelpCard(),
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildStatusCard() {
    final hasSettings = _existingSettings != null;
    final isActive = _existingSettings?.isActive ?? false;
    final lastTest = _existingSettings?.lastTestResult;
    final lastTestDate = _existingSettings?.lastTestedAt;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? Colors.green.shade200
              : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: hasSettings && isActive
                  ? Colors.green.shade50
                  : Colors.grey.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasSettings && isActive
                  ? Icons.check_circle_rounded
                  : Icons.cancel_rounded,
              color: hasSettings && isActive
                  ? Colors.green.shade600
                  : Colors.grey.shade400,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasSettings && isActive
                      ? 'Aktif – ${_existingSettings!.providerName}'
                      : hasSettings
                          ? 'Yapılandırıldı – Devre Dışı'
                          : 'Yapılandırılmamış',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: hasSettings && isActive
                        ? Colors.green.shade700
                        : Colors.grey.shade600,
                  ),
                ),
                if (lastTestDate != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Son test: ${lastTest == 'success' ? '✅' : '❌'} '
                    '${_formatDate(lastTestDate)}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.blueGrey.shade400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: _isActive,
            activeColor: Colors.blueGrey.shade700,
            onChanged: (val) => setState(() => _isActive = val),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.settings_rounded,
                    color: Colors.blueGrey.shade700, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'API Ayarları',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Provider Dropdown
          Text('SMS Sağlayıcısı',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey.shade700)),
          const SizedBox(height: 8),
          DropdownButtonFormField<SmsProvider>(
            value: _selectedProvider,
            decoration: _inputDecoration('Sağlayıcı seçin'),
            items: SmsProvider.values.map((p) {
              final names = {
                SmsProvider.netgsm: 'Netgsm',
                SmsProvider.iletisim360: 'İletişim360',
                SmsProvider.mutlucell: 'Mutlucell',
                SmsProvider.custom: 'Özel API',
              };
              return DropdownMenuItem(
                value: p,
                child: Text(names[p] ?? p.name),
              );
            }).toList(),
            onChanged: (val) => setState(() => _selectedProvider = val!),
          ),

          const SizedBox(height: 20),

          // API Key
          Text('API Kullanıcı Kodu',
              style: _labelStyle()),
          const SizedBox(height: 8),
          TextFormField(
            controller: _apiKeyController,
            obscureText: !_showApiKey,
            decoration: _inputDecoration('Kullanıcı kodu / API Key').copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _showApiKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: Colors.blueGrey.shade400,
                  size: 20,
                ),
                onPressed: () => setState(() => _showApiKey = !_showApiKey),
              ),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Bu alan zorunludur' : null,
          ),

          const SizedBox(height: 20),

          // API Secret
          Text('API Şifresi', style: _labelStyle()),
          const SizedBox(height: 8),
          TextFormField(
            controller: _apiSecretController,
            obscureText: !_showApiSecret,
            decoration: _inputDecoration('Şifre / API Secret').copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _showApiSecret
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colors.blueGrey.shade400,
                  size: 20,
                ),
                onPressed: () => setState(() => _showApiSecret = !_showApiSecret),
              ),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Bu alan zorunludur' : null,
          ),

          const SizedBox(height: 20),

          // Originator
          Text('SMS Başlığı (Gönderici Adı)', style: _labelStyle()),
          const SizedBox(height: 4),
          Text(
            'Netgsm hesabınızda onaylı olan başlığı girin (maks. 11 karakter)',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.blueGrey.shade400),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _originatorController,
            maxLength: 11,
            decoration: _inputDecoration('Örn: OKULUM'),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Bu alan zorunludur';
              if (v.trim().length > 11) return 'En fazla 11 karakter';
              return null;
            },
          ),

          // Custom API URL (only for custom provider)
          if (_selectedProvider == SmsProvider.custom) ...[
            const SizedBox(height: 20),
            Text('API URL', style: _labelStyle()),
            const SizedBox(height: 8),
            TextFormField(
              controller: _customUrlController,
              decoration: _inputDecoration('https://api.sağlayıcı.com/send'),
              validator: (v) {
                if (_selectedProvider == SmsProvider.custom) {
                  if (v == null || v.trim().isEmpty) return 'Özel API için URL zorunludur';
                }
                return null;
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTestCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.wifi_tethering_rounded,
                    color: Colors.teal.shade700, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Bağlantı Testi',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ayarlarınızı kaydetmeden önce gerçek bir SMS göndererek doğrulayın.',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.blueGrey.shade500),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _testPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration('+905xxxxxxxxx'),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                icon: _isTesting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_isTesting ? 'Gönderiliyor...' : 'Test Et'),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 16),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (_testSuccess ?? false)
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (_testSuccess ?? false)
                      ? Colors.green.shade200
                      : Colors.red.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    (_testSuccess ?? false)
                        ? Icons.check_circle_rounded
                        : Icons.error_rounded,
                    color: (_testSuccess ?? false)
                        ? Colors.green.shade600
                        : Colors.red.shade600,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: (_testSuccess ?? false)
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHelpCard() {
    final providerHelp = {
      SmsProvider.netgsm: {
        'title': 'Netgsm API Bilgileri',
        'endpoint': 'https://api.netgsm.com.tr/sms/send/get',
        'notes': [
          'Netgsm hesabınıza giriş yapın → API ayarları',
          'Kullanıcı kodu: Netgsm kullanıcı adınız',
          'Şifre: Netgsm şifreniz',
          'SMS Başlığı: Netgsm\'de onaylı gönderici adınız',
        ],
      },
      SmsProvider.iletisim360: {
        'title': 'İletişim360 API Bilgileri',
        'endpoint': 'https://api.iletisim360.com/v1/sms/send',
        'notes': [
          'İletişim360 panelinden API Key alın',
          'SMS Başlığı: Panelde tanımlı originator',
        ],
      },
      SmsProvider.mutlucell: {
        'title': 'Mutlucell API Bilgileri',
        'endpoint': 'https://api.mutlucell.com/api-utf8/sms-add',
        'notes': [
          'Mutlucell kullanıcı adı ve şifrenizi kullanın',
          'SMS Başlığı: Mutlucell\'de onaylı başlık',
        ],
      },
      SmsProvider.custom: {
        'title': 'Özel API',
        'endpoint': 'Kendi API URL\'nizi girin',
        'notes': [
          'API URL: Sağlayıcınızın SMS gönderim endpoint\'i',
          'POST isteği ile {apiKey, apiSecret, to, message, from} gönderilir',
        ],
      },
    };

    final help = providerHelp[_selectedProvider]!;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: Colors.blueGrey.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                help['title'] as String,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.blueGrey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Endpoint: ${help['endpoint']}',
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...(help['notes'] as List<String>).map((note) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.only(top: 6, right: 8),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade400,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        note,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  TextStyle _labelStyle() => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.blueGrey.shade700,
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.blueGrey.shade400, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')} '
        '${_monthName(dt.month)} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _monthName(int month) {
    const months = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    return months[month - 1];
  }
}
