import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/odak_controller.dart';
import 'odak64_classes_screen.dart';

/// ODAK-64: Sınav analizi ve sınıf dağıtım modülü.
class Odak64DashboardScreen extends StatelessWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? schoolTypeName;

  const Odak64DashboardScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.schoolTypeName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OdakController(institutionId)..init(),
      child: Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.light,
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.grey.shade50,
          appBar: EduknAppBar(title: 'ODAK-64', subtitle: schoolTypeName),
          body: _Body(schoolTypeName: schoolTypeName),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String? schoolTypeName;
  const _Body({this.schoolTypeName});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OdakController>();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeaderCard(),
              const SizedBox(height: 16),
              const _ExamCard(),
              if (c.examData != null) ...[
                const SizedBox(height: 16),
                const _WeightsCard(),
                const SizedBox(height: 16),
                const _ParamsCard(),
                const SizedBox(height: 16),
                const _LessonsCard(),
                const SizedBox(height: 16),
                _GenerateButton(schoolTypeName: schoolTypeName),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade700, Colors.cyan.shade800, Colors.blue.shade900],
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
            child: const Icon(
              Icons.center_focus_strong_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ODAK-64',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Sınav sonuçlarını ders ağırlıklarına göre puanlayın, öğrencileri sınıflara '
                  'bölün ve her sınıf için savaş planını görün.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final int step;
  final String title;
  final Widget child;

  const _StepCard({required this.step, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
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
                    '$step',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OdakController>();
    Widget content;
    if (c.loadingExams) {
      content = const Center(child: CircularProgressIndicator());
    } else if (c.exams.isEmpty) {
      content = Text(
        c.error ?? 'Bu dönemde sonuçları yüklenmiş deneme sınavı bulunamadı.',
        style: TextStyle(color: Colors.grey.shade700),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: c.selectedExamId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Deneme Sınavı',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              prefixIcon: const Icon(Icons.assignment_rounded),
            ),
            items: [
              for (final e in c.exams)
                DropdownMenuItem(
                  value: e.id,
                  child: Text(
                    e.date != null
                        ? '${e.name}  •  ${e.date!.day.toString().padLeft(2, '0')}.'
                            '${e.date!.month.toString().padLeft(2, '0')}.${e.date!.year}'
                        : e.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: c.loadingExam ? null : (v) => c.selectExam(v),
          ),
          if (c.loadingExam)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (c.examData != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${c.studentCount} öğrenci • ${c.subjects.length} ders',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(c.error!, style: TextStyle(color: Colors.red.shade700)),
            ),
        ],
      );
    }
    return _StepCard(step: 1, title: 'Sınav Seçimi', child: content);
  }
}

class _WeightsCard extends StatelessWidget {
  const _WeightsCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OdakController>();
    final scheme = Theme.of(context).colorScheme;
    final ok = c.totalWeight == 100;
    return _StepCard(
      step: 2,
      title: 'Ders Ağırlıkları',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in c.subjects)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      s,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: (c.weights[s] ?? 0).toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label: '%${c.weights[s] ?? 0}',
                      onChanged: (v) => c.setWeight(s, v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '%${c.weights[s] ?? 0}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: ok ? scheme.primaryContainer : Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ok ? Icons.check_circle_rounded : Icons.error_rounded,
                  size: 18,
                  color: ok ? scheme.primary : Colors.red.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  ok
                      ? 'Toplam: %100 (bir slider değişince diğerleri orantılı ayarlanır)'
                      : 'Toplam %${c.totalWeight} — %100 olmalı',
                  style: TextStyle(
                    color: ok ? scheme.onPrimaryContainer : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParamsCard extends StatelessWidget {
  const _ParamsCard();

  @override
  Widget build(BuildContext context) {
    final c = context.read<OdakController>();
    return _StepCard(
      step: 3,
      title: 'Program Parametreleri',
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _IntField(
            label: 'Program Süresi (Hafta)',
            icon: Icons.date_range_rounded,
            initial: c.weeks,
            onChanged: c.setWeeks,
          ),
          _IntField(
            label: 'Haftalık Ders Saati',
            icon: Icons.schedule_rounded,
            initial: c.hoursPerWeek,
            onChanged: c.setHoursPerWeek,
          ),
          _IntField(
            label: 'Sınıf Mevcudu (Max)',
            icon: Icons.groups_rounded,
            initial: c.maxClassSize,
            onChanged: c.setMaxClassSize,
          ),
        ],
      ),
    );
  }
}

class _LessonsCard extends StatelessWidget {
  const _LessonsCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OdakController>();
    final scheme = Theme.of(context).colorScheme;
    final rem = c.remainingHours;
    final ok = rem == 0 && c.lessonHours.isNotEmpty;
    final over = rem < 0;
    final statusColor = ok
        ? scheme.primary
        : (over ? Colors.red.shade700 : Colors.orange.shade800);
    final statusText = c.lessonHours.isEmpty
        ? 'En az bir ders seçin'
        : ok
            ? 'Toplam ${c.allocatedHours}/${c.hoursPerWeek} saat — dağılım tamam'
            : over
                ? 'Toplam ${c.allocatedHours}/${c.hoursPerWeek} saat — ${-rem} saat fazla'
                : 'Toplam ${c.allocatedHours}/${c.hoursPerWeek} saat — $rem saat boşta';
    return _StepCard(
      step: 4,
      title: 'Verilecek Dersler ve Haftalık Saatleri',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Programda hangi derslerin verileceğini seçin ve her ders için haftalık '
            'saati belirleyin. Toplam, "Haftalık Ders Saati" (${c.hoursPerWeek}) ile eşit olmalıdır.',
            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          ),
          const SizedBox(height: 12),
          for (final s in c.subjects)
            _LessonRow(
              key: ValueKey('odak-lesson-$s'),
              subject: s,
              selected: c.lessonHours.containsKey(s),
              hours: c.lessonHours[s] ?? 0,
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ok ? Icons.check_circle_rounded : Icons.error_rounded,
                      size: 18,
                      color: statusColor,
                    ),
                    const SizedBox(width: 8),
                    Text(statusText, style: TextStyle(color: statusColor)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: c.autoDistributeHours,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: const Text('Ağırlığa göre otomatik dağıt'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  final String subject;
  final bool selected;
  final int hours;

  const _LessonRow({
    super.key,
    required this.subject,
    required this.selected,
    required this.hours,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.read<OdakController>();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer.withValues(alpha: 0.45) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? scheme.primary.withValues(alpha: 0.5) : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: (v) => c.toggleLesson(subject, v ?? false),
          ),
          Expanded(
            child: Text(
              subject,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? null : Colors.grey.shade600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Azalt',
            onPressed: selected && hours > 1
                ? () => c.setLessonHours(subject, hours - 1)
                : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          SizedBox(
            width: 70,
            child: Text(
              selected ? '$hours saat' : '—',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Artır',
            onPressed: selected ? () => c.setLessonHours(subject, hours + 1) : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _IntField extends StatefulWidget {
  final String label;
  final IconData icon;
  final int initial;
  final ValueChanged<int> onChanged;

  const _IntField({
    required this.label,
    required this.icon,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<_IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<_IntField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: TextField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: Icon(widget.icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null && n > 0) widget.onChanged(n);
        },
      ),
    );
  }
}

class _GenerateButton extends StatelessWidget {
  final String? schoolTypeName;
  const _GenerateButton({this.schoolTypeName});

  void _generateAndOpen(BuildContext context, OdakController c) {
    c.generate();
    final analyzer = c.analyzer;
    if (analyzer == null) return;
    final subjects =
        c.subjects.where((s) => c.lessonHours.containsKey(s)).toList();
    final exam = c.exams.where((e) => e.id == c.selectedExamId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Odak64ClassesScreen(
          groups: c.groups,
          analyzer: analyzer,
          subjects: subjects,
          examName: exam.isEmpty ? '' : exam.first.name,
          schoolTypeName: schoolTypeName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OdakController>();
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          FilledButton.icon(
            onPressed: c.canGenerate ? () => _generateAndOpen(context, c) : null,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(c.generated ? 'Yeniden Oluştur' : 'Sınıfları Oluştur'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
          if (c.generated)
            OutlinedButton.icon(
              onPressed: () {
                final analyzer = c.analyzer;
                if (analyzer == null) return;
                final subjects =
                    c.subjects.where((s) => c.lessonHours.containsKey(s)).toList();
                final exam = c.exams.where((e) => e.id == c.selectedExamId);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Odak64ClassesScreen(
                      groups: c.groups,
                      analyzer: analyzer,
                      subjects: subjects,
                      examName: exam.isEmpty ? '' : exam.first.name,
                      schoolTypeName: schoolTypeName,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.groups_rounded),
              label: const Text('Son Sınıfları Gör'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              ),
            ),
          if (c.stale)
            Chip(
              avatar: Icon(Icons.info_outline_rounded, color: Colors.orange.shade800),
              label: const Text('Ayarlar değişti, yeniden oluşturun'),
              backgroundColor: Colors.orange.shade50,
            ),
        ],
      ),
    );
  }
}

