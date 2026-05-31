import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/assessment/external_exam_model.dart';
import '../../models/assessment/external_exam_registration_model.dart';
import '../../services/external_exam_service.dart';

/// Public-facing registration page — accessible without login
/// URL: /external-exam-register/:examId
class ExternalExamRegisterScreen extends StatefulWidget {
  final String examId;

  const ExternalExamRegisterScreen({Key? key, required this.examId})
      : super(key: key);

  @override
  State<ExternalExamRegisterScreen> createState() =>
      _ExternalExamRegisterScreenState();
}

class _ExternalExamRegisterScreenState
    extends State<ExternalExamRegisterScreen> {
  final ExternalExamService _service = ExternalExamService();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _submitted = false;
  String? _registrationId;

  ExternalExam? _exam;
  String? _errorMessage;

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

  static const _primaryColor = Color(0xFFF57C00);

  @override
  void initState() {
    super.initState();
    _loadExam();
  }

  @override
  void dispose() {
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

  Future<void> _loadExam() async {
    try {
      final exam = await _service.getExternalExamById(widget.examId);
      if (exam == null || !exam.isActive) {
        setState(() {
          _errorMessage = 'Bu sınav bulunamadı veya başvuruya kapalı.';
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _exam = exam;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Sınav bilgileri yüklenirken hata oluştu.';
        _isLoading = false;
      });
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

    setState(() => _isSubmitting = true);

    try {
      // Check duplicate
      final isDuplicate = await _service.checkDuplicateRegistration(
        widget.examId,
        _studentTcController.text.trim(),
      );

      if (isDuplicate) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bu TC kimlik numarası ile zaten başvuru yapılmış.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isSubmitting = false);
        return;
      }

      // Check quota
      final currentCount = await _service.getSessionRegistrationCount(
        widget.examId,
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
              content: Text(
                  'Seçilen seans ve sınıf için kontenjan dolmuştur.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isSubmitting = false);
        return;
      }

      // Create registration
      final reg = ExternalExamRegistration(
        examId: widget.examId,
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
        status: RegistrationStatus.pending,
        createdAt: DateTime.now(),
      );

      final regId = await _service.addRegistration(reg);

      if (mounted) {
        setState(() {
          _submitted = true;
          _registrationId = regId;
          _isSubmitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Başvuru hatası: $e')),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          _exam?.title ?? 'Sınav Başvurusu',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.bold, color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _primaryColor,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : _errorMessage != null
              ? _buildErrorState()
              : _submitted
                  ? _buildSuccessState()
                  : _buildForm(isMobile),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 64, color: Colors.red.shade300),
            const SizedBox(height: 20),
            Text(
              _errorMessage!,
              style: GoogleFonts.inter(
                  fontSize: 16, color: Colors.grey.shade600),
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
              child: const Icon(Icons.check_circle_rounded,
                  size: 44, color: Colors.green),
            ),
            const SizedBox(height: 24),
            Text(
              'Başvurunuz Alındı!',
              style: GoogleFonts.inter(
                  fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Başvurunuz incelendikten sonra onaylandığında bildirim alacaksınız.',
              style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (_registrationId != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  children: [
                    Text(
                      'Başvuru Numaranız',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.grey.shade500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _registrationId!.substring(0, 8).toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _primaryColor,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildForm(bool isMobile) {
    return SingleChildScrollView(
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
                // Exam info banner
                _buildExamInfoBanner(),

                const SizedBox(height: 24),

                // Session & Grade selection
                _buildCard(
                  title: 'Seans ve Sınıf Seçimi',
                  icon: Icons.calendar_today_rounded,
                  children: [
                    _buildSectionLabel('Sınıf'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _exam!.gradeLevels.map((g) {
                        final sel = _selectedGrade == g;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedGrade = g),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: sel
                                  ? _primaryColor
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sel
                                    ? _primaryColor
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$g.',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  color: sel
                                      ? Colors.white
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    _buildSectionLabel('Seans'),
                    const SizedBox(height: 8),
                    ...(_exam!.applicationSessions).map((session) {
                      final sel = _selectedSessionId == session.id;
                      final grade = _selectedGrade;
                      final quota = grade != null
                          ? session.quotaForGrade(grade)
                          : 0;
                      final canApply = grade == null ||
                          session.gradeLevels.contains(grade);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: canApply
                              ? () => setState(
                                  () => _selectedSessionId = session.id)
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
                                color: sel
                                    ? _primaryColor
                                    : Colors.grey.shade200,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                              color: Colors.grey.shade500),
                                        ),
                                      if (!canApply)
                                        Text(
                                          'Bu seans seçilen sınıf için uygun değil',
                                          style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: Colors.red.shade400),
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

                // Student info
                _buildCard(
                  title: 'Öğrenci Bilgileri',
                  icon: Icons.person_rounded,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _studentNameController,
                            label: 'Ad',
                            hint: 'Adı',
                            validator: (v) => v == null || v.isEmpty
                                ? 'Zorunlu'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _studentSurnameController,
                            label: 'Soyad',
                            hint: 'Soyadı',
                            validator: (v) => v == null || v.isEmpty
                                ? 'Zorunlu'
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _studentTcController,
                      label: 'TC Kimlik No',
                      hint: '11 haneli TC',
                      keyboardType: TextInputType.number,
                      maxLength: 11,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Zorunlu';
                        if (v.length != 11) return '11 hane olmalı';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _currentSchoolController,
                      label: 'Mevcut Okul',
                      hint: 'Öğrencinin mevcut okulu',
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Zorunlu' : null,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Parent info
                _buildCard(
                  title: 'Veli Bilgileri',
                  icon: Icons.family_restroom_rounded,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _parentNameController,
                            label: 'Veli Adı',
                            hint: 'Ad',
                            validator: (v) => v == null || v.isEmpty
                                ? 'Zorunlu'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _parentSurnameController,
                            label: 'Veli Soyadı',
                            hint: 'Soyad',
                            validator: (v) => v == null || v.isEmpty
                                ? 'Zorunlu'
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _parentPhoneController,
                      label: 'Veli Telefonu *',
                      hint: '05xxxxxxxxx',
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Zorunlu';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      controller: _parentEmailController,
                      label: 'Veli E-posta (opsiyonel)',
                      hint: 'ornek@mail.com',
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Location
                _buildCard(
                  title: 'Adres Bilgileri',
                  icon: Icons.location_on_rounded,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _cityController,
                            label: 'İl',
                            hint: 'Şehir',
                            validator: (v) => v == null || v.isEmpty
                                ? 'Zorunlu'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _districtController,
                            label: 'İlçe',
                            hint: 'İlçe',
                            validator: (v) => v == null || v.isEmpty
                                ? 'Zorunlu'
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'Başvuruyu Tamamla',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
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
            child: const Icon(Icons.emoji_events_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

  Widget _buildCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: _primaryColor),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _labelStyle()),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLength: maxLength,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: Colors.blueGrey.shade300, fontSize: 14),
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
              borderSide:
                  const BorderSide(color: _primaryColor, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Colors.red, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(text, style: _labelStyle());
  }

  TextStyle _labelStyle() => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.blueGrey.shade700,
      );
}
