import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ParentReportPdfHelper {
  static Future<Uint8List> generateReport({
    required String studentName,
    required String studentClass,
    required String studentNo,
    required String letterContent,
    required List<Map<String, dynamic>> selectedExams,
    required List<Map<String, dynamic>> agmAssignments,
    required List<Map<String, dynamic>> campAssignments,
    required List<Map<String, dynamic>> studyPrograms,
    required bool includeExams,
    required bool includeAgm,
    required bool includeCamp,
    required bool includeStudyPrograms,
    required Map<String, String> lessonAbbreviations,
    required Map<String, List<String>> examTypeSubjectOrders,
    required String classTeacherName,
    required String principalName,
    bool agmShowBranch = true,
    bool agmShowTeacher = true,
    bool agmShowKazanim = true,
    bool agmShowDurum = true,
    bool campShowBranch = true,
    bool campShowTeacher = true,
    bool campShowKazanim = true,
    bool campShowDurum = true,
    bool includeKazanimList = true,
    bool includeTopicAnalysis = true,
    Map<String, int> topicAnalysisThresholds = const {},
    List<dynamic> studentTopicAnalysis = const [],
    bool topicAnalysisShowPriority = true,
    bool topicAnalysisShowReinforcement = true,
    bool includeLessonPlans = true,
    List<Map<String, dynamic>> lessonPlans = const [],
    bool includeFooter = true,
    bool footerShowTeacher = true,
    bool footerShowPageNumber = true,
    bool footerShowPrincipal = true,
    String footerSlogan = 'Eğitim ve Gelişimde Başarılar Dileriz.',
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();
    final fontItalic = await PdfGoogleFonts.openSansItalic();

    await _addStudentReport(
      pdf: pdf,
      font: font,
      fontBold: fontBold,
      fontItalic: fontItalic,
      studentName: studentName,
      studentClass: studentClass,
      studentNo: studentNo,
      letterContent: letterContent,
      selectedExams: selectedExams,
      agmAssignments: agmAssignments,
      campAssignments: campAssignments,
      studyPrograms: studyPrograms,
      includeExams: includeExams,
      includeAgm: includeAgm,
      includeCamp: includeCamp,
      includeStudyPrograms: includeStudyPrograms,
      lessonAbbreviations: lessonAbbreviations,
      examTypeSubjectOrders: examTypeSubjectOrders,
      classTeacherName: classTeacherName,
      principalName: principalName,
      agmShowBranch: agmShowBranch,
      agmShowTeacher: agmShowTeacher,
      agmShowKazanim: agmShowKazanim,
      agmShowDurum: agmShowDurum,
      campShowBranch: campShowBranch,
      campShowTeacher: campShowTeacher,
      campShowKazanim: campShowKazanim,
      campShowDurum: campShowDurum,
      includeKazanimList: includeKazanimList,
      includeTopicAnalysis: includeTopicAnalysis,
      topicAnalysisThresholds: topicAnalysisThresholds,
      studentTopicAnalysis: studentTopicAnalysis,
      topicAnalysisShowPriority: topicAnalysisShowPriority,
      topicAnalysisShowReinforcement: topicAnalysisShowReinforcement,
      includeLessonPlans: includeLessonPlans,
      lessonPlans: lessonPlans,
      includeFooter: includeFooter,
      footerShowTeacher: footerShowTeacher,
      footerShowPageNumber: footerShowPageNumber,
      footerShowPrincipal: footerShowPrincipal,
      footerSlogan: footerSlogan,
    );

    return pdf.save();
  }

  static Future<Uint8List> generateCombinedReport({
    required List<Map<String, dynamic>> studentsData,
    required String letterContent,
    required bool includeExams,
    required bool includeAgm,
    required bool includeCamp,
    required bool includeStudyPrograms,
    required Map<String, String> lessonAbbreviations,
    required Map<String, List<String>> examTypeSubjectOrders,
    bool agmShowBranch = true,
    bool agmShowTeacher = true,
    bool agmShowKazanim = true,
    bool agmShowDurum = true,
    bool campShowBranch = true,
    bool campShowTeacher = true,
    bool campShowKazanim = true,
    bool campShowDurum = true,
    bool includeKazanimList = true,
    bool includeTopicAnalysis = true,
    bool topicAnalysisShowPriority = true,
    bool topicAnalysisShowReinforcement = true,
    bool includeLessonPlans = true,
    bool includeFooter = true,
    bool footerShowTeacher = true,
    bool footerShowPageNumber = true,
    bool footerShowPrincipal = true,
    String footerSlogan = 'Eğitim ve Gelişimde Başarılar Dileriz.',
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();
    final fontItalic = await PdfGoogleFonts.openSansItalic();

    for (var sData in studentsData) {
      await _addStudentReport(
        pdf: pdf,
        font: font,
        fontBold: fontBold,
        fontItalic: fontItalic,
        studentName: sData['studentName'] ?? '',
        studentClass: sData['studentClass'] ?? '',
        studentNo: sData['studentNo'] ?? '',
        letterContent: letterContent,
        selectedExams: List<Map<String, dynamic>>.from(sData['selectedExams'] ?? []),
        agmAssignments: List<Map<String, dynamic>>.from(sData['agmAssignments'] ?? []),
        campAssignments: List<Map<String, dynamic>>.from(sData['campAssignments'] ?? []),
        studyPrograms: List<Map<String, dynamic>>.from(sData['studyPrograms'] ?? []),
        includeExams: includeExams,
        includeAgm: includeAgm,
        includeCamp: includeCamp,
        includeStudyPrograms: includeStudyPrograms,
        lessonAbbreviations: lessonAbbreviations,
        examTypeSubjectOrders: examTypeSubjectOrders,
        classTeacherName: sData['classTeacherName'] ?? 'Belirtilmedi',
        principalName: sData['principalName'] ?? 'Belirtilmedi',
        agmShowBranch: agmShowBranch,
        agmShowTeacher: agmShowTeacher,
        agmShowKazanim: agmShowKazanim,
        agmShowDurum: agmShowDurum,
        campShowBranch: campShowBranch,
        campShowTeacher: campShowTeacher,
        campShowKazanim: campShowKazanim,
        campShowDurum: campShowDurum,
        includeKazanimList: includeKazanimList,
        includeTopicAnalysis: includeTopicAnalysis,
        topicAnalysisThresholds: Map<String, int>.from(sData['topicAnalysisThresholds'] ?? {}),
        studentTopicAnalysis: List<dynamic>.from(sData['studentTopicAnalysis'] ?? []),
        topicAnalysisShowPriority: topicAnalysisShowPriority,
        topicAnalysisShowReinforcement: topicAnalysisShowReinforcement,
        includeLessonPlans: includeLessonPlans,
        lessonPlans: List<Map<String, dynamic>>.from(sData['lessonPlans'] ?? []),
        includeFooter: includeFooter,
        footerShowTeacher: footerShowTeacher,
        footerShowPageNumber: footerShowPageNumber,
        footerShowPrincipal: footerShowPrincipal,
        footerSlogan: footerSlogan,
      );
    }

    return pdf.save();
  }

  static Future<void> _addStudentReport({
    required pw.Document pdf,
    required pw.Font font,
    required pw.Font fontBold,
    required pw.Font fontItalic,
    required String studentName,
    required String studentClass,
    required String studentNo,
    required String letterContent,
    required List<Map<String, dynamic>> selectedExams,
    required List<Map<String, dynamic>> agmAssignments,
    required List<Map<String, dynamic>> campAssignments,
    required List<Map<String, dynamic>> studyPrograms,
    required bool includeExams,
    required bool includeAgm,
    required bool includeCamp,
    required bool includeStudyPrograms,
    required Map<String, String> lessonAbbreviations,
    required Map<String, List<String>> examTypeSubjectOrders,
    required String classTeacherName,
    required String principalName,
    // AGM sütun görünürlükleri
    bool agmShowBranch = true,
    bool agmShowTeacher = true,
    bool agmShowKazanim = true,
    bool agmShowDurum = true,
    // Kamp sütun görünürlükleri
    bool campShowBranch = true,
    bool campShowTeacher = true,
    bool campShowKazanim = true,
    bool campShowDurum = true,
    // Kazanım listesi bölümü
    bool includeKazanimList = true,
    // 6. alan Konu Analizi
    bool includeTopicAnalysis = true,
    Map<String, int> topicAnalysisThresholds = const {},
    List<dynamic> studentTopicAnalysis = const [],
    bool topicAnalysisShowPriority = true,
    bool topicAnalysisShowReinforcement = true,
    // 7. alan Haftalık Ders Planları
    bool includeLessonPlans = true,
    List<Map<String, dynamic>> lessonPlans = const [],
    // 8. alan Alt Bilgi (Footer)
    bool includeFooter = true,
    bool footerShowTeacher = true,
    bool footerShowPageNumber = true,
    bool footerShowPrincipal = true,
    String footerSlogan = 'Eğitim ve Gelişimde Başarılar Dileriz.',
  }) async {

    // 1. Collect all unique subjects across selected exams
    final Set<String> allSubjectsSet = {};
    for (var exam in selectedExams) {
      final netsRaw = exam['subjectNets'];
      if (netsRaw != null && netsRaw is Map) {
        final nets = Map<String, dynamic>.from(netsRaw);
        allSubjectsSet.addAll(nets.keys);
      }
    }
    final List<String> subjectsList = allSubjectsSet.toList();
    
    // Try to get ordered subjects list from examTypeSubjectOrders based on examTypeId
    List<String> orderedSubjects = [];
    if (selectedExams.isNotEmpty) {
      final firstExamTypeId = selectedExams.first['examTypeId']?.toString() ?? '';
      if (firstExamTypeId.isNotEmpty && examTypeSubjectOrders.containsKey(firstExamTypeId)) {
        orderedSubjects = examTypeSubjectOrders[firstExamTypeId] ?? [];
      }
    }

    subjectsList.sort((a, b) {
      final indexA = orderedSubjects.indexWhere((s) => s.toLowerCase().trim() == a.toLowerCase().trim());
      final indexB = orderedSubjects.indexWhere((s) => s.toLowerCase().trim() == b.toLowerCase().trim());
      
      if (indexA != -1 && indexB != -1) {
        return indexA.compareTo(indexB);
      }
      if (indexA != -1) return -1;
      if (indexB != -1) return 1;
      
      // Fallback standard Turkish curriculum order
      final List<String> priorityOrder = [
        'türkçe', 'turkce',
        'matematik', 'mat',
        'fen', 'fizik', 'kimya', 'biyoloji',
        'sosyal', 'inkılap', 'tarih', 'coğrafya',
        'din', 'ahlak',
        'ingilizce', 'ing', 'yabancı'
      ];
      final priorityIndexA = priorityOrder.indexWhere((p) => a.toLowerCase().contains(p));
      final priorityIndexB = priorityOrder.indexWhere((p) => b.toLowerCase().contains(p));
      if (priorityIndexA != -1 && priorityIndexB != -1) {
        return priorityIndexA.compareTo(priorityIndexB);
      }
      if (priorityIndexA != -1) return -1;
      if (priorityIndexB != -1) return 1;
      return a.compareTo(b);
    });

    // Abbreviation helper using custom mappings from lessons collection
    String abbreviateSubject(String name) {
      final clean = name.trim().toLowerCase();
      if (lessonAbbreviations.containsKey(clean)) {
        return lessonAbbreviations[clean]!;
      }
      for (var entry in lessonAbbreviations.entries) {
        if (clean.contains(entry.key) || entry.key.contains(clean)) {
          return entry.value;
        }
      }
      
      // Fallback manual abbreviations
      if (clean.contains('türkçe') || clean == 'turkce') return 'TR';
      if (clean.contains('matematik') || clean == 'mat') return 'MAT';
      if (clean.contains('fen') || clean.contains('fizik') || clean.contains('kimya') || clean.contains('biyoloji')) return 'FEN';
      if (clean.contains('sosyal') || clean.contains('tarih') || clean.contains('coğrafya') || clean.contains('inkılap') || clean.contains('felsefe')) return 'SOS';
      if (clean.contains('din') || clean.contains('ahlak')) return 'DİN';
      if (clean.contains('ingilizce') || clean.contains('ing') || clean.contains('yabancı') || clean.contains('dil')) return 'İNG';
      if (name.length > 3) {
        return name.substring(0, 3).toUpperCase();
      }
      return name.toUpperCase();
    }

    // Dynamic column widths for pw.Table
    final Map<int, pw.TableColumnWidth> examColumnWidths = {};
    examColumnWidths[0] = const pw.FlexColumnWidth(3.0); // Sınav Adı
    int colIdx = 1;
    for (var _ in subjectsList) {
      examColumnWidths[colIdx] = const pw.FlexColumnWidth(0.9);
      colIdx++;
    }
    examColumnWidths[colIdx] = const pw.FlexColumnWidth(1.2); // Toplam Net
    examColumnWidths[colIdx + 1] = const pw.FlexColumnWidth(1.2); // Puan



    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 40),
        theme: pw.ThemeData.withFont(
          base: font,
          bold: fontBold,
          italic: fontItalic,
        ),
        footer: (context) {
          return _buildSignatureFooter(
            classTeacherName: classTeacherName,
            principalName: principalName,
            pageNumber: context.pageNumber,
            pagesCount: context.pagesCount,
            includeFooter: includeFooter,
            footerShowTeacher: footerShowTeacher,
            footerShowPageNumber: footerShowPageNumber,
            footerShowPrincipal: footerShowPrincipal,
            footerSlogan: footerSlogan,
          );
        },
        build: (context) {
          return [
            // ─── HEADER ───
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'eduKN',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#1A237E'), // Deep Indigo
                      ),
                    ),
                    pw.Text(
                      'Bireysel Gelişim & Veli Bilgilendirme Raporu',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColor.fromHex('#455A64'), // Slate Blue
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      DateFormat('dd.MM.yyyy').format(DateTime.now()),
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                    pw.Text(
                      'Kişiye Özel Rapor',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#E65100'), // Dark Orange
                      ),
                    ),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 12),
            pw.Divider(thickness: 1.5, color: PdfColor.fromHex('#303F9F')),
            pw.SizedBox(height: 10),

            // ─── STUDENT INFO CARD ───
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F5F7FA'),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0')),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Öğrenci Adı Soyadı:',
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                        ),
                        pw.Text(
                          studentName,
                          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                        ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Sınıf / Şube:',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        studentClass.isEmpty ? 'Belirtilmedi' : studentClass,
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                  pw.SizedBox(width: 30),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Okul Numarası:',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        studentNo.isEmpty ? '-' : studentNo,
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 16),

            // ─── VELİ BİLGİLENDİRME MEKTUBU ───
            if (letterContent.trim().isNotEmpty) ...[
              pw.Text(
                'Sayın Velimiz,',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#1A237E'),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  border: pw.Border.all(color: PdfColors.indigo100, width: 1),
                ),
                child: pw.Text(
                  letterContent,
                  style: const pw.TextStyle(fontSize: 10, height: 1.4, color: PdfColors.grey900),
                ),
              ),
              pw.SizedBox(height: 20),
            ],



            // ─── DENEME SINAVI SONUÇLARI ───
            if (includeExams)
              if (selectedExams.isEmpty)
                ...[
                  _buildSectionTitle('Deneme Sınavları Performansı'),
                  pw.SizedBox(height: 6),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 24),
                    child: pw.Text('Sınav verisi bulunamadı veya öğrenci sınavlara katılmamıştır.', style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
                  ),
                ]
              else ...[
                _buildSectionTitle('Deneme Sınavları Performansı'),
              pw.SizedBox(height: 6),
              // Header Row
              _buildSplittableRow(
                decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E8EAF6')),
                bottomBorderWidth: 1.0,
                bottomBorderColor: PdfColors.grey400,
                flexes: [30, ...subjectsList.map((_) => 9), 12, 12],
                children: [
                  _buildTableHeaderCell('Sınav Adı', alignLeft: true),
                  ...subjectsList.map((sub) => _buildTableHeaderCell(abbreviateSubject(sub))),
                  _buildTableHeaderCell('Net'),
                  _buildTableHeaderCell('Puan'),
                ],
              ),
              // Data Rows
              ...selectedExams.map((exam) {
                final bool didNotParticipate = exam['didNotParticipate'] == true;
                if (didNotParticipate) {
                  final remainingFlex = (subjectsList.length * 9) + 24;
                  return _buildSplittableRow(
                    bottomBorderWidth: 0.5,
                    bottomBorderColor: PdfColors.grey300,
                    flexes: [30, remainingFlex],
                    children: [
                      _buildTableCell(
                        exam['examName'] ?? 'Deneme Sınavı',
                        alignLeft: true,
                        isBold: true,
                        color: PdfColors.grey700,
                      ),
                      _buildTableCell(
                        'Öğrencimiz bu deneme sınavına katılmamıştır.',
                        alignLeft: false,
                        isBold: true,
                        color: PdfColors.red700,
                      ),
                    ],
                  );
                }

                final score = num.tryParse(exam['totalScore']?.toString() ?? '0')?.toStringAsFixed(1) ?? '0.0';
                final subjectNetsRaw = exam['subjectNets'];
                final subjectNets = (subjectNetsRaw is Map) ? Map<String, dynamic>.from(subjectNetsRaw) : <String, dynamic>{};
                
                double totalNet = num.tryParse(exam['totalNet']?.toString() ?? '0')?.toDouble() ?? 0.0;
                if (totalNet == 0.0 && subjectNets.isNotEmpty) {
                  totalNet = subjectNets.values.fold(0.0, (sum, item) => sum + (num.tryParse(item.toString())?.toDouble() ?? 0.0));
                }
                final net = totalNet.toStringAsFixed(2);

                return _buildSplittableRow(
                  bottomBorderWidth: 0.5,
                  bottomBorderColor: PdfColors.grey300,
                  flexes: [30, ...subjectsList.map((_) => 9), 12, 12],
                  children: [
                    _buildTableCell(exam['examName'] ?? 'Deneme Sınavı', alignLeft: true),
                    ...subjectsList.map((sub) {
                      final val = subjectNets[sub];
                      final valStr = val != null ? num.parse(val.toString()).toStringAsFixed(2) : '-';
                      return _buildTableCell(valStr);
                    }),
                    _buildTableCell(net, isBold: true, color: PdfColor.fromHex('#2E7D32')),
                    _buildTableCell(score),
                  ],
                );
              }),
              pw.SizedBox(height: 24),
            ],



            // ─── AKADEMİK GÜÇLENDİRME (AGM) PROGRAMI ───
            // ─── AKADEMİK GÜÇLENDİRME (AGM) PROGRAMI ───
            if (includeAgm)
              if (agmAssignments.isEmpty)
                ...[
                  _buildSectionTitle('Akademik Güçlendirme (AGM) Katılımları'),
                  pw.SizedBox(height: 6),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 24),
                    child: pw.Text('Bu programa ait atama veya katılım verisi bulunmamaktadır.', style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
                  ),
                ]
              else ...[
                _buildSectionTitle('Akademik Güçlendirme (AGM) Katılımları'),
              pw.SizedBox(height: 6),
              pw.Text(
                'Öğrencimizin eksik olduğu kazanımlara göre yerleştirildiği AGM grup ve etüt çalışmaları:',
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
              ),
              pw.SizedBox(height: 6),
              ...() {
                // Group assignments by cycleName
                final Map<String, List<Map<String, dynamic>>> agmGrouped = {};
                for (var asm in agmAssignments) {
                  final cName = asm['cycleName']?.toString() ?? 'AGM Dönemi';
                  agmGrouped.putIfAbsent(cName, () => []).add(asm);
                }

                final List<pw.Widget> agmWidgets = [];
                agmGrouped.forEach((cycleName, list) {
                  agmWidgets.add(
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
                      child: pw.Text(
                        'Program: $cycleName',
                        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                      ),
                    ),
                  );

                  agmWidgets.add(
                    _buildSplittableRow(
                      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#ECEFF1')),
                      bottomBorderWidth: 1.0,
                      bottomBorderColor: PdfColors.grey400,
                      flexes: () {
                        final List<int> flexes = [];
                        if (agmShowBranch)   flexes.add(20);
                        if (agmShowTeacher)  flexes.add(20);
                        if (agmShowKazanim) flexes.add(30);
                        if (agmShowDurum)   flexes.add(12);
                        if (flexes.isEmpty)  flexes.add(10);
                        return flexes;
                      }(),
                      children: [
                        if (agmShowBranch)   _buildTableHeaderCell('Branş', alignLeft: true),
                        if (agmShowTeacher)  _buildTableHeaderCell('Öğretmen', alignLeft: true),
                        if (agmShowKazanim) _buildTableHeaderCell('Ana Kazanım', alignLeft: true),
                        if (agmShowDurum)   _buildTableHeaderCell('Durum'),
                      ],
                    ),
                  );

                  for (var asm in list) {
                    final ders = _stripEmoji(asm['dersAdi']?.toString() ?? asm['ders']?.toString() ?? '-');
                    final ogretmen = _stripEmoji(asm['ogretmenAdi']?.toString() ?? asm['ogretmen']?.toString() ?? '-');
                    final anaKazanim = _stripEmoji(asm['anaKazanim']?.toString() ?? '-');
                    final attended = asm['attended'] == true;
                    agmWidgets.add(
                      _buildSplittableRow(
                        bottomBorderWidth: 0.5,
                        bottomBorderColor: PdfColors.grey300,
                        flexes: () {
                          final List<int> flexes = [];
                          if (agmShowBranch)   flexes.add(20);
                          if (agmShowTeacher)  flexes.add(20);
                          if (agmShowKazanim) flexes.add(30);
                          if (agmShowDurum)   flexes.add(12);
                          if (flexes.isEmpty)  flexes.add(10);
                          return flexes;
                        }(),
                        children: [
                          if (agmShowBranch)   _buildTableCell(ders, alignLeft: true, isBold: true),
                          if (agmShowTeacher)  _buildTableCell(ogretmen, alignLeft: true),
                          if (agmShowKazanim) _buildTableCell(anaKazanim, alignLeft: true),
                          if (agmShowDurum)   _buildTableCell(
                            attended ? 'Katıldı' : 'Katılmadı',
                            isBold: true,
                            color: attended ? PdfColor.fromHex('#2E7D32') : PdfColor.fromHex('#C62828'),
                          ),
                        ],
                      ),
                    );
                  }
                  agmWidgets.add(pw.SizedBox(height: 10));
                });
                return agmWidgets;
              }(),
              pw.SizedBox(height: 14),
            ],

            // ─── KAMP PROGRAMI ───
            if (includeCamp)
              if (campAssignments.isEmpty)
                ...[
                  _buildSectionTitle('Kamp Yoğunlaştırılmış Program Çalışmaları'),
                  pw.SizedBox(height: 6),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 24),
                    child: pw.Text('Bu programa ait atama veya katılım verisi bulunmamaktadır.', style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
                  ),
                ]
              else ...[
                _buildSectionTitle('Kamp Yoğunlaştırılmış Program Çalışmaları'),
              pw.SizedBox(height: 6),
              pw.Text(
                'Öğrencimizin katılım gösterdiği yoğunlaştırılmış kamp programı detayları:',
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
              ),
              pw.SizedBox(height: 6),
              ...() {
                // Group assignments by cycleName
                final Map<String, List<Map<String, dynamic>>> campGrouped = {};
                for (var asm in campAssignments) {
                  final cName = asm['cycleName']?.toString() ?? 'Kamp Dönemi';
                  campGrouped.putIfAbsent(cName, () => []).add(asm);
                }

                final List<pw.Widget> campWidgets = [];
                campGrouped.forEach((cycleName, list) {
                  campWidgets.add(
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
                      child: pw.Text(
                        'Program: $cycleName',
                        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900),
                      ),
                    ),
                  );

                  // Check if excluded
                  final isExcluded = list.any((asm) => asm['isExcluded'] == true);

                  if (isExcluded) {
                    campWidgets.add(
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromHex('#FFF3E0'),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                          border: pw.Border.all(color: PdfColors.orange300, width: 0.5),
                        ),
                        child: pw.Text(
                          'Programa katılmamıştır',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.orange900,
                          ),
                        ),
                      ),
                    );
                  } else {
                    campWidgets.add(
                      _buildSplittableRow(
                        decoration: pw.BoxDecoration(color: PdfColor.fromHex('#FFF3E0')),
                        bottomBorderWidth: 1.0,
                        bottomBorderColor: PdfColors.grey400,
                        flexes: () {
                          final List<int> flexes = [];
                          if (campShowBranch)   flexes.add(20);
                          if (campShowTeacher)  flexes.add(20);
                          if (campShowKazanim) flexes.add(30);
                          if (campShowDurum)   flexes.add(12);
                          if (flexes.isEmpty)  flexes.add(10);
                          return flexes;
                        }(),
                        children: [
                          if (campShowBranch)   _buildTableHeaderCell('Branş', alignLeft: true),
                          if (campShowTeacher)  _buildTableHeaderCell('Öğretmen', alignLeft: true),
                          if (campShowKazanim) _buildTableHeaderCell('Ana Kazanım', alignLeft: true),
                          if (campShowDurum)   _buildTableHeaderCell('Durum'),
                        ],
                      ),
                    );

                    for (var asm in list) {
                      final ders = _stripEmoji(asm['dersAdi']?.toString() ?? asm['ders']?.toString() ?? '-');
                      final ogretmen = _stripEmoji(asm['ogretmenAdi']?.toString() ?? asm['ogretmen']?.toString() ?? '-');
                      final anaKazanim = _stripEmoji(asm['anaKazanim']?.toString() ?? '-');
                      final attended = asm['attended'] == true;
                      campWidgets.add(
                        _buildSplittableRow(
                          bottomBorderWidth: 0.5,
                          bottomBorderColor: PdfColors.grey300,
                          flexes: () {
                            final List<int> flexes = [];
                            if (campShowBranch)   flexes.add(20);
                            if (campShowTeacher)  flexes.add(20);
                            if (campShowKazanim) flexes.add(30);
                            if (campShowDurum)   flexes.add(12);
                            if (flexes.isEmpty)  flexes.add(10);
                            return flexes;
                          }(),
                          children: [
                            if (campShowBranch)   _buildTableCell(ders, alignLeft: true, isBold: true),
                            if (campShowTeacher)  _buildTableCell(ogretmen, alignLeft: true),
                            if (campShowKazanim) _buildTableCell(anaKazanim, alignLeft: true),
                            if (campShowDurum)   _buildTableCell(
                              attended ? 'Katıldı' : 'Katılmadı',
                              isBold: true,
                              color: attended ? PdfColor.fromHex('#2E7D32') : PdfColor.fromHex('#C62828'),
                            ),
                          ],
                        ),
                      );
                    }
                  }
                  campWidgets.add(pw.SizedBox(height: 10));
                });
                return campWidgets;
              }(),
              pw.SizedBox(height: 14),
            ],

            // ─── BİREYSEL ÇALIŞMA VE GÜÇLENDİRME PROGRAMI ───
            if (includeStudyPrograms)
              if (studyPrograms.isEmpty)
                ...[
                  _buildSectionTitle('Kişisel Gelişim & Geliştirme Programı'),
                  pw.SizedBox(height: 6),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 24),
                    child: pw.Text('Bu başlığa ait etüt veya bireysel çalışma verisi bulunmamaktadır.', style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
                  ),
                ]
              else ...[
              ...studyPrograms.asMap().entries.map((entry) {
                final int index = entry.key;
                final prog = entry.value;
                final title = prog['title'] ?? prog['name'] ?? 'Bireysel Çalışma Programı';
                final desc = prog['description'] ?? '';

                // Build kazanim map: branch -> List<String>
                final Map<String, List<String>> kazanimByBranch = {};
                final subjectsRaw = prog['subjects'];
                if (subjectsRaw is List) {
                  for (final sub in subjectsRaw) {
                    if (sub is Map) {
                      final branch = _stripEmoji(sub['dersAdi']?.toString() ?? sub['ders']?.toString() ?? sub['branch']?.toString() ?? '');
                      final kazanimlarRaw = sub['kazanimlar'];
                      if (branch.isNotEmpty && kazanimlarRaw is List) {
                        kazanimByBranch[branch] = kazanimlarRaw.map((e) => _stripEmoji(e.toString())).where((e) => e.isNotEmpty).toList();
                      }
                    }
                  }
                }

                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (index == 0) ...[
                      _buildSectionTitle('Kişisel Gelişim & Geliştirme Programı'),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Öğrencimize özel tanımlanmış haftalık gelişim ve konu çalışma programı hedefleri:',
                        style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
                      ),
                      pw.SizedBox(height: 6),
                    ],
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          title,
                          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                        ),
                        if (prog['createdAtLabel'] != null)
                          pw.Text(
                            prog['createdAtLabel'],
                            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                          ),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        desc,
                        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic),
                      ),
                    ],
                    pw.SizedBox(height: 6),
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                      columnWidths: const {
                        0: pw.FractionColumnWidth(1 / 7),
                        1: pw.FractionColumnWidth(1 / 7),
                        2: pw.FractionColumnWidth(1 / 7),
                        3: pw.FractionColumnWidth(1 / 7),
                        4: pw.FractionColumnWidth(1 / 7),
                        5: pw.FractionColumnWidth(1 / 7),
                        6: pw.FractionColumnWidth(1 / 7),
                      },
                      children: [
                        // Headers
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E8EAF6')),
                          children: [
                            _buildWeeklyHeaderCell('Pazartesi'),
                            _buildWeeklyHeaderCell('Salı'),
                            _buildWeeklyHeaderCell('Çarşamba'),
                            _buildWeeklyHeaderCell('Perşembe'),
                            _buildWeeklyHeaderCell('Cuma'),
                            _buildWeeklyHeaderCell('Cumartesi'),
                            _buildWeeklyHeaderCell('Pazar'),
                          ],
                        ),
                        // Tasks Row
                        pw.TableRow(
                          children: [
                            _buildWeeklyDayCell(prog, 'Pazartesi'),
                            _buildWeeklyDayCell(prog, 'Salı'),
                            _buildWeeklyDayCell(prog, 'Çarşamba'),
                            _buildWeeklyDayCell(prog, 'Perşembe'),
                            _buildWeeklyDayCell(prog, 'Cuma'),
                            _buildWeeklyDayCell(prog, 'Cumartesi'),
                            _buildWeeklyDayCell(prog, 'Pazar'),
                          ],
                        ),
                      ],
                    ),
                    // ─── KAZANIM LİSTESİ ───
                    if (includeKazanimList && kazanimByBranch.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Pekiştirilecek Kazanımlar',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo800),
                      ),
                      pw.SizedBox(height: 4),
                      _buildSplittableRow(
                        decoration: pw.BoxDecoration(color: PdfColor.fromHex('#EDE7F6')),
                        bottomBorderWidth: 0.8,
                        bottomBorderColor: PdfColors.grey300,
                        flexes: const [15, 45],
                        children: [
                          _buildTableHeaderCell('Ders / Branş', alignLeft: true),
                          _buildTableHeaderCell('Kazanımlar', alignLeft: true),
                        ],
                      ),
                      ...kazanimByBranch.entries.map((entry) {
                        return _buildSplittableRow(
                          bottomBorderWidth: 0.4,
                          bottomBorderColor: PdfColors.grey200,
                          flexes: const [15, 45],
                          children: [
                            _buildTableCell(entry.key, alignLeft: true, isBold: true),
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: entry.value.map((kaz) => pw.Row(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Container(
                                      margin: const pw.EdgeInsets.only(top: 3, right: 4),
                                      width: 3, height: 3,
                                      decoration: const pw.BoxDecoration(
                                        shape: pw.BoxShape.circle,
                                        color: PdfColors.indigo400,
                                      ),
                                    ),
                                    pw.Expanded(child: pw.Text(kaz, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800))),
                                  ],
                                )).toList(),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ],
                  ],
                );
              }).toList(),
              pw.SizedBox(height: 24),
            ],

            // ─── 6. PEKİŞTİRİLECEK KONU ANALİZİ ───
            if (includeTopicAnalysis)
              if (studentTopicAnalysis.isEmpty)
                ...[
                  _buildSectionTitle('6. Konu Analizi'),
                  pw.SizedBox(height: 6),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 24),
                    child: pw.Text('Gösterilecek konu analizi verisi bulunmamaktadır.', style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
                  ),
                ]
              else ...[
                _buildSectionTitle('6. Konu Analizi'),
              pw.SizedBox(height: 6),
              pw.Text(
                'Öğrencimizin konu bazlı başarı durumları ve hedefler doğrultusunda öncelik verilecek/pekiştirilecek konuları:',
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
              ),
              pw.SizedBox(height: 8),
              ...() {
                final Map<String, List<Map<String, dynamic>>> groupedPriority = {};
                final Map<String, List<Map<String, dynamic>>> groupedReinforcement = {};
                final Set<String> allSubjects = {};

                for (var item in studentTopicAnalysis) {
                  if (item is Map) {
                    final mapItem = Map<String, dynamic>.from(item);
                    final subject = mapItem['dersAdi']?.toString() ?? mapItem['ders']?.toString() ?? mapItem['subject']?.toString() ?? 'Genel';
                    final topic = mapItem['konu']?.toString() ?? mapItem['topic']?.toString() ?? '-';
                    final rawSuccess = mapItem['basariYuzdesi'] ?? mapItem['successRate'] ?? mapItem['success'] ?? mapItem['basari'] ?? 0;

                    int successRate = 0;
                    if (rawSuccess is int) {
                      successRate = rawSuccess;
                    } else if (rawSuccess is num) {
                      successRate = rawSuccess.toInt();
                    } else {
                      successRate = int.tryParse(rawSuccess.toString()) ?? 0;
                    }

                    int threshold = 70;
                    final cleanSub = subject.trim().toLowerCase();
                    bool found = false;
                    for (var entry in topicAnalysisThresholds.entries) {
                      if (entry.key.trim().toLowerCase() == cleanSub) {
                        threshold = entry.value;
                        found = true;
                        break;
                      }
                    }
                    if (!found && topicAnalysisThresholds.containsKey('Genel')) {
                      threshold = topicAnalysisThresholds['Genel']!;
                    }

                    final parsedItem = {
                      'subject': subject,
                      'topic': topic,
                      'successRate': successRate,
                      'threshold': threshold,
                    };

                    allSubjects.add(subject);
                    if (successRate < threshold) {
                      groupedPriority.putIfAbsent(subject, () => []).add(parsedItem);
                    } else {
                      groupedReinforcement.putIfAbsent(subject, () => []).add(parsedItem);
                    }
                  }
                }

                // ── FLAT-ROW APPROACH: Each row is a separate MultiPage build item ──
                // This prevents the Container/Column nesting that causes mid-card page splits.
                final List<pw.Widget> subjectCards = [];
                for (final subject in allSubjects) {
                  final priorityList = groupedPriority[subject] ?? [];
                  final reinforcementList = groupedReinforcement[subject] ?? [];

                  final showPriority = topicAnalysisShowPriority && priorityList.isNotEmpty;
                  final showReinforcement = topicAnalysisShowReinforcement && reinforcementList.isNotEmpty;

                  if (!showPriority && !showReinforcement) continue;

                  priorityList.sort((a, b) => (a['successRate'] as int).compareTo(b['successRate'] as int));
                  reinforcementList.sort((a, b) => (b['successRate'] as int).compareTo(a['successRate'] as int));

                  final colors = _getSubjectHeaderColors(subject);

                  // Card header (rounded top, only top+left+right border)
                  subjectCards.add(_buildSubjectCardHeader(subject, colors));

                  // Priority topics
                  if (showPriority) {
                    subjectCards.add(_buildTopicSectionLabelRow(isPriority: true, colors: colors));
                    for (int i = 0; i < priorityList.length; i++) {
                      subjectCards.add(_buildTopicCardRow(
                        priorityList[i],
                        isPriority: true,
                        colors: colors,
                        isLastInCard: !showReinforcement && i == priorityList.length - 1,
                      ));
                    }
                  }

                  // Reinforcement topics
                  if (showReinforcement) {
                    subjectCards.add(_buildTopicSectionLabelRow(isPriority: false, colors: colors));
                    for (int i = 0; i < reinforcementList.length; i++) {
                      subjectCards.add(_buildTopicCardRow(
                        reinforcementList[i],
                        isPriority: false,
                        colors: colors,
                        isLastInCard: i == reinforcementList.length - 1,
                      ));
                    }
                  }

                  // Small gap after each subject card
                  subjectCards.add(pw.SizedBox(height: 6));
                }

                if (subjectCards.isEmpty) {
                  return [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 12),
                      child: pw.Center(
                        child: pw.Text(
                          'Gösterilecek konu bulunmamaktadır.',
                          style: pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic, color: PdfColors.grey600),
                        ),
                      ),
                    ),
                  ];
                }
                return subjectCards;
              }(),
              pw.SizedBox(height: 12),
            ],

            // ─── 7. HAFTALIK DERS PLANLARI ───
            if (includeLessonPlans)
              if (lessonPlans.isEmpty)
                ...[
                  _buildSectionTitle('7. Haftalık Ders Planları'),
                  pw.SizedBox(height: 6),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 24),
                    child: pw.Text('Bu başlığa ait haftalık ders planı verisi bulunmamaktadır.', style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
                  ),
                ]
              else ...[
                _buildSectionTitle('7. Haftalık Ders Planları'),
              pw.SizedBox(height: 6),
              pw.Text(
                'Öğretmenlerimiz tarafından girilen haftalık sınıf ders planları ve hedeflenen kazanımlar:',
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
              ),
              pw.SizedBox(height: 6),
              _buildSplittableRow(
                decoration: pw.BoxDecoration(color: PdfColor.fromHex('#ECEFF1')),
                bottomBorderWidth: 1.0,
                bottomBorderColor: PdfColors.grey400,
                flexes: const [18, 32, 20],
                children: [
                  _buildTableHeaderCell('Ders / Tarih', alignLeft: true),
                  _buildTableHeaderCell('İşlenen Konu / Açıklama', alignLeft: true),
                  _buildTableHeaderCell('Hedeflenen Kazanım', alignLeft: true),
                ],
              ),
              ...lessonPlans.map((plan) {
                final lessonName = _stripEmoji(plan['lessonName']?.toString() ?? plan['lesson']?.toString() ?? '-');
                final dateRaw = plan['date'];
                String dateStr = '-';
                if (dateRaw != null) {
                  if (dateRaw is DateTime) {
                    dateStr = DateFormat('dd.MM.yyyy').format(dateRaw);
                  } else if (dateRaw is Timestamp) {
                    dateStr = DateFormat('dd.MM.yyyy').format(dateRaw.toDate());
                  } else {
                    try {
                      if (dateRaw is Map && dateRaw.containsKey('_seconds')) {
                        final dt = DateTime.fromMillisecondsSinceEpoch(dateRaw['_seconds'] * 1000);
                        dateStr = DateFormat('dd.MM.yyyy').format(dt);
                      } else {
                        dateStr = dateRaw.toString();
                      }
                    } catch (_) {}
                  }
                }
                
                final title = _stripEmoji(plan['title']?.toString() ?? '');
                final content = _stripEmoji(plan['content']?.toString() ?? '');
                final outcome = _stripEmoji(plan['outcome']?.toString() ?? plan['kazanim']?.toString() ?? '-');
                
                final String desc = title.isNotEmpty
                    ? (content.isNotEmpty ? '$title\n$content' : title)
                    : content;

                return _buildSplittableRow(
                  bottomBorderWidth: 0.5,
                  bottomBorderColor: PdfColors.grey300,
                  flexes: const [18, 32, 20],
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            lessonName,
                            style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            dateStr,
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                          ),
                        ],
                      ),
                    ),
                    _buildTableCell(desc.isNotEmpty ? desc : '-', alignLeft: true),
                    _buildTableCell(outcome, alignLeft: true),
                  ],
                );
              }).toList(),
              pw.SizedBox(height: 24),
            ],

            // Signature is now rendered via MultiPage.footer (last page only)
          ];
        },
      ),
    );

  }

  // ─── PRIVATE WIDGET BUILDERS ───

  static pw.Widget _buildWeeklyHeaderCell(String day) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: pw.Center(
        child: pw.Text(
          day,
          style: pw.TextStyle(
            fontSize: 7.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.indigo900,
          ),
        ),
      ),
    );
  }

  static dynamic _getMapValueCaseInsensitive(Map<String, dynamic> map, String key) {
    if (map.containsKey(key)) return map[key];
    final normKey = _normalizeDayKey(key);
    for (var k in map.keys) {
      if (_normalizeDayKey(k) == normKey) {
        return map[k];
      }
    }
    return null;
  }

  static String _normalizeDayKey(String key) {
    return key
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .trim();
  }

  /// Strips emoji and other characters not supported by OpenSans PDF font.
  /// These show as X-boxes in the PDF if not removed.
  static String _stripEmoji(String text) {
    // Single pattern covering all emoji/symbol Unicode ranges
    return text
        .replaceAll(
          RegExp(
            r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
            r'\u{1F300}-\u{1F9FF}\u{FE00}-\u{FEFF}\u200D\uFE0F]',
            unicode: true,
          ),
          '',
        )
        .trim();
  }
  static pw.Widget _buildWeeklyDayCell(Map<String, dynamic> prog, String day) {
    final scheduleRaw = prog['schedule'];
    final schedule = (scheduleRaw is Map) ? Map<String, dynamic>.from(scheduleRaw) : <String, dynamic>{};
    final executionStatusRaw = prog['executionStatus'];
    final executionStatus = (executionStatusRaw is Map) ? Map<String, dynamic>.from(executionStatusRaw) : <String, dynamic>{};
    
    final tasksRaw = _getMapValueCaseInsensitive(schedule, day);
    final tasks = tasksRaw is List ? tasksRaw : [];
    
    final statusesRaw = _getMapValueCaseInsensitive(executionStatus, day);
    final statuses = statusesRaw is List ? statusesRaw : [];
    
    if (tasks.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: pw.Center(
          child: pw.Text(
            'Boş',
            style: pw.TextStyle(fontSize: 7, color: PdfColors.grey400, fontStyle: pw.FontStyle.italic),
          ),
        ),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: List.generate(tasks.length, (idx) {
          final taskText = _stripEmoji(tasks[idx]?.toString() ?? '');
          // Robust parse: Firestore can return int, num, double, or String
          final rawStatus = idx < statuses.length ? statuses[idx] : null;
          int statusVal = 0;
          if (rawStatus is int) {
            statusVal = rawStatus;
          } else if (rawStatus is num) {
            statusVal = rawStatus.toInt();
          } else if (rawStatus != null) {
            statusVal = int.tryParse(rawStatus.toString()) ?? 0;
          }
          
          PdfColor statusColor = PdfColors.grey400;
          if (statusVal == 1) {
            statusColor = PdfColor.fromHex('#2E7D32'); // Green
          } else if (statusVal == 2) {
            statusColor = PdfColor.fromHex('#EF6C00'); // Orange
          } else if (statusVal == 3) {
            statusColor = PdfColor.fromHex('#C62828'); // Red
          }

          final lines = taskText.split('\n');
          final branchLine = lines.isNotEmpty ? lines[0].trim() : '';
          final remainingText = lines.length > 1 ? lines.sublist(1).join('\n').trim() : '';
          final colors = _getSubjectColors(branchLine.isNotEmpty ? branchLine : taskText);

          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 4),
            padding: const pw.EdgeInsets.all(3),
            decoration: pw.BoxDecoration(
              color: colors['bg']!,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
              border: pw.Border.all(color: colors['border']!, width: 0.4),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  margin: const pw.EdgeInsets.only(top: 2, right: 2),
                  width: 4,
                  height: 4,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    color: statusColor,
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (branchLine.isNotEmpty)
                        pw.Text(
                          branchLine,
                          style: pw.TextStyle(
                            fontSize: 6.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey900,
                          ),
                        ),
                      if (remainingText.isNotEmpty) ...[
                        pw.SizedBox(height: 1),
                        pw.Text(
                          remainingText,
                          style: const pw.TextStyle(
                            fontSize: 6.0,
                            color: PdfColors.grey800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  static Map<String, PdfColor> _getSubjectColors(String taskText) {
    final clean = taskText.trim().toLowerCase();
    
    if (clean.contains('matematik') || clean.contains('mat')) {
      return {
        'bg': PdfColor.fromHex('#E0F2FE'), // Light blue
        'border': PdfColor.fromHex('#BAE6FD'),
      };
    } else if (clean.contains('türkçe') || clean.contains('turkce') || clean == 'tr') {
      return {
        'bg': PdfColor.fromHex('#F3E8FF'), // Light purple
        'border': PdfColor.fromHex('#E9D5FF'),
      };
    } else if (clean.contains('fen') || clean.contains('fizik') || clean.contains('kimya') || clean.contains('biyoloji')) {
      return {
        'bg': PdfColor.fromHex('#DCFCE7'), // Light green
        'border': PdfColor.fromHex('#BBF7D0'),
      };
    } else if (clean.contains('sosyal') || clean.contains('tarih') || clean.contains('coğrafya') || clean.contains('inkılap') || clean.contains('inkilap')) {
      return {
        'bg': PdfColor.fromHex('#FEF3C7'), // Light amber
        'border': PdfColor.fromHex('#FDE68A'),
      };
    } else if (clean.contains('ingilizce') || clean.contains('ing')) {
      return {
        'bg': PdfColor.fromHex('#FFE4E6'), // Light rose
        'border': PdfColor.fromHex('#FECDD3'),
      };
    } else if (clean.contains('din') || clean.contains('ahlak')) {
      return {
        'bg': PdfColor.fromHex('#F0FDFA'), // Light teal
        'border': PdfColor.fromHex('#CCFBF1'),
      };
    }
    
    // Default
    return {
      'bg': PdfColor.fromHex('#F9FAFB'),
      'border': PdfColor.fromHex('#ECEFF1'),
    };
  }

  static pw.Widget _buildSectionTitle(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: pw.BoxDecoration(
        border: const pw.Border(left: pw.BorderSide(color: PdfColors.indigo900, width: 3)),
        color: PdfColor.fromHex('#F5F5F5'),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.indigo900,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTableHeaderCell(String text, {bool alignLeft = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.grey900,
        ),
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text, {
    bool alignLeft = false,
    bool isBold = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColors.grey900,
        ),
      ),
    );
  }

  static pw.Widget _buildSplittableRow({
    required List<int> flexes,
    required List<pw.Widget> children,
    pw.BoxDecoration? decoration,
    double bottomBorderWidth = 0.0,
    PdfColor bottomBorderColor = PdfColors.grey300,
  }) {
    final List<pw.Widget> expandedChildren = [];
    for (int i = 0; i < children.length; i++) {
      final flex = i < flexes.length ? flexes[i] : 1;
      expandedChildren.add(
        pw.Expanded(
          flex: flex,
          child: children[i],
        ),
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: decoration?.color,
        borderRadius: decoration?.borderRadius,
        border: pw.Border(
          bottom: bottomBorderWidth > 0
              ? pw.BorderSide(color: bottomBorderColor, width: bottomBorderWidth)
              : pw.BorderSide.none,
          top: decoration?.border?.top ?? pw.BorderSide.none,
          left: decoration?.border?.left ?? pw.BorderSide.none,
          right: decoration?.border?.right ?? pw.BorderSide.none,
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: expandedChildren,
      ),
    );
  }

  static Map<String, PdfColor> _getSubjectHeaderColors(String subject) {
    final clean = subject.trim().toLowerCase();
    if (clean.contains('matematik') || clean.contains('mat')) {
      return {
        'bg': PdfColor.fromHex('#F0F9FF'),      // Light sky blue
        'border': PdfColor.fromHex('#BAE6FD'),  // Soft sky blue border
        'headerBg': PdfColor.fromHex('#E0F2FE'),// Blue header bg
        'text': PdfColor.fromHex('#0369A1'),    // Dark sky blue text
      };
    } else if (clean.contains('türkçe') || clean.contains('turkce') || clean == 'tr') {
      return {
        'bg': PdfColor.fromHex('#FAF5FF'),      // Light purple
        'border': PdfColor.fromHex('#E9D5FF'),  // Purple border
        'headerBg': PdfColor.fromHex('#F3E8FF'),// Purple header bg
        'text': PdfColor.fromHex('#7E22CE'),    // Dark purple text
      };
    } else if (clean.contains('fen') || clean.contains('fizik') || clean.contains('kimya') || clean.contains('biyoloji')) {
      return {
        'bg': PdfColor.fromHex('#F0FDF4'),      // Light emerald green
        'border': PdfColor.fromHex('#BBF7D0'),  // Emerald border
        'headerBg': PdfColor.fromHex('#DCFCE7'),// Emerald header bg
        'text': PdfColor.fromHex('#15803D'),    // Dark green text
      };
    } else if (clean.contains('sosyal') || clean.contains('tarih') || clean.contains('coğrafya') || clean.contains('inkılap') || clean.contains('inkilap') || clean.contains('felsefe')) {
      return {
        'bg': PdfColor.fromHex('#FFFBEB'),      // Light amber
        'border': PdfColor.fromHex('#FDE68A'),  // Amber border
        'headerBg': PdfColor.fromHex('#FEF3C7'),// Amber header bg
        'text': PdfColor.fromHex('#B45309'),    // Dark amber text
      };
    } else if (clean.contains('ingilizce') || clean.contains('ing')) {
      return {
        'bg': PdfColor.fromHex('#FFF1F2'),      // Light rose
        'border': PdfColor.fromHex('#FECDD3'),  // Rose border
        'headerBg': PdfColor.fromHex('#FFE4E6'),// Rose header bg
        'text': PdfColor.fromHex('#BE123C'),    // Dark rose text
      };
    } else if (clean.contains('din') || clean.contains('ahlak')) {
      return {
        'bg': PdfColor.fromHex('#F0FDFA'),      // Light teal
        'border': PdfColor.fromHex('#CCFBF1'),  // Teal border
        'headerBg': PdfColor.fromHex('#CCFBF1'),// Teal header bg
        'text': PdfColor.fromHex('#0F766E'),    // Dark teal text
      };
    }
    // Default fallback colors
    return {
      'bg': PdfColor.fromHex('#F9FAFB'),
      'border': PdfColor.fromHex('#E5E7EB'),
      'headerBg': PdfColor.fromHex('#F3F4F6'),
      'text': PdfColor.fromHex('#374151'),
    };
  }

  // ── Card header: rounded top, uniform border so borderRadius is allowed ──
  static pw.Widget _buildSubjectCardHeader(String subject, Map<String, PdfColor> colors) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      decoration: pw.BoxDecoration(
        color: colors['headerBg'],
        // Border.all (uniform) required to use borderRadius in pdf package
        border: pw.Border.all(color: colors['border']!, width: 0.8),
        borderRadius: const pw.BorderRadius.only(
          topLeft: pw.Radius.circular(8),
          topRight: pw.Radius.circular(8),
        ),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: pw.Text(
        subject.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: pw.FontWeight.bold,
          color: colors['text'],
        ),
      ),
    );
  }

  // ── Section label row (Öncelikli / Pekiştirilecek) ──
  static pw.Widget _buildTopicSectionLabelRow({
    required bool isPriority,
    required Map<String, PdfColor> colors,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: isPriority ? PdfColor.fromHex('#FFF5F5') : PdfColor.fromHex('#F0FFF4'),
        border: pw.Border(
          left: pw.BorderSide(color: colors['border']!, width: 0.8),
          right: pw.BorderSide(color: colors['border']!, width: 0.8),
        ),
      ),
      padding: const pw.EdgeInsets.fromLTRB(10, 6, 10, 4),
      child: pw.Row(
        children: [
          pw.Container(
            width: 5,
            height: 5,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              color: isPriority ? PdfColors.red700 : PdfColors.green700,
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Text(
            isPriority
                ? 'Öncelikli Konular (Çalışması Gerekenler)'
                : 'Pekiştirilecek Konular',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: isPriority ? PdfColors.red900 : PdfColors.green900,
            ),
          ),
        ],
      ),
    );
  }

  // ── Individual topic row with card-border continuity ──
  // NOTE: Cannot use borderRadius with non-uniform Border in pdf package.
  static pw.Widget _buildTopicCardRow(
    Map<String, dynamic> item, {
    required bool isPriority,
    required Map<String, PdfColor> colors,
    bool isLastInCard = false,
  }) {
    final topic = item['topic']?.toString() ?? '-';
    final successRate = item['successRate'] as int? ?? 0;

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: colors['bg'],
        // Non-uniform border → borderRadius NOT allowed here
        border: pw.Border(
          left: pw.BorderSide(color: colors['border']!, width: 0.8),
          right: pw.BorderSide(color: colors['border']!, width: 0.8),
          bottom: isLastInCard
              ? pw.BorderSide(color: colors['border']!, width: 0.8)
              : pw.BorderSide.none,
        ),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              topic,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: pw.BoxDecoration(
              color: isPriority ? PdfColor.fromHex('#FEE2E2') : PdfColor.fromHex('#D1FAE5'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              '%$successRate',
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: isPriority ? PdfColor.fromHex('#991B1B') : PdfColor.fromHex('#065F46'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Signature footer — rendered on all pages via MultiPage.footer ──
  static pw.Widget _buildSignatureFooter({
    required String classTeacherName,
    required String principalName,
    required int pageNumber,
    required int pagesCount,
    required bool includeFooter,
    required bool footerShowTeacher,
    required bool footerShowPageNumber,
    required bool footerShowPrincipal,
    required String footerSlogan,
  }) {
    if (!includeFooter) return pw.SizedBox.shrink();
    final isLastPage = pageNumber == pagesCount;

    return pw.Container(
      alignment: pw.Alignment.bottomCenter,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Divider(thickness: 0.5, color: PdfColors.grey300),
          pw.SizedBox(height: 3),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              // Teacher Signature Column
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (isLastPage && footerShowTeacher) ...[
                    pw.Text(
                      classTeacherName,
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Container(
                      width: 110,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 0.8)),
                      ),
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Text(
                        'Sınıf Rehber Öğretmeni',
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                      ),
                    ),
                  ] else ...[
                    pw.SizedBox.shrink(),
                  ],
                ],
              ),
              // Wish & Page Number Column
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  if (isLastPage && footerSlogan.isNotEmpty)
                    pw.Text(
                      footerSlogan,
                      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic),
                    ),
                  if (footerShowPageNumber) ...[
                    pw.SizedBox(height: 1),
                    pw.Text(
                      'Sayfa $pageNumber / $pagesCount',
                      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500),
                    ),
                  ],
                ],
              ),
              // Principal Signature Column
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (isLastPage && footerShowPrincipal) ...[
                    pw.Text(
                      principalName,
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Container(
                      width: 110,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 0.8)),
                      ),
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          'Kurum Yöneticisi',
                          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
                        ),
                      ),
                    ),
                  ] else ...[
                    pw.SizedBox.shrink(),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
