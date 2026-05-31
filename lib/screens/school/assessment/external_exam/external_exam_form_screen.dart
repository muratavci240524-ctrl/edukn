import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../models/assessment/external_exam_model.dart';
import '../../../../services/external_exam_service.dart';
import '../../../../services/user_permission_service.dart';

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

  // ─── Step 3: Salon Planı ───
  SeatingMode _seatingMode = SeatingMode.noSeating;
  final List<String> _selectedSchoolTypeIds = [];
  final List<GradeClassroomAssignment> _classroomAssignments = [];

  // ─── Step 4: Burs Konfigürasyonu ───
  bool _scholarshipEnabled = false;
  final Map<String, List<ScholarshipTier>> _scholarshipConfig = {};

  // ─── Step 5: Yönetmelik ───
  final _regulationUrlController = TextEditingController();

  static const _allGrades = ['5', '6', '7', '8', '9', '10', '11', '12'];

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
    _seatingMode = exam.venueConfig.seatingMode;
    _selectedSchoolTypeIds.addAll(exam.venueConfig.schoolTypeIds);
    _classroomAssignments.addAll(exam.venueConfig.classroomAssignments);
    _scholarshipEnabled = exam.scholarshipEnabled;
    _scholarshipConfig.addAll(exam.scholarshipConfig);
    _regulationUrlController.text = exam.regulationUrl ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
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
          onPressed: () => Navigator.pop(context),
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
      floatingActionButton: _buildFAB(),
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
          return Expanded(
            child: Row(
              children: [
                Expanded(
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _allGrades.map((grade) {
                  final selected = _selectedGrades.contains(grade);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _selectedGrades.remove(grade);
                      } else {
                        _selectedGrades.add(grade);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: selected ? _primaryColor : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? _primaryColor : Colors.grey.shade200,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$grade.',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            color: selected ? Colors.white : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
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
              OutlinedButton.icon(
                onPressed: _addSession,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryColor,
                  side: const BorderSide(color: _primaryColor),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Seans Ekle'),
              ),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionCard(ApplicationSession session, int index) {
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
              const Spacer(),
              IconButton(
                onPressed: () => setState(() => _sessions.removeAt(index)),
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: Colors.red),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tarih', style: _smallLabelStyle()),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _pickDate(index),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(
                          '${session.sessionDate.day}.${session.sessionDate.month}.${session.sessionDate.year}',
                          style: GoogleFonts.inter(fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Saat', style: _smallLabelStyle()),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        '${session.startTime} – ${session.endTime}',
                        style: GoogleFonts.inter(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Sınıf Kotaları', style: _smallLabelStyle()),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: session.gradeLevels.map((grade) {
              final quota = session.gradeLevelQuotas[grade] ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$grade. Sınıf: $quota kişi',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(int sessionIndex) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _sessions[sessionIndex].sessionDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      locale: const Locale('tr'),
    );
    if (picked != null) {
      final updated = ApplicationSession(
        id: _sessions[sessionIndex].id,
        sessionDate: picked,
        startTime: _sessions[sessionIndex].startTime,
        endTime: _sessions[sessionIndex].endTime,
        gradeLevels: _sessions[sessionIndex].gradeLevels,
        gradeLevelQuotas: _sessions[sessionIndex].gradeLevelQuotas,
      );
      setState(() => _sessions[sessionIndex] = updated);
    }
  }

  void _addSession() {
    final newId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    final gradeLevels = _selectedGrades.toList()..sort();
    final quotas = {for (final g in gradeLevels) g: 50};

    setState(() {
      _sessions.add(ApplicationSession(
        id: newId,
        sessionDate: DateTime.now().add(const Duration(days: 30)),
        startTime: '09:00',
        endTime: '11:30',
        gradeLevels: gradeLevels,
        gradeLevelQuotas: quotas,
      ));
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

              Text('Yönetmelik URL (opsiyonel)', style: _labelStyle()),
              const SizedBox(height: 8),
              TextField(
                controller: _regulationUrlController,
                decoration: _inputDecoration('https://...'),
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

  // ─── FAB ─────────────────────────────────────────────────────────────────

  Widget _buildFAB() {
    final isLastStep = _currentStep == 4;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_currentStep > 0)
          FloatingActionButton(
            heroTag: 'back_fab',
            onPressed: () {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
              setState(() => _currentStep--);
            },
            backgroundColor: Colors.grey.shade200,
            foregroundColor: Colors.grey.shade700,
            elevation: 2,
            mini: true,
            child: const Icon(Icons.arrow_back_rounded),
          ),
        const SizedBox(width: 12),
        FloatingActionButton.extended(
          heroTag: 'next_fab',
          onPressed: _isSaving
              ? null
              : isLastStep
                  ? _save
                  : _nextStep,
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          icon: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Icon(isLastStep
                  ? Icons.check_rounded
                  : Icons.arrow_forward_rounded),
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
      final user = FirebaseAuth.instance.currentUser;
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
        isActive: true,
        createdAt: widget.existingExam?.createdAt ?? DateTime.now(),
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
