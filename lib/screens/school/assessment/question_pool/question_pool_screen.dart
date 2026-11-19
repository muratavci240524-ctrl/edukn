import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../services/assessment_service.dart';
import '../../../../services/error_booklet_generator_service.dart';
import '../../../../models/assessment/outcome_list_model.dart';
import '../../../../utils/drive_image_helper.dart';
import '../../../../utils/difficulty_scale.dart';
import '../../../../utils/gercek_kazanim_mapper.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';
import 'package:edukn/widgets/pdf_generating_overlay.dart';
import '../error_booklet/error_booklet_editor_screen.dart';
import 'google_sheets_pool_import_dialog.dart';
import 'pool_auto_wide_fixer.dart';

class _TopicGroup {
  final String key;
  final String code;
  final String title;
  final List<OutcomeItem> subOutcomes;
  final List<Map<String, dynamic>> allQuestions;
  final Map<String, List<Map<String, dynamic>>> questionsBySubOutcome;

  _TopicGroup({
    required this.key,
    required this.code,
    required this.title,
    required this.subOutcomes,
    required this.allQuestions,
    required this.questionsBySubOutcome,
  });
}

// ─── Models ───────────────────────────────────────────────────────────────────

enum TestType { test, deneme, odev }
enum QuestionSelectionMethod { manuel, otomatik }
enum SortingAlgorithm { fixed, smart, none }

extension TestTypeLabel on TestType {
  String get label {
    switch (this) {
      case TestType.test: return 'Test';
      case TestType.deneme: return 'Deneme Sınavı';
      case TestType.odev: return 'Ödev';
    }
  }
  IconData get icon {
    switch (this) {
      case TestType.test: return Icons.quiz_outlined;
      case TestType.deneme: return Icons.assignment_outlined;
      case TestType.odev: return Icons.home_work_outlined;
    }
  }
  Color get color {
    switch (this) {
      case TestType.test: return Colors.indigo;
      case TestType.deneme: return Colors.purple;
      case TestType.odev: return Colors.teal;
    }
  }
}

extension QuestionSelectionLabel on QuestionSelectionMethod {
  String get label {
    switch (this) {
      case QuestionSelectionMethod.manuel: return 'Manuel';
      case QuestionSelectionMethod.otomatik: return 'Seçilen Konulardan Otomatik';
    }
  }
  IconData get icon {
    switch (this) {
      case QuestionSelectionMethod.manuel: return Icons.touch_app_outlined;
      case QuestionSelectionMethod.otomatik: return Icons.auto_awesome_outlined;
    }
  }
}

extension SortingLabel on SortingAlgorithm {
  String get label {
    switch (this) {
      case SortingAlgorithm.fixed: return 'Fixed';
      case SortingAlgorithm.smart: return 'Smart';
      case SortingAlgorithm.none: return 'Yerleştirme Yok';
    }
  }
  String get description {
    switch (this) {
      case SortingAlgorithm.fixed: return 'Sorular eklendiği sırayla kalır';
      case SortingAlgorithm.smart: return 'Akıllı algoritma en iyi dizgi için soru sırasını otomatik ayarlar';
      case SortingAlgorithm.none: return 'Sıralama uygulanmaz';
    }
  }
}

// ─── Main Screen ──────────────────────────────────────────────────────────────

class QuestionPoolScreen extends StatefulWidget {
  final String institutionId;
  final String? schoolTypeId;
  final String? schoolTypeName;

  const QuestionPoolScreen({
    Key? key,
    required this.institutionId,
    this.schoolTypeId,
    this.schoolTypeName,
  }) : super(key: key);

  @override
  State<QuestionPoolScreen> createState() => _QuestionPoolScreenState();
}

class _QuestionPoolScreenState extends State<QuestionPoolScreen> {
  // ─── Tüm Soru Havuzu Hiyerarşik Filtre & Sayfalama State ─────────────────
  static const int _questionsPerPage = 8;
  String? _selectedClassLevel;
  String? _selectedBranch;
  String? _selectedTopicKey;
  String? _selectedSubOutcomeDesc;
  String _selectedDifficultyFilter = 'Tümü'; // 'Tümü', 'Çok Kolay', 'Kolay', 'Orta', 'Zor', 'Çok Zor'
  final Set<String> _enabledPoolKinds = {'coktan_secmeli', 'egzersiz', 'deneme'};
  final Set<String> _expandedTopicKeys = {};
  bool _branchTreeCollapsed = false;
  int _currentPoolPage = 1;

  List<OutcomeList> _outcomeLists = [];

  static bool isExerciseQuestion(Map<String, dynamic> q) {
    final t = _normTr((q['questionType'] ?? '').toString());
    return t.contains('egzersiz') || t.contains('etkinlik');
  }

  static bool isDenemeQuestion(Map<String, dynamic> q) {
    if (isExerciseQuestion(q)) return false;
    final src = (q['sourceType'] ?? '').toString().trim().toLowerCase();
    if (src == 'google_sheets' || src == 'pool_manual') return false;
    final examId = (q['examId'] ?? '').toString().trim();
    if (examId.isNotEmpty && !examId.startsWith('pool_')) return true;
    if (q['isCentralPool'] == true) return true;
    final examName = _normTr((q['examName'] ?? '').toString());
    if (examName.contains('deneme')) return true;
    return false;
  }

  /// Soru kaynağı/türü kategorisi:
  /// - `'coktan_secmeli'`: Havuz / Tablo Çoktan Seçmeli Soruları
  /// - `'egzersiz'`: Egzersiz / Etkinlik Soruları
  /// - `'deneme'`: Deneme Sınavı (Hata Kitapçığı) Soruları
  static String questionKindCategory(Map<String, dynamic> q) {
    if (isExerciseQuestion(q)) return 'egzersiz';
    if (isDenemeQuestion(q)) return 'deneme';
    return 'coktan_secmeli';
  }

  static const List<String> _allStandardClassLevels = [
    '5. Sınıf',
    '6. Sınıf',
    '7. Sınıf',
    '8. Sınıf',
    '9. Sınıf',
    '10. Sınıf',
    '11. Sınıf',
    '12. Sınıf',
    'LGS',
    'TYT',
    'AYT',
  ];

  final AssessmentService _assessmentService = AssessmentService();
  late Stream<QuerySnapshot> _testsStream;
  late Stream<List<Map<String, dynamic>>> _globalPoolStream;
  StreamSubscription<List<Map<String, dynamic>>>? _poolSub;
  List<Map<String, dynamic>> _poolDocs = [];
  bool _isPoolLoading = true;
  Object? _poolError;
  StreamSubscription<List<OutcomeList>>? _outcomeListsSub;

  @override
  void initState() {
    super.initState();
    _initStreams();
    _loadOutcomeDefinitions();
  }

  @override
  void didUpdateWidget(covariant QuestionPoolScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId) {
      _initStreams();
      _loadOutcomeDefinitions();
    }
  }

  @override
  void dispose() {
    _poolSub?.cancel();
    _outcomeListsSub?.cancel();
    super.dispose();
  }

  void _initStreams() {
    _testsStream = FirebaseFirestore.instance
        .collection('institutions')
        .doc(widget.institutionId)
        .collection('question_pool_tests')
        .orderBy('createdAt', descending: true)
        .snapshots();
    final cached = AssessmentService.getCachedQuestionsPool(widget.institutionId);
    if (cached != null && cached.isNotEmpty) {
      _poolDocs = cached;
      _isPoolLoading = false;
    } else {
      _isPoolLoading = _poolDocs.isEmpty;
    }
    _poolError = null;
    _globalPoolStream = _assessmentService.getGlobalQuestionsPool(
      widget.institutionId,
    );
    _poolSub?.cancel();
    _poolSub = _globalPoolStream.listen(
      (docs) {
        if (!mounted) return;
        setState(() {
          _poolDocs = docs;
          _isPoolLoading = false;
          _poolError = null;
        });
      },
      onError: (Object err) {
        if (!mounted) return;
        setState(() {
          _isPoolLoading = false;
          _poolError = err;
        });
      },
    );
  }

  void _loadOutcomeDefinitions() {
    _outcomeListsSub?.cancel();
    _outcomeListsSub = _assessmentService
        .getOutcomeLists(widget.institutionId)
        .listen((lists) {
          PoolAutoWideFixer.scheduleOutcomeListsMigration(lists);
          if (mounted) {
            setState(() => _outcomeLists = lists);
          }
        });
  }

  static String _normTr(String input) {
    return input
        .trim()
        .replaceAll('İ', 'i')
        .replaceAll('I', 'i')
        .replaceAll('ı', 'i')
        .replaceAll('Ş', 's')
        .replaceAll('ş', 's')
        .replaceAll('Ğ', 'g')
        .replaceAll('ğ', 'g')
        .replaceAll('Ü', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('Ö', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('Ç', 'c')
        .replaceAll('ç', 'c')
        .toLowerCase();
  }

  static final RegExp _nonAlnumKeyRe = RegExp(r'[^a-z0-9]');
  static final RegExp _natCompareRe = RegExp(r'\d+|\D+');
  static final RegExp _wsOrParenRe = RegExp(r'[\s(]');

  static String _normOutcomeKey(String input) {
    return _normTr(input).replaceAll(_nonAlnumKeyRe, '');
  }

  static int _naturalCompare(String a, String b) {
    // Türkçe harf sırası için sıralama anahtarı (ç→c~, ğ→g~, ı→h~, ö→o~, ş→s~, ü→u~)
    String key(String s) => s
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase()
        .replaceAll('ç', 'c~')
        .replaceAll('ğ', 'g~')
        .replaceAll('ı', 'h~')
        .replaceAll('ö', 'o~')
        .replaceAll('ş', 's~')
        .replaceAll('ü', 'u~');
    final pa = _natCompareRe.allMatches(key(a)).map((m) => m.group(0)!).toList();
    final pb = _natCompareRe.allMatches(key(b)).map((m) => m.group(0)!).toList();
    for (int i = 0; i < pa.length && i < pb.length; i++) {
      final na = int.tryParse(pa[i]);
      final nb = int.tryParse(pb[i]);
      final int c = (na != null && nb != null) ? na.compareTo(nb) : pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return pa.length.compareTo(pb.length);
  }


  static String _canonicalBranchName(String raw) {
    final n = _normTr(raw);
    if (n.contains('turkce')) return 'Türkçe';
    if (n.contains('matematik')) return 'Matematik';
    if (n.contains('fen')) return 'Fen Bilimleri';
    if (n.contains('inkilap')) return 'T.C. İnkılap Tarihi';
    if (n.contains('sosyal')) return 'Sosyal Bilgiler';
    if (n.contains('din')) return 'Din Kültürü ve Ahlak Bilgisi';
    if (n.contains('ingilizce') || n.contains('yabanci dil')) return 'İngilizce';
    if (n.contains('fizik')) return 'Fizik';
    if (n.contains('kimya')) return 'Kimya';
    if (n.contains('biyoloji')) return 'Biyoloji';
    if (n.contains('tarih')) return 'Tarih';
    if (n.contains('cografya')) return 'Coğrafya';
    if (n.contains('edebiyat')) return 'Türk Dili ve Edebiyatı';
    if (n.contains('felsefe')) return 'Felsefe';
    return raw.trim().isEmpty ? 'Diğer' : raw.trim();
  }

  static bool _branchesMatch(String a, String b) {
    return _canonicalBranchName(a) == _canonicalBranchName(b) ||
        _normTr(a) == _normTr(b);
  }

  static bool _classLevelsMatch(String a, String b) {
    final na = AssessmentService.normalizeClassLevel(a);
    final nb = AssessmentService.normalizeClassLevel(b);
    return _normTr(na) == _normTr(nb);
  }

  void _openTestWizard({Map<String, dynamic>? editingData}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _TestCreationWizard(
          institutionId: widget.institutionId,
          schoolTypeId: widget.schoolTypeId,
          schoolTypeName: widget.schoolTypeName,
          editingData: editingData,
          outcomeLists: _outcomeLists,
        ),
      ),
    );
  }

  BuildContext? _tabContext;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (tabCtx) {
          _tabContext = tabCtx;
          return Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            appBar: _buildAppBar(),
            body: TabBarView(
              children: [
                _buildTestsTab(),
                _buildPoolTab(),
              ],
            ),
          );
        },
      ),
    );
  }

  EduknAppBar _buildAppBar() => EduknAppBar(
        title: 'Soru Havuzu',
        subtitle: widget.schoolTypeName ?? 'Test & Ödev Yönetimi',
        bottom: TabBar(
          labelColor: Colors.indigo,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.indigo,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'Testler & Ödevler'),
            Tab(text: 'Tüm Soru Havuzu'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: OutlinedButton.icon(
              onPressed: _openGoogleSheetsImportDialog,
              icon: const Icon(Icons.table_chart_outlined, size: 17),
              label: const Text('Tablodan Soru Aktar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F766E),
                side: const BorderSide(color: Color(0xFF0F766E)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: OutlinedButton.icon(
              onPressed: _openPoolCropStudio,
              icon: const Icon(Icons.crop_rounded, size: 17),
              label: const Text('Havuza Soru Ekle',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.indigo,
                side: BorderSide(color: Colors.indigo.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: FilledButton.icon(
              onPressed: () => _openTestWizard(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Yeni Test Oluştur',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.indigo,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      );

  Future<void> _openGoogleSheetsImportDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GoogleSheetsPoolImportDialog(
        institutionId: widget.institutionId,
        existingOutcomeLists: _outcomeLists,
      ),
    );
    if (result != null && mounted) {
      final int importedCount = (result['importedCount'] as int?) ?? 0;
      final int syncedCount = (result['syncedOutcomeCount'] as int?) ?? 0;
      final int updatedCount = (result['updatedCount'] as int?) ?? 0;
      final int removedCount = (result['removedCount'] as int?) ?? 0;
      final int newCount = importedCount - updatedCount;
      final String? cls = result['classLevel'] as String?;
      final String? sub = result['subject'] as String?;
      AssessmentService.invalidatePoolCache('pool_${widget.institutionId}');
      _initStreams();
      setState(() {
        if (cls != null && cls.isNotEmpty) _selectedClassLevel = cls;
        if (sub != null && sub.isNotEmpty) _selectedBranch = sub;
        _selectedTopicKey = null;
        _selectedSubOutcomeDesc = null;
        _currentPoolPage = 1;
      });
      DefaultTabController.maybeOf(_tabContext ?? context)?.animateTo(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0F766E),
          content: Text(
            '✓ Tablo aktarıldı: $newCount yeni soru, $updatedCount soru güncellendi'
            '${removedCount > 0 ? ', $removedCount eski soru kaldırıldı' : ''}'
            '${syncedCount > 0 ? ' ($syncedCount K12 kazanımı listeye eklendi)' : ''}.',
          ),
        ),
      );
    }
  }

  void _openPoolCropStudio() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ErrorBookletEditorScreen.forQuestionPool(
          institutionId: widget.institutionId,
          classLevel: _selectedClassLevel ?? '7. Sınıf',
        ),
      ),
    );
  }

  Widget _buildTestsTab() {
    return SafeStreamBuilder<QuerySnapshot>(
      stream: _testsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroBanner(),
                  const SizedBox(height: 32),
                  if (docs.isEmpty) _buildEmptyState() else _buildTestList(docs),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPoolTab() {
    if (_isPoolLoading && _poolDocs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_poolError != null && _poolDocs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Soru havuzu yüklenirken bir hata oluştu:\n$_poolError',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red.shade700),
          ),
        ),
      );
    }

    final docs = _poolDocs;

    if (docs.isEmpty) {
      return _buildEmptyPoolState();
    }

    // 1. Sınıf seviyelerini ve her sınıftaki soru sayılarını hesapla
    final Map<String, List<Map<String, dynamic>>> byClass = {};
    for (final q in docs) {
      final cls = (q['_cachedNormClass'] as String?) ??
          (q['_cachedNormClass'] = AssessmentService.normalizeClassLevel(
            q['classLevel']?.toString(),
            examName: q['examName']?.toString(),
          ));
      byClass.putIfAbsent(cls, () => []).add(q);
    }
    // Ayrıca outcome_lists'te tanımlı olan sınıf seviyelerini de listeye dahil et
    for (final ol in _outcomeLists) {
      final cls = AssessmentService.normalizeClassLevel(ol.classLevel);
      byClass.putIfAbsent(cls, () => []);
    }

    final List<String> availableClasses = [
      for (final std in _allStandardClassLevels)
        if (byClass.containsKey(std)) std,
      for (final k in byClass.keys)
        if (!_allStandardClassLevels.contains(k)) k,
    ];

    // Varsayılan sınıf seçimi (en çok sorusu olan sınıf)
    String activeClass = _selectedClassLevel ?? '';
    if (activeClass.isEmpty || !byClass.containsKey(activeClass)) {
      String bestCls = availableClasses.isNotEmpty ? availableClasses.first : '7. Sınıf';
      int bestCount = -1;
      for (final c in availableClasses) {
        final cnt = byClass[c]?.length ?? 0;
        if (cnt > bestCount) {
          bestCount = cnt;
          bestCls = c;
        }
      }
      activeClass = bestCls;
    }

    final List<Map<String, dynamic>> classQuestions = byClass[activeClass] ?? [];

    // 2. Seçili sınıftaki Branşları ve soru sayılarını hesapla
    final Map<String, List<Map<String, dynamic>>> byBranch = {};
    for (final q in classQuestions) {
      final branch = (q['_cachedCanonBranch'] as String?) ??
          (q['_cachedCanonBranch'] = _canonicalBranchName((q['subject'] ?? 'Diğer').toString()));
      byBranch.putIfAbsent(branch, () => []).add(q);
    }
    for (final ol in _outcomeLists) {
      if (_classLevelsMatch(ol.classLevel, activeClass)) {
        final branch = _canonicalBranchName(ol.branchName);
        byBranch.putIfAbsent(branch, () => []);
      }
    }

    final List<String> branchOrder = [
      'Türkçe',
      'Matematik',
      'Fen Bilimleri',
      'Sosyal Bilgiler',
      'T.C. İnkılap Tarihi',
      'Din Kültürü ve Ahlak Bilgisi',
      'İngilizce',
      'Türk Dili ve Edebiyatı',
      'Fizik',
      'Kimya',
      'Biyoloji',
      'Tarih',
      'Coğrafya',
      'Felsefe',
    ];
    final List<String> availableBranches = [
      for (final b in branchOrder)
        if (byBranch.containsKey(b)) b,
      for (final b in byBranch.keys)
        if (!branchOrder.contains(b)) b,
    ];

    String? activeBranch = _selectedBranch;
    if (activeBranch != null && !byBranch.containsKey(activeBranch)) {
      activeBranch = null;
    }
    if (activeBranch == null && availableBranches.isNotEmpty) {
      // İlk açılışta sorusu olan ilk branşı seç
      activeBranch = availableBranches.firstWhere(
        (b) => (byBranch[b]?.isNotEmpty ?? false),
        orElse: () => availableBranches.first,
      );
    }

    final List<Map<String, dynamic>> allBranchQuestions =
        activeBranch != null ? (byBranch[activeBranch] ?? []) : [];
    final List<Map<String, dynamic>> branchQuestions = allBranchQuestions
        .where((q) {
          final k = (q['_cachedKindCat'] as String?) ??
              (q['_cachedKindCat'] = questionKindCategory(q));
          return _enabledPoolKinds.contains(k);
        })
        .toList();

    // 3. Seçili Sınıf + Branş için Konu (depth=1) ve Alt Kazanım (depth=2) ağacını kur
    final List<_TopicGroup> topics = activeBranch != null
        ? _buildTopicsForBranch(activeClass, activeBranch, branchQuestions)
        : [];

    // 4. Seçili Konu / Alt Kazanım / Zorluk filtresine göre sağ paneldeki soruları belirle
    List<Map<String, dynamic>> filteredQuestions = branchQuestions;
    _TopicGroup? selectedTopicObj;
    if (_selectedTopicKey != null) {
      for (final t in topics) {
        if (t.key == _selectedTopicKey) {
          selectedTopicObj = t;
          break;
        }
      }
    }
    if (selectedTopicObj != null) {
      if (_selectedSubOutcomeDesc != null &&
          selectedTopicObj.questionsBySubOutcome.containsKey(_selectedSubOutcomeDesc)) {
        filteredQuestions =
            selectedTopicObj.questionsBySubOutcome[_selectedSubOutcomeDesc] ?? [];
      } else {
        filteredQuestions = selectedTopicObj.allQuestions;
      }
    }

    if (_selectedDifficultyFilter != 'Tümü') {
      filteredQuestions = filteredQuestions.where((q) {
        final d = (q['difficulty'] as num?)?.toDouble();
        final lbl = DifficultyScale.labelOf(d ?? DifficultyScale.defaultScore);
        return lbl == _selectedDifficultyFilter;
      }).toList();
    }

    final int totalFiltered = filteredQuestions.length;
    final int totalPages =
        totalFiltered == 0 ? 1 : ((totalFiltered + _questionsPerPage - 1) ~/ _questionsPerPage);
    final int safePage = _currentPoolPage.clamp(1, totalPages);
    final int startIndex = (safePage - 1) * _questionsPerPage;
    final List<Map<String, dynamic>> pageQuestions = totalFiltered == 0
        ? const []
        : filteredQuestions.skip(startIndex).take(_questionsPerPage).toList();

    // Yalnızca ekrandaki 8 sorunun sütun genişliğini (1/2 Sütun) arka planda kontrol et
    PoolAutoWideFixer.schedule(
      docs,
      visibleDocs: pageQuestions,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );

    final isMobile = MediaQuery.of(context).size.width < 950;

    if (isMobile) {
      return Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildPoolSidebarPanel(
                  availableClasses: availableClasses,
                  byClass: byClass,
                  activeClass: activeClass,
                  availableBranches: availableBranches,
                  byBranch: byBranch,
                  activeBranch: activeBranch,
                  topics: topics,
                  totalPoolCount: docs.length,
                  isMobile: true,
                ),
                const SizedBox(height: 12),
                _buildPoolRightHeader(
                  activeClass: activeClass,
                  activeBranch: activeBranch,
                  selectedTopicObj: selectedTopicObj,
                  allBranchQuestions: allBranchQuestions,
                  totalFiltered: totalFiltered,
                  safePage: safePage,
                  totalPages: totalPages,
                ),
                const SizedBox(height: 12),
                if (pageQuestions.isEmpty)
                  _buildNoQuestionsForFilterState()
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 340,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      mainAxisExtent: 300,
                    ),
                    itemCount: pageQuestions.length,
                    itemBuilder: (ctx, i) => _buildPoolQuestionCard(pageQuestions[i]),
                  ),
                const SizedBox(height: 12),
                if (totalFiltered > 0)
                  _buildPaginationBar(
                    safePage: safePage,
                    totalPages: totalPages,
                    totalFiltered: totalFiltered,
                    startIndex: startIndex,
                    shownCount: pageQuestions.length,
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // SOL PANEL: Sınıf -> Branş (Soru Sayısı) -> Konu (Soru Sayısı) -> Alt Kazanım (Soru Sayısı)
        SizedBox(
          width: 360,
          child: _buildPoolSidebarPanel(
            availableClasses: availableClasses,
            byClass: byClass,
            activeClass: activeClass,
            availableBranches: availableBranches,
            byBranch: byBranch,
            activeBranch: activeBranch,
            topics: topics,
            totalPoolCount: docs.length,
            isMobile: false,
          ),
        ),
        // SAĞ PANEL: Seçilen filtrenin 8 soruluk sayfalı görünümü
        Expanded(
          child: Column(
            children: [
              _buildPoolRightHeader(
                activeClass: activeClass,
                activeBranch: activeBranch,
                selectedTopicObj: selectedTopicObj,
                allBranchQuestions: allBranchQuestions,
                totalFiltered: totalFiltered,
                safePage: safePage,
                totalPages: totalPages,
              ),
              Expanded(
                child: pageQuestions.isEmpty
                    ? _buildNoQuestionsForFilterState()
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          mainAxisExtent: 295,
                        ),
                        itemCount: pageQuestions.length,
                        itemBuilder: (ctx, i) => _buildPoolQuestionCard(pageQuestions[i]),
                      ),
              ),
              if (totalFiltered > 0)
                _buildPaginationBar(
                  safePage: safePage,
                  totalPages: totalPages,
                  totalFiltered: totalFiltered,
                  startIndex: startIndex,
                  shownCount: pageQuestions.length,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Ölçme Değerlendirme > Tanımlar > Kazanım Listesi Tanımlamaları (`_outcomeLists`)
  /// içindeki Konu (`depth == 1`) ve Alt Kazanım (`depth == 2`) yapısını kullanarak
  /// seçili Sınıf ve Branşın konu-kazanım ağacını ve her birinin soru sayısını hesaplar.
  List<_TopicGroup> _buildTopicsForBranch(
    String classLevel,
    String branchName,
    List<Map<String, dynamic>> branchQuestions,
  ) =>
      buildTopicsForBranch(_outcomeLists, classLevel, branchName, branchQuestions);

  /// "Tam Sayılar ve Rasyonel Sayılar (Mutlak Değer)" → (konu: "Tam Sayılar ve Rasyonel Sayılar", alt: "Mutlak Değer").
  /// Eski tablolarda Konu sütununa "Konu (Alt Konu)" şeklinde yazılmış başlıkları ayırır.
  static ({String konu, String alt}) splitKonuAltKonu(String raw) {
    final s = raw.trim();
    if (!s.endsWith(')')) return (konu: s, alt: '');
    // En dıştaki (son) parantez grubunu bul (iç içe parantez destekli)
    int depth = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      final ch = s[i];
      if (ch == ')') depth++;
      if (ch == '(') {
        depth--;
        if (depth == 0) {
          final konu = s.substring(0, i).trim();
          final alt = s.substring(i + 1, s.length - 1).trim();
          if (konu.isEmpty || alt.isEmpty) return (konu: s, alt: '');
          return (konu: konu, alt: alt);
        }
      }
    }
    return (konu: s, alt: '');
  }

  static String _baseKazanimKey(String code) {
    final c = code.trim();
    if (c.isEmpty) return '';
    final cut = c.split(_wsOrParenRe).first;
    return _normOutcomeKey(cut);
  }

  /// Sol liste ağacı: **Konu (klasör) → Alt Konu**.
  /// - Konu: sorunun `topic` alanı (eski "Konu (Alt Konu)" biçimi otomatik ayrılır).
  /// - Alt Konu: tablodaki "Alt Konu" sütunu (`altKonu`), yoksa `subTopic`.
  /// - Konusu/alt konusu olmayan sorular (ör. Hata Kitapçığı) aynı Gerçek Kazanım koduna sahip
  ///   tablo sorularından veya kurum kazanım listesinden konuya otomatik yerleştirilir.
  /// Sol listede kazanım satırı gösterilmez; sorusu olmayan boş başlıklar gizlenir.
  static List<_TopicGroup> buildTopicsForBranch(
    List<OutcomeList> outcomeLists,
    String classLevel,
    String branchName,
    List<Map<String, dynamic>> branchQuestions,
  ) {
    const String otherTopic = 'Diğer Sorular';

    // 1) Kazanımları bellekte Gerçek Kazanım (2026-2027 TYMM) biçimine dönüştür (her soru için yalnızca 1 kez)
    for (final q in branchQuestions) {
      if (q['_kazanimNormalizedInTree'] == true) continue;
      q['_kazanimNormalizedInTree'] = true;
      final rawCode = (q['kazanimCode'] ?? '').toString().trim();
      final rawOut = (q['outcome'] ?? '').toString().trim();
      final rawK12 = (q['k12Code'] ?? '').toString().trim();
      final res = GercekKazanimMapper.resolve(
        kazanimCode: rawCode,
        outcomeText: rawOut,
        k12Code: rawK12,
      );
      if (res.code.isNotEmpty || res.description.isNotEmpty) {
        q['kazanimCode'] = res.code;
        q['outcome'] = res.description;
        if ((q['topic'] ?? '').toString().trim().isEmpty && res.topic.isNotEmpty) {
          q['topic'] = res.topic;
        }
      } else {
        if (GercekKazanimMapper.looksLikeLegacyOrK12Code(rawCode)) {
          q['kazanimCode'] = '';
        }
        if (rawOut.isNotEmpty) {
          q['outcome'] = GercekKazanimMapper.cleanLegacyDisplayText(rawOut);
        }
      }
      q.remove('k12Code');
      q.remove('k12OutcomeFull');
    }

    // 2) Kurum kazanım listesinden: konu sırası + kazanım kodu/metni → konu eşlemesi
    final matchingLists = outcomeLists.where((ol) {
      return _classLevelsMatch(ol.classLevel, classLevel) &&
          _branchesMatch(ol.branchName, branchName);
    }).toList();

    final Map<String, int> topicOrderFromLists = {};
    final Map<String, ({String konu, String alt})> listTopicByCode = {};
    final Map<String, ({String konu, String alt})> listTopicByDesc = {};
    for (final ol in matchingLists) {
      ({String konu, String alt})? current;
      for (final item in ol.outcomes) {
        final desc = item.description.trim();
        if (desc.isEmpty) continue;
        if (item.depth == 1) {
          current = splitKonuAltKonu(desc);
          topicOrderFromLists.putIfAbsent(
            _normOutcomeKey(current.konu),
            () => topicOrderFromLists.length,
          );
        } else if (current != null) {
          final res = GercekKazanimMapper.resolve(
            kazanimCode: item.code,
            outcomeText: item.description,
            k12Code: item.k12Code,
          );
          final code = res.code.isNotEmpty ? res.code : item.code;
          final baseKey = _baseKazanimKey(code);
          if (baseKey.length >= 3) listTopicByCode.putIfAbsent(baseKey, () => current!);
          final dKey = _normOutcomeKey(
            GercekKazanimMapper.splitOutcomeTextAndSubTopic(
              res.description.isNotEmpty ? res.description : desc,
            ).outcomeText,
          );
          if (dKey.isNotEmpty) listTopicByDesc.putIfAbsent(dKey, () => current!);
        }
      }
    }

    // 3) Her sorunun kendi Konu / Alt Konu bilgisi
    //    Alt Konu yalnızca tablodaki "Alt Konu" sütunundan (veya eski "Konu (Alt Konu)" biçiminden) alınır.
    //    Kazanım metninin parantezindeki çok detaylı ifadeler (ör. "Çok Anlamlılık: Yazmak Sözcüğü")
    //    alt başlık yapılmaz; aksi halde liste her soru için ayrı satırla kabarıyor.
    ({String konu, String alt}) ownKonuAlt(Map<String, dynamic> q) {
      final split = splitKonuAltKonu((q['topic'] ?? '').toString());
      String konu = split.konu;
      String alt = (q['altKonu'] ?? '').toString().trim();
      if (alt.isEmpty) alt = split.alt;
      return (konu: konu, alt: alt);
    }

    // Tablo sorularından öğren: Gerçek Kazanım kodu → en sık (Konu, Alt Konu)
    final Map<String, Map<String, int>> votesByCode = {};
    for (final q in branchQuestions) {
      final own = ownKonuAlt(q);
      if (own.konu.isEmpty || own.alt.isEmpty) continue;
      final key = _baseKazanimKey((q['kazanimCode'] ?? '').toString());
      if (key.length < 3) continue;
      final v = votesByCode.putIfAbsent(key, () => {});
      final pair = '${own.konu}\u0000${own.alt}';
      v[pair] = (v[pair] ?? 0) + 1;
    }
    final Map<String, ({String konu, String alt})> learnedByCode = {};
    votesByCode.forEach((code, votes) {
      String best = '';
      int bestCnt = -1;
      votes.forEach((pair, cnt) {
        if (cnt > bestCnt) {
          best = pair;
          bestCnt = cnt;
        }
      });
      final parts = best.split('\u0000');
      learnedByCode[code] = (konu: parts[0], alt: parts.length > 1 ? parts[1] : '');
    });

    // 4) Grupla: Konu → Alt Konu → Sorular
    final Map<String, String> konuDisplay = {}; // normKey -> görünen ad
    final Map<String, Map<String, String>> altDisplay = {}; // konu -> altNorm -> ad
    final Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {};
    final Map<String, int> konuFirstSeen = {};
    final Map<String, Map<String, int>> altFirstSeen = {};
    int seq = 0;

    for (final q in branchQuestions) {
      final own = ownKonuAlt(q);
      String konu = own.konu;
      String alt = own.alt;

      if (konu.isEmpty || alt.isEmpty) {
        final codeKey = _baseKazanimKey((q['kazanimCode'] ?? '').toString());
        ({String konu, String alt})? inferred = codeKey.length >= 3
            ? (learnedByCode[codeKey] ?? listTopicByCode[codeKey])
            : null;
        if (inferred == null) {
          final dKey = _normOutcomeKey(
            GercekKazanimMapper.splitOutcomeTextAndSubTopic(
              (q['outcome'] ?? '').toString(),
            ).outcomeText,
          );
          if (dKey.isNotEmpty) inferred = listTopicByDesc[dKey];
        }
        if (inferred != null) {
          if (konu.isEmpty) {
            konu = inferred.konu;
            if (alt.isEmpty) alt = inferred.alt;
          } else if (alt.isEmpty &&
              _normOutcomeKey(inferred.konu) == _normOutcomeKey(konu)) {
            alt = inferred.alt;
          }
        }
      }
      if (konu.isEmpty) konu = otherTopic;
      // Alt konusu belirtilmemiş sorular konu adıyla aynı alt başlıkta toplanır
      // (tablolardaki "Sözcükte Anlam → Sözcükte Anlam" kullanımıyla aynı)
      if (alt.isEmpty) alt = konu;

      final kKey = _normOutcomeKey(konu);
      final aKey = _normOutcomeKey(alt);
      konuDisplay.putIfAbsent(kKey, () => konu);
      final altNames = altDisplay.putIfAbsent(kKey, () => {});
      altNames.putIfAbsent(aKey, () => alt);
      grouped
          .putIfAbsent(kKey, () => {})
          .putIfAbsent(altNames[aKey]!, () => [])
          .add(q);

      // Sıralama: tablo soru numarası (yoksa görülme sırası)
      final bool isSheet = (q['sourceType'] ?? '').toString() == 'google_sheets';
      final int qNo = (num.tryParse('${q['questionNo']}') ?? 0).toInt();
      final int orderVal = isSheet ? qNo : 1000000 + seq;
      seq++;
      final prevK = konuFirstSeen[kKey];
      if (prevK == null || orderVal < prevK) konuFirstSeen[kKey] = orderVal;
      final altOrders = altFirstSeen.putIfAbsent(kKey, () => {});
      final altName = altNames[aKey]!;
      final prevA = altOrders[altName];
      if (prevA == null || orderVal < prevA) altOrders[altName] = orderVal;
    }

    // 5) Konu sırası: kurum listesindeki sıra → tablodaki sıra → alfabetik; "Diğer Sorular" en sonda
    final konuKeys = grouped.keys.toList()
      ..sort((a, b) {
        final aOther = a == _normOutcomeKey(otherTopic);
        final bOther = b == _normOutcomeKey(otherTopic);
        if (aOther != bOther) return aOther ? 1 : -1;
        final la = topicOrderFromLists[a];
        final lb = topicOrderFromLists[b];
        if (la != null && lb != null && la != lb) return la.compareTo(lb);
        if (la != null && lb == null) return -1;
        if (la == null && lb != null) return 1;
        final fa = konuFirstSeen[a] ?? 0;
        final fb = konuFirstSeen[b] ?? 0;
        if (fa != fb) return fa.compareTo(fb);
        return _naturalCompare(konuDisplay[a]!, konuDisplay[b]!);
      });

    final List<_TopicGroup> topicGroups = [];
    int idx = 0;
    for (final kKey in konuKeys) {
      idx++;
      final altMap = grouped[kKey]!;
      final altOrders = altFirstSeen[kKey] ?? const <String, int>{};
      final altNames = altMap.keys.toList()
        ..sort((a, b) {
          final oa = altOrders[a] ?? 0;
          final ob = altOrders[b] ?? 0;
          if (oa != ob) return oa.compareTo(ob);
          return _naturalCompare(a, b);
        });
      final subs = [
        for (final a in altNames) OutcomeItem(code: '', description: a, depth: 2),
      ];
      final allQs = [for (final a in altNames) ...altMap[a]!];
      topicGroups.add(
        _TopicGroup(
          key: 'topic_${idx}_$kKey',
          code: '',
          title: konuDisplay[kKey]!,
          subOutcomes: subs,
          allQuestions: allQs,
          questionsBySubOutcome: {for (final a in altNames) a: altMap[a]!},
        ),
      );
    }

    return topicGroups;
  }

  Widget _buildPoolSidebarPanel({
    required List<String> availableClasses,
    required Map<String, List<Map<String, dynamic>>> byClass,
    required String activeClass,
    required List<String> availableBranches,
    required Map<String, List<Map<String, dynamic>>> byBranch,
    required String? activeBranch,
    required List<_TopicGroup> topics,
    required int totalPoolCount,
    required bool isMobile,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: isMobile
            ? Border.all(color: Colors.grey.shade200)
            : Border(right: BorderSide(color: Colors.grey.shade200)),
        borderRadius: isMobile ? BorderRadius.circular(16) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          // 1. SINIF SEVİYESİ SEÇİMİ
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.school_rounded, size: 17, color: Colors.indigo),
                    const SizedBox(width: 6),
                    Text(
                      '1. Sınıf Seviyesi Seçin',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Toplam $totalPoolCount Soru',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: availableClasses.contains(activeClass) ? activeClass : null,
                  isDense: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.indigo.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.indigo.shade200),
                    ),
                  ),
                  items: availableClasses.map((cls) {
                    final cnt = byClass[cls]?.length ?? 0;
                    return DropdownMenuItem<String>(
                      value: cls,
                      child: Text(
                        '$cls ($cnt Soru)',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: cnt > 0 ? const Color(0xFF1E293B) : Colors.grey,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _selectedClassLevel = val;
                      _selectedBranch = null;
                      _selectedTopicKey = null;
                      _selectedSubOutcomeDesc = null;
                      _currentPoolPage = 1;
                    });
                  },
                ),
              ],
            ),
          ),

          // 2. BRANŞ & KONU / ALT KAZANIM AĞACI
          if (isMobile)
            _buildBranchAndTopicTree(
              availableBranches: availableBranches,
              byBranch: byBranch,
              activeBranch: activeBranch,
              topics: topics,
              shrinkWrap: true,
            )
          else
            Expanded(
              child: _buildBranchAndTopicTree(
                availableBranches: availableBranches,
                byBranch: byBranch,
                activeBranch: activeBranch,
                topics: topics,
                shrinkWrap: false,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBranchAndTopicTree({
    required List<String> availableBranches,
    required Map<String, List<Map<String, dynamic>>> byBranch,
    required String? activeBranch,
    required List<_TopicGroup> topics,
    required bool shrinkWrap,
  }) {
    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '2. Branş, Konu ve Alt Konu Seçin',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey.shade700,
            ),
          ),
        ),
        for (final branch in availableBranches) ...[
          Builder(
            builder: (context) {
              final int branchCount = byBranch[branch]?.length ?? 0;
              final bool isBranchSelected = branch == activeBranch;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isBranchSelected ? Colors.indigo.shade50.withValues(alpha: 0.45) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isBranchSelected ? Colors.indigo.shade300 : Colors.grey.shade200,
                    width: isBranchSelected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Branş Başlığı: örn. Fen Bilimleri (280)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          if (_selectedBranch == branch || isBranchSelected) {
                            // Seçili branşa tekrar tıklandı → konu listesini aç / kapat
                            _selectedBranch = branch;
                            _branchTreeCollapsed = !_branchTreeCollapsed;
                          } else {
                            _selectedBranch = branch;
                            _branchTreeCollapsed = false;
                            _selectedTopicKey = null;
                            _selectedSubOutcomeDesc = null;
                            _currentPoolPage = 1;
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        child: Row(
                          children: [
                            Icon(
                              isBranchSelected ? Icons.menu_book_rounded : Icons.book_outlined,
                              size: 18,
                              color: isBranchSelected ? Colors.indigo : Colors.blueGrey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$branch ($branchCount)',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: isBranchSelected ? FontWeight.bold : FontWeight.w600,
                                  color: isBranchSelected
                                      ? Colors.indigo.shade900
                                      : const Color(0xFF334155),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: isBranchSelected ? Colors.indigo : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$branchCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isBranchSelected ? Colors.white : Colors.blueGrey.shade700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              isBranchSelected && !_branchTreeCollapsed
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: isBranchSelected ? Colors.indigo : Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Seçili Branşın Konuları ve Alt Kazanımları
                    if (isBranchSelected && !_branchTreeCollapsed && topics.isNotEmpty) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // "Tüm Branş Soruları (N)" seçeneği
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                setState(() {
                                  _selectedTopicKey = null;
                                  _selectedSubOutcomeDesc = null;
                                  _currentPoolPage = 1;
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: _selectedTopicKey == null
                                      ? Colors.indigo.withValues(alpha: 0.12)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '• Tüm $branch Soruları ($branchCount)',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: _selectedTopicKey == null
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: _selectedTopicKey == null
                                        ? Colors.indigo.shade900
                                        : Colors.blueGrey.shade700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Konular (depth=1) ve içindeki Alt Kazanımlar (depth=2)
                            for (final topic in topics)
                              _buildTopicNode(topic),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildTopicNode(_TopicGroup topic) {
    final bool isTopicSelected = _selectedTopicKey == topic.key;
    final bool isExpanded = _expandedTopicKeys.contains(topic.key);
    final int topicCount = topic.allQuestions.length;
    final String topicTitleDisplay = topic.code.isNotEmpty
        ? '${topic.code} ${topic.title} ($topicCount)'
        : '${topic.title} ($topicCount)';

    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: isTopicSelected ? Colors.white : Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isTopicSelected ? Colors.indigo.shade200 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Konu Satırı
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                // Başlığa her tıklamada aç / kapat (seçili olsa bile kapanabilir)
                if (_expandedTopicKeys.contains(topic.key)) {
                  _expandedTopicKeys.remove(topic.key);
                } else {
                  _expandedTopicKeys.add(topic.key);
                }
                _selectedTopicKey = topic.key;
                _selectedSubOutcomeDesc = null;
                _currentPoolPage = 1;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded,
                    size: 15,
                    color: isTopicSelected ? Colors.indigo : Colors.amber.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      topicTitleDisplay,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: isTopicSelected ? FontWeight.bold : FontWeight.w600,
                        color: isTopicSelected
                            ? Colors.indigo.shade900
                            : const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),

          // Alt Kazanımlar Listesi
          if (isExpanded && topic.subOutcomes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final sub in topic.subOutcomes)
                    Builder(
                      builder: (context) {
                        final desc = sub.description.trim();
                        final int subCount =
                            topic.questionsBySubOutcome[desc]?.length ?? 0;
                        final bool isSubSelected =
                            isTopicSelected && _selectedSubOutcomeDesc == desc;
                        final String subLabel = sub.code.isNotEmpty
                            ? '${sub.code} - $desc ($subCount)'
                            : '$desc ($subCount)';

                        return InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            setState(() {
                              _selectedTopicKey = topic.key;
                              _selectedSubOutcomeDesc = desc;
                              _currentPoolPage = 1;
                            });
                          },
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSubSelected
                                  ? Colors.indigo.shade600
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSubSelected
                                    ? Colors.indigo.shade600
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.subdirectory_arrow_right_rounded,
                                    size: 13,
                                    color: isSubSelected
                                        ? Colors.white
                                        : Colors.indigo.shade400,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    subLabel,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      height: 1.3,
                                      fontWeight: isSubSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isSubSelected
                                          ? Colors.white
                                          : const Color(0xFF334155),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPoolRightHeader({
    required String activeClass,
    required String? activeBranch,
    required _TopicGroup? selectedTopicObj,
    required List<Map<String, dynamic>> allBranchQuestions,
    required int totalFiltered,
    required int safePage,
    required int totalPages,
  }) {
    final int cntCoktan = allBranchQuestions
        .where((q) => questionKindCategory(q) == 'coktan_secmeli')
        .length;
    final int cntEgzersiz = allBranchQuestions
        .where((q) => questionKindCategory(q) == 'egzersiz')
        .length;
    final int cntDeneme = allBranchQuestions
        .where((q) => questionKindCategory(q) == 'deneme')
        .length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Seçili filtre yolu (Breadcrumb)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  activeClass,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                  ),
                ),
              ),
              if (activeBranch != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey),
                ),
                Text(
                  activeBranch,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ],
              if (selectedTopicObj != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Text(
                    _selectedSubOutcomeDesc ?? selectedTopicObj.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.indigo.shade700,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  '$totalFiltered Soru',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              for (final kind in [
                ('coktan_secmeli', 'Çoktan Seçmeli ($cntCoktan)', Colors.indigo),
                ('egzersiz', 'Egzersiz ($cntEgzersiz)', Colors.purple),
                ('deneme', 'Deneme Sınavı ($cntDeneme)', Colors.teal.shade700),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: FilterChip(
                    label: Text(kind.$2, style: const TextStyle(fontSize: 11)),
                    selected: _enabledPoolKinds.contains(kind.$1),
                    visualDensity: VisualDensity.compact,
                    selectedColor: kind.$3,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: _enabledPoolKinds.contains(kind.$1)
                          ? Colors.white
                          : Colors.blueGrey.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _enabledPoolKinds.add(kind.$1);
                        } else if (_enabledPoolKinds.length > 1) {
                          _enabledPoolKinds.remove(kind.$1);
                        }
                        _currentPoolPage = 1;
                      });
                    },
                  ),
                ),
            ],
          ),

          // Zorluk filtresi + Yeni Soru Ekle butonu
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final diff in ['Tümü', ...DifficultyScale.labels])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                    label: Text(diff, style: const TextStyle(fontSize: 11)),
                    selected: _selectedDifficultyFilter == diff,
                    visualDensity: VisualDensity.compact,
                    selectedColor: Colors.indigo,
                    labelStyle: TextStyle(
                      color: _selectedDifficultyFilter == diff
                          ? Colors.white
                          : Colors.blueGrey.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _selectedDifficultyFilter = diff;
                        _currentPoolPage = 1;
                      });
                    },
                  ),
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _openGoogleSheetsImportDialog,
                icon: const Icon(Icons.table_chart_outlined, size: 15),
                label: const Text('Tablodan Aktar', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0F766E),
                  side: const BorderSide(color: Color(0xFF0F766E)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: _openPoolCropStudio,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                label: const Text('Soru Kırp & Ekle', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoQuestionsForFilterState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_alt_off_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Seçilen Konu / Kazanım İçin Henüz Soru Yok',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sol listeden farklı bir branş/kazanım seçebilir veya "Soru Kırp & Ekle" ile yeni soru ekleyebilirsiniz.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationBar({
    required int safePage,
    required int totalPages,
    required int totalFiltered,
    required int startIndex,
    required int shownCount,
  }) {
    final int endNum = startIndex + shownCount;
    // Gösterilecek sayfa numaraları (en fazla 7 buton)
    int startPage = (safePage - 3).clamp(1, totalPages);
    int endPage = (startPage + 6).clamp(1, totalPages);
    if (endPage - startPage < 6) {
      startPage = (endPage - 6).clamp(1, totalPages);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Toplam $totalFiltered sorudan ${startIndex + 1} – $endNum arası gösteriliyor (Sayfa $safePage / $totalPages)',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.blueGrey.shade700,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'İlk Sayfa',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.first_page_rounded, size: 20),
                onPressed: safePage > 1
                    ? () => setState(() => _currentPoolPage = 1)
                    : null,
              ),
              IconButton(
                tooltip: 'Önceki 8 Soru',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left_rounded, size: 22),
                onPressed: safePage > 1
                    ? () => setState(() => _currentPoolPage = safePage - 1)
                    : null,
              ),
              for (int p = startPage; p <= endPage; p++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _currentPoolPage = p),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p == safePage ? Colors.indigo : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$p',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: p == safePage ? Colors.white : Colors.blueGrey.shade800,
                        ),
                      ),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Sonraki 8 Soru',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
                onPressed: safePage < totalPages
                    ? () => setState(() => _currentPoolPage = safePage + 1)
                    : null,
              ),
              IconButton(
                tooltip: 'Son Sayfa',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.last_page_rounded, size: 20),
                onPressed: safePage < totalPages
                    ? () => setState(() => _currentPoolPage = totalPages)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPoolState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.layers_clear_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Soru Havuzu Boş',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'PDF yükleyip soruları kırparak cevabı, zorluğu ve kazanımıyla\nbirlikte doğrudan soru havuzuna ekleyebilirsiniz.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _openGoogleSheetsImportDialog,
                icon: const Icon(Icons.table_chart_rounded),
                label: const Text('Google Tablodan (Sheets) Soru Aktar'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              FilledButton.icon(
                onPressed: _openPoolCropStudio,
                icon: const Icon(Icons.crop_rounded),
                label: const Text('PDF\'den Soru Kırp & Havuza Ekle'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _poolDiffLabel(double val) => DifficultyScale.labelOf(val);

  Color _poolDiffColor(double val) => DifficultyScale.colorOf(val);

  Widget _buildPoolQuestionCard(Map<String, dynamic> data) {
    final base64Image = data['base64Image'] as String?;
    final imageUrl = data['imageUrl'] as String?;
    final driveFileId = data['driveFileId']?.toString();
    final answer = (data['correctAnswer'] as String?) ?? '?';
    final diffNum = (data['difficulty'] as num?)?.toDouble();
    final isWide = data['isWide'] == true;
    final outcome = (data['outcome'] as String?)?.trim() ?? '';
    final kazanimCode = (data['kazanimCode'] as String?)?.trim() ?? '';

    return InkWell(
      onTap: () => _showPoolQuestionPreview(data),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: Colors.white,
                    child: DriveImageHelper.buildPoolQuestionImage(
                      base64Image: base64Image,
                      imageUrl: (imageUrl != null && imageUrl.trim().isNotEmpty)
                          ? imageUrl
                          : (data['rawDriveUrl'] ?? data['fileName'])?.toString(),
                      driveFileId: driveFileId,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (kazanimCode.isNotEmpty)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          kazanimCode,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          color: isWide
                              ? Colors.deepPurple.withValues(alpha: 0.92)
                              : Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () async {
                              await PoolAutoWideFixer.toggleWideManually(data);
                              if (mounted) setState(() {});
                            },
                            child: Tooltip(
                              message: isWide
                                  ? '2 Sütun (Geniş) – tıkla: 1 Sütun yap'
                                  : '1 Sütun – tıkla: 2 Sütun (Geniş) yap',
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Text(
                                  isWide ? '2 Sütun' : '1 Sütun',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isWide ? Colors.white : Colors.deepPurple,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Material(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _showEditPoolQuestionDialog(data),
                            child: const Padding(
                              padding: EdgeInsets.all(5),
                              child: Icon(Icons.edit_outlined, size: 16, color: Colors.indigo),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Material(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _deletePoolQuestion(data),
                            child: const Padding(
                              padding: EdgeInsets.all(5),
                              child: Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data['subject'] ?? 'Ders Belirtilmemiş',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.indigo,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Cevap: $answer',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (diffNum != null ? _poolDiffColor(diffNum) : Colors.grey)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (diffNum != null ? _poolDiffColor(diffNum) : Colors.grey)
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          diffNum != null ? _poolDiffLabel(diffNum) : 'Belirtilmemiş',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: diffNum != null ? _poolDiffColor(diffNum) : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${data['examName'] ?? 'Soru Havuzu'} • Soru ${data['questionNo'] ?? '-'} (${isWide ? '2 Sütun' : '1 Sütun'})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    outcome.isNotEmpty
                        ? (kazanimCode.isNotEmpty && !outcome.startsWith(kazanimCode)
                            ? '$kazanimCode — $outcome'
                            : outcome)
                        : '+ Soruyu büyük görmek için tıklayın',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: outcome.isNotEmpty ? Colors.indigo.shade700 : Colors.grey.shade500,
                      fontStyle: outcome.isNotEmpty ? FontStyle.normal : FontStyle.italic,
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

  Future<void> _deletePoolQuestion(Map<String, dynamic> data) async {
    final examId = data['examId'] as String?;
    final docId = data['docId'] as String?;
    if (examId == null || docId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Soruyu Havuzdan Sil'),
        content: const Text('Bu soruyu soru havuzundan kalıcı olarak silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('trial_exams')
          .doc(examId)
          .collection('questions_pool')
          .doc(docId)
          .delete();
      if (mounted) setState(() {});
    }
  }

  /// Soruyu büyük (geniş) önizleme penceresinde gösterir. "Düzenle" ile düzenleme ekranına geçilir.
  Future<void> _showPoolQuestionPreview(Map<String, dynamic> data) async {
    final size = MediaQuery.of(context).size;
    final bool narrow = size.width < 700;
    final answer = (data['correctAnswer'] ?? '?').toString();
    final diffNum = (data['difficulty'] as num?)?.toDouble();
    final isWide = data['isWide'] == true;
    final outcome = (data['outcome'] ?? '').toString().trim();
    final kazanimCode = (data['kazanimCode'] ?? '').toString().trim();
    final topic = (data['topic'] ?? '').toString().trim();
    final altKonu = (data['altKonu'] ?? '').toString().trim();

    Widget chip(String text, Color color, {bool filled = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: filled ? Colors.white : color,
            ),
          ),
        );

    final bool? openEdit = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.all(narrow ? 10 : 28),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: SizedBox(
          width: math.min(1000, size.width - (narrow ? 20 : 56)),
          height: math.min(900, size.height - (narrow ? 20 : 56)),
          child: Column(
            children: [
              // Üst bilgi çubuğu
              Container(
                padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.visibility_outlined, color: Colors.indigo),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${data['subject'] ?? 'Soru'} • Soru ${data['questionNo'] ?? '-'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                          if (topic.isNotEmpty)
                            Text(
                              altKonu.isNotEmpty && altKonu != topic ? '$topic › $altKonu' : topic,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      label: const Text('Düzenle'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.pop(ctx, false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              // Büyük soru görseli (yakınlaştırılabilir)
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFFF1F5F9),
                  padding: EdgeInsets.all(narrow ? 8 : 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: SizedBox.expand(
                        child: DriveImageHelper.buildPoolQuestionImage(
                          base64Image: data['base64Image'] as String?,
                          imageUrl: ((data['imageUrl'] as String?)?.trim().isNotEmpty == true)
                              ? data['imageUrl'] as String?
                              : (data['rawDriveUrl'] ?? data['fileName'])?.toString(),
                          driveFileId: data['driveFileId']?.toString(),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Alt bilgi: cevap, zorluk, sütun, kazanım
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        chip('Cevap: $answer', Colors.indigo, filled: true),
                        chip(
                          diffNum != null ? _poolDiffLabel(diffNum) : 'Zorluk Belirtilmemiş',
                          diffNum != null ? _poolDiffColor(diffNum) : Colors.grey,
                        ),
                        chip(isWide ? '2 Sütun' : '1 Sütun', Colors.deepPurple),
                        if (kazanimCode.isNotEmpty) chip(kazanimCode, const Color(0xFF0F766E)),
                      ],
                    ),
                    if (outcome.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        outcome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.indigo.shade700),
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

    if (openEdit == true && mounted) {
      await _showEditPoolQuestionDialog(data);
    }
  }

  Future<void> _showEditPoolQuestionDialog(Map<String, dynamic> data) async {
    final examId = data['examId'] as String?;
    final docId = data['docId'] as String?;
    final base64Image = data['base64Image'] as String?;
    final imageUrl = data['imageUrl'] as String?;

    String selectedSub = (data['subject'] as String?) ?? 'Türkçe';
    final subjects = <String>{
      selectedSub,
      'Türkçe',
      'Matematik',
      'Fen Bilimleri',
      'T.C. İnkılap Tarihi',
      'Sosyal Bilgiler',
      'Din Kültürü',
      'İngilizce',
      'Fizik',
      'Kimya',
      'Biyoloji',
      'Tarih',
      'Coğrafya',
    }.toList();

    String selectedAnswer = (data['correctAnswer'] as String?) ?? 'A';
    if (!['A', 'B', 'C', 'D', 'E'].contains(selectedAnswer)) {
      selectedAnswer = 'A';
    }
    double selectedDiff = (data['difficulty'] as num?)?.toDouble() ?? DifficultyScale.defaultScore;
    final double initialDiff = selectedDiff;
    bool isWide = data['isWide'] == true;
    final outcomeCtrl = TextEditingController(text: (data['outcome'] as String?) ?? '');
    final outcomeFocus = FocusNode();
    final qNoCtrl = TextEditingController(text: '${data['questionNo'] ?? 1}');

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: Colors.indigo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Soru Bilgilerini Düzenle (Cevap / Zorluk / Kazanım)',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (base64Image != null || imageUrl != null || data['driveFileId'] != null)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      height: 200,
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: DriveImageHelper.buildPoolQuestionImage(
                        base64Image: base64Image,
                        imageUrl: imageUrl,
                        driveFileId: data['driveFileId']?.toString(),
                        fit: BoxFit.contain,
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedSub,
                          decoration: InputDecoration(
                            labelText: 'Ders',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: subjects
                              .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13))))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setModal(() => selectedSub = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: qNoCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Soru No',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Doğru Cevap',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final ans in ['A', 'B', 'C', 'D', 'E'])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: InkWell(
                              onTap: () => setModal(() => selectedAnswer = ans),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: selectedAnswer == ans ? Colors.indigo : Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selectedAnswer == ans ? Colors.indigo : Colors.indigo.shade200,
                                  ),
                                ),
                                child: Text(
                                  ans,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: selectedAnswer == ans ? Colors.white : Colors.indigo.shade900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Zorluk Derecesi (5 Aşamalı)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (int lvl = 1; lvl <= 5; lvl++)
                        Expanded(
                          child: Builder(builder: (_) {
                            final String lbl = DifficultyScale.labels[lvl - 1];
                            final Color col = DifficultyScale.colors[lvl - 1];
                            final bool sel = DifficultyScale.levelOf(selectedDiff) == lvl;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: InkWell(
                                onTap: () => setModal(
                                  () => selectedDiff = DifficultyScale.scoreForLevel(lvl),
                                ),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: sel ? col : col.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: sel ? col : col.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Text(
                                    lbl,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: sel ? Colors.white : col,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text('Kazanım / Konu',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      const Spacer(),
                      Builder(
                        builder: (context) {
                          final qCls = AssessmentService.normalizeClassLevel(
                            data['classLevel']?.toString(),
                            examName: data['examName']?.toString(),
                          );
                          final matchingLists = _outcomeLists.where((ol) {
                            return _classLevelsMatch(ol.classLevel, qCls) &&
                                _branchesMatch(ol.branchName, selectedSub);
                          }).toList();
                          final allItems = matchingLists.expand((ol) => ol.outcomes).toList();
                          if (allItems.isEmpty) return const SizedBox.shrink();
                          return PopupMenuButton<String>(
                            tooltip: 'Tanımlı Kazanım Listesinden Seç',
                            onSelected: (val) => setModal(() => outcomeCtrl.text = val),
                            itemBuilder: (ctx) => [
                              for (final item in allItems)
                                if (item.description.trim().isNotEmpty)
                                  PopupMenuItem<String>(
                                    enabled: item.depth != 1 || allItems.every((x) => x.depth == 1),
                                    value: item.description.trim(),
                                    child: Text(
                                      item.depth == 1
                                          ? '📁 ${item.code.isNotEmpty ? '${item.code} ' : ''}${item.description}'
                                          : '   • ${item.code.isNotEmpty ? '${item.code} - ' : ''}${item.description}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: item.depth == 1 ? FontWeight.bold : FontWeight.normal,
                                        color: item.depth == 1 ? Colors.indigo.shade900 : const Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.indigo.shade200),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.list_alt_rounded, size: 14, color: Colors.indigo),
                                  SizedBox(width: 4),
                                  Text(
                                    'Kazanım Listesinden Seç',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final qCls = AssessmentService.normalizeClassLevel(
                        data['classLevel']?.toString(),
                        examName: data['examName']?.toString(),
                      );
                      final matchingLists = _outcomeLists.where((ol) {
                        return _classLevelsMatch(ol.classLevel, qCls) &&
                            _branchesMatch(ol.branchName, selectedSub);
                      }).toList();
                      final allItems = matchingLists
                          .expand((ol) => ol.outcomes)
                          .where((x) => x.description.trim().isNotEmpty)
                          .toList();

                      return RawAutocomplete<OutcomeItem>(
                        textEditingController: outcomeCtrl,
                        focusNode: outcomeFocus,
                        displayStringForOption: (opt) => opt.description.trim(),
                        optionsBuilder: (TextEditingValue tv) {
                          if (allItems.isEmpty) return const Iterable<OutcomeItem>.empty();
                          final q = _normTr(tv.text);
                          if (q.isEmpty) return allItems;
                          return allItems.where((item) =>
                              _normTr(item.description).contains(q) ||
                              _normTr(item.code).contains(q));
                        },
                        onSelected: (OutcomeItem sel) {
                          setModal(() {
                            outcomeCtrl.text = sel.description.trim();
                            outcomeCtrl.selection = TextSelection.fromPosition(
                              TextPosition(offset: outcomeCtrl.text.length),
                            );
                          });
                        },
                        fieldViewBuilder: (ctx, textCtrl, fNode, onSubmitted) {
                          return TextField(
                            controller: textCtrl,
                            focusNode: fNode,
                            maxLines: 2,
                            minLines: 1,
                            onChanged: (_) => setModal(() {}),
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: '$qCls • $selectedSub kazanımı yazın veya seçin...',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        },
                        optionsViewBuilder: (ctx, onSelected, options) {
                          final optList = options.toList();
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 8,
                              borderRadius: BorderRadius.circular(10),
                              color: Colors.white,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 460, maxHeight: 240),
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  shrinkWrap: true,
                                  itemCount: optList.length,
                                  separatorBuilder: (_, __) =>
                                      Divider(height: 1, color: Colors.grey.shade100),
                                  itemBuilder: (ctx, idx) {
                                    final item = optList[idx];
                                    final isTopic = item.depth == 1;
                                    return InkWell(
                                      onTap: () => onSelected(item),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        child: Text(
                                          isTopic
                                              ? '📁 ${item.code.isNotEmpty ? '${item.code} ' : ''}${item.description}'
                                              : '• ${item.code.isNotEmpty ? '${item.code} - ' : ''}${item.description}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isTopic
                                                ? FontWeight.bold
                                                : FontWeight.w500,
                                            color: isTopic
                                                ? Colors.indigo.shade900
                                                : const Color(0xFF1E293B),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: isWide,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Geniş Soru (2 Sütun Kaplar)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    onChanged: (v) => setModal(() => isWide = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
            FilledButton.icon(
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Kaydet'),
              style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
              onPressed: () async {
                Navigator.pop(ctx);
                if (examId == null || docId == null) return;
                final parsedQNo = int.tryParse(qNoCtrl.text.trim()) ?? (data['questionNo'] as int? ?? 1);
                final newOutcome = outcomeCtrl.text.trim();
                final bool wideChangedManually = (data['isWide'] == true) != isWide;

                // Seçilen kazanım K12 listesinde varsa K12 kodunu / kazanım kodunu da işle
                OutcomeItem? pickedItem;
                if (newOutcome.isNotEmpty) {
                  final normNew = _normOutcomeKey(newOutcome);
                  for (final ol in _outcomeLists) {
                    for (final it in ol.outcomes) {
                      if (it.depth != 1 && _normOutcomeKey(it.description) == normNew) {
                        pickedItem = it;
                        break;
                      }
                    }
                    if (pickedItem != null) break;
                  }
                }

                final Map<String, dynamic> updates = {
                  'subject': selectedSub,
                  'questionNo': parsedQNo,
                  'correctAnswer': selectedAnswer,
                  'difficulty': selectedDiff,
                  if (selectedDiff != initialDiff) 'difficultyManual': true,
                  'outcome': newOutcome.isEmpty ? null : newOutcome,
                  'isWide': isWide,
                  if (wideChangedManually) 'isWideManual': true,
                  if (pickedItem != null && pickedItem.k12Code.trim().isNotEmpty)
                    'k12Code': pickedItem.k12Code.trim(),
                  if (pickedItem != null && pickedItem.code.trim().isNotEmpty)
                    'kazanimCode': pickedItem.code.trim(),
                };
                await _assessmentService.updatePoolQuestion(examId, docId, updates);
                // Havuz akışı alt koleksiyon değişikliklerini dinlemediği için ekrandaki kartı anında güncelle
                data.addAll(updates);
                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.green,
                      content: Text('Soru bilgileri güncellendi ✓'),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.35),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '✦  Soru Havuzu Modülü',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Akıllı Test & Ödev Oluşturucu',
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Hata kitapçığından biriken sorularla test, deneme sınavı veya ödev oluşturun. '
                  'Manuel seçim ya da konu bazlı otomatik algoritmayla sorularınızı düzenleyin. '
                  'Fixed ve Smart sıralama algoritmaları ile optimum soru dizgisi elde edin.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _buildFeatureChip(Icons.quiz_outlined, 'Test'),
                    const SizedBox(width: 8),
                    _buildFeatureChip(Icons.assignment_outlined, 'Deneme Sınavı'),
                    const SizedBox(width: 8),
                    _buildFeatureChip(Icons.home_work_outlined, 'Ödev'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.layers_rounded,
              size: 56,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w500)),
        ]),
      );

  Widget _buildEmptyState() => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 32),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.inbox_rounded,
                    size: 48, color: Colors.indigo.shade300),
              ),
              const SizedBox(height: 20),
              Text(
                'Henüz test oluşturulmadı',
                style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              Text(
                'Soru havuzundaki soruları kullanarak test, deneme sınavı veya ödev oluşturun.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 14, color: Colors.grey.shade500, height: 1.5),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _openTestWizard(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('İlk Testini Oluştur'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildTestList(List<QueryDocumentSnapshot> docs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Oluşturulan Testler',
              style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B)),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${docs.length} Test',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...docs.map((doc) => _buildTestCard(doc)).toList(),
      ],
    );
  }

  Future<void> _downloadSavedTestPdf(Map<String, dynamic> data) async {
    final List<String> qIds = data['questionIds'] != null
        ? List<String>.from(data['questionIds'])
        : const [];
    if (qIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu testte henüz seçili soru bulunmuyor. Düzenleyerek soru ekleyebilirsiniz.'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Yaprak Test PDF hazırlanıyor...'),
          ],
        ),
      ),
    );

    try {
      final poolDocs = await _assessmentService
          .getGlobalQuestionsPool(widget.institutionId)
          .first;
      final Map<String, Map<String, dynamic>> byId = {};
      for (int i = 0; i < poolDocs.length; i++) {
        final q = poolDocs[i];
        final pk = (q['poolKey'] ?? q['docId'] ?? '$i').toString();
        byId[pk] = q;
        if (q['docId'] != null) {
          byId[q['docId'].toString()] = q;
        }
      }

      final List<Map<String, dynamic>> selectedQs = [];
      for (final id in qIds) {
        final found = byId[id];
        if (found != null) selectedQs.add(found);
      }

      if (selectedQs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text('Seçili sorular soru havuzunda bulunamadı.'),
            ),
          );
        }
        return;
      }

      final firstQ = selectedQs.first;
      final classLevel = (data['classLevel'] as String?) ??
          AssessmentService.normalizeClassLevel(
            firstQ['classLevel']?.toString(),
            examName: firstQ['examName']?.toString(),
          );
      final branchName = (data['branchName'] as String?) ??
          _canonicalBranchName((firstQ['subject'] ?? 'Karma').toString());

      await ErrorBookletGeneratorService().generateAndDownloadTestPdf(
        title: (data['title'] ?? 'Yaprak Test').toString(),
        subtitle: (data['description'] ?? '').toString(),
        examLabel: (data['examLabel'] ?? '').toString(),
        testType: (data['testType'] ?? 'test').toString(),
        classLevel: classLevel,
        branchName: branchName,
        schoolName: widget.schoolTypeName ?? 'eduKN Kurumsal',
        sortingAlgorithm: (data['sortingAlgorithm'] ?? 'smart').toString(),
        questions: selectedQs,
        headerLeftText: (data['headerLeftText'] ?? '').toString(),
        headerRightText: (data['headerRightText'] ?? '').toString(),
        footerLeftText: (data['footerLeftText'] ?? '').toString(),
        footerRightText: (data['footerRightText'] ?? 'Başarılar Dileriz').toString(),
        showOutcomeOnQuestions: data['showOutcomeOnQuestions'] != false,
        showStudentBox: data['showStudentBox'] != false,
        showAnswerKey: data['showAnswerKey'] != false,
        questionRightLabel: (data['questionRightLabel'] ?? 'eduKN').toString(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('PDF oluşturulurken hata oluştu: $e'),
          ),
        );
      }
    }
  }

  Widget _buildTestCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final testTypeStr = data['testType'] ?? 'test';
    TestType type;
    switch (testTypeStr) {
      case 'deneme': type = TestType.deneme; break;
      case 'odev': type = TestType.odev; break;
      default: type = TestType.test;
    }
    final selStr = data['selectionMethod'] ?? 'manuel';
    final sortStr = data['sortingAlgorithm'] ?? 'fixed';
    final qCount = data['questionCount'] ?? 0;
    final classLevel = (data['classLevel'] ?? '').toString();
    final branchName = (data['branchName'] ?? '').toString();
    final targetSummary = (data['targetSummary'] ?? '').toString().trim();
    final Timestamp? ts = data['createdAt'];
    final dateStr = ts != null
        ? '${ts.toDate().day.toString().padLeft(2, '0')}.${ts.toDate().month.toString().padLeft(2, '0')}.${ts.toDate().year}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 4))
        ],
      ),
      child: InkWell(
        onTap: () => _openTestWizard(editingData: {...data, 'docId': doc.id}),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: type.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(type.icon, color: type.color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            data['title'] ?? 'İsimsiz Test',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: const Color(0xFF1E293B)),
                          ),
                        ),
                        _buildTypeBadge(type),
                      ],
                    ),
                    if ((data['description'] ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        data['description'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (targetSummary.isNotEmpty)
                          _buildInfoChip(
                              Icons.groups_rounded, targetSummary, Colors.amber.shade900),
                        if (classLevel.isNotEmpty)
                          _buildInfoChip(Icons.school_outlined, classLevel, Colors.indigo),
                        if (branchName.isNotEmpty)
                          _buildInfoChip(Icons.menu_book_rounded, branchName, Colors.deepPurple),
                        _buildInfoChip(Icons.help_outline_rounded,
                            '$qCount Soru', Colors.blue),
                        _buildInfoChip(Icons.touch_app_outlined,
                            _selLabel(selStr), Colors.purple),
                        _buildInfoChip(Icons.sort_rounded,
                            _sortLabel(sortStr), Colors.teal),
                        if (dateStr.isNotEmpty)
                          _buildInfoChip(
                              Icons.calendar_today_outlined, dateStr, Colors.grey),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _downloadSavedTestPdf(data),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: const Text('PDF İndir',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.indigo,
                  side: BorderSide(color: Colors.indigo.shade200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                onSelected: (val) async {
                  if (val == 'edit') {
                    _openTestWizard(editingData: {...data, 'docId': doc.id});
                  } else if (val == 'pdf') {
                    await _downloadSavedTestPdf(data);
                  } else if (val == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Testi Sil'),
                        content: const Text(
                            'Bu testi silmek istediğinize emin misiniz?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('İptal')),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Sil')),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await FirebaseFirestore.instance
                          .collection('institutions')
                          .doc(widget.institutionId)
                          .collection('question_pool_tests')
                          .doc(doc.id)
                          .delete();
                    }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                  const PopupMenuItem(value: 'pdf', child: Text('PDF Olarak İndir')),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Text('Sil', style: TextStyle(color: Colors.red))),
                ],
                icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(TestType type) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: type.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          type.label,
          style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: type.color),
        ),
      );

  Widget _buildInfoChip(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color.withValues(alpha: 0.8)),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w500)),
        ]),
      );

  String _selLabel(String s) {
    if (s == 'otomatik') return 'Otomatik';
    return 'Manuel';
  }

  String _sortLabel(String s) {
    if (s == 'smart') return 'Smart';
    if (s == 'none') return 'Yerleştirme Yok';
    return 'Fixed';
  }
}

// ─── Full-Screen Multi-Step Test Creation Wizard Page ─────────────────────────

class _TestCreationWizard extends StatefulWidget {
  final String institutionId;
  final String? schoolTypeId;
  final String? schoolTypeName;
  final Map<String, dynamic>? editingData;
  final List<OutcomeList> outcomeLists;

  const _TestCreationWizard({
    required this.institutionId,
    this.schoolTypeId,
    this.schoolTypeName,
    this.editingData,
    required this.outcomeLists,
  });

  @override
  State<_TestCreationWizard> createState() => _TestCreationWizardState();
}

class _TestCreationWizardState extends State<_TestCreationWizard> {
  static const int _questionsPerPage = 8;

  int _step = 0;
  bool _isSaving = false;
  bool _isGeneratingPdf = false;
  bool _didAutoSelectOnStep2 = false;

  // Adım 1: Temel Bilgiler & Hedef Sınıf/Branş & PDF Üst/Alt/Kazanım Ayarları
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _examLabelCtrl = TextEditingController();
  late final TextEditingController _headerLeftCtrl;
  final _headerRightCtrl = TextEditingController();
  late final TextEditingController _footerLeftCtrl;
  final _footerRightCtrl = TextEditingController(text: 'Başarılar Dileriz');
  final _questionRightLabelCtrl = TextEditingController(text: 'eduKN');
  bool _showOutcomeOnQuestions = true;
  bool _showStudentBox = true;
  bool _showAnswerKey = true;
  TestType _testType = TestType.test;

  // Adım 2: Soru Sayısı & Zorluk Derecesi Slider'ları & Seçim Yöntemi
  double _targetQuestionCount = 16;
  /// 5 aşamalı zorluk oranları (%): [Çok Kolay, Kolay, Orta, Zor, Çok Zor]
  List<double> _levelRatios = [10, 20, 40, 20, 10];
  String _difficultyPreset = 'Dengeli'; // 'Kolay Ağırlıklı', 'Dengeli', 'Zor Ağırlıklı', 'Özel'
  QuestionSelectionMethod _selectionMethod = QuestionSelectionMethod.otomatik;
  SortingAlgorithm _sortingAlgorithm = SortingAlgorithm.smart;

  // Adım 3: Hiyerarşik Sınıf -> Branş -> Konu -> Alt Kazanım & 8'li Sayfalama State
  String? _selectedClassLevel;
  String? _selectedBranch;
  String? _selectedTopicKey;
  String? _selectedSubOutcomeDesc;
  String _selectedDifficultyFilter = 'Tümü';
  bool _showOnlySelected = false;

  /// Adım 2 & 3 soru türü ve kaynağı filtreleri (açılıp kapatılabilir):
  /// - `'coktan_secmeli'`: Çoktan Seçmeli Sorular (Havuz / Tablo) — Varsayılan açık
  /// - `'egzersiz'`: Egzersiz Soruları — Varsayılan kapalı
  /// - `'deneme'`: Deneme Sınavı Soruları (Hata Kitapçığı) — Varsayılan kapalı
  Set<String> _enabledQuestionKinds = {'coktan_secmeli'};

  static String _questionKindCategory(Map<String, dynamic> q) =>
      _QuestionPoolScreenState.questionKindCategory(q);

  String get _enabledKindsLabel {
    final labels = <String>[
      if (_enabledQuestionKinds.contains('coktan_secmeli')) 'Çoktan Seçmeli',
      if (_enabledQuestionKinds.contains('egzersiz')) 'Egzersiz',
      if (_enabledQuestionKinds.contains('deneme')) 'Deneme Sınavı',
    ];
    return labels.isEmpty ? 'Tümü' : labels.join(' + ');
  }

  void _toggleQuestionKind(String kind) {
    if (_enabledQuestionKinds.contains(kind)) {
      if (_enabledQuestionKinds.length > 1) {
        _enabledQuestionKinds.remove(kind);
      }
    } else {
      _enabledQuestionKinds.add(kind);
    }
  }

  // ── Konu & Kazanım Kapsamı (2. Adım) ─────────────────────────────────────
  /// Seçilen alt kazanımlar (`"Konu Başlığı::Alt Kazanım"`). Boş = tüm konular.
  final Set<String> _scopeSubOutcomeKeys = {};
  /// Konu Kapsamı listesinde açık (genişletilmiş) konu başlıkları. Varsayılan: hepsi kapalı.
  final Set<String> _scopeExpandedTopicTitles = {};
  /// Kapsamın ait olduğu "sınıf|branş|türler" — sınıf/branş/tür değişirse kapsam devre dışı kalır.
  String _scopeContext = '';

  String _currentScopeContext() {
    final sortedKinds = _enabledQuestionKinds.toList()..sort();
    return '${_selectedClassLevel ?? '7. Sınıf'}|${_selectedBranch ?? ''}|${sortedKinds.join(',')}';
  }

  bool get _hasActiveScope =>
      _scopeSubOutcomeKeys.isNotEmpty && _scopeContext == _currentScopeContext();

  static String _scopeKey(_TopicGroup t, OutcomeItem s) =>
      '${t.title}::${s.description.trim()}';

  /// Kapsamda seçili alt kazanımların sorularını (tekrarsız) döndürür; kapsam yoksa `fallback`.
  List<Map<String, dynamic>> _scopedFromTopics(
    List<_TopicGroup> topics,
    List<Map<String, dynamic>> fallback,
  ) {
    if (!_hasActiveScope) return fallback;
    final List<Map<String, dynamic>> out = [];
    final Set<String> seen = {};
    for (final t in topics) {
      for (final s in t.subOutcomes) {
        if (!_scopeSubOutcomeKeys.contains(_scopeKey(t, s))) continue;
        for (final q in t.questionsBySubOutcome[s.description.trim()] ?? const []) {
          final id = (q['poolKey'] ?? q['docId'] ?? identityHashCode(q)).toString();
          if (seen.add(id)) out.add(q);
        }
      }
    }
    return out;
  }

  /// Seçili sınıf + branş + soru türü için soru listesi ve konu ağacı.
  ({
    List<Map<String, dynamic>> allBranchQuestions,
    List<Map<String, dynamic>> kindQuestions,
    List<_TopicGroup> topics,
  }) _computeScopeTree(
    List<Map<String, dynamic>> allPoolDocs,
  ) {
    final cls = _selectedClassLevel ?? '7. Sınıf';
    final br = _selectedBranch ?? 'Matematik';
    final allBranchQs = allPoolDocs.where((q) {
      final qCls = AssessmentService.normalizeClassLevel(
        q['classLevel']?.toString(),
        examName: q['examName']?.toString(),
      );
      final qBr = _QuestionPoolScreenState._canonicalBranchName((q['subject'] ?? '').toString());
      return _QuestionPoolScreenState._classLevelsMatch(qCls, cls) &&
          _QuestionPoolScreenState._branchesMatch(qBr, br);
    }).toList();
    final kindQs = allBranchQs
        .where((q) => _enabledQuestionKinds.contains(_questionKindCategory(q)))
        .toList();
    final topics = _QuestionPoolScreenState.buildTopicsForBranch(_outcomeLists, cls, br, kindQs);
    return (allBranchQuestions: allBranchQs, kindQuestions: kindQs, topics: topics);
  }

  void _onScopeChanged() {
    _scopeContext = _currentScopeContext();
    _selectedTopicKey = null;
    _selectedSubOutcomeDesc = null;
    _currentPoolPage = 1;
    if (_selectionMethod == QuestionSelectionMethod.otomatik) {
      // Kapsam değişti: 3. adımda yeni kapsama göre yeniden otomatik seçilsin
      _selectedQuestionIds.clear();
      _didAutoSelectOnStep2 = false;
    }
  }
  final Set<String> _expandedTopicKeys = {};
  int _currentPoolPage = 1;

  // ── Hedef Kitle (Kim İçin Oluşturuluyor?) & Daha Önce Kullanılan Soru Hafızası ──
  /// `'class'` (Tüm Sınıf Seviyesi), `'branch'` (Şube / Şubeler), `'student'` (Öğrenci / Öğrenciler)
  String _targetAudienceType = 'class';
  final Set<String> _selectedTargetBranches = {};
  final Set<String> _selectedTargetStudentIds = {};
  final Map<String, String> _selectedTargetStudentNames = {};
  final TextEditingController _customBranchCtrl = TextEditingController();
  final TextEditingController _studentSearchCtrl = TextEditingController();
  String? _studentBranchFilterInPicker;

  /// Bir sonraki test hazırlamada aynı sorular kullanılmasın — varsayılan olarak AÇIK (`true`).
  bool _excludePreviouslyUsedQuestions = true;
  /// 3. Adımda (Manuel Soru Seç) daha önce kullanılanları listede tamamen gizleme filtresi (varsayılan `false`, yani kart üzerinde "Daha Önce Kullanıldı" işaretiyle görünür).
  bool _hidePreviouslyUsedInGrid = false;

  /// Kurumdaki geçmiş testler (`question_pool_tests`)
  List<Map<String, dynamic>> _pastTests = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pastTestsSub;

  /// Kurumdaki şubeler (`classes`) ve öğrenciler (`students`)
  List<Map<String, dynamic>> _institutionClasses = [];
  List<Map<String, dynamic>> _institutionStudents = [];
  bool _isLoadingAudienceData = false;

  // Seçilen Soru ID'leri ve Önbelleği
  final List<String> _selectedQuestionIds = [];
  List<OutcomeList> _outcomeLists = [];
  StreamSubscription<List<OutcomeList>>? _wizardOutcomeSub;
  late Stream<List<Map<String, dynamic>>> _wizardPoolStream;

  @override
  void initState() {
    super.initState();
    _outcomeLists = List<OutcomeList>.from(widget.outcomeLists);
    PoolAutoWideFixer.scheduleOutcomeListsMigration(_outcomeLists);
    _wizardPoolStream = AssessmentService().getGlobalQuestionsPool(
      widget.institutionId,
    );
    _wizardOutcomeSub = AssessmentService()
        .getOutcomeLists(widget.institutionId)
        .listen((lists) {
          PoolAutoWideFixer.scheduleOutcomeListsMigration(lists);
          if (mounted && lists.isNotEmpty) {
            setState(() => _outcomeLists = lists);
          }
        });
    _subscribePastTests();
    _loadInstitutionClassesAndStudents();

    final defaultSchool = (widget.schoolTypeName ?? 'ABC ORTAOKULU').trim();
    _headerLeftCtrl = TextEditingController(text: defaultSchool);
    _footerLeftCtrl = TextEditingController(
      text: '$defaultSchool • eduKN Akıllı Soru Havuzu',
    );

    final d = widget.editingData;
    if (d != null) {
      _titleCtrl.text = d['title'] ?? '';
      _descCtrl.text = d['description'] ?? '';
      _examLabelCtrl.text = d['examLabel'] ?? '';
      if ((d['headerLeftText'] ?? '').toString().trim().isNotEmpty) {
        _headerLeftCtrl.text = d['headerLeftText'].toString();
      }
      _headerRightCtrl.text = (d['headerRightText'] ?? '').toString();
      if ((d['footerLeftText'] ?? '').toString().trim().isNotEmpty) {
        _footerLeftCtrl.text = d['footerLeftText'].toString();
      }
      if ((d['footerRightText'] ?? '').toString().trim().isNotEmpty) {
        _footerRightCtrl.text = d['footerRightText'].toString();
      }
      if ((d['questionRightLabel'] ?? '').toString().trim().isNotEmpty) {
        _questionRightLabelCtrl.text = d['questionRightLabel'].toString();
      }
      _showOutcomeOnQuestions = d['showOutcomeOnQuestions'] != false;
      _showStudentBox = d['showStudentBox'] != false;
      _showAnswerKey = d['showAnswerKey'] != false;
      _selectedClassLevel = d['classLevel'] as String?;
      _selectedBranch = d['branchName'] as String?;
      final audType = (d['targetAudienceType'] ?? '').toString().trim();
      if (audType == 'class' || audType == 'branch' || audType == 'student') {
        _targetAudienceType = audType;
      }
      if (d['targetBranches'] is List) {
        _selectedTargetBranches.addAll(
          (d['targetBranches'] as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty),
        );
      }
      if (d['targetStudentIds'] is List) {
        final ids = (d['targetStudentIds'] as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        final names = d['targetStudentNames'] is List
            ? (d['targetStudentNames'] as List).map((e) => e.toString().trim()).toList()
            : const <String>[];
        for (int i = 0; i < ids.length; i++) {
          _selectedTargetStudentIds.add(ids[i]);
          if (i < names.length && names[i].isNotEmpty) {
            _selectedTargetStudentNames[ids[i]] = names[i];
          }
        }
      }
      if (d['excludePreviouslyUsedQuestions'] is bool) {
        _excludePreviouslyUsedQuestions = d['excludePreviouslyUsedQuestions'] as bool;
      }
      final ts = d['testType'] ?? 'test';
      _testType = ts == 'deneme'
          ? TestType.deneme
          : ts == 'odev'
              ? TestType.odev
              : TestType.test;
      final sel = d['selectionMethod'] ?? 'manuel';
      _selectionMethod = sel == 'otomatik'
          ? QuestionSelectionMethod.otomatik
          : QuestionSelectionMethod.manuel;
      final sort = d['sortingAlgorithm'] ?? 'smart';
      _sortingAlgorithm = sort == 'smart'
          ? SortingAlgorithm.smart
          : sort == 'none'
              ? SortingAlgorithm.none
              : SortingAlgorithm.fixed;

      if (d['targetQuestionCount'] is num) {
        _targetQuestionCount =
            (d['targetQuestionCount'] as num).toDouble().clamp(4.0, 60.0);
      }
      if (d['levelRatios'] is List && (d['levelRatios'] as List).length == 5) {
        _levelRatios = (d['levelRatios'] as List).map((e) => (e as num).toDouble()).toList();
      } else if (d['easyRatio'] is num || d['mediumRatio'] is num || d['hardRatio'] is num) {
        // Eski 3 aşamalı kayıtları 5 aşamaya dönüştür
        final e = (d['easyRatio'] as num?)?.toDouble() ?? 0;
        final m = (d['mediumRatio'] as num?)?.toDouble() ?? 0;
        final h = (d['hardRatio'] as num?)?.toDouble() ?? 0;
        _levelRatios = [e / 2, e / 2, m, h / 2, h / 2];
        _difficultyPreset = 'Özel';
      }

      if (d['questionKinds'] is List && (d['questionKinds'] as List).isNotEmpty) {
        _enabledQuestionKinds =
            Set<String>.from((d['questionKinds'] as List).map((e) => e.toString()));
      } else if (d['questionKind'] is String) {
        final legacyKind = d['questionKind'] as String;
        if (legacyKind == 'egzersiz') {
          _enabledQuestionKinds = {'egzersiz'};
        } else {
          _enabledQuestionKinds = {'coktan_secmeli', 'deneme'};
        }
      }
      if (d['scopeOutcomes'] is List) {
        _scopeSubOutcomeKeys.addAll(List<String>.from(d['scopeOutcomes'] as List));
        _scopeContext = (d['scopeContext'] ?? '').toString();
      }
      if (d['questionIds'] != null) {
        _selectedQuestionIds.addAll(List<String>.from(d['questionIds']));
        if (_selectedQuestionIds.isNotEmpty) {
          _didAutoSelectOnStep2 = true;
          if (d['targetQuestionCount'] == null) {
            _targetQuestionCount =
                _selectedQuestionIds.length.toDouble().clamp(4.0, 60.0);
          }
        }
      }
    }
  }

  void _subscribePastTests() {
    _pastTestsSub?.cancel();
    _pastTestsSub = FirebaseFirestore.instance
        .collection('institutions')
        .doc(widget.institutionId)
        .collection('question_pool_tests')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _pastTests = snap.docs
                .map((doc) => <String, dynamic>{...doc.data(), 'docId': doc.id})
                .toList();
          });
        });
  }

  Future<void> _loadInstitutionClassesAndStudents() async {
    if (_isLoadingAudienceData) return;
    setState(() => _isLoadingAudienceData = true);
    try {
      final db = FirebaseFirestore.instance;
      final classesFuture = db
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();
      final studentsFuture = db
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final results = await Future.wait([classesFuture, studentsFuture]);
      final classSnap = results[0];
      final studentSnap = results[1];

      final List<Map<String, dynamic>> loadedClasses = [];
      for (final doc in classSnap.docs) {
        final data = doc.data();
        final name = (data['className'] ?? data['name'] ?? data['branch'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final rawLvl = (data['classLevel'] ?? data['grade'] ?? data['level'] ?? '').toString().trim();
        final normLvl = AssessmentService.normalizeClassLevel(
          rawLvl.isNotEmpty ? rawLvl : name,
          examName: name,
        );
        loadedClasses.add({
          'id': doc.id,
          'name': name,
          'classLevel': normLvl,
        });
      }

      final List<Map<String, dynamic>> loadedStudents = [];
      for (final doc in studentSnap.docs) {
        final data = doc.data();
        final fullName = (data['fullName'] ??
                '${data['name'] ?? ''} ${data['surname'] ?? ''}')
            .toString()
            .trim();
        if (fullName.isEmpty) continue;
        final className =
            (data['className'] ?? data['studentBranch'] ?? data['branch'] ?? '')
                .toString()
                .trim();
        final rawLvl =
            (data['classLevel'] ?? data['grade'] ?? data['level'] ?? '')
                .toString()
                .trim();
        final normLvl = AssessmentService.normalizeClassLevel(
          rawLvl.isNotEmpty ? rawLvl : className,
          examName: className,
        );
        final studentNo = (data['studentNo'] ??
                data['number'] ??
                data['schoolNumber'] ??
                data['studentNumber'] ??
                '')
            .toString()
            .trim();
        loadedStudents.add({
          'id': doc.id,
          'name': fullName,
          'className': className,
          'classLevel': normLvl,
          'studentNo': studentNo,
        });
        if (_selectedTargetStudentIds.contains(doc.id)) {
          _selectedTargetStudentNames[doc.id] = fullName;
        }
      }
      loadedStudents.sort(
        (a, b) => a['name'].toString().compareTo(b['name'].toString()),
      );

      if (mounted) {
        setState(() {
          _institutionClasses = loadedClasses;
          _institutionStudents = loadedStudents;
        });
      }
    } catch (e) {
      debugPrint('Audience load error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingAudienceData = false);
      }
    }
  }

  /// Seçili sınıf seviyesine ait mevcut şube isimlerini döndürür.
  List<String> _availableBranchesForSelectedClass() {
    final activeCls = _selectedClassLevel ?? '7. Sınıf';
    final gradeDigits = RegExp(r'\d+').firstMatch(activeCls)?.group(0) ?? '7';
    final Set<String> branches = {};

    for (final c in _institutionClasses) {
      final clsLvl = (c['classLevel'] ?? '').toString();
      final name = (c['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      if (_QuestionPoolScreenState._classLevelsMatch(clsLvl, activeCls) ||
          name.startsWith('$gradeDigits-') ||
          name.startsWith('$gradeDigits/') ||
          name.startsWith('$gradeDigits ')) {
        branches.add(name);
      }
    }
    for (final s in _institutionStudents) {
      final clsLvl = (s['classLevel'] ?? '').toString();
      final cName = (s['className'] ?? '').toString().trim();
      if (cName.isEmpty || cName == 'Belirtilmedi') continue;
      if (_QuestionPoolScreenState._classLevelsMatch(clsLvl, activeCls) ||
          cName.startsWith('$gradeDigits-') ||
          cName.startsWith('$gradeDigits/') ||
          cName.startsWith('$gradeDigits ')) {
        branches.add(cName);
      }
    }
    for (final t in _pastTests) {
      final tCls = (t['classLevel'] ?? '').toString();
      if (_QuestionPoolScreenState._classLevelsMatch(tCls, activeCls) &&
          t['targetBranches'] is List) {
        for (final b in (t['targetBranches'] as List)) {
          final bs = b.toString().trim();
          if (bs.isNotEmpty) branches.add(bs);
        }
      }
    }
    branches.addAll(_selectedTargetBranches);
    // Kurumda henüz şube tanımlanmamışsa standart şube önerilerini ekle
    if (branches.isEmpty) {
      branches.addAll([
        '$gradeDigits-A',
        '$gradeDigits-B',
        '$gradeDigits-C',
        '$gradeDigits-D',
      ]);
    }
    final list = branches.toList()..sort();
    return list;
  }

  /// Seçili sınıf seviyesine ait öğrenci listesini döndürür.
  List<Map<String, dynamic>> _studentsForSelectedClass() {
    final activeCls = _selectedClassLevel ?? '7. Sınıf';
    final gradeDigits = RegExp(r'\d+').firstMatch(activeCls)?.group(0) ?? '';
    final matching = _institutionStudents.where((s) {
      final clsLvl = (s['classLevel'] ?? '').toString();
      final cName = (s['className'] ?? '').toString().trim();
      if (_QuestionPoolScreenState._classLevelsMatch(clsLvl, activeCls)) {
        return true;
      }
      if (gradeDigits.isNotEmpty &&
          (cName.startsWith('$gradeDigits-') ||
              cName.startsWith('$gradeDigits/') ||
              cName.startsWith('$gradeDigits '))) {
        return true;
      }
      return false;
    }).toList();
    return matching.isNotEmpty ? matching : _institutionStudents;
  }

  String get _targetAudienceSummary {
    final cls = _selectedClassLevel ?? '7. Sınıf';
    if (_targetAudienceType == 'branch') {
      if (_selectedTargetBranches.isEmpty) return '$cls • Şube Seçilmedi';
      final sorted = _selectedTargetBranches.toList()..sort();
      return '$cls • ${sorted.join(', ')}';
    }
    if (_targetAudienceType == 'student') {
      if (_selectedTargetStudentIds.isEmpty) return '$cls • Öğrenci Seçilmedi';
      final names = _selectedTargetStudentIds
          .map((id) => _selectedTargetStudentNames[id] ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      if (names.isEmpty) {
        return '$cls • ${_selectedTargetStudentIds.length} Öğrenci';
      }
      if (names.length <= 2) {
        return '$cls • ${names.join(', ')}';
      }
      return '$cls • ${names.length} Öğrenci (${names.take(2).join(', ')} +${names.length - 2})';
    }
    return '$cls Genel';
  }

  static String _qKeyOfQuestion(Map<String, dynamic> q) =>
      (q['poolKey'] ?? q['docId'] ?? '').toString();

  static String _contentKeyOfQuestion(Map<String, dynamic> q) {
    final drive = (q['driveFileId'] ?? '').toString().trim();
    if (drive.isNotEmpty) return 'd:$drive';
    final img = (q['imageUrl'] ?? '').toString().trim();
    if (img.isNotEmpty && !img.startsWith('data:')) return 'u:$img';
    final b64 = (q['base64Image'] ?? '').toString();
    if (b64.length > 200) {
      return 'b:${b64.length}:${b64.substring(b64.length ~/ 2, b64.length ~/ 2 + 120)}';
    }
    return 'k:${_qKeyOfQuestion(q)}';
  }

  /// Seçili sınıf, branş (ders) ve hedef kitle (Sınıf / Şube / Öğrenci) için
  /// daha önce oluşturulan testlerde kullanılmış soruları ve kullanım geçmişini hesaplar.
  ({
    Set<String> usedQuestionIds,
    Set<String> usedContentKeys,
    Map<String, int> useCounts,
    Map<String, List<String>> testTitlesByKey,
    int matchingPastTestCount,
  }) _computeUsedQuestionsMemory() {
    final activeCls = _selectedClassLevel ?? '7. Sınıf';
    final activeSubj = _selectedBranch ?? 'Matematik';
    final editingDocId = widget.editingData?['docId']?.toString();

    // Seçili öğrencilerin şubelerini de bulalım (şubeye yapılan test o şubedeki öğrenciye de yapılmış sayılır)
    final Set<String> selectedStudentsBranches = {};
    if (_targetAudienceType == 'student' && _selectedTargetStudentIds.isNotEmpty) {
      for (final s in _institutionStudents) {
        if (_selectedTargetStudentIds.contains(s['id'])) {
          final cb = (s['className'] ?? '').toString().trim();
          if (cb.isNotEmpty) selectedStudentsBranches.add(cb);
        }
      }
    }

    final Set<String> usedIds = {};
    final Set<String> usedCKeys = {};
    final Map<String, int> useCounts = {};
    final Map<String, List<String>> testTitlesByKey = {};
    int matchingTests = 0;

    for (final test in _pastTests) {
      final docId = test['docId']?.toString();
      if (editingDocId != null && docId == editingDocId) continue;

      final tCls = AssessmentService.normalizeClassLevel(
        test['classLevel']?.toString(),
      );
      final tSubj = _QuestionPoolScreenState._canonicalBranchName(
        (test['branchName'] ?? '').toString(),
      );
      if (!_QuestionPoolScreenState._classLevelsMatch(tCls, activeCls)) continue;
      if (!_QuestionPoolScreenState._branchesMatch(tSubj, activeSubj)) continue;

      final String tAudType =
          (test['targetAudienceType'] ?? 'class').toString().trim();
      final Set<String> tBranches = test['targetBranches'] is List
          ? (test['targetBranches'] as List)
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toSet()
          : <String>{};
      final Set<String> tStudents = test['targetStudentIds'] is List
          ? (test['targetStudentIds'] as List)
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toSet()
          : <String>{};

      bool overlapsAudience = false;
      if (_targetAudienceType == 'class') {
        // Sınıf geneli için test hazırlarken o sınıfa veya şubelerine yapılmış testler
        overlapsAudience = (tAudType == 'class' || tAudType == 'branch' || tAudType.isEmpty);
      } else if (_targetAudienceType == 'branch') {
        if (tAudType == 'class' || tAudType.isEmpty) {
          overlapsAudience = true;
        } else if (tAudType == 'branch') {
          overlapsAudience = _selectedTargetBranches.isEmpty
              ? true
              : tBranches.any(_selectedTargetBranches.contains);
        }
      } else if (_targetAudienceType == 'student') {
        if (tAudType == 'class' || tAudType.isEmpty) {
          overlapsAudience = true;
        } else if (tAudType == 'branch') {
          overlapsAudience = selectedStudentsBranches.isNotEmpty &&
              tBranches.any(selectedStudentsBranches.contains);
        } else if (tAudType == 'student') {
          overlapsAudience = _selectedTargetStudentIds.isEmpty
              ? true
              : tStudents.any(_selectedTargetStudentIds.contains);
        }
      }

      if (!overlapsAudience) continue;

      final qIds = test['questionIds'] is List
          ? (test['questionIds'] as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
          : const <String>[];
      final cKeys = test['questionContentKeys'] is List
          ? (test['questionContentKeys'] as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
          : const <String>[];
      if (qIds.isEmpty && cKeys.isEmpty) continue;

      matchingTests++;
      final String tTitle = (test['title'] ?? 'İsimsiz Test').toString().trim();

      for (final qid in qIds) {
        usedIds.add(qid);
        useCounts[qid] = (useCounts[qid] ?? 0) + 1;
        final list = testTitlesByKey.putIfAbsent(qid, () => []);
        if (!list.contains(tTitle)) list.add(tTitle);
      }
      for (final ck in cKeys) {
        usedCKeys.add(ck);
        useCounts[ck] = (useCounts[ck] ?? 0) + 1;
        final list = testTitlesByKey.putIfAbsent(ck, () => []);
        if (!list.contains(tTitle)) list.add(tTitle);
      }
    }

    return (
      usedQuestionIds: usedIds,
      usedContentKeys: usedCKeys,
      useCounts: useCounts,
      testTitlesByKey: testTitlesByKey,
      matchingPastTestCount: matchingTests,
    );
  }

  bool _isQuestionPreviouslyUsed(
    Map<String, dynamic> q, [
    ({
      Set<String> usedQuestionIds,
      Set<String> usedContentKeys,
      Map<String, int> useCounts,
      Map<String, List<String>> testTitlesByKey,
      int matchingPastTestCount,
    })? mem,
  ]) {
    final m = mem ?? _computeUsedQuestionsMemory();
    final qKey = _qKeyOfQuestion(q);
    final docId = (q['docId'] ?? '').toString();
    final cKey = _contentKeyOfQuestion(q);
    return (qKey.isNotEmpty && m.usedQuestionIds.contains(qKey)) ||
        (docId.isNotEmpty && m.usedQuestionIds.contains(docId)) ||
        (cKey.isNotEmpty && m.usedContentKeys.contains(cKey));
  }

  int _questionUseCount(
    Map<String, dynamic> q, [
    ({
      Set<String> usedQuestionIds,
      Set<String> usedContentKeys,
      Map<String, int> useCounts,
      Map<String, List<String>> testTitlesByKey,
      int matchingPastTestCount,
    })? mem,
  ]) {
    final m = mem ?? _computeUsedQuestionsMemory();
    final qKey = _qKeyOfQuestion(q);
    final docId = (q['docId'] ?? '').toString();
    final cKey = _contentKeyOfQuestion(q);
    int c = 0;
    if (qKey.isNotEmpty && (m.useCounts[qKey] ?? 0) > c) c = m.useCounts[qKey]!;
    if (docId.isNotEmpty && (m.useCounts[docId] ?? 0) > c) c = m.useCounts[docId]!;
    if (cKey.isNotEmpty && (m.useCounts[cKey] ?? 0) > c) c = m.useCounts[cKey]!;
    return c;
  }

  List<String> _questionUsedTestTitles(
    Map<String, dynamic> q, [
    ({
      Set<String> usedQuestionIds,
      Set<String> usedContentKeys,
      Map<String, int> useCounts,
      Map<String, List<String>> testTitlesByKey,
      int matchingPastTestCount,
    })? mem,
  ]) {
    final m = mem ?? _computeUsedQuestionsMemory();
    final Set<String> titles = {};
    final qKey = _qKeyOfQuestion(q);
    final docId = (q['docId'] ?? '').toString();
    final cKey = _contentKeyOfQuestion(q);
    if (qKey.isNotEmpty && m.testTitlesByKey[qKey] != null) {
      titles.addAll(m.testTitlesByKey[qKey]!);
    }
    if (docId.isNotEmpty && m.testTitlesByKey[docId] != null) {
      titles.addAll(m.testTitlesByKey[docId]!);
    }
    if (cKey.isNotEmpty && m.testTitlesByKey[cKey] != null) {
      titles.addAll(m.testTitlesByKey[cKey]!);
    }
    return titles.toList();
  }

  void _onTargetAudienceChanged() {
    if (_selectionMethod == QuestionSelectionMethod.otomatik) {
      _selectedQuestionIds.clear();
      _didAutoSelectOnStep2 = false;
    }
  }

  @override
  void didUpdateWidget(covariant _TestCreationWizard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId) {
      _wizardPoolStream = AssessmentService().getGlobalQuestionsPool(
        widget.institutionId,
      );
      _wizardOutcomeSub?.cancel();
      _wizardOutcomeSub = AssessmentService()
          .getOutcomeLists(widget.institutionId)
          .listen((lists) {
            if (mounted && lists.isNotEmpty) {
              setState(() => _outcomeLists = lists);
            }
          });
      _subscribePastTests();
      _loadInstitutionClassesAndStudents();
    }
  }

  @override
  void dispose() {
    _wizardOutcomeSub?.cancel();
    _pastTestsSub?.cancel();
    _customBranchCtrl.dispose();
    _studentSearchCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _examLabelCtrl.dispose();
    _headerLeftCtrl.dispose();
    _headerRightCtrl.dispose();
    _footerLeftCtrl.dispose();
    _footerRightCtrl.dispose();
    _questionRightLabelCtrl.dispose();
    super.dispose();
  }

  bool get _step1Valid => _titleCtrl.text.trim().isNotEmpty;

  String _diffLabel(double d) => DifficultyScale.labelOf(d);

  Color _diffColor(double d) => DifficultyScale.colorOf(d);

  /// Hedef soru sayısına ve 5 aşamalı zorluk yüzdelerine göre her seviyedeki tam soru adedini hesaplar.
  /// Dönen liste: [Çok Kolay, Kolay, Orta, Zor, Çok Zor].
  List<int> get _targetLevelCounts {
    final int total = _targetQuestionCount.round();
    final double sum = _levelRatios.fold<double>(0, (a, b) => a + b).clamp(1.0, 10000.0);
    final raw = _levelRatios.map((r) => total * r / sum).toList();
    final counts = raw.map((v) => v.floor()).toList();
    int remaining = total - counts.fold<int>(0, (a, b) => a + b);
    // En büyük küsuratlılara kalan soruları dağıt (toplam her zaman hedefe eşit olsun)
    final order = List<int>.generate(5, (i) => i)
      ..sort((a, b) => (raw[b] - counts[b]).compareTo(raw[a] - counts[a]));
    for (final i in order) {
      if (remaining <= 0) break;
      if (_levelRatios[i] <= 0) continue;
      counts[i]++;
      remaining--;
    }
    return counts;
  }

  static const Map<String, List<double>> _difficultyPresets = {
    'Kolay Ağırlıklı': [25, 35, 25, 10, 5],
    'Dengeli': [10, 20, 40, 20, 10],
    'Zor Ağırlıklı': [5, 10, 25, 35, 25],
    'Tamamı Çok Kolay': [100, 0, 0, 0, 0],
    'Tamamı Kolay': [0, 100, 0, 0, 0],
    'Tamamı Orta': [0, 0, 100, 0, 0],
    'Tamamı Zor': [0, 0, 0, 100, 0],
    'Tamamı Çok Zor': [0, 0, 0, 0, 100],
  };

  void _applyDifficultyPreset(String preset) {
    final values = _difficultyPresets[preset];
    if (values == null) return;
    setState(() {
      _difficultyPreset = preset;
      _levelRatios = List<double>.from(values);
    });
  }

  /// Seçili havuz listesinden hedef soru sayısı ve 5 aşamalı zorluk dağılımına göre otomatik soru seçer.
  void _runAutoSelectFromCandidatePool(List<Map<String, dynamic>> candidates, {bool showFeedback = true}) {
    if (candidates.isEmpty) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Bu sınıf/branş/konu filtresinde seçilebilecek soru bulunamadı.'),
          ),
        );
      }
      return;
    }

    final mem = _computeUsedQuestionsMemory();
    final List<Map<String, dynamic>> effectiveCandidates = _excludePreviouslyUsedQuestions
        ? candidates.where((q) => !_isQuestionPreviouslyUsed(q, mem)).toList()
        : candidates;
    final int skippedUsedCount = candidates.length - effectiveCandidates.length;

    if (effectiveCandidates.isEmpty) {
      setState(() {
        _selectedQuestionIds.clear();
        _didAutoSelectOnStep2 = true;
        _currentPoolPage = 1;
      });
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.deepOrange,
            content: Text(
              'Bu filtredeki tüm sorular ($skippedUsedCount soru) $_targetAudienceSummary için daha önce kullanılmış! '
              'Yeni konu seçebilir veya "Daha Önce Kullanılan Sorular Seçilmesin" anahtarını kapatabilirsiniz.',
            ),
          ),
        );
      }
      return;
    }

    final counts = _targetLevelCounts;
    final int targetTotal = _targetQuestionCount.round();
    final rng = math.Random();

    final List<List<Map<String, dynamic>>> levelPools = List.generate(5, (_) => []);
    for (final q in effectiveCandidates) {
      final d = (q['difficulty'] as num?)?.toDouble() ?? DifficultyScale.defaultScore;
      levelPools[DifficultyScale.levelOf(d) - 1].add(q);
    }
    for (final p in levelPools) {
      p.shuffle(rng);
    }

    final List<Map<String, dynamic>> picked = [];
    final Set<String> pickedIds = {};
    final Set<String> pickedContentKeys = {};

    String qKeyOf(Map<String, dynamic> q) => _qKeyOfQuestion(q);
    String contentKeyOf(Map<String, dynamic> q) => _contentKeyOfQuestion(q);

    void pickUpTo(List<Map<String, dynamic>> src, int count) {
      int added = 0;
      for (final q in src) {
        if (added >= count) break;
        final k = qKeyOf(q);
        if (k.isEmpty || pickedIds.contains(k)) continue;
        final ck = contentKeyOf(q);
        if (pickedContentKeys.contains(ck)) continue;
        pickedIds.add(k);
        pickedContentKeys.add(ck);
        picked.add(q);
        added++;
      }
    }

    for (int i = 0; i < 5; i++) {
      pickUpTo(levelPools[i], counts[i]);
    }

    // Bir seviyede yeterli soru yoksa: önce komşu seviyelerden (en yakın zorluk), sonra kalanlardan tamamla
    if (picked.length < targetTotal) {
      for (int i = 0; i < 5 && picked.length < targetTotal; i++) {
        final short = counts[i] - picked.where((q) {
          final d = (q['difficulty'] as num?)?.toDouble() ?? DifficultyScale.defaultScore;
          return DifficultyScale.levelOf(d) - 1 == i;
        }).length;
        if (short <= 0) continue;
        for (final n in [i - 1, i + 1, i - 2, i + 2]) {
          if (n < 0 || n > 4) continue;
          pickUpTo(levelPools[n], math.min(short, targetTotal - picked.length));
        }
      }
    }
    if (picked.length < targetTotal) {
      final remainingAll = List<Map<String, dynamic>>.from(effectiveCandidates)..shuffle(rng);
      pickUpTo(remainingAll, targetTotal - picked.length);
    }

    setState(() {
      _selectedQuestionIds
        ..clear()
        ..addAll(pickedIds);
      _didAutoSelectOnStep2 = true;
      _currentPoolPage = 1;
    });

    if (showFeedback && mounted) {
      final got = List<int>.filled(5, 0);
      for (final q in picked) {
        final d = (q['difficulty'] as num?)?.toDouble() ?? DifficultyScale.defaultScore;
        got[DifficultyScale.levelOf(d) - 1]++;
      }
      final summary = [
        for (int i = 0; i < 5; i++)
          if (got[i] > 0) '${got[i]} ${DifficultyScale.labels[i]}',
      ].join(' • ');
      final usedNote = (_excludePreviouslyUsedQuestions && skippedUsedCount > 0)
          ? ' • Daha önce kullanılan $skippedUsedCount soru hariç tutuldu'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.indigo,
          content: Text('⚡ Otomatik ${picked.length} yeni soru seçildi ($summary$usedNote)'),
        ),
      );
    }
  }

  void _next() {
    if (_step == 0) {
      if (!_step1Valid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen test başlığını giriniz.')),
        );
        return;
      }
      if (_targetAudienceType == 'branch' && _selectedTargetBranches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Lütfen testi oluşturacağınız en az bir şube seçin (veya Sınıf Seviyesi Genel seçin).'),
          ),
        );
        return;
      }
      if (_targetAudienceType == 'student' && _selectedTargetStudentIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Lütfen testi oluşturacağınız en az bir öğrenci seçin.'),
          ),
        );
        return;
      }
    }
    if (_step < 3) {
      setState(() => _step++);
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _save({required bool downloadPdfAfterSave, required List<Map<String, dynamic>> allPoolDocs}) async {
    if (_selectedQuestionIds.isEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Soru Seçilmedi'),
          content: const Text('Henüz hiç soru seçmediniz. Yine de kaydetmek istiyor musunuz?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet, Kaydet')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() {
      _isSaving = true;
      if (downloadPdfAfterSave) _isGeneratingPdf = true;
    });
    // Animasyonun PDF işlemi başlamadan ekrana çizilebilmesi için kısa bir nefes payı
    if (downloadPdfAfterSave) {
      await Future.delayed(const Duration(milliseconds: 350));
    }

    try {
      final Map<String, Map<String, dynamic>> byId = {};
      for (int i = 0; i < allPoolDocs.length; i++) {
        final q = allPoolDocs[i];
        final pk = (q['poolKey'] ?? q['docId'] ?? '$i').toString();
        byId[pk] = q;
        if (q['docId'] != null) {
          byId[q['docId'].toString()] = q;
        }
      }

      final List<Map<String, dynamic>> selectedQuestions = [];
      for (final id in _selectedQuestionIds) {
        final found = byId[id];
        if (found != null) selectedQuestions.add(found);
      }

      final String resolvedClass = _selectedClassLevel ??
          (selectedQuestions.isNotEmpty
              ? AssessmentService.normalizeClassLevel(
                  selectedQuestions.first['classLevel']?.toString(),
                  examName: selectedQuestions.first['examName']?.toString(),
                )
              : '7. Sınıf');
      final String resolvedBranch = _selectedBranch ??
          (selectedQuestions.isNotEmpty
              ? _QuestionPoolScreenState._canonicalBranchName(
                  (selectedQuestions.first['subject'] ?? 'Karma').toString())
              : 'Karma');

      final data = {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'testType': _testType == TestType.deneme
            ? 'deneme'
            : _testType == TestType.odev
                ? 'odev'
                : 'test',
        'selectionMethod': _selectionMethod == QuestionSelectionMethod.otomatik
            ? 'otomatik'
            : 'manuel',
        'sortingAlgorithm': _sortingAlgorithm == SortingAlgorithm.smart
            ? 'smart'
            : _sortingAlgorithm == SortingAlgorithm.none
                ? 'none'
                : 'fixed',
        'examLabel': _examLabelCtrl.text.trim(),
        'headerLeftText': _headerLeftCtrl.text.trim(),
        'headerRightText': _headerRightCtrl.text.trim(),
        'footerLeftText': _footerLeftCtrl.text.trim(),
        'footerRightText': _footerRightCtrl.text.trim(),
        'questionRightLabel': _questionRightLabelCtrl.text.trim(),
        'showOutcomeOnQuestions': _showOutcomeOnQuestions,
        'showStudentBox': _showStudentBox,
        'showAnswerKey': _showAnswerKey,
        'classLevel': resolvedClass,
        'branchName': resolvedBranch,
        'targetAudienceType': _targetAudienceType,
        'targetBranches': _selectedTargetBranches.toList()..sort(),
        'targetStudentIds': _selectedTargetStudentIds.toList(),
        'targetStudentNames': _selectedTargetStudentIds
            .map((id) => _selectedTargetStudentNames[id] ?? '')
            .where((s) => s.isNotEmpty)
            .toList(),
        'targetSummary': _targetAudienceSummary,
        'excludePreviouslyUsedQuestions': _excludePreviouslyUsedQuestions,
        'targetQuestionCount': _targetQuestionCount.round(),
        'levelRatios': _levelRatios.map((e) => e.round()).toList(),
        'institutionId': widget.institutionId,
        'schoolTypeId': widget.schoolTypeId,
        'questionCount': _selectedQuestionIds.length,
        'questionIds': _selectedQuestionIds,
        'questionContentKeys': selectedQuestions
            .map(_contentKeyOfQuestion)
            .where((k) => k.isNotEmpty)
            .toSet()
            .toList(),
        'questionKinds': _enabledQuestionKinds.toList(),
        'scopeOutcomes': _hasActiveScope ? _scopeSubOutcomeKeys.toList() : <String>[],
        'scopeContext': _hasActiveScope ? _scopeContext : '',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final ref = FirebaseFirestore.instance
          .collection('institutions')
          .doc(widget.institutionId)
          .collection('question_pool_tests');

      if (widget.editingData?['docId'] != null) {
        await ref.doc(widget.editingData!['docId']).update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await ref.add(data);
      }

      if (downloadPdfAfterSave && selectedQuestions.isNotEmpty) {
        await ErrorBookletGeneratorService().generateAndDownloadTestPdf(
          title: _titleCtrl.text.trim(),
          subtitle: _descCtrl.text.trim(),
          examLabel: _examLabelCtrl.text.trim(),
          testType: _testType == TestType.deneme
              ? 'deneme'
              : _testType == TestType.odev
                  ? 'odev'
                  : 'test',
          classLevel: resolvedClass,
          branchName: resolvedBranch,
          schoolName: widget.schoolTypeName ?? 'eduKN Kurumsal',
          sortingAlgorithm: _sortingAlgorithm == SortingAlgorithm.smart
              ? 'smart'
              : _sortingAlgorithm == SortingAlgorithm.none
                  ? 'none'
                  : 'fixed',
          questions: selectedQuestions,
          headerLeftText: _headerLeftCtrl.text.trim(),
          headerRightText: _headerRightCtrl.text.trim(),
          footerLeftText: _footerLeftCtrl.text.trim(),
          footerRightText: _footerRightCtrl.text.trim(),
          showOutcomeOnQuestions: _showOutcomeOnQuestions,
          showStudentBox: _showStudentBox,
          showAnswerKey: _showAnswerKey,
          questionRightLabel: _questionRightLabelCtrl.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              downloadPdfAfterSave
                  ? 'Test kaydedildi ve PDF indirildi ✓'
                  : 'Test başarıyla kaydedildi ✓',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Save/PDF error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('İşlem hatası: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isGeneratingPdf = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: widget.editingData != null ? 'Testi Düzenle' : 'Yeni Test Oluştur',
        subtitle: widget.schoolTypeName ?? 'Adım Adım Akıllı Yaprak Test & Deneme Sihirbazı',
        actions: [
          if (_selectedQuestionIds.isNotEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 14),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 15, color: Colors.indigo),
                    const SizedBox(width: 6),
                    Text(
                      '${_selectedQuestionIds.length} / ${_targetQuestionCount.round()} Soru Seçili',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: SafeStreamBuilder<List<Map<String, dynamic>>>(
        stream: _wizardPoolStream,
        initialData: AssessmentService.getCachedQuestionsPool(widget.institutionId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final allPoolDocs = snapshot.data ?? [];
          PoolAutoWideFixer.schedule(
            allPoolDocs,
            visibleDocs: const [],
            onChanged: () {
              if (mounted) setState(() {});
            },
          );

          return Stack(
            children: [
              Column(
                children: [
                  _buildProgressBar(),
                  Expanded(
                    child: _buildStepBody(allPoolDocs),
                  ),
                  _buildBottomNavBar(allPoolDocs),
                ],
              ),
              if (_isGeneratingPdf)
                PdfGeneratingOverlay(
                  title: '${_titleCtrl.text.trim().isEmpty ? 'Yaprak Test' : _titleCtrl.text.trim()} hazırlanıyor',
                  questionCount: _selectedQuestionIds.length,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgressBar() {
    final steps = [
      ('1. Temel Bilgiler', Icons.description_outlined),
      ('2. Soru Sayısı & Zorluk', Icons.tune_rounded),
      ('3. Soru Seçimi (8\'li)', Icons.checklist_rtl_rounded),
      ('4. Önizleme & PDF İndir', Icons.picture_as_pdf_rounded),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: List.generate(steps.length, (i) {
          final done = i < _step;
          final active = i == _step;
          return Expanded(
            child: InkWell(
              onTap: () {
                if (i == 0 || _step1Valid) {
                  setState(() => _step = i);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.indigo
                          : done
                              ? Colors.green.shade600
                              : Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      done ? Icons.check_rounded : steps[i].$2,
                      size: 17,
                      color: (active || done) ? Colors.white : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      steps[i].$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        color: active
                            ? Colors.indigo.shade900
                            : done
                                ? Colors.green.shade800
                                : Colors.grey.shade500,
                      ),
                    ),
                  ),
                  if (i < steps.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: done ? Colors.green.shade400 : Colors.grey.shade200,
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepBody(List<Map<String, dynamic>> allPoolDocs) {
    switch (_step) {
      case 0:
        return _buildStep1BasicInfo(allPoolDocs);
      case 1:
        return _buildStep2SlidersAndStrategy(allPoolDocs);
      case 2:
        return _buildStep3HierarchicalSelection(allPoolDocs);
      case 3:
        return _buildStep4PreviewAndPdf(allPoolDocs);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── ADIM 1: Temel Bilgiler & Hedef Sınıf / Branş ───────────────────────────
  Widget _buildStep1BasicInfo(List<Map<String, dynamic>> allPoolDocs) {
    final Set<String> classSet = {..._QuestionPoolScreenState._allStandardClassLevels};
    final Set<String> branchSet = {
      'Türkçe',
      'Matematik',
      'Fen Bilimleri',
      'Sosyal Bilgiler',
      'T.C. İnkılap Tarihi',
      'Din Kültürü ve Ahlak Bilgisi',
      'İngilizce',
    };

    for (final q in allPoolDocs) {
      final cls = AssessmentService.normalizeClassLevel(
        q['classLevel']?.toString(),
        examName: q['examName']?.toString(),
      );
      classSet.add(cls);
      final br = _QuestionPoolScreenState._canonicalBranchName((q['subject'] ?? '').toString());
      if (br.isNotEmpty) branchSet.add(br);
    }

    final classList = classSet.toList();
    final branchList = branchSet.toList();

    _selectedClassLevel ??= classList.contains('7. Sınıf') ? '7. Sınıf' : classList.first;
    _selectedBranch ??= branchList.first;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(
                  '1. Adım — Test Kimliği, Sınıf ve Branş Seçimi',
                  'Oluşturacağınız yaprak test, deneme veya ödevin başlığını, sınıf seviyesini ve dersini seçin.',
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel(Icons.school_rounded, 'Hedef Sınıf Seviyesi', required: true),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: classList.contains(_selectedClassLevel) ? _selectedClassLevel : classList.first,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                            items: classList
                                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _selectedClassLevel = v;
                                  _selectedTargetBranches.clear();
                                  _selectedTargetStudentIds.clear();
                                  _selectedTargetStudentNames.clear();
                                  _studentBranchFilterInPicker = null;
                                  _selectedTopicKey = null;
                                  _selectedSubOutcomeDesc = null;
                                  _currentPoolPage = 1;
                                  _onTargetAudienceChanged();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel(Icons.menu_book_rounded, 'Ana Branş / Ders', required: true),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: branchList.contains(_selectedBranch) ? _selectedBranch : branchList.first,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                            items: branchList
                                .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _selectedBranch = v;
                                  _selectedTopicKey = null;
                                  _selectedSubOutcomeDesc = null;
                                  _currentPoolPage = 1;
                                  _onTargetAudienceChanged();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _buildTargetAudienceAndMemorySection(allPoolDocs),
                const SizedBox(height: 20),
                _buildFieldLabel(Icons.title_rounded, 'Test Başlığı', required: true),
                const SizedBox(height: 8),
                TextField(
                  controller: _titleCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Örn: ${_selectedClassLevel ?? '7. Sınıf'} ${_selectedBranch ?? 'Matematik'} Konu Tarama Testi - 1',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.all(16),
                    suffixIcon: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _titleCtrl.text =
                              '${_selectedClassLevel ?? '7. Sınıf'} ${_selectedBranch ?? 'Matematik'} Yaprak Testi';
                        });
                      },
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                      label: const Text('Otomatik Doldur', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel(Icons.info_outline_rounded, 'Alt Başlık / Açıklama'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _descCtrl,
                            decoration: InputDecoration(
                              hintText: 'Örn: 1. Dönem Kazanım Değerlendirme Çalışması',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.all(16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel(Icons.label_outline_rounded, 'PDF Üst Rozet Etiketi'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _examLabelCtrl,
                            decoration: InputDecoration(
                              hintText: 'Örn: LGS / TARAMA',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.all(16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildFieldLabel(Icons.category_outlined, 'Test Türü', required: true),
                const SizedBox(height: 10),
                Row(
                  children: TestType.values.map((t) {
                    final sel = _testType == t;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: InkWell(
                          onTap: () => setState(() => _testType = t),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                            decoration: BoxDecoration(
                              color: sel ? t.color.withValues(alpha: 0.08) : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: sel ? t.color : Colors.grey.shade200,
                                width: sel ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(t.icon, color: sel ? t.color : Colors.grey.shade600, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  t.label,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: sel ? t.color : const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 20),
                _buildPdfHeaderFooterAndOutcomeSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Testi oluşturmadan önce kimin için oluşturulacağını (Sınıf Seviyesi / Şube / Öğrenci veya Öğrenciler)
  /// soran ve "Bir Sonraki Test Hazırlamada Aynı Sorular Kullanılmasın" (varsayılan açık) hafıza kontrolünü sunan bölüm.
  Widget _buildTargetAudienceAndMemorySection(List<Map<String, dynamic>> allPoolDocs) {
    final activeCls = _selectedClassLevel ?? '7. Sınıf';
    final activeSubj = _selectedBranch ?? 'Matematik';
    final availableBranches = _availableBranchesForSelectedClass();
    final classStudents = _studentsForSelectedClass();
    final mem = _computeUsedQuestionsMemory();

    // Seçili sınıf + dersteki toplam soru ve daha önce kullanılmış soru sayısı
    final matchingBranchQs = allPoolDocs.where((q) {
      final cls = AssessmentService.normalizeClassLevel(
        q['classLevel']?.toString(),
        examName: q['examName']?.toString(),
      );
      final br = _QuestionPoolScreenState._canonicalBranchName((q['subject'] ?? '').toString());
      return _QuestionPoolScreenState._classLevelsMatch(cls, activeCls) &&
          _QuestionPoolScreenState._branchesMatch(br, activeSubj);
    }).toList();
    final int usedInPoolCount = matchingBranchQs.where((q) => _isQuestionPreviouslyUsed(q, mem)).length;
    final int unusedInPoolCount = (matchingBranchQs.length - usedInPoolCount).clamp(0, 999999);

    // Öğrenci seçici için filtreleme
    final String searchQ = _studentSearchCtrl.text.trim().toLowerCase();
    final Set<String> studentBranchesSet = {
      for (final s in classStudents)
        if ((s['className'] ?? '').toString().trim().isNotEmpty &&
            (s['className'] ?? '').toString().trim() != 'Belirtilmedi')
          (s['className'] ?? '').toString().trim(),
    };
    final List<String> studentBranchesList = studentBranchesSet.toList()..sort();
    final List<Map<String, dynamic>> filteredStudents = classStudents.where((s) {
      if (_studentBranchFilterInPicker != null &&
          _studentBranchFilterInPicker!.isNotEmpty &&
          (s['className'] ?? '').toString().trim() != _studentBranchFilterInPicker) {
        return false;
      }
      if (searchQ.isNotEmpty) {
        final name = (s['name'] ?? '').toString().toLowerCase();
        final no = (s['studentNo'] ?? '').toString().toLowerCase();
        final br = (s['className'] ?? '').toString().toLowerCase();
        if (!name.contains(searchQ) && !no.contains(searchQ) && !br.contains(searchQ)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.shade100, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.indigo,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.groups_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bu Testi Kim İçin Oluşturuyorsunuz?',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sınıf seviyesine, şubeye veya belirli öğrenci/öğrencilere göre seçiminizi yapın; oluşturduğunuz test hafızada tutulur.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_user_rounded, size: 15, color: Colors.indigo),
                    const SizedBox(width: 6),
                    Text(
                      _targetAudienceSummary,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3 Hedef Kitle Seçeneği: Sınıf Seviyesi Genel | Şube / Şubeler | Öğrenci / Öğrenciler
          Row(
            children: [
              Expanded(
                child: _buildSelectionTile(
                  selected: _targetAudienceType == 'class',
                  icon: Icons.school_rounded,
                  color: Colors.indigo,
                  label: 'Sınıf Seviyesi ($activeCls Genel)',
                  subtitle: 'Tüm $activeCls seviyesine uygulanacak ortak test',
                  onTap: () => setState(() {
                    _targetAudienceType = 'class';
                    _onTargetAudienceChanged();
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSelectionTile(
                  selected: _targetAudienceType == 'branch',
                  icon: Icons.class_rounded,
                  color: Colors.deepPurple,
                  label: 'Şube / Şubeler Seç',
                  subtitle: _selectedTargetBranches.isEmpty
                      ? 'Örn: ${availableBranches.take(2).join(', ')}'
                      : 'Seçili: ${(_selectedTargetBranches.toList()..sort()).join(', ')}',
                  onTap: () => setState(() {
                    _targetAudienceType = 'branch';
                    if (_selectedTargetBranches.isEmpty && availableBranches.isNotEmpty) {
                      _selectedTargetBranches.add(availableBranches.first);
                    }
                    _onTargetAudienceChanged();
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSelectionTile(
                  selected: _targetAudienceType == 'student',
                  icon: Icons.person_search_rounded,
                  color: Colors.teal.shade700,
                  label: 'Öğrenci / Öğrenciler Seç',
                  subtitle: _selectedTargetStudentIds.isEmpty
                      ? 'Bireysel veya seçili öğrenci grubu için'
                      : '${_selectedTargetStudentIds.length} öğrenci seçildi',
                  onTap: () => setState(() {
                    _targetAudienceType = 'student';
                    _onTargetAudienceChanged();
                  }),
                ),
              ),
            ],
          ),

          // ŞUBE SEÇİM ALANI
          if (_targetAudienceType == 'branch') ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.class_outlined, size: 16, color: Colors.deepPurple),
                      const SizedBox(width: 6),
                      Text(
                        '$activeCls Şubelerini Seçin (Birden fazla şube seçebilirsiniz):',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() {
                          _selectedTargetBranches.addAll(availableBranches);
                          _onTargetAudienceChanged();
                        }),
                        child: const Text('Tüm Şubeleri Seç', style: TextStyle(fontSize: 11.5)),
                      ),
                      if (_selectedTargetBranches.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() {
                            _selectedTargetBranches.clear();
                            _onTargetAudienceChanged();
                          }),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Temizle', style: TextStyle(fontSize: 11.5)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...availableBranches.map((br) {
                        final isSel = _selectedTargetBranches.contains(br);
                        return FilterChip(
                          label: Text(br),
                          selected: isSel,
                          selectedColor: Colors.deepPurple,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSel ? Colors.white : const Color(0xFF334155),
                          ),
                          onSelected: (v) => setState(() {
                            if (v) {
                              _selectedTargetBranches.add(br);
                            } else {
                              _selectedTargetBranches.remove(br);
                            }
                            _onTargetAudienceChanged();
                          }),
                        );
                      }),
                      SizedBox(
                        width: 170,
                        height: 34,
                        child: TextField(
                          controller: _customBranchCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Yeni şube ekle (Örn: 7-E)',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                            suffixIcon: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.add_circle_rounded, size: 18, color: Colors.deepPurple),
                              onPressed: () {
                                final val = _customBranchCtrl.text.trim().toUpperCase();
                                if (val.isNotEmpty) {
                                  setState(() {
                                    _selectedTargetBranches.add(val);
                                    _customBranchCtrl.clear();
                                    _onTargetAudienceChanged();
                                  });
                                }
                              },
                            ),
                          ),
                          onSubmitted: (v) {
                            final val = v.trim().toUpperCase();
                            if (val.isNotEmpty) {
                              setState(() {
                                _selectedTargetBranches.add(val);
                                _customBranchCtrl.clear();
                                _onTargetAudienceChanged();
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // ÖĞRENCİ SEÇİM ALANI
          if (_targetAudienceType == 'student') ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.people_alt_rounded, size: 16, color: Colors.teal.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Testin Hazırlanacağı Öğrenci / Öğrencileri Seçin (${_selectedTargetStudentIds.length} seçili):',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      if (filteredStudents.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() {
                            for (final s in filteredStudents) {
                              final id = s['id'].toString();
                              _selectedTargetStudentIds.add(id);
                              _selectedTargetStudentNames[id] = s['name'].toString();
                            }
                            _onTargetAudienceChanged();
                          }),
                          child: const Text('Listeyi Seç', style: TextStyle(fontSize: 11.5)),
                        ),
                      if (_selectedTargetStudentIds.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() {
                            _selectedTargetStudentIds.clear();
                            _selectedTargetStudentNames.clear();
                            _onTargetAudienceChanged();
                          }),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Seçimi Temizle', style: TextStyle(fontSize: 11.5)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _studentSearchCtrl,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 12.5),
                          decoration: InputDecoration(
                            hintText: 'Öğrenci adı, numarası veya şubesi ile ara...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 18),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      if (studentBranchesList.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<String?>(
                            initialValue: studentBranchesList.contains(_studentBranchFilterInPicker)
                                ? _studentBranchFilterInPicker
                                : null,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Tüm Şubeler', style: TextStyle(fontSize: 12)),
                              ),
                              ...studentBranchesList.map(
                                (b) => DropdownMenuItem<String?>(
                                  value: b,
                                  child: Text(b, style: const TextStyle(fontSize: 12)),
                                ),
                              ),
                            ],
                            onChanged: (v) => setState(() => _studentBranchFilterInPicker = v),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_selectedTargetStudentIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selectedTargetStudentIds.map((id) {
                        final name = _selectedTargetStudentNames[id] ?? id;
                        return InputChip(
                          label: Text(name, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                          backgroundColor: Colors.teal.shade50,
                          deleteIconColor: Colors.teal.shade900,
                          onDeleted: () => setState(() {
                            _selectedTargetStudentIds.remove(id);
                            _selectedTargetStudentNames.remove(id);
                            _onTargetAudienceChanged();
                          }),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (_isLoadingAudienceData)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (filteredStudents.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Bu filtrede öğrenci bulunamadı. Aşağıdan hızlıca öğrenci adı ekleyebilirsiniz:',
                        style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 165),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredStudents.length,
                        itemBuilder: (ctx, idx) {
                          final stu = filteredStudents[idx];
                          final id = stu['id'].toString();
                          final name = stu['name'].toString();
                          final cName = (stu['className'] ?? '').toString();
                          final sNo = (stu['studentNo'] ?? '').toString();
                          final isSel = _selectedTargetStudentIds.contains(id);
                          return CheckboxListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                            value: isSel,
                            activeColor: Colors.teal.shade700,
                            title: Text(
                              name,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                            subtitle: (cName.isNotEmpty || sNo.isNotEmpty)
                                ? Text(
                                    [
                                      if (cName.isNotEmpty) 'Şube: $cName',
                                      if (sNo.isNotEmpty && sNo != '-') 'No: $sNo',
                                    ].join(' • '),
                                    style: const TextStyle(fontSize: 11),
                                  )
                                : null,
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selectedTargetStudentIds.add(id);
                                _selectedTargetStudentNames[id] = name;
                              } else {
                                _selectedTargetStudentIds.remove(id);
                                _selectedTargetStudentNames.remove(id);
                              }
                              _onTargetAudienceChanged();
                            }),
                          );
                        },
                      ),
                    ),
                  if (_studentSearchCtrl.text.trim().isNotEmpty &&
                      !filteredStudents.any(
                        (s) => s['name'].toString().toLowerCase() == _studentSearchCtrl.text.trim().toLowerCase(),
                      ))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          final raw = _studentSearchCtrl.text.trim();
                          if (raw.isEmpty) return;
                          final customId = 'custom_${raw.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';
                          setState(() {
                            _selectedTargetStudentIds.add(customId);
                            _selectedTargetStudentNames[customId] = raw;
                            _studentSearchCtrl.clear();
                            _onTargetAudienceChanged();
                          });
                        },
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                        label: Text('"${_studentSearchCtrl.text.trim()}" öğrencisini hedefe ekle'),
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // DAHA ÖNCE KULLANILAN SORULAR KULLANILMASIN SWITCH (VARSAYILAN AÇIK / DEFAULT ON)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _excludePreviouslyUsedQuestions
                  ? Colors.amber.shade50
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _excludePreviouslyUsedQuestions
                    ? Colors.amber.shade400
                    : Colors.grey.shade300,
                width: _excludePreviouslyUsedQuestions ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _excludePreviouslyUsedQuestions
                        ? Colors.amber.shade800
                        : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.history_edu_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Bir Sonraki Test Hazırlamada Aynı Sorular Kullanılmasın',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _excludePreviouslyUsedQuestions
                                  ? Colors.green.shade600
                                  : Colors.grey.shade500,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _excludePreviouslyUsedQuestions ? 'VARSAYILAN AÇIK' : 'KAPALI',
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        mem.matchingPastTestCount > 0
                            ? '$_targetAudienceSummary için daha önce ${mem.matchingPastTestCount} testte toplam $usedInPoolCount soru kullanılmış • '
                              'Havuzda $unusedInPoolCount yeni (kullanılmamış) soru var. '
                              'Açık kaldığında otomatik seçimde kullanılmış sorular seçilmez ve Soru Seç ekranında "Daha Önce Kullanıldı" işareti görünür.'
                            : '$_targetAudienceSummary için $activeSubj dersinde henüz kayıtlı geçmiş test yok (${matchingBranchQs.length} sorunun tamamı yeni).',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _excludePreviouslyUsedQuestions,
                  activeThumbColor: Colors.amber.shade900,
                  onChanged: (v) => setState(() {
                    _excludePreviouslyUsedQuestions = v;
                    _onTargetAudienceChanged();
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// PDF Üste / Alta Neler Yazılacağını ve Sorunun Üstünde Kazanım Yazıp Yazmayacağını Soran Bölüm
  Widget _buildPdfHeaderFooterAndOutcomeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'PDF Sayfa Üst / Alt Yazıları & Soru Üstü Kazanım Tercihi',
          'Test oluşturulurken sayfanın üst (antet) ve alt (footer) kısımlarına neler yazılacağını ve soru üstünde kazanım görünüp görünmeyeceğini belirleyin.',
        ),
        const SizedBox(height: 16),

        // 1) SORUNUN KAZANIMI SORU ÜSTÜNDE YAZSIN MI YAZMASIN MI?
        _buildFieldLabel(
          Icons.bookmark_added_outlined,
          'Sorunun Kazanımı Soru Üstünde Yazsın mı?',
          required: true,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSelectionTile(
                selected: _showOutcomeOnQuestions,
                icon: Icons.visibility_rounded,
                color: Colors.indigo,
                label: 'Evet, Soru Üstünde Kazanım Yazsın',
                subtitle: 'Örn: [1. SORU]  Okudukları ile ilgili çıkarımlarda bulunur.',
                onTap: () => setState(() => _showOutcomeOnQuestions = true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSelectionTile(
                selected: !_showOutcomeOnQuestions,
                icon: Icons.visibility_off_rounded,
                color: Colors.deepOrange,
                label: 'Hayır, Kazanım Yazmasın',
                subtitle: 'Soru üst bandında yalnızca [1. SORU] numarası yer alır',
                onTap: () => setState(() => _showOutcomeOnQuestions = false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // 2) PDF ÜST KISMA (SAYFA TEPESİ / ANTET) NELER YAZILACAK?
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.indigo.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.vertical_align_top_rounded, size: 18, color: Colors.indigo.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Sayfa Üst Kısmına (Antet) Neler Yazılacak?',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel(Icons.school_outlined, 'Üst Sol Yazı (Kurum / Okul Adı)'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _headerLeftCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Örn: ABC ORTAOKULU',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                        _buildFieldLabel(Icons.badge_outlined, 'Üst Orta Rozet Etiketi'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _examLabelCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Örn: DENEME SINAVI / YAPRAK TEST',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                        _buildFieldLabel(Icons.short_text_rounded, 'Üst Sağ Bilgi Yazısı (Opsiyonel)'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _headerRightCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Boşsa: Sınıf • Branş • Soru Sayısı',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeTrackColor: Colors.indigo,
                title: Text(
                  'İlk Sayfada Öğrenci Ad Soyad / Sınıf-No / D-Y-Net Kutusu Gösterilsin',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                value: _showStudentBox,
                onChanged: (v) => setState(() => _showStudentBox = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3) PDF ALT KISMA (SAYFA ALTI / FOOTER) NELER YAZILACAK?
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.teal.shade50.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.teal.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.vertical_align_bottom_rounded, size: 18, color: Colors.teal.shade800),
                  const SizedBox(width: 8),
                  Text(
                    'Sayfa Alt Kısmına (Footer) Neler Yazılacak?',
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel(Icons.notes_rounded, 'Alt Sol Yazı (Footer Sol)'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _footerLeftCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Örn: ABC Ortaokulu • eduKN Akıllı Soru Havuzu',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel(Icons.emoji_events_outlined, 'Alt Sağ Yazı (Footer Sağ)'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _footerRightCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Örn: Başarılar Dileriz',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel(Icons.sell_outlined, 'Soru Sağ Etiketi'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _questionRightLabelCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Örn: eduKN',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeTrackColor: Colors.teal,
                title: Text(
                  'Son Sayfanın Altında Cevap Anahtarı Şeridi Gösterilsin',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                value: _showAnswerKey,
                onChanged: (v) => setState(() => _showAnswerKey = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── ADIM 2: Soru Sayısı Slider'ı & Zorluk Derecesi Slider'ı & Seçim Modu ───
  /// 2. Adım: "Hangi konulardan / kazanımlardan soru seçilsin?" kartı.
  Widget _buildScopeCard(
    List<_TopicGroup> topics,
    List<Map<String, dynamic>> allBranchQuestions,
    List<Map<String, dynamic>> kindQuestions,
    int scopedCount,
  ) {
    final bool active = _hasActiveScope;
    final visibleTopics = topics.where((t) => t.allQuestions.isNotEmpty).toList();
    final int cntCoktan = allBranchQuestions
        .where((q) => _questionKindCategory(q) == 'coktan_secmeli')
        .length;
    final int cntEgzersiz = allBranchQuestions
        .where((q) => _questionKindCategory(q) == 'egzersiz')
        .length;
    final int cntDeneme = allBranchQuestions
        .where((q) => _questionKindCategory(q) == 'deneme')
        .length;

    bool? topicState(_TopicGroup t) {
      if (!active) return false;
      final subs = t.subOutcomes
          .where((s) => (t.questionsBySubOutcome[s.description.trim()]?.isNotEmpty ?? false))
          .toList();
      if (subs.isEmpty) return false;
      final sel = subs.where((s) => _scopeSubOutcomeKeys.contains(_scopeKey(t, s))).length;
      if (sel == 0) return false;
      if (sel == subs.length) return true;
      return null; // kısmi
    }

    void ensureContext() {
      if (_scopeContext != _currentScopeContext()) {
        _scopeSubOutcomeKeys.clear();
        _scopeContext = _currentScopeContext();
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? Colors.teal.shade300 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSectionHeader(
                  'Soru Türü / Kaynağı & Konu Kapsamı',
                  'Çoktan Seçmeli, Egzersiz ve Deneme Sınavı sorularından hangilerinin dahil edileceğini açıp kapatın; ardından konuları seçin.',
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? Colors.teal : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  active ? '$scopedCount soru kapsamda' : 'Tüm konular (${kindQuestions.length})',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: active ? Colors.white : const Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Soru türü & kaynağı (Çoktan Seçmeli / Egzersiz / Deneme Sınavı) — aç/kapat
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final kind in [
                ('coktan_secmeli', 'Çoktan Seçmeli ($cntCoktan)', Colors.indigo),
                ('egzersiz', 'Egzersiz Soruları ($cntEgzersiz)', Colors.purple),
                ('deneme', 'Deneme Sınavı ($cntDeneme)', Colors.teal.shade700),
              ])
                FilterChip(
                  label: Text(kind.$2),
                  selected: _enabledQuestionKinds.contains(kind.$1),
                  selectedColor: kind.$3,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _enabledQuestionKinds.contains(kind.$1)
                        ? Colors.white
                        : const Color(0xFF334155),
                  ),
                  onSelected: (_) => setState(() {
                    _toggleQuestionKind(kind.$1);
                    _scopeSubOutcomeKeys.clear();
                    _onScopeChanged();
                  }),
                ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: visibleTopics.isEmpty
                    ? null
                    : () => setState(() {
                          ensureContext();
                          for (final t in visibleTopics) {
                            for (final s in t.subOutcomes) {
                              if (t.questionsBySubOutcome[s.description.trim()]?.isNotEmpty ?? false) {
                                _scopeSubOutcomeKeys.add(_scopeKey(t, s));
                              }
                            }
                          }
                          _onScopeChanged();
                        }),
                icon: const Icon(Icons.select_all_rounded, size: 16),
                label: const Text('Tümünü İşaretle', style: TextStyle(fontSize: 12)),
              ),
              TextButton.icon(
                onPressed: visibleTopics.isEmpty
                    ? null
                    : () => setState(() {
                          final allOpen = visibleTopics
                              .every((t) => _scopeExpandedTopicTitles.contains(t.title));
                          if (allOpen) {
                            _scopeExpandedTopicTitles.clear();
                          } else {
                            _scopeExpandedTopicTitles
                                .addAll(visibleTopics.map((t) => t.title));
                          }
                        }),
                icon: Icon(
                  visibleTopics.isNotEmpty &&
                          visibleTopics.every((t) => _scopeExpandedTopicTitles.contains(t.title))
                      ? Icons.unfold_less_rounded
                      : Icons.unfold_more_rounded,
                  size: 16,
                ),
                label: Text(
                  visibleTopics.isNotEmpty &&
                          visibleTopics.every((t) => _scopeExpandedTopicTitles.contains(t.title))
                      ? 'Tümünü Kapat'
                      : 'Tümünü Aç',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (active)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _scopeSubOutcomeKeys.clear();
                    _onScopeChanged();
                  }),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: const Text('Temizle (Tüm Konular)', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (visibleTopics.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Bu sınıf/branş ve seçili soru türü ($_enabledKindsLabel) için soru bulunamadı.',
                style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey.shade500),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 380),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final t in visibleTopics) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      child: Row(
                        children: [
                          Checkbox(
                            tristate: true,
                            activeColor: Colors.teal,
                            value: topicState(t),
                            onChanged: (_) => setState(() {
                              ensureContext();
                              final subsWithQs = t.subOutcomes.where(
                                (s) => t.questionsBySubOutcome[s.description.trim()]?.isNotEmpty ?? false,
                              );
                              final bool allSelected = topicState(t) == true;
                              for (final s in subsWithQs) {
                                if (allSelected) {
                                  _scopeSubOutcomeKeys.remove(_scopeKey(t, s));
                                } else {
                                  _scopeSubOutcomeKeys.add(_scopeKey(t, s));
                                }
                              }
                              _onScopeChanged();
                            }),
                          ),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(() {
                                if (!_scopeExpandedTopicTitles.remove(t.title)) {
                                  _scopeExpandedTopicTitles.add(t.title);
                                }
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                                child: Row(
                                  children: [
                                    Icon(
                                      _scopeExpandedTopicTitles.contains(t.title)
                                          ? Icons.folder_open_rounded
                                          : Icons.folder_rounded,
                                      size: 17,
                                      color: Colors.amber.shade800,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        t.code.isNotEmpty ? '${t.code} - ${t.title}' : t.title,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${t.allQuestions.length} soru',
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      _scopeExpandedTopicTitles.contains(t.title)
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      size: 20,
                                      color: Colors.grey.shade600,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_scopeExpandedTopicTitles.contains(t.title))
                    for (final s in t.subOutcomes)
                      if (t.questionsBySubOutcome[s.description.trim()]?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(left: 28),
                          child: CheckboxListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: Colors.teal,
                            value: active && _scopeSubOutcomeKeys.contains(_scopeKey(t, s)),
                            title: Text(
                              s.code.isNotEmpty ? '${s.code} - ${s.description}' : s.description,
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF334155)),
                            ),
                            secondary: Text(
                              '${t.questionsBySubOutcome[s.description.trim()]!.length}',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                            onChanged: (v) => setState(() {
                              ensureContext();
                              if (v == true) {
                                _scopeSubOutcomeKeys.add(_scopeKey(t, s));
                              } else {
                                _scopeSubOutcomeKeys.remove(_scopeKey(t, s));
                              }
                              _onScopeChanged();
                            }),
                          ),
                        ),
                    Divider(height: 1, color: Colors.grey.shade100),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStep2SlidersAndStrategy(List<Map<String, dynamic>> allPoolDocs) {
    final counts = _targetLevelCounts;
    final int targetTotal = _targetQuestionCount.round();

    // Seçili sınıf + branştaki mevcut soru sayılarını da gösterelim
    final activeClass = _selectedClassLevel ?? '7. Sınıf';
    final activeBranch = _selectedBranch ?? 'Matematik';
    final matchingBranchQs = allPoolDocs.where((q) {
      final cls = AssessmentService.normalizeClassLevel(
        q['classLevel']?.toString(),
        examName: q['examName']?.toString(),
      );
      final br = _QuestionPoolScreenState._canonicalBranchName((q['subject'] ?? '').toString());
      return _QuestionPoolScreenState._classLevelsMatch(cls, activeClass) &&
          _QuestionPoolScreenState._branchesMatch(br, activeBranch);
    }).toList();

    final List<int> availByLevel = List<int>.filled(5, 0);
    final scopeTree = _computeScopeTree(allPoolDocs);
    final List<Map<String, dynamic>> scopedCandidates =
        _scopedFromTopics(scopeTree.topics, scopeTree.kindQuestions);
    final usedMem = _computeUsedQuestionsMemory();
    final List<Map<String, dynamic>> unusedScopedCandidates = scopedCandidates
        .where((q) => !_isQuestionPreviouslyUsed(q, usedMem))
        .toList();
    final int usedScopedCount = scopedCandidates.length - unusedScopedCandidates.length;
    final List<Map<String, dynamic>> effectivePoolForCounts =
        _excludePreviouslyUsedQuestions ? unusedScopedCandidates : scopedCandidates;
    for (final q in effectivePoolForCounts) {
      final d = (q['difficulty'] as num?)?.toDouble() ?? DifficultyScale.defaultScore;
      availByLevel[DifficultyScale.levelOf(d) - 1]++;
    }
    final String availSummary = [
      for (int i = 0; i < 5; i++) '${availByLevel[i]} ${DifficultyScale.labels[i]}',
    ].join(', ');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            children: [
              // KART 1: Soru Sayısı Slider'ı
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildSectionHeader(
                            'Hedef Soru Sayısı ($_targetAudienceSummary)',
                            '$activeClass • $activeBranch havuzunda toplam ${matchingBranchQs.length} soru var. '
                            '${_hasActiveScope ? 'Seçili konu kapsamında' : 'Seçilebilir ($_enabledKindsLabel)'} ${effectivePoolForCounts.length} uygun soru ($availSummary)'
                            '${usedScopedCount > 0 ? ' • Daha önce kullanılan: $usedScopedCount soru' : ''}.',
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.indigo,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '$targetTotal Soru',
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _excludePreviouslyUsedQuestions
                            ? Colors.amber.shade50
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _excludePreviouslyUsedQuestions
                              ? Colors.amber.shade300
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.history_edu_rounded,
                            size: 18,
                            color: _excludePreviouslyUsedQuestions
                                ? Colors.amber.shade900
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$_targetAudienceSummary için daha önce kullanılan sorular otomatik seçimde kullanılmasın '
                              '(${usedScopedCount > 0 ? '$usedScopedCount kullanılmış soru var' : 'henüz kullanılmış soru yok'})',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          Switch(
                            value: _excludePreviouslyUsedQuestions,
                            activeThumbColor: Colors.amber.shade900,
                            onChanged: (v) => setState(() {
                              _excludePreviouslyUsedQuestions = v;
                              _onTargetAudienceChanged();
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.indigo,
                        inactiveTrackColor: Colors.indigo.shade100,
                        thumbColor: Colors.indigo,
                        overlayColor: Colors.indigo.withValues(alpha: 0.15),
                        trackHeight: 8,
                      ),
                      child: Slider(
                        value: _targetQuestionCount.clamp(4.0, 60.0),
                        min: 4,
                        max: 60,
                        divisions: 56,
                        label: '$targetTotal Soru',
                        onChanged: (v) => setState(() => _targetQuestionCount = v.roundToDouble()),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [8, 10, 12, 15, 16, 20, 24, 30, 40].map((preset) {
                        final isSel = targetTotal == preset;
                        return ChoiceChip(
                          label: Text('$preset Soru'),
                          selected: isSel,
                          selectedColor: Colors.indigo,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSel ? Colors.white : const Color(0xFF334155),
                          ),
                          onSelected: (_) => setState(() => _targetQuestionCount = preset.toDouble()),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // KART 1.5: Konu & Kazanım Kapsamı (hangi konulardan soru seçilecek)
              _buildScopeCard(
                scopeTree.topics,
                scopeTree.allBranchQuestions,
                scopeTree.kindQuestions,
                scopedCandidates.length,
              ),
              const SizedBox(height: 18),

              // KART 2: Zorluk Derecesi Slider'ı ve Dağılım Oranları
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildSectionHeader(
                            'Zorluk Derecesi Dağılımı (5 Aşamalı)',
                            'Otomatik seçimde Çok Kolay / Kolay / Orta / Zor / Çok Zor oranlarını slider ile ayarlayın (Hata Kitapçığı ile aynı ölçek).',
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.indigo.shade100),
                          ),
                          child: Text(
                            '${[for (int i = 0; i < 5; i++) if (counts[i] > 0) '${counts[i]} ${DifficultyScale.labels[i]}'].join(' • ')} = $targetTotal Soru',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _difficultyPresets.keys.map((p) {
                        final isSel = _difficultyPreset == p;
                        return ChoiceChip(
                          label: Text(p),
                          selected: isSel,
                          selectedColor: Colors.indigo,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSel ? Colors.white : const Color(0xFF334155),
                          ),
                          onSelected: (_) => _applyDifficultyPreset(p),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    for (int i = 0; i < 5; i++) ...[
                      _buildDifficultySliderRow(
                        label: DifficultyScale.labels[i],
                        color: DifficultyScale.colors[i],
                        ratio: _levelRatios[i],
                        questionCount: counts[i],
                        availableCount: availByLevel[i],
                        onChanged: (v) => setState(() {
                          _difficultyPreset = 'Özel';
                          _levelRatios[i] = v;
                        }),
                      ),
                      if (i < 4) const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // KART 3: Soru Seçim Yöntemi (Otomatik vs Manuel) & Dizgi Modu
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                      'Soru Seçim Yöntemi & PDF Dizgi Modu',
                      'Otomatik Seç dediğinizde belirlediğiniz sayıda ve zorlukta soru otomatik seçilir; Manuel dediğinizde kazanım ağacından 8\'erli sayfalarla seçersiniz.',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSelectionTile(
                            selected: _selectionMethod == QuestionSelectionMethod.otomatik,
                            icon: Icons.auto_awesome_rounded,
                            color: Colors.indigo,
                            label: 'Otomatik Seç ($targetTotal Soru)',
                            subtitle: 'Seçilen sınıf/branş/konu ve zorluk oranına göre otomatik seçer',
                            onTap: () {
                              setState(() => _selectionMethod = QuestionSelectionMethod.otomatik);
                              _runAutoSelectFromCandidatePool(scopedCandidates);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSelectionTile(
                            selected: _selectionMethod == QuestionSelectionMethod.manuel,
                            icon: Icons.touch_app_rounded,
                            color: Colors.purple,
                            label: 'Manuel Seçim (Kazanım Ağacı • 8\'li)',
                            subtitle: 'Soru havuzundaki gibi Sınıf > Branş > Konu > Alt Konu ile seçin',
                            onTap: () => setState(() => _selectionMethod = QuestionSelectionMethod.manuel),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSelectionTile(
                            selected: _sortingAlgorithm == SortingAlgorithm.smart,
                            icon: Icons.grid_view_rounded,
                            color: Colors.teal,
                            label: 'Akıllı Profesyonel Dizgi (Smart)',
                            subtitle: '2 sütunlu ve tek sütunlu soruları ortadan çizgili en şık mizanpajla dizer',
                            onTap: () => setState(() => _sortingAlgorithm = SortingAlgorithm.smart),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSelectionTile(
                            selected: _sortingAlgorithm == SortingAlgorithm.fixed,
                            icon: Icons.format_list_numbered_rounded,
                            color: Colors.blueGrey,
                            label: 'Sabit Sıralama (Fixed)',
                            subtitle: 'Sorular seçildiği sırayla dizilir',
                            onTap: () => setState(() => _sortingAlgorithm = SortingAlgorithm.fixed),
                          ),
                        ),
                      ],
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

  Widget _buildDifficultySliderRow({
    required String label,
    required Color color,
    required double ratio,
    required int questionCount,
    required int availableCount,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  'Havuzda: $availableCount soru',
                  style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                inactiveTrackColor: color.withValues(alpha: 0.2),
                thumbColor: color,
                trackHeight: 6,
              ),
              child: Slider(
                value: ratio.clamp(0.0, 100.0),
                min: 0,
                max: 100,
                divisions: 20,
                onChanged: onChanged,
              ),
            ),
          ),
          Container(
            width: 92,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$questionCount Soru',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ADIM 3: Hiyerarşik Sınıf -> Branş -> Konu -> Alt Kazanım + 8'li Sayfalama ─
  Widget _buildStep3HierarchicalSelection(List<Map<String, dynamic>> allPoolDocs) {
    // 1. Sınıf seviyelerine göre grupla
    final Map<String, List<Map<String, dynamic>>> byClass = {};
    for (final cls in _QuestionPoolScreenState._allStandardClassLevels) {
      byClass[cls] = [];
    }
    for (final q in allPoolDocs) {
      final cls = AssessmentService.normalizeClassLevel(
        q['classLevel']?.toString(),
        examName: q['examName']?.toString(),
      );
      byClass.putIfAbsent(cls, () => []).add(q);
    }

    final List<String> availableClasses = [
      for (final c in _QuestionPoolScreenState._allStandardClassLevels)
        if (byClass.containsKey(c)) c,
      for (final c in byClass.keys)
        if (!_QuestionPoolScreenState._allStandardClassLevels.contains(c)) c,
    ];

    String activeClass = _selectedClassLevel ??
        availableClasses.firstWhere(
          (c) => (byClass[c]?.isNotEmpty ?? false),
          orElse: () => '7. Sınıf',
        );
    final List<Map<String, dynamic>> classQuestions = byClass[activeClass] ?? [];

    // 2. Branşlara göre grupla
    final Map<String, List<Map<String, dynamic>>> byBranch = {};
    for (final q in classQuestions) {
      final branch = _QuestionPoolScreenState._canonicalBranchName((q['subject'] ?? '').toString());
      byBranch.putIfAbsent(branch, () => []).add(q);
    }
    for (final ol in _outcomeLists) {
      if (_QuestionPoolScreenState._classLevelsMatch(ol.classLevel, activeClass)) {
        final branch = _QuestionPoolScreenState._canonicalBranchName(ol.branchName);
        byBranch.putIfAbsent(branch, () => []);
      }
    }

    final List<String> availableBranches = byBranch.keys.toList();
    String? activeBranch = _selectedBranch;
    if (activeBranch != null && !byBranch.containsKey(activeBranch)) {
      activeBranch = null;
    }
    if (activeBranch == null && availableBranches.isNotEmpty) {
      activeBranch = availableBranches.firstWhere(
        (b) => (byBranch[b]?.isNotEmpty ?? false),
        orElse: () => availableBranches.first,
      );
    }

    final List<Map<String, dynamic>> allBranchQuestions =
        activeBranch != null ? (byBranch[activeBranch] ?? []) : [];
    final int cntCoktan = allBranchQuestions
        .where((q) => _questionKindCategory(q) == 'coktan_secmeli')
        .length;
    final int cntEgzersiz = allBranchQuestions
        .where((q) => _questionKindCategory(q) == 'egzersiz')
        .length;
    final int cntDeneme = allBranchQuestions
        .where((q) => _questionKindCategory(q) == 'deneme')
        .length;
    final List<Map<String, dynamic>> branchQuestions = allBranchQuestions
        .where((q) => _enabledQuestionKinds.contains(_questionKindCategory(q)))
        .toList();

    // 3. Seçili Sınıf + Branş için Konu ve Alt Kazanım ağacını oluştur
    final List<_TopicGroup> topics = activeBranch != null
        ? _QuestionPoolScreenState.buildTopicsForBranch(
            _outcomeLists, activeClass, activeBranch, branchQuestions)
        : [];

    // 4. Seçili Konu / Alt Kazanım filtresi
    // 2. Adımda konu/kazanım kapsamı seçildiyse "Tüm Sorular" görünümü ve Otomatik Seç bu kapsamla sınırlanır
    List<Map<String, dynamic>> candidateQuestions =
        _scopedFromTopics(topics, branchQuestions);
    _TopicGroup? selectedTopicObj;
    if (_selectedTopicKey != null) {
      for (final t in topics) {
        if (t.key == _selectedTopicKey) {
          selectedTopicObj = t;
          break;
        }
      }
    }
    if (selectedTopicObj != null) {
      if (_selectedSubOutcomeDesc != null &&
          selectedTopicObj.questionsBySubOutcome.containsKey(_selectedSubOutcomeDesc)) {
        candidateQuestions =
            selectedTopicObj.questionsBySubOutcome[_selectedSubOutcomeDesc] ?? [];
      } else {
        candidateQuestions = selectedTopicObj.allQuestions;
      }
    }

    // Eğer Otomatik seçim modundaysa ve henüz soru seçilmediyse otomatik seçimi çalıştır
    if (_selectionMethod == QuestionSelectionMethod.otomatik &&
        !_didAutoSelectOnStep2 &&
        candidateQuestions.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_didAutoSelectOnStep2) {
          _runAutoSelectFromCandidatePool(candidateQuestions, showFeedback: true);
        }
      });
    }

    final usedMem = _computeUsedQuestionsMemory();
    final int usedInCandidateCount = candidateQuestions
        .where((q) => _isQuestionPreviouslyUsed(q, usedMem))
        .length;

    List<Map<String, dynamic>> filteredQuestions = candidateQuestions;
    if (_hidePreviouslyUsedInGrid) {
      filteredQuestions = filteredQuestions
          .where((q) => !_isQuestionPreviouslyUsed(q, usedMem))
          .toList();
    }
    if (_selectedDifficultyFilter != 'Tümü') {
      filteredQuestions = filteredQuestions.where((q) {
        final d = (q['difficulty'] as num?)?.toDouble() ?? 55.0;
        return _diffLabel(d) == _selectedDifficultyFilter;
      }).toList();
    }
    if (_showOnlySelected) {
      filteredQuestions = filteredQuestions.where((q) {
        final qId = (q['poolKey'] ?? q['docId'] ?? '').toString();
        return _selectedQuestionIds.contains(qId) ||
            (q['docId'] != null && _selectedQuestionIds.contains(q['docId'].toString()));
      }).toList();
    }

    final int totalFiltered = filteredQuestions.length;
    final int totalPages =
        totalFiltered == 0 ? 1 : ((totalFiltered + _questionsPerPage - 1) ~/ _questionsPerPage);
    final int safePage = _currentPoolPage.clamp(1, totalPages);
    final int startIndex = (safePage - 1) * _questionsPerPage;
    final List<Map<String, dynamic>> pageQuestions = totalFiltered == 0
        ? const []
        : filteredQuestions.skip(startIndex).take(_questionsPerPage).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // SOL PANEL: Sınıf -> Branş (N) -> Konu (N) -> Alt Kazanım (N)
        SizedBox(
          width: 350,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.grey.shade200)),
            ),
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Text(
                  '1. SINIF SEVİYESİ SEÇİN',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: availableClasses.map((cls) {
                    final cnt = byClass[cls]?.length ?? 0;
                    final isSel = cls == activeClass;
                    return InkWell(
                      onTap: () => setState(() {
                        _selectedClassLevel = cls;
                        _selectedBranch = null;
                        _selectedTopicKey = null;
                        _selectedSubOutcomeDesc = null;
                        _currentPoolPage = 1;
                      }),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSel
                              ? Colors.indigo
                              : (cnt > 0 ? Colors.indigo.shade50 : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$cls ($cnt)',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isSel
                                ? Colors.white
                                : (cnt > 0 ? Colors.indigo.shade900 : Colors.grey.shade500),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text(
                  '2. BRANŞ SEÇİN ($activeClass)',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                ...availableBranches.map((br) {
                  final bCount = byBranch[br]?.length ?? 0;
                  final isSel = br == activeBranch;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: InkWell(
                      onTap: () => setState(() {
                        _selectedClassLevel = activeClass;
                        _selectedBranch = br;
                        _selectedTopicKey = null;
                        _selectedSubOutcomeDesc = null;
                        _currentPoolPage = 1;
                      }),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: isSel ? Colors.indigo : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSel ? Colors.indigo : Colors.grey.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                br,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                                  color: isSel ? Colors.white : const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            Text(
                              '($bCount)',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSel ? Colors.white : Colors.indigo,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 14),
                if (activeBranch != null) ...[
                  Text(
                    '3. SORU TÜRÜ & KAYNAĞI (AÇ / KAPAT)',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final kind in [
                    ('coktan_secmeli', 'Çoktan Seçmeli Sorular', Icons.quiz_outlined, Colors.indigo, cntCoktan),
                    ('egzersiz', 'Egzersiz Soruları', Icons.edit_note_rounded, Colors.purple, cntEgzersiz),
                    ('deneme', 'Deneme Sınavı Soruları', Icons.assignment_outlined, Colors.teal.shade700, cntDeneme),
                  ])
                    Builder(
                      builder: (_) {
                        final bool isEnabled = _enabledQuestionKinds.contains(kind.$1);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: InkWell(
                            onTap: () => setState(() {
                              _toggleQuestionKind(kind.$1);
                              _selectedTopicKey = null;
                              _selectedSubOutcomeDesc = null;
                              _currentPoolPage = 1;
                            }),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isEnabled
                                    ? kind.$4.withValues(alpha: 0.1)
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isEnabled ? kind.$4 : Colors.grey.shade200,
                                  width: isEnabled ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isEnabled
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 18,
                                    color: isEnabled ? kind.$4 : Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    kind.$3,
                                    size: 15,
                                    color: isEnabled ? kind.$4 : Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      kind.$2,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: isEnabled ? FontWeight.bold : FontWeight.w500,
                                        color: isEnabled
                                            ? const Color(0xFF1E293B)
                                            : Colors.grey.shade500,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isEnabled ? kind.$4 : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${kind.$5}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isEnabled ? Colors.white : Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 14),
                  Text(
                    '4. KONU & ALT KONULAR ($activeBranch • $_enabledKindsLabel)',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => setState(() {
                      _selectedTopicKey = null;
                      _selectedSubOutcomeDesc = null;
                      _currentPoolPage = 1;
                    }),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: _selectedTopicKey == null
                            ? Colors.indigo.shade50
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _selectedTopicKey == null
                              ? Colors.indigo
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.apps_rounded, size: 15, color: Colors.indigo),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tüm $activeBranch Soruları${_hasActiveScope ? ' (Seçili Konular)' : ''}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                          ),
                          Text(
                            '(${_scopedFromTopics(topics, branchQuestions).length})',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ...topics.map((topic) {
                    final isTopicSel = _selectedTopicKey == topic.key;
                    final isExp = _expandedTopicKeys.contains(topic.key);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isTopicSel
                            ? Colors.indigo.withValues(alpha: 0.04)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isTopicSel ? Colors.indigo : Colors.grey.shade200,
                        ),
                      ),
                      child: Column(
                        children: [
                          InkWell(
                            onTap: () => setState(() {
                              _selectedTopicKey = topic.key;
                              _selectedSubOutcomeDesc = null;
                              if (isExp) {
                                _expandedTopicKeys.remove(topic.key);
                              } else {
                                _expandedTopicKeys.add(topic.key);
                              }
                              _currentPoolPage = 1;
                            }),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      if (isExp) {
                                        _expandedTopicKeys.remove(topic.key);
                                      } else {
                                        _expandedTopicKeys.add(topic.key);
                                      }
                                    }),
                                    child: Icon(
                                      isExp
                                          ? Icons.keyboard_arrow_down_rounded
                                          : Icons.keyboard_arrow_right_rounded,
                                      size: 18,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      topic.code.isNotEmpty
                                          ? '${topic.code} - ${topic.title}'
                                          : topic.title,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: isTopicSel ? FontWeight.bold : FontWeight.w600,
                                        color: const Color(0xFF1E293B),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '(${topic.allQuestions.length})',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isExp && topic.subOutcomes.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                border: Border(top: BorderSide(color: Colors.grey.shade200)),
                              ),
                              child: Column(
                                children: topic.subOutcomes.map((sub) {
                                  final desc = sub.description.trim();
                                  final subCnt = topic.questionsBySubOutcome[desc]?.length ?? 0;
                                  final isSubSel = isTopicSel && _selectedSubOutcomeDesc == desc;
                                  return InkWell(
                                    onTap: () => setState(() {
                                      _selectedTopicKey = topic.key;
                                      _selectedSubOutcomeDesc = desc;
                                      _currentPoolPage = 1;
                                    }),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      margin: const EdgeInsets.only(bottom: 3),
                                      decoration: BoxDecoration(
                                        color: isSubSel ? Colors.indigo : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              sub.code.isNotEmpty ? '${sub.code} • $desc' : desc,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: isSubSel ? FontWeight.bold : FontWeight.w500,
                                                color: isSubSel ? Colors.white : const Color(0xFF334155),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '($subCnt)',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isSubSel ? Colors.white : Colors.indigo,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),

        // SAĞ PANEL: Otomatik Seç Aksiyon Çubuğu + 8 Soruluk Sayfalı Grid + Sayfalama
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _runAutoSelectFromCandidatePool(candidateQuestions),
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: Text(
                        'Otomatik Seç (${_targetQuestionCount.round()} Soru)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    FilterChip(
                      label: Text('Sadece Seçilenler (${_selectedQuestionIds.length})'),
                      selected: _showOnlySelected,
                      selectedColor: Colors.indigo.shade100,
                      onSelected: (v) => setState(() {
                        _showOnlySelected = v;
                        _currentPoolPage = 1;
                      }),
                    ),
                    FilterChip(
                      avatar: Icon(
                        Icons.history_edu_rounded,
                        size: 15,
                        color: _excludePreviouslyUsedQuestions
                            ? Colors.amber.shade900
                            : Colors.grey.shade600,
                      ),
                      label: Text(
                        'Aynı Sorular Seçilmesin (${_excludePreviouslyUsedQuestions ? 'Açık' : 'Kapalı'})',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: _excludePreviouslyUsedQuestions
                              ? Colors.amber.shade900
                              : const Color(0xFF334155),
                        ),
                      ),
                      selected: _excludePreviouslyUsedQuestions,
                      selectedColor: Colors.amber.shade100,
                      checkmarkColor: Colors.amber.shade900,
                      onSelected: (v) => setState(() {
                        _excludePreviouslyUsedQuestions = v;
                      }),
                    ),
                    if (usedInCandidateCount > 0)
                      FilterChip(
                        avatar: Icon(
                          _hidePreviouslyUsedInGrid
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 15,
                          color: _hidePreviouslyUsedInGrid
                              ? Colors.deepOrange
                              : Colors.grey.shade700,
                        ),
                        label: Text(
                          'Kullanılanları Gizle ($usedInCandidateCount)',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        selected: _hidePreviouslyUsedInGrid,
                        selectedColor: Colors.orange.shade100,
                        onSelected: (v) => setState(() {
                          _hidePreviouslyUsedInGrid = v;
                          _currentPoolPage = 1;
                        }),
                      ),
                    if (_selectedQuestionIds.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => setState(() => _selectedQuestionIds.clear()),
                        icon: const Icon(Icons.clear_all_rounded, size: 16),
                        label: const Text('Seçimi Temizle', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    const SizedBox(width: 8),
                    for (final diff in ['Tümü', ...DifficultyScale.labels])
                      ChoiceChip(
                        label: Text(diff, style: const TextStyle(fontSize: 11.5)),
                        selected: _selectedDifficultyFilter == diff,
                        onSelected: (_) => setState(() {
                          _selectedDifficultyFilter = diff;
                          _currentPoolPage = 1;
                        }),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: pageQuestions.isEmpty
                    ? Center(
                        child: Text(
                          'Bu filtrede soru bulunamadı.',
                          style: GoogleFonts.inter(color: Colors.grey.shade500),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(18),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          mainAxisExtent: 285,
                        ),
                        itemCount: pageQuestions.length,
                        itemBuilder: (ctx, i) => _buildWizardQuestionCard(pageQuestions[i], startIndex + i),
                      ),
              ),
              if (totalFiltered > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Toplam $totalFiltered sorudan ${startIndex + 1}–${startIndex + pageQuestions.length} arası gösteriliyor (Sayfa başına 8 soru)',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: safePage > 1
                            ? () => setState(() => _currentPoolPage = safePage - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Text(
                        'Sayfa $safePage / $totalPages',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                      IconButton(
                        onPressed: safePage < totalPages
                            ? () => setState(() => _currentPoolPage = safePage + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWizardQuestionCard(Map<String, dynamic> data, int index) {
    final String qId = (data['poolKey'] ?? data['docId'] ?? '$index').toString();
    final bool isSelected = _selectedQuestionIds.contains(qId) ||
        (data['docId'] != null && _selectedQuestionIds.contains(data['docId'].toString()));
    final int selectedOrder = _selectedQuestionIds.indexOf(qId) + 1;
    final String? base64Img = data['base64Image'] as String?;
    final String? imgUrl = data['imageUrl'] as String?;
    final double diffVal = (data['difficulty'] as num?)?.toDouble() ?? 55.0;
    final String diffText = _diffLabel(diffVal);
    final Color diffCol = _diffColor(diffVal);
    final String ans = (data['correctAnswer'] ?? '-').toString();
    final resolvedKaz = GercekKazanimMapper.resolve(
      outcome: (data['outcome'] ?? '').toString().trim(),
      kazanimCode: (data['kazanimCode'] ?? '').toString().trim(),
      k12Code: (data['k12Code'] ?? '').toString().trim(),
      legacyOutcome: (data['legacyOutcome'] ?? '').toString().trim(),
    );
    final String kazanimCode = resolvedKaz.code.isNotEmpty
        ? resolvedKaz.code
        : (data['kazanimCode'] ?? '').toString().trim();
    final String outcome = resolvedKaz.outcome.isNotEmpty
        ? resolvedKaz.outcome
        : (data['outcome'] ?? '').toString().trim();
    final String displayOutcome = kazanimCode.isNotEmpty && !outcome.startsWith(kazanimCode)
        ? '$kazanimCode — $outcome'
        : outcome;
    final bool isWide = data['isWide'] == true;
    final usedMem = _computeUsedQuestionsMemory();
    final bool isPreviouslyUsed = _isQuestionPreviouslyUsed(data, usedMem);
    final int useCount = isPreviouslyUsed ? _questionUseCount(data, usedMem) : 0;
    final List<String> usedTests =
        isPreviouslyUsed ? _questionUsedTestTitles(data, usedMem) : const <String>[];

    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedQuestionIds.remove(qId);
            if (data['docId'] != null) _selectedQuestionIds.remove(data['docId'].toString());
          } else {
            _selectedQuestionIds.add(qId);
          }
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.indigo
                : (isPreviouslyUsed ? Colors.amber.shade500 : Colors.grey.shade200),
            width: isSelected ? 2.5 : (isPreviouslyUsed ? 1.8 : 1),
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? Colors.indigo.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    child: DriveImageHelper.buildPoolQuestionImage(
                      base64Image: base64Img,
                      imageUrl: imgUrl,
                      driveFileId: data['driveFileId']?.toString(),
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (kazanimCode.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade900.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          kazanimCode,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (isPreviouslyUsed)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: Tooltip(
                        message: usedTests.isNotEmpty
                            ? 'Kullanıldığı Testler ($_targetAudienceSummary):\n• ${usedTests.join('\n• ')}'
                            : '$_targetAudienceSummary için daha önce kullanıldı',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade900.withValues(alpha: 0.93),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.history_edu_rounded, size: 13, color: Colors.white),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  usedTests.isNotEmpty
                                      ? 'Daha Önce Kullanıldı${useCount > 1 ? ' (${useCount}x)' : ''} • ${usedTests.first}'
                                      : 'Daha Önce Kullanıldı${useCount > 1 ? ' (${useCount}x)' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.indigo : Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? Colors.indigo : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                            size: 14,
                            color: isSelected ? Colors.white : Colors.indigo,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isSelected
                                ? '${selectedOrder > 0 ? '$selectedOrder. ' : ''}Seçili'
                                : 'Seç',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : Colors.indigo,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.indigo.shade50.withValues(alpha: 0.5) : Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${data['subject'] ?? ''} • S.${data['questionNo'] ?? '-'} (${isWide ? '2 Sütun' : '1 Sütun'})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.indigo,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ans,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: diffCol.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          diffText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: diffCol,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (displayOutcome.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      displayOutcome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 10, color: Colors.indigo.shade700),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ADIM 4: Önizleme, Kaydet ve Yakışıklı Yaprak Test PDF İndir ────────────
  Widget _buildStep4PreviewAndPdf(List<Map<String, dynamic>> allPoolDocs) {
    final Map<String, Map<String, dynamic>> byId = {};
    for (int i = 0; i < allPoolDocs.length; i++) {
      final q = allPoolDocs[i];
      final pk = (q['poolKey'] ?? q['docId'] ?? '$i').toString();
      byId[pk] = q;
      if (q['docId'] != null) {
        byId[q['docId'].toString()] = q;
      }
    }

    final List<Map<String, dynamic>> selectedQuestions = [];
    for (final id in _selectedQuestionIds) {
      final found = byId[id];
      if (found != null) selectedQuestions.add(found);
    }

    final List<int> selByLevel = List<int>.filled(5, 0);
    int wideCnt = 0;
    for (final q in selectedQuestions) {
      final d = (q['difficulty'] as num?)?.toDouble() ?? DifficultyScale.defaultScore;
      selByLevel[DifficultyScale.levelOf(d) - 1]++;
      if (q['isWide'] == true) wideCnt++;
    }
    final String selLevelSummary = [
      for (int i = 0; i < 5; i++)
        if (selByLevel[i] > 0) '${selByLevel[i]} ${DifficultyScale.labels[i]}',
    ].join(' • ');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Yakışıklı Yaprak Test Üst Başlık Önizleme Kartı
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFF4F46E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.indigo.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 36),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_targetAudienceSummary • ${_selectedBranch ?? 'Karma'} • ${_testType.label.toUpperCase()}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade100,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _titleCtrl.text.trim().isEmpty
                                ? 'İsimsiz Yaprak Test'
                                : _titleCtrl.text.trim(),
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${selectedQuestions.length} Soru ($selLevelSummary) • '
                            '${wideCnt} Geniş (2 Sütun) + ${selectedQuestions.length - wideCnt} Tek Sütun • '
                            'Ortadan Çizgili Profesyonel Yaprak Test Şablonu + Alt Cevap Anahtarı',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => _save(downloadPdfAfterSave: true, allPoolDocs: allPoolDocs),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text(
                        'Oluştur & PDF İndir',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1E3A8A),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Adım 4'te de PDF Üst/Alt Yazıları ve Soru Üstü Kazanım Ayarlarını Hızlı Düzenleme Kartı
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: _buildPdfHeaderFooterAndOutcomeSection(),
              ),
              const SizedBox(height: 20),

              // Cevap Anahtarı Şeridi Önizlemesi
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CEVAP ANAHTARI ÖNİZLEMESİ (${selectedQuestions.length} SORU)',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.indigo.shade900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (selectedQuestions.isEmpty)
                      const Text('Henüz soru seçilmedi.', style: TextStyle(color: Colors.grey))
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: List.generate(selectedQuestions.length, (idx) {
                          final ans = (selectedQuestions[idx]['correctAnswer'] ?? '-').toString();
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.indigo.shade200),
                            ),
                            child: Text(
                              '${idx + 1}. $ans',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade900,
                              ),
                            ),
                          );
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

  Widget _buildBottomNavBar(List<Map<String, dynamic>> allPoolDocs) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: _back,
              icon: Icon(_step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded, size: 16),
              label: Text(_step == 0 ? 'Vazgeç' : 'Önceki Adım'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const Spacer(),
            if (_step == 3) ...[
              OutlinedButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _save(downloadPdfAfterSave: false, allPoolDocs: allPoolDocs),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Sadece Kaydet', style: TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.indigo,
                  side: const BorderSide(color: Colors.indigo),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _save(downloadPdfAfterSave: true, allPoolDocs: allPoolDocs),
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: Text(
                  _isGeneratingPdf
                      ? 'PDF Hazırlanıyor...'
                      : (_isSaving ? 'Kaydediliyor...' : 'Oluştur & PDF Olarak İndir'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ] else
              FilledButton.icon(
                onPressed: _next,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(
                  _step == 2 ? 'Önizleme & PDF İndir Adımına Geç' : 'Sonraki Adım',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ),
      );

  Widget _buildSectionHeader(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B))),
          const SizedBox(height: 4),
          Text(subtitle,
              style: GoogleFonts.inter(
                  fontSize: 12.5, color: Colors.grey.shade600, height: 1.4)),
        ],
      );

  Widget _buildFieldLabel(IconData icon, String label, {bool required = false}) =>
      Row(
        children: [
          Icon(icon, size: 16, color: Colors.indigo),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: const Color(0xFF374151))),
          if (required) ...[
            const SizedBox(width: 4),
            Text(' *',
                style: GoogleFonts.inter(
                    color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ],
      );

  Widget _buildSelectionTile({
    required bool selected,
    required IconData icon,
    required Color color,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.06) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : Colors.grey.shade200,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: 0.15)
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon,
                    size: 20,
                    color: selected ? color : Colors.grey.shade500),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: selected
                                ? color
                                : const Color(0xFF374151))),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: Colors.grey.shade600)),
                    ],
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: color, size: 20),
            ],
          ),
        ),
      );
}
