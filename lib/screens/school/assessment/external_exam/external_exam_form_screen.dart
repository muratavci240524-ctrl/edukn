import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../models/assessment/external_exam_model.dart';
import '../../../../services/external_exam_service.dart';

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class ExternalExamFormScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final ExternalExam? existingExam; // null = yeni oluştur

  const ExternalExamFormScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.existingExam,
  }) : super(key: key);

  @override
  State<ExternalExamFormScreen> createState() => _ExternalExamFormScreenState();
}

class _ExternalExamFormScreenState extends State<ExternalExamFormScreen> {
  final ExternalExamService _service = ExternalExamService();
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isSaving = false;
  String? _schoolId;

  static const _primaryColor = Color(0xFFF57C00);

  // ─── Step 1: Temel Bilgiler ───
  final _titleController = TextEditingController();
  ExamType _selectedType = ExamType.bursluluk;
  final Set<String> _selectedGrades = {};

  // ─── Step 2: Başvuru Seansları ───
  final List<ApplicationSession> _sessions = [];
  final List<bool> _sessionExpanded = [];

  // ─── Step 3: Salon Planı ───
  SeatingMode _seatingMode = SeatingMode.noSeating;
  final List<String> _selectedSchoolTypeIds = [];
  final List<GradeClassroomAssignment> _classroomAssignments = [];

  // ─── Step 4: Burs Konfigürasyonu ───
  bool _scholarshipEnabled = false;
  final Map<String, List<ScholarshipTier>> _scholarshipConfig = {};

  // ─── Step 5: Yönetmelik ───
  final _regulationUrlController = TextEditingController();
  DateTime? _regulationPublishDate;
  
  // Dynamic Web Portal Visibility Toggles
  bool _showRegister = true;
  bool _showEdit = true;
  bool _showTicket = true;
  bool _showResults = true;
  bool _showRegulation = true;

  static const _allGrades = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', 'Mezun'];

  @override
  void initState() {
    super.initState();
    _loadSchoolId();
    if (widget.existingExam != null) {
      _prefillForm(widget.existingExam!);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _regulationUrlController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadSchoolId() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final schoolQuery = await FirebaseFirestore.instance
          .collection('schools')
          .where('institutionId', isEqualTo: widget.institutionId)
          .limit(1)
          .get();
      if (schoolQuery.docs.isNotEmpty && mounted) {
        setState(() => _schoolId = schoolQuery.docs.first.id);
      }
    } catch (e) {
      debugPrint('schoolId yükleme hatası: $e');
    }
  }

  void _prefillForm(ExternalExam exam) {
    _titleController.text = exam.title;
    _selectedType = exam.examType;
    _selectedGrades.addAll(exam.gradeLevels);
    _sessions.addAll(exam.applicationSessions);
    _sessionExpanded.addAll(List.generate(exam.applicationSessions.length, (index) => false));
    _seatingMode = exam.venueConfig.seatingMode;
    _selectedSchoolTypeIds.addAll(exam.venueConfig.schoolTypeIds);
    _classroomAssignments.addAll(exam.venueConfig.classroomAssignments);
    _scholarshipEnabled = exam.scholarshipEnabled;
    _scholarshipConfig.addAll(exam.scholarshipConfig);
    _regulationUrlController.text = exam.regulationUrl ?? '';
    _regulationPublishDate = exam.regulationPublishDate;
    _showRegister = exam.showRegister;
    _showEdit = exam.showEdit;
    _showTicket = exam.showTicket;
    _showResults = exam.showResults;
    _showRegulation = exam.showRegulation;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingExam != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          isEditing ? 'Sınavı Düzenle' : 'Yeni Sınav Oluştur',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: _primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (_currentStep > 0) {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
              setState(() => _currentStep--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          _buildStepIndicator(),

          // Form content
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep1(),
                _buildStep2(),
                _buildStep3(),
                _buildStep4(),
                _buildStep5(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['Temel', 'Seanslar', 'Salon', 'Burs', 'Özet'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        children: List.generate(steps.length, (i) {
          final isActive = i == _currentStep;
          final isDone = i < _currentStep;
          final isClickable = i < _currentStep;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: isClickable
                        ? () {
                            _pageController.animateToPage(
                              i,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                            setState(() => _currentStep = i);
                          }
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isDone
                                  ? Colors.green
                                  : isActive
                                      ? _primaryColor
                                      : Colors.grey.shade200,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: isDone
                                  ? const Icon(Icons.check_rounded,
                                      color: Colors.white, size: 16)
                                  : Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isActive
                                            ? Colors.white
                                            : Colors.grey.shade500,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            steps[i],
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: isActive ? _primaryColor : Colors.grey.shade400,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (i < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 20),
                      color: isDone ? Colors.green : Colors.grey.shade200,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ─── STEP 1: TEMEL BİLGİLER ──────────────────────────────────────────────

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Temel Bilgiler', Icons.info_outline_rounded),
              const SizedBox(height: 24),

              Text('Sınav Adı', style: _labelStyle()),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: _inputDecoration('Örn: 2026-2027 Bursluluk Sınavı'),
              ),

              const SizedBox(height: 24),

              Text('Sınav Türü', style: _labelStyle()),
              const SizedBox(height: 8),
              ...ExamType.values.map((type) {
                final names = {
                  ExamType.bursluluk: ('Bursluluk Sınavı', Icons.emoji_events_rounded),
                  ExamType.provaDeneme: ('Prova / Deneme Sınavı', Icons.science_rounded),
                  ExamType.diger: ('Diğer', Icons.quiz_rounded),
                };
                final (name, icon) = names[type]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => setState(() => _selectedType = type),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _selectedType == type
                            ? Colors.orange.shade50
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedType == type
                              ? _primaryColor
                              : Colors.grey.shade200,
                          width: _selectedType == type ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(icon,
                              color: _selectedType == type
                                  ? _primaryColor
                                  : Colors.grey.shade400,
                              size: 22),
                          const SizedBox(width: 12),
                          Text(
                            name,
                            style: GoogleFonts.inter(
                              fontWeight: _selectedType == type
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: _selectedType == type
                                  ? _primaryColor
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                          const Spacer(),
                          Radio<ExamType>(
                            value: type,
                            groupValue: _selectedType,
                            onChanged: (v) => setState(() => _selectedType = v!),
                            activeColor: _primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 24),

              Text('Sınıf Seviyeleri', style: _labelStyle()),
              const SizedBox(height: 4),
              Text('Bu sınavın hangi sınıflara yapılacağını seçin.',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 12),
              ScrollConfiguration(
                behavior: MyCustomScrollBehavior(),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: _allGrades.map((grade) {
                      final selected = _selectedGrades.contains(grade);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() {
                            if (selected) {
                              _selectedGrades.remove(grade);
                            } else {
                              _selectedGrades.add(grade);
                            }
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: grade == 'Mezun' ? 68 : 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: selected ? _primaryColor : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected ? _primaryColor : Colors.grey.shade200,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                grade == 'Mezun' ? 'Mezun' : '$grade.',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  color: selected ? Colors.white : Colors.grey.shade600,
                                  fontSize: grade == 'Mezun' ? 11 : 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  // ─── STEP 2: BAŞVURU SEANSLAR ─────────────────────────────────────────────

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Başvuru Seansları', Icons.calendar_today_rounded),
              const SizedBox(height: 8),
              Text(
                'Her seans için tarih, saat ve sınıf kotaları belirleyin.',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 24),

              ..._sessions.asMap().entries.map((entry) {
                final i = entry.key;
                final session = entry.value;
                return _buildSessionCard(session, i);
              }),

              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _primaryColor.withOpacity(0.06),
                      _primaryColor.withOpacity(0.01),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _primaryColor.withOpacity(0.35),
                    width: 1.5,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _addSession,
                    borderRadius: BorderRadius.circular(16),
                    splashColor: _primaryColor.withOpacity(0.1),
                    highlightColor: _primaryColor.withOpacity(0.05),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _primaryColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _primaryColor.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                )
                              ],
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Yeni Seans Ekle',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
    if (month >= 1 && month <= 12) {
      return months[month - 1];
    }
    return '';
  }

  Widget _buildSessionCard(ApplicationSession session, int index) {
    final isExpanded = _sessionExpanded[index];
    final isMobile = MediaQuery.of(context).size.width < 580;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? _primaryColor.withOpacity(0.3) : Colors.grey.shade200,
          width: isExpanded ? 1.5 : 1,
        ),
        boxShadow: isExpanded
            ? [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header of the Accordion
          InkWell(
            onTap: () {
              setState(() {
                _sessionExpanded[index] = !isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${index + 1}. Seans',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Date Display & Picker Chip
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        onTap: () => _pickDate(index),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 13, color: Colors.blueGrey.shade600),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${session.sessionDate.day} ${_getMonthName(session.sessionDate.month)} ${session.sessionDate.year}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey.shade700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.edit_calendar_rounded, size: 13, color: _primaryColor),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _sessions.removeAt(index);
                        _sessionExpanded.removeAt(index);
                      });
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          
          // Collapsed state classes summary
          if (!isExpanded) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: session.gradeLevels.isEmpty
                  ? Text(
                      'Sınıf seçilmedi.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: session.gradeLevels.map((grade) {
                        final quota = session.gradeLevelQuotas[grade] ?? 0;
                        final start = session.startTimeForGrade(grade);
                        final end = session.endTimeForGrade(grade);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            grade == 'Mezun' ? 'Mezun: $quota kişi ($start–$end)' : '$grade. Sınıf: $quota kişi ($start–$end)',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],

          // Expanded state accordion body
          if (isExpanded) ...[
            Divider(color: Colors.grey.shade100, height: 1, thickness: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sınav Sınıfları, Kotaları ve Saatleri',
                    style: _smallLabelStyle(),
                  ),
                  const SizedBox(height: 12),
                  if (_selectedGrades.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Lütfen önce 1. Adımda sınıf seviyelerini seçin.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.red.shade400,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  else
                    ...(_selectedGrades.toList()..sort()).map((grade) {
                      return _buildGradeRow(session, index, grade, isMobile);
                    }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGradeRow(ApplicationSession session, int sessionIndex, String grade, bool isMobile) {
    final isChecked = session.gradeLevels.contains(grade);
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isChecked ? Colors.orange.shade50.withOpacity(0.15) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isChecked ? _primaryColor.withOpacity(0.25) : Colors.grey.shade200,
          width: isChecked ? 1.5 : 1,
        ),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: isChecked,
                        activeColor: _primaryColor,
                        onChanged: (val) => _toggleGradeInSession(sessionIndex, grade, val == true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        grade == 'Mezun' ? 'Mezun Seviyesi' : '$grade. Sınıf',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isChecked ? const Color(0xFF1E293B) : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isChecked) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 38,
                            child: TextFormField(
                              key: ValueKey('quota_${sessionIndex}_$grade'),
                              initialValue: (session.gradeLevelQuotas[grade] ?? 50).toString(),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Kota',
                                labelStyle: GoogleFonts.inter(fontSize: 10, color: Colors.blueGrey.shade600),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              ),
                              onChanged: (val) {
                                final quota = int.tryParse(val) ?? 0;
                                _updateGradeQuota(sessionIndex, grade, quota);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: InkWell(
                            onTap: () => _pickGradeTime(sessionIndex, grade, isStart: true),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              height: 38,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.access_time_rounded, size: 13, color: Colors.blueGrey.shade500),
                                  const SizedBox(width: 4),
                                  Text(
                                    session.startTimeForGrade(grade),
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('–', style: TextStyle(color: Colors.grey.shade400)),
                        const SizedBox(width: 4),
                        Expanded(
                          flex: 3,
                          child: InkWell(
                            onTap: () => _pickGradeTime(sessionIndex, grade, isStart: false),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              height: 38,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.access_time_rounded, size: 13, color: Colors.blueGrey.shade500),
                                  const SizedBox(width: 4),
                                  Text(
                                    session.endTimeForGrade(grade),
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            )
          : Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isChecked,
                    activeColor: _primaryColor,
                    onChanged: (val) => _toggleGradeInSession(sessionIndex, grade, val == true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    grade == 'Mezun' ? 'Mezun Seviyesi' : '$grade. Sınıf',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isChecked ? const Color(0xFF1E293B) : Colors.grey.shade600,
                    ),
                  ),
                ),
                if (isChecked) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 38,
                      child: TextFormField(
                        key: ValueKey('quota_${sessionIndex}_$grade'),
                        initialValue: (session.gradeLevelQuotas[grade] ?? 50).toString(),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Kota',
                          labelStyle: GoogleFonts.inter(fontSize: 10, color: Colors.blueGrey.shade600),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        onChanged: (val) {
                          final quota = int.tryParse(val) ?? 0;
                          _updateGradeQuota(sessionIndex, grade, quota);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: () => _pickGradeTime(sessionIndex, grade, isStart: true),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.access_time_rounded, size: 13, color: Colors.blueGrey.shade500),
                            const SizedBox(width: 6),
                            Text(
                              session.startTimeForGrade(grade),
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('–', style: TextStyle(color: Colors.grey.shade400)),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: () => _pickGradeTime(sessionIndex, grade, isStart: false),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.access_time_rounded, size: 13, color: Colors.blueGrey.shade500),
                            const SizedBox(width: 6),
                            Text(
                              session.endTimeForGrade(grade),
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  const Spacer(flex: 8),
                ],
              ],
            ),
    );
  }

  void _toggleGradeInSession(int sessionIndex, String grade, bool isChecked) {
    final currentSession = _sessions[sessionIndex];
    final updatedGrades = List<String>.from(currentSession.gradeLevels);
    final updatedQuotas = Map<String, int>.from(currentSession.gradeLevelQuotas);
    final updatedStartTimes = Map<String, String>.from(currentSession.gradeLevelStartTimes);
    final updatedEndTimes = Map<String, String>.from(currentSession.gradeLevelEndTimes);

    if (isChecked) {
      if (!updatedGrades.contains(grade)) {
        updatedGrades.add(grade);
        updatedGrades.sort();
      }
      updatedQuotas.putIfAbsent(grade, () => 50);
      updatedStartTimes.putIfAbsent(grade, () => currentSession.startTime.isNotEmpty ? currentSession.startTime : '09:00');
      updatedEndTimes.putIfAbsent(grade, () => currentSession.endTime.isNotEmpty ? currentSession.endTime : '11:30');
    } else {
      updatedGrades.remove(grade);
      updatedQuotas.remove(grade);
      updatedStartTimes.remove(grade);
      updatedEndTimes.remove(grade);
    }

    final updatedSession = ApplicationSession(
      id: currentSession.id,
      sessionDate: currentSession.sessionDate,
      startTime: currentSession.startTime,
      endTime: currentSession.endTime,
      gradeLevels: updatedGrades,
      gradeLevelQuotas: updatedQuotas,
      gradeLevelStartTimes: updatedStartTimes,
      gradeLevelEndTimes: updatedEndTimes,
    );

    setState(() {
      _sessions[sessionIndex] = updatedSession;
    });
  }

  void _updateGradeQuota(int sessionIndex, String grade, int quota) {
    final currentSession = _sessions[sessionIndex];
    final updatedQuotas = Map<String, int>.from(currentSession.gradeLevelQuotas);
    updatedQuotas[grade] = quota;

    final updatedSession = ApplicationSession(
      id: currentSession.id,
      sessionDate: currentSession.sessionDate,
      startTime: currentSession.startTime,
      endTime: currentSession.endTime,
      gradeLevels: currentSession.gradeLevels,
      gradeLevelQuotas: updatedQuotas,
      gradeLevelStartTimes: currentSession.gradeLevelStartTimes,
      gradeLevelEndTimes: currentSession.gradeLevelEndTimes,
    );

    setState(() {
      _sessions[sessionIndex] = updatedSession;
    });
  }

  Future<void> _pickGradeTime(int sessionIndex, String grade, {required bool isStart}) async {
    final currentSession = _sessions[sessionIndex];
    final currentStr = isStart
        ? currentSession.startTimeForGrade(grade)
        : currentSession.endTimeForGrade(grade);
        
    TimeOfDay initialTime = const TimeOfDay(hour: 9, minute: 0);
    if (currentStr.isNotEmpty && currentStr.contains(':')) {
      final parts = currentStr.split(':');
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        initialTime = TimeOfDay(hour: h, minute: m);
      }
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox(),
        );
      },
    );

    if (picked != null) {
      final formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      final updatedStartTimes = Map<String, String>.from(currentSession.gradeLevelStartTimes);
      final updatedEndTimes = Map<String, String>.from(currentSession.gradeLevelEndTimes);

      if (isStart) {
        updatedStartTimes[grade] = formatted;
      } else {
        updatedEndTimes[grade] = formatted;
      }

      final updatedSession = ApplicationSession(
        id: currentSession.id,
        sessionDate: currentSession.sessionDate,
        startTime: currentSession.startTime,
        endTime: currentSession.endTime,
        gradeLevels: currentSession.gradeLevels,
        gradeLevelQuotas: currentSession.gradeLevelQuotas,
        gradeLevelStartTimes: updatedStartTimes,
        gradeLevelEndTimes: updatedEndTimes,
      );

      setState(() {
        _sessions[sessionIndex] = updatedSession;
      });
    }
  }

  Future<void> _pickDate(int sessionIndex) async {
    final sessionDate = _sessions[sessionIndex].sessionDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: sessionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('tr'),
    );
    if (picked != null) {
      final currentSession = _sessions[sessionIndex];
      final updated = ApplicationSession(
        id: currentSession.id,
        sessionDate: picked,
        startTime: currentSession.startTime,
        endTime: currentSession.endTime,
        gradeLevels: currentSession.gradeLevels,
        gradeLevelQuotas: currentSession.gradeLevelQuotas,
        gradeLevelStartTimes: currentSession.gradeLevelStartTimes,
        gradeLevelEndTimes: currentSession.gradeLevelEndTimes,
      );
      setState(() => _sessions[sessionIndex] = updated);
    }
  }

  void _addSession() {
    final newId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    final gradeLevels = _selectedGrades.toList()..sort();
    final quotas = {for (final g in gradeLevels) g: 50};
    final startTimes = {for (final g in gradeLevels) g: '09:00'};
    final endTimes = {for (final g in gradeLevels) g: '11:30'};

    setState(() {
      _sessions.add(ApplicationSession(
        id: newId,
        sessionDate: DateTime.now().add(const Duration(days: 30)),
        startTime: '09:00',
        endTime: '11:30',
        gradeLevels: gradeLevels,
        gradeLevelQuotas: quotas,
        gradeLevelStartTimes: startTimes,
        gradeLevelEndTimes: endTimes,
      ));
      _sessionExpanded.add(true);
    });
  }

  // ─── STEP 3: SALON PLANI ──────────────────────────────────────────────────

  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Salon Planlaması', Icons.meeting_room_rounded),
              const SizedBox(height: 24),

              Text('Oturma Düzeni', style: _labelStyle()),
              const SizedBox(height: 12),
              ...SeatingMode.values.map((mode) {
                final names = {
                  SeatingMode.noSeating: (
                    'Salon Hazırlanmasın',
                    'Sadece giriş belgesi verilir, oturma planı oluşturulmaz.',
                    Icons.no_accounts_rounded,
                  ),
                  SeatingMode.butterfly: (
                    'Kelebek Sistemi',
                    'Aynı okuldan öğrenciler ayrı salonlara / sıralara dağıtılır.',
                    Icons.scatter_plot_rounded,
                  ),
                  SeatingMode.simpleRandom: (
                    'Rastgele Dağılım',
                    'Öğrenciler rastgele salonlara dağıtılır.',
                    Icons.shuffle_rounded,
                  ),
                };
                final (name, desc, icon) = names[mode]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => setState(() => _seatingMode = mode),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _seatingMode == mode
                            ? Colors.orange.shade50
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _seatingMode == mode
                              ? _primaryColor
                              : Colors.grey.shade200,
                          width: _seatingMode == mode ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(icon,
                              color: _seatingMode == mode
                                  ? _primaryColor
                                  : Colors.grey.shade400,
                              size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold)),
                                Text(desc,
                                    style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                          Radio<SeatingMode>(
                            value: mode,
                            groupValue: _seatingMode,
                            onChanged: (v) =>
                                setState(() => _seatingMode = v!),
                            activeColor: _primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              if (_seatingMode != SeatingMode.noSeating) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: Colors.blue.shade600, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Sınav kaydedildikten sonra Detay > Salon Planı ekranından derslik atamalarını yapabilirsiniz.',
                          style: GoogleFonts.inter(
                              fontSize: 13, color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  // ─── STEP 4: BURS KONFİGÜRASYONU ─────────────────────────────────────────

  Widget _buildStep4() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Burs Konfigürasyonu', Icons.workspace_premium_rounded),
              const SizedBox(height: 16),

              SwitchListTile(
                value: _scholarshipEnabled,
                onChanged: (v) => setState(() => _scholarshipEnabled = v),
                title: Text('Burs Aktif',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    'Sınav sonucunda burs kademesi hesaplanır.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Colors.grey.shade500)),
                activeColor: _primaryColor,
                contentPadding: EdgeInsets.zero,
              ),

              if (_scholarshipEnabled) ...[
                const SizedBox(height: 16),
                Text(
                  'Sınıf bazlı burs kademeleri aşağıdan tanımlanır. Her sınıf için sıralama aralığı ve burs oranını belirleyin.',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 16),

                ...(_selectedGrades.toList()..sort()).map((grade) {
                  final tiers = _scholarshipConfig[grade] ?? [];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$grade. Sınıf',
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade700,
                                    fontSize: 13),
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _addTier(grade),
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Kademe'),
                              style: TextButton.styleFrom(
                                  foregroundColor: _primaryColor,
                                  padding: EdgeInsets.zero),
                            ),
                          ],
                        ),
                        if (tiers.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Henüz kademe eklenmedi.',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: Colors.grey.shade400),
                            ),
                          )
                        else
                          ...tiers.asMap().entries.map((e) => Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${e.value.minRank}–${e.value.maxRank}. arası',
                                        style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: Colors.green.shade700),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '%${e.value.rate} Burs',
                                        style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amber.shade700),
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _scholarshipConfig[grade]!
                                              .removeAt(e.key);
                                        });
                                      },
                                      icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 16,
                                          color: Colors.red),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              )),
                      ],
                    ),
                  );
                }),
              ],

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  void _addTier(String grade) async {
    final minController = TextEditingController(text: '1');
    final maxController = TextEditingController(text: '5');
    final rateController = TextEditingController(text: '100');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$grade. Sınıf – Burs Kademesi',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minController,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration('Min Sıra').copyWith(labelText: 'Min Sıra'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: maxController,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration('Max Sıra').copyWith(labelText: 'Max Sıra'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rateController,
              keyboardType: TextInputType.number,
              decoration: _inputDecoration('Burs Oranı (%)').copyWith(labelText: 'Burs Oranı (%)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _scholarshipConfig.putIfAbsent(grade, () => []).add(
                  ScholarshipTier(
                    minRank: int.tryParse(minController.text) ?? 1,
                    maxRank: int.tryParse(maxController.text) ?? 5,
                    rate: int.tryParse(rateController.text) ?? 100,
                  ),
                );
              });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  // ─── STEP 5: ÖZET ────────────────────────────────────────────────────────

  Widget _buildStep5() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Özet & Kaydet', Icons.check_circle_outline_rounded),
              const SizedBox(height: 24),

              _buildSummaryRow('Sınav Adı', _titleController.text.isEmpty ? '—' : _titleController.text),
              _buildSummaryRow('Tür', _selectedType == ExamType.bursluluk
                  ? 'Bursluluk Sınavı'
                  : _selectedType == ExamType.provaDeneme
                      ? 'Prova / Deneme'
                      : 'Diğer'),
              _buildSummaryRow('Sınıflar',
                  _selectedGrades.isEmpty ? '—' : (_selectedGrades.toList()..sort()).join(', ')),
              _buildSummaryRow('Seanslar', '${_sessions.length} seans'),
              _buildSummaryRow('Oturma Düzeni',
                  _seatingMode == SeatingMode.noSeating
                      ? 'Salon hazırlanmayacak'
                      : _seatingMode == SeatingMode.butterfly
                          ? 'Kelebek Sistemi'
                          : 'Rastgele Dağılım'),
              _buildSummaryRow(
                  'Burs', _scholarshipEnabled ? 'Aktif' : 'Pasif'),

              const SizedBox(height: 24),

              Text('Sınav Kılavuzu / Şartname Linki (Opsiyonel)', style: _labelStyle()),
              const SizedBox(height: 4),
              Text(
                'Başvuru yapan veli ve öğrencilerin görebileceği; sınav kuralları, burs detayları veya bilgilendirme kılavuzunun (PDF dosyası veya web sayfası) internet adresidir.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _regulationUrlController,
                decoration: _inputDecoration('Örn: https://okulunuzunadresi.com/bursluluk-kilavuzu.pdf'),
              ),

              const SizedBox(height: 24),

              Text('Sınav Sonuçları Açıklanma Tarihi (Opsiyonel)', style: _labelStyle()),
              const SizedBox(height: 4),
              Text(
                'Sınav sonuçlarının açıklanacağı tarihtir. Bu tarih seçilirse sonuç açıklanana kadar başvuru sayfasında bu tarih gösterilir.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _regulationPublishDate ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: _primaryColor,
                            onPrimary: Colors.white,
                            onSurface: Colors.black87,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (date != null) {
                    setState(() => _regulationPublishDate = date);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, color: _primaryColor, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        _regulationPublishDate == null
                            ? 'Tarih Seçilmedi'
                            : '${_regulationPublishDate!.day}.${_regulationPublishDate!.month}.${_regulationPublishDate!.year}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: _regulationPublishDate == null ? FontWeight.normal : FontWeight.bold,
                          color: _regulationPublishDate == null ? Colors.blueGrey.shade300 : const Color(0xFF1E293B),
                        ),
                      ),
                      const Spacer(),
                      if (_regulationPublishDate != null)
                        IconButton(
                          onPressed: () {
                            setState(() => _regulationPublishDate = null);
                          },
                          icon: const Icon(Icons.clear_rounded, color: Colors.red, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              _buildSectionTitle('Başvuru Portalı Görünüm Ayarları', Icons.settings_suggest_rounded),
              const SizedBox(height: 8),
              Text(
                'Başvuru portalında hangi butonların ve işlemlerin aktif olacağını buradan yönetebilirsiniz.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _showRegister,
                      onChanged: (v) => setState(() => _showRegister = v),
                      title: Text('Yeni Başvuru Butonu', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('Öğrencilerin yeni başvuru yapabilmesini sağlar.', style: GoogleFonts.inter(fontSize: 11)),
                      activeColor: _primaryColor,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _showEdit,
                      onChanged: (v) => setState(() => _showEdit = v),
                      title: Text('Başvuruyu Düzenle Butonu', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('Adayların bilgilerini güncelleyebilmesini sağlar.', style: GoogleFonts.inter(fontSize: 11)),
                      activeColor: _primaryColor,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _showTicket,
                      onChanged: (v) => setState(() => _showTicket = v),
                      title: Text('Sınav Giriş Belgesi Butonu', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('Giriş belgesi sorgulama ve indirmeyi aktif eder.', style: GoogleFonts.inter(fontSize: 11)),
                      activeColor: _primaryColor,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _showRegulation,
                      onChanged: (v) => setState(() => _showRegulation = v),
                      title: Text('Sınav Yönergesi Butonu', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('Varsa yüklenen kılavuz linkini ana sayfada gösterir.', style: GoogleFonts.inter(fontSize: 11)),
                      activeColor: _primaryColor,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _showResults,
                      onChanged: (v) => setState(() => _showResults = v),
                      title: Text('Sınav Sonuçları Butonu', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('Sonuç sorgulama veya duyuru butonunu aktif eder.', style: GoogleFonts.inter(fontSize: 11)),
                      activeColor: _primaryColor,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 13, color: Colors.grey.shade500)),
            const Spacer(),
            Text(value,
                style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // ─── BOTTOM NAVIGATION BAR ────────────────────────────────────────────────

  Widget _buildBottomNavigationBar() {
    final isLastStep = _currentStep == 4;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              if (_currentStep > 0)
                OutlinedButton.icon(
                  onPressed: () {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                    setState(() => _currentStep--);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text('Geri', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                )
              else
                const SizedBox(),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isSaving
                    ? null
                    : isLastStep
                        ? _save
                        : _nextStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  elevation: 0,
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Icon(isLastStep ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 18),
                label: Text(
                  isLastStep
                      ? _isSaving
                          ? 'Kaydediliyor...'
                          : 'Kaydet'
                      : 'İleri',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _nextStep() {
    // Validation
    if (_currentStep == 0) {
      if (_titleController.text.trim().isEmpty) {
        _showSnack('Lütfen sınav adı girin.');
        return;
      }
      if (_selectedGrades.isEmpty) {
        _showSnack('En az bir sınıf seçin.');
        return;
      }
    }

    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep++);
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty || _selectedGrades.isEmpty) {
      _showSnack('Lütfen temel bilgileri doldurun.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final exam = ExternalExam(
        id: widget.existingExam?.id,
        institutionId: widget.institutionId,
        schoolId: _schoolId ?? '',
        title: _titleController.text.trim(),
        examType: _selectedType,
        gradeLevels: (_selectedGrades.toList()..sort()),
        trialExamIds: widget.existingExam?.trialExamIds ?? {},
        applicationSessions: _sessions,
        venueConfig: VenueConfig(
          seatingMode: _seatingMode,
          schoolTypeIds: _selectedSchoolTypeIds,
          classroomAssignments: _classroomAssignments,
        ),
        scholarshipEnabled: _scholarshipEnabled,
        scholarshipConfig: _scholarshipConfig,
        regulationUrl: _regulationUrlController.text.trim().isEmpty
            ? null
            : _regulationUrlController.text.trim(),
        regulationPublishDate: _regulationPublishDate,
        isActive: true,
        createdAt: widget.existingExam?.createdAt ?? DateTime.now(),
        showRegister: _showRegister,
        showEdit: _showEdit,
        showTicket: _showTicket,
        showResults: _showResults,
        showRegulation: _showRegulation,
      );

      if (widget.existingExam != null) {
        await _service.updateExternalExam(exam);
      } else {
        await _service.createExternalExam(exam);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existingExam != null
                ? 'Sınav güncellendi.'
                : 'Sınav oluşturuldu.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnack('Kaydetme hatası: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────────

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.orange.shade800),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _primaryColor, size: 22),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  TextStyle _labelStyle() => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.blueGrey.shade700,
      );

  TextStyle _smallLabelStyle() => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.blueGrey.shade500,
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
          borderSide: BorderSide(color: _primaryColor, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}
