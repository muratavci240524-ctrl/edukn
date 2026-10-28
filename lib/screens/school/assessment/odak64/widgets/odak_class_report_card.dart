import 'package:flutter/material.dart';

import '../models/odak_models.dart';
import '../services/odak_engine.dart';
import '../services/odak_pdf_service.dart';
import '../services/odak_excel_service.dart';
import 'odak_export_bar.dart';

/// Genişletilebilir sınıf kartı: sınıf listesi, riskli öğrenciler ve
/// seçilen her ders için ayrı rapor (zayıf kazanım, boş, çeldirici, plan).
class OdakClassReportCard extends StatelessWidget {
  final OdakClassGroup group;
  final OdakAnalyzer analyzer;
  final List<String> subjects;
  final String examName;
  final String? schoolName;
  final String brand;

  const OdakClassReportCard({
    super.key,
    required this.group,
    required this.analyzer,
    required this.subjects,
    this.examName = '',
    this.schoolName,
    this.brand = 'ODAK-64',
  });

  @override
  Widget build(BuildContext context) {
    final risky = analyzer.getStudentWarnings(group.id);
    final riskyIds = risky.map((r) => r.ranked.student.id).toSet();
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              group.id,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          title: Text(
            group.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          subtitle: Text(
            '${group.students.length} öğrenci • Ortalama ${group.avgScore.toStringAsFixed(1)}'
            '${risky.isNotEmpty ? ' • ${risky.length} riskli' : ''}'
            ' • ${group.filterSubjects(subjects).length + OdakClassGroup.linkedTracks(group, analyzer.groups).fold<int>(0, (n, t) => n + t.filterSubjects(subjects).length)} ders raporu',
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OdakExportBar(
                  fileName: '${OdakPdfService.fileBase(brand)}_${group.name.replaceAll(' ', '_')}.pdf',
                  title: '$brand ${group.name} Raporu',
                  shareText: '$brand ${group.name} raporu ($examName) ektedir.',
                  buildDoorList: brand != 'ODAK-64' ? null : () => OdakPdfService.buildDoorList(
                    groups: [group],
                    examName: examName,
                    schoolName: schoolName,
                    brand: brand,
                  ),
                  doorFileName: 'Kapi_Listesi_${group.name.replaceAll(' ', '_')}.pdf',
                  doorExcel: () => OdakExcelService.saveDoorList(
                    groups: [group],
                    examName: examName,
                    schoolName: schoolName,
                    fileName: 'Kapi_Listesi_${group.name.replaceAll(' ', '_')}',
                  ),
                  buildPdf: () => OdakPdfService.build(
                    groups: [group],
                    analyzer: analyzer,
                    subjects: subjects,
                    examName: examName,
                    schoolName: schoolName,
                    brand: brand,
                  ),
                ),
              ),
            ),
            _Section(
              icon: Icons.groups_rounded,
              title: 'Sınıf Listesi',
              child: Column(
                children: [
                  for (final s in group.students)
                    _StudentRow(ranked: s, risky: riskyIds.contains(s.student.id)),
                ],
              ),
            ),
            _Section(
              icon: Icons.menu_book_rounded,
              title: 'Ders Raporları',
              child: Column(
                children: [
                  for (final s in group.filterSubjects(subjects))
                    _SubjectReport(
                      key: ValueKey('odak-${group.id}-$s'),
                      classId: group.id,
                      subject: s,
                      analyzer: analyzer,
                    ),
                  for (final lk in OdakClassGroup.linkedTracks(group, analyzer.groups))
                    for (final s in lk.filterSubjects(subjects)) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 2),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.layers_outlined, size: 16),
                            label: Text('$s • Kur ${lk.shortLabel} (${lk.students.length} öğrenci)'),
                          ),
                        ),
                      ),
                      _SubjectReport(
                        key: ValueKey('odak-${lk.id}-$s'),
                        classId: lk.id,
                        subject: s,
                        analyzer: analyzer,
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
}

class _SubjectReport extends StatelessWidget {
  final String classId;
  final String subject;
  final OdakAnalyzer analyzer;

  const _SubjectReport({
    super.key,
    required this.classId,
    required this.subject,
    required this.analyzer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weak = analyzer.getWeakOutcomes(classId, subject: subject);
    final empties = analyzer.getMostEmptyQuestions(classId, subject: subject);
    final distractors = analyzer.getMostFallenDistractor(classId, subject: subject);
    final risky = analyzer.getSubjectWarnings(classId, subject);
    final plan = analyzer.buildSubjectPlan(classId, subject);
    final rate = analyzer.subjectClassRate(classId, subject);
    final totals = analyzer.subjectTotals(classId, subject);
    final hours = analyzer.lessonHours[subject] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Icon(Icons.auto_stories_rounded, color: scheme.primary),
          title: Text(subject, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            'Sınıf başarısı %${(rate * 100).round()} • haftada $hours saat'
            '${risky.isNotEmpty ? ' • ${risky.length} riskli' : ''}',
          ),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill('Doğru ${totals.correct}', Colors.green.shade700),
                _Pill('Yanlış ${totals.wrong}', Colors.red.shade700),
                _Pill('Boş ${totals.empty}', Colors.orange.shade800),
              ],
            ),
            _Section(
              icon: Icons.trending_down_rounded,
              title: 'Zayıf Kazanımlar',
              child: weak.isEmpty
                  ? const _Empty('Zayıf kazanım tespit edilemedi.')
                  : Column(
                      children: [
                        for (final w in weak)
                          _BarRow(label: w.label, value: w.successRate),
                      ],
                    ),
            ),
            _Section(
              icon: Icons.radio_button_unchecked_rounded,
              title: 'En Çok Boş Bırakılan 3 Soru',
              child: empties.isEmpty
                  ? const _Empty('Boş bırakılan soru yok.')
                  : Column(
                      children: [
                        for (final e in empties)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.help_outline_rounded),
                            title: Text('${e.questionNo}. soru'),
                            subtitle: Text(
                              e.outcome.isNotEmpty && e.outcome != '-'
                                  ? e.outcome
                                  : 'Kazanım tanımsız',
                            ),
                            trailing: Text(
                              '%${(e.ratio * 100).round()} boş\n(${e.emptyCount}/${e.total})',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
            ),
            _Section(
              icon: Icons.warning_amber_rounded,
              title: 'Çeldirici Analizi',
              child: distractors.isEmpty
                  ? const _Empty(
                      'Sınıfın %40\'ından fazlasının aynı yanlış şıkka düştüğü soru yok.',
                    )
                  : Column(
                      children: [
                        for (final d in distractors)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.red.shade50,
                              child: Text(
                                d.option,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text('${d.questionNo}. soru'),
                            subtitle: Text(
                              '${d.option} şıkkı ${d.count}/${d.total} öğrenci (%${(d.ratio * 100).round()}) '
                              'tarafından işaretlendi; doğru: ${d.correctOption.isEmpty ? '?' : d.correctOption} '
                              '(${d.correctCount} kişi).'
                              '${d.outcome.isNotEmpty && d.outcome != '-' ? '\n${d.outcome}' : ''}',
                            ),
                            isThreeLine: d.outcome.isNotEmpty && d.outcome != '-',
                          ),
                      ],
                    ),
            ),
            _Section(
              icon: Icons.priority_high_rounded,
              title: 'Riskli Öğrenciler ($subject)',
              child: risky.isEmpty
                  ? _Empty('Ders başarısı ${analyzer.riskRuleText} kalan öğrenci yok.')
                  : Column(
                      children: [
                        for (final r in risky)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.error_outline_rounded,
                              color: Colors.red.shade600,
                            ),
                            title: Text(r.name),
                            subtitle: Text(
                              'Başarı %${(r.rate * 100).round()} • '
                              'Sınıf ort. %${(r.classRate * 100).round()}',
                            ),
                            trailing: Text(
                              '-%${r.gapPercent.round()}',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            if (analyzer.showActionPlan) ...[
            _Section(
              icon: Icons.assignment_turned_in_rounded,
              title: 'Haftalık Aksiyon Planı (Öğretmen İçin)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in plan.summary)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2, right: 8),
                            child: Icon(Icons.info_outline_rounded, size: 16),
                          ),
                          Expanded(child: Text(s)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  for (final w in plan.weeks)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'H${w.week}',
                              style: TextStyle(
                                color: scheme.onPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(w.detail)),
                        ],
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
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
        ),
      );
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _Section({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          child,
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
      );
}

class _StudentRow extends StatelessWidget {
  final OdakRankedStudent ranked;
  final bool risky;

  const _StudentRow({required this.ranked, required this.risky});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '${ranked.rank}.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              ranked.student.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: risky ? Colors.red.shade700 : null,
                fontWeight: risky ? FontWeight.w600 : null,
              ),
            ),
          ),
          if (ranked.student.branch.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                ranked.student.branch,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
          Text(
            ranked.score.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final double value;

  const _BarRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value < 0.4
        ? Colors.red.shade600
        : (value < 0.6 ? Colors.orange.shade700 : Colors.green.shade600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
              Text(
                '%${(value * 100).round()}',
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 6,
              color: color,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
        ],
      ),
    );
  }
}
