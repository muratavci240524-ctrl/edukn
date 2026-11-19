import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'assessment_definitions_screen.dart';
import 'trial_exam_list_screen.dart';
import 'active_exam_list_screen.dart';
import 'assessment_reports_screen.dart';
import '../../../services/assessment_service.dart';
import '../../../models/assessment/trial_exam_model.dart';
import '../../../models/assessment/outcome_list_model.dart';
import 'error_booklet/error_booklet_dashboard_screen.dart';
import 'personalized_book/personalized_book_dashboard_screen.dart';
import 'central_school_reports_screen.dart';
import 'question_pool/question_pool_screen.dart';
import 'external_exam/external_exam_list_screen.dart';
import '../tools/academic_tracking/academic_tracking_models.dart';
import '../tools/academic_tracking/champions_league_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/term_service.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';

class AssessmentDashboardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final int initialTab;

  const AssessmentDashboardScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.initialTab = 0,
  }) : super(key: key);

  @override
  State<AssessmentDashboardScreen> createState() =>
      _AssessmentDashboardScreenState();
}

class _AssessmentDashboardScreenState extends State<AssessmentDashboardScreen> {
  final AssessmentService _assessmentService = AssessmentService();
  String? _activeTermId;
  String? _termName;
  String _schoolStage = 'genel';
  String _schoolTypeName = '';

  late Stream<int> _examTypesCountStream;
  late Stream<int> _opticalFormsCountStream;
  late Stream<List<OutcomeList>> _outcomeListsStream;
  late Stream<List<TrialExam>> _trialExamsStream;

  @override
  void initState() {
    super.initState();
    _initStaticStreams();
    _trialExamsStream = _assessmentService.getTrialExams(
      widget.institutionId,
      termId: _activeTermId,
    );
    _loadTerm();
  }

  @override
  void didUpdateWidget(covariant AssessmentDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId) {
      _initStaticStreams();
      _trialExamsStream = _assessmentService.getTrialExams(
        widget.institutionId,
        termId: _activeTermId,
      );
    }
    if (oldWidget.schoolTypeId != widget.schoolTypeId) {
      _loadTerm();
    }
  }

  void _initStaticStreams() {
    _examTypesCountStream = _assessmentService
        .getExamTypes(widget.institutionId)
        .map((list) => list.length);
    _opticalFormsCountStream = _assessmentService
        .getOpticalForms(widget.institutionId)
        .map((list) => list.length);
    _outcomeListsStream = _assessmentService.getOutcomeLists(
      widget.institutionId,
    );
  }

  Future<void> _loadTerm() async {
    try {
      final termId =
          await TermService().getSelectedTermId() ??
          await TermService().getActiveTermId();
      String? name = await TermService().getSelectedTermName();
      if (name == null && termId != null) {
        final doc = await FirebaseFirestore.instance
            .collection('terms')
            .doc(termId)
            .get();
        if (doc.exists) {
          name = doc.data()?['name']?.toString();
        }
      }

      String stage = 'genel';
      String stLabel = '';
      if (widget.schoolTypeId.trim().isNotEmpty) {
        final stDoc = await FirebaseFirestore.instance
            .collection('schoolTypes')
            .doc(widget.schoolTypeId.trim())
            .get();
        if (stDoc.exists) {
          final sd = stDoc.data() ?? const <String, dynamic>{};
          stLabel = (sd['schoolTypeName'] ?? sd['name'] ?? sd['type'] ?? '')
              .toString()
              .trim();
          final norm = AcademicTrackingDataService.normTr(stLabel);
          final grades = (sd['activeGrades'] is Iterable)
              ? (sd['activeGrades'] as Iterable)
                    .map(
                      (e) =>
                          RegExp(r'\d+').firstMatch(e.toString())?.group(0) ??
                          '',
                    )
                    .where((e) => e.isNotEmpty)
                    .toSet()
              : <String>{};
          if (norm.contains('ortaokul') ||
              (grades.any({'5', '6', '7', '8'}.contains) &&
                  !grades.any({'9', '10', '11', '12'}.contains))) {
            stage = 'ortaokul';
          } else if (norm.contains('lise') ||
              norm.contains('anadolu') ||
              norm.contains('fen lise') ||
              norm.contains('kurs') ||
              grades.any({'9', '10', '11', '12'}.contains)) {
            stage = 'lise';
          } else if (norm.contains('ilkokul')) {
            stage = 'ilkokul';
          } else if (norm.contains('anaokul') || norm.contains('kres')) {
            stage = 'anaokulu';
          }
        }
      }

      if (mounted) {
        final bool termChanged = termId != _activeTermId;
        setState(() {
          _activeTermId = termId;
          _termName = name;
          _schoolStage = stage;
          _schoolTypeName = stLabel;
          if (termChanged) {
            _trialExamsStream = _assessmentService.getTrialExams(
              widget.institutionId,
              termId: _activeTermId,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading term in AssessmentDashboard: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width > 850;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(title: 'Ölçme Değerlendirme', subtitle: _termName),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 24 : 16,
          vertical: isDesktop ? 32 : 20,
        ),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Tanımlar & Raporlar
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 850) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 2, child: _buildTanimlarCard()),
                            const SizedBox(width: 24),
                            Expanded(flex: 1, child: _buildRaporlarCard()),
                          ],
                        ),
                      );
                    } else {
                      return Column(
                        children: [
                          _buildTanimlarCard(),
                          const SizedBox(height: 24),
                          _buildRaporlarCard(),
                        ],
                      );
                    }
                  },
                ),

                const SizedBox(height: 24),

                // Row 2: Denemeler & Sınavlar
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 850) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _buildSecondaryCard(
                                title: 'Denemeler',
                                subtitle:
                                    'Yeni deneme sınavları kurgulayın, soru dağılımlarını belirleyin ve uygulama takvimini yayınlayın.',
                                icon: Icons.edit_note_rounded,
                                iconColor: Colors.purple,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (ctx) => TrialExamListScreen(
                                      institutionId: widget.institutionId,
                                      schoolTypeId: widget.schoolTypeId,
                                    ),
                                  ),
                                ),
                                actions: ['Yeni Oluştur', 'Yayınla', 'Arşiv'],
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: _buildSecondaryCard(
                                title: 'Sınavlar',
                                subtitle:
                                    'Yayınlanmış sınavların uygulama süreçlerini takip edin ve optik okuma sonuçlarını sisteme aktarın.',
                                icon: Icons.assignment_turned_in_rounded,
                                iconColor: Colors.teal,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (ctx) => ActiveExamListScreen(
                                      institutionId: widget.institutionId,
                                      schoolTypeId: widget.schoolTypeId,
                                    ),
                                  ),
                                ),
                                statusText: 'Şu an devam eden 4 sınav var',
                                isActive: true,
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      return Column(
                        children: [
                          _buildSecondaryCard(
                            title: 'Denemeler',
                            subtitle: 'Yeni deneme sınavları kurgulayın...',
                            icon: Icons.edit_note_rounded,
                            iconColor: Colors.purple,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (ctx) => TrialExamListScreen(
                                  institutionId: widget.institutionId,
                                  schoolTypeId: widget.schoolTypeId,
                                ),
                              ),
                            ),
                            actions: ['Yeni Oluştur', 'Yayınla', 'Arşiv'],
                          ),
                          const SizedBox(height: 24),
                          _buildSecondaryCard(
                            title: 'Sınavlar',
                            subtitle:
                                'Yayınlanmış sınavların uygulama süreçlerini takip edin...',
                            icon: Icons.assignment_turned_in_rounded,
                            iconColor: Colors.teal,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (ctx) => ActiveExamListScreen(
                                  institutionId: widget.institutionId,
                                  schoolTypeId: widget.schoolTypeId,
                                ),
                              ),
                            ),
                            statusText: 'Şu an devam eden 4 sınav var',
                            isActive: true,
                          ),
                        ],
                      );
                    }
                  },
                ),

                const SizedBox(height: 24),

                if (_schoolStage == 'ortaokul' ||
                    _schoolStage == 'lise' ||
                    _schoolStage == 'genel') ...[
                  _buildSecondaryCard(
                    title: _schoolStage == 'ortaokul'
                        ? 'LGS ŞAMPİYONLARI'
                        : (_schoolStage == 'lise'
                              ? 'YKS ŞAMPİYONLARI'
                              : 'LGS & YKS ŞAMPİYONLARI'),
                    subtitle: _schoolStage == 'lise'
                        ? 'Aktif dönem deneme sınavı verilerine göre YKS derece adaylarını ve tüm öğrencilerin yaklaşık yüzdelik / Türkiye sıralama ihtimallerini listeler.'
                        : 'Aktif dönem deneme sınavı verilerine göre LGS şampiyon adaylarını ve tüm öğrencilerin yaklaşık Türkiye yüzdelik dilim ihtimallerini listeler.',
                    icon: Icons.emoji_events_rounded,
                    iconColor: Colors.amber.shade800,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => ChampionsLeagueLoaderScreen(
                            institutionId: widget.institutionId,
                            schoolTypeId: widget.schoolTypeId,
                            schoolTypeName: _schoolTypeName,
                          ),
                        ),
                      );
                    },
                    actions: const [
                      'Şampiyon Kürsüsü',
                      'Tüm Öğrenci % İhtimalleri',
                      'Derece PDF',
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                // Row 3: Hata Kitapçığı & Fokus Kitap (Kişiye Özel Soru Bankası)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final hataCard = _buildSecondaryCard(
                      title: 'Hata Kitapçığı',
                      subtitle:
                          'Sınav PDF\'lerini sisteme yükleyin, soruları kırpın ve öğrencinin yanlış/boş sorularından hata kitapçığı üretin.',
                      icon: Icons.auto_stories_rounded,
                      iconColor: Colors.deepOrange,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => ErrorBookletDashboardScreen(
                              institutionId: widget.institutionId,
                              schoolTypeId: widget.schoolTypeId,
                            ),
                          ),
                        );
                      },
                      actions: ['PDF Yükle', 'Soru Kırp', 'Kitapçık Oluştur'],
                    );
                    final fokusCard = _buildSecondaryCard(
                      title: 'Fokus Kitap (Kişiye Özel Soru Bankası)',
                      subtitle:
                          'Deneme kazanım analizine ve öğrenci seviyesine göre soru havuzundan sayfa sayısı, kapak, ön söz (manuel/ek PDF) ve içindekiler kontrollü akıllı soru bankası üretin.',
                      icon: Icons.menu_book_rounded,
                      iconColor: const Color(0xFF0F766E),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => PersonalizedBookDashboardScreen(
                              institutionId: widget.institutionId,
                              schoolTypeId: widget.schoolTypeId,
                            ),
                          ),
                        );
                      },
                      actions: const [
                        'Kazanım & Seviye Analizi',
                        'Sayfa & Kapak Tasarımı',
                        'Bireysel / Toplu ZIP',
                      ],
                    );
                    if (constraints.maxWidth > 850) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: hataCard),
                            const SizedBox(width: 24),
                            Expanded(child: fokusCard),
                          ],
                        ),
                      );
                    }
                    return Column(
                      children: [
                        hataCard,
                        const SizedBox(height: 24),
                        fokusCard,
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Row 3.5: Genel Merkez Deneme Raporları
                _buildSecondaryCard(
                  title: 'Genel Merkez Deneme Raporları',
                  subtitle:
                      'Genel Merkez tarafından uygulanan Türkiye / bölge / kurum karşılaştırmalı deneme değerlendirme ve kazanım ihtiyaç raporlarını inceleyin.',
                  icon: Icons.workspace_premium_rounded,
                  iconColor: Colors.indigo,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => CentralSchoolReportsScreen(
                          institutionId: widget.institutionId,
                          schoolTypeId: widget.schoolTypeId,
                        ),
                      ),
                    );
                  },
                  actions: const [
                    'Genel & Bölge Sıralaması',
                    'İhtiyaç Analizi',
                    'Resmi PDF Rapor',
                  ],
                ),

                const SizedBox(height: 24),

                // Row 4: Soru Havuzu
                _buildSecondaryCard(
                  title: 'Soru Havuzu',
                  subtitle:
                      'Biriktirilen sorulardan test, deneme sınavı veya ödev oluşturun. Konu bazlı otomatik seçim ve akıllı sıralama algoritmasıyla optimum soru dizgisi elde edin.',
                  icon: Icons.layers_rounded,
                  iconColor: Colors.indigo,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => QuestionPoolScreen(
                          institutionId: widget.institutionId,
                          schoolTypeId: widget.schoolTypeId,
                        ),
                      ),
                    );
                  },
                  actions: ['Test', 'Deneme Sınavı', 'Ödev'],
                ),

                const SizedBox(height: 24),

                // Row 5: Dış Katılımlı Sınav
                _buildExternalExamCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTanimlarCard() {
    final isDesktop = MediaQuery.sizeOf(context).width > 850;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(isDesktop ? 32 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.library_books_rounded,
              color: Colors.indigo,
              size: 24,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Tanımlar',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sınav türlerini yapılandırın, optik form şablonlarını yönetin\nve akademik kazanımları eşleştirin.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.grey.shade500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          SafeStreamBuilder<int>(
            stream: _examTypesCountStream,
            builder: (context, typeSnapshot) {
              return SafeStreamBuilder<int>(
                stream: _opticalFormsCountStream,
                builder: (context, formSnapshot) {
                  return SafeStreamBuilder<List<OutcomeList>>(
                    stream: _outcomeListsStream,
                    builder: (context, outcomeSnapshot) {
                      int totalOutcomesCount = 0;
                      if (outcomeSnapshot.hasData &&
                          outcomeSnapshot.data != null) {
                        for (final list in outcomeSnapshot.data!) {
                          totalOutcomesCount += list.outcomes.length;
                        }
                      }

                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _buildStatBox(
                            'TÜRLER',
                            '${typeSnapshot.data ?? 0} Sınav Türü',
                          ),
                          _buildStatBox(
                            'FORMLAR',
                            '${formSnapshot.data ?? 0} Aktif Optik',
                          ),
                          _buildStatBox(
                            'KAZANIM',
                            _formatDataCount(totalOutcomesCount),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),

          const SizedBox(height: 48),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => AssessmentDefinitionsScreen(
                  institutionId: widget.institutionId,
                ),
              ),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            label: const Text('Yönetmeye Başla'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.indigo,
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDataCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k Veri';
    }
    return '$count Veri';
  }

  Widget _buildStatBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRaporlarCard() {
    final isDesktop = MediaQuery.sizeOf(context).width > 850;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: EdgeInsets.all(isDesktop ? 32 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bar_chart_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Raporlar',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sınav sonuçlarını, öğrenci gelişim grafiklerini ve kurumsal başarı metriklerini detaylıca inceleyin.',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => AssessmentReportsScreen(
                  institutionId: widget.institutionId,
                  schoolTypeId: widget.schoolTypeId,
                ),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.indigo.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              minimumSize: const Size(double.infinity, 54),
              elevation: 0,
            ),
            child: const Text(
              'Raporları Aç',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    List<String>? actions,
    String? statusText,
    bool isActive = false,
  }) {
    final isDesktop = MediaQuery.sizeOf(context).width > 850;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: EdgeInsets.all(isDesktop ? 24 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (actions != null)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: actions
                    .map(
                      (a) => Chip(
                        label: Text(a, style: const TextStyle(fontSize: 12)),
                        backgroundColor: const Color(0xFFF1F5F9),
                        side: BorderSide.none,
                      ),
                    )
                    .toList(),
              ),
            if (isActive)
              SafeStreamBuilder<List<TrialExam>>(
                stream: _trialExamsStream,
                builder: (context, snapshot) {
                  final activeCount =
                      snapshot.data?.where((e) => e.isPublished).length ?? 0;
                  final launchedCount =
                      snapshot.data?.where((e) => e.isLaunched).length ?? 0;

                  return Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$activeCount AKTİF',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Şu an devam eden $launchedCount sınav var',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExternalExamCard() {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => ExternalExamListScreen(
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8F00), Color(0xFFF57C00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(28),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Dış Katılımlı Sınav',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bursluluk, prova ve deneme sınavları için başvuru yönetimi, salon planlaması ve giriş belgesi oluşturun.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildWhiteChip('Başvuru Yönetimi'),
                      _buildWhiteChip('Salon Planı'),
                      _buildWhiteChip('Giriş Belgesi'),
                      _buildWhiteChip('SMS & E-posta'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWhiteChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
