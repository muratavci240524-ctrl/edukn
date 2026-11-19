import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/assessment/external_exam_model.dart';
import '../models/assessment/external_exam_result_model.dart';

/// Dış katılımlı sınav öğrenci karnesi. Hem yönetim panelinde (önizleme) hem de
/// herkese açık sonuç sorgulama sayfasında kullanılır.
class ExternalExamKarneCard extends StatelessWidget {
  final ExternalExam exam;
  final ExternalExamResult result;
  final String? schoolName;

  const ExternalExamKarneCard({
    super.key,
    required this.exam,
    required this.result,
    this.schoolName,
  });

  static const Color _navy = Color(0xFF1E3A8A);

  /// Burs oranına göre banner renkleri (yüksek oran → daha sıcak / değerli renk).
  static List<Color> bursColors(int rate) {
    if (rate >= 100) return const [Color(0xFFF59E0B), Color(0xFFEA580C)];
    if (rate >= 75) return const [Color(0xFF059669), Color(0xFF34D399)];
    if (rate >= 50) return const [Color(0xFF0891B2), Color(0xFF22D3EE)];
    return const [Color(0xFF6D28D9), Color(0xFFA78BFA)];
  }

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(r),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _studentInfo(r),
                const SizedBox(height: 16),
                _statsRow(r),
                const SizedBox(height: 18),
                _subjectTable(r),
              ],
            ),
          ),
          _scholarshipBanner(r),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Text(
              'Sıralama ${r.gradeLevel}. sınıf seviyesindeki ${r.totalInGrade} aday arasında hesaplanmıştır.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(ExternalExamResult r) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.assignment_turned_in_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((schoolName ?? '').isNotEmpty)
                  Text(
                    schoolName!.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                Text(
                  exam.title,
                  style: GoogleFonts.outfit(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'SINAV KARNESİ',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: const Color(0xFFFDE68A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentInfo(ExternalExamResult r) {
    final masked = r.maskedTc;
Widget item(String l, String v) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l, style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(v, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(children: [item('ADAY', r.fullName), item('SINIF', '${r.gradeLevel}. Sınıf')]),
          const SizedBox(height: 10),
          Row(children: [item('T.C. KİMLİK NO', masked), item('OKUDUĞU OKUL', r.currentSchool.isEmpty ? '-' : r.currentSchool)]),
        ],
      ),
    );
  }

  Widget _statsRow(ExternalExamResult r) {
    Widget tile(String label, String value, Color c, {String? sub}) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(value, style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.bold, color: c)),
            if (sub != null)
              Text(sub, style: GoogleFonts.inter(fontSize: 10.5, color: c.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
    return Row(
      children: [
        tile('PUAN', r.score.toStringAsFixed(2), _navy, sub: '/ 100'),
        const SizedBox(width: 10),
        tile('SIRALAMA', '${r.rank}', const Color(0xFFEA580C), sub: '/ ${r.totalInGrade}'),
        const SizedBox(width: 10),
        tile('TOPLAM NET', r.net.toStringAsFixed(2), const Color(0xFF059669), sub: '/ ${r.orderedSubjects.fold<int>(0, (a, s) => a + s.questionCount)}'),
      ],
    );
  }

  Widget _subjectTable(ExternalExamResult r) {
    TextStyle head = GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade600);
    TextStyle cell = GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B));
    Widget c(String t, {TextStyle? s, TextAlign a = TextAlign.center}) =>
        Padding(padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4), child: Text(t, textAlign: a, style: s ?? cell));
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1), 4: FlexColumnWidth(1.2)},
        border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade200)),
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade100),
            children: [c('DERS', s: head, a: TextAlign.left), c('D', s: head), c('Y', s: head), c('B', s: head), c('NET', s: head)],
          ),
          for (final s in r.orderedSubjects)
            TableRow(children: [
              c(s.name, a: TextAlign.left),
              c('${s.correct}', s: cell.copyWith(color: const Color(0xFF059669))),
              c('${s.wrong}', s: cell.copyWith(color: const Color(0xFFDC2626))),
              c('${s.empty}'),
              c(s.net.toStringAsFixed(2), s: cell.copyWith(fontWeight: FontWeight.w800)),
            ]),
          TableRow(
            decoration: BoxDecoration(color: _navy.withValues(alpha: 0.06)),
            children: [
              c('TOPLAM', s: cell.copyWith(fontWeight: FontWeight.w800), a: TextAlign.left),
              c('${r.correct}', s: cell.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF059669))),
              c('${r.wrong}', s: cell.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFFDC2626))),
              c('${r.empty}', s: cell.copyWith(fontWeight: FontWeight.w800)),
              c(r.net.toStringAsFixed(2), s: cell.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scholarshipBanner(ExternalExamResult r) {
    if (!exam.scholarshipEnabled) return const SizedBox.shrink();

    if (r.scholarshipRate > 0) {
      final cols = bursColors(r.scholarshipRate);
      return Container(
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: cols, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: cols.first.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
              child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TEBRİKLER!', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: Colors.white.withValues(alpha: 0.9))),
                  const SizedBox(height: 2),
                  Text('%${r.scholarshipRate} Burs Kazandınız', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(
                    '${r.gradeLevel}. sınıf sıralamanız ${r.rank}. olduğu için %${r.scholarshipRate} burs hakkı kazandınız. Kayıt işlemleri için kurumumuzla iletişime geçiniz.',
                    style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: Colors.white.withValues(alpha: 0.95)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.blueGrey.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bu sınavda burs kazanma sıralamasına girilemedi. Sınava katıldığınız için teşekkür ederiz.',
              style: GoogleFonts.inter(fontSize: 12.5, color: Colors.blueGrey.shade700, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
