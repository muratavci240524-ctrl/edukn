import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

import 'evaluation_models.dart';
import '../../../models/assessment/trial_exam_model.dart';

class ExamReportCardService {
  static final ExamReportCardService _instance = ExamReportCardService._internal();
  factory ExamReportCardService() => _instance;
  ExamReportCardService._internal();

  // Renk Paleti (Modern, Prestijli ve Kurumsal)
  static final PdfColor primaryDark = PdfColor.fromHex('#1E3A8A'); // Koyu İndigo
  static final PdfColor primaryLight = PdfColor.fromHex('#3B82F6'); // Açık İndigo / Mavi
  static final PdfColor accentColor = PdfColor.fromHex('#4F46E5'); // İndigo Accent
  static final PdfColor successColor = PdfColor.fromHex('#16A34A'); // Yeşil
  static final PdfColor dangerColor = PdfColor.fromHex('#DC2626'); // Kırmızı
  static final PdfColor warningColor = PdfColor.fromHex('#D97706'); // Amber/Turuncu
  static final PdfColor bgHeader = PdfColor.fromHex('#0F172A'); // Koyu Slate
  static final PdfColor bgCard = PdfColor.fromHex('#F8FAFC'); // Çok açık gri
  static final PdfColor borderSoft = PdfColor.fromHex('#E2E8F0'); // Yumuşak kenarlık
  static final PdfColor textDark = PdfColor.fromHex('#1E293B'); // Koyu Metin
  static final PdfColor textMuted = PdfColor.fromHex('#64748B'); // Gri Metin

  /// Yazı tiplerini yükle
  Future<pw.ThemeData> _loadTheme() async {
    try {
      final regular = await PdfGoogleFonts.openSansRegular();
      final bold = await PdfGoogleFonts.openSansBold();
      return pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: regular,
        boldItalic: bold,
      );
    } catch (e) {
      debugPrint("PdfGoogleFonts error: $e, using default fallback font");
      return pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
    }
  }

  static int getSubjectOrderIndex(String subject, {List<String>? definedOrder}) {
    final clean = subject.trim().toLowerCase();

    if (definedOrder != null && definedOrder.isNotEmpty) {
      for (int i = 0; i < definedOrder.length; i++) {
        final d = definedOrder[i].trim().toLowerCase();
        if (clean == d || clean.contains(d) || d.contains(clean)) {
          return i;
        }
      }
    }

    // 1: Türkçe
    if (clean.contains('türkçe') ||
        clean.contains('turkce') ||
        clean.contains('edebiyat') ||
        clean.contains('türk dili')) {
      return 10;
    }
    // 2: Sosyal Bilgiler / T.C. İnkılap Tarihi ve Atatürkçülük / Tarih / Coğrafya
    if (clean.contains('sosyal') ||
        clean.contains('inkılap') ||
        clean.contains('inkilap') ||
        clean.contains('tarih') ||
        clean.contains('coğrafya') ||
        clean.contains('felsefe')) {
      return 20;
    }
    // 3: Din Kültürü ve Ahlak Bilgisi
    if (clean.contains('din')) {
      return 30;
    }
    // 4: İngilizce / Yabancı Dil
    if (clean.contains('ingilizce') ||
        clean.contains('yabancı') ||
        clean.contains('yabanci') ||
        clean.contains('dil') ||
        clean.contains('almanca') ||
        clean.contains('fransızca')) {
      return 40;
    }
    // 5: Matematik (İlköğretim Matematik, Temel Matematik, Geometri)
    if (clean.contains('matematik') || clean.contains('geometri')) {
      return 50;
    }
    // 6: Fen Bilimleri (Fen ve Teknoloji, Fizik, Kimya, Biyoloji)
    if (clean.contains('fen') ||
        clean.contains('fizik') ||
        clean.contains('kimya') ||
        clean.contains('biyoloji')) {
      return 60;
    }

    return 999;
  }

  static List<String> sortSubjectsList(List<String> rawSubjects,
      {List<String>? definedOrder}) {
    final list = List<String>.from(rawSubjects);
    list.sort((a, b) {
      int idxA = getSubjectOrderIndex(a, definedOrder: definedOrder);
      int idxB = getSubjectOrderIndex(b, definedOrder: definedOrder);
      if (idxA != idxB) return idxA.compareTo(idxB);
      return a.compareTo(b);
    });
    return list;
  }

  // ===========================================================================
  // 1. ÖĞRENCİ SINAV SONUÇ BELGESİ (KARNE) - TEK VEYA TOPLU
  // ===========================================================================
  Future<Uint8List> generateStudentReportCardsPdf({
    required List<StudentResult> students,
    required String examName,
    DateTime? examDate,
    String? institutionName,
    required List<String> subjects,
    Map<String, Map<String, List<String>>> outcomes = const {},
    int totalStudents = 0,
    int schoolStudents = 0,
    Map<String, int> branchStudentCounts = const {},
    bool isRankingVisible = true,
    List<String>? definedSubjectOrder,
  }) async {
    final pdf = pw.Document();
    final theme = await _loadTheme();
    final dateStr = examDate != null ? DateFormat('dd.MM.yyyy').format(examDate) : '';
    final orderedSubjects = sortSubjectsList(subjects, definedOrder: definedSubjectOrder);

    for (int i = 0; i < students.length; i++) {
      if (i > 0 && i % 4 == 0) {
        await Future.delayed(Duration.zero);
      }
      final student = students[i];
      final branchCount = branchStudentCounts[student.branch] ?? 0;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          theme: theme,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // 1. Üst Başlık (Header)
                _buildStudentHeader(
                  student: student,
                  examName: examName,
                  examDate: dateStr,
                  institutionName: _resolveSchoolType(institutionName, student.classLevel),
                ),
                pw.SizedBox(height: 6),

                // 2. Öğrenci Bilgileri ve Derece Kartı
                _buildStudentInfoAndRanks(
                  student: student,
                  totalStudents: totalStudents > 0 ? totalStudents : students.length,
                  schoolStudents: schoolStudents > 0 ? schoolStudents : students.length,
                  branchStudents: branchCount,
                  isRankingVisible: isRankingVisible,
                ),
                pw.SizedBox(height: 6),

                // 3. Ders Başarı ve Net Tablosu
                _buildStudentScoreTable(student, orderedSubjects),
                pw.SizedBox(height: 6),

                // 4. Cevap Anahtarı & Öğrenci Cevapları Şeridi
                _buildStudentAnswerKeys(student, orderedSubjects),
                pw.SizedBox(height: 6),

                // 5. Konu ve Kazanım Analizi (Kalan boşluğu dolduracak şekilde)
                pw.Expanded(
                  child: _buildStudentOutcomesAnalysis(student, orderedSubjects, outcomes),
                ),

                // 6. Sayfa Altlığı (Footer)
                _buildFooter(pageNumber: i + 1, totalPages: students.length),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  String _resolveSchoolType(String? instName, String classLevel) {
    if (instName != null &&
        instName.trim().isNotEmpty &&
        instName.trim().toLowerCase() != 'eğitim kurumu' &&
        instName.trim().toLowerCase() != 'egitim kurumu') {
      return instName.trim();
    }
    final digits = RegExp(r'\d+').firstMatch(classLevel)?.group(0);
    if (digits != null) {
      final grade = int.tryParse(digits);
      if (grade != null) {
        if (grade >= 1 && grade <= 4) return 'İLKOKUL';
        if (grade >= 5 && grade <= 8) return 'ORTAOKUL';
        if (grade >= 9 && grade <= 12) return 'ANADOLU LİSESİ';
      }
    }
    final clean = classLevel.toLowerCase();
    if (clean.contains('anaokul') || clean.contains('kreş') || clean.contains('anasınıf')) return 'ANAOKULU';
    if (clean.contains('ilkokul')) return 'İLKOKUL';
    if (clean.contains('ortaokul') || clean.contains('lgs')) return 'ORTAOKUL';
    if (clean.contains('lise') || clean.contains('yks') || clean.contains('tyt')) return 'ANADOLU LİSESİ';
    return 'ORTAOKUL';
  }

  // --- Öğrenci Karne Bileşenleri ---

  pw.Widget _buildStudentHeader({
    required StudentResult student,
    required String examName,
    required String examDate,
    required String institutionName,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: primaryDark,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                institutionName.toUpperCase(),
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                "SINAV SONUÇ BELGESİ",
                style: pw.TextStyle(
                  color: PdfColor.fromHex('#93C5FD'),
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                examName,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                "${student.classLevel}. Sınıf • $examDate",
                style: pw.TextStyle(
                  color: PdfColor.fromHex('#E2E8F0'),
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStudentInfoAndRanks({
    required StudentResult student,
    required int totalStudents,
    required int schoolStudents,
    required int branchStudents,
    required bool isRankingVisible,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Sol Kart: Öğrenci Kimliği
        pw.Expanded(
          flex: 5,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: bgCard,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: borderSoft, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      "ÖĞRENCİ BİLGİLERİ",
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: textMuted,
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: pw.BoxDecoration(
                        color: primaryLight,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(
                        "KİTAPÇIK: ${student.booklet.isNotEmpty ? student.booklet : 'A'}",
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  student.name.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: textDark,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  children: [
                    pw.Text(
                      "Okul No: ",
                      style: pw.TextStyle(fontSize: 8, color: textMuted),
                    ),
                    pw.Text(
                      student.studentNo.isNotEmpty ? student.studentNo : '-',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(width: 16),
                    pw.Text(
                      "Sınıf / Şube: ",
                      style: pw.TextStyle(fontSize: 8, color: textMuted),
                    ),
                    pw.Text(
                      "${student.classLevel} / ${student.branch}",
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 8),

        // Sağ Kart: Puan & Dereceler
        pw.Expanded(
          flex: 5,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: bgCard,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: borderSoft, width: 0.8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                // Toplam Puan Kutusu
                pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      "SINAV PUANI",
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: textMuted,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      student.score.toStringAsFixed(2),
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryDark,
                      ),
                    ),
                    pw.Text(
                      "Net: ${student.total.net.toStringAsFixed(2)}",
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: successColor,
                      ),
                    ),
                  ],
                ),


                // Dereceler yalnızca paylaşım ayarında "Derecelendirme" işaretliyse gösterilir.
                if (isRankingVisible) ...[
                  _buildRankBadge('GENEL', student.rankGeneral, totalStudents),
                  _buildRankBadge('KURUM', student.rankInstitution, schoolStudents),
                  _buildRankBadge('ŞUBE', student.rankBranch, branchStudents),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildRankBadge(String title, int rank, int total) {
    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 7, color: textMuted),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          rank > 0 ? "$rank" : "-",
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: textDark,
          ),
        ),
        pw.Text(
          total > 0 ? "/ $total" : "",
          style: pw.TextStyle(fontSize: 6.5, color: textMuted),
        ),
      ],
    );
  }

  pw.Widget _buildStudentScoreTable(StudentResult student, List<String> subjects) {
    int totalQ = 0;
    int totalD = 0;
    int totalY = 0;
    int totalB = 0;
    double totalNet = 0.0;

    final rows = <pw.TableRow>[];

    for (var s in subjects) {
      final stat = student.subjects[s];
      int q = 0;
      int d = 0;
      int y = 0;
      int b = 0;
      double n = 0.0;

      if (stat != null) {
        d = stat.correct;
        y = stat.wrong;
        b = stat.empty;
        n = stat.net;
        q = d + y + b;
      }
      if (student.correctAnswers.containsKey(s) && student.correctAnswers[s]!.isNotEmpty) {
        q = student.correctAnswers[s]!.length;
        b = q - (d + y);
        if (b < 0) b = 0;
      }

      totalQ += q;
      totalD += d;
      totalY += y;
      totalB += b;
      totalNet += n;

      final successRate = q > 0 ? (d / q) * 100 : 0.0;

      rows.add(
        pw.TableRow(
          decoration: rows.length % 2 == 1
              ? pw.BoxDecoration(color: PdfColor.fromHex('#F8FAFC'))
              : const pw.BoxDecoration(color: PdfColors.white),
          children: [
            _tableCell(s, alignLeft: true, isBold: true),
            _tableCell("$q"),
            _tableCell("$d", color: successColor, isBold: true),
            _tableCell("$y", color: dangerColor, isBold: true),
            _tableCell("$b", color: textMuted),
            _tableCell(n.toStringAsFixed(2), isBold: true, color: primaryDark),
            _tableCell("%${successRate.toStringAsFixed(0)}", isBold: true),
          ],
        ),
      );
    }

    final totalSuccessRate = totalQ > 0 ? (totalD / totalQ) * 100 : 0.0;

    return pw.Container(
      decoration: pw.BoxDecoration(
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: borderSoft, width: 0.8),
      ),
      child: pw.Table(
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: borderSoft, width: 0.5),
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(3.2),
          1: const pw.FlexColumnWidth(1),
          2: const pw.FlexColumnWidth(1),
          3: const pw.FlexColumnWidth(1),
          4: const pw.FlexColumnWidth(1),
          5: const pw.FlexColumnWidth(1.2),
          6: const pw.FlexColumnWidth(1.2),
        },
        children: [
          // Başlık Satırı
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F1F5F9'),
              borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(5)),
            ),
            children: [
              _tableCell("DERS ADI", isHeader: true, alignLeft: true),
              _tableCell("SORU", isHeader: true),
              _tableCell("DOĞRU", isHeader: true),
              _tableCell("YANLIŞ", isHeader: true),
              _tableCell("BOŞ", isHeader: true),
              _tableCell("NET", isHeader: true),
              _tableCell("BAŞARI", isHeader: true),
            ],
          ),
          ...rows,
          // Toplam Satırı
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#E0E7FF'),
              borderRadius: const pw.BorderRadius.vertical(bottom: pw.Radius.circular(5)),
            ),
            children: [
              _tableCell("GENEL TOPLAM", alignLeft: true, isBold: true, color: primaryDark),
              _tableCell("$totalQ", isBold: true, color: primaryDark),
              _tableCell("$totalD", isBold: true, color: successColor),
              _tableCell("$totalY", isBold: true, color: dangerColor),
              _tableCell("$totalB", isBold: true, color: textMuted),
              _tableCell(totalNet.toStringAsFixed(2), isBold: true, color: primaryDark),
              _tableCell("%${totalSuccessRate.toStringAsFixed(0)}", isBold: true, color: primaryDark),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _tableCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    bool alignLeft = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.center,
        maxLines: 1,
        style: pw.TextStyle(
          fontSize: isHeader ? 7.0 : 7.5,
          fontWeight: isHeader || isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? (isHeader ? textDark : textDark),
        ),
      ),
    );
  }

  pw.Widget _buildStudentAnswerKeys(StudentResult student, List<String> subjects) {
    final validSubjects = subjects.where((s) {
      final c = student.correctAnswers[s] ?? "";
      final st = student.answers[s] ?? "";
      return c.isNotEmpty || st.isNotEmpty;
    }).toList();

    if (validSubjects.isEmpty) return pw.SizedBox.shrink();

    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: bgCard,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: borderSoft, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                "CEVAP ANAHTARI VE ÖĞRENCİ CEVAPLARI",
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: textMuted,
                ),
              ),
              pw.Row(
                children: [
                  _legendDot(successColor, "Doğru"),
                  pw.SizedBox(width: 8),
                  _legendDot(dangerColor, "Yanlış"),
                  pw.SizedBox(width: 8),
                  _legendDot(textMuted, "Boş"),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Wrap(
            spacing: 6,
            runSpacing: 4,
            children: validSubjects.map((s) {
              final c = student.correctAnswers[s] ?? "";
              final st = student.answers[s] ?? "";
              final len = c.length > st.length ? c.length : st.length;
              // Her iki satır aynı hücre genişliğini kullanır (aynı soru = aynı sütun)
              const availableWidth = 153.0;
              const groupGap = 3.0; // her 5 soruda bir boşluk
              final gapCount = len > 0 ? (len - 1) ~/ 5 : 0;
              final cellW = (len > 0 && len * 4.8 + gapCount * groupGap > availableWidth)
                  ? (availableWidth - gapCount * groupGap) / len
                  : 4.8;

              return pw.Container(
                width: 175,
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  border: pw.Border.all(color: borderSoft, width: 0.6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      s,
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryDark,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Row(
                      children: [
                        pw.Container(
                          width: 14,
                          child: pw.Text("C:", style: pw.TextStyle(fontSize: 6, color: textMuted)),
                        ),
                        pw.Expanded(
                          child: pw.Row(
                            children: List.generate(len, (idx) {
                              final cChar = idx < c.length ? c[idx] : ' ';
                              return pw.Padding(
                                padding: pw.EdgeInsets.only(
                                  right: ((idx + 1) % 5 == 0 && idx < len - 1) ? groupGap : 0,
                                ),
                                child: pw.Container(
                                  width: cellW,
                                  alignment: pw.Alignment.center,
                                  child: pw.Text(
                                    cChar == ' ' ? '-' : cChar,
                                    style: pw.TextStyle(
                                      fontSize: 6,
                                      font: pw.Font.courier(),
                                      fontWeight: pw.FontWeight.bold,
                                      color: textDark,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                    pw.Row(
                      children: [
                        pw.Container(
                          width: 14,
                          child: pw.Text("Ö:", style: pw.TextStyle(fontSize: 6, color: textMuted)),
                        ),
                        pw.Expanded(
                          child: pw.Row(
                            children: List.generate(len, (idx) {
                              final stChar = idx < st.length ? st[idx] : ' ';
                              final cChar = idx < c.length ? c[idx] : ' ';
                              final status = TrialExam.evaluateAnswer(stChar, cChar);

                              PdfColor charColor = textMuted;
                              if (status == AnswerStatus.correct) {
                                charColor = successColor;
                              } else if (status == AnswerStatus.wrong) {
                                charColor = dangerColor;
                              }

                              return pw.Padding(
                                padding: pw.EdgeInsets.only(
                                  right: ((idx + 1) % 5 == 0 && idx < len - 1) ? groupGap : 0,
                                ),
                                child: pw.Container(
                                  width: cellW,
                                  alignment: pw.Alignment.center,
                                  child: pw.Text(
                                    stChar == ' ' ? '-' : stChar,
                                    style: pw.TextStyle(
                                      fontSize: 6,
                                      font: pw.Font.courier(),
                                      fontWeight: pw.FontWeight.bold,
                                      color: charColor,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  pw.Widget _legendDot(PdfColor color, String text) {
    return pw.Row(
      children: [
        pw.Container(
          width: 5,
          height: 5,
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
        ),
        pw.SizedBox(width: 2.5),
        pw.Text(text, style: pw.TextStyle(fontSize: 6.5, color: textDark)),
      ],
    );
  }

  pw.Widget _buildStudentOutcomesAnalysis(
    StudentResult student,
    List<String> subjects,
    Map<String, Map<String, List<String>>> outcomes,
  ) {
    String booklet = student.booklet;
    if (!outcomes.containsKey(booklet) && booklet.length > 1 && outcomes.containsKey(booklet[0])) {
      booklet = booklet[0];
    }
    if (!outcomes.containsKey(booklet) && outcomes.isNotEmpty) {
      booklet = outcomes.keys.first;
    }

    if (!outcomes.containsKey(booklet)) {
      return pw.Center(
        child: pw.Text(
          "Kazanım / Konu analizi verisi bulunamadı.",
          style: pw.TextStyle(fontSize: 8, color: textMuted),
        ),
      );
    }

    final validSubjects = subjects.where((s) => outcomes[booklet]!.containsKey(s)).toList();
    if (validSubjects.isEmpty) return pw.SizedBox.shrink();

    // Tüm konuları topla ve 2 sütuna böl
    final subjectWidgets = <pw.Widget>[];

    for (var subject in validSubjects) {
      final topics = outcomes[booklet]![subject]!;
      final correctAns = student.correctAnswers[subject] ?? "";
      final studentAns = student.answers[subject] ?? "";

      Map<String, _TopicStat> stats = {};
      int len = correctAns.length;
      if (topics.length < len) len = topics.length;

      for (int i = 0; i < len; i++) {
        String topic = topics[i].trim();
        if (topic.isEmpty) topic = "Genel";
        stats.putIfAbsent(topic, () => _TopicStat());

        String c = correctAns[i];
        String s = (i < studentAns.length) ? studentAns[i] : " ";
        stats[topic]!.total++;

        final res = TrialExam.evaluateAnswer(s, c);
        if (res == AnswerStatus.correct) {
          stats[topic]!.correct++;
        } else if (res == AnswerStatus.empty) {
          stats[topic]!.empty++;
        } else {
          stats[topic]!.wrong++;
        }
      }

      if (stats.isEmpty) continue;

      subjectWidgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 5),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: borderSoft, width: 0.6),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#EEF2F6'),
                  borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(3)),
                ),
                child: pw.Text(
                  subject,
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryDark,
                  ),
                ),
              ),
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(6),
                  1: const pw.FixedColumnWidth(16),
                  2: const pw.FixedColumnWidth(16),
                  3: const pw.FixedColumnWidth(16),
                  4: const pw.FixedColumnWidth(22),
                },
                border: pw.TableBorder(
                  horizontalInside: pw.BorderSide(color: borderSoft, width: 0.4),
                ),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F8FAFC')),
                    children: [
                      _outcomeCell("Kazanım / Konu", isHeader: true, alignLeft: true),
                      _outcomeCell("S", isHeader: true),
                      _outcomeCell("D", isHeader: true),
                      _outcomeCell("Y", isHeader: true),
                      _outcomeCell("%", isHeader: true),
                    ],
                  ),
                  ...stats.entries.toList().asMap().entries.map((entry) {
                    final e = entry.value;
                    final st = e.value;
                    final succ = st.total > 0 ? ((st.correct / st.total) * 100).round() : 0;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: entry.key % 2 == 1
                            ? PdfColor.fromHex('#F1F5F9')
                            : PdfColors.white,
                      ),
                      children: [
                        _outcomeCell(e.key, alignLeft: true),
                        _outcomeCell("${st.total}"),
                        _outcomeCell("${st.correct}", color: successColor),
                        _outcomeCell("${st.wrong}", color: dangerColor),
                        _outcomeCell("%$succ", isBold: true),
                      ],
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      );
    }

    int mid = (subjectWidgets.length / 2).ceil();
    final col1 = subjectWidgets.take(mid).toList();
    final col2 = subjectWidgets.skip(mid).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          "KAZANIM VE KONU ANALİZİ",
          style: pw.TextStyle(
            fontSize: 7.5,
            fontWeight: pw.FontWeight.bold,
            color: textMuted,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Expanded(
          child: col2.isEmpty
              // Tek sütuna sığıyorsa sayfa genişliğini kapla
              ? pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: col1,
                )
              : pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(child: pw.Column(children: col1)),
                    pw.SizedBox(width: 8),
                    pw.Expanded(child: pw.Column(children: col2)),
                  ],
                ),
        ),
      ],
    );
  }

  pw.Widget _outcomeCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    bool alignLeft = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: pw.Text(
        text,
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.center,
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
        style: pw.TextStyle(
          fontSize: isHeader ? 6 : 6.5,
          fontWeight: isHeader || isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? (isHeader ? textMuted : textDark),
        ),
      ),
    );
  }

  pw.Widget _buildFooter({required int pageNumber, required int totalPages, String? branchName}) {
    final title = branchName != null
        ? "EduKN Sınav & Ölçme Değerlendirme Sistemi • $branchName Şubesi Raporu"
        : "EduKN Sınav & Ölçme Değerlendirme Sistemi • Kurum Geneli Raporu";
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 6.5, color: textMuted),
          ),
          pw.Text(
            "Sayfa $pageNumber / $totalPages",
            style: pw.TextStyle(fontSize: 6.5, color: textMuted),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. KURUM SINAV KARNESİ (KURUMSAL DEĞERLENDİRME VE BAŞARI RAPORU)
  // ===========================================================================
  Future<Uint8List> generateInstitutionalReportCardPdf({
    required String examName,
    DateTime? examDate,
    String? classLevel,
    String? institutionName,
    required List<Map<String, dynamic>> examResults,
    required List<String> availableSubjects,
  }) async {
    final pdf = pw.Document();
    final theme = await _loadTheme();
    final dateStr = examDate != null ? DateFormat('dd.MM.yyyy').format(examDate) : '';

    // İstatistikleri Hesapla
    int totalStudents = examResults.length;
    double sumScore = 0.0;
    double sumNet = 0.0;
    double maxScore = 0.0;
    String topStudentName = '-';
    String topStudentBranch = '-';

    Map<String, List<Map<String, dynamic>>> byBranch = {};
    Map<String, _SubjectAccumulator> subjectTotals = {};
    for (var s in availableSubjects) {
      subjectTotals[s] = _SubjectAccumulator();
    }

    for (var r in examResults) {
      final score = num.tryParse(r['totalScore']?.toString() ?? '0')?.toDouble() ?? 0.0;
      final net = num.tryParse(r['totalNet']?.toString() ?? '0')?.toDouble() ?? 0.0;
      sumScore += score;
      sumNet += net;

      if (score > maxScore) {
        maxScore = score;
        topStudentName = (r['studentName'] ?? r['name'] ?? '-').toString();
        topStudentBranch = (r['className'] ?? r['branch'] ?? '-').toString();
      }

      final bName = (r['className'] ?? r['branch'] ?? 'Belirtilmemiş').toString();
      byBranch.putIfAbsent(bName, () => []).add(r);

      // Ders bazlı
      if (r['subjects'] != null && r['subjects'] is Map) {
        final subMap = r['subjects'] as Map;
        subMap.forEach((k, v) {
          final subj = k.toString();
          if (subjectTotals.containsKey(subj) && v is Map) {
            subjectTotals[subj]!.correct += int.tryParse(v['correct']?.toString() ?? '0') ?? 0;
            subjectTotals[subj]!.wrong += int.tryParse(v['wrong']?.toString() ?? '0') ?? 0;
            subjectTotals[subj]!.empty += int.tryParse(v['empty']?.toString() ?? '0') ?? 0;
            subjectTotals[subj]!.net += num.tryParse(v['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
            subjectTotals[subj]!.count++;
          }
        });
      }
    }

    double avgScore = totalStudents > 0 ? sumScore / totalStudents : 0.0;
    double avgNet = totalStudents > 0 ? sumNet / totalStudents : 0.0;

    // Şubeleri Sırala (Puan ortalamasına göre)
    final branchList = byBranch.keys.toList();
    branchList.sort((a, b) {
      final listA = byBranch[a]!;
      final listB = byBranch[b]!;
      final avgA = listA.fold<double>(0, (prev, e) => prev + (num.tryParse(e['totalScore']?.toString() ?? '0') ?? 0)) / listA.length;
      final avgB = listB.fold<double>(0, (prev, e) => prev + (num.tryParse(e['totalScore']?.toString() ?? '0') ?? 0)) / listB.length;
      return avgB.compareTo(avgA);
    });

    // İlk 10 Öğrenci (Dereceler)
    final sortedStudents = List<Map<String, dynamic>>.from(examResults);
    sortedStudents.sort((a, b) {
      final scA = num.tryParse(a['totalScore']?.toString() ?? '0') ?? 0;
      final scB = num.tryParse(b['totalScore']?.toString() ?? '0') ?? 0;
      return scB.compareTo(scA);
    });
    // Aynı puanı alanlar aynı sırayı alır; ilk 10 SIRADAKİ tüm öğrenciler listelenir.
    final allRanks = _competitionRanks(sortedStudents);
    final topStudents = <Map<String, dynamic>>[];
    final topRanks = <int>[];
    for (int i = 0; i < sortedStudents.length; i++) {
      if (allRanks[i] <= 10) {
        topStudents.add(sortedStudents[i]);
        topRanks.add(allRanks[i]);
      }
    }

    final totalPages = 1 + branchList.length;

    // ─────────────────────────────────────────────────────────────
    // SAYFA 1: KURUM GENELİ ÖZETİ
    // ─────────────────────────────────────────────────────────────
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        theme: theme,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // 1. Kurum Başlığı
              _buildInstitutionHeader(
                institutionName: (institutionName != null && institutionName.isNotEmpty)
                    ? institutionName
                    : 'Eğitim Kurumu',
                examName: examName,
                examDate: dateStr,
                classLevel: classLevel ?? '',
              ),
              pw.SizedBox(height: 10),

              // 2. KPI / Özet Kartları
              _buildInstitutionKpiCards(
                totalStudents: totalStudents,
                totalBranches: byBranch.length,
                avgScore: avgScore,
                avgNet: avgNet,
                maxScore: maxScore,
                topStudentName: topStudentName,
                topStudentBranch: topStudentBranch,
                topStudentCount: _countTopScorers(examResults),
              ),
              pw.SizedBox(height: 10),

              // 3. Şube Karşılaştırma Tablosu
              pw.Text(
                "ŞUBE BAŞARI KARŞILAŞTIRMA LİSTESİ",
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryDark,
                ),
              ),
              pw.SizedBox(height: 4),
              _buildBranchComparisonTable(
                byBranch: byBranch,
                sortedBranches: branchList,
                subjects: availableSubjects,
                avgSchoolScore: avgScore,
                avgSchoolNet: avgNet,
              ),
              pw.SizedBox(height: 10),

              // 4. Ders Bazlı Başarı Analizi
              pw.Text(
                "DERS BAZLI KURUM GENEL BAŞARI ANALİZİ",
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryDark,
                ),
              ),
              pw.SizedBox(height: 4),
              _buildSubjectSummaryTable(subjectTotals, totalStudents),
              pw.SizedBox(height: 10),

              // 5. Kurum İlk 10 Başarı Listesi (Onur Listesi)
              pw.Text(
                topStudents.length > 10
                    ? "KURUM DERECELERİ (İLK 10 SIRA • ${topStudents.length} ÖĞRENCİ)"
                    : "KURUM DERECELERİ (İLK 10 ÖĞRENCİ)",
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryDark,
                ),
              ),
              pw.SizedBox(height: 4),
              _buildTopStudentsTable(topStudents, topRanks),
              pw.Spacer(),

              // 6. Footer
              _buildFooter(pageNumber: 1, totalPages: totalPages),
            ],
          );
        },
      ),
    );

    // ─────────────────────────────────────────────────────────────
    // SAYFA 2..N: HER ŞUBE İÇİN AYRI AYRINTILI BAŞARI RAPORU (GRAFİKLİ)
    // ─────────────────────────────────────────────────────────────
    for (int bIdx = 0; bIdx < branchList.length; bIdx++) {
      final bName = branchList[bIdx];
      final bStudents = List<Map<String, dynamic>>.from(byBranch[bName]!);
      bStudents.sort((a, b) {
        final scA = num.tryParse(a['totalScore']?.toString() ?? '0') ?? 0;
        final scB = num.tryParse(b['totalScore']?.toString() ?? '0') ?? 0;
        return scB.compareTo(scA);
      });

      final int bCount = bStudents.length;
      final double bSumScore = bStudents.fold<double>(0, (p, e) => p + (num.tryParse(e['totalScore']?.toString() ?? '0') ?? 0));
      final double bSumNet = bStudents.fold<double>(0, (p, e) => p + (num.tryParse(e['totalNet']?.toString() ?? '0') ?? 0));
      final double bAvgScore = bCount > 0 ? bSumScore / bCount : 0.0;
      final double bAvgNet = bCount > 0 ? bSumNet / bCount : 0.0;
      final topBranchStudent = bStudents.isNotEmpty ? bStudents.first : null;
      final topBranchStudentName = topBranchStudent != null
          ? (topBranchStudent['studentName'] ?? topBranchStudent['name'] ?? '-').toString()
          : '-';
      final topBranchScore = topBranchStudent != null
          ? (num.tryParse(topBranchStudent['totalScore']?.toString() ?? '0')?.toDouble() ?? 0.0)
          : 0.0;

      final int topBranchCount = _countTopScorers(bStudents);
      final List<int> bRanks = _competitionRanks(bStudents);

      // Şubenin ders bazlı toplamları
      final Map<String, _SubjectAccumulator> bSubjectTotals = {};
      for (var s in availableSubjects) {
        bSubjectTotals[s] = _SubjectAccumulator();
      }
      for (var r in bStudents) {
        if (r['subjects'] != null && r['subjects'] is Map) {
          final subMap = r['subjects'] as Map;
          subMap.forEach((k, v) {
            final subj = k.toString();
            if (bSubjectTotals.containsKey(subj) && v is Map) {
              bSubjectTotals[subj]!.correct += int.tryParse(v['correct']?.toString() ?? '0') ?? 0;
              bSubjectTotals[subj]!.wrong += int.tryParse(v['wrong']?.toString() ?? '0') ?? 0;
              bSubjectTotals[subj]!.empty += int.tryParse(v['empty']?.toString() ?? '0') ?? 0;
              bSubjectTotals[subj]!.net += num.tryParse(v['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
              bSubjectTotals[subj]!.count++;
            }
          });
        }
      }

      final pageNumber = 2 + bIdx;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          theme: theme,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // 1. Şube Başlığı
                _buildBranchHeader(
                  institutionName: (institutionName != null && institutionName.isNotEmpty)
                      ? institutionName
                      : 'Eğitim Kurumu',
                  branchName: bName,
                  branchRank: bIdx + 1,
                  totalBranches: branchList.length,
                  examName: examName,
                  examDate: dateStr,
                  classLevel: classLevel ?? '',
                ),
                pw.SizedBox(height: 8),

                // 2. Şube KPI Kartları (4 Kart)
                _buildBranchKpiCards(
                  studentCount: bCount,
                  totalStudents: totalStudents,
                  avgScore: bAvgScore,
                  schoolAvgScore: avgScore,
                  avgNet: bAvgNet,
                  schoolAvgNet: avgNet,
                  topStudentName: topBranchStudentName,
                  topStudentScore: topBranchScore,
                  topStudentCount: topBranchCount,
                ),
                pw.SizedBox(height: 8),

                // 3. Ders Bazlı Şube vs Kurum Karşılaştırma Tablosu (Grafikli)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      "$bName ŞUBESİ DERS GELİŞİM VE KURUM KARŞILAŞTIRMA GRAFİĞİ",
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryDark,
                      ),
                    ),
                    pw.Row(
                      children: [
                        pw.Container(width: 8, height: 8, decoration: pw.BoxDecoration(color: primaryDark, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)))),
                        pw.SizedBox(width: 4),
                        pw.Text("Şube Neti", style: pw.TextStyle(fontSize: 6.5, color: textDark)),
                        pw.SizedBox(width: 8),
                        pw.Container(width: 8, height: 8, decoration: pw.BoxDecoration(color: PdfColors.grey400, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)))),
                        pw.SizedBox(width: 4),
                        pw.Text("Kurum Neti", style: pw.TextStyle(fontSize: 6.5, color: textDark)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                _buildBranchSubjectComparisonChartTable(
                  bSubjectTotals: bSubjectTotals,
                  schoolSubjectTotals: subjectTotals,
                  bStudentCount: bCount,
                  schoolStudentCount: totalStudents,
                ),
                pw.SizedBox(height: 8),

                // 4. Şube Öğrenci Sıralama Listesi
                pw.Text(
                  "$bName ŞUBESİ ÖĞRENCİ BAŞARI SIRALAMASI (${bStudents.length} Öğrenci)",
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryDark,
                  ),
                ),
                pw.SizedBox(height: 4),
                _buildBranchStudentsTable(
                  students: bStudents,
                  allSortedStudents: sortedStudents,
                  branchRanks: bRanks,
                  schoolRanks: allRanks,
                ),
                pw.Spacer(),

                // 5. Footer
                _buildFooter(
                  pageNumber: pageNumber,
                  totalPages: totalPages,
                  branchName: bName,
                ),
              ],
            );
          },
        ),
      );

      // Async loop yielding to prevent freezing in browser
      await Future.delayed(Duration.zero);
    }

    return pdf.save();
  }

  pw.Widget _buildBranchHeader({
    required String institutionName,
    required String branchName,
    required int branchRank,
    required int totalBranches,
    required String examName,
    required String examDate,
    required String classLevel,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: primaryDark,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                institutionName.toUpperCase(),
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                "$branchName ŞUBESİ SINAV SONUÇ VE BAŞARI RAPORU",
                style: pw.TextStyle(
                  color: PdfColor.fromHex('#93C5FD'),
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                examName,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                "$classLevel. Sınıf • Şube Başarı Sırası: $branchRank / $totalBranches • $examDate",
                style: pw.TextStyle(
                  color: PdfColor.fromHex('#E2E8F0'),
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildBranchKpiCards({
    required int studentCount,
    required int totalStudents,
    required double avgScore,
    required double schoolAvgScore,
    required double avgNet,
    required double schoolAvgNet,
    required String topStudentName,
    required double topStudentScore,
    int topStudentCount = 1,
  }) {
    final scoreDiff = avgScore - schoolAvgScore;
    final netDiff = avgNet - schoolAvgNet;

    return pw.Row(
      children: [
        _kpiBox(
          "ŞUBE MEVCUDU",
          "$studentCount",
          primaryDark,
          subtitle: "Kurum: $totalStudents",
        ),
        pw.SizedBox(width: 6),
        _kpiBox(
          "ŞUBE PUAN ORT.",
          avgScore.toStringAsFixed(2),
          scoreDiff >= 0 ? successColor : dangerColor,
          subtitle: "Fark: ${scoreDiff >= 0 ? '+' : ''}${scoreDiff.toStringAsFixed(2)}",
        ),
        pw.SizedBox(width: 6),
        _kpiBox(
          "ŞUBE NET ORT.",
          avgNet.toStringAsFixed(2),
          netDiff >= 0 ? successColor : dangerColor,
          subtitle: "Fark: ${netDiff >= 0 ? '+' : ''}${netDiff.toStringAsFixed(2)}",
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(
          flex: 3,
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FEF3C7'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColor.fromHex('#FDE68A'), width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  "ŞUBE BİRİNCİSİ: ${topStudentScore.toStringAsFixed(2)} Puan",
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#92400E'),
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  topStudentCount > 1
                      ? _topScorersText(topStudentCount, topStudentScore)
                      : topStudentName,
                  maxLines: 2,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#78350F'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildBranchSubjectComparisonChartTable({
    required Map<String, _SubjectAccumulator> bSubjectTotals,
    required Map<String, _SubjectAccumulator> schoolSubjectTotals,
    required int bStudentCount,
    required int schoolStudentCount,
  }) {
    final rows = <pw.TableRow>[];
    int idx = 0;

    bSubjectTotals.forEach((subj, bAcc) {
      final sAcc = schoolSubjectTotals[subj];
      final bCnt = bAcc.count > 0 ? bAcc.count : bStudentCount;
      final sCnt = (sAcc != null && sAcc.count > 0) ? sAcc.count : schoolStudentCount;

      final bAvgC = bCnt > 0 ? bAcc.correct / bCnt : 0.0;
      final bAvgW = bCnt > 0 ? bAcc.wrong / bCnt : 0.0;
      final bAvgE = bCnt > 0 ? bAcc.empty / bCnt : 0.0;
      final bAvgN = bCnt > 0 ? bAcc.net / bCnt : 0.0;
      final sAvgN = (sAcc != null && sCnt > 0) ? sAcc.net / sCnt : 0.0;
      final diff = bAvgN - sAvgN;

      final maxN = [bAvgN, sAvgN, 1.0].reduce((curr, next) => curr > next ? curr : next);
      final bWidth = ((bAvgN / maxN) * 50).clamp(0.0, 50.0);
      final sWidth = ((sAvgN / maxN) * 50).clamp(0.0, 50.0);

      rows.add(
        pw.TableRow(
          decoration: idx % 2 == 1
              ? pw.BoxDecoration(color: PdfColor.fromHex('#F8FAFC'))
              : const pw.BoxDecoration(color: PdfColors.white),
          children: [
            _tableCell(subj, alignLeft: true, isBold: true),
            _tableCell(bAvgC.toStringAsFixed(1), color: successColor),
            _tableCell(bAvgW.toStringAsFixed(1), color: dangerColor),
            _tableCell(bAvgE.toStringAsFixed(1), color: textMuted),
            _tableCell(bAvgN.toStringAsFixed(2), isBold: true, color: primaryDark),
            _tableCell(sAvgN.toStringAsFixed(2), isBold: true, color: textMuted),
            _tableCell(
              "${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(2)}",
              isBold: true,
              color: diff >= 0 ? successColor : dangerColor,
            ),
            // Görsel Mini Çubuk Grafik
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Container(
                    height: 3.5,
                    width: bWidth,
                    decoration: pw.BoxDecoration(
                      color: primaryDark,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                    ),
                  ),
                  pw.SizedBox(height: 1.5),
                  pw.Container(
                    height: 3.5,
                    width: sWidth,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey400,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      idx++;
    });

    return pw.Container(
      decoration: pw.BoxDecoration(
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: borderSoft, width: 0.8),
      ),
      child: pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: borderSoft, width: 0.5)),
        columnWidths: {
          0: const pw.FlexColumnWidth(2.8),
          1: const pw.FlexColumnWidth(1.1),
          2: const pw.FlexColumnWidth(1.1),
          3: const pw.FlexColumnWidth(1.1),
          4: const pw.FlexColumnWidth(1.3),
          5: const pw.FlexColumnWidth(1.3),
          6: const pw.FlexColumnWidth(1.3),
          7: const pw.FixedColumnWidth(58),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F1F5F9'),
              borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(5)),
            ),
            children: [
              _tableCell("DERS", isHeader: true, alignLeft: true),
              _tableCell("DOĞRU", isHeader: true),
              _tableCell("YANLIŞ", isHeader: true),
              _tableCell("BOŞ", isHeader: true),
              _tableCell("ŞUBE NET", isHeader: true),
              _tableCell("KURUM NET", isHeader: true),
              _tableCell("FARK", isHeader: true),
              _tableCell("GRAFİK", isHeader: true),
            ],
          ),
          ...rows,
        ],
      ),
    );
  }

  String _resolveStudentNo(Map<String, dynamic> s) {
    dynamic val = s['studentNo'];
    if (val == null || val.toString().trim().isEmpty) val = s['studentNumber'];
    if (val == null || val.toString().trim().isEmpty) val = s['no'];
    if (val == null || val.toString().trim().isEmpty) val = s['number'];
    if (val == null || val.toString().trim().isEmpty) val = s['schoolNumber'];
    if (val == null || val.toString().trim().isEmpty) val = s['ogrNo'];
    if (val == null || val.toString().trim().isEmpty) {
      if (s['raw'] != null && s['raw'] is Map) {
        final raw = s['raw'] as Map;
        val = raw['studentNo'] ??
            raw['studentNumber'] ??
            raw['no'] ??
            raw['number'] ??
            raw['schoolNumber'] ??
            raw['ogrNo'];
      }
    }
    final str = val?.toString().trim() ?? '';
    return str.isNotEmpty ? str : '-';
  }

  pw.Widget _buildBranchStudentsTable({
    required List<Map<String, dynamic>> students,
    required List<Map<String, dynamic>> allSortedStudents,
    required List<int> branchRanks,
    required List<int> schoolRanks,
  }) {
    final rows = <pw.TableRow>[];
    final totalInSchool = allSortedStudents.length;
    final isCompact = students.length > 25;
    final rowPadV = isCompact ? 1.5 : 2.2;
    final fontSize = isCompact ? 6.5 : 7.0;

    for (int i = 0; i < students.length; i++) {
      final s = students[i];
      final name = (s['studentName'] ?? s['name'] ?? '-').toString();
      final no = _resolveStudentNo(s);
      final score = num.tryParse(s['totalScore']?.toString() ?? '0')?.toDouble() ?? 0.0;
      final net = num.tryParse(s['totalNet']?.toString() ?? '0')?.toDouble() ?? 0.0;

      int totalD = 0;
      int totalY = 0;
      int totalB = 0;
      if (s['subjects'] != null && s['subjects'] is Map) {
        final subMap = s['subjects'] as Map;
        subMap.forEach((_, v) {
          if (v is Map) {
            totalD += int.tryParse(v['correct']?.toString() ?? '0') ?? 0;
            totalY += int.tryParse(v['wrong']?.toString() ?? '0') ?? 0;
            totalB += int.tryParse(v['empty']?.toString() ?? '0') ?? 0;
          }
        });
      }

      final schoolIdx = allSortedStudents.indexOf(s);
      final schoolRank = (schoolIdx >= 0 && schoolIdx < schoolRanks.length) ? schoolRanks[schoolIdx] : 0;

      rows.add(
        pw.TableRow(
          decoration: i % 2 == 1
              ? pw.BoxDecoration(color: PdfColor.fromHex('#F8FAFC'))
              : const pw.BoxDecoration(color: PdfColors.white),
          children: [
            _branchStudentCell("${branchRanks[i]}", isBold: branchRanks[i] <= 3, color: branchRanks[i] == 1 ? warningColor : null, vPad: rowPadV, fontSize: fontSize),
            _branchStudentCell(no, vPad: rowPadV, fontSize: fontSize),
            _branchStudentCell(name, alignLeft: true, isBold: true, vPad: rowPadV, fontSize: fontSize),
            _branchStudentCell("$totalD", color: successColor, vPad: rowPadV, fontSize: fontSize),
            _branchStudentCell("$totalY", color: dangerColor, vPad: rowPadV, fontSize: fontSize),
            _branchStudentCell("$totalB", color: textMuted, vPad: rowPadV, fontSize: fontSize),
            _branchStudentCell(net.toStringAsFixed(2), isBold: true, vPad: rowPadV, fontSize: fontSize),
            _branchStudentCell(score.toStringAsFixed(2), isBold: true, color: primaryDark, vPad: rowPadV, fontSize: fontSize),
            _branchStudentCell(schoolRank > 0 ? "$schoolRank / $totalInSchool" : "-", isBold: true, vPad: rowPadV, fontSize: fontSize),
          ],
        ),
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: borderSoft, width: 0.8),
      ),
      child: pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: borderSoft, width: 0.5)),
        columnWidths: {
          0: const pw.FixedColumnWidth(34),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(3.8),
          3: const pw.FlexColumnWidth(1.0),
          4: const pw.FlexColumnWidth(1.0),
          5: const pw.FlexColumnWidth(1.0),
          6: const pw.FlexColumnWidth(1.4),
          7: const pw.FlexColumnWidth(1.5),
          8: const pw.FlexColumnWidth(1.6),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F1F5F9'),
              borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(5)),
            ),
            children: [
              _tableCell("SIRA", isHeader: true),
              _tableCell("NO", isHeader: true),
              _tableCell("ÖĞRENCİ ADI SOYADI", isHeader: true, alignLeft: true),
              _tableCell("DOĞRU", isHeader: true),
              _tableCell("YANLIŞ", isHeader: true),
              _tableCell("BOŞ", isHeader: true),
              _tableCell("NET", isHeader: true),
              _tableCell("PUAN", isHeader: true),
              _tableCell("KURUM SIRASI", isHeader: true),
            ],
          ),
          ...rows,
        ],
      ),
    );
  }

  pw.Widget _branchStudentCell(
    String text, {
    bool isBold = false,
    bool alignLeft = false,
    PdfColor? color,
    double vPad = 2.5,
    double fontSize = 7.0,
  }) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: 3, vertical: vPad),
      child: pw.Text(
        text,
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.center,
        maxLines: 1,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? textDark,
        ),
      ),
    );
  }

  pw.Widget _buildInstitutionHeader({
    required String institutionName,
    required String examName,
    required String examDate,
    required String classLevel,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: primaryDark,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                institutionName.toUpperCase(),
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                "KURUM SINAV SONUÇ VE BAŞARI KARNESİ",
                style: pw.TextStyle(
                  color: PdfColor.fromHex('#93C5FD'),
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                examName,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                "$classLevel. Sınıf • $examDate",
                style: pw.TextStyle(
                  color: PdfColor.fromHex('#E2E8F0'),
                  fontSize: 8.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildInstitutionKpiCards({
    required int totalStudents,
    required int totalBranches,
    required double avgScore,
    required double avgNet,
    required double maxScore,
    required String topStudentName,
    required String topStudentBranch,
    int topStudentCount = 1,
  }) {
    return pw.Row(
      children: [
        _kpiBox("Katılan Öğrenci", "$totalStudents", primaryDark),
        pw.SizedBox(width: 6),
        _kpiBox("Şube Sayısı", "$totalBranches", primaryLight),
        pw.SizedBox(width: 6),
        _kpiBox("Kurum Puan Ort.", avgScore.toStringAsFixed(2), accentColor),
        pw.SizedBox(width: 6),
        _kpiBox("Kurum Net Ort.", avgNet.toStringAsFixed(2), successColor),
        pw.SizedBox(width: 6),
        pw.Expanded(
          flex: 3,
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FEF3C7'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColor.fromHex('#FDE68A'), width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "EN YÜKSEK PUAN: ${maxScore.toStringAsFixed(2)}",
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#92400E'),
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  topStudentCount > 1
                      ? _topScorersText(topStudentCount, maxScore)
                      : "$topStudentName ($topStudentBranch)",
                  maxLines: 2,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#78350F'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _kpiBox(String title, String value, PdfColor color, {String? subtitle}) {
    return pw.Expanded(
      flex: 2,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: pw.BoxDecoration(
          color: bgCard,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          border: pw.Border.all(color: borderSoft, width: 0.8),
        ),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 6.5, color: textMuted),
              maxLines: 1,
            ),
            pw.SizedBox(height: 1),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
            if (subtitle != null) ...[
              pw.SizedBox(height: 1),
              pw.Text(
                subtitle,
                style: pw.TextStyle(fontSize: 5.5, color: textMuted),
                maxLines: 1,
              ),
            ],
          ],
        ),
      ),
    );
  }

  pw.Widget _buildBranchComparisonTable({
    required Map<String, List<Map<String, dynamic>>> byBranch,
    required List<String> sortedBranches,
    required List<String> subjects,
    required double avgSchoolScore,
    required double avgSchoolNet,
  }) {
    final rows = <pw.TableRow>[];

    for (int i = 0; i < sortedBranches.length; i++) {
      final bName = sortedBranches[i];
      final list = byBranch[bName]!;
      final count = list.length;
      final sumSc = list.fold<double>(0, (prev, e) => prev + (num.tryParse(e['totalScore']?.toString() ?? '0') ?? 0));
      final sumN = list.fold<double>(0, (prev, e) => prev + (num.tryParse(e['totalNet']?.toString() ?? '0') ?? 0));
      final avgSc = count > 0 ? sumSc / count : 0.0;
      final avgN = count > 0 ? sumN / count : 0.0;

      rows.add(
        pw.TableRow(
          decoration: i % 2 == 1
              ? pw.BoxDecoration(color: PdfColor.fromHex('#F8FAFC'))
              : const pw.BoxDecoration(color: PdfColors.white),
          children: [
            _tableCell("${i + 1}"),
            _tableCell(bName, alignLeft: true, isBold: true),
            _tableCell("$count"),
            _tableCell(avgN.toStringAsFixed(2), isBold: true),
            _tableCell(avgSc.toStringAsFixed(2), isBold: true, color: primaryDark),
          ],
        ),
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: borderSoft, width: 0.8),
      ),
      child: pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: borderSoft, width: 0.5)),
        columnWidths: {
          0: const pw.FixedColumnWidth(36),
          1: const pw.FlexColumnWidth(3),
          2: const pw.FlexColumnWidth(1.5),
          3: const pw.FlexColumnWidth(2),
          4: const pw.FlexColumnWidth(2),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F1F5F9'),
              borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(5)),
            ),
            children: [
              _tableCell("SIRA", isHeader: true),
              _tableCell("ŞUBE ADI", isHeader: true, alignLeft: true),
              _tableCell("ÖĞRENCİ", isHeader: true),
              _tableCell("NET ORT.", isHeader: true),
              _tableCell("PUAN ORT.", isHeader: true),
            ],
          ),
          ...rows,
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#E0E7FF'),
              borderRadius: const pw.BorderRadius.vertical(bottom: pw.Radius.circular(5)),
            ),
            children: [
              _tableCell(""),
              _tableCell("OKUL GENELİ", alignLeft: true, isBold: true, color: primaryDark),
              _tableCell("${byBranch.values.fold<int>(0, (p, l) => p + l.length)}", isBold: true, color: primaryDark),
              _tableCell(avgSchoolNet.toStringAsFixed(2), isBold: true, color: primaryDark),
              _tableCell(avgSchoolScore.toStringAsFixed(2), isBold: true, color: primaryDark),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSubjectSummaryTable(
    Map<String, _SubjectAccumulator> subjectTotals,
    int totalStudents,
  ) {
    final rows = <pw.TableRow>[];
    int idx = 0;

    subjectTotals.forEach((subj, acc) {
      final count = acc.count > 0 ? acc.count : totalStudents;
      final avgC = count > 0 ? acc.correct / count : 0.0;
      final avgW = count > 0 ? acc.wrong / count : 0.0;
      final avgE = count > 0 ? acc.empty / count : 0.0;
      final avgN = count > 0 ? acc.net / count : 0.0;
      final totalQ = avgC + avgW + avgE;
      final succ = totalQ > 0 ? (avgC / totalQ) * 100 : 0.0;

      rows.add(
        pw.TableRow(
          decoration: idx % 2 == 1
              ? pw.BoxDecoration(color: PdfColor.fromHex('#F8FAFC'))
              : const pw.BoxDecoration(color: PdfColors.white),
          children: [
            _tableCell(subj, alignLeft: true, isBold: true),
            _tableCell(avgC.toStringAsFixed(1), color: successColor),
            _tableCell(avgW.toStringAsFixed(1), color: dangerColor),
            _tableCell(avgE.toStringAsFixed(1), color: textMuted),
            _tableCell(avgN.toStringAsFixed(2), isBold: true, color: primaryDark),
            _tableCell("%${succ.toStringAsFixed(0)}", isBold: true),
          ],
        ),
      );
      idx++;
    });

    return pw.Container(
      decoration: pw.BoxDecoration(
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: borderSoft, width: 0.8),
      ),
      child: pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: borderSoft, width: 0.5)),
        columnWidths: {
          0: const pw.FlexColumnWidth(3),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(1.2),
          3: const pw.FlexColumnWidth(1.2),
          4: const pw.FlexColumnWidth(1.5),
          5: const pw.FlexColumnWidth(1.5),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F1F5F9'),
              borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(5)),
            ),
            children: [
              _tableCell("DERS", isHeader: true, alignLeft: true),
              _tableCell("D. ORT", isHeader: true),
              _tableCell("Y. ORT", isHeader: true),
              _tableCell("B. ORT", isHeader: true),
              _tableCell("NET ORT.", isHeader: true),
              _tableCell("BAŞARI", isHeader: true),
            ],
          ),
          ...rows,
        ],
      ),
    );
  }

  /// Puana göre azalan sıralanmış liste için sıra numaraları üretir.
  /// Aynı puanı alanlar aynı sırayı alır (1,1,1,4...).
  List<int> _competitionRanks(List<Map<String, dynamic>> sorted) {
    final ranks = <int>[];
    int? prevKey;
    int current = 0;
    for (int i = 0; i < sorted.length; i++) {
      final key = _scoreKey(sorted[i]);
      if (prevKey == null || key != prevKey) current = i + 1;
      ranks.add(current);
      prevKey = key;
    }
    return ranks;
  }

  int _scoreKey(Map<String, dynamic> s) {
    final score = num.tryParse(s['totalScore']?.toString() ?? '0')?.toDouble() ?? 0.0;
    return (score * 100).round();
  }

  /// En yüksek puanı alan öğrenci sayısı.
  int _countTopScorers(List<Map<String, dynamic>> students) {
    if (students.isEmpty) return 0;
    int maxKey = _scoreKey(students.first);
    for (var s in students) {
      final k = _scoreKey(s);
      if (k > maxKey) maxKey = k;
    }
    return students.where((s) => _scoreKey(s) == maxKey).length;
  }

  String _topScorersText(int count, double score) {
    return "$count öğrenci en yüksek puanı aldı";
  }

  pw.Widget _buildTopStudentsTable(List<Map<String, dynamic>> students, List<int> ranks) {
    if (students.length <= 10) {
      return _buildTopStudentsSingleTable(students, ranks);
    }

    // 10'dan fazla öğrenci (eşit puanlar) varsa çift sütun halinde göster.
    const maxShown = 40;
    final shown = students.take(maxShown).toList();
    final hidden = students.length - shown.length;
    final half = (shown.length + 1) ~/ 2;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _buildTopStudentsCompactTable(shown.sublist(0, half), ranks.sublist(0, half)),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: _buildTopStudentsCompactTable(
                shown.sublist(half),
                ranks.sublist(half, shown.length),
              ),
            ),
          ],
        ),
        if (hidden > 0)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Text(
              "... ve aynı sıradaki $hidden öğrenci daha",
              style: pw.TextStyle(fontSize: 6.5, color: textMuted),
            ),
          ),
      ],
    );
  }

  pw.Widget _buildTopStudentsCompactTable(List<Map<String, dynamic>> students, List<int> ranks) {
    final rows = <pw.TableRow>[];
    for (int i = 0; i < students.length; i++) {
      final s = students[i];
      final name = (s['studentName'] ?? s['name'] ?? '-').toString();
      final branch = (s['className'] ?? s['branch'] ?? '-').toString();
      final score = num.tryParse(s['totalScore']?.toString() ?? '0')?.toDouble() ?? 0.0;
      final net = num.tryParse(s['totalNet']?.toString() ?? '0')?.toDouble() ?? 0.0;
      rows.add(
        pw.TableRow(
          decoration: i % 2 == 1
              ? pw.BoxDecoration(color: PdfColor.fromHex('#F8FAFC'))
              : const pw.BoxDecoration(color: PdfColors.white),
          children: [
            _branchStudentCell("${ranks[i]}", isBold: ranks[i] <= 3, color: ranks[i] == 1 ? warningColor : null, vPad: 1.5, fontSize: 6.5),
            _branchStudentCell(name, alignLeft: true, isBold: true, vPad: 1.5, fontSize: 6.5),
            _branchStudentCell(branch, vPad: 1.5, fontSize: 6.5),
            _branchStudentCell(net.toStringAsFixed(2), isBold: true, vPad: 1.5, fontSize: 6.5),
            _branchStudentCell(score.toStringAsFixed(2), isBold: true, color: primaryDark, vPad: 1.5, fontSize: 6.5),
          ],
        ),
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: borderSoft, width: 0.8),
      ),
      child: pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: borderSoft, width: 0.5)),
        columnWidths: {
          0: const pw.FixedColumnWidth(24),
          1: const pw.FlexColumnWidth(4),
          2: const pw.FlexColumnWidth(1.3),
          3: const pw.FlexColumnWidth(1.5),
          4: const pw.FlexColumnWidth(1.6),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F1F5F9'),
              borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(5)),
            ),
            children: [
              _branchStudentCell("SIRA", isBold: true, vPad: 2, fontSize: 6.5),
              _branchStudentCell("ÖĞRENCİ ADI SOYADI", alignLeft: true, isBold: true, vPad: 2, fontSize: 6.5),
              _branchStudentCell("ŞUBE", isBold: true, vPad: 2, fontSize: 6.5),
              _branchStudentCell("NET", isBold: true, vPad: 2, fontSize: 6.5),
              _branchStudentCell("PUAN", isBold: true, vPad: 2, fontSize: 6.5),
            ],
          ),
          ...rows,
        ],
      ),
    );
  }

  pw.Widget _buildTopStudentsSingleTable(List<Map<String, dynamic>> top10, List<int> ranks) {
    final rows = <pw.TableRow>[];

    for (int i = 0; i < top10.length; i++) {
      final s = top10[i];
      final name = (s['studentName'] ?? s['name'] ?? '-').toString();
      final no = _resolveStudentNo(s);
      final branch = (s['className'] ?? s['branch'] ?? '-').toString();
      final score = num.tryParse(s['totalScore']?.toString() ?? '0')?.toDouble() ?? 0.0;
      final net = num.tryParse(s['totalNet']?.toString() ?? '0')?.toDouble() ?? 0.0;

      rows.add(
        pw.TableRow(
          decoration: i % 2 == 1
              ? pw.BoxDecoration(color: PdfColor.fromHex('#F8FAFC'))
              : const pw.BoxDecoration(color: PdfColors.white),
          children: [
            _tableCell("${ranks[i]}", isBold: ranks[i] <= 3, color: ranks[i] == 1 ? warningColor : null),
            _tableCell(no),
            _tableCell(name, alignLeft: true, isBold: true),
            _tableCell(branch),
            _tableCell(net.toStringAsFixed(2), isBold: true),
            _tableCell(score.toStringAsFixed(2), isBold: true, color: primaryDark),
          ],
        ),
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: borderSoft, width: 0.8),
      ),
      child: pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: borderSoft, width: 0.5)),
        columnWidths: {
          0: const pw.FixedColumnWidth(36),
          1: const pw.FlexColumnWidth(1.5),
          2: const pw.FlexColumnWidth(3.5),
          3: const pw.FlexColumnWidth(1.5),
          4: const pw.FlexColumnWidth(2),
          5: const pw.FlexColumnWidth(2),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F1F5F9'),
              borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(5)),
            ),
            children: [
              _tableCell("SIRA", isHeader: true),
              _tableCell("NO", isHeader: true),
              _tableCell("ÖĞRENCİ ADI SOYADI", isHeader: true, alignLeft: true),
              _tableCell("ŞUBE", isHeader: true),
              _tableCell("NET", isHeader: true),
              _tableCell("PUAN", isHeader: true),
            ],
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _TopicStat {
  int total = 0;
  int correct = 0;
  int wrong = 0;
  int empty = 0;
}

class _SubjectAccumulator {
  int correct = 0;
  int wrong = 0;
  int empty = 0;
  double net = 0.0;
  int count = 0;
}
