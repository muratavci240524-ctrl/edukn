import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';
import '../../../../models/assessment/external_exam_model.dart';
import '../../../../models/assessment/external_exam_registration_model.dart';
import '../../../../models/assessment/external_exam_result_model.dart';
import '../../../../models/assessment/optical_form_model.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../services/assessment_service.dart';
import '../../../../services/external_exam_result_service.dart';
import '../../../../services/external_exam_service.dart';
import 'external_exam_results_screen.dart';

/// "Sınav Seviyeleri" sekmesi: her sınıf seviyesi için sınav tanımı (optik form + cevap anahtarı),
/// optik dosya okuma ve sonuç / karne ekranına geçiş.
class ExternalExamLevelsTab extends StatefulWidget {
  final ExternalExam exam;
  final String institutionId;

  const ExternalExamLevelsTab({
    super.key,
    required this.exam,
    required this.institutionId,
  });

  @override
  State<ExternalExamLevelsTab> createState() => _ExternalExamLevelsTabState();
}

class _ExternalExamLevelsTabState extends State<ExternalExamLevelsTab> {
  static const Color _primary = Color(0xFFF57C00);
  final ExternalExamResultService _svc = ExternalExamResultService();
  late final Stream<List<ExternalExamResult>> _resultsStream;
  late final Stream<List<ExternalExamRegistration>> _regsStream;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _resultsStream = _svc.streamResults(widget.exam.id ?? '');
    _regsStream = ExternalExamService().getRegistrations(widget.exam.id ?? '');
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _defineLevel(String grade) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExternalExamLevelDefinitionPage(
          exam: widget.exam,
          grade: grade,
          institutionId: widget.institutionId,
        ),
      ),
    );
  }

  Future<void> _readOptical(
    String grade,
    ExternalLevelDefinition def,
    List<ExternalExamRegistration> regs,
  ) async {
    if (_busy) return;
    if (def.isTrialLinked) return _readTrialOptical(grade, def, regs);
    setState(() => _busy = true);
    try {
      final forms = await AssessmentService()
          .getOpticalForms(widget.institutionId)
          .first;
      final matches = forms.where((f) => f.id == def.opticalFormId).toList();
      if (matches.isEmpty) {
        _snack(
          'Bu seviyede seçili optik form bulunamadı. "Sınavı Tanımla" ekranından optik formu yeniden seçin.',
          color: Colors.red,
        );
        return;
      }
      final form = matches.first;

      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'dat'],
        withData: true,
      );
      if (picked == null || picked.files.single.bytes == null) return;
      final bytes = picked.files.single.bytes!;
      String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        text = ExternalExamResultService.decodeLegacyTurkish(bytes);
      }

      final report = ExternalExamResultService.processOpticalText(
        text: text,
        form: form,
        def: def,
        registrations: regs,
        exam: widget.exam,
        grade: grade,
      );

      if (!mounted) return;
      final confirm = await showDialog<String>(
        context: context,
        builder: (ctx) => _ReadPreviewDialog(report: report, grade: grade),
      );
      if (confirm != 'save' || report.results.isEmpty) return;

      final n = await _svc.saveGradeResults(
        exam: widget.exam,
        grade: grade,
        newResults: report.results,
      );
      _snack(
        '✓ ${report.results.length} aday okundu. $grade. sınıfta toplam $n aday sıralandı; burs hesaplandı.',
        color: Colors.green,
      );
    } catch (e) {
      _snack('Optik okuma hatası: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Deneme sınavına bağlı seviye: oturum başına optik dosya seçilir, okunur, sıralanır.
  Future<void> _readTrialOptical(
    String grade,
    ExternalLevelDefinition def,
    List<ExternalExamRegistration> regs,
  ) async {
    setState(() => _busy = true);
    try {
      final trial = await _svc.loadTrialExam(def.trialExamId);
      if (trial == null) {
        _snack(
          'Bağlı deneme sınavı bulunamadı (silinmiş olabilir). "Sınavı Düzenle" ile yeniden seçin.',
          color: Colors.red,
        );
        return;
      }
      final forms = await AssessmentService().getOpticalForms(widget.institutionId).first;
      if (!mounted) return;
      final texts = await showDialog<Map<int, String>>(
        context: context,
        builder: (_) => _SessionFilesDialog(
          trial: trial,
          forms: {for (final f in forms) f.id: f},
        ),
      );
      if (texts == null || texts.isEmpty) return;

      // Sınav türündeki ders sırası (karnede dersler bu sıraya göre dizilir).
      var subjectOrder = <String>[];
      try {
        final et = await AssessmentService().getExamType(trial.examTypeId);
        if (et != null) {
          subjectOrder = et.subjects.map((s) => s.branchName).where((s) => s.isNotEmpty).toList();
        }
      } catch (_) {}

      var report = ExternalExamResultService.processTrialExamSessions(
        subjectOrder: subjectOrder,
        sessionTexts: texts,
        trial: trial,
        forms: {for (final f in forms) f.id: f},
        registrations: regs,
        exam: widget.exam,
        grade: grade,
        penaltyDivisor: def.penaltyDivisor,
      );

      String? confirm;
      while (true) {
        if (!mounted) return;
        confirm = await showDialog<String>(
          context: context,
          builder: (ctx) => _ReadPreviewDialog(report: report, grade: grade),
        );
        if (confirm != 'match') break;
        if (!mounted) return;
        final updated = await showDialog<ExternalOpticalReadReport>(
          context: context,
          builder: (_) => _StudentMatchingDialog(
            report: report,
            registrations: regs,
            exam: widget.exam,
            grade: grade,
          ),
        );
        if (updated != null) report = updated;
      }
      if (confirm != 'save' || report.results.isEmpty) return;

      final n = await _svc.saveGradeResults(
        exam: widget.exam,
        grade: grade,
        newResults: report.results,
      );
      _snack(
        '✓ ${report.results.length} aday okundu. $grade. sınıfta toplam $n aday sıralandı; burs hesaplandı.',
        color: Colors.green,
      );
    } catch (e) {
      _snack('Optik okuma hatası: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editTiers(String grade) async {
    final res = await showDialog<_TierEditResult>(
      context: context,
      builder: (_) => _TierEditorDialog(
        grade: grade,
        tiers: widget.exam.scholarshipConfig[grade] ?? const <ScholarshipTier>[],
        enabled: widget.exam.scholarshipEnabled,
      ),
    );
    if (res == null) return;
    setState(() => _busy = true);
    try {
      final fresh = await _svc.saveScholarship(widget.exam.id ?? '', grade, res.tiers, res.enabled);
      int n = 0;
      if (fresh != null) n = await _svc.recomputeRanking(fresh, grade);
      _snack(
        n > 0 ? 'Burs kademeleri kaydedildi; $n adayın bursu yeniden hesaplandı.' : 'Burs kademeleri kaydedildi.',
        color: Colors.green,
      );
    } catch (e) {
      _snack('Burs kademesi kaydedilemedi: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleShare(String grade, bool share) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(share ? 'Sonuçları Paylaş' : 'Paylaşımı Geri Al'),
        content: Text(
          share
              ? '$grade. sınıf sonuçları paylaşılacak: adaylar başvuru sayfasındaki "Sınav Sonucu Sorgulama" bölümünden karnelerini görebilecek. Dilediğiniz an geri alabilirsiniz.'
              : '$grade. sınıf sonuçlarının paylaşımı kaldırılacak: adaylar artık sonuç/karne göremeyecek. Yönetici ekranındaki veriler korunur.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: share ? const Color(0xFF0F766E) : Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(share ? 'Paylaş' : 'Geri Al'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final n = await _svc.setGradeShared(widget.exam.id ?? '', grade, share);
      _snack(share ? '$n adayın sonucu paylaşıldı.' : '$n adayın paylaşımı geri alındı.', color: Colors.green);
    } catch (e) {
      _snack('İşlem başarısız: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteGradeData(String grade, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Okunan Verileri Sil'),
        content: Text(
          '$grade. sınıf seviyesine ait $count adayın TÜM okunan sonuçları (tüm yüklenen .dat dosyalarından gelenler) silinecek. '
          'Sınav tanımı ve başvurular korunur; dosyaları baştan okutabilirsiniz.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hepsini Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _svc.deleteGradeResults(widget.exam.id ?? '', grade);
      _snack('$grade. sınıf okuma verileri silindi.', color: Colors.green);
    } catch (e) {
      _snack('Silme hatası: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openResults(String grade) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExternalExamResultsScreen(
          exam: widget.exam,
          grade: grade,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exam = widget.exam;
    return SafeStreamBuilder<List<ExternalExamResult>>(
      stream: _resultsStream,
      initialData: const [],
      builder: (context, resSnap) {
        final results = resSnap.data ?? const <ExternalExamResult>[];
        return SafeStreamBuilder<List<ExternalExamRegistration>>(
          stream: _regsStream,
          initialData: const [],
          builder: (context, regSnap) {
            final regs = regSnap.data ?? const <ExternalExamRegistration>[];
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sınav Seviyeleri, Optik Okuma & Karne',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _howItWorks(),
                      const SizedBox(height: 20),
                      ...exam.gradeLevels.map((grade) {
                        final def = exam.levelDefinitions[grade];
                        final gradeResults = results.where((r) => r.gradeLevel == grade).toList();
                        final gradeRegs = regs.where((r) => r.gradeLevel == grade && r.status != RegistrationStatus.cancelled).length;
                        return _levelCard(grade, def, gradeResults.length, gradeRegs, regs, sharedCount: gradeResults.where((r) => r.shared).length);
                      }),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _howItWorks() {
    Widget step(String n, String t) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _primary, shape: BoxShape.circle),
            child: Text(n, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey.shade700))),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          step('1', 'Deneme Sınavı Seç: Deneme Sınavları modülündeki hazır sınavı bu sınıf seviyesine bağla (optik form, oturumlar ve cevap anahtarı otomatik gelir).'),
          step('2', 'Optik Dosya Oku: her oturum için optik okuyucudan çıkan .txt/.dat dosyasını seç. Adaylar T.C. kimlik no (yoksa okul no / ad-soyad) ile başvurulara eşleşir.'),
          step('3', 'Sonuç hesaplanır: puan → sınıf seviyesi sıralaması → burs kademesi. Karneler admin panelinde ve başvuru sayfasındaki "Sınav Sonuçları" bölümünde görünür.'),
        ],
      ),
    );
  }

  Widget _levelCard(
    String grade,
    ExternalLevelDefinition? def,
    int readCount,
    int regCount,
    List<ExternalExamRegistration> regs, {
    int sharedCount = 0,
  }) {
    final exam = widget.exam;
    final isMezun = grade == 'Mezun';
    final label = isMezun ? 'Mezun Seviyesi' : '$grade. Sınıf';
    final tiers = exam.scholarshipConfig[grade] ?? const <ScholarshipTier>[];
    final defined = def != null && (def.isTrialLinked || def.subjects.isNotEmpty);
    final complete = def?.isComplete ?? false;

    Widget chip(String t, Color c, IconData i) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 13, color: c),
        const SizedBox(width: 4),
        Text(t, style: GoogleFonts.inter(fontSize: 11.5, color: c, fontWeight: FontWeight.w700)),
      ]),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: complete ? Colors.green.shade200 : Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    isMezun ? 'Mzn' : '$grade.',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: _primary, fontSize: isMezun ? 12 : 15),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      complete
                          ? (def!.isTrialLinked
                              ? chip('${def.trialExamName} • ${def.sessionCount} oturum • ${def.totalQuestions} soru', Colors.green.shade700, Icons.check_circle_rounded)
                              : chip('Sınav tanımlı • ${def.totalQuestions} soru • ${def.subjects.length} ders', Colors.green.shade700, Icons.check_circle_rounded))
                          : defined
                              ? chip('Cevap anahtarı eksik', Colors.orange.shade800, Icons.warning_amber_rounded)
                              : chip('Sınav henüz tanımlanmadı', Colors.grey.shade600, Icons.link_off_rounded),
                      chip('$regCount başvuru', Colors.blue.shade700, Icons.people_alt_rounded),
                      chip('$readCount sonuç okundu', readCount > 0 ? Colors.purple.shade700 : Colors.grey.shade600, Icons.fact_check_rounded),
                      if (readCount > 0)
                        chip(
                          sharedCount == readCount
                              ? 'Paylaşıldı'
                              : sharedCount > 0
                                  ? 'Kısmen paylaşıldı'
                                  : 'Paylaşılmadı (aday göremez)',
                          sharedCount == readCount ? Colors.green.shade700 : Colors.blueGrey.shade600,
                          sharedCount == readCount ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                        ),
                      InkWell(
                        onTap: () => _editTiers(grade),
                        borderRadius: BorderRadius.circular(20),
                        child: !exam.scholarshipEnabled
                            ? chip('Burs kapalı • düzenle', Colors.grey.shade600, Icons.workspace_premium_rounded)
                            : tiers.isEmpty
                                ? chip('Burs kademesi tanımsız • düzenle', Colors.red.shade600, Icons.workspace_premium_rounded)
                                : chip('${tiers.length} burs kademesi • düzenle', Colors.amber.shade800, Icons.workspace_premium_rounded),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          if (exam.scholarshipEnabled && tiers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Burs: ${tiers.map((t) => t.displayText).join('  •  ')}',
              style: GoogleFonts.inter(fontSize: 11.5, color: Colors.amber.shade900),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _defineLevel(grade),
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: Text(defined ? 'Denemeyi Değiştir' : 'Deneme Sınavı Seç'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.indigo),
              ),
              FilledButton.icon(
                onPressed: (complete && !_busy) ? () => _readOptical(grade, def!, regs) : null,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Optik Dosya Oku'),
                style: FilledButton.styleFrom(backgroundColor: _primary),
              ),
              OutlinedButton.icon(
                onPressed: readCount > 0 ? () => _openResults(grade) : null,
                icon: const Icon(Icons.assignment_ind_rounded, size: 18),
                label: const Text('Sonuçlar & Karneler'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.teal.shade700),
              ),
              if (readCount > 0)
                sharedCount == readCount
                    ? OutlinedButton.icon(
                        onPressed: _busy ? null : () => _toggleShare(grade, false),
                        icon: const Icon(Icons.visibility_off_rounded, size: 18),
                        label: const Text('Paylaşımı Geri Al'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                      )
                    : FilledButton.icon(
                        onPressed: _busy ? null : () => _toggleShare(grade, true),
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('Paylaş'),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                      ),
              TextButton.icon(
                onPressed: (readCount > 0 && !_busy) ? () => _deleteGradeData(grade, readCount) : null,
                icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                label: const Text('Verileri Sil'),
                style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              ),
            ],
          ),
          if (!complete && defined)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Optik okuma için tüm derslerin cevap anahtarı soru sayısı kadar girilmelidir.',
                style: GoogleFonts.inter(fontSize: 11.5, color: Colors.orange.shade800),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── Okuma önizleme penceresi ─────────────────────────

class _ReadPreviewDialog extends StatelessWidget {
  final ExternalOpticalReadReport report;
  final String grade;
  const _ReadPreviewDialog({required this.report, required this.grade});

  @override
  Widget build(BuildContext context) {
    final r = report;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('Optik Okuma Önizleme ($grade. Sınıf)', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                _pill('Dosyada ${r.totalLines} satır', Colors.blueGrey),
                _pill('${r.results.length} aday eşleşti', Colors.green),
                _pill('${r.unmatched.length} eşleşmeyen', r.unmatched.isEmpty ? Colors.grey : Colors.red),
                if (r.orphans.isNotEmpty)
                  _pill('${r.orphans.length} başvuruda yok → Öğrenci Eşleme', Colors.deepOrange),
              ]),
              for (final w in r.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('⚠ $w', style: TextStyle(color: Colors.orange.shade800, fontSize: 12.5)),
                ),
              if (r.results.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('İlk eşleşenler', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                for (final x in r.results.take(5))
                  Text('• ${x.fullName} — D:${x.correct} Y:${x.wrong} Net:${x.net.toStringAsFixed(2)} Puan:${x.score.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12.5)),
              ],
              if (r.unmatched.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Eşleşmeyen satırlar (kaydedilmeyecek)', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade700)),
                const SizedBox(height: 4),
                for (final u in r.unmatched.take(40))
                  Text('• Satır ${u.lineNo}: ${u.name.isEmpty ? '(adsız)' : u.name}${u.tc.isEmpty ? '' : ' • TC ${u.tc}'} — ${u.reason}', style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
                if (r.unmatched.length > 40)
                  Text('… ve ${r.unmatched.length - 40} satır daha', style: const TextStyle(fontSize: 12)),
              ],
              const SizedBox(height: 12),
              Text(
                'Kaydedince bu okuma mevcut sonuçların üstüne eklenir: aynı aday varsa dersleri birleştirilir (aynı ders yeniden okunduysa yenisi geçerli), sonra tüm seviye puana göre yeniden sıralanır ve burs uygulanır.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Vazgeç')),
        if (r.orphans.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'match'),
            icon: const Icon(Icons.people_alt_rounded, size: 18),
            label: Text('Öğrenci Eşleme (${r.orphans.length})'),
          ),
        FilledButton.icon(
          onPressed: r.results.isEmpty ? null : () => Navigator.pop(context, 'save'),
          icon: const Icon(Icons.save_rounded, size: 18),
          label: Text('Kaydet (${r.results.length} aday)'),
        ),
      ],
    );
  }

  Widget _pill(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Text(t, style: TextStyle(color: c.shade800Safe, fontWeight: FontWeight.w700, fontSize: 12)),
  );
}

extension on Color {
  Color get shade800Safe => HSLColor.fromColor(this).withLightness(0.28).toColor();
}

// ───────────────────────── Oturum dosyaları penceresi ─────────────────────────

/// Bağlı deneme sınavının her oturumu için optik dosya seçtirir.
class _SessionFilesDialog extends StatefulWidget {
  final TrialExam trial;
  final Map<String, OpticalForm> forms;
  const _SessionFilesDialog({required this.trial, required this.forms});

  @override
  State<_SessionFilesDialog> createState() => _SessionFilesDialogState();
}

class _SessionFilesDialogState extends State<_SessionFilesDialog> {
  final Map<int, String> _texts = {};
  final Map<int, String> _names = {};

  Future<void> _pick(int sessionNo) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'dat'],
      withData: true,
    );
    if (picked == null || picked.files.single.bytes == null) return;
    final bytes = picked.files.single.bytes!;
    String text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      text = ExternalExamResultService.decodeLegacyTurkish(bytes);
    }
    setState(() {
      _texts[sessionNo] = text;
      _names[sessionNo] = picked.files.single.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessions = [...widget.trial.sessions]
      ..sort((a, b) => a.sessionNumber.compareTo(b.sessionNumber));
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'Optik Dosyaları Seç',
        style: GoogleFonts.inter(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 560,
        child: sessions.isEmpty
            ? const Text('Bu deneme sınavında tanımlı oturum yok.')
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.trial.name} • ${sessions.length} oturum. Her oturumun optik okuyucu dosyasını (.txt / .dat) seçin; '
                      'en az bir oturum yeterlidir.',
                      style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    for (final s in sessions) _row(s),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton.icon(
          onPressed: _texts.isEmpty ? null : () => Navigator.pop(context, Map<int, String>.from(_texts)),
          icon: const Icon(Icons.fact_check_rounded, size: 18),
          label: Text('Oku (${_texts.length} oturum)'),
        ),
      ],
    );
  }

  Widget _row(TrialExamSession s) {
    final form = widget.forms[s.opticalFormId ?? ''];
    final hasForm = form != null;
    final picked = _names[s.sessionNumber];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: picked != null ? Colors.green.shade50 : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: picked != null ? Colors.green.shade200 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
            child: Text(
              '${s.sessionNumber}',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFFF57C00)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s.sessionNumber}. Oturum', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5)),
                Text(
                  hasForm
                      ? 'Form: ${form.name}${s.selectedSubjects.isEmpty ? '' : ' • ${s.selectedSubjects.join(', ')}'}'
                      : 'Bu oturum için optik form seçilmemiş (okunamaz)',
                  style: TextStyle(fontSize: 11.5, color: hasForm ? Colors.grey.shade600 : Colors.red.shade600),
                ),
                if (picked != null)
                  Text('✓ $picked', style: TextStyle(fontSize: 11.5, color: Colors.green.shade800, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: hasForm ? () => _pick(s.sessionNumber) : null,
            icon: const Icon(Icons.upload_file_rounded, size: 16),
            label: Text(picked == null ? 'Dosya Seç' : 'Değiştir'),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Sınav tanımı sayfası ─────────────────────────

/// Sınıf seviyesi için Deneme Sınavları modülünden hazır bir deneme seçilir.
class ExternalExamLevelDefinitionPage extends StatefulWidget {
  final ExternalExam exam;
  final String grade;
  final String institutionId;

  const ExternalExamLevelDefinitionPage({
    super.key,
    required this.exam,
    required this.grade,
    required this.institutionId,
  });

  @override
  State<ExternalExamLevelDefinitionPage> createState() =>
      _ExternalExamLevelDefinitionPageState();
}

class _ExternalExamLevelDefinitionPageState
    extends State<ExternalExamLevelDefinitionPage> {
  final ExternalExamResultService _svc = ExternalExamResultService();
  List<TrialExam> _trials = [];
  Map<String, OpticalForm> _forms = {};
  bool _loading = true;
  bool _saving = false;
  bool _showAllLevels = false;
  String? _selectedId;
  double _penalty = 3;
  String _search = '';

  @override
  void initState() {
    super.initState();
    final existing = widget.exam.levelDefinitions[widget.grade];
    if (existing != null && existing.isTrialLinked) {
      _selectedId = existing.trialExamId;
      _penalty = existing.penaltyDivisor;
    }
    _load();
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  bool _matchesGrade(TrialExam t) {
    if (widget.grade == 'Mezun') {
      return t.classLevel.toLowerCase().contains('mezun') || t.classLevel.toLowerCase().contains('12');
    }
    final d = _digits(t.classLevel);
    return d.isNotEmpty && d == _digits(widget.grade);
  }

  Future<void> _load() async {
    try {
      final svc = AssessmentService();
      final trials = await svc.getTrialExams(widget.institutionId).first;
      final forms = await svc.getOpticalForms(widget.institutionId).first;
      if (!mounted) return;
      setState(() {
        _trials = trials;
        _forms = {for (final f in forms) f.id: f};
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(TrialExam t) async {
    setState(() => _selectedId = t.id);
    try {
      final et = await AssessmentService().getExamType(t.examTypeId);
      if (et != null && mounted) {
        setState(() => _penalty = et.wrongCorrectRatio > 0 ? et.wrongCorrectRatio : _penalty);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final matches = _trials.where((t) => t.id == _selectedId).toList();
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce bir deneme sınavı seçin.'), backgroundColor: Colors.orange),
      );
      return;
    }
    final t = matches.first;
    final def = ExternalLevelDefinition(
      trialExamId: t.id,
      trialExamName: t.name,
      sessionCount: t.sessions.length,
      linkedQuestionCount: ExternalExamResultService.trialTotalQuestions(t),
      penaltyDivisor: _penalty,
    );
    setState(() => _saving = true);
    try {
      await _svc.saveLevelDefinition(widget.exam.id ?? '', widget.grade, def);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deneme sınavı bu seviyeye bağlandı ✓ Optik okumaya hazır.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kayıt hatası: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.grade == 'Mezun' ? 'Mezun' : '${widget.grade}. Sınıf';
    final q = _search.trim().toLowerCase();
    var list = _trials.where((t) => _showAllLevels || _matchesGrade(t) || t.id == _selectedId).toList();
    if (q.isNotEmpty) list = list.where((t) => t.name.toLowerCase().contains(q)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: '$label Sınav Tanımı',
        subtitle: widget.exam.title,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Deneme Sınavı Seç',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Deneme Sınavları modülünde hazırladığınız bir sınavı $label için seçin. Optik form, oturumlar ve cevap '
                            'anahtarı o denemeden otomatik gelir; burada yalnızca optik dosyaları okutursunuz.',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  onChanged: (v) => setState(() => _search = v),
                                  decoration: InputDecoration(
                                    hintText: 'Deneme sınavı ara...',
                                    prefixIcon: const Icon(Icons.search_rounded),
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilterChip(
                                label: const Text('Tüm sınıf seviyeleri'),
                                selected: _showAllLevels,
                                onSelected: (v) => setState(() => _showAllLevels = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _trials.isEmpty
                                      ? 'Henüz hiç deneme sınavı yok. Önce Ölçme Değerlendirme › Deneme Sınavları bölümünden bir sınav tanımlayın.'
                                      : '$label için deneme sınavı bulunamadı. "Tüm sınıf seviyeleri" ile diğerlerini de görebilirsiniz.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                              itemCount: list.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => _trialTile(list[i]),
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<double>(
                              initialValue: const [3.0, 4.0, 0.0].contains(_penalty) ? _penalty : 3.0,
                              decoration: InputDecoration(
                                labelText: 'Puanlama',
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              items: const [
                                DropdownMenuItem(value: 3.0, child: Text('3 yanlış 1 doğruyu götürür')),
                                DropdownMenuItem(value: 4.0, child: Text('4 yanlış 1 doğruyu götürür')),
                                DropdownMenuItem(value: 0.0, child: Text('Yanlış doğruyu götürmez')),
                              ],
                              onChanged: (v) => setState(() => _penalty = v ?? 3),
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilledButton.icon(
                            onPressed: (_saving || _selectedId == null) ? null : _save,
                            icon: _saving
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.link_rounded),
                            label: const Text('Bu Seviyeye Bağla'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFF57C00),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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

  Widget _trialTile(TrialExam t) {
    final selected = t.id == _selectedId;
    final hasKeys = t.answerKeys.isNotEmpty;
    final qCount = ExternalExamResultService.trialTotalQuestions(t);
    final noFormSessions = t.sessions.where((s) => (s.opticalFormId ?? '').isEmpty || !_forms.containsKey(s.opticalFormId)).length;
    final canUse = hasKeys && t.sessions.isNotEmpty;

    Widget chip(String text, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w700)),
    );

    return InkWell(
      onTap: canUse ? () => _select(t) : null,
      borderRadius: BorderRadius.circular(14),
      child: Opacity(
        opacity: canUse ? 1 : 0.55,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? Colors.orange.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? const Color(0xFFF57C00) : Colors.grey.shade200,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? const Color(0xFFF57C00) : Colors.grey.shade400,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        chip(t.classLevel.isEmpty ? 'Seviye ?' : '${t.classLevel}. sınıf', Colors.indigo),
                        chip('${t.sessions.length} oturum', Colors.blue.shade700),
                        chip('$qCount soru', Colors.teal.shade700),
                        chip('${t.date.day.toString().padLeft(2, '0')}.${t.date.month.toString().padLeft(2, '0')}.${t.date.year}', Colors.grey.shade700),
                        if (!hasKeys) chip('Cevap anahtarı yok', Colors.red.shade600),
                        if (t.sessions.isEmpty) chip('Oturum tanımsız', Colors.red.shade600),
                        if (canUse && noFormSessions > 0) chip('$noFormSessions oturumda optik form yok', Colors.orange.shade800),
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
}


// ───────────────────────── Öğrenci eşleme ekranı ─────────────────────────

class _MatchDecision {
  final ExternalExamRegistration? reg;
  final bool guest;
  const _MatchDecision({this.reg, this.guest = false});
}

/// Başvuruyla otomatik eşleşmeyen optik adaylarını elle eşleme ekranı.
/// Her aday: bir başvuruya eşlenir, başvurusuz aday olarak eklenir ya da atlanır.
class _StudentMatchingDialog extends StatefulWidget {
  final ExternalOpticalReadReport report;
  final List<ExternalExamRegistration> registrations;
  final ExternalExam exam;
  final String grade;

  const _StudentMatchingDialog({
    required this.report,
    required this.registrations,
    required this.exam,
    required this.grade,
  });

  @override
  State<_StudentMatchingDialog> createState() => _StudentMatchingDialogState();
}

class _StudentMatchingDialogState extends State<_StudentMatchingDialog> {
  final Map<String, _MatchDecision> _decisions = {};
  final Map<String, ExternalExamRegistration?> _suggest = {};
  late final List<ExternalExamRegistration> _pool;
  String _q = '';
  bool _onlyOpen = false;

  @override
  void initState() {
    super.initState();
    final used = widget.report.results.map((r) => r.registrationId).toSet();
    _pool = widget.registrations
        .where((r) =>
            r.gradeLevel == widget.grade &&
            r.status != RegistrationStatus.cancelled &&
            !used.contains(r.id ?? ''))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    for (final o in widget.report.orphans) {
      _suggest[o.key] = ExternalExamResultService.suggestRegistration(o, _pool);
    }
  }

  Set<String> get _takenRegIds =>
      _decisions.values.where((d) => d.reg != null).map((d) => d.reg!.id ?? '').toSet();

  Future<void> _pick(OrphanCandidate o) async {
    final taken = _takenRegIds;
    final options = _pool.where((r) => !taken.contains(r.id ?? '')).toList();
    final picked = await showDialog<ExternalExamRegistration>(
      context: context,
      builder: (_) => _RegistrationPickerDialog(options: options, title: o.name.isEmpty ? 'Aday' : o.name),
    );
    if (picked != null) setState(() => _decisions[o.key] = _MatchDecision(reg: picked));
  }

  void _autoSuggest() {
    final taken = {..._takenRegIds};
    int n = 0;
    for (final o in widget.report.orphans) {
      if (_decisions.containsKey(o.key)) continue;
      final s = _suggest[o.key];
      if (s == null || taken.contains(s.id ?? '')) continue;
      // yalnızca en az iki kelime örtüşen güçlü öneriler
      final a = ExternalExamResultService.foldText(o.name).split(' ').toSet();
      final b = ExternalExamResultService.foldText(s.fullName).split(' ').toSet();
      if (a.where(b.contains).length < 2) continue;
      _decisions[o.key] = _MatchDecision(reg: s);
      taken.add(s.id ?? '');
      n++;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n aday önerilen başvuruyla eşlendi.')));
  }

  void _guestRest() {
    for (final o in widget.report.orphans) {
      _decisions.putIfAbsent(o.key, () => const _MatchDecision(guest: true));
    }
    setState(() {});
  }

  void _apply() {
    final results = [...widget.report.results];
    final remaining = <OrphanCandidate>[];
    for (final o in widget.report.orphans) {
      final d = _decisions[o.key];
      if (d == null) {
        remaining.add(o);
      } else if (d.reg != null) {
        results.add(ExternalExamResultService.buildResult(
          exam: widget.exam, grade: widget.grade, subjects: o.subjects, reg: d.reg, trialExamId: o.trialExamId));
      } else {
        results.add(ExternalExamResultService.buildResult(
          exam: widget.exam, grade: widget.grade, subjects: o.subjects,
          fallbackName: o.name, fallbackTc: o.tc, fallbackNo: o.studentNo, trialExamId: o.trialExamId));
      }
    }
    Navigator.pop(
      context,
      ExternalOpticalReadReport(
        results: results,
        unmatched: widget.report.unmatched,
        warnings: widget.report.warnings,
        totalLines: widget.report.totalLines,
        orphans: remaining,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = ExternalExamResultService.foldText(_q);
    final all = widget.report.orphans;
    var list = all.where((o) {
      if (_onlyOpen && _decisions.containsKey(o.key)) return false;
      if (q.isEmpty) return true;
      return ExternalExamResultService.foldText(o.name).contains(q) || o.tc.contains(q) || o.studentNo.contains(q);
    }).toList();
    final decided = _decisions.length;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Öğrenci Eşleme (${widget.grade}. Sınıf)', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17)),
                        Text(
                          'Başvuruyla eşleşmeyen ${all.length} aday  •  ${_pool.length} eşlenmemiş başvuru  •  $decided karar verildi',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      onChanged: (v) => setState(() => _q = v),
                      decoration: InputDecoration(
                        hintText: 'Ad, TC veya okul no ara...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pool.isEmpty ? null : _autoSuggest,
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text('Önerilerle Otomatik Eşle'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _guestRest,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Kalanları Başvurusuz Ekle'),
                  ),
                  FilterChip(
                    label: const Text('Yalnız kararsızlar'),
                    selected: _onlyOpen,
                    onSelected: (v) => setState(() => _onlyOpen = v),
                  ),
                  if (decided > 0)
                    TextButton(
                      onPressed: () => setState(_decisions.clear),
                      child: const Text('Kararları Temizle'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Gösterilecek aday yok.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _row(list[i]),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      'Karar verilmeyen adaylar kaydedilmez.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: decided == 0 ? null : _apply,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text('Uygula ($decided)'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(OrphanCandidate o) {
    final d = _decisions[o.key];
    final sug = _suggest[o.key];
    final sugTaken = sug != null && _takenRegIds.contains(sug.id ?? '');
    final sessions = o.sessions.map((s) => '$s. oturum').join(', ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: d == null ? Colors.white : (d.reg != null ? Colors.green.shade50 : Colors.blue.shade50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d == null ? Colors.grey.shade200 : (d.reg != null ? Colors.green.shade200 : Colors.blue.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.name.isEmpty ? '(adsız)' : o.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5)),
                Text(
                  '${o.tc.isEmpty ? '' : 'TC ${o.tc}  •  '}${o.studentNo.isEmpty ? '' : 'No ${o.studentNo}  •  '}$sessions  •  Net ${o.net.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Align(
              alignment: Alignment.centerRight,
              child: d != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            d.reg != null ? '→ ${d.reg!.fullName} (${d.reg!.studentTcNo})' : 'Başvurusuz aday olarak eklenecek',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: d.reg != null ? Colors.green.shade800 : Colors.blue.shade800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Kararı kaldır',
                          onPressed: () => setState(() => _decisions.remove(o.key)),
                          icon: const Icon(Icons.undo_rounded, size: 18),
                        ),
                      ],
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: [
                        if (sug != null && !sugTaken)
                          ActionChip(
                            avatar: const Icon(Icons.lightbulb_outline_rounded, size: 15),
                            label: Text('Öneri: ${sug.fullName}', style: const TextStyle(fontSize: 11.5)),
                            onPressed: () => setState(() => _decisions[o.key] = _MatchDecision(reg: sug)),
                          ),
                        OutlinedButton(onPressed: _pool.isEmpty ? null : () => _pick(o), child: const Text('Eşle')),
                        TextButton(
                          onPressed: () => setState(() => _decisions[o.key] = const _MatchDecision(guest: true)),
                          child: const Text('Başvurusuz Ekle'),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistrationPickerDialog extends StatefulWidget {
  final List<ExternalExamRegistration> options;
  final String title;
  const _RegistrationPickerDialog({required this.options, required this.title});

  @override
  State<_RegistrationPickerDialog> createState() => _RegistrationPickerDialogState();
}

class _RegistrationPickerDialogState extends State<_RegistrationPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = ExternalExamResultService.foldText(_q);
    final list = widget.options.where((r) {
      if (q.isEmpty) return true;
      return ExternalExamResultService.foldText(r.fullName).contains(q) ||
          r.studentTcNo.contains(q) ||
          ExternalExamResultService.foldText(r.currentSchool).contains(q);
    }).toList();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('"${widget.title}" için başvuru seç', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Ad, TC veya okul ara...',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Başvuru bulunamadı.'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final r = list[i];
                        return ListTile(
                          dense: true,
                          title: Text(r.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('TC ${r.studentTcNo}  •  ${r.currentSchool}'),
                          onTap: () => Navigator.pop(context, r),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
    );
  }
}


// ───────────────────────── Burs kademesi düzenleme ─────────────────────────

class _TierEditResult {
  final List<ScholarshipTier> tiers;
  final bool enabled;
  const _TierEditResult(this.tiers, this.enabled);
}

class _TierRow {
  final TextEditingController min;
  final TextEditingController max;
  final TextEditingController rate;
  _TierRow(int a, int b, int r)
      : min = TextEditingController(text: a > 0 ? '$a' : ''),
        max = TextEditingController(text: b > 0 ? '$b' : ''),
        rate = TextEditingController(text: r > 0 ? '$r' : '');
  void dispose() {
    min.dispose();
    max.dispose();
    rate.dispose();
  }
}

/// Bir sınıf seviyesinin burs kademelerini (sıralama aralığı → burs %) düzenler.
class _TierEditorDialog extends StatefulWidget {
  final String grade;
  final List<ScholarshipTier> tiers;
  final bool enabled;
  const _TierEditorDialog({required this.grade, required this.tiers, required this.enabled});

  @override
  State<_TierEditorDialog> createState() => _TierEditorDialogState();
}

class _TierEditorDialogState extends State<_TierEditorDialog> {
  final List<_TierRow> _rows = [];
  late bool _enabled;
  String? _error;

  @override
  void initState() {
    super.initState();
    _enabled = widget.enabled || widget.tiers.isEmpty;
    final sorted = [...widget.tiers]..sort((a, b) => a.minRank.compareTo(b.minRank));
    for (final t in sorted) {
      _rows.add(_TierRow(t.minRank, t.maxRank, t.rate));
    }
    if (_rows.isEmpty) _rows.add(_TierRow(1, 3, 100));
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _save() {
    final tiers = <ScholarshipTier>[];
    for (final r in _rows) {
      final a = int.tryParse(r.min.text.trim());
      final b = int.tryParse(r.max.text.trim());
      final p = int.tryParse(r.rate.text.trim());
      if (a == null && b == null && p == null) continue; // boş satır
      if (a == null || b == null || p == null || a < 1 || b < a || p < 1 || p > 100) {
        setState(() => _error = 'Her satırda başlangıç ≤ bitiş sıra ve %1–100 arası burs oranı girin.');
        return;
      }
      tiers.add(ScholarshipTier(minRank: a, maxRank: b, rate: p));
    }
    tiers.sort((x, y) => x.minRank.compareTo(y.minRank));
    for (int i = 1; i < tiers.length; i++) {
      if (tiers[i].minRank <= tiers[i - 1].maxRank) {
        setState(() => _error = 'Sıra aralıkları çakışıyor: ${tiers[i - 1].displayText}  /  ${tiers[i].displayText}');
        return;
      }
    }
    if (_enabled && tiers.isEmpty) {
      setState(() => _error = 'Burs açıksa en az bir kademe girin ya da bursu kapatın.');
      return;
    }
    Navigator.pop(context, _TierEditResult(tiers, _enabled));
  }

  Widget _num(TextEditingController c, String label) => SizedBox(
        width: 96,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('${widget.grade}. Sınıf Burs Kademeleri', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: const Text('Bu sınavda burs uygulansın'),
              ),
              Text(
                'Sınıf seviyesindeki sıralamaya göre burs oranı. Örn: 1–3. sıra %100, 4–10. sıra %50.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),
              for (int i = 0; i < _rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      _num(_rows[i].min, 'Sıra (baş.)'),
                      const SizedBox(width: 8),
                      _num(_rows[i].max, 'Sıra (bitiş)'),
                      const SizedBox(width: 8),
                      _num(_rows[i].rate, 'Burs %'),
                      IconButton(
                        tooltip: 'Satırı sil',
                        onPressed: () => setState(() {
                          _rows[i].dispose();
                          _rows.removeAt(i);
                        }),
                        icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: () {
                  int next = 1;
                  for (final r in _rows) {
                    final b = int.tryParse(r.max.text.trim());
                    if (b != null && b >= next) next = b + 1;
                  }
                  setState(() => _rows.add(_TierRow(next, next + 4, 0)));
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Kademe Ekle'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)),
                ),
              const SizedBox(height: 8),
              Text(
                'Kaydedince bu seviyedeki okunmuş sonuçların burs durumu otomatik yeniden hesaplanır.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_rounded, size: 18),
          label: const Text('Kaydet'),
        ),
      ],
    );
  }
}
