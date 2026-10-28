import 'dart:typed_data';

import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../odak64/models/odak_models.dart';
import '../odak64/widgets/odak_export_bar.dart';
import 'school_timetable_loader.dart';
import 'student_performance_service.dart';

/// Öğrenci bazlı Performans Özeti: şubelerden öğrenci(ler) seçilir, her biri
/// için kişisel rapor + çalışma planı PDF'i üretilir (indir / yazdır / paylaş).
class StudentReportsScreen extends StatefulWidget {
  final List<OdakClassGroup> groups;
  final List<String> subjects;
  final Map<String, Map<String, List<String>>> outcomes;
  final int weeks;
  final String examName;
  final String? schoolName;

  /// true ise çalışma planı, hedefler ve plan sonrası değerlendirme üretilir.
  final bool withPlan;

  /// Verilirse şubelerin okul ders programı yüklenir; tekrar oturumları
  /// öğrencinin o gün okulda gördüğü dersten seçilir.
  final String? institutionId;
  final String? schoolTypeId;

  const StudentReportsScreen({
    super.key,
    required this.groups,
    required this.subjects,
    required this.outcomes,
    required this.weeks,
    required this.examName,
    this.schoolName,
    this.withPlan = true,
    this.institutionId,
    this.schoolTypeId,
  });

  @override
  State<StudentReportsScreen> createState() => _StudentReportsScreenState();
}

class _StudentReportsScreenState extends State<StudentReportsScreen> {
  final Set<String> _selected = {};
  String _query = '';

  /// Şube anahtarı -> (gün -> okul dersleri).
  Map<String, Map<String, List<String>>> _timetables = const {};

  /// PDF üretimi bunu bekler: program yüklenmeden plan üretilirse aynı sınav
  /// için farklı plan çıkabilirdi.
  late final Future<void> _ttReady;

  @override
  void initState() {
    super.initState();
    _ttReady = _loadTimetables();
  }

  Future<void> _loadTimetables() async {
    final inst = widget.institutionId, st = widget.schoolTypeId;
    if (!widget.withPlan || inst == null || st == null) return;
    final t = await SchoolTimetableLoader.load(
      institutionId: inst,
      schoolTypeId: st,
      branchNames: widget.groups.map((g) => g.id),
    );
    if (mounted) {
      setState(() => _timetables = t);
    } else {
      _timetables = t;
    }
  }

  Map<String, List<String>>? _daysFor(OdakClassGroup g) =>
      _timetables[SchoolTimetableLoader.key(g.id)];

  double _rate(OdakRankedStudent rs) {
    if (widget.subjects.isEmpty) return 0;
    var sum = 0.0;
    for (final s in widget.subjects) {
      sum += rs.result.subjects[s]?.successRate ?? 0.0;
    }
    return sum / widget.subjects.length;
  }

  List<StudentReport> _selectedReports() {
    final list = <StudentReport>[];
    for (final g in widget.groups) {
      final names = g.students.where((s) => _selected.contains(s.student.id)).toList()
        ..sort((a, b) => a.student.name.compareTo(b.student.name));
      for (final rs in names) {
        list.add(StudentPerfService.analyze(
          branchGroup: g,
          result: rs.result,
          subjects: widget.subjects,
          outcomes: widget.outcomes,
          weeks: widget.weeks,
          withPlan: widget.withPlan,
          schoolDays: _daysFor(g),
        ));
      }
    }
    return list;
  }

  Future<List<int>> _pdf(List<StudentReport> reports) =>
      StudentPerfService.buildPdf(
        reports: reports,
        examName: widget.examName,
        schoolName: widget.schoolName,
        weeks: widget.weeks,
        withPlan: widget.withPlan,
      );

  Future<void> _single(OdakClassGroup g, OdakRankedStudent rs) async {
    try {
      await _ttReady;
      final report = StudentPerfService.analyze(
        branchGroup: g,
        result: rs.result,
        subjects: widget.subjects,
        outcomes: widget.outcomes,
        weeks: widget.weeks,
        withPlan: widget.withPlan,
        schoolDays: _daysFor(g),
      );
      final bytes = await StudentPerfService.buildPdf(
        reports: [report],
        examName: widget.examName,
        schoolName: widget.schoolName,
        weeks: widget.weeks,
        withPlan: widget.withPlan,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Performans_${rs.student.name.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF hazırlanamadı: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    final q = _query.trim().toLowerCase();
    return Theme(
      data: Theme.of(context).copyWith(colorScheme: scheme),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FE),
        appBar: const EduknAppBar(title: 'Öğrenci Performans Özeti'),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(),
                          const SizedBox(height: 14),
                          TextField(
                            onChanged: (v) => setState(() => _query = v),
                            decoration: InputDecoration(
                              hintText: 'Öğrenci ara...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final g in widget.groups) _branch(g, q),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.indigo.shade600, Colors.deepPurple.shade500],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Öğrenci Performans Raporları',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.examName} • ${widget.groups.length} şube\n'
              'Dersler: ${widget.subjects.join(', ')}\n'
              '${widget.withPlan ? 'Seçtiğiniz her öğrenci için ders/kazanım analizi ve '
                  '${widget.weeks} haftalık kişisel çalışma planı hazırlanır.' : 'Seçtiğiniz her öğrenci için ders/kazanım analizi hazırlanır '
                  '(çalışma planı oluşturulmaz).'}',
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ],
        ),
      );

  Widget _branch(OdakClassGroup g, String q) {
    final visible = g.students
        .where((s) => q.isEmpty || s.student.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.student.name.compareTo(b.student.name));
    if (visible.isEmpty) return const SizedBox.shrink();
    final ids = visible.map((s) => s.student.id).toList();
    final selCount = ids.where(_selected.contains).length;
    final bool? all = selCount == 0
        ? false
        : (selCount == ids.length ? true : null);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: ExpansionTile(
        key: PageStorageKey('stu-branch-${g.id}-${q.isNotEmpty}'),
        initiallyExpanded: widget.groups.length == 1 || q.isNotEmpty,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Checkbox(
          tristate: true,
          value: all,
          onChanged: (v) => setState(() {
            if (all == true) {
              _selected.removeAll(ids);
            } else {
              _selected.addAll(ids);
            }
          }),
        ),
        title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${g.students.length} öğrenci • $selCount seçili'),
        children: [
          for (final rs in visible)
            CheckboxListTile(
              dense: true,
              value: _selected.contains(rs.student.id),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(rs.student.id);
                } else {
                  _selected.remove(rs.student.id);
                }
              }),
              title: Text(rs.student.name),
              subtitle: Text('Başarı: %${(_rate(rs) * 100).round()}'),
              secondary: IconButton(
                tooltip: 'Bu öğrencinin PDF\'ini indir',
                icon: const Icon(Icons.picture_as_pdf_rounded),
                onPressed: () => _single(g, rs),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final n = _selected.length;
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                n == 0 ? 'Öğrenci seçin' : '$n öğrenci seçili',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (n > 0)
                OdakExportBar(
                  key: ValueKey('stu-export-$n'),
                  fileName: n == 1
                      ? 'Performans_Ogrenci.pdf'
                      : 'Performans_Ogrenciler.pdf',
                  title: 'Öğrenci Performans Özeti',
                  shareText:
                      'Öğrenci performans özeti (${widget.examName}) ektedir.',
                  buildPdf: () async {
                    await _ttReady;
                    final bytes = await _pdf(_selectedReports());
                    return Uint8List.fromList(bytes);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
