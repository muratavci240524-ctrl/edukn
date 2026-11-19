import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';
import '../../../../models/assessment/external_exam_model.dart';
import '../../../../models/assessment/external_exam_result_model.dart';
import '../../../../services/external_exam_karne_pdf_service.dart';
import '../../../../services/external_exam_result_service.dart';
import '../../../../widgets/external_exam_karne_card.dart';
import '../../../../services/external_exam_outcome_karne.dart';

/// Bir sınıf seviyesinin sınav sonuçları: sıralama, burs durumu, karne önizleme ve PDF.
class ExternalExamResultsScreen extends StatefulWidget {
  final ExternalExam exam;
  final String grade;

  const ExternalExamResultsScreen({
    super.key,
    required this.exam,
    required this.grade,
  });

  @override
  State<ExternalExamResultsScreen> createState() => _ExternalExamResultsScreenState();
}

class _ExternalExamResultsScreenState extends State<ExternalExamResultsScreen> {
  final ExternalExamResultService _svc = ExternalExamResultService();
  late final Stream<List<ExternalExamResult>> _stream;
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _schoolName;

  @override
  void initState() {
    super.initState();
    _stream = _svc.streamResults(widget.exam.id ?? '');
    _loadSchoolName();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSchoolName() async {
    try {
      final d = await FirebaseFirestore.instance.collection('schools').doc(widget.exam.schoolId).get();
      if (mounted) setState(() => _schoolName = d.data()?['schoolName'] as String?);
    } catch (_) {}
  }

  void _snack(String m, {Color? c}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
  }

  Future<void> _recompute() async {
    final n = await _svc.recomputeRanking(widget.exam, widget.grade);
    _snack('$n adayın sıralaması ve bursu yeniden hesaplandı.', c: Colors.green);
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sonuçları Sil'),
        content: Text('${widget.grade}. sınıf seviyesine ait TÜM okunan sonuçlar silinecek. Sınav tanımı korunur, optik dosyayı yeniden okutabilirsiniz.'),
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
    if (ok != true) return;
    await _svc.deleteGradeResults(widget.exam.id ?? '', widget.grade);
    _snack('Sonuçlar silindi.');
    if (mounted) Navigator.pop(context);
  }

  /// Ölçme Değerlendirme'deki öğrenci karnesini (ders + kazanım analizi) açar.
  Future<void> _openOutcomeReport(BuildContext ctx, ExternalExamResult r) =>
      ExternalExamOutcomeKarne.open(context, widget.exam, r);
  Future<void> _toggleShare(bool share) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(share ? 'Sonuçları Paylaş' : 'Paylaşımı Geri Al'),
        content: Text(
          share
              ? '${widget.grade}. sınıf sonuçları paylaşılacak: adaylar başvuru sayfasındaki "Sınav Sonucu Sorgulama" bölümünden T.C. kimlik numaralarıyla karnelerini görebilecek. Dilediğiniz an geri alabilirsiniz.'
              : '${widget.grade}. sınıf sonuçlarının paylaşımı kaldırılacak: adaylar artık sonuç/karne göremeyecek. Yönetici ekranındaki veriler korunur.',
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
    try {
      final n = await _svc.setGradeShared(widget.exam.id ?? '', widget.grade, share);
      _snack(share ? '$n adayın sonucu paylaşıldı.' : '$n adayın paylaşımı geri alındı.', c: Colors.green);
    } catch (e) {
      _snack('İşlem başarısız: $e', c: Colors.red);
    }
  }

  /// Toplu karne: "Sonuç Karnesi" mi "Kazanım Karnesi" mi sorar.
  Future<void> _printBulk(List<ExternalExamResult> list) =>
      ExternalExamOutcomeKarne.printWithChoice(context, widget.exam, list, schoolName: _schoolName);
  void _showKarne(ExternalExamResult r) {    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFFF1F5F9),
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 820),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
                child: Row(
                  children: [
                    Expanded(child: Text('Karne Önizleme', style: GoogleFonts.inter(fontWeight: FontWeight.bold))),
                    TextButton.icon(
                      onPressed: () => ExternalExamOutcomeKarne.printWithChoice(context, widget.exam, [r], schoolName: _schoolName),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('Yazdır'),
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ExternalExamKarneCard(exam: widget.exam, result: r, schoolName: _schoolName),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _openOutcomeReport(ctx, r),
                          icon: const Icon(Icons.track_changes_rounded, size: 18),
                          label: const Text('Kazanım Karnesini Gör'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: '${widget.grade}. Sınıf Sonuçları',
        subtitle: widget.exam.title,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context)),
      ),
      body: SafeStreamBuilder<List<ExternalExamResult>>(
        stream: _stream,
        initialData: const [],
        builder: (context, snap) {
          final all = (snap.data ?? const <ExternalExamResult>[]).where((r) => r.gradeLevel == widget.grade).toList()
            ..sort((a, b) => a.rank.compareTo(b.rank));
          final q = _query.toLowerCase();
          final list = q.isEmpty
              ? all
              : all.where((r) => r.fullName.toLowerCase().contains(q) || r.tcNo.contains(q) || r.currentSchool.toLowerCase().contains(q)).toList();
          final burslu = all.where((r) => r.scholarshipRate > 0).length;
          final avg = all.isEmpty ? 0.0 : all.fold<double>(0, (a, r) => a + r.score) / all.length;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _stat('Katılan', '${all.length}', Colors.blue),
                        _stat('Puan Ort.', avg.toStringAsFixed(2), Colors.indigo),
                        if (widget.exam.scholarshipEnabled) _stat('Burs Kazanan', '$burslu', Colors.amber.shade800),
                        SizedBox(
                          width: 260,
                          child: TextField(
                            controller: _search,
                            onChanged: (v) => setState(() => _query = v),
                            decoration: InputDecoration(
                              hintText: 'Ad, TC veya okul ara...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: all.isEmpty ? null : () => _printBulk(list),
                          icon: const Icon(Icons.print_rounded, size: 18),
                          label: Text('Toplu Karne PDF (${list.length})'),
                        ),
                        if (all.isNotEmpty && all.every((r) => r.shared))
                          OutlinedButton.icon(
                            onPressed: () => _toggleShare(false),
                            icon: const Icon(Icons.visibility_off_rounded, size: 18),
                            label: const Text('Paylaşımı Geri Al'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                          )
                        else
                          FilledButton.icon(
                            onPressed: all.isEmpty ? null : () => _toggleShare(true),
                            icon: const Icon(Icons.share_rounded, size: 18),
                            label: Text(all.any((r) => r.shared) ? 'Paylaş (kısmen paylaşıldı)' : 'Paylaş'),
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                          ),
                        OutlinedButton.icon(
                          onPressed: all.isEmpty ? null : _recompute,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Sıralama & Bursu Yeniden Hesapla'),
                        ),
                        TextButton.icon(
                          onPressed: all.isEmpty ? null : _deleteAll,
                          icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Sonuçları Sil'),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? const Center(child: Text('Sonuç bulunamadı.'))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _row(list[i]),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _stat(String l, String v, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Text(v, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: c)),
      Text(l, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade700)),
    ]),
  );

  Widget _row(ExternalExamResult r) {
    final won = r.scholarshipRate > 0;
    final cols = ExternalExamKarneCard.bursColors(r.scholarshipRate);
    return InkWell(
      onTap: () => _showKarne(r),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: won ? cols.first.withValues(alpha: 0.5) : Colors.grey.shade200, width: won ? 1.4 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
              child: Text('${r.rank}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(r.fullName, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14))),
                      if (r.isGuest) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
                          child: Text('Başvurusuz', style: TextStyle(fontSize: 10.5, color: Colors.blue.shade800, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${r.currentSchool.isEmpty ? '-' : r.currentSchool}  •  D:${r.correct}  Y:${r.wrong}  Net:${r.net.toStringAsFixed(2)}',
                    style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Text(r.score.toStringAsFixed(2), style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E3A8A))),
            const SizedBox(width: 12),
            if (won)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: cols),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text('%${r.scholarshipRate} Burs', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ]),
              )
            else if (widget.exam.scholarshipEnabled)
              Text('Burs yok', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade500)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
