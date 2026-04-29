import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  const QuestionPoolScreen({
    Key? key,
    required this.institutionId,
    this.schoolTypeId,
  }) : super(key: key);

  @override
  State<QuestionPoolScreen> createState() => _QuestionPoolScreenState();
}

class _QuestionPoolScreenState extends State<QuestionPoolScreen> {
  bool _showWizard = false;
  Map<String, dynamic>? _editingTest;

  Stream<QuerySnapshot> get _testsStream => FirebaseFirestore.instance
      .collection('institutions')
      .doc(widget.institutionId)
      .collection('question_pool_tests')
      .orderBy('createdAt', descending: true)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildBody(),
          if (_showWizard)
            _TestCreationWizard(
              institutionId: widget.institutionId,
              schoolTypeId: widget.schoolTypeId,
              editingData: _editingTest,
              onClose: () => setState(() {
                _showWizard = false;
                _editingTest = null;
              }),
              onSaved: () => setState(() {
                _showWizard = false;
                _editingTest = null;
              }),
            ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() => AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.indigo.shade900),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Soru Havuzu',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: Colors.indigo.shade900),
            ),
            Text(
              'Test & Ödev Yönetimi',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: FilledButton.icon(
              onPressed: () => setState(() {
                _editingTest = null;
                _showWizard = true;
              }),
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

  Widget _buildBody() {
    return StreamBuilder<QuerySnapshot>(
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
            color: Colors.indigo.withOpacity(0.35),
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
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '✦  Soru Havuzu Modülü',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.9),
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
                    color: Colors.white.withOpacity(0.85),
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
              color: Colors.white.withOpacity(0.12),
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
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
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
                  color: Colors.black.withOpacity(0.04),
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
                onPressed: () => setState(() {
                  _editingTest = null;
                  _showWizard = true;
                }),
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
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 4))
        ],
      ),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: type.color.withOpacity(0.1),
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
              PopupMenuButton<String>(
                onSelected: (val) async {
                  if (val == 'edit') {
                    setState(() {
                      _editingTest = {...data, 'docId': doc.id};
                      _showWizard = true;
                    });
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
          color: type.color.withOpacity(0.1),
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
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color.withOpacity(0.8)),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  color: color.withOpacity(0.9),
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

// ─── Multi-Step Wizard ────────────────────────────────────────────────────────

class _TestCreationWizard extends StatefulWidget {
  final String institutionId;
  final String? schoolTypeId;
  final Map<String, dynamic>? editingData;
  final VoidCallback onClose;
  final VoidCallback onSaved;

  const _TestCreationWizard({
    required this.institutionId,
    this.schoolTypeId,
    this.editingData,
    required this.onClose,
    required this.onSaved,
  });

  @override
  State<_TestCreationWizard> createState() => _TestCreationWizardState();
}

class _TestCreationWizardState extends State<_TestCreationWizard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  int _step = 0;
  bool _isSaving = false;

  // Step 1
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // Step 2
  TestType? _testType;
  QuestionSelectionMethod? _selectionMethod;
  SortingAlgorithm _sortingAlgorithm = SortingAlgorithm.fixed;

  // Step 3
  final _examLabelCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();

    final d = widget.editingData;
    if (d != null) {
      _titleCtrl.text = d['title'] ?? '';
      _descCtrl.text = d['description'] ?? '';
      _examLabelCtrl.text = d['examLabel'] ?? '';
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
      final sort = d['sortingAlgorithm'] ?? 'fixed';
      _sortingAlgorithm = sort == 'smart'
          ? SortingAlgorithm.smart
          : sort == 'none'
              ? SortingAlgorithm.none
              : SortingAlgorithm.fixed;
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _examLabelCtrl.dispose();
    super.dispose();
  }

  bool get _step1Valid => _titleCtrl.text.trim().isNotEmpty;
  bool get _step2Valid => _testType != null && _selectionMethod != null;

  void _next() {
    if (_step == 0 && !_step1Valid) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen başlık giriniz.')));
      return;
    }
    if (_step == 1 && !_step2Valid) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen test türü ve soru seçim yöntemini belirleyiniz.')));
      return;
    }
    if (_step < 2) setState(() => _step++);
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
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
        'institutionId': widget.institutionId,
        'schoolTypeId': widget.schoolTypeId,
        'questionCount': 0,
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

      if (mounted) widget.onSaved();
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kayıt hatası: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        color: Colors.black.withOpacity(0.45),
        child: Center(
          child: Material(
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Container(
              width: 680,
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88),
              decoration: const BoxDecoration(color: Colors.white),
              child: Column(
                children: [
                  _buildWizardHeader(),
                  _buildProgressBar(),
                  Expanded(child: SingleChildScrollView(child: _buildStepContent())),
                  _buildNavButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWizardHeader() => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
        ),
        child: Row(
          children: [
            Text(
              widget.editingData != null ? 'Testi Düzenle' : 'Yeni Test Oluştur',
              style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: const Color(0xFF1E293B)),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: widget.onClose,
            ),
          ],
        ),
      );

  Widget _buildProgressBar() {
    final steps = ['Temel Bilgiler', 'Test Türü ve Ayarlar', 'Tasarım ve Çıktı'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: List.generate(steps.length, (i) {
          final done = i < _step;
          final active = i == _step;
          final color = done || active ? Colors.indigo : Colors.grey.shade300;

          return Expanded(
            child: Row(
              children: [
                Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: done || active ? Colors.indigo : Colors.grey.shade200,
                        shape: BoxShape.circle,
                        boxShadow: active
                            ? [BoxShadow(
                                color: Colors.indigo.withOpacity(0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4))]
                            : null,
                      ),
                      child: Center(
                        child: done
                            ? const Icon(Icons.check_rounded,
                                color: Colors.white, size: 18)
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                    color: active
                                        ? Colors.white
                                        : Colors.grey.shade500,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 90,
                      child: Text(
                        steps[i],
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight:
                              active ? FontWeight.bold : FontWeight.normal,
                          color: active
                              ? Colors.indigo
                              : done
                                  ? Colors.indigo.shade300
                                  : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ],
                ),
                if (i < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin:
                          const EdgeInsets.only(bottom: 28, left: 4, right: 4),
                      decoration: BoxDecoration(
                        color: done ? Colors.indigo : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 1: Temel Bilgiler ──────────────────────────────────────────────────
  Widget _buildStep1() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Temel Bilgiler',
                'Hazırlayacağınız test için gerekli temel bilgileri girin. Başlık zorunlu alandır.'),
            const SizedBox(height: 24),
            _buildFieldLabel(Icons.title_rounded, 'Başlık', required: true),
            const SizedBox(height: 8),
            TextField(
              controller: _titleCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Örn: 6. Sınıf Deneme Sınavı – 1',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Colors.indigo, width: 2)),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 20),
            _buildFieldLabel(Icons.info_outline_rounded, 'Açıklama'),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'İsteğe bağlı bir açıklama ekleyebilirsiniz.',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Colors.indigo, width: 2)),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      );

  // ── Step 2: Test Türü ve Ayarlar ───────────────────────────────────────────
  Widget _buildStep2() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Test Türü ve Ayarlar',
                'Test türünü seçin ve test özelliklerini belirleyin.'),
            const SizedBox(height: 24),

            // Test Türü
            _buildFieldLabel(Icons.category_outlined, 'Test Türü', required: true),
            const SizedBox(height: 12),
            ...TestType.values.map((t) => _buildSelectionTile(
                  selected: _testType == t,
                  icon: t.icon,
                  color: t.color,
                  label: t.label,
                  onTap: () => setState(() => _testType = t),
                )),
            const SizedBox(height: 24),

            // Soru Seçim Yöntemi
            _buildFieldLabel(Icons.swap_horiz_rounded, 'Soru Seçim Stratejisi',
                required: true),
            const SizedBox(height: 12),
            ...QuestionSelectionMethod.values.map((m) => _buildSelectionTile(
                  selected: _selectionMethod == m,
                  icon: m.icon,
                  color: Colors.purple,
                  label: m.label,
                  onTap: () => setState(() => _selectionMethod = m),
                )),
            const SizedBox(height: 24),

            // Sıralama Algoritması
            _buildFieldLabel(Icons.sort_rounded, 'Sıralama Algoritması'),
            const SizedBox(height: 12),
            ...SortingAlgorithm.values.map((s) => _buildSelectionTile(
                  selected: _sortingAlgorithm == s,
                  icon: Icons.sort_rounded,
                  color: Colors.teal,
                  label: s.label,
                  subtitle: s.description,
                  onTap: () => setState(() => _sortingAlgorithm = s),
                )),
          ],
        ),
      );

  // ── Step 3: Tasarım ve Çıktı ───────────────────────────────────────────────
  Widget _buildStep3() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Tasarım ve Çıktı',
                'Test kitapçığının görünüm ve çıktı formatını belirleyin.'),
            const SizedBox(height: 24),
            _buildFieldLabel(
                Icons.label_outline_rounded, 'Test Başlıklarına Yazılacak Sınav Türü Adı'),
            const SizedBox(height: 8),
            TextField(
              controller: _examLabelCtrl,
              decoration: InputDecoration(
                hintText: 'Örnek: LGS, TYT, 11. SINIF TARAMA',
                helperText: 'Testlerin üzerine yazılacak sınav türü adını belirtin. En fazla 18 karakter.',
                helperMaxLines: 2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Colors.indigo, width: 2)),
                contentPadding: const EdgeInsets.all(16),
              ),
              maxLength: 18,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_rounded, color: Colors.indigo.shade400, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tüm gerekli ayarları yaptınız. Şimdi kaydedin ve soru seçimi adımı ile devam edin.',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.indigo.shade700,
                          height: 1.4),
                    ),
                  ),
                ],
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
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B))),
          const SizedBox(height: 6),
          Text(subtitle,
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey.shade500, height: 1.45)),
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
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.06) : Colors.grey.shade50,
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
                      ? color.withOpacity(0.15)
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon,
                    size: 20,
                    color: selected ? color : Colors.grey.shade500),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: selected
                                ? color
                                : const Color(0xFF374151))),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade500)),
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

  Widget _buildNavButtons() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade100)),
        ),
        child: Row(
          children: [
            if (_step > 0)
              TextButton.icon(
                onPressed: _back,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Geri'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
              ),
            const Spacer(),
            TextButton(
              onPressed: widget.onClose,
              child: const Text('İptal'),
              style: TextButton.styleFrom(foregroundColor: Colors.grey),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _isSaving
                  ? null
                  : (_step == 2 ? _save : _next),
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(
                      _step == 2
                          ? Icons.save_rounded
                          : Icons.arrow_forward_rounded,
                      size: 18),
              label: Text(
                _isSaving
                    ? 'Kaydediliyor...'
                    : (_step == 2 ? 'Kaydet' : 'İleri'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.indigo,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
}
