import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'evaluation_models.dart';
import '../../../models/assessment/trial_exam_model.dart';
import '../../../models/assessment/external_exam_model.dart';
import '../../../services/external_exam_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:edukn/services/web_share/web_file_share.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'exam_report_card_service.dart';

class StudentReportCardDialog extends StatefulWidget {
  final StudentResult student;
  final String examName;
  final List<String> subjects;
  final Map<String, Map<String, List<String>>> outcomes;
  final int totalStudents;
  final int schoolStudents;
  final int branchStudents;
  final bool isRankingVisible;
  final String? trialExamId;
  final String? schoolTypeName;

  const StudentReportCardDialog({
    Key? key,
    required this.student,
    required this.examName,
    required this.subjects,
    this.outcomes = const {},
    this.totalStudents = 0,
    this.schoolStudents = 0,
    this.branchStudents = 0,
    this.isRankingVisible = true,
    this.trialExamId,
    this.schoolTypeName,
  }) : super(key: key);

  @override
  _StudentReportCardDialogState createState() =>
      _StudentReportCardDialogState();
}

class _StudentReportCardDialogState extends State<StudentReportCardDialog> {
  late StudentResult student;
  late String examName;
  late List<String> subjects;
  late Map<String, Map<String, List<String>>> outcomes;
  late int totalStudents;
  late int schoolStudents;
  late int branchStudents;
  late bool isRankingVisible;

  String? _selectedKeySubject;
  String? _selectedOutcomeSubject;

  ExternalExam? _externalExam;
  ScholarshipTier? _scholarshipTier;
  bool _loadingScholarship = false;
  String? _fetchedSchoolTypeName;

  @override
  void initState() {
    super.initState();
    student = widget.student;
    examName = widget.examName;
    subjects = ExamReportCardService.sortSubjectsList(widget.subjects);
    outcomes = widget.outcomes;
    // restore original content
    totalStudents = widget.totalStudents;
    schoolStudents = widget.schoolStudents;
    branchStudents = widget.branchStudents;
    isRankingVisible = widget.isRankingVisible;

    if (subjects.isNotEmpty) {
      _selectedKeySubject = subjects.first;
      _selectedOutcomeSubject = subjects.first;
    }
    _checkScholarship();
    _fetchSchoolTypeName();
  }

  Future<void> _fetchSchoolTypeName() async {
    try {
      if (widget.trialExamId != null && widget.trialExamId!.isNotEmpty) {
        final examDoc = await FirebaseFirestore.instance
            .collection('trial_exams')
            .doc(widget.trialExamId)
            .get();
        if (examDoc.exists) {
          final examData = examDoc.data();

          // Fetch examType defined subject order if available
          final examTypeId = examData?['examTypeId']?.toString();
          if (examTypeId != null && examTypeId.isNotEmpty) {
            try {
              final etDoc = await FirebaseFirestore.instance
                  .collection('exam_types')
                  .doc(examTypeId)
                  .get();
              if (etDoc.exists) {
                final rawSubjs = etDoc.data()?['subjects'];
                if (rawSubjs is List) {
                  final definedOrder = rawSubjs
                      .map((s) => s is Map
                          ? (s['branchName'] ?? s['name'] ?? '').toString()
                          : s.toString())
                      .where((s) => s.isNotEmpty)
                      .toList();
                  if (definedOrder.isNotEmpty && mounted) {
                    setState(() {
                      subjects = ExamReportCardService.sortSubjectsList(
                        widget.subjects,
                        definedOrder: definedOrder,
                      );
                      if (subjects.isNotEmpty) {
                        if (!subjects.contains(_selectedKeySubject)) {
                          _selectedKeySubject = subjects.first;
                        }
                        if (!subjects.contains(_selectedOutcomeSubject)) {
                          _selectedOutcomeSubject = subjects.first;
                        }
                      }
                    });
                  }
                }
              }
            } catch (e) {
              debugPrint('Error fetching examType subjects: $e');
            }
          }

          if (widget.schoolTypeName != null &&
              widget.schoolTypeName!.trim().isNotEmpty &&
              widget.schoolTypeName!.trim().toLowerCase() != 'eğitim kurumu' &&
              widget.schoolTypeName!.trim().toLowerCase() != 'egitim kurumu') {
            return;
          }

          final stName = examData?['schoolTypeName']?.toString().trim();
          if (stName != null && stName.isNotEmpty) {
            if (mounted) setState(() => _fetchedSchoolTypeName = stName);
            return;
          }
          final stId = examData?['schoolTypeId']?.toString().trim();
          if (stId != null && stId.isNotEmpty) {
            final stDoc = await FirebaseFirestore.instance
                .collection('schoolTypes')
                .doc(stId)
                .get();
            if (stDoc.exists) {
              final name = (stDoc.data()?['name'] ??
                      stDoc.data()?['schoolTypeName'] ??
                      stDoc.data()?['schoolType'] ??
                      '')
                  .toString()
                  .trim();
              if (name.isNotEmpty) {
                if (mounted) setState(() => _fetchedSchoolTypeName = name);
                return;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching schoolTypeName in dialog: $e');
    }
  }

  String _resolveSchoolTypeName() {
    if (widget.schoolTypeName != null &&
        widget.schoolTypeName!.trim().isNotEmpty &&
        widget.schoolTypeName!.trim().toLowerCase() != 'eğitim kurumu' &&
        widget.schoolTypeName!.trim().toLowerCase() != 'egitim kurumu') {
      return widget.schoolTypeName!.trim();
    }
    if (_fetchedSchoolTypeName != null &&
        _fetchedSchoolTypeName!.trim().isNotEmpty &&
        _fetchedSchoolTypeName!.trim().toLowerCase() != 'eğitim kurumu' &&
        _fetchedSchoolTypeName!.trim().toLowerCase() != 'egitim kurumu') {
      return _fetchedSchoolTypeName!.trim();
    }
    final level = student.classLevel;
    final digits = RegExp(r'\d+').firstMatch(level)?.group(0);
    if (digits != null) {
      final grade = int.tryParse(digits);
      if (grade != null) {
        if (grade >= 1 && grade <= 4) return 'İlkokul';
        if (grade >= 5 && grade <= 8) return 'Ortaokul';
        if (grade >= 9 && grade <= 12) return 'Anadolu Lisesi';
      }
    }
    final clean = level.toLowerCase();
    if (clean.contains('anaokul') || clean.contains('kreş') || clean.contains('anasınıf') || clean.contains('okul öncesi')) {
      return 'Anaokulu';
    }
    if (clean.contains('ilkokul')) return 'İlkokul';
    if (clean.contains('ortaokul') || clean.contains('lgs')) return 'Ortaokul';
    if (clean.contains('lise') || clean.contains('yks') || clean.contains('tyt')) return 'Anadolu Lisesi';
    return 'Ortaokul';
  }

  Future<void> _checkScholarship() async {
    if (widget.trialExamId == null) return;
    setState(() => _loadingScholarship = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('external_exams')
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in snap.docs) {
        final data = doc.data();
        final trialExamIds = data['trialExamIds'] as Map<dynamic, dynamic>?;
        if (trialExamIds != null &&
            trialExamIds.values.contains(widget.trialExamId)) {
          final exam = ExternalExam.fromMap(data, doc.id);
          final tier = ExternalExamService().getScholarshipTier(
            exam,
            student.classLevel,
            student.rankGeneral,
          );
          if (mounted) {
            setState(() {
              _externalExam = exam;
              _scholarshipTier = tier;
            });
          }
          break;
        }
      }
    } catch (e) {
      debugPrint("Scholarship check failed: $e");
    } finally {
      if (mounted) {
        setState(() => _loadingScholarship = false);
      }
    }
  }

  Widget _buildScholarshipBanner() {
    if (_scholarshipTier == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.shade100.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KAZANILAN BURS DERECESİ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.amber.shade900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tebrikler! Sınav sonucunuza göre %${_scholarshipTier!.rate} Burs kazandınız.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                // Karnede derece/sıralama gösterilmez.
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.shade800,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              '%${_scholarshipTier!.rate} BURS',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfScholarshipBanner() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        color: PdfColors.amber100,
        border: pw.Border.all(color: PdfColors.amber700, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            "TEBRİKLER! SINAV DERECENİZE GÖRE KAZANILAN BURS ORANI:  %${_scholarshipTier!.rate} BURS",
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
              color: PdfColors.amber900,
            ),
          ),
          // Karnede derece/sıralama gösterilmez.
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EduknAppBar(
        title: 'Sınav Sonuç Belgesi',
        actions: [
          IconButton(
            icon: Icon(Icons.print),
            tooltip: 'Yazdır / PDF',
            onPressed: () => _printReport(context),
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Paylaş (WhatsApp / PDF)',
            onPressed: () => _showStudentShareDialog(context),
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      backgroundColor: Colors.white,
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: 900),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderSection(),
                SizedBox(height: 12),
                _buildScoreSummaryTable(),
                SizedBox(height: 12),
                _buildRankInfoTable(),
                SizedBox(height: 12),
                _buildPerformanceChart(),
                SizedBox(height: 24),
                _buildAnswerKeySectionWithTabs(),
                SizedBox(height: 24),
                _buildScholarshipBanner(),
                Center(
                  child: Text(
                    'DERSLERE VE KONULARA GÖRE SINAV ANALİZİ',
                    style: TextStyle(
                      color: Colors.pink,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                SizedBox(height: 8),
                Container(height: 2, color: Colors.grey.shade400),
                SizedBox(height: 12),
                _buildTopicAnalysisSectionWithTabs(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectSelector(String? selected, Function(String) onSelect) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: subjects.map((s) {
          final isSelected = s == selected;
          return Padding(
            padding: EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(s),
              selected: isSelected,
              onSelected: (v) => onSelect(s),
              selectedColor: Colors.orange.shade100,
              backgroundColor: Colors.grey.shade100,
              labelStyle: TextStyle(
                color: isSelected ? Colors.orange.shade900 : Colors.black,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAnswerKeySectionWithTabs() {
    if (_selectedKeySubject == null)
      return Center(child: Text("Ders bulunamadı"));
    return Column(
      children: [
        _buildSubjectSelector(
          _selectedKeySubject,
          (s) => setState(() => _selectedKeySubject = s),
        ),
        SizedBox(height: 8),
        _buildAnswerKeySectionSingle(_selectedKeySubject!),
      ],
    );
  }

  Widget _buildTopicAnalysisSectionWithTabs() {
    if (_selectedOutcomeSubject == null)
      return Center(child: Text("Ders bulunamadı"));
    return Column(
      children: [
        _buildSubjectSelector(
          _selectedOutcomeSubject,
          (s) => setState(() => _selectedOutcomeSubject = s),
        ),
        SizedBox(height: 8),
        _buildTopicAnalysisSectionSingle(_selectedOutcomeSubject!),
      ],
    );
  }

  // Wrappers or implementations for single subject

  Widget _buildAnswerKeySectionSingle(String subject) {
    if (!student.answers.containsKey(subject))
      return Container(child: Text("Bu ders için cevap bulunamadı."));

    final studentAns = student.answers[subject] ?? "";
    final correctAns = student.correctAnswers[subject] ?? "";
    final int len = correctAns.length > studentAns.length
        ? correctAns.length
        : studentAns.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: Colors.orange.shade100,
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            subject,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ),
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAnswerRowLabel("SORU NO", Colors.grey.shade300),
                _buildAnswerRowLabel("CEVAP ANAHTARI", Colors.grey.shade200),
                _buildAnswerRowLabel("ÖĞRENCİ CEVABI", Colors.grey.shade100),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(len, (i) {
                        return _buildAnswerBox(
                          "${i + 1}",
                          Colors.grey.shade300,
                          isKey: true,
                        );
                      }),
                    ),
                    Row(
                      children: List.generate(len, (i) {
                        String c = (i < correctAns.length) ? correctAns[i] : "";
                        return _buildAnswerBox(c, Colors.white, isKey: true);
                      }),
                    ),
                    Row(
                      children: List.generate(len, (i) {
                        String s = (i < studentAns.length)
                            ? studentAns[i]
                            : " ";
                        String c = (i < correctAns.length) ? correctAns[i] : "";

                        final status = TrialExam.evaluateAnswer(s, c);
                        bool isCorrect = status == AnswerStatus.correct;
                        bool isEmpty = status == AnswerStatus.empty;

                        Color bg = Colors.white;

                        if (isEmpty)
                          bg = Colors.white;
                        else if (isCorrect)
                          bg = Colors.green.shade100;
                        else
                          bg = Colors.red.shade100;

                        String displayChar = s;
                        if (isCorrect)
                          displayChar = displayChar.toUpperCase();
                        else
                          displayChar = displayChar.toLowerCase();

                        if (i >= correctAns.length) bg = Colors.grey;

                        return _buildAnswerBox(displayChar, bg);
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopicAnalysisSectionSingle(String subject) {
    String lookupBooklet = student.booklet;
    if (!outcomes.containsKey(lookupBooklet)) {
      if (lookupBooklet.length > 1 && outcomes.containsKey(lookupBooklet[0])) {
        lookupBooklet = lookupBooklet[0];
      }
    }

    if (!outcomes.containsKey(lookupBooklet)) {
      return SizedBox.shrink();
    }

    if (!outcomes[lookupBooklet]!.containsKey(subject)) {
      return SizedBox.shrink();
    }

    final List<String> subjectOutcomes = outcomes[lookupBooklet]![subject]!;
    if (subjectOutcomes.isEmpty) return SizedBox.shrink();

    final correctAns = student.correctAnswers[subject] ?? "";
    final studentAns = student.answers[subject] ?? "";

    Map<String, _TopicStat> stats = {};

    int len = correctAns.length;
    if (subjectOutcomes.length < len) len = subjectOutcomes.length;

    for (int i = 0; i < len; i++) {
      String topic = subjectOutcomes[i];
      if (topic.isEmpty) topic = "Genel";

      stats.putIfAbsent(topic, () => _TopicStat());

      String c = correctAns[i];
      String s = (i < studentAns.length) ? studentAns[i] : " ";

      stats[topic]!.total++;

      final result = TrialExam.evaluateAnswer(s, c);
      if (result == AnswerStatus.correct) {
        stats[topic]!.correct++;
      } else if (result == AnswerStatus.empty) {
        stats[topic]!.empty++;
      } else {
        stats[topic]!.wrong++;
      }
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(border: Border.all(color: Colors.black87)),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: Color(0xFFFFCC80),
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Text(
              subject,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Container(
            color: Colors.white,
            child: Row(
              children: [
                _buildTopicCell("KONU ADI", flex: 6, isHeader: true),
                _buildTopicCell("SS", flex: 1, isHeader: true),
                _buildTopicCell("D", flex: 1, isHeader: true),
                _buildTopicCell("Y", flex: 1, isHeader: true),
                _buildTopicCell("%", flex: 1, isHeader: true),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.black54),
          ...stats.entries.map((e) {
            final stat = e.value;
            int success = (stat.total > 0)
                ? ((stat.correct / stat.total) * 100).round()
                : 0;
            int idx = stats.keys.toList().indexOf(e.key);
            Color rowColor = (idx % 2 == 0) ? Color(0xFFFFF3E0) : Colors.white;

            return Container(
              color: rowColor,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopicCell(e.key, flex: 6, alignLeft: true),
                    _buildTopicCell("${stat.total}", flex: 1),
                    _buildTopicCell("${stat.correct}", flex: 1),
                    _buildTopicCell("${stat.wrong}", flex: 1),
                    _buildTopicCell("$success", flex: 1),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.black54)),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            color: Colors.grey.shade100,
            width: double.infinity,
            child: Text(
              'SINAV SONUÇ BELGESİ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.blue.shade900,
              ),
            ),
          ),
          Divider(height: 1, color: Colors.black54),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildInfoCell("SINAV ADI", examName, isHeader: true),
              ),
            ],
          ),
          Divider(height: 1, color: Colors.black54),
          Row(
            children: [
              Expanded(child: _buildInfoCell("ADI SOYADI", student.name)),
              Container(width: 1, height: 40, color: Colors.black54),
              Expanded(
                child: _buildInfoCell(
                  "SINIFI / ŞUBESİ",
                  "${student.classLevel} / ${student.branch}",
                ),
              ),
              Container(width: 1, height: 40, color: Colors.black54),
              Expanded(child: _buildInfoCell("NUMARASI", student.studentNo)),
              Container(width: 1, height: 40, color: Colors.black54),
              Expanded(child: _buildInfoCell("KİTAPÇIK TÜRÜ", student.booklet)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCell(String label, String value, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: isHeader ? 14 : 13,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildRankInfoTable() {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.black87)),
      child: Column(
        children: [
          Row(
            children: [
              _buildRankCell("", isHeader: true),
              _buildRankCell("GENEL", isHeader: true),
              _buildRankCell("KURUM", isHeader: true),
              _buildRankCell("ŞUBE", isHeader: true),
            ],
          ),
          Divider(height: 1, color: Colors.black54),
          Row(
            children: [
              _buildRankCell("KATILIM", isHeader: true, alignLeft: true),
              _buildRankCell("$totalStudents"),
              _buildRankCell("$schoolStudents"),
              _buildRankCell("$branchStudents"),
            ],
          ),
          if (isRankingVisible) ...[
            Divider(height: 1, color: Colors.black54),
            Row(
              children: [
                _buildRankCell("DERECE", isHeader: true, alignLeft: true),
                _buildRankCell(student.rankGeneral > 0 ? "${student.rankGeneral}" : "-", isBold: true),
                _buildRankCell(student.rankInstitution > 0 ? "${student.rankInstitution}" : "-", isBold: true),
                _buildRankCell(student.rankBranch > 0 ? "${student.rankBranch}" : "-", isBold: true),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRankCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    bool alignLeft = false,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isHeader ? Colors.grey.shade200 : Colors.white,
          border: Border(right: BorderSide(color: Colors.black45)),
        ),
        alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontWeight: isHeader || isBold
                ? FontWeight.bold
                : FontWeight.normal,
            fontSize: 11,
          ),
          textAlign: alignLeft ? TextAlign.left : TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildPerformanceChart() {
    return Column(
      children: [
        _buildSingleBarChart(
          "GENEL BAŞARI",
          student.total.correct,
          student.total.wrong,
          student.total.empty,
        ),
        SizedBox(height: 12),
        ...subjects.map((s) {
          final stats = student.subjects[s];
          if (stats == null) return SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: _buildSingleBarChart(
              s,
              stats.correct,
              stats.wrong,
              stats.empty,
              height: 20,
              showTitle: true,
            ),
          );
        }).toList(),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLegendItem("Doğru", Colors.green),
            SizedBox(width: 12),
            _buildLegendItem("Yanlış", Colors.red),
            SizedBox(width: 12),
            _buildLegendItem("Boş", Colors.grey.shade300),
          ],
        ),
      ],
    );
  }

  Widget _buildSingleBarChart(
    String title,
    int correct,
    int wrong,
    int empty, {
    double height = 25,
    bool showTitle = true,
  }) {
    int total = correct + wrong + empty;
    if (total == 0) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle)
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: Colors.grey.shade800,
            ),
          ),
        if (showTitle) SizedBox(height: 4),
        Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade400),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Row(
              children: [
                _buildBarPart(correct, total, Colors.green),
                _buildBarPart(wrong, total, Colors.red),
                _buildBarPart(
                  empty,
                  total,
                  Colors.grey.shade300,
                  showText: false,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBarPart(
    int value,
    int total,
    Color color, {
    bool showText = true,
  }) {
    if (value <= 0) return SizedBox.shrink();
    return Expanded(
      flex: value,
      child: Container(
        color: color,
        alignment: Alignment.center,
        child: showText
            ? Text(
                "%${((value / total) * 100).round()}",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, color: color),
        SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _buildScoreSummaryTable() {
    List<Widget> headers = [
      _buildTableCell("DERSLER", isHeader: true),
      ...subjects.map((s) => _buildTableCell(s, isHeader: true)),
      _buildTableCell("TOPLAM", isHeader: true, color: Colors.pink.shade50),
    ];

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.black87)),
      child: Column(
        children: [
          IntrinsicHeight(child: Row(children: headers)),
          Divider(height: 1, color: Colors.black87),
          _buildStatRow(
            "SORU S.",
            (s) =>
                "${(student.subjects[s]?.correct ?? 0) + (student.subjects[s]?.wrong ?? 0) + (student.subjects[s]?.empty ?? 0)}",
          ),
          Divider(height: 1, color: Colors.black45),
          _buildStatRow("DOĞRU", (s) => "${student.subjects[s]?.correct ?? 0}"),
          Divider(height: 1, color: Colors.black45),
          _buildStatRow("YANLIŞ", (s) => "${student.subjects[s]?.wrong ?? 0}"),
          Divider(height: 1, color: Colors.black45),
          _buildStatRow("BOŞ", (s) => "${student.subjects[s]?.empty ?? 0}"),
          Divider(height: 1, color: Colors.black45),
          _buildStatRow(
            "NET",
            (s) => (student.subjects[s]?.net ?? 0).toStringAsFixed(2),
            isBold: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(
    String title,
    String Function(String subject) getValue, {
    bool isBold = false,
  }) {
    List<Widget> cells = [
      _buildTableCell(title, isHeader: true, alignLeft: true),
      ...subjects.map((s) => _buildTableCell(getValue(s), isBold: isBold)),
      _buildTableCell(
        _getTotalValue(title),
        isBold: isBold,
        color: Colors.pink.shade50,
      ),
    ];
    return IntrinsicHeight(child: Row(children: cells));
  }

  String _getTotalValue(String title) {
    double total = 0;
    int intTotal = 0;
    bool isDouble = title.contains("NET");

    for (var s in subjects) {
      final stats = student.subjects[s];
      if (stats != null) {
        if (title.contains("DOĞRU")) intTotal += stats.correct;
        if (title.contains("YANLIŞ")) intTotal += stats.wrong;
        if (title.contains("BOŞ")) intTotal += stats.empty;
        if (title.contains("SORU"))
          intTotal += (stats.correct + stats.wrong + stats.empty);
        if (title.contains("NET")) total += stats.net;
      }
    }

    return isDouble ? total.toStringAsFixed(2) : intTotal.toString();
  }

  Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    Color? color,
    bool alignLeft = false,
  }) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: color ?? (isHeader ? Colors.grey.shade200 : Colors.white),
          border: Border(right: BorderSide(color: Colors.black45)),
        ),
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontWeight: (isHeader || isBold)
                ? FontWeight.bold
                : FontWeight.normal,
            fontSize: 10,
          ),
          maxLines: 2,
          textAlign: alignLeft ? TextAlign.left : TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildAnswerRowLabel(String label, Color color) {
    return Container(
      width: 100,
      height: 20, // Fixed height to match boxes
      padding: EdgeInsets.only(left: 4),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: color,
        border: Border(
          right: BorderSide(color: Colors.grey),
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildAnswerBox(String char, Color color, {bool isKey = false}) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        border: Border(
          right: BorderSide(color: Colors.grey.shade400),
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        char,
        style: TextStyle(
          fontSize: 10,
          fontWeight: isKey ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildTopicCell(
    String text, {
    int flex = 1,
    bool isHeader = false,
    bool alignLeft = false,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Colors.black26),
            bottom: BorderSide(color: Colors.black12),
          ),
        ),
        alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          ),
          textAlign: alignLeft ? TextAlign.left : TextAlign.center,
        ),
      ),
    );
  }

  Future<void> _printReport(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3, color: Colors.indigo),
                ),
                const SizedBox(width: 16),
                const Text("Karne hazırlanıyor...", style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      },
    );

    try {
      await Future.delayed(const Duration(milliseconds: 150));
      final pdfBytes = await _buildStudentReportCardPdfBytes();

      if (Navigator.of(context, rootNavigator: true).canPop()) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: sanitizeFileName('sinav_sonuc_belgesi_${student.studentNo}.pdf'),
      );
    } catch (e, stack) {
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      }
      debugPrint("Print error: $e");
      debugPrint("$stack");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Yazdırma sırasında bir hata oluştu: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Uint8List> _buildStudentReportCardPdfBytes() async {
    final instName = _resolveSchoolTypeName();

    return await ExamReportCardService().generateStudentReportCardsPdf(
      students: [student],
      examName: examName,
      institutionName: instName,
      subjects: subjects,
      outcomes: outcomes,
      totalStudents: totalStudents,
      schoolStudents: schoolStudents,
      branchStudentCounts: {student.branch: branchStudents},
      isRankingVisible: isRankingVisible,
    );
  }

  Future<void> _showStudentShareDialog(BuildContext context) async {
    final pdfFileName = sanitizeFileName('karne_${student.studentNo}_${student.name}.pdf');

    final sb = StringBuffer();
    sb.writeln('🎓 *eduKN Öğrenci Sınav Sonuç Belgesi (Karne)*');
    sb.writeln('👤 *Öğrenci:* ${student.name} (${student.studentNo})');
    sb.writeln('🏫 *Sınıf / Şube:* ${student.classLevel}/${student.branch}');
    sb.writeln('📝 *Sınav:* $examName');
    sb.writeln('📊 *Toplam Net:* ${student.total.net.toStringAsFixed(2)} | *Toplam Puan:* ${student.score.toStringAsFixed(2)}');
    // Karnede derece/sıralama gösterilmez.
    final summaryText = sb.toString().trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.share_rounded, color: Colors.indigo.shade700, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${student.name} - Karne Paylaş',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Karne PDF belgesini veya özetini paylaşın',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // 1. PDF Karnesini Paylaş (WhatsApp vb. - Doğrudan Belge)
              _buildShareOptionItem(
                icon: Icons.share_rounded,
                iconColor: const Color(0xFF25D366),
                bgColor: const Color(0xFFE8F5E9),
                title: 'PDF Karnesini Paylaş (WhatsApp vb.)',
                subtitle: 'Öğrenci karne PDF belgesini WhatsApp veya diğer uygulamalarla doğrudan iletin',
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final bytes = await _buildStudentReportCardPdfBytes();
                    final shared = await _tryShareFile(
                      bytes: bytes,
                      fileName: pdfFileName,
                      mimeType: 'application/pdf',
                      title: '$examName - ${student.name} Karnesi',
                      text: summaryText,
                    );
                    if (shared) return;

                    await Printing.sharePdf(bytes: bytes, filename: pdfFileName);
                  } catch (e) {
                    debugPrint('Student PDF share error: $e');
                  }
                },
              ),
              const SizedBox(height: 10),

              // 2. PDF Karnesini İndir
              _buildShareOptionItem(
                icon: Icons.download_rounded,
                iconColor: Colors.red.shade700,
                bgColor: Colors.red.shade50,
                title: 'PDF Karnesini İndir',
                subtitle: 'Öğrenci karne PDF belgesini doğrudan bilgisayarınıza indirin',
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final bytes = await _buildStudentReportCardPdfBytes();
                    await Printing.sharePdf(bytes: bytes, filename: pdfFileName);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('📁 "$pdfFileName" bilgisayarınıza indirildi.'),
                          backgroundColor: Colors.indigo.shade800,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } catch (e) {
                    debugPrint('Download error: $e');
                  }
                },
              ),
              const SizedBox(height: 6),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // Alt Butonlar: Link Olarak Paylaş & Metni Kopyala
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    icon: Icon(Icons.cloud_upload_outlined, size: 16, color: Colors.teal.shade700),
                    label: Text(
                      'WhatsApp İndirme Linki (Bulut)',
                      style: TextStyle(fontSize: 12, color: Colors.teal.shade700, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _shareStudentPdfToWhatsApp(summaryText, pdfFileName);
                    },
                  ),
                  TextButton.icon(
                    icon: Icon(Icons.copy_rounded, size: 16, color: Colors.grey.shade700),
                    label: Text(
                      'Metni Kopyala',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await Clipboard.setData(ClipboardData(text: summaryText));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Öğrenci karnesi metni panoya kopyalandı!'),
                            backgroundColor: Colors.indigo.shade800,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _tryShareFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String title,
    String? text,
  }) async {
    if (kIsWeb) {
      return await shareFileWeb(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        title: title,
        text: text,
      );
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
          fileNameOverrides: [fileName],
          subject: title,
          text: text,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _shareStudentPdfToWhatsApp(String summaryText, String pdfFileName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Karne PDF'i hazırlanıyor ve WhatsApp bağlantısı oluşturuluyor..."),
            ],
          ),
        ),
      ),
    );

    try {
      final bytes = await _buildStudentReportCardPdfBytes();
      final safeName = sanitizeFileName(pdfFileName);
      String? pdfUrl;
      try {
        final ref = FirebaseStorage.instance
            .ref()
            .child('reports/${student.studentNo}_${DateTime.now().millisecondsSinceEpoch}_$safeName');
        final task = await ref.putData(
          bytes,
          SettableMetadata(contentType: 'application/pdf'),
        );
        pdfUrl = await task.ref.getDownloadURL();
      } catch (e) {
        debugPrint('Firebase Storage upload error: $e');
      }

      // Download file locally too
      try {
        await Printing.sharePdf(bytes: bytes, filename: safeName);
      } catch (e) {
        debugPrint('Printing share error: $e');
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        if (pdfUrl != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('✅ Karne PDF hazırlandı ve indirildi! WhatsApp mesajına doğrudan PDF bağlantısı eklendi.'),
              backgroundColor: Colors.teal.shade800,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('📁 Karne PDF bilgisayarınıza indirildi. İndirilen PDF dosyasını açılan WhatsApp Web sohbetine sürükleyebilirsiniz.'),
              backgroundColor: Colors.indigo.shade800,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }

      final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());
      final msgSb = StringBuffer();
      msgSb.writeln('🎓 *eduKN Öğrenci Sınav Sonuç Belgesi (Karne)*');
      msgSb.writeln('👤 *Öğrenci:* ${student.name} (${student.studentNo})');
      msgSb.writeln('🏫 *Sınıf / Şube:* ${student.classLevel}/${student.branch}');
      msgSb.writeln('📝 *Sınav:* $examName');
      msgSb.writeln('📅 *Tarih:* $dateStr');
      msgSb.writeln('');
      if (pdfUrl != null) {
        msgSb.writeln('📄 *Resmi Öğrenci Karnesi PDF Belgesini İncelemek ve İndirmek İçin Tıklayın:*');
        msgSb.writeln('👉 $pdfUrl');
        msgSb.writeln('');
      }
      msgSb.writeln(summaryText);

      final waUrl = Uri.parse(
          'https://api.whatsapp.com/send?text=${Uri.encodeComponent(msgSb.toString().trim())}');
      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Karne paylaşılırken hata oluştu: $e')),
        );
      }
    }
  }

  Widget _buildShareOptionItem({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildPdfHeader() {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.5),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            color: PdfColors.grey200,
            width: double.infinity,
            padding: const pw.EdgeInsets.all(1),
            child: pw.Text(
              "SINAV SONUÇ BELGESİ",
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            ),
          ),
          pw.Divider(height: 1, thickness: 0.5),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 2,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(2),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "Adı Soyadı: ${student.name.toUpperCase()}",
                        style: pw.TextStyle(fontSize: 7),
                      ),
                      pw.Text(
                        "Okul No: ${student.studentNo}",
                        style: pw.TextStyle(fontSize: 7),
                      ),
                      pw.Text(
                        "Sınıf / Şube: ${student.classLevel} / ${student.branch}",
                        style: pw.TextStyle(fontSize: 7),
                      ),
                    ],
                  ),
                ),
              ),
              pw.Container(width: 0.5, height: 25, color: PdfColors.black),
              pw.Expanded(
                flex: 3,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(2),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        examName,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfScoreRankSection() {
    final headers = ['DERSLER'];
    final rowQ = ['SORU'];
    final rowD = ['DOĞRU'];
    final rowY = ['YANLIŞ'];
    final rowN = ['NET'];
    final rowSucc = ['%'];

    int totalQ = 0;
    int totalD = 0;
    int totalY = 0;
    double totalN = 0;

    for (var s in subjects) {
      String shortName = s;
      if (s.length > 3) shortName = s.substring(0, 3);
      headers.add(shortName);

      if (student.subjects.containsKey(s)) {
        final stat = student.subjects[s]!;
        int qLen = stat.correct + stat.wrong + stat.empty;
        if (student.correctAnswers.containsKey(s))
          qLen = student.correctAnswers[s]!.length;

        rowQ.add(qLen.toString());
        rowD.add(stat.correct.toString());
        rowY.add(stat.wrong.toString());
        rowN.add(stat.net.toStringAsFixed(1));

        double success = qLen > 0 ? (stat.correct / qLen) * 100 : 0;
        rowSucc.add("%${success.toStringAsFixed(0)}");

        totalQ += qLen;
        totalD += stat.correct;
        totalY += stat.wrong;
        totalN += stat.net;
      } else {
        rowQ.add("0");
        rowD.add("0");
        rowY.add("0");
        rowN.add("0");
        rowSucc.add("%0");
      }
    }

    headers.add("TOP");
    rowQ.add(totalQ.toString());
    rowD.add(totalD.toString());
    rowY.add(totalY.toString());
    rowN.add(totalN.toStringAsFixed(1));
    rowSucc.add("-");

    final scoreTable = pw.Table.fromTextArray(
      headers: headers,
      data: [rowQ, rowD, rowY, rowN, rowSucc],
      headerStyle: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
      cellStyle: pw.TextStyle(fontSize: 6),
      headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        for (int i = 1; i < headers.length; i++) i: pw.Alignment.center,
      },
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: {0: pw.FixedColumnWidth(25)},
    );

    final rankBox = pw.Container(
      width: 100,
      margin: pw.EdgeInsets.only(left: 5),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
      child: pw.Column(
        children: [
          pw.Container(
            color: PdfColors.red50,
            width: double.infinity,
            padding: pw.EdgeInsets.all(1),
            child: pw.Text(
              "PUAN",
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Padding(
            padding: pw.EdgeInsets.all(2),
            child: pw.Text(
              student.score.toStringAsFixed(2),
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red,
              ),
            ),
          ),
          pw.Divider(height: 1, thickness: 0.5),
          // Karnede derece/sıralama gösterilmez.
        ],
      ),
    );

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: scoreTable),
        rankBox,
      ],
    );
  }

  pw.Widget _buildPdfRankRow(String label, int rank, int total) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(vertical: 1, horizontal: 2),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text("$label:", style: pw.TextStyle(fontSize: 6)),
          pw.Text(
            "$rank / $total",
            style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfAnswerKeyCompact() {
    final validSubjects = subjects.toList();

    return pw.Container(
      padding: pw.EdgeInsets.all(2),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
      child: pw.Wrap(
        spacing: 5,
        runSpacing: 2,
        children: validSubjects.map((s) {
          final c = student.correctAnswers[s] ?? "";
          final st = student.answers[s] ?? "";
          if (c.isEmpty && st.isEmpty) return pw.Container(width: 0);

          return pw.Container(
            width: 120,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            ),
            padding: pw.EdgeInsets.all(2),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 30,
                  child: pw.Text(
                    s.substring(0, s.length > 3 ? 3 : s.length),
                    style: pw.TextStyle(
                      fontSize: 5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "C: $c",
                        style: pw.TextStyle(
                          fontSize: 5,
                          font: pw.Font.courier(),
                        ),
                      ),
                      pw.Text(
                        "Ö: $st",
                        style: pw.TextStyle(
                          fontSize: 5,
                          font: pw.Font.courier(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  pw.Widget _buildPdfTopicHeaderRow() {
    return pw.Table(
      columnWidths: {
        0: pw.FlexColumnWidth(5),
        1: pw.FixedColumnWidth(10),
        2: pw.FixedColumnWidth(10),
        3: pw.FixedColumnWidth(10),
        4: pw.FixedColumnWidth(10),
      },
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            pw.Padding(
              padding: pw.EdgeInsets.all(1),
              child: pw.Text(
                "KONU ADI",
                style: pw.TextStyle(
                  fontSize: 5, // Reduced to prevent wrap
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                "SS",
                style: pw.TextStyle(
                  fontSize: 5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                "D",
                style: pw.TextStyle(
                  fontSize: 5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                "Y",
                style: pw.TextStyle(
                  fontSize: 5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                "%",
                style: pw.TextStyle(
                  fontSize: 5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<pw.Widget> _buildAllTopicWidgets(
    List<String> colSubjects,
    String bookletKey,
  ) {
    final widgets = <pw.Widget>[];

    for (var subject in colSubjects) {
      final topics = outcomes[bookletKey]![subject]!;
      final correctAns = student.correctAnswers[subject] ?? "";
      final studentAns = student.answers[subject] ?? "";

      Map<String, _TopicStat> stats = {};
      int len = correctAns.length;
      if (topics.length < len) len = topics.length;

      for (int i = 0; i < len; i++) {
        String topic = topics[i];
        if (topic.isEmpty) topic = "Genel";
        stats.putIfAbsent(topic, () => _TopicStat());

        String c = correctAns[i];
        String s = (i < studentAns.length) ? studentAns[i] : " ";
        stats[topic]!.total++;
        if (s == c)
          stats[topic]!.correct++;
        else if (s == ' ' || s.isEmpty)
          stats[topic]!.empty++;
        else
          stats[topic]!.wrong++;
      }

      final dataRows = <pw.TableRow>[];
      stats.forEach((t, stat) {
        int success = (stat.total > 0)
            ? ((stat.correct / stat.total) * 100).round()
            : 0;
        dataRows.add(
          pw.TableRow(
            children: [
              pw.Padding(
                padding: pw.EdgeInsets.all(1),
                child: pw.Text(
                  t,
                  maxLines: 1,
                  overflow: pw.TextOverflow.span,
                  style: pw.TextStyle(fontSize: 6),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  stat.total.toString(),
                  style: pw.TextStyle(fontSize: 6),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  stat.correct.toString(),
                  style: pw.TextStyle(fontSize: 6),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  stat.wrong.toString(),
                  style: pw.TextStyle(fontSize: 6),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  success.toString(),
                  style: pw.TextStyle(fontSize: 6),
                ),
              ),
            ],
          ),
        );
      });

      widgets.add(
        pw.Container(
          margin: pw.EdgeInsets.only(bottom: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.orange300, width: 0.5),
          ),
          child: pw.Column(
            children: [
              pw.Container(
                width: double.infinity,
                padding: pw.EdgeInsets.symmetric(vertical: 1, horizontal: 2),
                decoration: pw.BoxDecoration(
                  color: PdfColors.orange100,
                  border: pw.Border(
                    bottom: pw.BorderSide(
                      width: 0.5,
                      color: PdfColors.orange300,
                    ),
                  ),
                ),
                child: pw.Text(
                  subject,
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Table(
                columnWidths: {
                  0: pw.FlexColumnWidth(5),
                  1: pw.FixedColumnWidth(10),
                  2: pw.FixedColumnWidth(10),
                  3: pw.FixedColumnWidth(10),
                  4: pw.FixedColumnWidth(10),
                },
                border: pw.TableBorder.all(color: PdfColors.grey, width: 0.5),
                children: dataRows,
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }
}

class _TopicStat {
  int total = 0;
  int correct = 0;
  int wrong = 0;
  int empty = 0;
}
