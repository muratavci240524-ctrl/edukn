import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../services/assessment_service.dart';
import '../../../../services/term_service.dart';
import '../../../../services/user_permission_service.dart';
import 'personalized_book_generator_service.dart';
import 'personalized_book_models.dart';
import 'personalized_book_wizard_screen.dart';

class PersonalizedBookDashboardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const PersonalizedBookDashboardScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
  });

  @override
  State<PersonalizedBookDashboardScreen> createState() =>
      _PersonalizedBookDashboardScreenState();
}

class _PersonalizedBookDashboardScreenState
    extends State<PersonalizedBookDashboardScreen> {
  final AssessmentService _assessmentService = AssessmentService();
  final PersonalizedBookGeneratorService _bookService =
      PersonalizedBookGeneratorService();

  bool _isLoadingMeta = true;
  String? _resolvedInstitutionId;
  String? _schoolTypeName;
  String? _activeTermId;
  List<String>? _allowedGrades;

  bool _isLoadingPoolCount = true;
  List<PoolQuestionItem> _cachedPool = [];

  Stream<List<TrialExam>>? _examsStream;
  Stream<List<PersonalizedBookConfig>>? _configsStream;
  Stream<List<PersonalizedBookHistoryRecord>>? _historyStream;

  @override
  void initState() {
    super.initState();
    _loadContextAndPool();
  }

  @override
  void didUpdateWidget(covariant PersonalizedBookDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId ||
        oldWidget.schoolTypeId != widget.schoolTypeId) {
      _loadContextAndPool();
    }
  }

  String get _effectiveInstitutionId {
    if (_resolvedInstitutionId != null &&
        _resolvedInstitutionId!.trim().isNotEmpty) {
      return _resolvedInstitutionId!.trim();
    }
    return widget.institutionId.trim();
  }

  void _bindStreams() {
    final instId = _effectiveInstitutionId;
    if (instId.isEmpty) {
      _examsStream = Stream.value(const []);
      _configsStream = Stream.value(const []);
      _historyStream = Stream.value(const []);
      return;
    }
    _examsStream = _assessmentService.getTrialExams(
      instId,
      termId: _activeTermId,
    );
    _configsStream = _bookService.watchSavedConfigs(instId);
    _historyStream = _bookService.watchHistory(instId);
  }

  Future<void> _loadContextAndPool() async {
    if (!mounted) return;
    setState(() => _isLoadingMeta = true);
    try {
      final userData = await UserPermissionService.loadUserData();
      final userEmail =
          (userData?['email'] ?? FirebaseAuth.instance.currentUser?.email) ??
          '';
      final resolved = await UserPermissionService.resolveInstitutionId(
        userEmail,
        userData: userData,
      );
      if (resolved.trim().isNotEmpty) {
        _resolvedInstitutionId = resolved.trim();
      } else if (widget.institutionId.trim().isNotEmpty) {
        _resolvedInstitutionId = widget.institutionId.trim();
      } else {
        final rawRole = (userData?['role'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        final isSuperAdmin =
            rawRole == 'SUPER_ADMIN' ||
            rawRole == 'SUPERADMIN' ||
            userData?['isSuperAdmin'] == true;
        if (isSuperAdmin) {
          _resolvedInstitutionId = 'SUPER_ADMIN';
        }
      }

      if (widget.schoolTypeId.trim().isNotEmpty) {
        final stDoc = await FirebaseFirestore.instance
            .collection('schoolTypes')
            .doc(widget.schoolTypeId.trim())
            .get();
        if (stDoc.exists) {
          final d = stDoc.data();
          _schoolTypeName =
              d?['schoolTypeName']?.toString() ?? d?['name']?.toString();
          if (d?['activeGrades'] is List) {
            _allowedGrades = (d!['activeGrades'] as List)
                .map((e) => e.toString())
                .where((e) => e.trim().isNotEmpty)
                .toList();
          }
        }
      }

      _activeTermId =
          await TermService().getSelectedTermId() ??
          await TermService().getActiveTermId();
    } catch (_) {
    } finally {
      _bindStreams();
      if (mounted) setState(() => _isLoadingMeta = false);
    }

    final instId = _effectiveInstitutionId;
    if (instId.isEmpty) {
      if (mounted) setState(() => _isLoadingPoolCount = false);
      return;
    }

    // Havuz sorularını arka planda yükle (KPI sayacı + sihirbaza hızlı aktarım için)
    try {
      final pool = await _bookService.loadFullQuestionPool(instId);
      if (mounted) {
        setState(() {
          _cachedPool = pool;
          _isLoadingPoolCount = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPoolCount = false);
    }
  }

  void _openWizard({
    required List<TrialExam> allExams,
    PersonalizedBookConfig? template,
    List<String>? preselectedExamIds,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalizedBookWizardScreen(
          institutionId: _effectiveInstitutionId,
          schoolTypeId: widget.schoolTypeId,
          availableExams: allExams,
          preloadedPool: _cachedPool.isNotEmpty ? _cachedPool : null,
          initialTemplate: template,
          preselectedExamIds: preselectedExamIds,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 720;
    final isCompactCard = screenWidth < 600;
    final instId = _effectiveInstitutionId;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: 'Fokus Kitap',
        subtitle:
            _schoolTypeName ??
            'Kişiye Özel Akıllı Soru Bankası & Kazanım Güçlendirme Kitabı',
        institutionId: instId,
      ),
      body: _isLoadingMeta
          ? const Center(child: CircularProgressIndicator())
          : instId.isEmpty
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _emptyBox(
                    Icons.business_outlined,
                    'Kurum bilgisi doğrulanamadı. Lütfen kurum oturumunuzu kontrol edip sayfayı yenileyin.',
                  ),
                ),
              ),
            )
          : SafeStreamBuilder<List<TrialExam>>(
              stream: _examsStream ?? Stream.value(const []),
              builder: (context, examSnap) {
                final rawExams = examSnap.data ?? const <TrialExam>[];
                final allExams = rawExams.where((e) {
                  if (e.id.startsWith('pool_')) return false;
                  if (_allowedGrades == null || _allowedGrades!.isEmpty) {
                    return true;
                  }
                  final normLvl = AssessmentService.normalizeClassLevel(
                    e.classLevel,
                    examName: e.name,
                  );
                  final matchesNorm = _allowedGrades!.any(
                    (g) =>
                        FokusTextUtils.classLevelsCompatible(g, normLvl) ||
                        FokusTextUtils.classLevelsCompatible(g, e.classLevel),
                  );
                  if (matchesNorm) return true;
                  return FokusTextUtils.examMatchesAllowedGrades(
                    allowedGrades: _allowedGrades,
                    classLevel: e.classLevel,
                    examName: e.name,
                    examTypeName: e.examTypeName,
                  );
                }).toList();

                final evaluatedExams = allExams
                    .where(
                      (e) =>
                          e.resultsJson != null &&
                          e.resultsJson!.trim().isNotEmpty,
                    )
                    .toList();

                return SafeStreamBuilder<List<PersonalizedBookConfig>>(
                  stream: _configsStream ?? Stream.value(const []),
                  builder: (context, tplSnap) {
                    final templates = tplSnap.data ?? const [];

                    return SafeStreamBuilder<
                      List<PersonalizedBookHistoryRecord>
                    >(
                      stream: _historyStream ?? Stream.value(const []),
                      builder: (context, histSnap) {
                        final history = histSnap.data ?? const [];
                        final totalProducedStudents = history.fold<int>(
                          0,
                          (acc, item) => acc + item.studentCount,
                        );

                        return SingleChildScrollView(
                          padding: EdgeInsets.all(isMobile ? 14 : 24),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1180),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildHeroBanner(
                                    isMobile: isMobile,
                                    evaluatedExams: evaluatedExams,
                                  ),
                                  const SizedBox(height: 22),
                                  _buildKpiRow(
                                    isMobile: isMobile,
                                    poolCount: _cachedPool.length,
                                    evaluatedExamsCount: evaluatedExams.length,
                                    templateCount: templates.length,
                                    producedStudentBooks: totalProducedStudents,
                                  ),
                                  const SizedBox(height: 26),
                                  _buildQuickEvaluatedExamsSection(
                                    evaluatedExams: evaluatedExams,
                                    isMobile: isMobile,
                                  ),
                                  const SizedBox(height: 26),
                                  _buildTemplatesSection(
                                    templates: templates,
                                    evaluatedExams: evaluatedExams,
                                    isCompactCard: isCompactCard,
                                  ),
                                  const SizedBox(height: 26),
                                  _buildHistorySection(
                                    history,
                                    isCompactCard: isCompactCard,
                                  ),
                                  const SizedBox(height: 36),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildHeroBanner({
    required bool isMobile,
    required List<TrialExam> evaluatedExams,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF4F46E5)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF312E81).withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroPill(
                Icons.auto_awesome_rounded,
                'ADAPTİF SEVİYE EŞLEŞTİRME',
              ),
              _heroPill(Icons.verified_outlined, '%100 BAŞARIDA SIFIR SORU'),
              _heroPill(Icons.straighten_rounded, 'BİREBİR SAYFA BÜTÇESİ'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Fokus Kitap',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 26 : 34,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Kişiye Özel Akıllı Soru Bankası & Kazanım Güçlendirme Kitabı',
            style: GoogleFonts.inter(
              fontSize: isMobile ? 14 : 16.5,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFBAE6FD),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Text(
              'Öğrencilerinizin deneme sınavlarındaki kazanım hakimiyetini analiz eder; güçlü oldukları kazanımlarda vakit kaybettirmeden, ihtiyaç duydukları kazanımlardan kendi seviyelerine uygun zorlukta soruları seçerek kapak, ön söz (manuel veya ek PDF), gerçek sayfa numaralı içindekiler ve cevap anahtarıyla tam belirlediğiniz sayfa sayısında basıma hazır kitap üretir.',
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.5,
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => _openWizard(allExams: evaluatedExams),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                label: Text(
                  'Yeni Fokus Kitap Oluştur',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  foregroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF38BDF8)),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 10.8,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow({
    required bool isMobile,
    required int poolCount,
    required int evaluatedExamsCount,
    required int templateCount,
    required int producedStudentBooks,
  }) {
    final cards = [
      (
        'Toplam Havuz Sorusu',
        _isLoadingPoolCount ? '...' : '$poolCount',
        'Kurum + Genel Merkez + Deneme',
        Icons.inventory_2_outlined,
        const Color(0xFF4F46E5),
      ),
      (
        'Değerlendirilmiş Deneme',
        '$evaluatedExamsCount',
        'Analize hazır sınav sayısı',
        Icons.assignment_turned_in_outlined,
        const Color(0xFF059669),
      ),
      (
        'Kayıtlı Kitap Şablonu',
        '$templateCount',
        'Tek tıkla hazır sayfa kurgusu',
        Icons.bookmarks_outlined,
        const Color(0xFF7C3AED),
      ),
      (
        'Üretilen Fokus Kitap',
        '$producedStudentBooks',
        'Toplam kişiye özel öğrenci kitabı',
        Icons.menu_book_rounded,
        const Color(0xFFD97706),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isMobile ? 2 : 4,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        mainAxisExtent: 134,
      ),
      itemCount: cards.length,
      itemBuilder: (_, idx) {
        final c = cards[idx];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      c.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(c.$4, color: c.$5, size: 20),
                ],
              ),
              Text(
                c.$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Text(
                c.$3,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickEvaluatedExamsSection({
    required List<TrialExam> evaluatedExams,
    required bool isMobile,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Hızlı Başlat: Son Değerlendirilmiş Denemeler',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
            if (evaluatedExams.length > 4)
              TextButton(
                onPressed: () => _openWizard(allExams: evaluatedExams),
                child: const Text('Tümünü Sihirbazda Gör'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (evaluatedExams.isEmpty)
          _emptyBox(
            Icons.quiz_outlined,
            'Henüz değerlendirilmiş (optik/online sonucu hesaplanmış) bir deneme sınavı bulunmuyor.',
          )
        else
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: evaluatedExams.take(4).map((ex) {
              final dStr =
                  '${ex.date.day.toString().padLeft(2, '0')}.${ex.date.month.toString().padLeft(2, '0')}.${ex.date.year}';
              return Container(
                width: isMobile ? double.infinity : 280,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
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
                              color: const Color(0xFF4F46E5),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          dStr,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      ex.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      ex.examTypeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openWizard(
                          allExams: evaluatedExams,
                          preselectedExamIds: [ex.id],
                        ),
                        icon: const Icon(Icons.auto_stories_outlined, size: 16),
                        label: const Text('Fokus Kitap Hazırla'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4F46E5),
                          side: const BorderSide(color: Color(0xFFC7D2FE)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildTemplatesSection({
    required List<PersonalizedBookConfig> templates,
    required List<TrialExam> evaluatedExams,
    required bool isCompactCard,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Kayıtlı Fokus Kitap Şablonları (${templates.length})',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        if (templates.isEmpty)
          _emptyBox(
            Icons.bookmark_border_rounded,
            'Henüz kaydedilmiş bir Fokus Kitap şablonunuz yok. Sihirbaz içerisinden sayfa sayısı, kapak teması ve kazanım kurallarınızı şablon olarak kaydedebilirsiniz.',
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: templates.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, idx) {
              final tpl = templates[idx];
              final iconBox = Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      tpl.coverTheme.primaryColor,
                      tpl.coverTheme.secondaryColor,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  color: tpl.coverTheme.accentColor,
                  size: 22,
                ),
              );
              final infoCol = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tpl.templateName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14.2,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${tpl.targetPageCount} Sayfa  •  Tema: ${tpl.coverTheme.label}  •  Ön Söz: ${tpl.prefaceMode.label}  •  ${tpl.skipZeroMinOnHighMastery ? '%${tpl.highMasteryZeroThreshold.toInt()} Muafiyet Aktif' : 'Muafiyet Kapalı'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              );

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: isCompactCard
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              iconBox,
                              const SizedBox(width: 12),
                              Expanded(child: infoCol),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: () => _openWizard(
                                    allExams: evaluatedExams,
                                    template: tpl,
                                  ),
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Şablonla Başlat'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Şablonu Sil',
                                onPressed: () async {
                                  await _bookService.deleteConfigTemplate(
                                    _effectiveInstitutionId,
                                    tpl.id,
                                  );
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          iconBox,
                          const SizedBox(width: 14),
                          Expanded(child: infoCol),
                          const SizedBox(width: 12),
                          FilledButton.tonalIcon(
                            onPressed: () => _openWizard(
                              allExams: evaluatedExams,
                              template: tpl,
                            ),
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 18,
                            ),
                            label: const Text('Şablonla Başlat'),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Şablonu Sil',
                            onPressed: () async {
                              await _bookService.deleteConfigTemplate(
                                _effectiveInstitutionId,
                                tpl.id,
                              );
                            },
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildHistorySection(
    List<PersonalizedBookHistoryRecord> history, {
    required bool isCompactCard,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Son Üretim Geçmişi (${history.length})',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 10),
        if (history.isEmpty)
          _emptyBox(
            Icons.history_rounded,
            'Henüz üretilmiş bir Fokus Kitap kaydı bulunmuyor.',
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: history.take(10).length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, idx) {
              final h = history[idx];
              final dStr =
                  '${h.createdAt.day.toString().padLeft(2, '0')}.${h.createdAt.month.toString().padLeft(2, '0')}.${h.createdAt.year} ${h.createdAt.hour.toString().padLeft(2, '0')}:${h.createdAt.minute.toString().padLeft(2, '0')}';
              final modeLabel = h.exportMode == 'zip'
                  ? 'Şube Klasörlü ZIP'
                  : (h.exportMode == 'combined_pdf'
                        ? 'Birleşik Baskı PDF'
                        : 'Tekil Öğrenci PDF');

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.check_circle_outline_rounded,
                        color: Color(0xFF059669),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${h.bookTitle} — ${h.studentCount} Öğrenci (${h.targetPageCount} Sayfa)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            '${h.examNames.join(', ')}  •  $modeLabel${isCompactCard ? '  •  $dStr' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11.8,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isCompactCard) ...[
                      const SizedBox(width: 8),
                      Text(
                        dStr,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _emptyBox(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade400, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 12.8,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
