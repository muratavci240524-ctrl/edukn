import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:flutter/material.dart';
import 'student_performance_service.dart';
import 'student_reports_screen.dart';

import '../odak64/providers/odak_controller.dart';
import '../odak64/screens/odak64_classes_screen.dart';
import '../odak64/services/odak_engine.dart';
import 'package:edukn/services/course_track_resolver.dart';
import '../odak64/models/odak_models.dart';
import '../odak64/repository/odak_repository.dart' show OdakExamInfo;

/// Performans Özeti: ODAK-64 mantığıyla sınav analizi, ancak YENİ SINIF
/// OLUŞTURMADAN. Öğrenciler sınavdaki kendi şubelerinde kalır; her şube için
/// ders bazlı (ders öğretmenine verilecek) raporlar üretilir.
class PerformanceSummaryScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? schoolTypeName;

  const PerformanceSummaryScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    this.schoolTypeName,
  });

  @override
  State<PerformanceSummaryScreen> createState() =>
      _PerformanceSummaryScreenState();
}

class _PerformanceSummaryScreenState extends State<PerformanceSummaryScreen> {
  late final OdakController _c = OdakController(widget.institutionId);
  final Set<String> _selected = {};
  int _weeks = 4;

  /// Seçili sınıf seviyeleri (anahtar: "8" gibi) ve seçili sınavlar (birleşik değerlendirme).
  final Set<String> _grades = {};
  List<String> _examIds = [];

  /// false: Şube raporları, true: Öğrenci raporları.
  bool _studentMode = false;

  /// Öğrenci raporunda çalışma planı (+ hedefler + plan sonrası) üretilsin mi?
  bool _withPlan = false;

  /// Şube raporunda haftalık aksiyon planı üretilsin mi?
  bool _withActionPlan = false;

  @override
  void initState() {
    super.initState();
    _c.init();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Sınav listesindeki ders sırası: LGS sırasına göre.
  List<String> get _orderedSubjects =>
      StudentPerfService.sortSubjects(_c.subjects);

  /// Sınav sınıf seviyesi anahtarı: "8. Sınıf" -> "8"; boşsa "".
  static String _gradeKey(String raw) {
    final m = RegExp(r'(\d+)').firstMatch(raw);
    return m != null ? m.group(1)! : raw.trim();
  }

  static String _gradeLabel(String key) {
    if (key.isEmpty) return 'Belirtilmemiş';
    return RegExp(r'^\d+$').hasMatch(key) ? '$key. Sınıf' : key;
  }

  List<String> get _gradeKeys {
    final keys = _c.exams.map((e) => _gradeKey(e.classLevel)).toSet().toList();
    keys.sort((a, b) {
      final na = int.tryParse(a), nb = int.tryParse(b);
      if (na != null && nb != null) return na.compareTo(nb);
      if (na != null) return -1;
      if (nb != null) return 1;
      return a.compareTo(b);
    });
    return keys;
  }

  /// Hiç sınava sınıf seviyesi girilmemişse seviye adımı atlanır.
  bool get _hasGrades => _gradeKeys.any((k) => k.isNotEmpty);

  List<OdakExamInfo> get _visibleExams => _hasGrades
      ? _c.exams
          .where((e) => _grades.contains(_gradeKey(e.classLevel)))
          .toList()
      : _c.exams;

  void _toggleGrade(String key) {
    setState(() {
      if (!_grades.add(key)) _grades.remove(key);
    });
    // Seviyesi dışında kalan sınavlar seçimden çıkarılır.
    final visible = _visibleExams.map((e) => e.id).toSet();
    final kept = _examIds.where(visible.contains).toList();
    if (kept.length != _examIds.length) _applyExams(kept);
  }

  Future<void> _applyExams(List<String> ids) async {
    _examIds = ids;
    if (mounted) setState(() {});
    await _c.selectExams(ids);
    _selected
      ..clear()
      ..addAll(_c.subjects);
    if (mounted) setState(() {});
  }

  String get _examName {
    final names = [
      for (final id in _examIds)
        ..._c.exams.where((e) => e.id == id).map((e) => e.name),
    ];
    if (names.length <= 1) return names.isEmpty ? '' : names.first;
    return '${names.length} sınav birleşik değerlendirme (${names.join(' + ')})';
  }

  /// Seçili derslere eşit ağırlık verir (toplam 100). Sıralama sadece
  /// şube içi puan sıralaması için kullanılır.
  Map<String, int> _equalWeights(List<String> subjects) {
    final base = 100 ~/ subjects.length;
    var rest = 100 - base * subjects.length;
    final m = <String, int>{};
    for (final s in subjects) {
      m[s] = base + (rest > 0 ? 1 : 0);
      if (rest > 0) rest--;
    }
    return m;
  }

  Future<void> _generate() async {
    final data = _c.examData;
    if (data == null || _selected.isEmpty) return;
    final subjects = _orderedSubjects.where(_selected.contains).toList();
    final weights = _equalWeights(subjects);
    List<OdakClassGroup> groups;
    if (_studentMode) {
      groups = OdakEngine.groupByBranch(data.results, weights);
    } else {
      // Kurs Listesi'ndeki kurlar: kurlu derslerde şube yerine kur kullanılır.
      final tracks = await CourseTrackResolver.load(
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
      );
      if (!mounted) return;
      groups = tracks.isEmpty
          ? OdakEngine.groupByBranch(data.results, weights)
          : OdakEngine.groupByBranchWithTracks(
              data.results,
              weights,
              isTrackSubject: tracks.isTrackSubject,
              slotLabelFor: (sid, subject) => tracks.slotFor(sid, subject)?.label,
            );
    }
    final analyzer = OdakAnalyzer(
      groups: groups,
      weights: weights,
      outcomes: data.outcomes,
      weeks: _weeks,
      hoursPerWeek: 0,
      showActionPlan: _withActionPlan,
    );
    final examName = _examName;
    if (_studentMode) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StudentReportsScreen(
            groups: groups,
            subjects: subjects,
            outcomes: data.outcomes,
            weeks: _weeks,
            examName: examName,
            schoolName: widget.schoolTypeName,
            withPlan: _withPlan,
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Odak64ClassesScreen(
          groups: groups,
          analyzer: analyzer,
          subjects: subjects,
          examName: examName,
          schoolTypeName: widget.schoolTypeName,
          title: 'Performans Özeti • Şubeler',
          heading: 'Şube Performans Raporları',
          brand: 'Performans Özeti',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FE),
        appBar: EduknAppBar(
          title: 'Performans Özeti',
          subtitle: widget.schoolTypeName,
        ),
        body: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    const SizedBox(height: 16),
                    if (_hasGrades) ...[
                      _step(1, 'Sınıf Seviyesi', _gradePicker()),
                      const SizedBox(height: 16),
                    ],
                    _step(_hasGrades ? 2 : 1, 'Sınav Seçimi', _examPicker()),
                    if (_c.examData != null) ...[
                      const SizedBox(height: 16),
                      _step(_hasGrades ? 3 : 2, 'Dersler', _subjectsPicker()),
                      const SizedBox(height: 16),
                      _step(
                        _hasGrades ? 4 : 3,
                        'Rapor Türü, Şubeler ve Plan Süresi',
                        _branchesAndWeeks(),
                      ),
                      const SizedBox(height: 16),
                      _actionBar(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Alttaki ana eylem: özet bilgi + gradient büyük buton.
  Widget _actionBar() {
    final enabled = _selected.isNotEmpty;
    final examCount = _examIds.length;
    final plan = _studentMode ? _withPlan : _withActionPlan;
    final summary = [
      '$examCount sınav${examCount > 1 ? ' (birleşik)' : ''}',
      '${_selected.length} ders',
      _studentMode ? 'Öğrenci raporu' : 'Şube raporu',
      plan ? '$_weeks haftalık plan' : 'plansız',
    ].join('  •  ');
    final fg = enabled ? Colors.white : Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final btn = AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: enabled
                ? LinearGradient(colors: [
                    Colors.indigo.shade600,
                    Colors.deepPurple.shade500,
                  ])
                : null,
            color: enabled ? null : Colors.grey.shade300,
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: Colors.indigo.withValues(alpha: 0.32),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: enabled ? _generate : null,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.insights_rounded, color: fg),
                    const SizedBox(width: 10),
                    Text(
                      _studentMode
                          ? 'Öğrenci Seçimine Geç'
                          : 'Şube Raporlarını Oluştur',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15.5,
                        color: fg,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.arrow_forward_rounded, color: fg),
                  ],
                ),
              ),
            ),
          ),
        );
        final info = Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.task_alt_rounded, color: Colors.indigo.shade600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rapor hazır',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    enabled ? summary : 'En az bir ders seçin',
                    style:
                        TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ],
        );
        if (c.maxWidth >= 640) {
          return Row(
              children: [Expanded(child: info), const SizedBox(width: 12), btn]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [info, const SizedBox(height: 12), btn],
        );
      }),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.indigo.shade600, Colors.deepPurple.shade500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_graph_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Performans Özeti',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Sınıf seviyesi ve bir veya birden fazla sınav seçin; öğrenciler kendi şubelerinde '
                    'kalarak her şube ve her ders için ayrıntılı performans raporunu alın.',
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _step(int n, String title, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primary,
                  child: Text(
                    '$n',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _examPicker() {
    if (_c.loadingExams) return const Center(child: CircularProgressIndicator());
    if (_c.exams.isEmpty) {
      return Text(
        _c.error ?? 'Bu dönemde sonuçları yüklenmiş deneme sınavı bulunamadı.',
        style: TextStyle(color: Colors.grey.shade700),
      );
    }
    if (_hasGrades && _grades.isEmpty) {
      return Text(
        'Önce yukarıdan bir veya birden fazla sınıf seviyesi seçin.',
        style: TextStyle(color: Colors.grey.shade700),
      );
    }
    final visible = _visibleExams;
    if (visible.isEmpty) {
      return Text(
        'Seçilen sınıf seviyesi için sonuçları yüklenmiş deneme sınavı yok.',
        style: TextStyle(color: Colors.grey.shade700),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final selectedInfos = [
      for (final id in _examIds) ..._c.exams.where((e) => e.id == id),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _c.loadingExam ? null : () => _pickExams(visible),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selectedInfos.isEmpty
                    ? scheme.outlineVariant
                    : scheme.primary,
                width: selectedInfos.isEmpty ? 1 : 1.6,
              ),
              gradient: LinearGradient(
                colors: [
                  scheme.primaryContainer.withValues(alpha: 0.35),
                  Colors.white,
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.fact_check_rounded, color: scheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: selectedInfos.isEmpty
                      ? Text(
                          'Bir veya birden fazla deneme sınavı seçin (${visible.length} sınav)',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedInfos.length == 1
                                  ? 'Tek sınav seçildi'
                                  : '${selectedInfos.length} sınav seçildi • Birleşik değerlendirme',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final e in selectedInfos)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: scheme.primary,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      e.name,
                                      style: TextStyle(
                                        color: scheme.onPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey.shade700),
              ],
            ),
          ),
        ),
        if (_c.loadingExam)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_c.examData != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${_c.studentCount} öğrenci • ${_c.subjects.length} ders'
              '${_examIds.length > 1 ? ' • sonuçlar öğrenci bazında birleştirildi' : ''}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        if (_c.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_c.error!, style: TextStyle(color: Colors.red.shade700)),
          ),
      ],
    );
  }

  /// Sihirbaz: sınav listesini (arama + onay kutuları) açar; çoklu seçim.
  Future<void> _pickExams(List<OdakExamInfo> exams) async {
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        final sel = <String>{..._examIds};
        var query = '';
        return StatefulBuilder(builder: (ctx, setD) {
          final scheme = Theme.of(ctx).colorScheme;
          final shown = exams
              .where((e) => e.name.toLowerCase().contains(query.toLowerCase()))
              .toList();
          String fmt(DateTime d) =>
              '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.fact_check_rounded, color: scheme.primary),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Sınavları Seçin',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setD(() {
                            if (sel.length == exams.length) {
                              sel.clear();
                            } else {
                              sel.addAll(exams.map((e) => e.id));
                            }
                          }),
                          child: Text(sel.length == exams.length
                              ? 'Temizle'
                              : 'Tümünü seç'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Birden fazla sınav seçerseniz sonuçlar öğrenci bazında birleştirilir.',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (v) => setD(() => query = v),
                      decoration: InputDecoration(
                        hintText: 'Sınav ara...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final e in shown)
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: sel.contains(e.id)
                                    ? scheme.primaryContainer
                                        .withValues(alpha: 0.5)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: sel.contains(e.id)
                                      ? scheme.primary
                                      : scheme.outlineVariant,
                                ),
                              ),
                              child: CheckboxListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                value: sel.contains(e.id),
                                onChanged: (v) => setD(() {
                                  if (v == true) {
                                    sel.add(e.id);
                                  } else {
                                    sel.remove(e.id);
                                  }
                                }),
                                title: Text(e.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text([
                                  if (e.classLevel.isNotEmpty)
                                    _gradeLabel(_gradeKey(e.classLevel)),
                                  if (e.date != null) fmt(e.date!),
                                ].join('  •  ')),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Vazgeç'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(
                            ctx,
                            // Seçim sırası: liste (tarih) sırası.
                            exams
                                .where((e) => sel.contains(e.id))
                                .map((e) => e.id)
                                .toList(),
                          ),
                          icon: const Icon(Icons.check_rounded),
                          label: Text('Uygula (${sel.length})'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
    if (picked != null) await _applyExams(picked);
  }

  /// Sınıf seviyesi butonları (bir veya birden fazla seçilebilir).
  Widget _gradePicker() {
    if (_c.loadingExams) return const Center(child: CircularProgressIndicator());
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bir veya birden fazla sınıf seviyesi seçin; sonraki adımda yalnızca bu '
          'seviyelere ait sınavlar listelenir.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final k in _gradeKeys)
              Builder(builder: (_) {
                final on = _grades.contains(k);
                final count = _c.exams
                    .where((e) => _gradeKey(e.classLevel) == k)
                    .length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: on
                        ? LinearGradient(colors: [
                            Colors.indigo.shade600,
                            Colors.deepPurple.shade500,
                          ])
                        : null,
                    color: on ? null : Colors.white,
                    border: Border.all(
                      color: on ? Colors.transparent : scheme.outlineVariant,
                    ),
                    boxShadow: on
                        ? [
                            BoxShadow(
                              color: Colors.indigo.withValues(alpha: 0.28),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _toggleGrade(k),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              on
                                  ? Icons.check_circle_rounded
                                  : Icons.school_outlined,
                              size: 20,
                              color: on ? Colors.white : scheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _gradeLabel(k),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: on ? Colors.white : Colors.black87,
                                  ),
                                ),
                                Text(
                                  '$count sınav',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: on
                                        ? Colors.white70
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ],
    );
  }

  /// Plan/aksiyon planı seçimi: açık/kapalı kart (Switch).
  Widget _planToggle() {
    final scheme = Theme.of(context).colorScheme;
    final on = _studentMode ? _withPlan : _withActionPlan;
    final title = _studentMode
        ? 'Çalışma planı oluşturulsun'
        : 'Aksiyon planı oluşturulsun';
    final desc = _studentMode
        ? (on
            ? 'Raporlara sınav sonucuna göre değerlendirme, haftalık planlar, '
                'plan sonrası değerlendirme ve hedefler eklenir.'
            : 'Raporlar yalnızca sınav analizini içerir; plan, hedefler ve plan '
                'sonrası bölümleri üretilmez.')
        : (on
            ? 'Her ders raporuna öğretmen için haftalık aksiyon planı eklenir.'
            : 'Ders raporları haftalık aksiyon planı olmadan, yalnızca analiz '
                've değerlendirme olarak hazırlanır.');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        gradient: on
            ? LinearGradient(colors: [
                scheme.primaryContainer.withValues(alpha: 0.65),
                Colors.white,
              ])
            : null,
        color: on ? null : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: on ? scheme.primary : scheme.outlineVariant,
          width: on ? 1.6 : 1,
        ),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: on,
            onChanged: (v) => setState(() {
              if (_studentMode) {
                _withPlan = v;
              } else {
                _withActionPlan = v;
              }
            }),
            contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            secondary: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: on ? 0.16 : 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _studentMode
                    ? Icons.event_note_rounded
                    : Icons.assignment_turned_in_rounded,
                color: on ? scheme.primary : Colors.grey.shade600,
              ),
            ),
            title:
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(desc),
          ),
          if (on)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  Icon(Icons.date_range_rounded,
                      size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    _studentMode ? 'Plan süresi' : 'Aksiyon planı süresi',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  _stepper(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Hafta sayısı: − / + adımlayıcı.
  Widget _stepper() {
    final scheme = Theme.of(context).colorScheme;
    Widget btn(IconData i, VoidCallback? onTap) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: onTap == null ? 0.05 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(i,
                size: 18,
                color: onTap == null ? Colors.grey : scheme.primary),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove_rounded,
            _weeks > 1 ? () => setState(() => _weeks--) : null),
        Container(
          width: 84,
          alignment: Alignment.center,
          child: Text(
            '$_weeks hafta',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        btn(Icons.add_rounded,
            _weeks < 52 ? () => setState(() => _weeks++) : null),
      ],
    );
  }

  static const _subjectColors = <Color>[
    Color(0xFFE53935), // Türkçe
    Color(0xFF8E24AA), // Sosyal
    Color(0xFF00897B), // Din
    Color(0xFF1E88E5), // İngilizce
    Color(0xFFF4511E), // Matematik
    Color(0xFF43A047), // Fen
  ];

  static const _subjectIcons = <IconData>[
    Icons.menu_book_rounded,
    Icons.public_rounded,
    Icons.auto_stories_rounded,
    Icons.translate_rounded,
    Icons.calculate_rounded,
    Icons.science_rounded,
  ];

  Widget _subjectsPicker() {
    final all = _orderedSubjects;
    final scheme = Theme.of(context).colorScheme;
    final allOn = _selected.length == all.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Rapor hazırlanacak dersleri seçin (her ders ayrı sayfadan başlar).',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                if (allOn) {
                  _selected.clear();
                } else {
                  _selected
                    ..clear()
                    ..addAll(all);
                }
              }),
              icon: Icon(
                  allOn ? Icons.deselect_rounded : Icons.select_all_rounded,
                  size: 18),
              label: Text(allOn ? 'Hiçbiri' : 'Tümünü seç'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: all.isEmpty ? 0.0 : _selected.length / all.length,
            minHeight: 6,
            backgroundColor: scheme.primary.withValues(alpha: 0.1),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_selected.length} / ${all.length} ders seçili',
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: scheme.primary),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, cons) {
          final cols = cons.maxWidth >= 640 ? 3 : 2;
          final cardW = (cons.maxWidth - 12 * (cols - 1)) / cols;
          return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final s in all)
              Builder(builder: (_) {
                final on = _selected.contains(s);
                final rank = StudentPerfService.subjectRank(s);
                final color = rank < _subjectColors.length
                    ? _subjectColors[rank]
                    : scheme.primary;
                final icon = rank < _subjectIcons.length
                    ? _subjectIcons[rank]
                    : Icons.book_rounded;
                return SizedBox(
                  width: cardW,
                  height: cols == 2 ? 108 : 120,
                  child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: on
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [color, color.withValues(alpha: 0.72)],
                          )
                        : null,
                    color: on ? null : Colors.white,
                    border: Border.all(
                      color: on ? Colors.transparent : scheme.outlineVariant,
                    ),
                    boxShadow: on
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.32),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => setState(() {
                        if (!_selected.add(s)) _selected.remove(s);
                      }),
                      child: Padding(
                        padding: EdgeInsets.all(cols == 2 ? 10 : 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: EdgeInsets.all(cols == 2 ? 6 : 8),
                                  decoration: BoxDecoration(
                                    color: on
                                        ? Colors.white.withValues(alpha: 0.22)
                                        : color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(icon,
                                      size: cols == 2 ? 20 : 22,
                                      color: on ? Colors.white : color),
                                ),
                                Icon(
                                  on
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color:
                                      on ? Colors.white : Colors.grey.shade400,
                                ),
                              ],
                            ),
                            SizedBox(height: cols == 2 ? 6 : 12),
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Text(
                              s,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: cols == 2 ? 13 : 14.5,
                                height: 1.15,
                                color: on ? Colors.white : Colors.black87,
                              ),
                            ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ),
                );
              }),
          ],
        );
        }),
      ],
    );
  }

  /// Büyük seçim kartı (rapor türü).
  Widget _typeCard({
    required bool selected,
    required IconData icon,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: selected
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.indigo.shade600, Colors.deepPurple.shade500],
              )
            : null,
        color: selected ? null : Colors.white,
        border: Border.all(
            color: selected ? Colors.transparent : scheme.outlineVariant),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Colors.indigo.withValues(alpha: 0.3),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.2)
                        : scheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon,
                      size: 26,
                      color: selected ? Colors.white : scheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: selected ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        desc,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color:
                              selected ? Colors.white70 : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? Colors.white : Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _branchesAndWeeks() {
    final data = _c.examData!;
    final scheme = Theme.of(context).colorScheme;
    final counts = <String, int>{};
    for (final r in data.results) {
      final k = OdakEngine.branchLabel(r.student);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final labels = counts.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 640;
          final cards = [
            _typeCard(
              selected: !_studentMode,
              icon: Icons.groups_rounded,
              title: 'Şube Raporu',
              desc: 'Her şube ve ders için ders öğretmenine verilecek '
                  'ayrıntılı analiz raporu.',
              onTap: () => setState(() => _studentMode = false),
            ),
            _typeCard(
              selected: _studentMode,
              icon: Icons.person_rounded,
              title: 'Öğrenci Raporu',
              desc: 'Seçtiğiniz her öğrenci için kişisel ders ve kazanım '
                  'analizi (isteğe bağlı çalışma planı).',
              onTap: () => setState(() => _studentMode = true),
            ),
          ];
          return wide
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 12),
                      Expanded(child: cards[1]),
                    ],
                  ),
                )
              : Column(children: [
                  cards[0],
                  const SizedBox(height: 10),
                  cards[1],
                ]);
        }),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.hub_rounded, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _studentMode
                          ? 'Sonraki adımda şubelerden öğrenci(ler) seçersiniz'
                          : 'Öğrenciler yeni sınıflara bölünmez; kendi şubelerinde raporlanır',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${labels.length} şube • ${data.results.length} öğrenci',
                    style: TextStyle(
                        fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final l in labels)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${counts[l]}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _planToggle(),
      ],
    );
  }
}
