import 'dart:js' as js;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/assessment/external_exam_model.dart';
import '../../models/assessment/external_exam_registration_model.dart';
import '../../services/external_exam_service.dart';
import '../../constants/turkey_address_data.dart';
import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';

enum PortalState { landing, form, ticket }

/// Public-facing premium registration portal — accessible without login
class ExternalExamRegisterScreen extends StatefulWidget {
  final String? examId;

  const ExternalExamRegisterScreen({Key? key, this.examId}) : super(key: key);

  @override
  State<ExternalExamRegisterScreen> createState() => _ExternalExamRegisterScreenState();
}

class _ExternalExamRegisterScreenState extends State<ExternalExamRegisterScreen> {
  final ExternalExamService _service = ExternalExamService();
  final _formKey = GlobalKey<FormState>();
  
  // Navigation & Portal states
  PortalState _portalState = PortalState.landing;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _submitted = false;
  bool _isEditing = false;
  
  String? _editingRegId;
  String _examId = '';
  ExternalExam? _exam;
  String? _schoolName;
  String? _errorMessage;
  ExternalExamRegistration? _currentTicket;
  List<String> _availableSchools = [];
  String? _registrationId;
  final GlobalKey _ticketKey = GlobalKey();

  // Search controllers
  final _searchTcController = TextEditingController();

  // Form controllers
  final _studentNameController = TextEditingController();
  final _studentSurnameController = TextEditingController();
  final _studentTcController = TextEditingController();
  final _currentSchoolController = TextEditingController();
  final _parentNameController = TextEditingController();
  final _parentSurnameController = TextEditingController();
  final _parentPhoneController = TextEditingController();
  final _parentEmailController = TextEditingController();
  final _cityController = TextEditingController();
  final _districtController = TextEditingController();

  String? _selectedGrade;
  String? _selectedSessionId;

  // Address Dropdown states
  String? _selectedCity;
  String? _selectedDistrict;

  // Premium design branding colors
  static const _primaryColor = Color(0xFFE65100); // Sleek Deep Amber
  static const _accentColor = Color(0xFF1E3A8A); // Royal Navy
  static const _tealColor = Color(0xFF0D9488); // Teal for ticket print
  static const _cardBgColor = Colors.white;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadExam();
      }
    });
  }

  @override
  void dispose() {
    _searchTcController.dispose();
    _studentNameController.dispose();
    _studentSurnameController.dispose();
    _studentTcController.dispose();
    _currentSchoolController.dispose();
    _parentNameController.dispose();
    _parentSurnameController.dispose();
    _parentPhoneController.dispose();
    _parentEmailController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    super.dispose();
  }

  String _getExamId() {
    if (widget.examId != null && widget.examId!.isNotEmpty) {
      return widget.examId!;
    }
    if (Uri.base.queryParameters.containsKey('examId')) {
      return Uri.base.queryParameters['examId'] ?? '';
    }
    try {
      final fragment = Uri.base.fragment;
      if (fragment.contains('?')) {
        final queryStr = fragment.split('?').last;
        final params = Uri.splitQueryString(queryStr);
        return params['examId'] ?? '';
      }
    } catch (e) {
      debugPrint('Error parsing fragment query: $e');
    }
    return '';
  }

  Future<void> _loadExam() async {
    final parsedId = _getExamId();
    _examId = parsedId;
    if (parsedId.isEmpty) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Sınav bağlantısı geçersiz (Sınav ID bulunamadı).';
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final exam = await _service.getExternalExamById(parsedId);
      if (exam == null || !exam.isActive) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Bu sınav bulunamadı veya başvuruya kapalı.';
            _isLoading = false;
          });
        }
        return;
      }
      
      // Fetch school name from root schools collection
      String? fetchedSchoolName;
      try {
        final schoolDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(exam.schoolId)
            .get();
        if (schoolDoc.exists) {
          fetchedSchoolName = schoolDoc.data()?['schoolName'] as String?;
        }
      } catch (e) {
        debugPrint('School name fetch error: $e');
      }

      // Fetch autocomplete schools
      final availableSchools = await _service.getExternalSchools();

      if (mounted) {
        setState(() {
          _exam = exam;
          _schoolName = fetchedSchoolName;
          _availableSchools = availableSchools;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Sınav bilgileri yüklenirken hata oluştu: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Official Turkish Identification Number Validation Algorithm
  bool _validateTcNo(String tc) {
    if (tc.length != 11) return false;
    if (tc.startsWith('0')) return false;

    try {
      List<int> digits = tc.split('').map((e) => int.parse(e)).toList();

      int oddSum = digits[0] + digits[2] + digits[4] + digits[6] + digits[8];
      int evenSum = digits[1] + digits[3] + digits[5] + digits[7];

      int tenthDigit = ((oddSum * 7) - evenSum) % 10;
      if (digits[9] != tenthDigit) return false;

      int eleventhDigit = digits.take(10).reduce((a, b) => a + b) % 10;
      if (digits[10] != eleventhDigit) return false;

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _lookupAndStartEditing(String tcNo) async {
    if (!_validateTcNo(tcNo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen geçerli bir T.C. Kimlik Numarası girin.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final reg = await _service.getRegistrationByTc(_examId, tcNo);
      if (reg == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bu T.C. Kimlik Numarası ile aktif bir sınav başvurusu bulunamadı.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      // Prefill all inputs
      _studentNameController.text = reg.studentName;
      _studentSurnameController.text = reg.studentSurname;
      _studentTcController.text = reg.studentTcNo;
      _currentSchoolController.text = reg.currentSchool;
      _parentNameController.text = reg.parentName;
      _parentSurnameController.text = reg.parentSurname;
      _parentPhoneController.text = reg.parentPhone;
      _parentEmailController.text = reg.parentEmail ?? '';
      _cityController.text = reg.city;
      _districtController.text = reg.district;
      _selectedGrade = reg.gradeLevel;
      _selectedSessionId = reg.sessionId;

      // Map dynamic Address Dropdowns
      final upperCity = reg.city.toUpperCase();
      if (TurkeyAddressData.cities.contains(upperCity)) {
        _selectedCity = upperCity;
        final districts = TurkeyAddressData.getDistricts(upperCity);
        final upperDistrict = reg.district.toUpperCase();
        if (districts.contains(upperDistrict)) {
          _selectedDistrict = upperDistrict;
        }
      }

      if (mounted) {
        setState(() {
          _isEditing = true;
          _editingRegId = reg.id;
          _portalState = PortalState.form;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veri yükleme hatası: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _lookupAndShowTicket(String tcNo) async {
    if (!_validateTcNo(tcNo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen geçerli bir T.C. Kimlik Numarası girin.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final reg = await _service.getRegistrationByTc(_examId, tcNo);
      if (reg == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bu T.C. Kimlik Numarası ile aktif bir sınav başvurusu bulunamadı.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      if (mounted) {
        setState(() {
          _currentTicket = reg;
          _portalState = PortalState.ticket;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sınav belgesi yükleme hatası: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedGrade == null || _selectedSessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen sınıf ve seans seçin.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (mounted) {
      setState(() => _isSubmitting = true);
    }

    try {
      // Build Registration Object
      final reg = ExternalExamRegistration(
        id: _editingRegId,
        examId: _examId,
        institutionId: _exam!.institutionId,
        sessionId: _selectedSessionId!,
        studentName: _studentNameController.text.trim(),
        studentSurname: _studentSurnameController.text.trim(),
        studentTcNo: _studentTcController.text.trim(),
        gradeLevel: _selectedGrade!,
        parentName: _parentNameController.text.trim(),
        parentSurname: _parentSurnameController.text.trim(),
        parentPhone: _parentPhoneController.text.trim(),
        parentEmail: _parentEmailController.text.trim().isEmpty
            ? null
            : _parentEmailController.text.trim(),
        city: _cityController.text.trim(),
        district: _districtController.text.trim(),
        currentSchool: _currentSchoolController.text.trim(),
        registrationSource: RegistrationSource.online,
        status: RegistrationStatus.confirmed,
        createdAt: DateTime.now(),
      );

      // Save school for autocomplete (both create and edit modes)
      if (_currentSchoolController.text.trim().isNotEmpty) {
        await _service.addExternalSchool(_currentSchoolController.text.trim());
      }

      if (_isEditing && _editingRegId != null) {
        // Edit Mode: Update existing Firestore record
        await _service.updateRegistration(_editingRegId!, reg);
        if (mounted) {
          setState(() {
            _submitted = true;
            _registrationId = _editingRegId;
            _isSubmitting = false;
          });
        }
      } else {
        // Create Mode: Check duplicates
        final isDuplicate = await _service.checkDuplicateRegistration(
          _examId,
          _studentTcController.text.trim(),
        );

        if (isDuplicate) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bu T.C. kimlik numarası ile zaten başvuru yapılmış.'),
                backgroundColor: Colors.red,
              ),
            );
            setState(() => _isSubmitting = false);
          }
          return;
        }

        // Quota check
        final currentCount = await _service.getSessionRegistrationCount(
          _examId,
          _selectedSessionId!,
          _selectedGrade!,
        );

        final session = _exam!.applicationSessions
            .firstWhere((s) => s.id == _selectedSessionId!);
        final quota = session.quotaForGrade(_selectedGrade!);

        if (quota > 0 && currentCount >= quota) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Seçilen seans ve sınıf için kontenjan dolmuştur.'),
                backgroundColor: Colors.red,
              ),
            );
            setState(() => _isSubmitting = false);
          }
          return;
        }

        final regId = await _service.addRegistration(reg);

        if (mounted) {
          setState(() {
            _submitted = true;
            _registrationId = regId;
            _isSubmitting = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kayıt hatası: $e')),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _triggerPrint() async {
    try {
      final boundary = _ticketKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Belge yüklenemedi. Lütfen tekrar deneyin.')));
        }
        return;
      }
      
      // Use pixelRatio: 2.0 for a balance between speed and quality. 3.0 or higher makes PNG encoding very slow on Flutter Web.
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      
      final pngBytes = byteData.buffer.asUint8List();
      final base64Image = base64Encode(pngBytes);
      
      final printWindow = js.context.callMethod('open', ['', 'PrintTicket']);
      if (printWindow != null) {
        printWindow.callMethod('document.write', ['''
          <!DOCTYPE html>
          <html>
            <head>
              <title>Sınav Giriş Belgesi</title>
              <style>
                @media print {
                  @page { margin: 0; }
                  body { margin: 0; padding: 2cm; display: flex; justify-content: center; }
                  img { box-shadow: none !important; }
                }
                body { margin: 0; padding: 20px; display: flex; justify-content: center; background: #f0f0f0; }
                img { max-width: 100%; height: auto; box-shadow: 0 4px 12px rgba(0,0,0,0.1); border-radius: 12px; }
              </style>
            </head>
            <body onload="setTimeout(function(){ window.print(); window.close(); }, 200);">
              <img src="data:image/png;base64,$base64Image" style="width: 100%; max-width: 750px;" />
            </body>
          </html>
        ''']);
        printWindow.callMethod('document.close');
      }
    } catch (e) {
      debugPrint('Print error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Baskı işlemi sırasında bir hata oluştu.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Light beautiful gray/blue base
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : _errorMessage != null
              ? _buildErrorState()
              : _submitted
                  ? _buildSuccessState()
                  : _buildPortalBody(isMobile),
    );
  }

  Widget _buildPortalBody(bool isMobile) {
    switch (_portalState) {
      case PortalState.landing:
        return _buildLandingView(isMobile);
      case PortalState.form:
        return _buildFormView(isMobile);
      case PortalState.ticket:
        return _buildTicketView(isMobile);
    }
  }

  Widget _buildLandingView(bool isMobile) {
    final isCompact = MediaQuery.of(context).size.width < 650;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // Premium Hero Header
          _buildPortalHeroHeader(isMobile),

          // Portal Options Layout
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 32,
              vertical: 40,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  children: [
                    Text(
                      'Lütfen yapmak istediğiniz işlemi seçin',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 18 : 22,
                        fontWeight: FontWeight.bold,
                        color: _accentColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sınav başvurularınızı kolayca yönetebilir ve giriş belgenizi yazdırabilirsiniz.',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.blueGrey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 36),

                    // Regulation button (kept at top)
                    _buildWideRegulationButton(isMobile),

                    const SizedBox(height: 24),

                    // Option cards
                    Builder(
                      builder: (context) {
                        final cards = <Widget>[];

                        if (_exam!.showRegister) {
                          cards.add(
                            _buildOptionCard(
                              title: 'Yeni Başvuru Yap',
                              description: 'Sınav kaydınızı saniyeler içerisinde kolayca oluşturun.',
                              icon: Icons.person_add_rounded,
                              gradientColors: [const Color(0xFFFF9800), const Color(0xFFF57C00)],
                              buttonText: 'Başvuru Ekranına Git',
                              isStretched: !isCompact,
                              onTap: () {
                                setState(() {
                                  _isEditing = false;
                                  _editingRegId = null;
                                  _studentNameController.clear();
                                  _studentSurnameController.clear();
                                  _studentTcController.clear();
                                  _currentSchoolController.clear();
                                  _parentNameController.clear();
                                  _parentSurnameController.clear();
                                  _parentPhoneController.clear();
                                  _parentEmailController.clear();
                                  _cityController.clear();
                                  _districtController.clear();
                                  _selectedGrade = null;
                                  _selectedSessionId = null;
                                  _selectedCity = null;
                                  _selectedDistrict = null;
                                  _portalState = PortalState.form;
                                });
                              },
                            ),
                          );
                        }

                        if (_exam!.showEdit) {
                          cards.add(
                            _buildOptionCard(
                              title: 'Başvurumu Düzenle',
                              description: 'Daha önceden yapmış olduğunuz başvuru bilgilerinizi güncelleyin.',
                              icon: Icons.edit_note_rounded,
                              gradientColors: [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
                              buttonText: 'Başvuruyu Güncelle',
                              isStretched: !isCompact,
                              onTap: () => _showTcLookupDialog(isEdit: true),
                            ),
                          );
                        }

                        if (_exam!.showTicket) {
                          cards.add(
                            _buildOptionCard(
                              title: 'Sınav Giriş Belgesi',
                              description: 'Sınav salonunuzu öğrenin ve belgenizi yazdırıp indirin.',
                              icon: Icons.local_activity_rounded,
                              gradientColors: [const Color(0xFF10B981), const Color(0xFF047857)],
                              buttonText: 'Belgeyi Sorgula',
                              isStretched: !isCompact,
                              onTap: () => _showTcLookupDialog(isEdit: false),
                            ),
                          );
                        }

                        if (cards.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                'Bu sınav için şu anda aktif bir işlem bulunmamaktadır.',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }

                        if (isCompact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 16), child: c)).toList(),
                          );
                        } else {
                          // Row - Equal Width Cards
                          return IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: cards.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final widget = entry.value;
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: idx == 0 ? 0 : 8,
                                      right: idx == cards.length - 1 ? 0 : 8,
                                    ),
                                    child: widget,
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        }
                      },
                    ),

                    const SizedBox(height: 24),
                    // Results button placed after cards
                    _buildWideResultsButton(isMobile),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideRegulationButton(bool isMobile) {
    if (_exam == null) return const SizedBox.shrink();
    final showRegButton = _exam!.showRegulation &&
        _exam!.regulationUrl != null &&
        _exam!.regulationUrl!.isNotEmpty;
    if (!showRegButton) return const SizedBox.shrink();
    return _buildWideButton(
      title: 'SINAV YÖNERGESİ VE KILAVUZU',
      subtitle: 'Sınav kuralları, katılım şartları ve detayları incelemek için tıklayınız.',
      icon: Icons.menu_book_rounded,
      gradientColors: [const Color(0xFF1E3A8A), const Color(0xFF3B82F6)],
      onTap: () {
        if (_exam!.regulationUrl != null && _exam!.regulationUrl!.isNotEmpty) {
          try {
            js.context.callMethod('open', [_exam!.regulationUrl]);
          } catch (e) {
            debugPrint('URL açma hatası: $e');
          }
        }
      },
    );
  }

  Widget _buildWideResultsButton(bool isMobile) {
    if (_exam == null) return const SizedBox.shrink();
    final showResButton = _exam!.showResults;
    if (!showResButton) return const SizedBox.shrink();
    return _buildWideButton(
      title: 'SINAV SONUÇLARI SORGULAMA',
      subtitle: 'Sınav sonuçları, puan durumları ve burs derecelerini öğrenmek için tıklayınız.',
      icon: Icons.workspace_premium_rounded,
      gradientColors: [const Color(0xFF0D9488), const Color(0xFF0F766E)],
      onTap: () {
        final now = DateTime.now();
        final publishDate = _exam!.regulationPublishDate;
        final isPublished = publishDate != null && now.isAfter(publishDate);
        if (isPublished) {
          showDialog(
            context: context,
            builder: (ctx) => _buildPremiumDialog(
              title: 'Sınav Sonuçları',
              content: Text(
                'Sınav sonuçları açıklanmıştır! Sonuç belgenizi almak ve kayıt işlemleri hakkında detaylı bilgi edinmek için lütfen kurumumuz ile iletişime geçiniz.',
                style: GoogleFonts.inter(height: 1.5),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Kapat', style: GoogleFonts.inter(color: _accentColor, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        } else {
          String msg = 'Sınav sonuçları henüz açıklanmamıştır.';
          if (publishDate != null) {
            final dateStr = "${publishDate.day.toString().padLeft(2, '0')}.${publishDate.month.toString().padLeft(2, '0')}.${publishDate.year}";
            msg += '\n\nSonuçlar $dateStr tarihinde açıklanacaktır.';
          } else {
            msg += '\n\nLütfen daha sonra tekrar kontrol ediniz veya kurumumuzla iletişime geçiniz.';
          }
          showDialog(
            context: context,
            builder: (ctx) => _buildPremiumDialog(
              title: 'Sonuçlar Açıklanmadı',
              content: Text(msg, style: GoogleFonts.inter(height: 1.5)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Tamam', style: GoogleFonts.inter(color: _accentColor, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  // Helper for premium styled dialogs
  Widget _buildPremiumDialog({required String title, required Widget content, required List<Widget> actions}) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_accentColor, Color(0xFF111827)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: content,
          ),
          ButtonBar(
            alignment: MainAxisAlignment.end,
            children: actions,
          ),
        ],
      ), // closes Column
      ), // closes ConstrainedBox
    ); // closes Dialog
  }

  // Generic wide button builder used by all premium cards
  Widget _buildWideButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradientColors.last.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  


  Widget _buildPortalHeroHeader(bool isMobile) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_accentColor, Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 48,
        vertical: isMobile ? 40 : 64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_schoolName != null && _schoolName!.isNotEmpty) ...[
                Text(
                  _schoolName!.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 14 : 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.orange.shade400,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.emoji_events_rounded, color: Colors.orange, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      _exam?.examTypeName ?? 'Dış Katılımlı Sınav',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _exam?.title ?? 'Sınav Kayıt Portalı',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 26 : 38,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Lütfen bu portal aracılığıyla başvurunuzu oluşturun, düzenleyin veya yerleştiğiniz salon kodunu öğrenerek giriş belgenizi indirin.',
                style: GoogleFonts.inter(
                  fontSize: isMobile ? 13 : 15,
                  color: Colors.grey.shade400,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required String title,
    required String description,
    required IconData icon,
    required List<Color> gradientColors,
    required String buttonText,
    required VoidCallback onTap,
    bool isStretched = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.blueGrey.shade600,
              height: 1.4,
            ),
          ),
          // Adjust spacing to reduce cramped layout on edit card
          const SizedBox(height: 12),
          if (isStretched) const Spacer() else const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: gradientColors.last,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Text(
                buttonText,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTcLookupDialog({required bool isEdit}) {
    _searchTcController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return _buildPremiumDialog(
          title: isEdit ? 'Başvuru Bilgilerini Sorgula' : 'Giriş Belgesi Sorgula',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sistemde kayıtlı olan T.C. Kimlik Numaranızı girin:',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchTcController,
                maxLength: 11,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'T.C. Kimlik No',
                  counterText: '',
                  prefixIcon: const Icon(Icons.badge_rounded, color: _primaryColor),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('İptal', style: GoogleFonts.inter(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                final tc = _searchTcController.text.trim();
                Navigator.pop(context);
                if (isEdit) {
                  _lookupAndStartEditing(tc);
                } else {
                  _lookupAndShowTicket(tc);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Sorgula', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFormView(bool isMobile) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
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
                // Top Header Back Navigation Row
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: _accentColor),
                      onPressed: () {
                        setState(() {
                          _portalState = PortalState.landing;
                          _isEditing = false;
                        });
                      },
                    ),
                    Text(
                      'Ana Sayfaya Dön',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _accentColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Branded Title Banner
                _buildExamInfoBanner(),
                const SizedBox(height: 24),

                // 1. Session & Grade Selector Card
                _buildCard(
                  title: 'Oturum ve Sınıf Seçimi',
                  icon: Icons.calendar_today_rounded,
                  children: [
                    _buildSectionLabel('Mevcut Okuduğunuz Sınıf Seviyesi'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _exam!.gradeLevels.map((g) {
                        final sel = _selectedGrade == g;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedGrade = g),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: sel ? _primaryColor : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sel ? _primaryColor : Colors.grey.shade200,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                g == 'Mezun' ? 'Mezun' : g,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  color: sel ? Colors.white : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    _buildSectionLabel('Sınav Seansı'),
                    const SizedBox(height: 8),
                    if (_selectedGrade == null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Lütfen önce sınıf seviyesini seçin.',
                          style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13),
                        ),
                      )
                    else if (_exam!.applicationSessions.where((s) => s.gradeLevels.contains(_selectedGrade)).isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Seçili sınıf için uygun seans bulunamadı.',
                          style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13),
                        ),
                      )
                    else
                      ...(_exam!.applicationSessions.where((s) => s.gradeLevels.contains(_selectedGrade))).map((session) {
                        final sel = _selectedSessionId == session.id;
                        final grade = _selectedGrade;
                        final quota = grade != null ? session.quotaForGrade(grade) : 0;
                        final canApply = grade == null || session.gradeLevels.contains(grade);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: canApply
                                ? () => setState(() => _selectedSessionId = session.id)
                                : null,
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: !canApply
                                    ? Colors.grey.shade50
                                    : sel
                                        ? Colors.orange.shade50
                                        : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: sel ? _primaryColor : Colors.grey.shade200,
                                  width: sel ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 18,
                                    color: !canApply
                                        ? Colors.grey.shade300
                                        : sel
                                            ? _primaryColor
                                            : Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${session.sessionDate.day}.${session.sessionDate.month}.${session.sessionDate.year} · ${session.displayTime}',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: !canApply
                                                ? Colors.grey.shade400
                                                : const Color(0xFF1E293B),
                                          ),
                                        ),
                                        if (grade != null && quota > 0)
                                          Text(
                                            '$grade. Sınıf – Kontenjan: $quota kişi',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        if (!canApply)
                                          Text(
                                            'Bu seans seçilen sınıf için uygun değil',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: Colors.red.shade400,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (sel)
                                    const Icon(Icons.check_circle_rounded,
                                        color: _primaryColor, size: 18),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. Student Info Card
                _buildCard(
                  title: 'Öğrenci Bilgileri',
                  icon: Icons.person_rounded,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _studentNameController,
                            label: 'Ad *',
                            hint: 'Adı',
                            validator: (v) => v == null || v.isEmpty ? 'Öğrenci adı zorunludur' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _studentSurnameController,
                            label: 'Soyad *',
                            hint: 'Soyadı',
                            validator: (v) => v == null || v.isEmpty ? 'Öğrenci soyadı zorunludur' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _studentTcController,
                      label: 'T.C. Kimlik Numarası *',
                      hint: '11 haneli T.C.',
                      keyboardType: TextInputType.number,
                      maxLength: 11,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'T.C. Kimlik Numarası zorunludur';
                        if (v.length != 11) return '11 hane olmalıdır';
                        if (!_validateTcNo(v)) return 'Geçersiz T.C. Kimlik Numarası';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildSchoolAutocompleteField(),
                  ],
                ),
                const SizedBox(height: 16),

                // 3. Parent Info Card
                _buildCard(
                  title: 'Veli Bilgileri',
                  icon: Icons.family_restroom_rounded,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _parentNameController,
                            label: 'Veli Adı *',
                            hint: 'Veli Adı',
                            validator: (v) => v == null || v.isEmpty ? 'Veli adı zorunludur' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _parentSurnameController,
                            label: 'Veli Soyadı *',
                            hint: 'Veli Soyadı',
                            validator: (v) => v == null || v.isEmpty ? 'Veli soyadı zorunludur' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _parentPhoneController,
                      label: 'Veli Telefonu *',
                      hint: 'Örn: 05xxxxxxxxx',
                      keyboardType: TextInputType.phone,
                      maxLength: 11,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => v == null || v.isEmpty ? 'Veli telefonu zorunludur' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _parentEmailController,
                      label: 'Veli E-posta (Opsiyonel)',
                      hint: 'veli@mail.com',
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 4. Address Details via Custom Searchable Selectors
                _buildCard(
                  title: 'Adres Bilgileri',
                  icon: Icons.location_on_rounded,
                  children: [
                    _buildSearchableSelectorField(
                      label: 'İl *',
                      value: _selectedCity,
                      hint: 'Şehir seçiniz',
                      validator: (val) => val == null ? 'Lütfen şehir seçin' : null,
                      onTap: () => _showCitySelectDialog(),
                    ),
                    const SizedBox(height: 16),
                    _buildSearchableSelectorField(
                      label: 'İlçe *',
                      value: _selectedDistrict,
                      hint: _selectedCity == null ? 'Önce şehir seçiniz' : 'İlçe seçiniz',
                      validator: (val) => val == null ? 'Lütfen ilçe seçin' : null,
                      onTap: _selectedCity == null
                          ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Lütfen önce bir şehir seçin.'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          : () => _showDistrictSelectDialog(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Form Submit Action
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isEditing ? _accentColor : _primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _isEditing ? 'Bilgileri Güncelle ve Kaydet' : 'Başvuruyu Tamamla',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCitySelectDialog() {
    _showSearchableSelectDialog(
      title: 'Şehir Seçiniz',
      items: TurkeyAddressData.cities,
      currentValue: _selectedCity,
      onSelected: (val) {
        setState(() {
          _selectedCity = val;
          _cityController.text = val;
          _selectedDistrict = null;
          _districtController.text = '';
        });
      },
    );
  }

  void _showDistrictSelectDialog() {
    if (_selectedCity == null) return;
    _showSearchableSelectDialog(
      title: 'İlçe Seçiniz',
      items: TurkeyAddressData.getDistricts(_selectedCity!),
      currentValue: _selectedDistrict,
      onSelected: (val) {
        setState(() {
          _selectedDistrict = val;
          _districtController.text = val;
        });
      },
    );
  }

  Widget _buildTicketView(bool isMobile) {
    if (_currentTicket == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 32,
        vertical: 32,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            children: [
              // Ticket Header Back Navigation Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _portalState = PortalState.landing;
                      });
                    },
                    icon: const Icon(Icons.arrow_back_rounded, color: _accentColor),
                    label: Text(
                      'Ana Sayfa',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: _accentColor),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _triggerPrint,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _tealColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.print_rounded, size: 16),
                    label: Text(
                      'Yazdır / PDF İndir',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // The Printable Ticket Card
              RepaintBoundary(
                key: _ticketKey,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade200, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top header block of the ticket
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_schoolName != null && _schoolName!.isNotEmpty) ...[
                                Text(
                                  _schoolName!.toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.grey.shade600,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 4),
                              ],
                              Text(
                                _exam?.title.toUpperCase() ?? 'DIŞ KATILIMLI SINAV',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: _accentColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'SINAV GİRİŞ BELGESİ',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: _primaryColor,
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: QrImageView(
                            data: _currentTicket!.id ?? _currentTicket!.studentTcNo,
                            size: 80,
                            foregroundColor: _accentColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(thickness: 1.5),
                    const SizedBox(height: 16),

                    // Student details layout
                    Text(
                      'ADAY BİLGİLERİ',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade500,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildTicketRow('Adı Soyadı:', '${_currentTicket!.studentName.toUpperCase()} ${_currentTicket!.studentSurname.toUpperCase()}'),
                    _buildTicketRow('T.C. Kimlik No:', _currentTicket!.studentTcNo),
                    _buildTicketRow('Sınıf Seviyesi:', '${_currentTicket!.gradeLevel}. Sınıf'),
                    _buildTicketRow('Mevcut Okuduğu Okul:', _currentTicket!.currentSchool),
                    const SizedBox(height: 24),
                    const Divider(thickness: 1.5),
                    const SizedBox(height: 16),

                    // Salon and seating placement details
                    Text(
                      'SALON VE OTURUM BİLGİLERİ',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade500,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Find and map session time
                    Builder(
                      builder: (context) {
                        final session = _exam?.applicationSessions
                            .firstWhere((s) => s.id == _currentTicket!.sessionId,
                                orElse: () => ApplicationSession(
                                      id: '',
                                      sessionDate: DateTime.now(),
                                      startTime: '',
                                      endTime: '',
                                      gradeLevels: [],
                                      gradeLevelQuotas: {},
                                    ));
                        final dateStr = session != null
                            ? '${session.sessionDate.day}.${session.sessionDate.month}.${session.sessionDate.year}'
                            : '-';
                        final timeStr = session != null
                            ? '${session.startTimeForGrade(_currentTicket!.gradeLevel)} – ${session.endTimeForGrade(_currentTicket!.gradeLevel)}'
                            : '-';

                        return Column(
                          children: [
                            _buildTicketRow('Sınav Tarihi:', dateStr),
                            _buildTicketRow('Sınav Saati:', timeStr),
                          ],
                        );
                      },
                    ),

                    _buildTicketRow('Sınav Salonu:', _currentTicket!.assignedRoomName ?? 'Planlanıyor (Daha Sonra Sorgulayın)'),
                    _buildTicketRow('Sıra Numarası:', _currentTicket!.seatNumber != null ? '${_currentTicket!.seatNumber}' : 'Planlanıyor'),
                    _buildTicketRow('Giriş Belge Kodu:', _currentTicket!.examEntryCode ?? 'Atanıyor'),

                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Adayların sınav başlangıç saatinden en az 15 dakika önce sınav salonunda hazır bulunmaları gerekmektedir. Yanınızda T.C. Kimlik Kartı ve bu giriş belgesini bulundurunuz.',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.blueGrey.shade700,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ), // Container end
            ), // RepaintBoundary end
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTicketRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 20),
            Text(
              _errorMessage!,
              style: GoogleFonts.inter(fontSize: 16, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, size: 44, color: Colors.green),
            ),
            const SizedBox(height: 24),
            Text(
              _isEditing ? 'Başvurunuz Güncellendi!' : 'Başvurunuz Alındı!',
              style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _isEditing
                  ? 'Sınav başvuru bilgileriniz başarıyla güncellenmiştir.'
                  : 'Başvurunuz başarıyla kaydedilmiştir. Giriş belgenizi sorgulayabilirsiniz.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _submitted = false;
                  _registrationId = null;
                  _isEditing = false;
                  _portalState = PortalState.landing;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'Ana Sayfaya Dön',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardBgColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: _primaryColor),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildExamInfoBanner() {
    if (_exam == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF8F00), Color(0xFFF57C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_schoolName != null && _schoolName!.isNotEmpty) ...[
                  Text(
                    _schoolName!.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withOpacity(0.9),
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  _exam!.title,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _exam!.examTypeName,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchoolAutocompleteField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('Mevcut Okuduğu Okul *'),
        const SizedBox(height: 6),
        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return const Iterable<String>.empty();
            }
            final q = textEditingValue.text.toLowerCase();
            return _availableSchools.where((s) => s.toLowerCase().contains(q));
          },
          onSelected: (String selection) {
            _currentSchoolController.text = selection;
          },
          fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
            // Init value if exists (edit mode)
            if (textEditingController.text.isEmpty && _currentSchoolController.text.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                textEditingController.text = _currentSchoolController.text;
              });
            }

            return TextFormField(
              controller: textEditingController,
              focusNode: focusNode,
              onFieldSubmitted: (v) => onFieldSubmitted(),
              onChanged: (v) => _currentSchoolController.text = v,
              validator: (v) => v == null || v.trim().isEmpty ? 'Okul alanı zorunludur' : null,
              decoration: InputDecoration(
                hintText: 'Öğrencinin kayıtlı olduğu okul',
                hintStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4.0,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: MediaQuery.of(context).size.width - 64, // Appx responsive width
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return ListTile(
                        title: Text(option, style: const TextStyle(fontSize: 13)),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            counterText: '',
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
              borderSide: const BorderSide(color: _primaryColor, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.blueGrey.shade800,
      ),
    );
  }

  String _toTurkishUpper(String text) {
    return text
        .replaceAll('i', 'İ')
        .replaceAll('ı', 'I')
        .replaceAll('ğ', 'Ğ')
        .replaceAll('ü', 'Ü')
        .replaceAll('ş', 'Ş')
        .replaceAll('ö', 'Ö')
        .replaceAll('ç', 'Ç')
        .toUpperCase();
  }

  Widget _buildSearchableSelectorField({
    required String label,
    required String? value,
    required String hint,
    required VoidCallback onTap,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 6),
        FormField<String>(
          key: ValueKey(value),
          initialValue: value,
          validator: validator,
          builder: (formState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: formState.hasError ? Colors.red : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            value ?? hint,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: value == null ? Colors.blueGrey.shade300 : const Color(0xFF1E293B),
                              fontWeight: value == null ? FontWeight.normal : FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.blueGrey,
                        ),
                      ],
                    ),
                  ),
                ),
                if (formState.hasError) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      formState.errorText ?? '',
                      style: const TextStyle(color: Colors.red, fontSize: 11),
                    ),
                  ),
                ]
              ],
            );
          },
        ),
      ],
    );
  }

  void _showSearchableSelectDialog({
    required String title,
    required List<String> items,
    required String? currentValue,
    required ValueChanged<String> onSelected,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        String searchQuery = '';
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 500),
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                final filtered = items.where((item) {
                  final itemUpper = _toTurkishUpper(item);
                  final queryUpper = _toTurkishUpper(searchQuery);
                  return itemUpper.contains(queryUpper);
                }).toList();

                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: _accentColor,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => Navigator.pop(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Ara...',
                          hintStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: _primaryColor),
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
                            borderSide: const BorderSide(color: _primaryColor, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onChanged: (val) {
                          setDialogState(() {
                            searchQuery = val;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'Sonuç bulunamadı.',
                                  style: GoogleFonts.inter(
                                    color: Colors.grey.shade400,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  final isCurrent = item == currentValue;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: InkWell(
                                      onTap: () {
                                        onSelected(item);
                                        Navigator.pop(context);
                                      },
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: isCurrent
                                              ? Colors.orange.shade50
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item,
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  fontWeight: isCurrent
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: isCurrent
                                                      ? _primaryColor
                                                      : const Color(0xFF1E293B),
                                                ),
                                              ),
                                            ),
                                            if (isCurrent)
                                              const Icon(
                                                Icons.check_circle_rounded,
                                                color: _primaryColor,
                                                size: 16,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

