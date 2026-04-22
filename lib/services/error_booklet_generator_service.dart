import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../../../models/assessment/trial_exam_model.dart';

class ErrorBookletGeneratorService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> generateAndDownloadBooklet({
    required List<TrialExam> exams,
    required List<Map<String, dynamic>> studentResults,
  }) async {
    try {
      final pdf = pw.Document();
      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();

      if (studentResults.isEmpty) return;
      final studentName = studentResults.first['studentName'] ?? studentResults.first['name'] ?? 'Öğrenci';

      // Composite Data Structures
      Map<String, List<Map<String, dynamic>>> compositeGrouped = {};
      Map<String, Map<String, int>> stats = {}; 

      for (int i = 0; i < exams.length; i++) {
        final exam = exams[i];
        final result = studentResults[i];
        if (result.isEmpty) continue;
        
        final booklet = result['booklet'] ?? 'A';
        final studentAnswersRaw = result['answers'] ?? result['cevaplar'];
        Map<String, String> studentAnswersMap = {};
        if (studentAnswersRaw is Map) {
          studentAnswersRaw.forEach((k, v) => studentAnswersMap[k.toString()] = v.toString());
        }

        final refAnswers = exam.answerKeys[booklet];
        if (refAnswers == null) continue;

        final poolSnap = await _firestore
            .collection('trial_exams')
            .doc(exam.id)
            .collection('questions_pool')
            .get();
        
        Map<String, Map<String, dynamic>> poolMap = {};
        for (var doc in poolSnap.docs) {
          final data = doc.data();
          poolMap['${data['subject']}_${data['questionNo']}'] = data;
        }

        for (var subject in studentAnswersMap.keys) {
          final sAns = studentAnswersMap[subject] ?? '';
          final rAns = refAnswers[subject] ?? '';
          
          stats.putIfAbsent(subject, () => {'T': 0, 'C': 0, 'W': 0, 'E': 0});
          
          for (int j = 0; j < rAns.length; j++) {
            final sChar = j < sAns.length ? sAns[j] : ' ';
            final rChar = rAns[j];
            final status = TrialExam.evaluateAnswer(sChar, rChar);

            stats[subject]!['T'] = stats[subject]!['T']! + 1;
            if (status == AnswerStatus.correct) {
              stats[subject]!['C'] = stats[subject]!['C']! + 1;
            } else if (status == AnswerStatus.wrong) {
              stats[subject]!['W'] = stats[subject]!['W']! + 1;
            } else {
              stats[subject]!['E'] = stats[subject]!['E']! + 1;
            }

            if (status != AnswerStatus.correct) {
              final qNo = j + 1;
              final meta = poolMap['${subject}_$qNo'];

              if (meta != null) {
                Uint8List? bytes;
                if (meta['base64Image'] != null) {
                  try { bytes = base64Decode(meta['base64Image']); } catch (_) {}
                } else if (meta['imageUrl'] != null) {
                  try {
                    final response = await http.get(Uri.parse(meta['imageUrl']));
                    if (response.statusCode == 200) bytes = response.bodyBytes;
                  } catch (_) {}
                }

                if (bytes != null) {
                  compositeGrouped.putIfAbsent(subject, () => []).add({
                    'examName': exam.name,
                    'questionNo': qNo,
                    'imageBytes': bytes,
                    'isWide': meta['isWide'] ?? false,
                    'correctAnswer': meta['correctAnswer'] ?? rChar,
                  });
                }
              }
            }
          }
        }
      }

      final lgsOrder = ['türkçe', 'sosyal', 'inkılap', 'din', 'ingilizce', 'yabancı', 'matematik', 'fen'];
      int getSubjectOrder(String s) {
        final lower = s.toLowerCase();
        for (int i = 0; i < lgsOrder.length; i++) {
          if (lower.contains(lgsOrder[i])) return i;
        }
        return 99;
      }

      final sortedSubjects = stats.keys.toList()
        ..sort((a, b) => getSubjectOrder(a).compareTo(getSubjectOrder(b)));

      // 1. General Cover Page
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.indigo900, width: 3)),
            child: pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.indigo900, width: 1)),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                   pw.Text('KİŞİSEL HATA KİTAPÇIĞI', style: pw.TextStyle(font: fontBold, fontSize: 32, color: PdfColors.indigo900)),
                  pw.SizedBox(height: 10),
                  pw.Container(width: 150, height: 2, color: PdfColors.indigo900),
                  pw.SizedBox(height: 30),
                  pw.Text(studentName.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 24)),
                  pw.SizedBox(height: 50),
                  pw.Text('SINAV BİLGİLERİ', style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.grey700)),
                  for (var exam in exams) pw.Text('• ${exam.name}', style: pw.TextStyle(font: font, fontSize: 11)),
                  pw.SizedBox(height: 50),
                  pw.Text('GENEL PERFORMANS ANALİZİ', style: pw.TextStyle(font: fontBold, fontSize: 15, color: PdfColors.indigo900)),
                  pw.SizedBox(height: 15),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                    columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1), 3: const pw.FlexColumnWidth(1), 4: const pw.FlexColumnWidth(1)},
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.indigo50),
                        children: [_cell('DERS ADI', fontBold, isHeader: true), _cell('SORU', fontBold, isHeader: true), _cell('D', fontBold, isHeader: true), _cell('Y', fontBold, isHeader: true), _cell('B', fontBold, isHeader: true)],
                      ),
                      for (var subject in sortedSubjects)
                        pw.TableRow(
                          children: [
                            _cell(subject, font),
                            _cell('${stats[subject]!['T']}', font),
                            _cell('${stats[subject]!['C']}', font),
                            _cell('${stats[subject]!['W']}', font, color: PdfColors.red),
                            _cell('${stats[subject]!['E']}', font, color: PdfColors.orange),
                          ],
                        ),
                    ],
                  ),
                  pw.Spacer(),
                  pw.Text('eduKN Eğitim Teknolojileri', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)),
                ],
              ),
            ),
          ),
        ),
      );

      // 2. Subject Sections
      for (var subject in sortedSubjects) {
        if (!compositeGrouped.containsKey(subject)) continue;
        final questions = compositeGrouped[subject]!;
        final sStat = stats[subject] ?? {'T': 0, 'C': 0, 'W': 0, 'E': 0};
        
        // Premium Intro Page
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (ctx) => pw.Container(
              padding: const pw.EdgeInsets.all(32),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Spacer(),
                  pw.Container(
                    width: double.infinity,
                    child: pw.Column(
                      children: [
                        pw.Text(subject.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 44, color: PdfColors.indigo900, letterSpacing: 2.5)),
                        pw.SizedBox(height: 12),
                        pw.Container(height: 2, width: 300, color: PdfColors.indigo900),
                        pw.SizedBox(height: 5, width: 150, child: pw.Divider(color: PdfColors.indigo200)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 60),
                  pw.Container(
                    width: 400,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.indigo50.shade(0.2),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20)),
                      border: pw.Border.all(color: PdfColors.indigo100, width: 1.5),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                      children: [
                        _statCard('SORU', '${sStat['T']}', PdfColors.indigo900, fontBold, font),
                        _statCard('DOĞRU', '${sStat['C']}', PdfColors.green800, fontBold, font),
                        _statCard('YANLIŞ', '${sStat['W']}', PdfColors.red800, fontBold, font),
                        _statCard('BOŞ', '${sStat['E']}', PdfColors.orange800, fontBold, font),
                      ],
                    ),
                  ),
                  pw.Spacer(),
                  pw.Text('Kişisel Analiz ve Hata Kitapçığı', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey500)),
                ],
              ),
            ),
          ),
        );

        // Questions
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            header: (ctx) => pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 15),
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.indigo900, width: 2))),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(subject.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.indigo900)),
                  pw.Text('$studentName | eduKN', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
            ),
            build: (ctx) {
              List<pw.Widget> widgets = [];
              List<Map<String, dynamic>> currentRow = [];
              for (var q in questions) {
                if (q['isWide'] == true) {
                  if (currentRow.isNotEmpty) {
                    widgets.add(_buildRow(currentRow, fontBold, font));
                    currentRow = [];
                  }
                  widgets.add(_buildFullWidth(q, fontBold, font));
                  widgets.add(pw.SizedBox(height: 25));
                } else {
                  currentRow.add(q);
                  if (currentRow.length == 2) {
                    widgets.add(_buildRow(currentRow, fontBold, font));
                    widgets.add(pw.SizedBox(height: 25));
                    currentRow = [];
                  }
                }
              }
              if (currentRow.isNotEmpty) widgets.add(_buildRow(currentRow, fontBold, font));
              return widgets;
            },
          ),
        );
      }

      // 3. Final Answer Key Page
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Container(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(child: pw.Text('CEVAP ANAHTARI', style: pw.TextStyle(font: fontBold, fontSize: 24, color: PdfColors.indigo900))),
                pw.SizedBox(height: 10),
                pw.Center(child: pw.Container(width: 100, height: 2, color: PdfColors.indigo900)),
                pw.SizedBox(height: 30),
                
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    for (var subject in sortedSubjects)
                      if (compositeGrouped.containsKey(subject))
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 20),
                          child: _buildSubjectAnswerKey(subject, compositeGrouped[subject]!, fontBold, font),
                        ),
                  ],
                ),
                pw.Spacer(),
                pw.Center(child: pw.Text('www.edukn.com', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey500))),
              ],
            ),
          ),
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) => pdf.save(),
        name: '$studentName - Karma Hata Kitapçığı.pdf',
      );
    } catch (e) {
      print('Composite PDF Error: $e');
    }
  }

  pw.Widget _buildSubjectAnswerKey(String subject, List<Map<String, dynamic>> questions, pw.Font bold, pw.Font reg) {
    final sortedQ = List<Map<String, dynamic>>.from(questions)..sort((a, b) => (a['questionNo'] as int).compareTo(b['questionNo'] as int));
    
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 1)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: const pw.BoxDecoration(color: PdfColors.indigo900, borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
                child: pw.Text(subject.toUpperCase(), style: pw.TextStyle(font: bold, fontSize: 10, color: PdfColors.white)),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(child: pw.Divider(color: PdfColors.indigo100, thickness: 0.5)),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Wrap(
            spacing: 20,
            runSpacing: 10,
            children: sortedQ.map((q) => pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('${q['questionNo']}.', style: pw.TextStyle(font: reg, fontSize: 10, color: PdfColors.grey600)),
                pw.SizedBox(width: 4),
                pw.Text('${q['correctAnswer']}', style: pw.TextStyle(font: bold, fontSize: 11, color: PdfColors.black)),
              ],
            )).toList(),
          ),
        ],
      ),
    );
  }

  pw.Widget _cell(String text, pw.Font font, {bool isHeader = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Center(child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: isHeader ? 9 : 8, color: color ?? (isHeader ? PdfColors.indigo900 : PdfColors.black)))),
    );
  }

  pw.Widget _statCard(String label, String value, PdfColor color, pw.Font bold, pw.Font reg) {
    return pw.Column(
      children: [
        pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 7, color: color.shade(0.7), letterSpacing: 0.5)),
        pw.SizedBox(height: 5),
        pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 20, color: color)),
      ],
    );
  }

  pw.Widget _questionHeader(Map<String, dynamic> q, pw.Font bold, {bool isNarrow = false}) {
    final headerWidth = isNarrow ? 230.0 : 480.0;
    return pw.Container(
      width: headerWidth,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const pw.BoxDecoration(color: PdfColors.indigo50, border: pw.Border(left: pw.BorderSide(color: PdfColors.indigo900, width: 3))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.SizedBox(
            width: headerWidth * 0.7,
            child: pw.Text('${q['examName']} - ${q['questionNo']}. Soru', style: pw.TextStyle(font: bold, fontSize: isNarrow ? 8 : 10, color: PdfColors.indigo900)),
          ),
          pw.Text('eduKN', style: pw.TextStyle(font: bold, fontSize: isNarrow ? 7 : 8, color: PdfColors.indigo200)),
        ],
      ),
    );
  }

  pw.Widget _buildFullWidth(Map<String, dynamic> q, pw.Font bold, pw.Font reg) {
    return pw.Table(
      children: [
        pw.TableRow(
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _questionHeader(q, bold),
                pw.SizedBox(height: 10),
                pw.Center(child: pw.Image(pw.MemoryImage(q['imageBytes']), width: 480)),
                pw.SizedBox(height: 15),
                pw.Divider(color: PdfColors.grey100, thickness: 0.5),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildRow(List<Map<String, dynamic>> items, pw.Font bold, pw.Font reg) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _buildHalfWidth(items[0], bold, reg)),
        if (items.length > 1) ...[
          pw.SizedBox(width: 20),
          pw.Expanded(child: _buildHalfWidth(items[1], bold, reg)),
        ] else pw.Expanded(child: pw.SizedBox()),
      ],
    );
  }

  pw.Widget _buildHalfWidth(Map<String, dynamic> q, pw.Font bold, pw.Font reg) {
    return pw.Table(
      children: [
        pw.TableRow(
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _questionHeader(q, bold, isNarrow: true),
                pw.SizedBox(height: 8),
                pw.Image(pw.MemoryImage(q['imageBytes']), fit: pw.BoxFit.contain, width: 230),
                pw.SizedBox(height: 15),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
