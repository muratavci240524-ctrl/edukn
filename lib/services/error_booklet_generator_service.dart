import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../../../models/assessment/trial_exam_model.dart';
import '../utils/drive_image_helper.dart';

class ErrorBookletGeneratorService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> generateAndDownloadBooklet({
    required List<TrialExam> exams,
    required List<Map<String, dynamic>> studentResults,
    bool prioritizeCritical = true,
    int? maxQuestions,
    bool fillFromPool = false,
    bool individualPDFs = false,
    Function(int current, int total, String studentName)? onProgress,
  }) async {
    await generateBulkBooklets(
      exams: exams,
      bulkStudentResults: [studentResults],
      prioritizeCritical: prioritizeCritical,
      maxQuestions: maxQuestions,
      fillFromPool: fillFromPool,
      individualPDFs: individualPDFs,
      onProgress: onProgress,
    );
  }

  Future<void> generateBulkBooklets({
    required List<TrialExam> exams,
    required List<List<Map<String, dynamic>>> bulkStudentResults,
    bool prioritizeCritical = true,
    int? maxQuestions,
    bool fillFromPool = false,
    bool individualPDFs = false,
    Function(int current, int total, String studentName)? onProgress,
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
      final singlePdf = pw.Document();

      // 2. Pre-fetch Data & Metadata (with generous timeout & retry per exam so pool is never lost)
      Map<String, Map<String, Map<String, dynamic>>> allPoolMaps = {};
      Map<String, List<String>> allTypeOrders = {};

      for (var exam in exams) {
        try {
          Future<QuerySnapshot<Map<String, dynamic>>> fetchPoolSnap(
            String examDocId,
          ) async {
            try {
              return await _firestore
                  .collection('trial_exams')
                  .doc(examDocId)
                  .collection('questions_pool')
                  .get()
                  .timeout(const Duration(seconds: 60));
            } catch (_) {
              return await _firestore
                  .collection('trial_exams')
                  .doc(examDocId)
                  .collection('questions_pool')
                  .get(const GetOptions(source: Source.serverAndCache))
                  .timeout(const Duration(seconds: 60));
            }
          }

          void mergeSnapIntoPool(
            QuerySnapshot<Map<String, dynamic>> snap,
            Map<String, Map<String, dynamic>> targetPool,
          ) {
            for (var qDoc in snap.docs) {
              final Map<String, dynamic> data = Map<String, dynamic>.from(
                qDoc.data(),
              );
              final String sKey = (data['subject'] ?? '')
                  .toString()
                  .toLowerCase()
                  .trim();
              final String normSKey = _normalizeText(
                (data['subject'] ?? '').toString(),
              );
              final String nKey = (data['questionNo'] ?? '').toString().trim();
              targetPool['${sKey}_$nKey'] = data;
              if (normSKey.isNotEmpty) {
                targetPool['${normSKey}_$nKey'] = data;
              }
            }
          }

          Map<String, Map<String, dynamic>> poolMap = {};
          final String centralId = (exam.centralExamId ?? '').trim();
          if (centralId.isNotEmpty && centralId != exam.id) {
            try {
              final centralPoolSnap = await fetchPoolSnap(centralId);
              mergeSnapIntoPool(centralPoolSnap, poolMap);
            } catch (e) {
              print('Pre-fetch Central Pool Warning ($centralId): $e');
            }
          }

          final poolSnap = await fetchPoolSnap(exam.id);
          mergeSnapIntoPool(poolSnap, poolMap);
          allPoolMaps[exam.id] = poolMap;
        } catch (e) {
          print('Pre-fetch Pool Warning (${exam.id}): $e');
        }

        try {
          final String tId = exam.examTypeId;
          if (tId.isNotEmpty && !allTypeOrders.containsKey(tId)) {
            final tSnap = await _firestore
                .collection('exam_types')
                .doc(tId)
                .get()
                .timeout(const Duration(seconds: 15));
            if (tSnap.exists) {
              final subjectsRaw = tSnap.data()?['subjects'] as List<dynamic>?;
              if (subjectsRaw != null) {
                allTypeOrders[tId] = subjectsRaw
                    .map((s) => (s['branchName'] ?? '').toString().toLowerCase().trim())
                    .toList();
              }
            }
          }
        } catch (e) {
          print('Pre-fetch ExamType Warning: $e');
        }
      }

      // 3. Process Students
      int currentIdx = 0;
      final int totalCount = bulkStudentResults.length;
      final zipArchive = (individualPDFs && totalCount > 1) ? Archive() : null;

      for (var studentResults in bulkStudentResults) {
        currentIdx++;
        try {
          if (studentResults.isEmpty) continue;
          final Map<String, dynamic> firstValid = studentResults.firstWhere((r) => r.isNotEmpty, orElse: () => {});
          if (firstValid.isEmpty) continue;

          final String studentName = (firstValid['studentName'] ?? firstValid['name'] ?? 'Öğrenci').toString();
          final String branch = (firstValid['branch'] ?? firstValid['className'] ?? firstValid['sube'] ?? 'Bilinmeyen').toString().trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
          
          // Invoke progress callback & yield thread to prevent blocking the UI
          onProgress?.call(currentIdx, totalCount, studentName);
          await Future.delayed(const Duration(milliseconds: 50));

          final activePdf = individualPDFs ? pw.Document() : singlePdf;

          Map<String, List<Map<String, dynamic>>> compositeGrouped = {};
          Map<String, Map<String, dynamic>> stats = {}; // subject -> {T, C, W, E, Net}

          for (int i = 0; i < exams.length; i++) {
            final exam = exams[i];
            if (i >= studentResults.length) continue;
            final result = studentResults[i];
            if (result.isEmpty) continue;
            
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

                  final dynamic meta = poolMap['${normSubject}_$masterQNo'] ??
                      poolMap['${_normalizeText(subject)}_$masterQNo'];
                  if (meta != null) {
                    Uint8List? bytes = meta['__whitenedImageBytes'] as Uint8List?;
                    if (bytes == null) {
                      try {
                        if (meta['base64Image'] != null) {
                          bytes = base64Decode(meta['base64Image']);
                        } else if (meta['imageUrl'] != null || meta['driveFileId'] != null) {
                          bytes = await DriveImageHelper.fetchImageBytes(
                            meta['imageUrl']?.toString(),
                            driveFileId: meta['driveFileId']?.toString(),
                            perTryTimeout: const Duration(seconds: 4),
                          );
                        }
                        if (bytes != null) {
                          bytes = await _whitenBytesForPdf(bytes);
                          meta['__whitenedImageBytes'] = bytes;
                        }
                      } catch (silentError) {
                        print('[error_booklet_generator_service] hata yutuldu: $silentError');
                      }
                    }
                    if (bytes != null) {
                      Uint8List? passageBytes = meta['__whitenedPassageBytes'] as Uint8List?;
                      if (passageBytes == null && meta['passageBase64'] != null) {
                        try {
                          final rawPassage = base64Decode(meta['passageBase64'] as String);
                          passageBytes = await _whitenBytesForPdf(rawPassage);
                          meta['__whitenedPassageBytes'] = passageBytes;
                        } catch (_) {}
                      }
                      compositeGrouped.putIfAbsent(subject, () => []).add({
                        'examName': exam.name, 
                        'questionNo': qNoInStudentBooklet, // We show the STU's question number in text
                        'masterQNo': masterQNo, // But we use the master index for the image
                        'imageBytes': bytes,
                        'isWide': meta['isWide'] ?? false, 
                        'isCritical': meta['isCritical'] == true,
                        'correctAnswer': meta['correctAnswer'] ?? rChar,
                        'booklet': booklet,
                        'difficulty': meta['difficulty'],
                        'passageId': meta['passageId'],
                        'passageBytes': passageBytes,
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

          // Apply smart question prioritization & difficulty sorting (zordan kolaya - difficulty ascending)
          final List<Map<String, dynamic>> allCandidates = [];
          compositeGrouped.forEach((sub, list) {
            for (var item in list) {
              item['subjectGroup'] = sub;
              allCandidates.add(item);
            }
          });

          // Separate candidates by critical status
          final List<Map<String, dynamic>> wrongCriticals = allCandidates.where((q) => q['isCritical'] == true).toList();
          final List<Map<String, dynamic>> wrongNonCriticals = allCandidates.where((q) => q['isCritical'] != true).toList();

          // Sort each sublist from hardest to easiest (success rate ascending: 0% to 100%)
          wrongCriticals.sort((a, b) {
            final double diffA = (a['difficulty'] as num?)?.toDouble() ?? 50.0;
            final double diffB = (b['difficulty'] as num?)?.toDouble() ?? 50.0;
            return diffA.compareTo(diffB);
          });
          wrongNonCriticals.sort((a, b) {
            final double diffA = (a['difficulty'] as num?)?.toDouble() ?? 50.0;
            final double diffB = (b['difficulty'] as num?)?.toDouble() ?? 50.0;
            return diffA.compareTo(diffB);
          });

          List<Map<String, dynamic>> selectedQuestions = [];
          if (prioritizeCritical) {
            selectedQuestions = [...wrongCriticals, ...wrongNonCriticals];
          } else {
            selectedQuestions = [...allCandidates];
            selectedQuestions.sort((a, b) {
              final double diffA = (a['difficulty'] as num?)?.toDouble() ?? 50.0;
              final double diffB = (b['difficulty'] as num?)?.toDouble() ?? 50.0;
              return diffA.compareTo(diffB);
            });
          }

          // If maximum limit is set and candidates exceed limit, slice to maxQuestions
          if (maxQuestions != null && maxQuestions > 0 && selectedQuestions.length > maxQuestions) {
            selectedQuestions = selectedQuestions.sublist(0, maxQuestions);
          }

          // DYNAMIC POOL FILL-UP: If fillFromPool is active, fill remaining slots up to maxQuestions
          if (fillFromPool && maxQuestions != null && maxQuestions > 0 && selectedQuestions.length < maxQuestions) {
            final int neededCount = maxQuestions - selectedQuestions.length;
            final List<Map<String, dynamic>> fillCandidates = [];

            // Tracking selected keys to avoid duplicating any questions in the booklet
            final Set<String> selectedKeys = selectedQuestions.map((q) {
              final String subGroup = (q['subjectGroup'] ?? '').toString().toLowerCase().trim();
              return '${q['examName']}_${subGroup}_${q['masterQNo']}';
            }).toSet();

            for (var exam in exams) {
              final Map<String, Map<String, dynamic>> poolMap = allPoolMaps[exam.id] ?? {};
              for (var key in poolMap.keys) {
                final Map<String, dynamic> meta = poolMap[key]!;
                final String sKey = (meta['subject'] ?? '').toString();
                final String normSubject = sKey.toLowerCase().trim();
                final int masterQNo = (num.tryParse((meta['questionNo'] ?? '').toString()) ?? 0).toInt();

                final String uniqueKey = '${exam.name}_${normSubject}_$masterQNo';
                if (!selectedKeys.contains(uniqueKey)) {
                  fillCandidates.add({
                    'exam': exam,
                    'meta': meta,
                    'subject': sKey,
                    'masterQNo': masterQNo,
                    'uniqueKey': uniqueKey,
                    'difficulty': meta['difficulty'],
                    'isCritical': meta['isCritical'] == true,
                  });
                }
              }
            }

            // Separate fill candidates by critical status
            final List<Map<String, dynamic>> fillCriticals = fillCandidates.where((q) => q['isCritical'] == true).toList();
            final List<Map<String, dynamic>> fillNonCriticals = fillCandidates.where((q) => q['isCritical'] != true).toList();

            // Sort fill candidates by difficulty ascending (zordan kolaya)
            fillCriticals.sort((a, b) {
              final double diffA = (a['difficulty'] as num?)?.toDouble() ?? 50.0;
              final double diffB = (b['difficulty'] as num?)?.toDouble() ?? 50.0;
              return diffA.compareTo(diffB);
            });
            fillNonCriticals.sort((a, b) {
              final double diffA = (a['difficulty'] as num?)?.toDouble() ?? 50.0;
              final double diffB = (b['difficulty'] as num?)?.toDouble() ?? 50.0;
              return diffA.compareTo(diffB);
            });

            // Starred (critical) pool questions are ALWAYS prioritized first (hardest to easiest)
            final List<Map<String, dynamic>> orderedFillCandidates = [...fillCriticals, ...fillNonCriticals];

            // Decode image bytes for chosen fill-up questions
            int filled = 0;
            for (var cand in orderedFillCandidates) {
              if (filled >= neededCount) break;

              final Map<String, dynamic> meta = cand['meta'];
              final TrialExam exam = cand['exam'];
              final String subject = cand['subject'];
              final int masterQNo = cand['masterQNo'];

              Uint8List? bytes;
              try {
                if (meta['base64Image'] != null) {
                  bytes = base64Decode(meta['base64Image']);
                } else if (meta['imageUrl'] != null || meta['driveFileId'] != null) {
                  bytes = await DriveImageHelper.fetchImageBytes(
                    meta['imageUrl']?.toString(),
                    driveFileId: meta['driveFileId']?.toString(),
                    perTryTimeout: const Duration(seconds: 4),
                  );
                }
              } catch (silentError) { print('[error_booklet_generator_service] hata yutuldu: $silentError'); }

              if (bytes != null) {
                Uint8List? passageBytes;
                try {
                  if (meta['passageBase64'] != null) {
                    passageBytes = base64Decode(meta['passageBase64'] as String);
                  }
                } catch (_) {}
                selectedQuestions.add({
                  'examName': exam.name,
                  'questionNo': masterQNo,
                  'masterQNo': masterQNo,
                  'imageBytes': bytes,
                  'isWide': meta['isWide'] ?? false,
                  'isCritical': meta['isCritical'] == true,
                  'correctAnswer': meta['correctAnswer'] ?? 'A',
                  'booklet': 'A',
                  'subjectGroup': subject,
                  'difficulty': meta['difficulty'],
                  'isFromPoolFill': true,
                  'passageId': meta['passageId'],
                  'passageBytes': passageBytes,
                });
                filled++;
              }
            }
          }

          compositeGrouped.clear();
          for (var q in selectedQuestions) {
            final String sub = q['subjectGroup'] as String;
            compositeGrouped.putIfAbsent(sub, () => []).add(q);
          }

          // Group questions sharing the same passageId together (in questionNo order)
          // and assign sequence numbers per subject (1, 2, 3...)
          for (var sub in compositeGrouped.keys) {
            final rawList = compositeGrouped[sub]!;
            final groupedList = <Map<String, dynamic>>[];
            final handledPassages = <String>{};
            for (final q in rawList) {
              final pid = q['passageId'] as String?;
              if (pid != null && pid.isNotEmpty && q['passageBytes'] != null) {
                if (handledPassages.contains(pid)) continue;
                handledPassages.add(pid);
                final siblings = rawList
                    .where((x) => x['passageId'] == pid)
                    .toList()
                  ..sort((a, b) => (a['questionNo'] as int).compareTo(b['questionNo'] as int));
                groupedList.addAll(siblings);
              } else {
                groupedList.add(q);
              }
            }
            for (int k = 0; k < groupedList.length; k++) {
              groupedList[k]['sequenceNo'] = k + 1;
            }
            compositeGrouped[sub] = groupedList;
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
          activePdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, build: (ctx) => pw.Container(
            padding: const pw.EdgeInsets.all(24),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.indigo900, width: 3)),
            child: pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blue300, width: 1)),
              child: pw.Column(children: [
                pw.SizedBox(height: 20),
                
                // 🌟 HIGH FIDELITY eduKN VECTOR BRAND LOGO (Matches Home Page App Bar exactly)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    // Slanted 3 speed bars slanted at -15 degrees skew
                    pw.Transform(
                      transform: vm.Matrix4.skewX(-0.2679),
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          // Top Speed Bar (Bright Blue)
                          pw.Container(width: 18, height: 3.5, decoration: const pw.BoxDecoration(color: PdfColors.blue600, borderRadius: pw.BorderRadius.all(pw.Radius.circular(1.5)))),
                          pw.SizedBox(height: 2.5),
                          // Middle Speed Bar (Bright Blue - longest)
                          pw.Container(width: 26, height: 3.5, decoration: const pw.BoxDecoration(color: PdfColors.blue600, borderRadius: pw.BorderRadius.all(pw.Radius.circular(1.5)))),
                          pw.SizedBox(height: 2.5),
                          // Bottom Speed Bar (Cyan - shortest)
                          pw.Container(width: 14, height: 3.5, decoration: const pw.BoxDecoration(color: PdfColors.cyan400, borderRadius: pw.BorderRadius.all(pw.Radius.circular(1.5)))),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    // eduKN Logo text (Italic style matching official app bar & login page)
                    pw.Text(
                      'eduKN',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 34,
                        fontStyle: pw.FontStyle.italic,
                        color: PdfColors.indigo900,
                      ),
                    ),
                  ],
                ),
                
                pw.SizedBox(height: 35),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.indigo900,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(16)),
                  ),
                  child: pw.Text('HATA KİTAPÇIĞI', style: pw.TextStyle(font: fontBold, fontSize: 30, color: PdfColors.white, letterSpacing: 3)),
                ),
                pw.SizedBox(height: 8),
                pw.Text('KİŞİYE ÖZEL PERFORMANS RAPORU', style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.indigo500, letterSpacing: 1.5)),
                pw.SizedBox(height: 45),
                
                // Student Banner Name Card
                pw.Text('ÖĞRENCİ ADI SOYADI', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey500, letterSpacing: 1.5)),
                pw.SizedBox(height: 4),
                pw.Text(studentName.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 26, color: PdfColors.indigo900, letterSpacing: 1)),
                pw.SizedBox(height: 8),
                pw.Container(width: 100, height: 2.5, color: PdfColors.blue300),
                pw.SizedBox(height: 45),
                
                pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('KAPSAMDAKİ SINAVLAR', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.indigo900, letterSpacing: 1))),
                pw.SizedBox(height: 8),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey50,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
                  ),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    for (var e in exams)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 6),
                        child: pw.Row(children: [
                          pw.Container(width: 5, height: 5, decoration: const pw.BoxDecoration(color: PdfColors.blue500, shape: pw.BoxShape.circle)),
                          pw.SizedBox(width: 10),
                          pw.Text(e.name, style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey800)),
                        ]),
                      ),
                  ]),
                ),
                pw.SizedBox(height: 35),
                pw.Text('GENEL PERFORMANS ÖZETİ', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.indigo900, letterSpacing: 1)),
                pw.SizedBox(height: 12),
                pw.Table(border: pw.TableBorder.all(color: PdfColors.grey200, width: 0.5), children: [
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
                  pw.Text('eduKN Okul Yönetimi', style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.indigo900)),
                  pw.Text('www.edukn.co', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey500)),
                ]),
              ]),
            ),
          )));

          // 2. Question Pages (Professional 2-Column Test Booklet Layout)
          for (var subject in sortedSubjects) {
            if (!compositeGrouped.containsKey(subject)) continue;
            final qList = compositeGrouped[subject]!;
            final sStat = stats[subject]!;
            final double tc = (sStat['C'] as int).toDouble();
            final double tw = (sStat['W'] as int).toDouble();
            final double tt = (sStat['T'] as int).toDouble();
            final double net = (tc - (tw / 3.0)).clamp(0, tt);

            activePdf.addPage(pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              maxPages: 100,
              margin: const pw.EdgeInsets.all(24),
              header: (ctx) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                padding: const pw.EdgeInsets.only(bottom: 4),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.indigo100, width: 0.6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${subject.toUpperCase()} TESTİ',
                      style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.indigo700),
                    ),
                    pw.Text(
                      '$studentName | Kişiye Özel Hata Kitapçığı',
                      style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),
              footer: (ctx) => pw.Container(
                margin: const pw.EdgeInsets.only(top: 6),
                padding: const pw.EdgeInsets.only(top: 4),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: PdfColors.indigo100, width: 0.6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('eduKN Akıllı Ölçme ve Değerlendirme', style: pw.TextStyle(font: font, fontSize: 7.5, color: PdfColors.grey500)),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.indigo900,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                      ),
                      child: pw.Text(
                        '${ctx.pageNumber}',
                        style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white),
                      ),
                    ),
                    pw.Text(subject.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: PdfColors.indigo400)),
                  ],
                ),
              ),
              build: (ctx) {
                final List<pw.Widget> wgs = [];
                wgs.add(pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.indigo50,
                    border: pw.Border(left: pw.BorderSide(color: PdfColors.indigo900, width: 5)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '${subject.toUpperCase()} TESTİ',
                        style: pw.TextStyle(font: fontBold, fontSize: 15, color: PdfColors.indigo900),
                      ),
                      pw.Row(children: [
                        _miniStat('S', '${sStat['T']}', PdfColors.grey700, fontBold, font),
                        _miniStat('D', '${sStat['C']}', PdfColors.green700, fontBold, font),
                        _miniStat('Y', '${sStat['W']}', PdfColors.red700, fontBold, font),
                        _miniStat('NET', net.toStringAsFixed(2), PdfColors.indigo900, fontBold, font),
                      ]),
                    ],
                  ),
                ));

                final List<Map<String, dynamic>> sortedQ = List.from(qList)
                  ..sort((a, b) => (a['sequenceNo'] as int).compareTo(b['sequenceNo'] as int));

                wgs.addAll(_buildProfessionalTestLayout(sortedQ, fontBold, font));
                return wgs;
              },
            ));
          }

          // 3. Answer Key (compact, premium layout – flows onto extra page only if needed)
          activePdf.addPage(pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(28),
            build: (ctx) => [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const pw.EdgeInsets.only(bottom: 12),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.indigo900,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('GENEL CEVAP ANAHTARI', style: pw.TextStyle(font: fontBold, fontSize: 15, color: PdfColors.white, letterSpacing: 1)),
                    pw.Text(studentName, style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.indigo100)),
                  ],
                ),
              ),
              for (var s in sortedSubjects)
                if (compositeGrouped.containsKey(s)) _buildSubjectAnswerKey(s, compositeGrouped[s]!, fontBold, font),
            ],
          ));

          // If individualPDFs is true, handle individual student booklet saving
          if (individualPDFs) {
            final bytes = await activePdf.save();
            final String examNameStr = exams.length == 1 ? exams[0].name : 'Karma';
            final String sanitizedStudentName = studentName.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
            final String sanitizedExamName = examNameStr.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
            final String filename = '$sanitizedStudentName - $sanitizedExamName Hata Kitapçığı.pdf';

            if (zipArchive != null) {
              // Add to ZIP under branch folder without slow double-compression (1000x speedup!)
              final String zipPath = '$branch/$filename';
              zipArchive.addFile(ArchiveFile.noCompress(zipPath, bytes.length, bytes));
            } else {
              // Single student direct download
              if (kIsWeb) {
                final blob = html.Blob([bytes], 'application/pdf');
                final url = html.Url.createObjectUrlFromBlob(blob);
                html.AnchorElement(href: url)
                  ..setAttribute("download", filename)
                  ..click();
                html.Url.revokeObjectUrl(url);
              } else {
                await Printing.sharePdf(bytes: bytes, filename: filename);
              }
            }
          }
          
        } catch (stErr) {
          print('Single Student Generation Error: $stErr');
        }
      }

      // 4. Finalize & Download ZIP Archive if bulk individual PDFs were processed
      if (zipArchive != null) {
        onProgress?.call(totalCount, totalCount, 'Klasörler Paketleniyor (ZIP)...');
        await Future.delayed(const Duration(milliseconds: 150)); // Allow Flutter to render the progress update
        
        final zipBytes = Uint8List.fromList(ZipEncoder().encode(zipArchive)!);
        final String examNameStr = exams.length == 1 ? exams[0].name : 'Karma';
        final String sanitizedExamName = examNameStr.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        final String zipFilename = '$sanitizedExamName - Sınıf Bazlı Hata Kitapçıkları.zip';

        if (kIsWeb) {
          final blob = html.Blob([zipBytes], 'application/zip');
          final url = html.Url.createObjectUrlFromBlob(blob);
          html.AnchorElement(href: url)
            ..setAttribute("download", zipFilename)
            ..click();
          html.Url.revokeObjectUrl(url);
        } else {
          await Printing.sharePdf(bytes: zipBytes, filename: zipFilename);
        }
      }

      if (!individualPDFs) {
        await Printing.layoutPdf(onLayout: (format) => singlePdf.save(), name: 'Hata_Kitapcigi.pdf');
      }
    } catch (e) {
      print('Composite PDF Critical Error: $e');
    }
  }



  pw.Widget _buildSubjectAnswerKey(String subject, List<Map<String, dynamic>> questions, pw.Font bold, pw.Font reg) {
    final sortedQ = List<Map<String, dynamic>>.from(questions)..sort((a, b) => (a['sequenceNo'] as int).compareTo(b['sequenceNo'] as int));
    
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: const pw.BoxDecoration(color: PdfColors.indigo900, borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
                child: pw.Text(subject.toUpperCase(), style: pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.white)),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(child: pw.Divider(color: PdfColors.indigo100, thickness: 0.5)),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Wrap(
            spacing: 6,
            runSpacing: 4,
            children: sortedQ.map((q) => pw.Container(
              width: 46,
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text('${q['sequenceNo']}.', style: pw.TextStyle(font: reg, fontSize: 8, color: PdfColors.grey600)),
                  pw.SizedBox(width: 3),
                  pw.Text('${q['correctAnswer']}', style: pw.TextStyle(font: bold, fontSize: 10, color: PdfColors.indigo900)),
                ],
              ),
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

  static const double _fullPageWidth = 544.0; // Fits safely inside A4 (595.28 - 2*24 = 547.28)
  static const double _colWidth = 262.0;
  static const double _centerCorridorWidth = 20.0; // 262 + 20 + 262 = 544

  /// Builds a professional Turkish test-booklet layout:
  /// - 1-column questions are packed page-by-page into two balanced vertical
  ///   columns (`Left Column` | `Vertical Divider Line` | `Right Column`).
  ///   When `smartOrder` is enabled, questions are selected using best-fit bin
  ///   packing so that columns are filled (up to 3 questions per column, or 2
  ///   questions aligned to top & bottom lines when 3 don't fit) to minimize
  ///   total page count.
  /// - 2-column questions (`isWide == true`) and Shared Passage groups
  ///   (`Ortak Metin`) span across both columns (`540pt`), cleanly interrupting
  ///   and resuming the center divider line. Tall/full-page 2-column questions
  ///   expand up to full page height (`625pt`) so graphics and text remain
  ///   large and readable.
  List<pw.Widget> _buildProfessionalTestLayout(
    List<Map<String, dynamic>> sortedQ,
    pw.Font bold,
    pw.Font reg, {
    double firstPageAvailH = 605.0,
    double fullPageAvailH = 665.0, // Safe printable height between header & footer
    double lastPageBottomReserveH = 0.0,
    bool smartOrder = true,
    List<Map<String, dynamic>>? outVisualOrder,
    void Function(double finalRemPageH)? onFinalRemPageH,
  }) {
    final List<pw.Widget> wgs = [];
    _activeFullPageAvailH = fullPageAvailH;
    double remPageH = firstPageAvailH; // First page has the subject/test banner
    bool hasBlockOnCurrentPage = false;
    int seqCounter = 0;

    void assignSeq(Map<String, dynamic> q) {
      seqCounter++;
      q['sequenceNo'] = seqCounter;
      outVisualOrder?.add(q);
    }

    void startNewPage() {
      wgs.add(pw.NewPage());
      remPageH = fullPageAvailH;
      hasBlockOnCurrentPage = false;
    }

    // Geniş (2 sütun) sorularda akıllı yarı-sayfa sığdırma kuralı:
    // - Eğer bir geniş soru tek başına sayfanın %65'ini veya fazlasını kaplıyorsa (>= 0.65 * pageH),
    //   küçültülmez, tam boyutta kalır.
    // - Eğer yüksekliği sayfanın %65'ini geçmiyorsa (< 0.65 * pageH), bir sayfaya iki soru
    //   (örn. 14. ve 15. soru veya üstte 5-6, altta 7. soru) sığdırabilmek adına ortalı şekilde
    //   sayfanın ~%47'sine (yarı sayfaya) daraltılır.
    double effectiveWideHeight(Map<String, dynamic> q, double pageCapH) {
      final double rawH = _estimateWideQuestionHeight(q);
      if (rawH >= fullPageAvailH * 0.65) {
        return rawH;
      }
      final double halfPageMaxH = (pageCapH - _kQuestionGap - 6.0) * 0.50;
      return rawH > halfPageMaxH ? halfPageMaxH : rawH;
    }

    int i = 0;
    while (i < sortedQ.length) {
      // 1. Collect consecutive 1-column (narrow, non-passage) questions
      final List<Map<String, dynamic>> narrowPool = [];
      while (i < sortedQ.length &&
          sortedQ[i]['isWide'] != true &&
          sortedQ[i]['passageBytes'] == null) {
        narrowPool.add(sortedQ[i]);
        i++;
      }

      // Pack narrowPool into page-aware 2-column blocks with a vertical center divider line
      while (narrowPool.isNotEmpty) {
        final double minFirstH = _estimateNarrowQuestionHeight(narrowPool.first, widthScale: 0.90);

        // If remaining space on current page cannot fit the question, move to a fresh page
        if (remPageH < minFirstH + 6 && hasBlockOnCurrentPage) {
          startNewPage();
        }

        List<Map<String, dynamic>> bestLeft = [];
        List<Map<String, dynamic>> bestRight = [];

        if (smartOrder) {
          final paired = _selectSmartTwoColumnPair(narrowPool, remPageH);
          bestLeft = paired.left;
          bestRight = paired.right;
        } else {
          // Fixed order: preserve exact question sequence
          int bestK = 1;
          bestLeft = [narrowPool.first];
          bestRight = [];

          for (int k = 1; k <= narrowPool.length && k <= 6; k++) {
            final slice = narrowPool.sublist(0, k);
            if (k == 1) {
              bestK = 1;
              bestLeft = [slice[0]];
              bestRight = [];
              continue;
            }
            int chosenSplit = (k / 2).ceil();
            double minMaxColH = double.infinity;
            for (int split = 1; split < k; split++) {
              final lH = _sumNarrowColumnHeight(slice.sublist(0, split));
              final rH = _sumNarrowColumnHeight(slice.sublist(split));
              final maxH = lH > rH ? lH : rH;
              if (maxH < minMaxColH) {
                minMaxColH = maxH;
                chosenSplit = split;
              }
            }
            final candLeft = slice.sublist(0, chosenSplit);
            final candRight = slice.sublist(chosenSplit);
            final minLH = _sumNarrowColumnHeight(candLeft, widthScale: 0.90);
            final minRH = _sumNarrowColumnHeight(candRight, widthScale: 0.90);
            final minReadableSectionH = minLH > minRH ? minLH : minRH;
            if (minReadableSectionH <= remPageH) {
              bestK = k;
              bestLeft = candLeft;
              bestRight = candRight;
            } else {
              break;
            }
          }
          narrowPool.removeRange(0, bestK);
        }

        // Assign sequential numbers in visual column order (Left top->bottom, then Right top->bottom)
        for (final q in bestLeft) {
          assignSeq(q);
        }
        for (final q in bestRight) {
          assignSeq(q);
        }

        final double lH = _sumNarrowColumnHeight(bestLeft);
        final double rH = _sumNarrowColumnHeight(bestRight);
        final double naturalMaxColH = lH > rH ? lH : rH;

        // Check if another block (wide question or passage) will fit on this SAME page below this 2-col section
        bool anotherBlockFitsBelow = false;
        if (narrowPool.isEmpty && i < sortedQ.length) {
          final nextQ = sortedQ[i];
          final double nextNeededH = nextQ['passageBytes'] != null
              ? _estimatePassageFirstBlockHeight(nextQ)
              : effectiveWideHeight(nextQ, remPageH);
          if (naturalMaxColH + 18.0 + nextNeededH <= remPageH) {
            anotherBlockFitsBelow = true;
          }
        }

        // Tam sayfa dikey hizalama (Akıllı Dizgi):
        // Sütunlarda 2+ soru varsa üstteki soru üst çizgide başlar, alttaki soru alt çizgide biter
        // ve aradaki boşluk eşit dağıtılır. Son sayfada cevap anahtarı şeridi aynı sayfaya sığıyorsa
        // onun yüksekliği düşülerek kalan alan doldurulur.
        final bool hasMultiRowCol = bestLeft.length >= 2 || bestRight.length >= 2;
        final bool isVeryLastBlock = narrowPool.isEmpty && i >= sortedQ.length;
        double effectiveAvailH = remPageH - 4.0;
        if (isVeryLastBlock && lastPageBottomReserveH > 0) {
          if (naturalMaxColH + lastPageBottomReserveH <= remPageH) {
            effectiveAvailH = remPageH - lastPageBottomReserveH - 4.0;
          }
        }
        final bool finishesPage = narrowPool.isNotEmpty ||
            (!isVeryLastBlock && !anotherBlockFitsBelow && hasMultiRowCol) ||
            (isVeryLastBlock &&
                hasMultiRowCol &&
                naturalMaxColH >= effectiveAvailH * 0.48);
        final double targetSectionH = finishesPage
            ? effectiveAvailH.clamp(naturalMaxColH.clamp(80.0, remPageH), remPageH)
            : naturalMaxColH.clamp(80.0, remPageH);

        wgs.add(
          _buildTwoColumnSection(
            bestLeft,
            bestRight,
            targetSectionH,
            bold,
            reg,
            stretchColumnsToBottom: finishesPage,
          ),
        );
        hasBlockOnCurrentPage = true;
        remPageH -= targetSectionH;

        if (narrowPool.isNotEmpty) {
          startNewPage();
        } else if (i < sortedQ.length) {
          if (!anotherBlockFitsBelow) {
            startNewPage();
          }
        }
      }

      // 2. Shared-passage question group (spans full 2-column width)
      if (i < sortedQ.length && sortedQ[i]['passageBytes'] != null) {
        final String? pid = sortedQ[i]['passageId'] as String?;
        final List<Map<String, dynamic>> passageGroup = [sortedQ[i]];
        i++;
        if (pid != null && pid.isNotEmpty) {
          while (i < sortedQ.length && sortedQ[i]['passageId'] == pid) {
            passageGroup.add(sortedQ[i]);
            i++;
          }
        }

        for (final pq in passageGroup) {
          assignSeq(pq);
        }

        final double firstBlockH = _estimatePassageFirstBlockHeight(passageGroup.first);
        if (remPageH < firstBlockH && hasBlockOnCurrentPage) {
          startNewPage();
        } else if (hasBlockOnCurrentPage) {
          wgs.add(pw.SizedBox(height: 14));
          remPageH -= 14.0;
        }

        final passageWidgets = _buildPassageGroup(passageGroup, bold, reg);
        wgs.addAll(passageWidgets);
        hasBlockOnCurrentPage = true;
        remPageH -= firstBlockH;
        for (int idx = 1; idx < passageGroup.length; idx++) {
          final qH = _estimateWideQuestionHeight(passageGroup[idx]);
          if (remPageH < qH) {
            remPageH = fullPageAvailH - qH;
          } else {
            remPageH -= (qH + 8.0);
          }
        }

        if (i < sortedQ.length) {
          wgs.add(pw.SizedBox(height: 14));
          remPageH -= 14.0;
        }
        continue;
      }

      // 3. 2-Column Wide Questions (`isWide == true`, spans full 2-column width)
      //    - Yüksekliği sayfanın %65'ini geçmeyen (< %65) geniş sorular ortalı şekilde ~%47 yüksekliğe
      //      daraltılarak bir sayfaya 2 soru sığdırılır (1. soru üst çizgide, 2. soru alt çizgide).
      //    - Sayfanın üstünde 2 sütunlu bir blok varsa (örn. 5. ve 6. soru üstte) ve altında tek bir
      //      geniş soru (örn. 7. soru) yer alıyorsa, 7. soru sayfanın alt sınırına yaslanır!
      if (i < sortedQ.length && sortedQ[i]['isWide'] == true) {
        final double firstEffH = effectiveWideHeight(sortedQ[i], fullPageAvailH);
        if (hasBlockOnCurrentPage && remPageH < firstEffH + 18.0) {
          startNewPage();
        }

        final double pageCapForGroup = hasBlockOnCurrentPage ? remPageH : fullPageAvailH;
        final List<Map<String, dynamic>> wideGroup = [];
        final List<double> wideHeights = [];
        double usedH = 0.0;
        while (i < sortedQ.length &&
            sortedQ[i]['isWide'] == true &&
            sortedQ[i]['passageBytes'] == null) {
          final double rawH = _estimateWideQuestionHeight(sortedQ[i]);
          final double effH = effectiveWideHeight(sortedQ[i], pageCapForGroup);
          // Eğer tek başına sayfanın >= %65'ini kaplayan dev bir soruysa küçültme
          final double candH = (!hasBlockOnCurrentPage &&
                  wideGroup.isEmpty &&
                  rawH >= fullPageAvailH * 0.65)
              ? rawH
              : effH;
          final double gapNeeded = (wideGroup.isEmpty && !hasBlockOnCurrentPage)
              ? 0.0
              : (wideGroup.isEmpty ? 18.0 : _kQuestionGap);
          final double need = usedH + gapNeeded + candH;
          if (wideGroup.isNotEmpty && need > remPageH - 4.0) break;
          wideGroup.add(sortedQ[i]);
          wideHeights.add(candH);
          usedH = need;
          i++;
          if (usedH >= remPageH - 4.0) break;
        }

        for (final q in wideGroup) {
          assignSeq(q);
        }

        // Sonraki blok bu sayfada kalan boşluğa sığacak mı?
        bool nextFitsBelow = false;
        if (i < sortedQ.length) {
          final nextQ = sortedQ[i];
          final double nextH = nextQ['passageBytes'] != null
              ? _estimatePassageFirstBlockHeight(nextQ)
              : (nextQ['isWide'] == true
                  ? effectiveWideHeight(nextQ, fullPageAvailH)
                  : _estimateNarrowQuestionHeight(nextQ, widthScale: 0.90));
          nextFitsBelow = usedH + _kQuestionGap + nextH <= remPageH;
        }

        final bool isVeryLastBlock = i >= sortedQ.length;
        double availForThisSection = remPageH - 4.0;
        if (isVeryLastBlock && lastPageBottomReserveH > 0) {
          if (usedH + lastPageBottomReserveH <= remPageH) {
            availForThisSection = remPageH - lastPageBottomReserveH - 4.0;
          }
        }

        if (wideGroup.length == 1) {
          final q = wideGroup.first;
          final double wideH = wideHeights.first;
          final double allowedBoxH = wideH.clamp(140.0, availForThisSection);

          // EĞER sayfanın üstünde başka bir blok varsa (örn. 5. ve 6. soru üstte, 7. soru altta)
          // ve bu 7. soru sayfanın son bloğuysa → 7. soruyu sayfanın ALT ÇİZGİSİNE YASLA!
          if (hasBlockOnCurrentPage && !nextFitsBelow) {
            final double containerH = availForThisSection.clamp(allowedBoxH + 12.0, remPageH);
            wgs.add(
              pw.Inseparable(
                child: pw.Container(
                  width: _fullPageWidth,
                  height: containerH,
                  alignment: pw.Alignment.bottomCenter,
                  child: _buildFullWidth(q, bold, reg, maxTotalHeight: allowedBoxH),
                ),
              ),
            );
            remPageH -= containerH;
            if (!isVeryLastBlock) {
              startNewPage();
            }
          } else {
            if (hasBlockOnCurrentPage) {
              wgs.add(pw.SizedBox(height: 18));
              remPageH -= 18.0;
            }
            wgs.add(_buildFullWidth(q, bold, reg, maxTotalHeight: allowedBoxH));
            hasBlockOnCurrentPage = true;
            final double consumedH = wideH > allowedBoxH ? allowedBoxH : wideH;
            remPageH -= consumedH;
            if (!isVeryLastBlock && !nextFitsBelow) {
              startNewPage();
            }
          }
        } else {
          // Aynı sayfada 2 (veya daha fazla) geniş soru (örn. 14. ve 15. soru):
          // İlk soru üst çizgide, son soru alt çizgide olacak şekilde dikeyde eşit yayılır.
          if (hasBlockOnCurrentPage) {
            wgs.add(pw.SizedBox(height: 18));
            remPageH -= 18.0;
            availForThisSection = (availForThisSection - 18.0).clamp(usedH, remPageH);
          }
          final bool finishesPage = !nextFitsBelow;
          final double boxH = finishesPage
              ? availForThisSection.clamp(usedH, remPageH)
              : usedH;
          wgs.add(
            pw.Inseparable(
              child: pw.Container(
                height: boxH,
                child: pw.Column(
                  mainAxisAlignment: finishesPage
                      ? pw.MainAxisAlignment.spaceBetween
                      : pw.MainAxisAlignment.start,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    for (int g = 0; g < wideGroup.length; g++) ...[
                      _buildFullWidth(
                        wideGroup[g],
                        bold,
                        reg,
                        maxTotalHeight: wideHeights[g],
                      ),
                      if (!finishesPage && g < wideGroup.length - 1)
                        pw.SizedBox(height: _kQuestionGap),
                    ],
                  ],
                ),
              ),
            ),
          );
          hasBlockOnCurrentPage = true;
          remPageH -= boxH;
          if (!isVeryLastBlock && finishesPage) {
            startNewPage();
          }
        }
      }
    }

    onFinalRemPageH?.call(remPageH);
    return wgs;
  }

  /// Sorular arasındaki ideal minimum boşluk (pt). Sayfa doluyken fazla boşluk sorular arasına eşit dağıtılır.
  static const double _kQuestionGap = 32.0;

  /// Etkin dizgide bir sayfanın soru alanı yüksekliği (üst bilgi ile alt bilgi arası, pt).
  double _activeFullPageAvailH = 665.0;

  /// Çift sütunlu akıllı dizgi kombinasyon seçici:
  /// Havuzdaki sıradaki adaylar arasından Sol ve Sağ sütunu BİRLİKTE seçer:
  /// - Uzun soru + kısa soruyu aynı sütunda eşleştirerek (`tall + short | tall + short`) veya
  ///   3 kısa soruyu 2 orta-uzun soruyla dengeleyerek (`3 short | 2 medium-tall`) iki sütunun
  ///   toplam yüksekliğini birbirine yaklaştırır (`|lH - rH|` minimum),
  /// - Bir sütuna en fazla 3 soru koyar (4 soru üst üste sıkıştırmaz) ve 3 soruya yalnızca
  ///   sorular gerçekten kısaysa ve aralarında ferah boşluk kalıyorsa izin verir,
  /// - Her iki sütunda da mümkün olduğunca en az 2 soru bulundurur ki üstteki sorular üst çizgide,
  ///   alttaki sorular alt çizgide tam hizalansın ve aralarında ferah boşluk kalsın.
  ({List<Map<String, dynamic>> left, List<Map<String, dynamic>> right})
      _selectSmartTwoColumnPair(
    List<Map<String, dynamic>> narrowPool,
    double maxColH,
  ) {
    if (narrowPool.isEmpty) {
      return (left: <Map<String, dynamic>>[], right: <Map<String, dynamic>>[]);
    }
    if (narrowPool.length == 1) {
      return (
        left: <Map<String, dynamic>>[narrowPool.removeAt(0)],
        right: <Map<String, dynamic>>[],
      );
    }

    final int m = narrowPool.length < 14 ? narrowPool.length : 14;
    final List<double> hNat = List<double>.generate(
      m,
      (idx) => _estimateNarrowQuestionHeight(narrowPool[idx], widthScale: 1.0),
    );
    final List<double> hMin = List<double>.generate(
      m,
      (idx) => _estimateNarrowQuestionHeight(narrowPool[idx], widthScale: 0.92),
    );

    final List<({int mask, List<int> indices, double natH, double minH})>
        candCols = [];

    void addIfFits(List<int> idxs) {
      final int k = idxs.length;
      double sumNat = (k - 1) * _kQuestionGap;
      double sumMin = (k - 1) * _kQuestionGap;
      int mask = 0;
      for (final idx in idxs) {
        sumNat += hNat[idx];
        sumMin += hMin[idx];
        mask |= (1 << idx);
      }
      // 3 sorulu sütuna yalnızca görseller küçültülmeden ve ferah boşlukla sığıyorsa izin ver
      if (k == 1 ||
          (k == 2 && sumMin <= maxColH * 0.96) ||
          (k == 3 && sumNat <= maxColH * 0.88)) {
        candCols.add((
          mask: mask,
          indices: idxs,
          natH: sumNat,
          minH: sumMin,
        ));
      }
    }

    for (int a = 0; a < m; a++) {
      addIfFits([a]);
      for (int b = a + 1; b < m; b++) {
        addIfFits([a, b]);
        for (int c = b + 1; c < m; c++) {
          addIfFits([a, b, c]);
        }
      }
    }

    double bestScore = double.negativeInfinity;
    List<int> chosenLeftIdx = [0];
    List<int> chosenRightIdx = narrowPool.length >= 2 ? [1] : const [];

    for (int i = 0; i < candCols.length; i++) {
      final c1 = candCols[i];
      for (int j = i + 1; j < candCols.length; j++) {
        final c2 = candCols[j];
        if ((c1.mask & c2.mask) != 0) continue;

        final leftCand = c1.indices.first < c2.indices.first ? c1 : c2;
        final rightCand = c1.indices.first < c2.indices.first ? c2 : c1;

        final double lH = leftCand.natH;
        final double rH = rightCand.natH;
        final int lLen = leftCand.indices.length;
        final int rLen = rightCand.indices.length;

        // İdeal doluluk (%72 - %88 arası): sorular arasında ferah boşluk bırakır, sıkıştırmaz
        final double effL = lH.clamp(0.0, maxColH * 0.92);
        final double effR = rH.clamp(0.0, maxColH * 0.92);
        final double avgFill = (effL + effR) / (2.0 * maxColH);
        final double diffRatio = ((lH - rH).abs() / maxColH).clamp(0.0, 1.0);

        double score = (avgFill * 2.1) + ((1.0 - diffRatio) * 1.55);

        // Her iki sütunda 2+ soru varsa hem üst çizgi hem alt çizgi tam hizalanır
        if (lLen >= 2 && rLen >= 2) {
          score += 1.25;
          // 2+2 dizilim ferahlık açısından en ideal yapıdır; çok sıkışık 3+3 yerine tercih edilir
          if (lLen == 2 && rLen == 2) {
            score += 0.22;
          }
        } else if (lLen >= 2 || rLen >= 2) {
          final double singleH = lLen == 1 ? lH : rH;
          if (singleH >= maxColH * 0.65) {
            score += 0.55;
          } else {
            score -= 0.55;
          }
        } else {
          // 1+1 durumu: yalnızca ikisi de çok uzun sorularsa veya havuzda 2 soru kaldıysa iyi
          if (lH >= maxColH * 0.62 && rH >= maxColH * 0.62) {
            score += 0.45;
          } else if (narrowPool.length > 2) {
            score -= 0.85;
          }
        }

        // Görselleri küçültmeden ve ferah boşlukla sığma ödülü
        if (lH <= maxColH * 0.90 && rH <= maxColH * 0.90) {
          score += 0.55;
        } else if (lH <= maxColH && rH <= maxColH) {
          score += 0.20;
        } else {
          final double overL = lH > maxColH ? (lH - maxColH) : 0.0;
          final double overR = rH > maxColH ? (rH - maxColH) : 0.0;
          score -= ((overL + overR) / maxColH) * 2.2;
        }

        // Orijinal soru sırasını koruma bonusu
        double orderBonus = 0.0;
        for (final idx in leftCand.indices) {
          orderBonus += ((m - idx) / m) * 0.07;
        }
        for (final idx in rightCand.indices) {
          orderBonus += ((m - idx) / m) * 0.07;
        }
        if (leftCand.indices.first == 0) {
          orderBonus += 0.14;
        }
        score += orderBonus;

        if (score > bestScore) {
          bestScore = score;
          chosenLeftIdx = leftCand.indices;
          chosenRightIdx = rightCand.indices;
        }
      }
    }

    final List<Map<String, dynamic>> bestLeft = [
      for (final idx in chosenLeftIdx) narrowPool[idx],
    ];
    final List<Map<String, dynamic>> bestRight = [
      for (final idx in chosenRightIdx) narrowPool[idx],
    ];

    final List<int> allUsed = [...chosenLeftIdx, ...chosenRightIdx]..sort();
    for (final idx in allUsed.reversed) {
      narrowPool.removeAt(idx);
    }

    return (left: bestLeft, right: bestRight);
  }

  double _sumNarrowColumnHeight(List<Map<String, dynamic>> col, {double widthScale = 1.0}) {
    if (col.isEmpty) return 0.0;
    double total = 0.0;
    for (int idx = 0; idx < col.length; idx++) {
      total += _estimateNarrowQuestionHeight(col[idx], widthScale: widthScale);
      if (idx < col.length - 1) total += _kQuestionGap;
    }
    return total;
  }

  double _estimateNarrowQuestionHeight(Map<String, dynamic> q, {double widthScale = 1.0}) {
    final Uint8List bytes = q['imageBytes'] as Uint8List;
    final double ar = _getImageAspectRatio(bytes);
    // Allow tall 1-column questions to keep full column width up to 580pt height!
    final double imgH = ((_colWidth * widthScale) * ar).clamp(55.0, 580.0);
    return 22.0 + 5.0 + imgH + 4.0; // header + gap + image + padding
  }

  double _estimateWideQuestionHeight(Map<String, dynamic> q) {
    final Uint8List bytes = q['imageBytes'] as Uint8List;
    final double ar = _getImageAspectRatio(bytes);
    // Allow tall/full-page 2-column questions (like multi-chart or 4-diagram questions)
    // to expand up to 625pt (full page height) instead of crushing them to 360pt!
    final double imgH = ((_fullPageWidth - 6.0) * ar).clamp(65.0, 625.0);
    return 24.0 + 6.0 + imgH + 6.0;
  }

  double _estimatePassageFirstBlockHeight(Map<String, dynamic> firstQ) {
    final Uint8List pBytes = firstQ['passageBytes'] as Uint8List;
    final Uint8List qBytes = firstQ['imageBytes'] as Uint8List;
    final double pH = (520.0 * _getImageAspectRatio(pBytes)).clamp(55.0, 210.0);
    final double qH = (520.0 * _getImageAspectRatio(qBytes)).clamp(60.0, 250.0);
    return 34.0 + pH + 14.0 + 26.0 + qH + 18.0;
  }

  pw.Widget _buildTwoColumnSection(
    List<Map<String, dynamic>> leftCol,
    List<Map<String, dynamic>> rightCol,
    double sectionHeight,
    pw.Font bold,
    pw.Font reg, {
    bool stretchColumnsToBottom = false,
  }) {
    final double dividerH = sectionHeight.clamp(60.0, _activeFullPageAvailH);

    // Sütun içinde 2 veya 3 soru olduğunda MainAxisAlignment.spaceBetween ile
    // ilk soru tam üst çizgide başlar, son soru tam alt çizgide biter ve aradaki
    // boşluk eşit dağıtılır. Görsellerin toplam yüksekliği dividerH bütçesini
    // asla aşmayacak şekilde hesaplanır (taşma olmaz ve sorular birbirine yapışmaz).
    pw.Widget buildColumnBox(List<Map<String, dynamic>> col) {
      if (col.isEmpty) return pw.SizedBox(width: _colWidth);
      final int k = col.length;
      const double headerAndPadPerItem = 28.0;
      final double minGapTotal = k >= 2 ? (k - 1) * 26.0 : 0.0;
      final double maxTotalImgH = (dividerH - (k * headerAndPadPerItem) - minGapTotal)
          .clamp(45.0 * k, dividerH);

      final List<double> unscaledImgHs = col.map((q) {
        final Uint8List bytes = q['imageBytes'] as Uint8List;
        final double ar = _getImageAspectRatio(bytes);
        return (_colWidth * ar).clamp(55.0, 580.0);
      }).toList();

      final double sumUnscaledImgH = unscaledImgHs.fold<double>(0.0, (a, b) => a + b);
      final double colScale = (sumUnscaledImgH > maxTotalImgH && sumUnscaledImgH > 0)
          ? (maxTotalImgH / sumUnscaledImgH).clamp(0.84, 1.0)
          : 1.0;

      final List<pw.Widget> items = [
        for (int idx = 0; idx < k; idx++)
          _buildHalfWidth(
            col[idx],
            bold,
            reg,
            widthScale: colScale,
            maxImgHeight: sumUnscaledImgH > 0
                ? (maxTotalImgH * (unscaledImgHs[idx] / sumUnscaledImgH)).clamp(45.0, 580.0)
                : 580.0,
          ),
      ];

      if (items.length >= 2) {
        return pw.Container(
          width: _colWidth,
          height: dividerH,
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: items,
          ),
        );
      }
      return pw.Container(
        width: _colWidth,
        height: stretchColumnsToBottom ? dividerH : null,
        alignment: pw.Alignment.topLeft,
        child: items.first,
      );
    }

    return pw.Inseparable(
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          buildColumnBox(leftCol),
          pw.Container(
            width: _centerCorridorWidth,
            height: dividerH,
            alignment: pw.Alignment.topCenter,
            child: pw.Container(
              width: 0.9,
              height: dividerH,
              color: PdfColors.indigo200,
            ),
          ),
          buildColumnBox(rightCol),
        ],
      ),
    );
  }

  pw.Widget _questionHeader(Map<String, dynamic> q, pw.Font bold, {bool isNarrow = false, double? customWidth}) {
    final headerWidth = customWidth ?? (isNarrow ? _colWidth : _fullPageWidth);
    final bool isYaprak = q['isYaprakTest'] == true;
    final bool showOutcome = q['showOutcome'] != false;
    final String rightLabel = (q['questionRightLabel'] ?? 'eduKN').toString();
    final String subtitleText = !showOutcome
        ? ''
        : (isYaprak
            ? ((q['outcome'] ?? q['subject'] ?? '').toString())
            : '${q['examName']} (${q['booklet']}-${q['questionNo']})');
    return pw.Container(
      width: headerWidth,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const pw.BoxDecoration(
        color: PdfColors.indigo50,
        border: pw.Border(left: pw.BorderSide(color: PdfColors.indigo900, width: 3)),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: const pw.BoxDecoration(
              color: PdfColors.indigo900,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            child: pw.Text(
              '${q['sequenceNo']}. SORU',
              style: pw.TextStyle(font: bold, fontSize: isNarrow ? 7.5 : 8.5, color: PdfColors.white),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: subtitleText.isNotEmpty
                ? pw.Text(
                    subtitleText,
                    style: pw.TextStyle(font: bold, fontSize: isNarrow ? 6.5 : 7.5, color: PdfColors.indigo700),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                  )
                : pw.SizedBox.shrink(),
          ),
          if (rightLabel.isNotEmpty)
            pw.Text(rightLabel, style: pw.TextStyle(font: bold, fontSize: isNarrow ? 6.5 : 7.5, color: PdfColors.indigo300)),
        ],
      ),
    );
  }

  List<pw.Widget> _buildPassageGroup(
      List<Map<String, dynamic>> group, pw.Font bold, pw.Font reg) {
    if (group.isEmpty) return [];
    final Uint8List passageBytes = group.first['passageBytes'] as Uint8List;
    final List<int> seqs = group.map((q) => q['sequenceNo'] as int).toList();
    final String rangeLabel;
    if (seqs.length == 1) {
      rangeLabel = '${seqs.first}. soruyu aşağıdaki metne göre cevaplayınız.';
    } else if (seqs.length == 2) {
      rangeLabel = '${seqs[0]} ve ${seqs[1]}. soruları aşağıdaki metne göre cevaplayınız.';
    } else {
      final head = seqs.sublist(0, seqs.length - 1).join(', ');
      rangeLabel = '$head ve ${seqs.last}. soruları aşağıdaki metne göre cevaplayınız.';
    }

    final widgets = <pw.Widget>[];
    const double innerW = _fullPageWidth - 12.0;

    // Keep the shared passage + first question (or passage banner) within safe single-page height (< 550pt)
    final bool useTwoColForGroup = group.length >= 2 && group.every((q) => q['isWide'] != true);

    widgets.add(
      pw.Inseparable(
        child: pw.Container(
          width: _fullPageWidth,
          padding: const pw.EdgeInsets.only(left: 8, top: 6, bottom: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(color: PdfColors.indigo900, width: 3),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: innerW,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.indigo50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                  border: pw.Border.all(color: PdfColors.indigo200, width: 0.8),
                ),
                child: pw.Row(
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.indigo900,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                      ),
                      child: pw.Text(
                        'ORTAK METİN',
                        style: pw.TextStyle(font: bold, fontSize: 7, color: PdfColors.white),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: pw.Text(
                        rangeLabel,
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 9.5,
                          color: PdfColors.indigo900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                width: innerW,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
                ),
                child: pw.Center(
                  child: pw.Container(
                    constraints: const pw.BoxConstraints(maxHeight: 205),
                    child: pw.Image(
                      pw.MemoryImage(passageBytes),
                      width: innerW - 14,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
              ),
              if (!useTwoColForGroup) ...[
                pw.SizedBox(height: 10),
                _questionHeader(group.first, bold, customWidth: innerW),
                pw.SizedBox(height: 6),
                pw.Container(
                  constraints: const pw.BoxConstraints(maxHeight: 250),
                  width: group.first['isWide'] == true ? innerW - 8 : (_colWidth * 1.15),
                  alignment: pw.Alignment.topLeft,
                  child: pw.Image(
                    pw.MemoryImage(group.first['imageBytes'] as Uint8List),
                    width: group.first['isWide'] == true ? innerW - 8 : (_colWidth * 1.15),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (useTwoColForGroup) {
      final int split = (group.length / 2).ceil();
      final leftG = group.sublist(0, split);
      final rightG = group.sublist(split);
      final double lH = _sumNarrowColumnHeight(leftG);
      final double rH = _sumNarrowColumnHeight(rightG);
      final double secH = (lH > rH ? lH : rH).clamp(80.0, 390.0);
      widgets.add(pw.SizedBox(height: 8));
      widgets.add(_buildTwoColumnSection(leftG, rightG, secH, bold, reg));
    } else {
      for (int idx = 1; idx < group.length; idx++) {
        final q = group[idx];
        final double qTargetW = q['isWide'] == true ? innerW - 8 : (_colWidth * 1.15);
        widgets.add(pw.SizedBox(height: 8));
        widgets.add(
          pw.Inseparable(
            child: pw.Container(
              width: _fullPageWidth,
              padding: const pw.EdgeInsets.only(left: 8, top: 4, bottom: 6),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  left: pw.BorderSide(color: PdfColors.indigo900, width: 3),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _questionHeader(q, bold, customWidth: innerW),
                  pw.SizedBox(height: 6),
                  pw.Container(
                    constraints: const pw.BoxConstraints(maxHeight: 260),
                    width: qTargetW,
                    alignment: pw.Alignment.topLeft,
                    child: pw.Image(
                      pw.MemoryImage(q['imageBytes'] as Uint8List),
                      width: qTargetW,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  pw.Widget _buildFullWidth(
    Map<String, dynamic> q,
    pw.Font bold,
    pw.Font reg, {
    double maxTotalHeight = 660.0,
  }) {
    final Uint8List bytes = q['imageBytes'] as Uint8List;
    final double ar = _getImageAspectRatio(bytes);
    final double targetW = _fullPageWidth - 4.0;
    final double maxImgH = (maxTotalHeight - 34.0).clamp(110.0, 625.0);
    final double rawImgH = (targetW * ar).clamp(65.0, 625.0);
    final double naturalH = rawImgH > maxImgH ? maxImgH : rawImgH;
    // Soru yüksekliği yarı-sayfaya (%50) sınırlandığında görsel en/boy oranını koruyarak
    // yatayda ortalı şekilde daralır.
    final double effectiveImgW = (rawImgH > maxImgH && ar > 0)
        ? (naturalH / ar).clamp(220.0, targetW)
        : targetW;
    return pw.Inseparable(
      child: pw.Container(
        width: _fullPageWidth,
        padding: const pw.EdgeInsets.only(bottom: 4),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            _questionHeader(q, bold),
            pw.SizedBox(height: 6),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 2),
              child: pw.Container(
                height: naturalH,
                width: targetW,
                alignment: pw.Alignment.topCenter,
                child: pw.Image(
                  pw.MemoryImage(bytes),
                  width: effectiveImgW,
                  height: naturalH,
                  fit: pw.BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildHalfWidth(
    Map<String, dynamic> q,
    pw.Font bold,
    pw.Font reg, {
    double widthScale = 1.0,
    double maxImgHeight = 580.0,
  }) {
    final Uint8List bytes = q['imageBytes'] as Uint8List;
    final double ar = _getImageAspectRatio(bytes);
    final double renderW = (_colWidth * widthScale).clamp(_colWidth * 0.84, _colWidth);
    final double rawH = (renderW * ar).clamp(50.0, 580.0);
    final double naturalH = rawH > maxImgHeight ? maxImgHeight : rawH;
    return pw.Container(
      width: _colWidth,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _questionHeader(q, bold, isNarrow: true),
          pw.SizedBox(height: 5),
          pw.Container(
            height: naturalH,
            width: _colWidth,
            alignment: pw.Alignment.topLeft,
            child: pw.Image(
              pw.MemoryImage(bytes),
              width: renderW,
              height: naturalH,
              fit: pw.BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }

  /// PNG / JPEG başlığından piksel genişliğini okur (bulunamazsa 0).
  int _getImagePixelWidth(Uint8List bytes) {
    try {
      if (bytes.length < 24) return 0;
      if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        return (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        int offset = 2;
        while (offset + 9 < bytes.length) {
          if (bytes[offset] != 0xFF) {
            offset++;
            continue;
          }
          final int marker = bytes[offset + 1];
          if (marker == 0xFF) {
            offset++;
            continue;
          }
          if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) {
            offset += 2;
            continue;
          }
          final int segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];
          if (segLen < 2) break;
          final bool isSof = (marker >= 0xC0 && marker <= 0xC3) ||
              (marker >= 0xC5 && marker <= 0xC7) ||
              (marker >= 0xC9 && marker <= 0xCB) ||
              (marker >= 0xCD && marker <= 0xCF);
          if (isSof && offset + 8 < bytes.length) {
            return (bytes[offset + 7] << 8) | bytes[offset + 8];
          }
          offset += 2 + segLen;
        }
      }
    } catch (_) {}
    return 0;
  }

  /// Görsel baytlarının hızlı parmak izi (FNV-1a) — aynı görselin teste iki kez girmesini önlemek için.
  String _bytesFingerprint(Uint8List bytes) {
    int h = 0x811c9dc5;
    final int step = bytes.length > 200000 ? 7 : 1;
    for (int k = 0; k < bytes.length; k += step) {
      h ^= bytes[k];
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return '${bytes.length}_$h';
  }

  /// Fast pure-Dart JPEG & PNG header parser to extract exact `height / width`
  /// aspect ratio without decoding pixel buffers.
  double _getImageAspectRatio(Uint8List bytes) {
    try {
      if (bytes.length < 24) return 0.62;
      // PNG: 89 50 4E 47 0D 0A 1A 0A, IHDR width at [16..19], height at [20..23]
      if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        final int w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
        final int h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        if (w > 0 && h > 0) return (h / w).clamp(0.14, 2.2);
      }
      // JPEG: FF D8 ... scan for SOF0..SOF3 / SOF5..SOF7 / SOF9..SOF11 / SOF13..SOF15
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        int offset = 2;
        while (offset + 9 < bytes.length) {
          if (bytes[offset] != 0xFF) {
            offset++;
            continue;
          }
          final int marker = bytes[offset + 1];
          if (marker == 0xFF) {
            offset++;
            continue;
          }
          if (marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7)) {
            offset += 2;
            continue;
          }
          final int segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];
          if (segLen < 2) break;
          final bool isSof = (marker >= 0xC0 && marker <= 0xC3) ||
              (marker >= 0xC5 && marker <= 0xC7) ||
              (marker >= 0xC9 && marker <= 0xCB) ||
              (marker >= 0xCD && marker <= 0xCF);
          if (isSof && offset + 8 < bytes.length) {
            final int h = (bytes[offset + 5] << 8) | bytes[offset + 6];
            final int w = (bytes[offset + 7] << 8) | bytes[offset + 8];
            if (w > 0 && h > 0) return (h / w).clamp(0.14, 2.2);
            break;
          }
          offset += 2 + segLen;
        }
      }
    } catch (_) {}
    return 0.62;
  }

  /// Cleans scanner shadows, grayish/bluish/yellowish paper tint, and backside
  /// bleed-through from question images on Web before embedding into the PDF.
  Future<Uint8List> _whitenBytesForPdf(Uint8List srcBytes) async {
    if (!kIsWeb || srcBytes.isEmpty) return srcBytes;
    try {
      final b64 = base64Encode(srcBytes);
      final img = html.ImageElement(src: 'data:image/jpeg;base64,$b64');
      await img.onLoad.first.timeout(const Duration(seconds: 3));
      final int w = img.naturalWidth;
      final int h = img.naturalHeight;
      if (w <= 0 || h <= 0) return srcBytes;

      final canvas = html.CanvasElement(width: w, height: h);
      final ctx = canvas.context2D;
      ctx.fillStyle = '#FFFFFF';
      ctx.fillRect(0, 0, w, h);
      ctx.drawImage(img, 0, 0);

      final imgData = ctx.getImageData(0, 0, w, h);
      final data = imgData.data;
      final hist = List<int>.filled(256, 0);
      final int totalPx = w * h;
      final int step = totalPx > 250000 ? 16 : 4;
      for (int i = 0; i < data.length; i += step) {
        final int lum = (data[i] * 77 + data[i + 1] * 150 + data[i + 2] * 29) >> 8;
        hist[lum]++;
      }
      int paperLum = 240;
      int maxCount = 0;
      for (int l = 165; l <= 255; l++) {
        if (hist[l] >= maxCount) {
          maxCount = hist[l];
          paperLum = l;
        }
      }
      final int whiteCutoff = (paperLum - 26).clamp(172, 232);
      const int blackAnchor = 75;
      final int toneSpan = (whiteCutoff - blackAnchor).clamp(1, 255);

      for (int i = 0; i < data.length; i += 4) {
        final int r = data[i];
        final int g = data[i + 1];
        final int b = data[i + 2];
        final int maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
        final int minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
        final int chroma = maxC - minC;
        final int lum = (r * 77 + g * 150 + b * 29) >> 8;

        if (chroma <= 38) {
          if (lum >= whiteCutoff) {
            data[i] = 255;
            data[i + 1] = 255;
            data[i + 2] = 255;
          } else if (lum <= blackAnchor) {
            final int dark = (lum * 0.65).round().clamp(0, 60);
            data[i] = dark;
            data[i + 1] = dark;
            data[i + 2] = dark;
          } else {
            final double norm = (lum - blackAnchor) / toneSpan;
            final double curved = norm * norm * (3.0 - 2.0 * norm);
            final int out = (blackAnchor * 0.65 + curved * (255.0 - blackAnchor * 0.65))
                .round()
                .clamp(0, 255);
            data[i] = out;
            data[i + 1] = out;
            data[i + 2] = out;
          }
        } else if (lum >= 218 && chroma <= 55) {
          data[i] = 255;
          data[i + 1] = 255;
          data[i + 2] = 255;
        }
      }

      ctx.putImageData(imgData, 0, 0);

      // Auto-trim outer white margins so the question content fills 100% of its
      // target column width in the PDF (enlarging small/padded crops automatically).
      final List<int> rowHits = List<int>.filled(h, 0);
      final List<int> colHits = List<int>.filled(w, 0);
      for (int y = 0; y < h; y++) {
        final int rowOff = y * w * 4;
        for (int x = 0; x < w; x++) {
          final int idx = rowOff + (x << 2);
          if (data[idx] < 242 || data[idx + 1] < 242 || data[idx + 2] < 242) {
            rowHits[y]++;
            colHits[x]++;
          }
        }
      }
      int minY = 0;
      int maxY = h - 1;
      int minX = 0;
      int maxX = w - 1;
      while (minY < maxY && rowHits[minY] < 2) {
        minY++;
      }
      while (maxY > minY && rowHits[maxY] < 2) {
        maxY--;
      }
      while (minX < maxX && colHits[minX] < 2) {
        minX++;
      }
      while (maxX > minX && colHits[maxX] < 2) {
        maxX--;
      }

      const int pad = 3;
      final int cropX = (minX - pad).clamp(0, w - 1);
      final int cropY = (minY - pad).clamp(0, h - 1);
      final int cropR = (maxX + pad).clamp(cropX + 1, w);
      final int cropB = (maxY + pad).clamp(cropY + 1, h);
      final int cropW = cropR - cropX;
      final int cropH = cropB - cropY;

      if (cropW > 20 && cropH > 20 && (cropW < w - 4 || cropH < h - 4)) {
        final trimmedCanvas = html.CanvasElement(width: cropW, height: cropH);
        final tCtx = trimmedCanvas.context2D;
        final subData = ctx.getImageData(cropX, cropY, cropW, cropH);
        tCtx.putImageData(subData, 0, 0);
        final outUrl = trimmedCanvas.toDataUrl('image/jpeg', 0.92);
        return base64Decode(outUrl.split(',').last);
      }

      final outUrl = canvas.toDataUrl('image/jpeg', 0.92);
      return base64Decode(outUrl.split(',').last);
    } catch (_) {
      return srcBytes;
    }
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
    n = n.replaceAll(RegExp(r'[.,;:\-()""\’\‘\“\”\!' r"']"), '');
    return n.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Generates and downloads a standalone professional Yaprak Test / Deneme / Ödev PDF
  /// with a handsome top institutional header banner, 2-column vertical divider layout,
  /// whitened & auto-trimmed question images, and a bottom answer key table.
  Future<void> generateAndDownloadTestPdf({
    required String title,
    String subtitle = '',
    String examLabel = '',
    String testType = 'test',
    String classLevel = '',
    String branchName = '',
    String schoolName = 'eduKN Eğitim Kurumları',
    String headerLeftText = '',
    String headerRightText = '',
    String footerLeftText = '',
    String footerRightText = 'Başarılar Dileriz',
    bool showOutcomeOnQuestions = true,
    bool showStudentBox = true,
    bool showAnswerKey = true,
    String questionRightLabel = 'eduKN',
    String sortingAlgorithm = 'smart',
    required List<Map<String, dynamic>> questions,
  }) async {
    if (questions.isEmpty) return;

    late pw.Font font;
    late pw.Font fontBold;
    try {
      font = await PdfGoogleFonts.robotoRegular().timeout(const Duration(seconds: 5));
      fontBold = await PdfGoogleFonts.robotoBold().timeout(const Duration(seconds: 5));
    } catch (_) {
      font = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
    }

    // 1. Decode & whiten question images
    final List<Map<String, dynamic>> prepared = [];
    // Aynı soru (aynı görsel) teste iki kez girmesin: görsel içerik parmak izi ile tekilleştir
    final Set<String> seenContentKeys = {};
    for (final raw in questions) {
      Uint8List? bytes = raw['__whitenedImageBytes'] as Uint8List?;
      if (bytes == null) {
        try {
          if (raw['base64Image'] != null) {
            final decoded = base64Decode(raw['base64Image'] as String);
            bytes = await _whitenBytesForPdf(decoded);
            raw['__whitenedImageBytes'] = bytes;
          } else if (raw['imageUrl'] != null || raw['driveFileId'] != null) {
            final fetched = await DriveImageHelper.fetchImageBytes(
              raw['imageUrl']?.toString(),
              driveFileId: raw['driveFileId']?.toString(),
              perTryTimeout: const Duration(seconds: 5),
            );
            if (fetched != null) {
              bytes = await _whitenBytesForPdf(fetched);
              raw['__whitenedImageBytes'] = bytes;
            }
          }
        } catch (_) {}
      }
      if (bytes == null || bytes.isEmpty) continue;

      // Aynı Drive dosyası / aynı görsel içeriği → tekrar ekleme
      final String driveId = (raw['driveFileId'] ?? '').toString().trim();
      final String contentKey = 'b:${_bytesFingerprint(bytes)}';
      if (seenContentKeys.contains(contentKey) ||
          (driveId.isNotEmpty && seenContentKeys.contains('d:$driveId'))) {
        continue;
      }
      seenContentKeys.add(contentKey);
      if (driveId.isNotEmpty) seenContentKeys.add('d:$driveId');

      Uint8List? passageBytes = raw['__whitenedPassageBytes'] as Uint8List?;
      if (passageBytes == null && raw['passageBase64'] != null) {
        try {
          final rawPassage = base64Decode(raw['passageBase64'] as String);
          passageBytes = await _whitenBytesForPdf(rawPassage);
          raw['__whitenedPassageBytes'] = passageBytes;
        } catch (_) {}
      }

      // Sütun kararı (1 sütun / 2 sütun):
      // - Soru havuzunda genişlik zaten belirlenmişse (tablodan aktarılan sorularda görselin gerçek
      //   piksel genişliğine göre otomatik, ya da elle) ona güvenilir. Kısa ama 1 sütunluk sorular
      //   (en/boy oranı düşük) artık yanlışlıkla 2 sütuna yayılmaz.
      // - Bilgi yoksa (eski kayıtlar) en/boy oranına bakılır: genişlik > 2.15 × yükseklik ise 2 sütun.
      final bool hasWideDecision = raw['autoWideChecked'] == true ||
          raw['isWideManual'] == true ||
          raw['imageWidth'] != null;
      final bool isSheetQuestion =
          (raw['sourceType'] ?? '').toString() == 'google_sheets';
      final double ar = _getImageAspectRatio(bytes);
      final bool autoWide;
      if (hasWideDecision) {
        autoWide = raw['isWide'] == true;
      } else if (isSheetQuestion) {
        // Tablo görselleri sabit ölçekli: 1 sütun ≈ 600 px, 2 sütun ≈ 1100+ px (kenar kırpma genişliği büyütmez)
        final int pxW = _getImagePixelWidth(bytes);
        autoWide = raw['isWide'] == true ||
            (pxW > 0 ? pxW >= DriveImageHelper.kWidePixelThreshold : ar < 0.30);
      } else {
        autoWide = (raw['isWide'] == true) || (ar < 0.46);
      }

      prepared.add({
        ...raw,
        'imageBytes': bytes,
        'passageBytes': passageBytes,
        'isWide': autoWide,
        'correctAnswer': raw['correctAnswer'] ?? '?',
        'isYaprakTest': true,
        'showOutcome': showOutcomeOnQuestions,
        'questionRightLabel': questionRightLabel,
      });
    }

    if (prepared.isEmpty) return;

    // 2. Apply sorting algorithm ('smart' pairs 1-column questions cleanly and groups wide questions)
    final bool isSmart = sortingAlgorithm == 'smart';
    List<Map<String, dynamic>> ordered = List<Map<String, dynamic>>.from(prepared);
    if (isSmart) {
      final narrow = ordered
          .where((q) => q['isWide'] != true && q['passageBytes'] == null)
          .toList();
      final passages = ordered
          .where((q) => q['passageBytes'] != null)
          .toList();
      final wideList = ordered
          .where((q) => q['isWide'] == true && q['passageBytes'] == null)
          .toList();
      // Sort wide questions by height ascending so half-page wide questions pair together on the same page
      wideList.sort((a, b) =>
          _estimateWideQuestionHeight(a).compareTo(_estimateWideQuestionHeight(b)));
      ordered = [...narrow, ...wideList, ...passages];
    }

    for (int i = 0; i < ordered.length; i++) {
      ordered[i]['sequenceNo'] = i + 1;
    }

    final String effectiveBranch = branchName.isNotEmpty
        ? branchName
        : ((ordered.first['subject'] ?? 'Karma Test').toString());
    final String effectiveClass = classLevel.isNotEmpty
        ? classLevel
        : ((ordered.first['classLevel'] ?? '').toString());
    final String badgeText = examLabel.trim().isNotEmpty
        ? examLabel.trim().toUpperCase()
        : (testType == 'deneme'
            ? 'DENEME SINAVI'
            : testType == 'odev'
                ? 'ÖDEV FÖYÜ'
                : 'YAPRAK TEST');
    final String topBarLeft = headerLeftText.trim().isNotEmpty
        ? headerLeftText.trim()
        : schoolName;
    final String topBarRight = headerRightText.trim().isNotEmpty
        ? headerRightText.trim()
        : '${effectiveClass.isNotEmpty ? '${effectiveClass.toUpperCase()}  •  ' : ''}${effectiveBranch.toUpperCase()}  •  ${ordered.length} SORU';
    final String bottomLeft = footerLeftText.trim().isNotEmpty
        ? footerLeftText.trim()
        : '$topBarLeft  •  eduKN Akıllı Soru Havuzu';
    final String bottomRight = footerRightText.trim();

    final List<Map<String, dynamic>> visualOrdered = [];
    // Gerçek A4 soru alanı: 842 - üst/alt kenar (20+22) = 800 pt.
    // 1. sayfa: üst başlık bandının gerçek yüksekliği (öğrenci kutusu + 2 satır başlık + alt açıklama)
    // düşülür ki 1. sayfadaki Inseparable blok asla 2. sayfaya taşmasın ve 1. sayfa boş kalmasın.
    final double bannerH = (showStudentBox ? 104.0 : 92.0) +
        (subtitle.trim().isNotEmpty ? 14.0 : 0.0);
    const double footerH = 28.0;
    const double runningHeaderH = 38.0;
    const double safety = 14.0;
    final double firstPageAvail = 800.0 - footerH - bannerH - 8.0 - safety;
    const double otherPageAvail = 800.0 - footerH - runningHeaderH - safety;
    // 20 soruluk tek satırlı kompakt cevap anahtarı yüksekliği (~38 pt + her ek 20'lik satır için 15 pt)
    final int answerRows = ((ordered.length - 1) ~/ 20) + 1;
    final double answerKeyStripH = 26.0 + (answerRows * 15.0);
    final double answerKeyReserveH = showAnswerKey ? (answerKeyStripH + 8.0) : 0.0;
    double finalRemPageH = 0.0;
    final List<pw.Widget> layoutWidgets = _buildProfessionalTestLayout(
      ordered,
      fontBold,
      font,
      firstPageAvailH: firstPageAvail,
      fullPageAvailH: otherPageAvail,
      lastPageBottomReserveH: answerKeyReserveH,
      smartOrder: isSmart,
      outVisualOrder: visualOrdered,
      onFinalRemPageH: (rem) => finalRemPageH = rem,
    );
    final List<Map<String, dynamic>> finalAnswerOrder =
        visualOrdered.isNotEmpty ? visualOrdered : ordered;

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 22),
        header: (ctx) {
          if (ctx.pageNumber == 1) {
            return pw.SizedBox.shrink();
          }
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const pw.BoxDecoration(
              color: PdfColors.indigo50,
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.indigo900, width: 1.5),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '$topBarLeft  •  ${effectiveClass.isNotEmpty ? '$effectiveClass ' : ''}${effectiveBranch.toUpperCase()}',
                  style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.indigo900),
                ),
                pw.Text(
                  title.toUpperCase(),
                  style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.indigo700),
                ),
                pw.Text(
                  badgeText,
                  style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700),
                ),
              ],
            ),
          );
        },
        footer: (ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 6),
          padding: const pw.EdgeInsets.only(top: 5),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.indigo100, width: 0.8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                bottomLeft,
                style: pw.TextStyle(font: font, fontSize: 7.5, color: PdfColors.grey600),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.indigo900,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Text(
                  'Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}',
                  style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: PdfColors.white),
                ),
              ),
              pw.Text(
                bottomRight,
                style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: PdfColors.indigo700),
              ),
            ],
          ),
        ),
        build: (ctx) => [
          _buildYaprakTestTopBanner(
            title: title,
            subtitle: subtitle,
            badgeText: badgeText,
            classLevel: effectiveClass,
            branchName: effectiveBranch,
            topBarLeft: topBarLeft,
            topBarRight: topBarRight,
            showStudentBox: showStudentBox,
            questionCount: finalAnswerOrder.length,
            bold: fontBold,
            reg: font,
          ),
          pw.SizedBox(height: 8),
          ...layoutWidgets,
          if (showAnswerKey) ...[
            if (finalRemPageH >= answerKeyReserveH)
              pw.SizedBox(
                height: (finalRemPageH - answerKeyStripH - 4.0).clamp(6.0, otherPageAvail),
              )
            else ...[
              pw.NewPage(),
              pw.SizedBox(
                height: (otherPageAvail - answerKeyStripH - 4.0).clamp(6.0, otherPageAvail),
              ),
            ],
            _buildYaprakAnswerKeyStrip(finalAnswerOrder, fontBold, font),
          ],
        ],
      ),
    );

    final bytes = await pdf.save();
    final safeName = title.trim().isEmpty
        ? 'Yaprak_Test'
        : title.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filename = '$safeName.pdf';

    if (kIsWeb) {
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      await Printing.sharePdf(bytes: bytes, filename: filename);
    }
  }

  /// Handsome top institutional Yaprak Test / Deneme header banner on Page 1.
  pw.Widget _buildYaprakTestTopBanner({
    required String title,
    required String subtitle,
    required String badgeText,
    required String classLevel,
    required String branchName,
    required String topBarLeft,
    required String topBarRight,
    required bool showStudentBox,
    required int questionCount,
    required pw.Font bold,
    required pw.Font reg,
  }) {
    // Başlık içinde "YAPRAK TESTİ", "YAPRAK TEST", "DENEME SINAVI", "TARAMA TESTİ", "ÖDEV FÖYÜ"
    // gibi ifadeler varsa "YAPRAK" üstte "TESTİ" altta bölünmesin:
    // Üst satırda ders/sınıf adı (örn. "7. SINIF MATEMATİK"), hemen altında biraz daha küçük puntoyla
    // "YAPRAK TESTİ" tek satır olarak yer alsın.
    final String rawUpper = title.trim().toUpperCase();
    String mainHeading = rawUpper;
    String? subHeading;
    const List<String> knownSuffixes = [
      'KONU TARAMA TESTİ',
      'KONU TARAMA TESTI',
      'TARAMA TESTİ',
      'TARAMA TESTI',
      'YAPRAK TESTİ',
      'YAPRAK TESTI',
      'YAPRAK TEST',
      'DENEME SINAVI',
      'ÖDEV FÖYÜ',
      'ODEV FOYU',
      'ÇALIŞMA FÖYÜ',
      'CALISMA FOYU',
    ];
    for (final sfx in knownSuffixes) {
      if (rawUpper.endsWith(sfx) && rawUpper.length > sfx.length) {
        final String prefix = rawUpper
            .substring(0, rawUpper.length - sfx.length)
            .replaceAll(RegExp(r'[-•–\s]+$'), '')
            .trim();
        if (prefix.isNotEmpty) {
          mainHeading = prefix;
          subHeading = sfx;
          break;
        }
      }
    }

    return pw.Container(
      width: _fullPageWidth,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: PdfColors.indigo900, width: 1.8),
      ),
      child: pw.Column(
        children: [
          // Top institutional dark-indigo accent bar
          pw.Container(
            width: _fullPageWidth,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: const pw.BoxDecoration(
              color: PdfColors.indigo900,
              borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(6)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    pw.Container(
                      width: 8,
                      height: 8,
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.cyan400,
                        shape: pw.BoxShape.circle,
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    pw.Text(
                      topBarLeft.toUpperCase(),
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 8.5,
                        color: PdfColors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.cyan400,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    badgeText,
                    style: pw.TextStyle(
                      font: bold,
                      fontSize: 8,
                      color: PdfColors.indigo900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                pw.Text(
                  topBarRight.toUpperCase(),
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 8.5,
                    color: PdfColors.indigo100,
                  ),
                ),
              ],
            ),
          ),

          // Main 3-Part Banner Content: Left (Logo + Branch) | Center (Test Title) | Right (Student Box)
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Left: eduKN Vector Brand Logo + Class/Branch Badge
                pw.Container(
                  width: 118,
                  padding: const pw.EdgeInsets.only(right: 10),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(right: pw.BorderSide(color: PdfColors.indigo100, width: 1)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        children: [
                          pw.Transform(
                            transform: vm.Matrix4.skewX(-0.2679),
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Container(width: 12, height: 2.5, color: PdfColors.blue600),
                                pw.SizedBox(height: 1.8),
                                pw.Container(width: 17, height: 2.5, color: PdfColors.blue600),
                                pw.SizedBox(height: 1.8),
                                pw.Container(width: 9, height: 2.5, color: PdfColors.cyan400),
                              ],
                            ),
                          ),
                          pw.SizedBox(width: 6),
                          pw.Text(
                            'eduKN',
                            style: pw.TextStyle(
                              font: bold,
                              fontSize: 20,
                              fontStyle: pw.FontStyle.italic,
                              color: PdfColors.indigo900,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.indigo50,
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                        child: pw.Text(
                          branchName.toUpperCase(),
                          style: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.indigo900),
                        ),
                      ),
                    ],
                  ),
                ),

                // Center: Main Test Title (Course/Class on top, "YAPRAK TESTİ" right underneath in smaller font) & Description
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          mainHeading,
                          textAlign: pw.TextAlign.center,
                          maxLines: 1,
                          style: pw.TextStyle(
                            font: bold,
                            fontSize: subHeading != null ? 12.5 : 12.0,
                            color: PdfColors.indigo900,
                          ),
                        ),
                        if (subHeading != null) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            subHeading,
                            textAlign: pw.TextAlign.center,
                            maxLines: 1,
                            style: pw.TextStyle(
                              font: bold,
                              fontSize: 10.0,
                              letterSpacing: 0.8,
                              color: PdfColors.indigo700,
                            ),
                          ),
                        ],
                        if (subtitle.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            subtitle.trim(),
                            textAlign: pw.TextAlign.center,
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                            style: pw.TextStyle(
                              font: reg,
                              fontSize: 8.2,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Right: Student Info & Score Box (Optional)
                if (showStudentBox)
                  pw.Container(
                    width: 170,
                    padding: const pw.EdgeInsets.all(7),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey50,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                      border: pw.Border.all(color: PdfColors.indigo200, width: 0.8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'ADI SOYADI : ............................................',
                          style: pw.TextStyle(font: bold, fontSize: 7.2, color: PdfColors.indigo900),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'SINIF / NO   : ......................   PUAN : ..........',
                          style: pw.TextStyle(font: bold, fontSize: 7.2, color: PdfColors.indigo900),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('D : .........', style: pw.TextStyle(font: bold, fontSize: 7.2, color: PdfColors.green800)),
                            pw.Text('Y : .........', style: pw.TextStyle(font: bold, fontSize: 7.2, color: PdfColors.red800)),
                            pw.Text('NET : .........', style: pw.TextStyle(font: bold, fontSize: 7.2, color: PdfColors.indigo900)),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildYaprakAnswerKeyStrip(
    List<Map<String, dynamic>> questions,
    pw.Font bold,
    pw.Font reg,
  ) {
    // Bir satırda 20 sorunun cevabı olacak şekilde kompakt dizilim
    const int perRow = 20;
    final List<List<Map<String, dynamic>>> rows = [];
    for (int idx = 0; idx < questions.length; idx += perRow) {
      final int end = (idx + perRow) < questions.length ? (idx + perRow) : questions.length;
      rows.add(questions.sublist(idx, end));
    }

    return pw.Inseparable(
      child: pw.Container(
        width: _fullPageWidth,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: pw.BoxDecoration(
          color: PdfColors.indigo50,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
          border: pw.Border.all(color: PdfColors.indigo900, width: 1.0),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.indigo900,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                  ),
                  child: pw.Text(
                    'CEVAP ANAHTARI',
                    style: pw.TextStyle(font: bold, fontSize: 7.0, color: PdfColors.white),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(child: pw.Divider(color: PdfColors.indigo200, thickness: 0.6)),
              ],
            ),
            pw.SizedBox(height: 4),
            for (int r = 0; r < rows.length; r++) ...[
              if (r > 0) pw.SizedBox(height: 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.start,
                children: [
                  for (int c = 0; c < rows[r].length; c++) ...[
                    if (c > 0) pw.SizedBox(width: 1.4),
                    pw.Container(
                      width: 25.3,
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      alignment: pw.Alignment.center,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                        border: pw.Border.all(color: PdfColors.indigo200, width: 0.5),
                      ),
                      child: pw.Text(
                        '${rows[r][c]['sequenceNo']}-${rows[r][c]['correctAnswer'] ?? '?'}',
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 6.8,
                          color: PdfColors.indigo900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
