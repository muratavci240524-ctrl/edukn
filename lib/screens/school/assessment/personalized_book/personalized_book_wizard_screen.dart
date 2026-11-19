import 'dart:math' as math;
import 'dart:typed_data';

import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:printing/printing.dart';

import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../services/assessment_service.dart';
import '../../../../services/web_share/web_file_share.dart';
import '../../../../utils/difficulty_scale.dart';
import 'personalized_book_generator_service.dart';
import 'personalized_book_models.dart';

class PersonalizedBookWizardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final List<TrialExam> availableExams;
  final List<PoolQuestionItem>? preloadedPool;
  final PersonalizedBookConfig? initialTemplate;
  final List<String>? preselectedExamIds;

  const PersonalizedBookWizardScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.availableExams,
    this.preloadedPool,
    this.initialTemplate,
    this.preselectedExamIds,
  });

  @override
  State<PersonalizedBookWizardScreen> createState() =>
      _PersonalizedBookWizardScreenState();
}

class _PersonalizedBookWizardScreenState
    extends State<PersonalizedBookWizardScreen> {
  final PersonalizedBookGeneratorService _service =
      PersonalizedBookGeneratorService();

  int _currentStep = 0;

  // Havuz & Sınav Analizi Durumu
  bool _isLoadingPool = true;
  bool _isAnalyzing = false;
  int _analysisRunId = 0;
  List<PoolQuestionItem> _poolQuestions = [];
  final Set<String> _selectedExamIds = {};

  // Filtreler - Step 1
  String? _examClassFilter;
  String _examSearchQuery = '';
  String? _studentBranchFilter;
  MasteryBand? _studentBandFilter;
  String _studentSearchQuery = '';

  // Analiz Sonuçları
  List<StudentMasteryProfile> _allStudents = [];
  final Set<String> _selectedStudentIds = {};
  List<ExamOutcomeTopicRule> _outcomeRules = [];

  // Filtreler - Step 2
  String? _ruleSubjectFilter;

  // Kitap Tasarım Konfigürasyonu - Step 3
  late PersonalizedBookConfig _config;
  late TextEditingController _pageCountCtrl;
  late TextEditingController _bookTitleCtrl;
  late TextEditingController _bookSubtitleCtrl;
  late TextEditingController _institutionNameCtrl;
  late TextEditingController _prefaceTitleCtrl;
  late TextEditingController _prefaceBodyCtrl;
  late TextEditingController _prefaceAuthorCtrl;
  bool _isRasterizingPrefacePdf = false;

  // Step 4 Önizleme Memoization & İzole Üretim İlerleme Durumu
  String? _previewStudentId;
  int _planRevision = 0;
  StudentBookPlan? _cachedPreviewPlan;
  String? _cachedPreviewPlanKey;
  bool _isPreparingImagesForPreview = false;
  bool _isExporting = false;
  final ValueNotifier<({String text, double ratio, int current, int total})>
  _exportProgressNotifier = ValueNotifier((
    text: '',
    ratio: 0.0,
    current: 0,
    total: 0,
  ));

  static const List<int> _quickPagePresets = [12, 16, 20, 24, 32, 40, 48, 64];

  static OutlineInputBorder _fieldBorder(Color color, [double width = 1.0]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  @override
  void initState() {
    super.initState();
    final tpl = widget.initialTemplate;
    _config = tpl != null
        ? PersonalizedBookConfig(
            id: tpl.id,
            templateName: tpl.templateName,
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
            selectedExamIds: List<String>.from(tpl.selectedExamIds),
            selectedExamNames: List<String>.from(tpl.selectedExamNames),
            targetPageCount: tpl.targetPageCount,
            padShortBooksWithStudyNotes: tpl.padShortBooksWithStudyNotes,
            includeCover: tpl.includeCover,
            coverTheme: tpl.coverTheme,
            bookTitle: tpl.bookTitle,
            bookSubtitle: tpl.bookSubtitle,
            institutionDisplayName: tpl.institutionDisplayName,
            prefaceMode: tpl.prefaceMode,
            manualPrefaceTitle: tpl.manualPrefaceTitle,
            manualPrefaceBody: tpl.manualPrefaceBody,
            manualPrefaceAuthor: tpl.manualPrefaceAuthor,
            includeToc: tpl.includeToc,
            includeAnswerKey: tpl.includeAnswerKey,
            skipZeroMinOnHighMastery: tpl.skipZeroMinOnHighMastery,
            highMasteryZeroThreshold: tpl.highMasteryZeroThreshold,
            allowSubjectFallbackWhenOutcomePoolShort:
                tpl.allowSubjectFallbackWhenOutcomePoolShort,
            includeExerciseQuestions: tpl.includeExerciseQuestions,
            includeTrialExamQuestions: tpl.includeTrialExamQuestions,
            veryEasyDifficultyWeight: tpl.veryEasyDifficultyWeight,
            easyDifficultyWeight: tpl.easyDifficultyWeight,
            mediumDifficultyWeight: tpl.mediumDifficultyWeight,
            hardDifficultyWeight: tpl.hardDifficultyWeight,
            veryHardDifficultyWeight: tpl.veryHardDifficultyWeight,
            minQuestionsByOutcomeKey: Map<String, int>.from(
              tpl.minQuestionsByOutcomeKey,
            ),
            disabledOutcomeKeys: Set<String>.from(tpl.disabledOutcomeKeys),
          )
        : PersonalizedBookConfig(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
          );

    _pageCountCtrl = TextEditingController(text: '${_config.targetPageCount}');
    _bookTitleCtrl = TextEditingController(text: _config.bookTitle);
    _bookSubtitleCtrl = TextEditingController(text: _config.bookSubtitle);
    _institutionNameCtrl = TextEditingController(
      text: _config.institutionDisplayName,
    );
    _prefaceTitleCtrl = TextEditingController(text: _config.manualPrefaceTitle);
    _prefaceBodyCtrl = TextEditingController(text: _config.manualPrefaceBody);
    _prefaceAuthorCtrl = TextEditingController(
      text: _config.manualPrefaceAuthor,
    );

    if (widget.preselectedExamIds != null &&
        widget.preselectedExamIds!.isNotEmpty) {
      _selectedExamIds.addAll(widget.preselectedExamIds!);
    } else if (_config.selectedExamIds.isNotEmpty) {
      final validIds = widget.availableExams.map((e) => e.id).toSet();
      _selectedExamIds.addAll(
        _config.selectedExamIds.where((id) => validIds.contains(id)),
      );
    }

    _initializePoolAndAnalyze();
  }

  @override
  void dispose() {
    _exportProgressNotifier.dispose();
    _pageCountCtrl.dispose();
    _bookTitleCtrl.dispose();
    _bookSubtitleCtrl.dispose();
    _institutionNameCtrl.dispose();
    _prefaceTitleCtrl.dispose();
    _prefaceBodyCtrl.dispose();
    _prefaceAuthorCtrl.dispose();
    super.dispose();
  }

  Future<void> _initializePoolAndAnalyze() async {
    setState(() => _isLoadingPool = true);
    try {
      if (widget.preloadedPool != null && widget.preloadedPool!.isNotEmpty) {
        _poolQuestions = widget.preloadedPool!;
      } else {
        _poolQuestions = await _service.loadFullQuestionPool(
          widget.institutionId,
          extraExams: widget.availableExams,
        );
      }
      if (_selectedExamIds.isNotEmpty) {
        await _runAnalysis();
      }
    } finally {
      if (mounted) setState(() => _isLoadingPool = false);
    }
  }

  List<TrialExam> get _selectedExams => widget.availableExams
      .where((e) => _selectedExamIds.contains(e.id))
      .toList();

  /// Şablondaki "Egzersiz Sorularını da Ekle" ve "Deneme Sorularını da Ekle" anahtarlarına göre aktif havuz.
  List<PoolQuestionItem> get _activePoolQuestions =>
      _poolQuestions.where((q) => q.isAllowedByConfig(_config)).toList();

  /// Egzersiz / Deneme anahtarları değiştiğinde kazanım satırlarının havuz eşleşme sayılarını anında günceller.
  void _recomputeOutcomeRulePoolCounts() {
    final activePool = _activePoolQuestions;
    final Map<String, int> poolCountBySubject = {};
    for (final pq in activePool) {
      poolCountBySubject[pq.subject] =
          (poolCountBySubject[pq.subject] ?? 0) + 1;
    }
    for (final r in _outcomeRules) {
      int exactCount = 0;
      for (final pq in activePool) {
        if (pq.subject != r.subject) continue;
        if (pq.normalizedOutcomeKey == r.key ||
            pq.matchesOutcomeTextOrK12(r.outcome)) {
          exactCount++;
        }
      }
      r.poolExactCount = exactCount;
      r.poolSubjectTotalCount = poolCountBySubject[r.subject] ?? 0;
    }
  }

  Future<void> _runAnalysis() async {
    final int runId = ++_analysisRunId;
    final exams = _selectedExams;
    if (exams.isEmpty) {
      setState(() {
        _isAnalyzing = false;
        _allStudents = [];
        _selectedStudentIds.clear();
        _outcomeRules = [];
        _previewStudentId = null;
        _cachedPreviewPlan = null;
        _cachedPreviewPlanKey = null;
        _planRevision++;
      });
      return;
    }

    setState(() => _isAnalyzing = true);
    try {
      final bundle = await _service.analyzeExamsAndPool(
        institutionId: widget.institutionId,
        selectedExams: exams,
        preloadedPool: _poolQuestions,
      );
      if (!mounted || runId != _analysisRunId) return;

      _poolQuestions = bundle.poolQuestions;

      // Şablondan kayıtlı minQuestions & disabled durumlarını uygula
      for (final r in bundle.outcomeRules) {
        if (_config.minQuestionsByOutcomeKey.containsKey(r.key)) {
          r.minQuestions = _config.minQuestionsByOutcomeKey[r.key]!;
        }
        if (_config.disabledOutcomeKeys.contains(r.key)) {
          r.isEnabled = false;
        }
      }

      setState(() {
        _allStudents = bundle.students;
        _outcomeRules = bundle.outcomeRules;
        _recomputeOutcomeRulePoolCounts();
        _selectedStudentIds
          ..clear()
          ..addAll(bundle.students.map((s) => s.id));
        _previewStudentId = bundle.students.isNotEmpty
            ? bundle.students.first.id
            : null;
        _config.selectedExamIds = exams.map((e) => e.id).toList();
        _config.selectedExamNames = exams.map((e) => e.name).toList();
        _cachedPreviewPlan = null;
        _cachedPreviewPlanKey = null;
        _planRevision++;
      });
    } finally {
      if (mounted && runId == _analysisRunId) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  /// Yalnızca metin alanlarını günceller (her tuş vuruşunda kural haritası kopyalamaz).
  void _syncTextControllersToConfig() {
    _config.bookTitle = _bookTitleCtrl.text.trim().isEmpty
        ? 'FOKUS KİTAP'
        : _bookTitleCtrl.text.trim();
    _config.bookSubtitle = _bookSubtitleCtrl.text.trim();
    _config.institutionDisplayName = _institutionNameCtrl.text.trim().isEmpty
        ? 'eduKN Eğitim Kurumları'
        : _institutionNameCtrl.text.trim();
    _config.manualPrefaceTitle = _prefaceTitleCtrl.text.trim();
    _config.manualPrefaceBody = _prefaceBodyCtrl.text;
    _config.manualPrefaceAuthor = _prefaceAuthorCtrl.text.trim();
  }

  /// Kazanım minQuestions ve pasif anahtarlarını `_config` üzerine senkronize eder.
  void _syncRulesToConfig() {
    _config.minQuestionsByOutcomeKey = {
      for (final r in _outcomeRules) r.key: r.minQuestions,
    };
    _config.disabledOutcomeKeys = {
      for (final r in _outcomeRules)
        if (!r.isEnabled) r.key,
    };
  }

  /// Aktif analiz paketindeki branş ve sınıf seviyeleriyle uyumlu havuz alt kümesini döndürür;
  /// böylece 2.000+ ilgisiz sınıf sorusunun görseli boşuna indirilmez.
  List<PoolQuestionItem> _getRelevantPoolForActiveBundle() {
    final activePool = _activePoolQuestions;
    if (activePool.isEmpty) return const [];
    final Set<String> activeSubjects = {
      for (final r in _outcomeRules)
        if (r.isEnabled) r.subject,
    };
    if (activeSubjects.isEmpty) {
      activeSubjects.addAll(_outcomeRules.map((r) => r.subject));
    }

    final Set<String> targetLevels = {
      for (final ex in _selectedExams)
        if (AssessmentService.normalizeClassLevel(
          ex.classLevel,
          examName: ex.name,
        ).trim().isNotEmpty)
          AssessmentService.normalizeClassLevel(
            ex.classLevel,
            examName: ex.name,
          ),
      for (final s in _allStudents)
        if (_selectedStudentIds.contains(s.id) &&
            s.classLevel.trim().isNotEmpty)
          s.classLevel,
    };

    final Set<String> selectedExamIdSet = {
      ..._selectedExamIds,
      for (final ex in _selectedExams)
        if (ex.centralExamId != null && ex.centralExamId!.trim().isNotEmpty)
          ex.centralExamId!.trim(),
    };

    final List<PoolQuestionItem> primary = [];
    final Map<String, int> countPerSub = {};

    for (final q in activePool) {
      if (activeSubjects.isNotEmpty && !activeSubjects.contains(q.subject)) {
        continue;
      }
      final bool fromSelectedExam = selectedExamIdSet.contains(q.examId);
      final bool levelOk =
          fromSelectedExam ||
          targetLevels.isEmpty ||
          q.classLevel.trim().isEmpty ||
          targetLevels.any(
            (lvl) => FokusTextUtils.classLevelsCompatible(q.classLevel, lvl),
          );
      if (levelOk) {
        primary.add(q);
        countPerSub[q.subject] = (countPerSub[q.subject] ?? 0) + 1;
      }
    }

    // Bir branşta sınıf etiketi uyuşmazlığı yüzünden çok az soru kaldıysa aynı branş yedeğini ekle
    final Set<String> starvedSubjects = {
      for (final sub in activeSubjects)
        if ((countPerSub[sub] ?? 0) < 8) sub,
    };
    if (starvedSubjects.isNotEmpty) {
      final Set<String> existingKeys = primary.map((e) => e.poolKey).toSet();
      for (final q in activePool) {
        if (starvedSubjects.contains(q.subject) &&
            !existingKeys.contains(q.poolKey)) {
          primary.add(q);
        }
      }
    }

    return primary.isNotEmpty ? primary : activePool;
  }

  PageBudgetBreakdown get _liveBudget {
    final activeRuleCount = _outcomeRules.where((r) => r.isEnabled).length;
    return _config.computeBudget(
      estimatedTocEntries: activeRuleCount > 0 ? activeRuleCount : 12,
      estimatedTotalQuestions: (_config.targetPageCount * 4).clamp(20, 220),
    );
  }

  Future<void> _goToStep(int targetStep) async {
    if (targetStep > 0 && _selectedExamIds.isEmpty) {
      _showSnack('Lütfen en az 1 değerlendirilmiş deneme sınavı seçin.');
      return;
    }
    if (targetStep > 0 && _selectedStudentIds.isEmpty) {
      _showSnack('Lütfen kitap üretilecek en az 1 öğrenci seçin.');
      return;
    }
    _syncTextControllersToConfig();
    _syncRulesToConfig();

    if (targetStep == 3) {
      if (!_liveBudget.isValid) {
        _showSnack(
          'Soru bankası alanı için en az 1 sayfa kalmalıdır! Lütfen hedef sayfa sayısını artırın.',
        );
        return;
      }
      setState(() {
        _currentStep = 3;
        _isPreparingImagesForPreview = true;
      });
      if (_previewStudentId == null ||
          !_selectedStudentIds.contains(_previewStudentId)) {
        _previewStudentId = _selectedStudentIds.first;
      }
      final relevantPool = _getRelevantPoolForActiveBundle();
      await _service.ensurePoolImagesPrepared(relevantPool);
      if (mounted) {
        setState(() {
          _isPreparingImagesForPreview = false;
          _planRevision++;
        });
      }
      return;
    }
    setState(() => _currentStep = targetStep);
  }

  void _showSnack(String msg, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isSuccess ? const Color(0xFF059669) : null,
      ),
    );
  }

  // ─── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 760;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: 'Fokus Kitap Sihirbazı',
        subtitle: 'Kişiye Özel Akıllı Soru Bankası & Kazanım Güçlendirme',
        institutionId: widget.institutionId,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: _openSaveTemplateDialog,
                icon: const Icon(Icons.bookmark_add_outlined, size: 17),
                label: Text(
                  isMobile ? 'Kaydet' : 'Şablon Kaydet',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4F46E5),
                  side: const BorderSide(color: Color(0xFFC7D2FE)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildStepperHeader(isMobile),
              Expanded(
                child: _isLoadingPool
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 14),
                            Text(
                              'Kurum ve Genel Merkez soru havuzları hazırlanıyor...',
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _buildActiveStepBody(isMobile),
              ),
              _buildBottomNavigationBar(isMobile),
            ],
          ),
          if (_isExporting) _buildExportProgressOverlay(),
        ],
      ),
    );
  }

  Widget _buildStepperHeader(bool isMobile) {
    const steps = [
      ('1', 'Deneme & Öğrenci', Icons.analytics_outlined),
      ('2', 'Kazanım & Min Soru', Icons.tune_rounded),
      ('3', 'Tasarım & Sayfa Bütçesi', Icons.auto_stories_outlined),
      ('4', 'Önizleme & Üretim', Icons.picture_as_pdf_outlined),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 24,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(steps.length, (index) {
                final s = steps[index];
                final isActive = _currentStep == index;
                final isCompleted = _currentStep > index;
                return Row(
                  children: [
                    InkWell(
                      onTap: () => _goToStep(index),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF4F46E5)
                              : (isCompleted
                                    ? const Color(0xFFEEF2FF)
                                    : const Color(0xFFF8FAFC)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive
                                ? const Color(0xFF4F46E5)
                                : (isCompleted
                                      ? const Color(0xFFC7D2FE)
                                      : const Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isActive
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : (isCompleted
                                          ? const Color(0xFF4F46E5)
                                          : const Color(0xFFE2E8F0)),
                                shape: BoxShape.circle,
                              ),
                              child: isCompleted
                                  ? const Icon(
                                      Icons.check_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    )
                                  : Text(
                                      s.$1,
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: isActive
                                            ? Colors.white
                                            : const Color(0xFF475569),
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              s.$2,
                              style: GoogleFonts.inter(
                                fontSize: 12.8,
                                fontWeight: FontWeight.w700,
                                color: isActive
                                    ? Colors.white
                                    : (isCompleted
                                          ? const Color(0xFF3730A3)
                                          : const Color(0xFF64748B)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (index < steps.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: Colors.grey.shade400,
                        ),
                      ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveStepBody(bool isMobile) {
    switch (_currentStep) {
      case 0:
        return _buildStep1ExamsAndStudents(isMobile);
      case 1:
        return _buildStep2OutcomesAndRules(isMobile);
      case 2:
        return _buildStep3DesignAndBudget(isMobile);
      case 3:
        return _buildStep4PreviewAndExport(isMobile);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBottomNavigationBar(bool isMobile) {
    final budget = _liveBudget;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 24,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Row(
            children: [
              if (_currentStep > 0)
                OutlinedButton.icon(
                  onPressed: () => _goToStep(_currentStep - 1),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text(isMobile ? 'Geri' : 'Önceki Adım'),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              if (!isMobile)
                Expanded(
                  child: Text(
                    'Seçili: ${_selectedExamIds.length} Deneme  •  ${_selectedStudentIds.length} Öğrenci  •  Havuz: ${_activePoolQuestions.length} Soru  •  Hedef: ${_config.targetPageCount} Sayfa (${budget.remainingQuestionPages} Soru Sayfası)',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: budget.isValid
                          ? const Color(0xFF475569)
                          : const Color(0xFFDC2626),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              if (_currentStep < 3)
                Flexible(
                  child: FilledButton.icon(
                    onPressed: () => _goToStep(_currentStep + 1),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(
                      _currentStep == 2
                          ? (isMobile
                                ? 'Önizleme & Üretim'
                                : 'Önizleme & Üretime Geç')
                          : 'Devam Et',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 14 : 20,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── ADIM 1: DENEME(LER) VE ÖĞRENCİ SEÇİMİ + CANLI KAZANIM KARNESİ ─────────

  Widget _buildStep1ExamsAndStudents(bool isMobile) {
    final evaluatedExams = widget.availableExams
        .where((e) => e.resultsJson != null && e.resultsJson!.trim().isNotEmpty)
        .toList();

    final classLevels = <String>{
      for (final e in evaluatedExams)
        AssessmentService.normalizeClassLevel(e.classLevel, examName: e.name),
    }.toList()..sort();

    final filteredExams = evaluatedExams.where((e) {
      if (_examClassFilter != null) {
        final norm = AssessmentService.normalizeClassLevel(
          e.classLevel,
          examName: e.name,
        );
        if (norm != _examClassFilter) return false;
      }
      if (_examSearchQuery.trim().isNotEmpty) {
        final q = _examSearchQuery.trim().toLowerCase();
        if (!('${e.name} ${e.examTypeName} ${e.classLevel}')
            .toLowerCase()
            .contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    final branches = <String>{for (final s in _allStudents) s.branch}.toList()
      ..sort();

    final filteredStudents = _allStudents.where((s) {
      if (_studentBranchFilter != null && s.branch != _studentBranchFilter) {
        return false;
      }
      if (_studentBandFilter != null && s.overallBand != _studentBandFilter) {
        return false;
      }
      if (_studentSearchQuery.trim().isNotEmpty) {
        final q = _studentSearchQuery.trim().toLowerCase();
        if (!('${s.name} ${s.studentNo} ${s.branch}').toLowerCase().contains(
          q,
        )) {
          return false;
        }
      }
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Değerlendirilmiş Deneme Seçim Kartı
              _sectionCard(
                icon: Icons.fact_check_outlined,
                title: '1. Analiz Edilecek Deneme Sınavlarını Seçin',
                subtitle:
                    'Birden fazla deneme seçtiğinizde öğrencilerin tüm denemelerdeki birleşik kazanım hakimiyeti hesaplanır.',
                trailing: _selectedExamIds.isNotEmpty
                    ? Chip(
                        backgroundColor: const Color(0xFFEEF2FF),
                        label: Text(
                          '${_selectedExamIds.length} Deneme Seçili',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF4F46E5),
                          ),
                        ),
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ChoiceChip(
                          label: const Text('Tüm Sınıflar'),
                          selected: _examClassFilter == null,
                          onSelected: (_) =>
                              setState(() => _examClassFilter = null),
                        ),
                        for (final lvl in classLevels)
                          ChoiceChip(
                            label: Text(lvl),
                            selected: _examClassFilter == lvl,
                            onSelected: (_) => setState(
                              () => _examClassFilter = _examClassFilter == lvl
                                  ? null
                                  : lvl,
                            ),
                          ),
                        SizedBox(
                          width: 240,
                          child: TextField(
                            onChanged: (v) =>
                                setState(() => _examSearchQuery = v),
                            decoration: InputDecoration(
                              hintText: 'Deneme ara...',
                              prefixIcon: const Icon(Icons.search, size: 18),
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              border: _fieldBorder(const Color(0xFFCBD5E1)),
                              enabledBorder: _fieldBorder(
                                const Color(0xFFCBD5E1),
                              ),
                              focusedBorder: _fieldBorder(
                                const Color(0xFF4F46E5),
                                1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (filteredExams.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Text(
                          'Değerlendirilmiş (sonuçları hesaplanmış) deneme sınavı bulunamadı.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 250),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filteredExams.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) {
                            final ex = filteredExams[idx];
                            final selected = _selectedExamIds.contains(ex.id);
                            final dStr =
                                '${ex.date.day.toString().padLeft(2, '0')}.${ex.date.month.toString().padLeft(2, '0')}.${ex.date.year}';
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  if (selected) {
                                    _selectedExamIds.remove(ex.id);
                                  } else {
                                    _selectedExamIds.add(ex.id);
                                  }
                                });
                                _runAnalysis();
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(0xFFEEF2FF)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected
                                        ? const Color(0xFF4F46E5)
                                        : Colors.grey.shade200,
                                    width: selected ? 1.6 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: selected,
                                      activeColor: const Color(0xFF4F46E5),
                                      onChanged: (_) {
                                        setState(() {
                                          if (selected) {
                                            _selectedExamIds.remove(ex.id);
                                          } else {
                                            _selectedExamIds.add(ex.id);
                                          }
                                        });
                                        _runAnalysis();
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE0E7FF),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        AssessmentService.normalizeClassLevel(
                                          ex.classLevel,
                                          examName: ex.name,
                                        ),
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF3730A3),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            ex.name,
                                            style: GoogleFonts.inter(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF0F172A),
                                            ),
                                          ),
                                          Text(
                                            '${ex.examTypeName}  •  $dStr',
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              color: const Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (ex.isCentralExam)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade50,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: Colors.amber.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          'Genel Merkez',
                                          style: GoogleFonts.inter(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.amber.shade900,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. Katılımcı Öğrenciler & Canlı Kazanım Karnesi
              _sectionCard(
                icon: Icons.groups_2_outlined,
                title: '2. Öğrenci Seçimi & Canlı Kazanım Karnesi İnceleme',
                subtitle:
                    'Her öğrencinin yanındaki "Kazanım Karnesi" butonuyla ders ve kazanım bazlı hakimiyet yüzdelerini inceleyebilirsiniz.',
                trailing: _allStudents.isNotEmpty
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                for (final s in filteredStudents) {
                                  _selectedStudentIds.add(s.id);
                                }
                                _planRevision++;
                              });
                            },
                            child: const Text('Filtreyi Seç'),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _selectedStudentIds.clear();
                              _planRevision++;
                            }),
                            child: const Text('Temizle'),
                          ),
                        ],
                      )
                    : null,
                child: _isAnalyzing
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _selectedExamIds.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'Öğrenci kazanım profillerini hesaplamak için yukarıdan en az 1 deneme sınavı seçin.',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Filtre Çubuğu
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ChoiceChip(
                                label: Text(
                                  'Tüm Şubeler (${_allStudents.length})',
                                ),
                                selected: _studentBranchFilter == null,
                                onSelected: (_) =>
                                    setState(() => _studentBranchFilter = null),
                              ),
                              for (final br in branches)
                                ChoiceChip(
                                  label: Text(br),
                                  selected: _studentBranchFilter == br,
                                  onSelected: (_) => setState(
                                    () => _studentBranchFilter =
                                        _studentBranchFilter == br ? null : br,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              for (final band in MasteryBand.values)
                                FilterChip(
                                  label: Text(band.shortLabel),
                                  selected: _studentBandFilter == band,
                                  selectedColor: band.color.withValues(
                                    alpha: 0.16,
                                  ),
                                  onSelected: (_) => setState(
                                    () => _studentBandFilter =
                                        _studentBandFilter == band
                                        ? null
                                        : band,
                                  ),
                                ),
                              SizedBox(
                                width: 220,
                                child: TextField(
                                  onChanged: (v) =>
                                      setState(() => _studentSearchQuery = v),
                                  decoration: InputDecoration(
                                    hintText: 'Öğrenci adı / no ara...',
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      size: 18,
                                    ),
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    border: _fieldBorder(
                                      const Color(0xFFCBD5E1),
                                    ),
                                    enabledBorder: _fieldBorder(
                                      const Color(0xFFCBD5E1),
                                    ),
                                    focusedBorder: _fieldBorder(
                                      const Color(0xFF4F46E5),
                                      1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 420),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: filteredStudents.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (ctx, idx) {
                                final st = filteredStudents[idx];
                                final isSel = _selectedStudentIds.contains(
                                  st.id,
                                );
                                final band = st.overallBand;
                                return LayoutBuilder(
                                  builder: (ctx, rowConstraints) {
                                    final bool narrowRow =
                                        rowConstraints.maxWidth < 640;
                                    final Widget bandBadge = Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: band.color.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        band.shortLabel,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: band.color,
                                        ),
                                      ),
                                    );
                                    final Widget
                                    karneButton = OutlinedButton.icon(
                                      onPressed: () =>
                                          _showStudentKarnesiDialog(st),
                                      icon: const Icon(
                                        Icons.insights_rounded,
                                        size: 16,
                                      ),
                                      label: Text(
                                        narrowRow || isMobile
                                            ? 'Karne'
                                            : 'Kazanım Karnesi',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        foregroundColor: const Color(
                                          0xFF4F46E5,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFFC7D2FE),
                                        ),
                                      ),
                                    );
                                    final Widget studentDetails = Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              st.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFF0F172A),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1F5F9),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '${st.classLevel} / ${st.branch}${st.studentNo.isNotEmpty ? ' • No: ${st.studentNo}' : ''}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: const Color(
                                                    0xFF475569,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 4,
                                          children: [
                                            Text(
                                              'Genel Hakimiyet: %${st.overallAbilityPercent.toStringAsFixed(0)} (${st.totalCorrect}D / ${st.totalWrong}Y / ${st.totalEmpty}B)',
                                              style: GoogleFonts.inter(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: band.color,
                                              ),
                                            ),
                                            Text(
                                              '• Güçlendirilecek Kazanım: ${st.weakOutcomeCount}  •  %100 Tam Kazanım: ${st.fullMasteryOutcomeCount}',
                                              style: GoogleFonts.inter(
                                                fontSize: 11.5,
                                                color: const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (narrowRow) ...[
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [bandBadge, karneButton],
                                          ),
                                        ],
                                      ],
                                    );

                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSel
                                            ? const Color(0xFFF8FAFF)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSel
                                              ? const Color(0xFF818CF8)
                                              : Colors.grey.shade200,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: narrowRow
                                            ? CrossAxisAlignment.start
                                            : CrossAxisAlignment.center,
                                        children: [
                                          Checkbox(
                                            value: isSel,
                                            activeColor: const Color(
                                              0xFF4F46E5,
                                            ),
                                            onChanged: (val) {
                                              setState(() {
                                                if (val == true) {
                                                  _selectedStudentIds.add(
                                                    st.id,
                                                  );
                                                } else {
                                                  _selectedStudentIds.remove(
                                                    st.id,
                                                  );
                                                }
                                                _planRevision++;
                                              });
                                            },
                                          ),
                                          Expanded(child: studentDetails),
                                          if (!narrowRow) ...[
                                            const SizedBox(width: 8),
                                            bandBadge,
                                            const SizedBox(width: 8),
                                            karneButton,
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStudentKarnesiDialog(StudentMasteryProfile st) {
    final outcomes = st.weakestOutcomes;
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740, maxHeight: 680),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.psychology_alt_rounded,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${st.name} — Canlı Kazanım Karnesi',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              '${st.classLevel} / ${st.branch}  •  Genel Hakimiyet: %${st.overallAbilityPercent.toStringAsFixed(1)} (${st.overallBand.label})',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  // Branş Özet Kartları
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: st.subjectStats.values.map((sub) {
                        return Container(
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sub.subject,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '%${sub.masteryPercent.toStringAsFixed(0)}  •  ${sub.correct}D ${sub.wrong}Y ${sub.empty}B',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF4F46E5),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Kazanım Bazlı Analiz ve Adaptif Soru Zorluk Eşleşmesi (${outcomes.length} Kazanım)',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: outcomes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final o = outcomes[i];
                        final b = o.band;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 135,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    o.subject,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF3730A3),
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
                                      o.outcome,
                                      style: GoogleFonts.inter(
                                        fontSize: 12.2,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      'Sorulan: ${o.totalAsked}  •  ${o.correct} Doğru, ${o.wrong} Yanlış, ${o.empty} Boş  •  Hedef Soru Seviyesi: ${b.label}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: b.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '%${o.masteryPercent.toStringAsFixed(0)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: b.color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── ADIM 2: KONU / KAZANIM DAĞILIMI & MİNİMUM SORU KURALLARI ──────────────

  Widget _buildStep2OutcomesAndRules(bool isMobile) {
    final subjects = <String>{for (final r in _outcomeRules) r.subject}.toList()
      ..sort(
        (a, b) => FokusTextUtils.subjectSortRank(
          a,
        ).compareTo(FokusTextUtils.subjectSortRank(b)),
      );

    final visibleRules = _outcomeRules.where((r) {
      if (_ruleSubjectFilter != null && r.subject != _ruleSubjectFilter) {
        return false;
      }
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // %100 Başarı Sıfır Soru Kuralı Kartı
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEEF2FF), Color(0xFFF5F3FF)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.bolt_rounded,
                          color: Color(0xFF4F46E5),
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '%100 Başarıda (Min=0 ise) Soru Sorma Kuralı',
                                style: GoogleFonts.inter(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1E1B4B),
                                ),
                              ),
                              Text(
                                'Minimum soru sayısı 0 olan bir kazanımda öğrenci tam başarı (%100 veya seçili eşik) sağlamışsa o kazanımdan 0 soru çekilir; sayfa bütçesi öğrencinin eksik kazanımlarına aktarılır! Min > 0 verirseniz her koşulda en az o kadar soru eklenir.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF4338CA),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _config.skipZeroMinOnHighMastery,
                          activeThumbColor: const Color(0xFF4F46E5),
                          onChanged: (v) => setState(() {
                            _config.skipZeroMinOnHighMastery = v;
                            _planRevision++;
                          }),
                        ),
                      ],
                    ),
                    if (_config.skipZeroMinOnHighMastery) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Muafiyet Başarı Eşiği:',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF312E81),
                            ),
                          ),
                          for (final th in [100.0, 90.0, 85.0, 80.0])
                            ChoiceChip(
                              label: Text(
                                th == 100.0
                                    ? '%100 (Tam Başarı)'
                                    : '%${th.toInt()}+ Başarı',
                              ),
                              selected: _config.highMasteryZeroThreshold == th,
                              onSelected: (_) => setState(() {
                                _config.highMasteryZeroThreshold = th;
                                _planRevision++;
                              }),
                            ),
                        ],
                      ),
                    ],
                    const Divider(height: 22),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'Kazanım Havuzu Yetmezse Aynı Branşın Diğer Sorularından Seviyeye Uygun Tamamla',
                        style: GoogleFonts.inter(
                          fontSize: 12.8,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      subtitle: Text(
                        'Kazanım metni ufak farklılık içerdiğinde öğrencinin sayfasının boş kalmaması için aynı branştan uygun zorlukta soru seçer.',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      value: _config.allowSubjectFallbackWhenOutcomePoolShort,
                      activeThumbColor: const Color(0xFF4F46E5),
                      onChanged: (v) => setState(() {
                        _config.allowSubjectFallbackWhenOutcomePoolShort = v;
                        _planRevision++;
                      }),
                    ),
                    const Divider(height: 22),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'Egzersiz Sorularını da Ekle',
                        style: GoogleFonts.inter(
                          fontSize: 12.8,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      subtitle: Text(
                        'Varsayılan olarak kapalıdır. Açtığınızda soru havuzundaki Egzersiz / Etkinlik soruları da (${_poolQuestions.where((q) => q.isExerciseQuestion).length} soru) Fokus Kitap havuzuna dahil edilir.',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      value: _config.includeExerciseQuestions,
                      activeThumbColor: const Color(0xFF4F46E5),
                      onChanged: (v) => setState(() {
                        _config.includeExerciseQuestions = v;
                        _recomputeOutcomeRulePoolCounts();
                        _cachedPreviewPlan = null;
                        _cachedPreviewPlanKey = null;
                        _planRevision++;
                      }),
                    ),
                    const Divider(height: 22),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'Deneme Sorularını da Ekle',
                        style: GoogleFonts.inter(
                          fontSize: 12.8,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      subtitle: Text(
                        'Varsayılan olarak kapalıdır. Açtığınızda Deneme Sınavları / Hata Kitapçığı havuzundaki sorular da (${_poolQuestions.where((q) => q.isTrialExamQuestion).length} soru) Fokus Kitap havuzuna dahil edilir.',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      value: _config.includeTrialExamQuestions,
                      activeThumbColor: const Color(0xFF4F46E5),
                      onChanged: (v) => setState(() {
                        _config.includeTrialExamQuestions = v;
                        _recomputeOutcomeRulePoolCounts();
                        _cachedPreviewPlan = null;
                        _cachedPreviewPlanKey = null;
                        _planRevision++;
                      }),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Adaptif Soru Zorluk Ağırlıkları (StatefulBuilder ile izole 60 FPS Slider)
              StatefulBuilder(
                builder: (ctx, setSliderState) {
                  Widget difficultySlider({
                    required String label,
                    required String subtitle,
                    required Color color,
                    required double value,
                    required ValueChanged<double> onChanged,
                    required ValueChanged<double> onChangeEnd,
                  }) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$label  •  $subtitle',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 12.2,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${value.toStringAsFixed(1)}x',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SliderTheme(
                            data: SliderTheme.of(ctx).copyWith(
                              activeTrackColor: color,
                              thumbColor: color,
                              overlayColor: color.withValues(alpha: 0.14),
                              inactiveTrackColor: color.withValues(alpha: 0.18),
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: value.clamp(0.2, 2.0),
                              min: 0.2,
                              max: 2.0,
                              divisions: 18,
                              onChanged: onChanged,
                              onChangeEnd: onChangeEnd,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final activePool = _activePoolQuestions;
                  final int cVeryEasy = activePool
                      .where(
                        (q) => DifficultyScale.labelOf(q.difficulty) == 'Çok Kolay',
                      )
                      .length;
                  final int cEasy = activePool
                      .where(
                        (q) => DifficultyScale.labelOf(q.difficulty) == 'Kolay',
                      )
                      .length;
                  final int cMedium = activePool
                      .where(
                        (q) => DifficultyScale.labelOf(q.difficulty) == 'Orta',
                      )
                      .length;
                  final int cHard = activePool
                      .where(
                        (q) => DifficultyScale.labelOf(q.difficulty) == 'Zor',
                      )
                      .length;
                  final int cVeryHard = activePool
                      .where(
                        (q) => DifficultyScale.labelOf(q.difficulty) == 'Çok Zor',
                      )
                      .length;

                  return _sectionCard(
                    icon: Icons.tune_rounded,
                    title:
                        'Adaptif Soru Zorluk Ağırlıkları (5 Kademe: Çok Kolay / Kolay / Orta / Zor / Çok Zor)',
                    subtitle:
                        'Hata Kitapçığı ve Soru Havuzu ile uyumlu 5 kademeli zorluk sisteminde her kademenin seçilme önceliğini ayarlayın.',
                    trailing: TextButton(
                      onPressed: () {
                        setSliderState(() {
                          _config.veryEasyDifficultyWeight = 1.0;
                          _config.easyDifficultyWeight = 1.0;
                          _config.mediumDifficultyWeight = 1.0;
                          _config.hardDifficultyWeight = 1.0;
                          _config.veryHardDifficultyWeight = 1.0;
                          _planRevision++;
                        });
                      },
                      child: const Text('Varsayılan (1.0x)'),
                    ),
                    child: Column(
                      children: [
                        difficultySlider(
                          label: '1. Kademe — Çok Kolay',
                          subtitle:
                              'Havuzda $cVeryEasy soru (%81-100 başarı • Egzersiz & başlangıç)',
                          color: DifficultyScale.colorForLabel('Çok Kolay'),
                          value: _config.veryEasyDifficultyWeight,
                          onChanged: (v) => setSliderState(
                            () => _config.veryEasyDifficultyWeight = v,
                          ),
                          onChangeEnd: (_) => _planRevision++,
                        ),
                        difficultySlider(
                          label: '2. Kademe — Kolay',
                          subtitle:
                              'Havuzda $cEasy soru (%61-80 başarı • Kavrama ve temel kazanım)',
                          color: DifficultyScale.colorForLabel('Kolay'),
                          value: _config.easyDifficultyWeight,
                          onChanged: (v) => setSliderState(
                            () => _config.easyDifficultyWeight = v,
                          ),
                          onChangeEnd: (_) => _planRevision++,
                        ),
                        difficultySlider(
                          label: '3. Kademe — Orta',
                          subtitle:
                              'Havuzda $cMedium soru (%41-60 başarı • Dengeli deneme ve uygulama)',
                          color: DifficultyScale.colorForLabel('Orta'),
                          value: _config.mediumDifficultyWeight,
                          onChanged: (v) => setSliderState(
                            () => _config.mediumDifficultyWeight = v,
                          ),
                          onChangeEnd: (_) => _planRevision++,
                        ),
                        difficultySlider(
                          label: '4. Kademe — Zor',
                          subtitle:
                              'Havuzda $cHard soru (%21-40 başarı • Seçici ve analitik sorular)',
                          color: DifficultyScale.colorForLabel('Zor'),
                          value: _config.hardDifficultyWeight,
                          onChanged: (v) => setSliderState(
                            () => _config.hardDifficultyWeight = v,
                          ),
                          onChangeEnd: (_) => _planRevision++,
                        ),
                        difficultySlider(
                          label: '5. Kademe — Çok Zor',
                          subtitle:
                              'Havuzda $cVeryHard soru (%0-20 başarı • Üst düzey muhakeme & derece)',
                          color: DifficultyScale.colorForLabel('Çok Zor'),
                          value: _config.veryHardDifficultyWeight,
                          onChanged: (v) => setSliderState(
                            () => _config.veryHardDifficultyWeight = v,
                          ),
                          onChangeEnd: (_) => _planRevision++,
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 18),

              // Kazanım Tablosu ve Toplu Kural Araç Çubuğu
              _sectionCard(
                icon: Icons.rule_folder_outlined,
                title:
                    'Konu / Kazanım Dağılımı & Minimum Soru Kuralları (${_outcomeRules.length} Kazanım)',
                subtitle:
                    'Her kazanım için minimum soru alt sınırını (0, 1, 2...) belirleyin. Kalan sayfa bütçesi öğrencinin zayıf kazanımlarına otomatik dağıtılır.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Toplu İşlem Butonları
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _presetButton(
                          label: 'Tümüne Min 0 Ver',
                          icon: Icons.exposure_zero_rounded,
                          onTap: () => setState(() {
                            for (final r in visibleRules) {
                              r.minQuestions = 0;
                            }
                            _planRevision++;
                          }),
                        ),
                        _presetButton(
                          label: 'Tümüne Min 1 Ver',
                          icon: Icons.looks_one_outlined,
                          onTap: () => setState(() {
                            for (final r in visibleRules) {
                              r.minQuestions = 1;
                            }
                            _planRevision++;
                          }),
                        ),
                        _presetButton(
                          label: 'Tümüne Min 2 Ver',
                          icon: Icons.looks_two_outlined,
                          onTap: () => setState(() {
                            for (final r in visibleRules) {
                              r.minQuestions = 2;
                            }
                            _planRevision++;
                          }),
                        ),
                        _presetButton(
                          label: 'Sadece Havuzda Sorusu Olanları Aktif Et',
                          icon: Icons.filter_alt_outlined,
                          onTap: () => setState(() {
                            for (final r in _outcomeRules) {
                              r.isEnabled =
                                  _config
                                      .allowSubjectFallbackWhenOutcomePoolShort
                                  ? (r.poolExactCount > 0 ||
                                        r.poolSubjectTotalCount > 0)
                                  : (r.poolExactCount > 0);
                            }
                            _planRevision++;
                          }),
                        ),
                        _presetButton(
                          label: 'Tümünü Aktif Et',
                          icon: Icons.done_all_rounded,
                          onTap: () => setState(() {
                            for (final r in _outcomeRules) {
                              r.isEnabled = true;
                            }
                            _planRevision++;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Branş Filtresi
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text(
                              'Tüm Branşlar (${_outcomeRules.length})',
                            ),
                            selected: _ruleSubjectFilter == null,
                            onSelected: (_) =>
                                setState(() => _ruleSubjectFilter = null),
                          ),
                          for (final sub in subjects)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ChoiceChip(
                                label: Text(
                                  '$sub (${_outcomeRules.where((x) => x.subject == sub).length})',
                                ),
                                selected: _ruleSubjectFilter == sub,
                                onSelected: (_) => setState(
                                  () => _ruleSubjectFilter =
                                      _ruleSubjectFilter == sub ? null : sub,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 460),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: visibleRules.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, idx) {
                          final r = visibleRules[idx];
                          final hasExact = r.poolExactCount > 0;
                          return LayoutBuilder(
                            builder: (_, ruleConstraints) {
                              final bool compactRuleRow =
                                  ruleConstraints.maxWidth < 660;
                              final Widget subjectBadge = ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: compactRuleRow ? 170 : 150,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    r.subject,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF3730A3),
                                    ),
                                  ),
                                ),
                              );
                              final Widget minStepper = Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: r.minQuestions > 0
                                        ? const Color(0xFF4F46E5)
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Min:',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.remove_rounded,
                                        size: 16,
                                      ),
                                      onPressed: r.minQuestions > 0
                                          ? () => setState(() {
                                              r.minQuestions--;
                                              _planRevision++;
                                            })
                                          : null,
                                    ),
                                    SizedBox(
                                      width: 22,
                                      child: Text(
                                        '${r.minQuestions}',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: r.minQuestions > 0
                                              ? const Color(0xFF4F46E5)
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(
                                        Icons.add_rounded,
                                        size: 16,
                                      ),
                                      onPressed: r.minQuestions < 20
                                          ? () => setState(() {
                                              r.minQuestions++;
                                              _planRevision++;
                                            })
                                          : null,
                                    ),
                                  ],
                                ),
                              );
                              final Widget outcomeDetails = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.outcome,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: r.isEnabled
                                          ? const Color(0xFF0F172A)
                                          : Colors.grey.shade500,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        'Denemede: ${r.examQuestionCount} soru',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                      Text(
                                        hasExact
                                            ? 'Havuz Eşleşen: ${r.poolExactCount} soru'
                                            : 'Branş Havuzu: ${r.poolSubjectTotalCount} soru',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: hasExact
                                              ? const Color(0xFF059669)
                                              : (r.poolSubjectTotalCount > 0
                                                    ? const Color(0xFFD97706)
                                                    : Colors.grey),
                                        ),
                                      ),
                                      Text(
                                        'Sınıf Ort: %${r.avgClassMastery.toStringAsFixed(0)}',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: r.avgClassMastery < 50
                                              ? const Color(0xFFDC2626)
                                              : const Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: r.isEnabled
                                      ? Colors.white
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                                child: compactRuleRow
                                    ? Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Checkbox(
                                                value: r.isEnabled,
                                                activeColor: const Color(
                                                  0xFF4F46E5,
                                                ),
                                                onChanged: (v) => setState(() {
                                                  r.isEnabled = v ?? true;
                                                  _planRevision++;
                                                }),
                                              ),
                                              Flexible(child: subjectBadge),
                                              const Spacer(),
                                              minStepper,
                                            ],
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8,
                                              top: 4,
                                            ),
                                            child: outcomeDetails,
                                          ),
                                        ],
                                      )
                                    : Row(
                                        children: [
                                          Checkbox(
                                            value: r.isEnabled,
                                            activeColor: const Color(
                                              0xFF4F46E5,
                                            ),
                                            onChanged: (v) => setState(() {
                                              r.isEnabled = v ?? true;
                                              _planRevision++;
                                            }),
                                          ),
                                          subjectBadge,
                                          const SizedBox(width: 10),
                                          Expanded(child: outcomeDetails),
                                          const SizedBox(width: 8),
                                          minStepper,
                                        ],
                                      ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF334155),
        side: BorderSide(color: Colors.grey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─── ADIM 3: KİTAP TASARIMI, SAYFA SAYISI & CANLI SAYFA BÜTÇESİ ────────────

  Widget _buildStep3DesignAndBudget(bool isMobile) {
    final budget = _liveBudget;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. SAYFA SAYISI VE CANLI SAYFA BÜTÇESİ
              _sectionCard(
                icon: Icons.pie_chart_outline_rounded,
                title:
                    '1. Hedef Sayfa Sayısı & Canlı Sayfa Bütçesi (Page Budget)',
                subtitle:
                    'Kapak, Ön Söz (manuel veya yüklenen PDF sayfa adedi), İçindekiler ve Cevap Anahtarı düşüldükten sonra kalan net soru bankası sayfası canlı hesaplanır.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final p in _quickPagePresets)
                          ChoiceChip(
                            label: Text('$p Sayfa'),
                            selected: _config.targetPageCount == p,
                            onSelected: (_) => _updateTargetPages(p),
                          ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_rounded,
                                  size: 18,
                                ),
                                onPressed: _config.targetPageCount > 4
                                    ? () => _updateTargetPages(
                                        _config.targetPageCount - 2,
                                      )
                                    : null,
                              ),
                              SizedBox(
                                width: 58,
                                child: TextField(
                                  controller: _pageCountCtrl,
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                  onChanged: (v) {
                                    final parsed = int.tryParse(v);
                                    if (parsed != null &&
                                        parsed >= 2 &&
                                        parsed <= 240) {
                                      setState(() {
                                        _config.targetPageCount = parsed;
                                        _planRevision++;
                                      });
                                    }
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_rounded, size: 18),
                                onPressed: _config.targetPageCount < 240
                                    ? () => _updateTargetPages(
                                        _config.targetPageCount + 2,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Görsel Segmented Sayfa Bütçesi Barı
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        height: 20,
                        child: Row(
                          children: [
                            if (budget.coverPages > 0)
                              Expanded(
                                flex: budget.coverPages,
                                child: Container(
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                            if (budget.prefacePages > 0)
                              Expanded(
                                flex: budget.prefacePages,
                                child: Container(
                                  color: const Color(0xFF7C3AED),
                                ),
                              ),
                            if (budget.tocPages > 0)
                              Expanded(
                                flex: budget.tocPages,
                                child: Container(
                                  color: const Color(0xFF0284C7),
                                ),
                              ),
                            if (budget.remainingQuestionPages > 0)
                              Expanded(
                                flex: budget.remainingQuestionPages,
                                child: Container(
                                  color: const Color(0xFF059669),
                                ),
                              ),
                            if (budget.answerKeyPages > 0)
                              Expanded(
                                flex: budget.answerKeyPages,
                                child: Container(
                                  color: const Color(0xFFD97706),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _budgetBadge(
                          'Kapak',
                          '${budget.coverPages} syf',
                          const Color(0xFF1E293B),
                        ),
                        _budgetBadge(
                          'Ön Söz',
                          '${budget.prefacePages} syf',
                          const Color(0xFF7C3AED),
                        ),
                        _budgetBadge(
                          'İçindekiler',
                          '${budget.tocPages} syf',
                          const Color(0xFF0284C7),
                        ),
                        _budgetBadge(
                          'Soru Bankası Alanı',
                          '${budget.remainingQuestionPages} syf',
                          budget.isValid
                              ? const Color(0xFF059669)
                              : const Color(0xFFDC2626),
                          boldHighlight: true,
                        ),
                        _budgetBadge(
                          'Cevap Anahtarı',
                          '${budget.answerKeyPages} syf',
                          const Color(0xFFD97706),
                        ),
                      ],
                    ),
                    if (!budget.isValid) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFDC2626),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Sabit sayfalar (${budget.fixedPages} sayfa) hedef sayfa sayısını aşıyor! Soru bankası için en az 1 sayfa kalmalıdır.',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF991B1B),
                                ),
                              ),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  _updateTargetPages(budget.fixedPages + 12),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                              ),
                              child: Text(
                                '${budget.fixedPages + 12} Sayfa Yap',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'Havuz Sorusu Erken Tükenirse "Öğrenci Çözüm & Kazanım Not Alanı" ile Tam Hedef Sayfaya Tamamla',
                        style: GoogleFonts.inter(
                          fontSize: 12.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      value: _config.padShortBooksWithStudyNotes,
                      activeThumbColor: const Color(0xFF4F46E5),
                      onChanged: (v) => setState(() {
                        _config.padShortBooksWithStudyNotes = v;
                        _planRevision++;
                      }),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. KAPAK TASARIMI VE TEMALAR
              _sectionCard(
                icon: Icons.palette_outlined,
                title: '2. Kitap Kapağı & 5 Vektörel Kapak Teması',
                subtitle:
                    'Öğrencinin adı, sınıf/şube, numara, deneme özeti ve kişisel kazanım hakimiyet rozeti kapakta yer alır.',
                trailing: Switch(
                  value: _config.includeCover,
                  activeThumbColor: const Color(0xFF4F46E5),
                  onChanged: (v) => setState(() {
                    _config.includeCover = v;
                    _planRevision++;
                  }),
                ),
                child: !_config.includeCover
                    ? Text(
                        'Kitap kapağı devre dışı bırakıldı (0 sayfa).',
                        style: GoogleFonts.inter(color: Colors.grey.shade600),
                      )
                    : LayoutBuilder(
                        builder: (_, coverConstraints) {
                          final double maxW = coverConstraints.maxWidth;
                          final double themeCardW = maxW < 450
                              ? maxW
                              : math.min(205.0, (maxW - 12) / 2);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: CoverThemePreset.values.map((theme) {
                                  final selected = _config.coverTheme == theme;
                                  return InkWell(
                                    onTap: () => setState(() {
                                      _config.coverTheme = theme;
                                      _planRevision++;
                                    }),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      width: maxW >= 660 ? 205 : themeCardW,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: selected
                                              ? const Color(0xFF4F46E5)
                                              : Colors.grey.shade200,
                                          width: selected ? 2.2 : 1.0,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            height: 44,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  theme.primaryColor,
                                                  theme.secondaryColor,
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            alignment: Alignment.bottomRight,
                                            padding: const EdgeInsets.all(6),
                                            child: Container(
                                              width: 24,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: theme.accentColor,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            theme.label,
                                            style: GoogleFonts.inter(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFF0F172A),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            theme.subtitle,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 10.8,
                                              color: const Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 14,
                                runSpacing: 12,
                                children: [
                                  SizedBox(
                                    width: math.min(320.0, maxW),
                                    child: _labeledField(
                                      'Kitap Başlığı',
                                      _bookTitleCtrl,
                                    ),
                                  ),
                                  SizedBox(
                                    width: math.min(420.0, maxW),
                                    child: _labeledField(
                                      'Alt Başlık',
                                      _bookSubtitleCtrl,
                                    ),
                                  ),
                                  SizedBox(
                                    width: math.min(320.0, maxW),
                                    child: _labeledField(
                                      'Kurum Adı',
                                      _institutionNameCtrl,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Flexible(
                                    child: OutlinedButton.icon(
                                      onPressed: _pickCustomCoverImage,
                                      icon: const Icon(
                                        Icons.image_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        _config.customCoverImageBytes == null
                                            ? 'Özel Kapak Görseli Yükle (PNG/JPG)'
                                            : 'Kapak Görselini Değiştir (${_config.customCoverImageName ?? 'Görsel'})',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  if (_config.customCoverImageBytes !=
                                      null) ...[
                                    const SizedBox(width: 10),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        _config.customCoverImageBytes!,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Görseli Kaldır',
                                      onPressed: () => setState(() {
                                        _config.customCoverImageBytes = null;
                                        _config.customCoverImageName = null;
                                        _planRevision++;
                                      }),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          );
                        },
                      ),
              ),

              const SizedBox(height: 20),

              // 3. ÖN SÖZ (YOK / MANUEL METİN / EK PDF YÜKLE)
              _sectionCard(
                icon: Icons.history_edu_rounded,
                title: '3. Ön Söz Yapılandırması (Yok / Manuel / Ek PDF Yükle)',
                subtitle:
                    'Dinamik yer tutuculu manuel ön söz yazabilir veya çok sayfalı hazır bir PDF dosyasını doğrudan kapağın arkasına ekleyebilirsiniz.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: PrefaceMode.values.map((mode) {
                        return ChoiceChip(
                          label: Text(mode.label),
                          selected: _config.prefaceMode == mode,
                          onSelected: (_) => setState(() {
                            _config.prefaceMode = mode;
                            _planRevision++;
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    if (_config.prefaceMode == PrefaceMode.manual) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Dinamik Değişken Ekle:',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF475569),
                            ),
                          ),
                          for (final tag in [
                            '{ogrenci}',
                            '{sinif}',
                            '{okul}',
                            '{tarih}',
                            '{zayifKonular}',
                          ])
                            ActionChip(
                              label: Text(
                                tag,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              onPressed: () => _insertPrefaceTag(tag),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (isMobile) ...[
                        _labeledField('Hitap Başlığı', _prefaceTitleCtrl),
                        const SizedBox(height: 10),
                        _labeledField(
                          'Yazar / Birim İmzası',
                          _prefaceAuthorCtrl,
                        ),
                      ] else
                        Row(
                          children: [
                            Expanded(
                              child: _labeledField(
                                'Hitap Başlığı',
                                _prefaceTitleCtrl,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _labeledField(
                                'Yazar / Birim İmzası',
                                _prefaceAuthorCtrl,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      _labeledField(
                        'Ön Söz Metni',
                        _prefaceBodyCtrl,
                        maxLines: 5,
                      ),
                    ] else if (_config.prefaceMode ==
                        PrefaceMode.uploadedPdf) ...[
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _isRasterizingPrefacePdf
                                ? null
                                : _pickAndRasterizePrefacePdf,
                            icon: _isRasterizingPrefacePdf
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.upload_file_rounded),
                            label: Text(
                              _isRasterizingPrefacePdf
                                  ? 'PDF Sayfaları İşleniyor...'
                                  : 'Ek Ön Söz PDF Dosyası Seç (.pdf)',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF7C3AED),
                            ),
                          ),
                          if (_config.uploadedPrefacePagePngs.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    '${_config.uploadedPrefaceFileName}  •  ${_config.uploadedPrefacePagePngs.length} Tam A4 Sayfa Eklendi',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF059669),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'PDF Ön Sözü Kaldır',
                                  onPressed: () => setState(() {
                                    _config.uploadedPrefacePagePngs = [];
                                    _config.uploadedPrefacePageCount = 0;
                                    _config.uploadedPrefaceFileName = null;
                                    _planRevision++;
                                  }),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (_config.uploadedPrefacePagePngs.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 110,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _config.uploadedPrefacePagePngs.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 10),
                            itemBuilder: (_, idx) {
                              return Container(
                                width: 80,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFC4B5FD),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Image.memory(
                                          _config.uploadedPrefacePagePngs[idx],
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      color: const Color(0xFFF3E8FF),
                                      child: Text(
                                        'Ön Söz ${idx + 1}',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF6B21A8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 4. İÇİNDEKİLER VE CEVAP ANAHTARI ANAHTARLARI
              _sectionCard(
                icon: Icons.format_list_numbered_rounded,
                title: '4. İçindekiler & Cevap Anahtarı Bölümleri',
                subtitle:
                    'İçindekiler bölümü her öğrenci için iki aşamalı (two-pass) dizgiyle gerçek konu başlangıç sayfalarını gösterir.',
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'İçindekiler Sayfası Ekle (Olsun / Olmasın)',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Noktalı kılavuz çizgiler, konu başı soru adedi, öğrencinin kazanım başarı % rozeti ve gerçek sayfa numaraları yer alır.',
                        style: GoogleFonts.inter(fontSize: 12),
                      ),
                      value: _config.includeToc,
                      activeThumbColor: const Color(0xFF4F46E5),
                      onChanged: (v) => setState(() {
                        _config.includeToc = v;
                        _planRevision++;
                      }),
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Kitap Sonu Cevap Anahtarı Ekle (Olsun / Olmasın)',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        'Kitabın en sonunda her branş kendi soru sırasına göre (1-A  2-C ...) düzenli kutucuklarla listelenir.',
                        style: GoogleFonts.inter(fontSize: 12),
                      ),
                      value: _config.includeAnswerKey,
                      activeThumbColor: const Color(0xFF4F46E5),
                      onChanged: (v) => setState(() {
                        _config.includeAnswerKey = v;
                        _planRevision++;
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _insertPrefaceTag(String tag) {
    final text = _prefaceBodyCtrl.text;
    final sel = _prefaceBodyCtrl.selection;
    int insertStart = sel.isValid
        ? sel.start.clamp(0, text.length)
        : text.length;
    int insertEnd = sel.isValid ? sel.end.clamp(0, text.length) : text.length;
    if (insertStart > insertEnd) {
      final tmp = insertStart;
      insertStart = insertEnd;
      insertEnd = tmp;
    }
    final bool needLeadingSpace =
        insertStart > 0 && !RegExp(r'\s').hasMatch(text[insertStart - 1]);
    final String inserted = '${needLeadingSpace ? ' ' : ''}$tag';
    final String nextText = text.replaceRange(insertStart, insertEnd, inserted);
    _prefaceBodyCtrl.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: insertStart + inserted.length),
    );
    _syncTextControllersToConfig();
  }

  void _updateTargetPages(int newPages) {
    final clamped = newPages.clamp(4, 240);
    setState(() {
      _config.targetPageCount = clamped;
      _pageCountCtrl.text = '$clamped';
      _planRevision++;
    });
  }

  Widget _budgetBadge(
    String label,
    String val,
    Color color, {
    bool boldHighlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: boldHighlight ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: boldHighlight ? 0.5 : 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF334155),
            ),
          ),
          Text(
            val,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeledField(
    String label,
    TextEditingController ctrl, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      onChanged: (_) => _syncTextControllersToConfig(),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: _fieldBorder(const Color(0xFFCBD5E1)),
        enabledBorder: _fieldBorder(const Color(0xFFCBD5E1)),
        focusedBorder: _fieldBorder(const Color(0xFF4F46E5), 1.5),
      ),
    );
  }

  Future<void> _pickCustomCoverImage() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.first;
      if (file.bytes == null || file.bytes!.isEmpty) return;
      setState(() {
        _config.customCoverImageBytes = file.bytes;
        _config.customCoverImageName = file.name;
        _planRevision++;
      });
    } catch (e) {
      _showSnack('Görsel yüklenemedi: $e');
    }
  }

  Future<void> _pickAndRasterizePrefacePdf() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.first;
      if (file.bytes == null || file.bytes!.isEmpty) {
        _showSnack('PDF verisi okunamadı.');
        return;
      }

      setState(() => _isRasterizingPrefacePdf = true);
      final pages = await _service.rasterizeUploadedPrefacePdf(file.bytes!);
      if (!mounted) return;

      if (pages.isEmpty) {
        setState(() => _isRasterizingPrefacePdf = false);
        _showSnack('PDF sayfaları görüntüye dönüştürülemedi.');
        return;
      }

      setState(() {
        _config.uploadedPrefacePagePngs = pages;
        _config.uploadedPrefacePageCount = pages.length;
        _config.uploadedPrefaceFileName = file.name;
        _isRasterizingPrefacePdf = false;
        // Sayfa bütçesi taşarsa hedef sayfayı otomatik uyumlu tut
        if (!_liveBudget.isValid) {
          _config.targetPageCount = _liveBudget.fixedPages + 12;
          _pageCountCtrl.text = '${_config.targetPageCount}';
        }
        _planRevision++;
      });
      _showSnack(
        '${pages.length} sayfalık PDF ön söz eklendi ve Sayfa Bütçesi güncellendi!',
        isSuccess: true,
      );
    } catch (e) {
      if (mounted) setState(() => _isRasterizingPrefacePdf = false);
      _showSnack('PDF yüklenirken hata oluştu: $e');
    }
  }

  // ─── ADIM 4: ÖNİZLEME VE ÜRETİM (TEKİL / ZIP / BİRLEŞİK PDF) ──────────────

  StudentBookPlan? _resolveMemoizedPreviewPlan(
    StudentMasteryProfile? student,
    List<PoolQuestionItem> relevantPool,
  ) {
    if (_isPreparingImagesForPreview || student == null) return null;
    final String key =
        '${student.id}|rev:$_planRevision|pool:${relevantPool.length}|ex:${_config.includeExerciseQuestions}|tr:${_config.includeTrialExamQuestions}|pg:${_config.targetPageCount}|cov:${_config.includeCover}|pref:${_config.prefaceMode.key}:${_config.uploadedPrefacePagePngs.length}|toc:${_config.includeToc}|ans:${_config.includeAnswerKey}|pad:${_config.padShortBooksWithStudyNotes}';
    if (_cachedPreviewPlanKey == key && _cachedPreviewPlan != null) {
      return _cachedPreviewPlan;
    }
    _cachedPreviewPlanKey = key;
    _cachedPreviewPlan = _service.buildStudentBookPlan(
      student: student,
      config: _config,
      rules: _outcomeRules,
      preparedPool: relevantPool,
    );
    return _cachedPreviewPlan;
  }

  Widget _buildStep4PreviewAndExport(bool isMobile) {
    _syncTextControllersToConfig();
    final selectedStudents = _allStudents
        .where((s) => _selectedStudentIds.contains(s.id))
        .toList();

    StudentMasteryProfile? activePreviewStudent;
    for (final s in selectedStudents) {
      if (s.id == _previewStudentId) {
        activePreviewStudent = s;
        break;
      }
    }
    activePreviewStudent ??= selectedStudents.isNotEmpty
        ? selectedStudents.first
        : null;

    final relevantPool = _getRelevantPoolForActiveBundle();
    final StudentBookPlan? previewPlan = _resolveMemoizedPreviewPlan(
      activePreviewStudent,
      relevantPool,
    );

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üretim Kartları (Tekil Önizleme / Tekil İndir / Toplu ZIP / Birleşik PDF)
              _sectionCard(
                icon: Icons.rocket_launch_outlined,
                title:
                    'Fokus Kitap Üretim & İndirme Merkezi (${selectedStudents.length} Seçili Öğrenci)',
                subtitle:
                    'Önce tek bir öğrencinin kitabını canlı önizleyebilir, ardından şube klasörlü ZIP veya tek birleşik baskı PDF olarak indirebilirsiniz.',
                child: LayoutBuilder(
                  builder: (_, actionConstraints) {
                    final double maxW = actionConstraints.maxWidth;
                    final double cardWidth = maxW >= 960
                        ? (maxW - 42) / 4
                        : maxW >= 560
                        ? (maxW - 14) / 2
                        : maxW;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        _exportActionCard(
                          width: cardWidth,
                          icon: Icons.visibility_outlined,
                          color: const Color(0xFF4F46E5),
                          title: 'Seçili Öğrenciyi Önizle / Yazdır',
                          subtitle: activePreviewStudent != null
                              ? '${activePreviewStudent.name} için canlı PDF önizleme penceresi aç'
                              : 'Önizlenecek öğrenci seçin',
                          buttonLabel: 'PDF Önizle',
                          onPressed: activePreviewStudent == null
                              ? null
                              : () =>
                                    _handlePreviewSingle(activePreviewStudent!),
                        ),
                        _exportActionCard(
                          width: cardWidth,
                          icon: Icons.download_rounded,
                          color: const Color(0xFF0284C7),
                          title: 'Seçili Öğrenci PDF İndir',
                          subtitle: activePreviewStudent != null
                              ? '${activePreviewStudent.name}_FokusKitap.pdf olarak indir'
                              : 'Öğrenci seçin',
                          buttonLabel: 'Tek PDF İndir',
                          onPressed: activePreviewStudent == null
                              ? null
                              : () => _handleDownloadSingle(
                                  activePreviewStudent!,
                                ),
                        ),
                        _exportActionCard(
                          width: cardWidth,
                          icon: Icons.folder_zip_outlined,
                          color: const Color(0xFF059669),
                          title: 'Toplu Şube Klasörlü ZIP İndir',
                          subtitle:
                              '${selectedStudents.length} öğrenciyi {Şube}/{Öğrenci}_FokusKitap.pdf yapısında paketler',
                          buttonLabel:
                              'ZIP Olarak İndir (${selectedStudents.length})',
                          onPressed: selectedStudents.isEmpty
                              ? null
                              : () => _handleBulkZip(selectedStudents),
                        ),
                        _exportActionCard(
                          width: cardWidth,
                          icon: Icons.print_outlined,
                          color: const Color(0xFFD97706),
                          title: 'Tek Birleşik Baskı PDF İndir',
                          subtitle:
                              'Matbaa / fotokopi baskısı için ${selectedStudents.length} öğrencinin kitabını tek PDF dosyasında birleştirir',
                          buttonLabel: 'Birleşik PDF İndir',
                          onPressed: selectedStudents.isEmpty
                              ? null
                              : () => _handleBulkCombinedPdf(selectedStudents),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // Canlı Öğrenci Kitap Planı & Gerçek Sayfa Numaralı İçindekiler Simülasyonu
              _sectionCard(
                icon: Icons.menu_book_rounded,
                title:
                    'Bireysel Kitap Planı & İki Aşamalı İçindekiler Önizlemesi',
                subtitle:
                    'Farklı öğrencileri seçerek her öğrencinin kendi kazanım karnesine göre kitabın nasıl şekillendiğini anında kontrol edin.',
                child: _isPreparingImagesForPreview
                    ? const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 10),
                              Text(
                                'Soru boyutları ve sayfa yerleşimi hesaplanıyor...',
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: activePreviewStudent?.id,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Planı İncelenen Öğrenci',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: _fieldBorder(const Color(0xFFCBD5E1)),
                              enabledBorder: _fieldBorder(
                                const Color(0xFFCBD5E1),
                              ),
                              focusedBorder: _fieldBorder(
                                const Color(0xFF4F46E5),
                                1.5,
                              ),
                            ),
                            items: selectedStudents.map((s) {
                              return DropdownMenuItem(
                                value: s.id,
                                child: Text(
                                  '${s.name} (${s.classLevel}/${s.branch}) — Genel Hakimiyet: %${s.overallAbilityPercent.toStringAsFixed(0)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (v) =>
                                setState(() => _previewStudentId = v),
                          ),
                          if (previewPlan != null) ...[
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                _budgetBadge(
                                  'Toplam Kitap Sayfası',
                                  '${previewPlan.totalPages} Sayfa',
                                  const Color(0xFF4F46E5),
                                  boldHighlight: true,
                                ),
                                _budgetBadge(
                                  'Kişiye Özel Soru',
                                  '${previewPlan.totalQuestionCount} Soru',
                                  const Color(0xFF059669),
                                  boldHighlight: true,
                                ),
                                _budgetBadge(
                                  'Soru Sayfası',
                                  '${previewPlan.questionPagesCount} syf',
                                  const Color(0xFF0284C7),
                                ),
                                if (previewPlan.studyNotePadPagesCount > 0)
                                  _budgetBadge(
                                    'Çalışma Not Sayfası',
                                    '${previewPlan.studyNotePadPagesCount} syf',
                                    const Color(0xFF7C3AED),
                                  ),
                                _budgetBadge(
                                  '%100 Başarıyla Atlanan Kazanım',
                                  '${previewPlan.skippedMasteredOutcomeCount} konu',
                                  const Color(0xFFD97706),
                                ),
                              ],
                            ),
                            if (previewPlan.totalQuestionCount > 0) ...[
                              const SizedBox(height: 10),
                              Builder(
                                builder: (_) {
                                  final allPlaced = previewPlan
                                      .questionsBySubject
                                      .values
                                      .expand((l) => l)
                                      .toList();
                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      for (final lvl in DifficultyScale.levels)
                                        () {
                                          final cnt = allPlaced
                                              .where(
                                                (q) =>
                                                    DifficultyScale.labelOf(
                                                      q.item.difficulty,
                                                    ) ==
                                                    lvl,
                                              )
                                              .length;
                                          return _budgetBadge(
                                            lvl,
                                            '$cnt soru',
                                            DifficultyScale.colorForLabel(lvl),
                                            boldHighlight: cnt > 0,
                                          );
                                        }(),
                                    ],
                                  );
                                },
                              ),
                            ],
                            const SizedBox(height: 16),
                            Text(
                              '${previewPlan.student.name} İçin Oluşan Gerçek Sayfa Numaralı İçindekiler (${previewPlan.tocEntries.length} Konu)',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (previewPlan.tocEntries.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Bu öğrenci için aktif havuzda eşleşen soru bulunamadı veya tüm kazanımlar muaf tutuldu. Lütfen Adım 2\'de "Deneme Sorularını da Ekle" / "Egzersiz Sorularını da Ekle" veya branş yedekleme anahtarlarını açın.',
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              )
                            else
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 280,
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: previewPlan.tocEntries.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (_, idx) {
                                    final t = previewPlan.tocEntries[idx];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 7,
                                      ),
                                      child: Row(
                                        children: [
                                          ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: isMobile ? 105 : 150,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEEF2FF),
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                              ),
                                              child: Text(
                                                t.subject,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: const Color(
                                                    0xFF3730A3,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              t.outcome,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 12.5,
                                                color: const Color(0xFF0F172A),
                                              ),
                                            ),
                                          ),
                                          if (!isMobile &&
                                              t.studentMasteryPercent != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 8,
                                              ),
                                              child: Text(
                                                'Başarı: %${t.studentMasteryPercent!.toStringAsFixed(0)}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: const Color(
                                                    0xFF64748B,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isMobile
                                                ? '${t.questionCount}S • S.${t.startPageNumber}'
                                                : '${t.questionCount} Soru  •  Sayfa ${t.startPageNumber}',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFF4F46E5),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _exportActionCard({
    required double width,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback? onPressed,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 13.8,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 36,
            child: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                buttonLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePreviewSingle(StudentMasteryProfile student) async {
    _syncTextControllersToConfig();
    _syncRulesToConfig();
    final relevantPool = _getRelevantPoolForActiveBundle();
    _exportProgressNotifier.value = (
      text: '${student.name} için PDF önizleme hazırlanıyor...',
      ratio: 0.0,
      current: 1,
      total: 1,
    );
    setState(() => _isExporting = true);

    Uint8List? pdfBytes;
    try {
      pdfBytes = await _service.generateSingleStudentPdfBytes(
        student: student,
        config: _config,
        rules: _outcomeRules,
        pool: relevantPool,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
      }
      _showSnack('Önizleme hatası: $e');
      return;
    }

    if (!mounted) return;
    setState(() => _isExporting = false);
    if (pdfBytes.isEmpty) {
      _showSnack('Önizlenecek PDF verisi oluşturulamadı.');
      return;
    }

    await _showInlinePdfPreviewDialog(student, pdfBytes);
  }

  Future<void> _showInlinePdfPreviewDialog(
    StudentMasteryProfile student,
    Uint8List pdfBytes,
  ) async {
    final String safeFileName = sanitizeFileName(
      '${student.name}_FokusKitap.pdf',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final bool narrowModal = size.width < 640;
        return Dialog(
          insetPadding: EdgeInsets.all(narrowModal ? 10 : 24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: SizedBox(
            width: math.min(980, size.width - (narrowModal ? 20 : 48)),
            height: math.min(820, size.height - (narrowModal ? 20 : 48)),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: narrowModal ? 12 : 18,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.picture_as_pdf_rounded,
                          color: Color(0xFF4F46E5),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${student.name} — Fokus Kitap Önizleme',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: narrowModal ? 13.5 : 15,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              '${student.classLevel}/${student.branch}  •  Genel Hakimiyet: %${student.overallAbilityPercent.toStringAsFixed(0)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          await downloadFileUniversal(
                            bytes: pdfBytes,
                            fileName: safeFileName,
                            mimeType: 'application/pdf',
                          );
                          await _service.recordGenerationHistory(
                            institutionId: _config.institutionId,
                            config: _config,
                            studentCount: 1,
                            exportMode: 'single',
                          );
                          if (mounted) {
                            _showSnack(
                              '$safeFileName indirildi!',
                              isSuccess: true,
                            );
                          }
                        },
                        icon: const Icon(Icons.download_rounded, size: 17),
                        label: Text(narrowModal ? 'İndir' : 'PDF İndir'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFFF1F5F9),
                    child: PdfPreview(
                      build: (_) async => pdfBytes,
                      pdfFileName: safeFileName,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      canDebug: false,
                      maxPageWidth: 720,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleDownloadSingle(StudentMasteryProfile student) async {
    _syncTextControllersToConfig();
    _syncRulesToConfig();
    final relevantPool = _getRelevantPoolForActiveBundle();
    _exportProgressNotifier.value = (
      text: '${student.name} için Fokus Kitap indiriliyor...',
      ratio: 0.0,
      current: 1,
      total: 1,
    );
    setState(() => _isExporting = true);
    try {
      await _service.downloadSingleStudentBook(
        student: student,
        config: _config,
        rules: _outcomeRules,
        pool: relevantPool,
      );
      _showSnack('${student.name} Fokus Kitap indirildi!', isSuccess: true);
    } catch (e) {
      _showSnack('İndirme hatası: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _handleBulkZip(List<StudentMasteryProfile> students) async {
    _syncTextControllersToConfig();
    _syncRulesToConfig();
    final relevantPool = _getRelevantPoolForActiveBundle();
    _exportProgressNotifier.value = (
      text: 'ZIP üretimi başlatılıyor...',
      ratio: 0.0,
      current: 0,
      total: students.length,
    );
    setState(() => _isExporting = true);
    try {
      await _service.exportBulkBooksAsZip(
        students: students,
        config: _config,
        rules: _outcomeRules,
        pool: relevantPool,
        onProgress: (cur, tot, label) {
          if (!mounted) return;
          final double r = tot > 0 ? (cur / tot).clamp(0.0, 1.0) : 0.0;
          _exportProgressNotifier.value = (
            text: label,
            ratio: r,
            current: cur,
            total: tot,
          );
        },
      );
      _showSnack(
        '${students.length} öğrencinin şube klasörlü Fokus Kitap ZIP arşivi indirildi!',
        isSuccess: true,
      );
    } catch (e) {
      _showSnack('Toplu ZIP hatası: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _handleBulkCombinedPdf(
    List<StudentMasteryProfile> students,
  ) async {
    _syncTextControllersToConfig();
    _syncRulesToConfig();
    final relevantPool = _getRelevantPoolForActiveBundle();
    _exportProgressNotifier.value = (
      text: 'Birleşik PDF üretimi başlatılıyor...',
      ratio: 0.0,
      current: 0,
      total: students.length,
    );
    setState(() => _isExporting = true);
    try {
      await _service.exportBulkBooksAsCombinedPdf(
        students: students,
        config: _config,
        rules: _outcomeRules,
        pool: relevantPool,
        onProgress: (cur, tot, label) {
          if (!mounted) return;
          final double r = tot > 0 ? (cur / tot).clamp(0.0, 1.0) : 0.0;
          _exportProgressNotifier.value = (
            text: label,
            ratio: r,
            current: cur,
            total: tot,
          );
        },
      );
      _showSnack(
        '${students.length} öğrencilik tek birleşik baskı PDF dosyası indirildi!',
        isSuccess: true,
      );
    } catch (e) {
      _showSnack('Birleşik PDF hatası: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _openSaveTemplateDialog() async {
    _syncTextControllersToConfig();
    _syncRulesToConfig();
    final nameCtrl = TextEditingController(text: _config.templateName);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fokus Kitap Şablonunu Kaydet'),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: 'Şablon Adı',
            hintText: 'Örn: 8. Sınıf LGS 24 Sayfa Zümrüt Şablon',
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: _fieldBorder(const Color(0xFFCBD5E1)),
            enabledBorder: _fieldBorder(const Color(0xFFCBD5E1)),
            focusedBorder: _fieldBorder(const Color(0xFF4F46E5), 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (saved == true) {
      _config.templateName = nameCtrl.text.trim().isEmpty
          ? 'Fokus Kitap Şablonu'
          : nameCtrl.text.trim();
      await _service.saveConfigTemplate(_config);
      _showSnack(
        '"${_config.templateName}" şablonu başarıyla kaydedildi!',
        isSuccess: true,
      );
    }
    nameCtrl.dispose();
  }

  Widget _buildExportProgressOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child:
              ValueListenableBuilder<
                ({String text, double ratio, int current, int total})
              >(
                valueListenable: _exportProgressNotifier,
                builder: (_, prog, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF4F46E5)),
                      const SizedBox(height: 16),
                      Text(
                        prog.total > 0
                            ? 'Fokus Kitap Üretiliyor (${prog.current} / ${prog.total})'
                            : 'Fokus Kitap Üretiliyor...',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        prog.text,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: prog.ratio > 0 ? prog.ratio : null,
                          minHeight: 8,
                          backgroundColor: const Color(0xFFE2E8F0),
                          color: const Color(0xFF4F46E5),
                        ),
                      ),
                    ],
                  );
                },
              ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF4F46E5), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12.2,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
