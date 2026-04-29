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
    await generateBulkBooklets(exams: exams, bulkStudentResults: [studentResults]);
  }

  Future<void> generateBulkBooklets({
    required List<TrialExam> exams,
    required List<List<Map<String, dynamic>>> bulkStudentResults,
  }) async {
    try {
      // 1. Restore Unicode support for Turkish characters with robust loading
      late pw.Font font;
      late pw.Font fontBold;
      try {
        font = await PdfGoogleFonts.robotoRegular().timeout(const Duration(seconds: 5));
        fontBold = await PdfGoogleFonts.robotoBold().timeout(const Duration(seconds: 5));
      } catch (e) {
        print('Font Load Timeout: Falling back to Helvetica');
        font = pw.Font.helvetica();
        fontBold = pw.Font.helveticaBold();
      }

      if (bulkStudentResults.isEmpty || exams.isEmpty) return;
      final pdf = pw.Document();

      // 2. Pre-fetch Data & Metadata
      Map<String, Map<String, Map<String, dynamic>>> allPoolMaps = {};
      Map<String, List<String>> allTypeOrders = {};

      try {
        for (var exam in exams) {
          final poolSnap = await _firestore.collection('trial_exams').doc(exam.id).collection('questions_pool').get().timeout(const Duration(seconds: 10));
          Map<String, Map<String, dynamic>> poolMap = {};
          for (var qDoc in poolSnap.docs) {
            final data = qDoc.data();
            // Normalize key to ensure perfect matching
            final String sKey = (data['subject'] ?? '').toString().toLowerCase().trim();
            final String nKey = (data['questionNo'] ?? '').toString();
            poolMap['${sKey}_$nKey'] = data;
          }
          allPoolMaps[exam.id] = poolMap;

          final String tId = exam.examTypeId;
          if (tId.isNotEmpty && !allTypeOrders.containsKey(tId)) {
            final tSnap = await _firestore.collection('exam_types').doc(tId).get().timeout(const Duration(seconds: 5));
            if (tSnap.exists) {
              final subjectsRaw = tSnap.data()?['subjects'] as List<dynamic>?;
              if (subjectsRaw != null) {
                allTypeOrders[tId] = subjectsRaw
                    .map((s) => (s['branchName'] ?? '').toString().toLowerCase().trim())
                    .toList();
              }
            }
          }
        }
      } catch (e) {
        print('Pre-fetch Data Warning: $e');
      }

      // 3. Process Students
      for (var studentResults in bulkStudentResults) {
        try {
          if (studentResults.isEmpty) continue;
          final Map<String, dynamic> firstValid = studentResults.firstWhere((r) => r.isNotEmpty, orElse: () => {});
          if (firstValid.isEmpty) continue;

          final String studentName = (firstValid['studentName'] ?? firstValid['name'] ?? 'Öğrenci').toString();
          Map<String, List<Map<String, dynamic>>> compositeGrouped = {};
          Map<String, Map<String, dynamic>> stats = {}; // subject -> {T, C, W, E, Net}

          for (int i = 0; i < exams.length; i++) {
            final exam = exams[i];
            if (i >= studentResults.length) continue;
            final result = studentResults[i];
            if (result == null || result is! Map || result.isEmpty) continue;
            
            final String booklet = result['booklet']?.toString() ?? 'A';
            final Map<String, String> studentAnswersMap = {};
            final dynamic sAnsRaw = result['answers'] ?? result['cevaplar'];
            if (sAnsRaw is Map) sAnsRaw.forEach((k, v) => studentAnswersMap[k.toString()] = v.toString());

            final Map<String, Map<String, dynamic>> poolMap = allPoolMaps[exam.id] ?? {};
            final Map<String, dynamic> backendSubjects = result['subjects'] as Map<String, dynamic>? ?? {};

            for (var subject in studentAnswersMap.keys) {
              final String normSubject = subject.toLowerCase().trim();
              final String sAns = studentAnswersMap[subject] ?? '';
              
              stats.putIfAbsent(subject, () => {'T': 0, 'C': 0, 'W': 0, 'E': 0, 'Net': 0.0});
              
              final dynamic bs = backendSubjects[subject];
              int expectedC = -1;
              if (bs != null && bs is Map) {
                expectedC = (num.tryParse(bs['correct']?.toString() ?? '0') ?? 0).toInt();
                stats[subject]!['T'] = (stats[subject]!['T'] as int) + expectedC + 
                                       (num.tryParse(bs['wrong']?.toString() ?? '0') ?? 0).toInt() + 
                                       (num.tryParse(bs['empty']?.toString() ?? '0') ?? 0).toInt();
                stats[subject]!['C'] = (stats[subject]!['C'] as int) + expectedC;
                stats[subject]!['W'] = (stats[subject]!['W'] as int) + (num.tryParse(bs['wrong']?.toString() ?? '0') ?? 0).toInt();
                stats[subject]!['E'] = (stats[subject]!['E'] as int) + (num.tryParse(bs['empty']?.toString() ?? '0') ?? 0).toInt();
              }

              // SMART BOOKLET PICKER (Brute Force to match expected Correct count)
              String rAns = exam.answerKeys[booklet]?[subject] ?? exam.answerKeys['A']?[subject] ?? '';
              if (expectedC != -1) {
                bool foundPerfect = false;
                // Test all available booklets
                for (var bKey in exam.answerKeys.keys) {
                  final testR = exam.answerKeys[bKey]?[subject] ?? '';
                  int testC = 0;
                  for (int j = 0; j < testR.length; j++) {
                    if (TrialExam.evaluateAnswer(j < sAns.length ? sAns[j] : ' ', testR[j]) == AnswerStatus.correct) testC++;
                  }
                  if (testC == expectedC) {
                    rAns = testR;
                    foundPerfect = true;
                    break;
                  }
                }
                // Fallback to master if no perfect match
                if (!foundPerfect) rAns = exam.answerKeys['A']?[subject] ?? rAns;
              }

              // Final Evaluation & Question Selection
              for (int j = 0; j < rAns.length; j++) {
                final String sChar = j < sAns.length ? sAns[j] : ' ';
                final String rChar = rAns[j];
                final AnswerStatus status = TrialExam.evaluateAnswer(sChar, rChar);

                // If no backend stats, increment locally
                if (bs == null) {
                  stats[subject]!['T'] = (stats[subject]!['T'] as int) + 1;
                  if (status == AnswerStatus.correct) stats[subject]!['C'] = (stats[subject]!['C'] as int) + 1;
                  else if (status == AnswerStatus.wrong) stats[subject]!['W'] = (stats[subject]!['W'] as int) + 1;
                  else stats[subject]!['E'] = (stats[subject]!['E'] as int) + 1;
                }

                if (status == AnswerStatus.wrong || status == AnswerStatus.empty) {
                  final int qNoInStudentBooklet = j + 1;
                  int masterQNo = qNoInStudentBooklet;

                  // ADVANCED MAPPING: Find the corresponding question in Master Booklet (A)
                  // Priority 1: Use the explicit bookletMapping table (Conversion Table)
                  bool mappingFound = false;
                  if (booklet != 'A' && exam.bookletMapping.containsKey(booklet) && exam.bookletMapping[booklet]!.containsKey(subject)) {
                    final String mappingStr = exam.bookletMapping[booklet]![subject]!;
                    if (mappingStr.contains('(')) {
                      final RegExp regex = RegExp(r'(\d+)\((\d+)\)');
                      final matches = regex.allMatches(mappingStr);
                      for (var m in matches) {
                        if (int.tryParse(m.group(1)!) == qNoInStudentBooklet) {
                          masterQNo = int.tryParse(m.group(2)!) ?? masterQNo;
                          mappingFound = true;
                          break;
                        }
                      }
                    } else {
                      final RegExp regex = RegExp(r'\d+');
                      final numbers = regex.allMatches(mappingStr).map((m) => int.parse(m.group(0)!)).toList();
                      if (j < numbers.length) {
                        masterQNo = numbers[j];
                        mappingFound = true;
                      }
                    }
                  }

                  // Priority 2: Fallback to Outcome-based matching
                  if (!mappingFound && booklet != 'A' && exam.outcomes.containsKey('A') && exam.outcomes.containsKey(booklet)) {
                    final List<String>? studentSubOutcomes = exam.outcomes[booklet]?[subject];
                    final List<String>? masterSubOutcomes = exam.outcomes['A']?[subject];
                    
                    if (studentSubOutcomes != null && masterSubOutcomes != null && j < studentSubOutcomes.length) {
                      final String rawTarget = studentSubOutcomes[j];
                      final String targetOutcome = _normalizeText(rawTarget);
                      
                      if (targetOutcome.isNotEmpty) {
                        final int? parsedDirectMap = int.tryParse(rawTarget.trim());
                        if (parsedDirectMap != null && parsedDirectMap > 0) {
                          masterQNo = parsedDirectMap;
                        } else {
                          int occurrence = 0;
                          for (int k = 0; k <= j; k++) {
                            if (k < studentSubOutcomes.length && _normalizeText(studentSubOutcomes[k]) == targetOutcome) {
                              occurrence++;
                            }
                          }

                          int foundCount = 0;
                          int foundIndex = -1;
                          for (int k = 0; k < masterSubOutcomes.length; k++) {
                            if (_normalizeText(masterSubOutcomes[k]) == targetOutcome) {
                              foundCount++;
                              if (foundCount == occurrence) {
                                foundIndex = k;
                                break;
                              }
                            }
                          }

                          if (foundIndex != -1) {
                            masterQNo = foundIndex + 1;
                          }
                        }
                      }
                    }
                  }

                  final dynamic meta = poolMap['${normSubject}_$masterQNo'];
                  if (meta != null) {
                    Uint8List? bytes;
                    try {
                      if (meta['base64Image'] != null) bytes = base64Decode(meta['base64Image']);
                      else if (meta['imageUrl'] != null) {
                        final res = await http.get(Uri.parse(meta['imageUrl'])).timeout(const Duration(seconds: 4));
                        if (res.statusCode == 200) bytes = res.bodyBytes;
                      }
                    } catch (_) {}
                    if (bytes != null) {
                      compositeGrouped.putIfAbsent(subject, () => []).add({
                        'examName': exam.name, 
                        'questionNo': qNoInStudentBooklet, // We show the STU's question number in text
                        'masterQNo': masterQNo, // But we use the master index for the image
                        'imageBytes': bytes,
                        'isWide': meta['isWide'] ?? false, 
                        'correctAnswer': meta['correctAnswer'] ?? rChar,
                        'booklet': booklet,
                      });
                    }
                  }
                }
              }
              // Update Net locally for summary page
              final int tc = stats[subject]!['C'] as int;
              final int tw = stats[subject]!['W'] as int;
              stats[subject]!['Net'] = (tc - (tw / 3.0)).clamp(0, stats[subject]!['T'] as int);
            }
          }

          // Assign sequence numbers per subject (1, 2, 3...)
          for (var sub in compositeGrouped.keys) {
            final list = compositeGrouped[sub]!;
            for (int k = 0; k < list.length; k++) {
              list[k]['sequenceNo'] = k + 1;
            }
          }

          final List<String> sortedSubjects = stats.keys.toList();
          final String firstTId = exams.isNotEmpty ? exams.first.examTypeId : '';
          final List<String> mOrder = allTypeOrders[firstTId] ?? [];
          sortedSubjects.sort((a,b) {
            final int ia = mOrder.indexOf(a.toLowerCase().trim());
            final int ib = mOrder.indexOf(b.toLowerCase().trim());
            return (ia != -1 ? ia : 999).compareTo(ib != -1 ? ib : 999);
          });

          // 1. Premium Cover Page
          pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, build: (ctx) => pw.Container(
            padding: const pw.EdgeInsets.all(32),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.indigo900, width: 4)),
            child: pw.Column(children: [
              pw.SizedBox(height: 40),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: const pw.BoxDecoration(color: PdfColors.indigo900),
                child: pw.Text('HATA KİTAPÇIĞI', style: pw.TextStyle(font: fontBold, fontSize: 36, color: PdfColors.white, letterSpacing: 2)),
              ),
              pw.SizedBox(height: 10),
              pw.Text('KİŞİYE ÖZEL PERFORMANS RAPORU', style: pw.TextStyle(font: font, fontSize: 14, color: PdfColors.indigo300)),
              pw.SizedBox(height: 60),
              pw.Text(studentName.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 28, color: PdfColors.black)),
              pw.SizedBox(height: 10),
              pw.Container(width: 80, height: 3, color: PdfColors.indigo900),
              pw.SizedBox(height: 60),
              pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('KAPSAMDAKİ SINAVLAR', style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.indigo900))),
              pw.SizedBox(height: 10),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(15),
                decoration: pw.BoxDecoration(color: PdfColors.grey50, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  for (var e in exams)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 6),
                      child: pw.Row(children: [
                        pw.Container(width: 6, height: 6, decoration: const pw.BoxDecoration(color: PdfColors.indigo900, shape: pw.BoxShape.circle)),
                        pw.SizedBox(width: 10),
                        pw.Text(e.name, style: pw.TextStyle(font: font, fontSize: 11)),
                      ]),
                    ),
                ]),
              ),
              pw.SizedBox(height: 40),
              pw.Text('GENEL PERFORMANS ÖZETİ', style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.indigo900)),
              pw.SizedBox(height: 15),
              pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5), children: [
                pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.indigo900), children: [
                  _cell('DERS ADI', fontBold, isHeader: true, color: PdfColors.white),
                  _cell('S', fontBold, isHeader: true, color: PdfColors.white),
                  _cell('D', fontBold, isHeader: true, color: PdfColors.white),
                  _cell('Y', fontBold, isHeader: true, color: PdfColors.white),
                  _cell('B', fontBold, isHeader: true, color: PdfColors.white),
                  _cell('NET', fontBold, isHeader: true, color: PdfColors.white),
                ]),
                for (var s in sortedSubjects)
                  pw.TableRow(children: [
                    _cell(s, font),
                    _cell('${stats[s]?['T']}', font),
                    _cell('${stats[s]?['C']}', font),
                    _cell('${stats[s]?['W']}', font, color: PdfColors.red700),
                    _cell('${stats[s]?['E']}', font, color: PdfColors.orange700),
                    _cell((stats[s]?['Net'] as double).toStringAsFixed(2), fontBold, color: PdfColors.indigo900),
                  ]),
              ]),
              pw.Spacer(),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('eduKN Eğitim Teknolojileri', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.indigo900)),
                pw.Text('www.edukn.com', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey500)),
              ]),
            ]),
          )));

          // 2. Question Pages
          for (var subject in sortedSubjects) {
            if (!compositeGrouped.containsKey(subject)) continue;
            final qList = compositeGrouped[subject]!;
            final sStat = stats[subject]!;
            final double tc = (sStat['C'] as int).toDouble();
            final double tw = (sStat['W'] as int).toDouble();
            final double tt = (sStat['T'] as int).toDouble();
            final double net = (tc - (tw / 3.0)).clamp(0, tt);
            final double perc = tt > 0 ? (tc / tt * 100) : 0.0;

            pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32),
              header: (ctx) => pw.Container(alignment: pw.Alignment.topRight, child: pw.Text('$studentName | Hata Kitapçığı', style: pw.TextStyle(font: font, fontSize: 8))),
              build: (ctx) {
                List<pw.Widget> wgs = [];
                wgs.add(pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  margin: const pw.EdgeInsets.only(bottom: 20),
                  decoration: pw.BoxDecoration(color: PdfColors.indigo50, border: pw.Border(left: pw.BorderSide(color: PdfColors.indigo900, width: 6))),
                  child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text(subject.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.indigo900)),
                    pw.Row(children: [
                      _miniStat('S', '${sStat['T']}', PdfColors.grey700, fontBold, font),
                      _miniStat('D', '${sStat['C']}', PdfColors.green700, fontBold, font),
                      _miniStat('Y', '${sStat['W']}', PdfColors.red700, fontBold, font),
                      _miniStat('NET', net.toStringAsFixed(2), PdfColors.indigo900, fontBold, font),
                    ]),
                  ]),
                ));
                final List<Map<String, dynamic>> sortedQ = List.from(qList)..sort((a,b) => (a['sequenceNo'] as int).compareTo(b['sequenceNo'] as int));
                
                // Process in blocks to maintain column-first layout for narrow questions
                // and row-spanning layout for wide questions in the correct order.
                int i = 0;
                while (i < sortedQ.length) {
                  List<Map<String, dynamic>> currentNarrowBlock = [];
                  
                  // Collect consecutive narrow questions
                  while (i < sortedQ.length && sortedQ[i]['isWide'] != true) {
                    currentNarrowBlock.add(sortedQ[i]);
                    i++;
                  }
                  
                  if (currentNarrowBlock.isNotEmpty) {
                    // Split narrow block into two columns for Column-First ordering
                    // e.g., if 4 questions: 1,2 go left; 3,4 go right
                    final int count = currentNarrowBlock.length;
                    final int leftCount = (count / 2).ceil();
                    final leftCol = currentNarrowBlock.sublist(0, leftCount);
                    final rightCol = currentNarrowBlock.sublist(leftCount);
                    
                    final int rowCount = leftCol.length;
                    for (int r = 0; r < rowCount; r++) {
                      List<Map<String, dynamic>> rowItems = [];
                      rowItems.add(leftCol[r]);
                      if (r < rightCol.length) rowItems.add(rightCol[r]);
                      
                      wgs.add(_buildRow(rowItems, fontBold, font));
                      wgs.add(pw.SizedBox(height: 20));
                    }
                  }
                  
                  // If we hit a wide question, add it and continue
                  if (i < sortedQ.length && sortedQ[i]['isWide'] == true) {
                    wgs.add(_buildFullWidth(sortedQ[i], fontBold, font));
                    wgs.add(pw.SizedBox(height: 20));
                    i++;
                  }
                }
                
                return wgs;
              },
            ));
          }

          // 3. Answer Key
          pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, build: (ctx) => pw.Container(padding: const pw.EdgeInsets.all(32), child: pw.Column(children: [
            pw.Text('GENEL CEVAP ANAHTARI', style: pw.TextStyle(font: fontBold, fontSize: 22, color: PdfColors.indigo900)),
            pw.SizedBox(height: 20),
            for (var s in sortedSubjects) if (compositeGrouped.containsKey(s)) _buildSubjectAnswerKey(s, compositeGrouped[s]!, fontBold, font),
          ]))));
          
        } catch (stErr) {
          print('Single Student Generation Error: $stErr');
        }
      }

      await Printing.layoutPdf(onLayout: (format) => pdf.save(), name: 'Hata_Kitapcigi.pdf');
    } catch (e) {
      print('Composite PDF Critical Error: $e');
    }
  }



  pw.Widget _buildSubjectAnswerKey(String subject, List<Map<String, dynamic>> questions, pw.Font bold, pw.Font reg) {
    final sortedQ = List<Map<String, dynamic>>.from(questions)..sort((a, b) => (a['sequenceNo'] as int).compareTo(b['sequenceNo'] as int));
    
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
                pw.Text('${q['sequenceNo']}.', style: pw.TextStyle(font: reg, fontSize: 10, color: PdfColors.grey600)),
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

  pw.Widget _miniStat(String label, String value, PdfColor color, pw.Font bold, pw.Font reg) {
     return pw.Padding(
       padding: const pw.EdgeInsets.symmetric(horizontal: 5),
       child: pw.Column(
         children: [
           pw.Text(label, style: pw.TextStyle(font: reg, fontSize: 7, color: PdfColors.grey500)),
           pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 11, color: color)),
         ],
       ),
     );
  }

  pw.Widget _questionHeader(Map<String, dynamic> q, pw.Font bold, {bool isNarrow = false}) {
    final headerWidth = isNarrow ? 230.0 : 480.0;
    return pw.Container(
      width: headerWidth,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const pw.BoxDecoration(color: PdfColors.indigo50, border: pw.Border(left: pw.BorderSide(color: PdfColors.indigo900, width: 3))),
      child: pw.Row(
        children: [
          pw.Container(
            width: 16, height: 16,
            decoration: const pw.BoxDecoration(color: PdfColors.indigo900, shape: pw.BoxShape.circle),
            child: pw.Center(
              child: pw.Text('${q['sequenceNo']}', style: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.white)),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text('${q['examName']} | ${q['booklet']} KİTAPÇIĞI ${q['questionNo']}. SORU', 
              style: pw.TextStyle(font: bold, fontSize: isNarrow ? 7 : 8.5, color: PdfColors.indigo900),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
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
                pw.Center(
                  child: pw.Container(
                    constraints: const pw.BoxConstraints(maxHeight: 380),
                    child: pw.Image(pw.MemoryImage(q['imageBytes']), width: 480, fit: pw.BoxFit.contain),
                  ),
                ),
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
                pw.Container(
                  constraints: const pw.BoxConstraints(maxHeight: 250),
                  child: pw.Image(pw.MemoryImage(q['imageBytes']), fit: pw.BoxFit.contain, width: 230),
                ),
                pw.SizedBox(height: 15),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // Helper method for robust string matching
  String _normalizeText(String s) {
    String n = s
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g');
    n = n.replaceAll(RegExp(r'[.,;:\-()""\’\‘\“\”\!' + r"']"), '');
    return n.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
