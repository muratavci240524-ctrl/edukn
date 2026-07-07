import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../services/portfolio_report_service.dart';
import '../../../widgets/edukn_logo.dart';
import '../../../services/crypto_service.dart';

class MentorStudentReportDetailScreen extends StatefulWidget {
  final Map<String, dynamic> student;
  final String institutionId;
  final String schoolTypeId;

  const MentorStudentReportDetailScreen({
    Key? key,
    required this.student,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<MentorStudentReportDetailScreen> createState() =>
      _MentorStudentReportDetailScreenState();
}

class _MentorStudentReportDetailScreenState
    extends State<MentorStudentReportDetailScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _portfolioData = {};
  Map<String, dynamic>? _studentDocData;

  // Selection range for program analysis
  String _selectedRange = '1_month'; // '1_week', '1_month', 'all'

  // Edit Comment Controller
  final _commentController = TextEditingController();
  bool _isSavingComment = false;

  @override
  void initState() {
    super.initState();
    _loadAllReportDetails();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadAllReportDetails() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch Portfolio Data (Exams, study programs, interviews)
      _portfolioData = await PortfolioReportService().fetchFullPortfolioData(
        studentId: widget.student['id'],
        institutionId: widget.institutionId,
        termId: 'current',
      );

      // 2. Fetch latest student document for goals & evaluation
      final studentDoc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.student['id'])
          .get();

      if (studentDoc.exists) {
        _studentDocData = studentDoc.data();
        _commentController.text = _studentDocData?['mentorReportEvaluation'] ?? '';
      }

    } catch (e) {
      debugPrint("Error loading student report details: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveComment() async {
    setState(() => _isSavingComment = true);
    try {
      await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.student['id'])
          .update({
        'mentorReportEvaluation': _commentController.text.trim(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yorum ve aksiyon planı kaydedildi.', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          backgroundColor: Colors.teal.shade600,
        ),
      );
    } catch (e) {
      debugPrint("Error saving evaluation: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: $e', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSavingComment = false);
    }
  }

  // --- Calculations for Section A: Goal Status ---
  Map<String, dynamic> _calculateGoalStatus() {
    final goals = _studentDocData?['mentorGoals'] as Map<String, dynamic>?;
    final targetPoints = (goals?['points'] as num?)?.toDouble() ?? 0.0;
    final targetNets = (goals?['nets'] as num?)?.toDouble() ?? 0.0;
    final targetSchool = goals?['targetSchool'] as String? ?? 'Hedef Belirlenmemiş';

    final trialExams = _portfolioData['trialExams'] as List? ?? [];
    double avgPoints = 0.0;
    double avgNets = 0.0;

    if (trialExams.isNotEmpty) {
      // Last 3 trial exams (sorted descending by date)
      final lastThree = trialExams.take(3).toList();
      final sumPoints = lastThree.map((e) => (e['score'] as num?)?.toDouble() ?? 0.0).reduce((a, b) => a + b);
      final sumNets = lastThree.map((e) => (e['net'] as num?)?.toDouble() ?? 0.0).reduce((a, b) => a + b);
      avgPoints = sumPoints / lastThree.length;
      avgNets = sumNets / lastThree.length;
    }

    final double remainingPoints = targetPoints > 0.0 ? (targetPoints - avgPoints) : 0.0;
    final double remainingNets = targetNets > 0.0 ? (targetNets - avgNets) : 0.0;

    return {
      'targetPoints': targetPoints,
      'targetNets': targetNets,
      'targetSchool': targetSchool,
      'avgPoints': avgPoints,
      'avgNets': avgNets,
      'remainingPoints': remainingPoints,
      'remainingNets': remainingNets,
    };
  }



  Future<Map<String, dynamic>> _fetchDetailedStudyStats() async {
    final ninetyDaysAgo = DateTime.now().subtract(const Duration(days: 90));
    final query = await FirebaseFirestore.instance
        .collection('institutions')
        .doc(widget.institutionId)
        .collection('study_programs')
        .where('studentId', isEqualTo: widget.student['id'])
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(ninetyDaysAgo))
        .get();

    int totalTasks = 0;
    int completedTasks = 0;

    Map<String, Map<String, int>> lessonStats = {}; // LessonName -> {'total': X, 'completed': Y}

    // Filter by selected range
    final now = DateTime.now();
    DateTime threshold = now.subtract(const Duration(days: 30));
    if (_selectedRange == '1_week') {
      threshold = now.subtract(const Duration(days: 7));
    } else if (_selectedRange == 'all') {
      threshold = now.subtract(const Duration(days: 90));
    }

    for (var doc in query.docs) {
      final data = doc.data();
      final Timestamp? created = data['createdAt'] as Timestamp?;
      if (created == null) continue;
      if (created.toDate().isBefore(threshold)) continue;

      if (data['executionStatus'] != null) {
        final statusMap = data['executionStatus'] as Map<String, dynamic>;
        statusMap.forEach((lesson, val) {
          if (val is List) {
            final list = List<int>.from(val);
            
            // Increment overall stats
            totalTasks += list.length;
            final completed = list.where((s) => s == 1).length;
            completedTasks += completed;

            // Increment lesson specific stats
            final normalizedLesson = _normalizeLessonName(lesson);
            lessonStats.putIfAbsent(normalizedLesson, () => {'total': 0, 'completed': 0});
            lessonStats[normalizedLesson]!['total'] = lessonStats[normalizedLesson]!['total']! + list.length;
            lessonStats[normalizedLesson]!['completed'] = lessonStats[normalizedLesson]!['completed']! + completed;
          }
        });
      }
    }

    return {
      'total': totalTasks,
      'completed': completedTasks,
      'lessonStats': lessonStats,
    };
  }

  String _normalizeLessonName(String name) {
    final s = name.toLowerCase().trim();
    if (s.contains('matematik') || s.contains('mat')) return 'Matematik';
    if (s.contains('turkce') || s.contains('türkçe') || s.contains('trk')) return 'Türkçe';
    if (s.contains('fen') || s.contains('fizik') || s.contains('kimya') || s.contains('biyoloji')) return 'Fen Bilimleri';
    if (s.contains('sosyal') || s.contains('tarih') || s.contains('coğrafya') || s.contains('inkılap') || s.contains('inkilap')) return 'İnkılap Tarihi';
    if (s.contains('ingilizce') || s.contains('ing') || s.contains('english')) return 'İngilizce';
    if (s.contains('din') || s.contains('dkab') || s.contains('ahlak')) return 'Din Kültürü';
    return name;
  }

  // --- PDF Export Logic ---
  Future<void> _exportToPDF(Map<String, dynamic> goalData, Map<String, dynamic> studyStats) async {
    final pdf = pw.Document();

    final trialExams = _portfolioData['trialExams'] as List? ?? [];
    final recentExams = trialExams.take(5).toList();

    final interviews = _portfolioData['interviews'] as List? ?? [];
    final recentInterviews = interviews.take(3).toList();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'EDUKN GELISIM VE TAKIP RAPORU',
                        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Rapor Tarihi: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        widget.student['fullName'].toString().toUpperCase(),
                        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                      ),
                      pw.Text(
                        'Sınıf: ${widget.student['className'] ?? 'Sınıfsız'}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Divider(color: PdfColors.grey300, thickness: 1.5),
              pw.SizedBox(height: 16),

              // SECTION A: Hedef Durumu
              pw.Text('A. Hedef Durumu & Mevcut Seviye', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Hedeflenen Okul/Program: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text(goalData['targetSchool'].toString(), style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Hedef Puan / Net: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text('${goalData['targetPoints']} Puan / ${goalData['targetNets']} Net', style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Son 3 Deneme Ortalaması: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text('${goalData['avgPoints'].toStringAsFixed(2)} Puan / ${goalData['avgNets'].toStringAsFixed(2)} Net', style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Divider(color: PdfColors.grey200),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Kalan Mesafe: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.amber800)),
                        pw.Text(
                          goalData['remainingPoints'] > 0.0
                              ? 'Hedefe ulaşmak için ${goalData['remainingPoints'].toStringAsFixed(2)} puana daha ihtiyaç var.'
                              : 'Tebrikler! Hedef başarıyla aşıldı.',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: goalData['remainingPoints'] > 0.0 ? PdfColors.amber : PdfColors.green),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // SECTION B: Çalışma Programı Analizi
              pw.Text('B. Çalışma Programı Gerçekleşme Analizi', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
              pw.SizedBox(height: 8),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Program Tamamlama Oranı: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          '%${studyStats['total'] > 0 ? ((studyStats['completed'] / studyStats['total']) * 100).round() : 0} Başarı',
                          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                        ),
                        pw.Text('Toplam Atanan: ${studyStats['total']} Görev • Tamamlanan: ${studyStats['completed']} Görev', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: (studyStats['lessonStats'] as Map<String, Map<String, int>>).entries.map((e) {
                        final total = e.value['total']!;
                        final comp = e.value['completed']!;
                        final rate = total > 0 ? ((comp / total) * 100).round() : 0;
                        return pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 4),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(e.key, style: const pw.TextStyle(fontSize: 9)),
                              pw.Text('%$rate ($comp/$total)', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // SECTION C: Deneme Trendi
              pw.Text('C. Deneme Sınavları Trend Raporu', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Sınav Adı', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Tarih', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Net', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Puan', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Başarı %', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                    ],
                  ),
                  ...recentExams.map((e) {
                    final dateStr = e['date'] != null ? DateFormat('dd.MM.yyyy').format(e['date'] as DateTime) : '-';
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(e['examName'] ?? 'Deneme Sınavı', style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(dateStr, style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${e['net']}', style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${e['score']}', style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('%${(e['success'] as double).round()}', style: const pw.TextStyle(fontSize: 9))),
                      ],
                    );
                  }).toList(),
                ],
              ),
              pw.SizedBox(height: 20),

              // SECTION D: Mentör Yorumları & Aksiyon Planı
              pw.Text('D. Mentör Yorumu ve Aksiyon Planı', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey50,
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Text(
                  _commentController.text.trim().isNotEmpty
                      ? _commentController.text.trim()
                      : 'Henüz bir sonuç değerlendirmesi ve aksiyon planı girilmemiş.',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),

              pw.Spacer(),

              // Sign-off
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Mentör Öğretmen', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.SizedBox(height: 24),
                      pw.Text('İmza', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Kurum Yöneticisi', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.SizedBox(height: 24),
                      pw.Text('İmza / Mühür', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${widget.student['fullName']}_gelisim_raporu.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F4F6),
        body: Center(child: EduKnLoader(size: 80.0)),
      );
    }

    final goalData = _calculateGoalStatus();

    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchDetailedStudyStats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFFF3F4F6),
            body: Center(child: EduKnLoader(size: 80.0)),
          );
        }

        final studyStats = snapshot.data!;
        final double overallRate = studyStats['total'] > 0
            ? (studyStats['completed'] / studyStats['total'] * 100)
            : 0.0;

        return Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
          appBar: AppBar(
            title: Text(
              'Gelişim Rapor Detayı',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
            ),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_rounded),
                tooltip: 'PDF Raporu Oluştur',
                onPressed: () => _exportToPDF(goalData, studyStats),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Student Banner Card
                _buildStudentHeaderCard(),
                const SizedBox(height: 24),

                // Grid layout for Section A (Goal Status) & Section B (Study Program Stats)
                LayoutBuilder(builder: (context, constraints) {
                  final cols = constraints.maxWidth > 900 ? 2 : 1;
                  if (cols == 2) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildSectionA(goalData)),
                        const SizedBox(width: 20),
                        Expanded(child: _buildSectionB(overallRate, studyStats)),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _buildSectionA(goalData),
                        const SizedBox(height: 20),
                        _buildSectionB(overallRate, studyStats),
                      ],
                    );
                  }
                }),
                const SizedBox(height: 24),

                // Section C: Deneme Trendi
                _buildSectionC(),
                const SizedBox(height: 24),

                // Section D: Mentör Yorumları & Aksiyon Planı
                _buildSectionD(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudentHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.indigo.shade900,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withOpacity(0.15),
            child: Text(
              widget.student['fullName'].toString().substring(0, 1).toUpperCase(),
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.student['fullName'],
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sınıf/Şube: ${widget.student['className'] ?? 'Sınıfsız'} • Öğrenci No: ${widget.student['studentNo'] ?? '-'}',
                  style: GoogleFonts.inter(color: Colors.indigo.shade100, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionA(Map<String, dynamic> goalData) {
    final double progressPercent = goalData['targetPoints'] > 0
        ? (goalData['avgPoints'] / goalData['targetPoints']).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.track_changes_rounded, color: Colors.amber, size: 24),
                const SizedBox(width: 10),
                Text(
                  'A. Hedef Durumu (Neredeyiz, Ne Kaldı?)',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo.shade900),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Hedef Okul/Program', goalData['targetSchool'].toString()),
            _buildDetailRow('Hedeflenen Puan / Net', '${goalData['targetPoints']} Puan / ${goalData['targetNets']} Net'),
            _buildDetailRow('Mevcut Seviye (Son 3 Deneme Ort.)', '${goalData['avgPoints'].toStringAsFixed(2)} Puan / ${goalData['avgNets'].toStringAsFixed(2)} Net'),
            const Divider(height: 24),

            // Horizontal visual progress bar
            Text(
              'Puan Hedefi İlerleme Durumu',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progressPercent,
                      minHeight: 12,
                      backgroundColor: Colors.grey.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(progressPercent >= 0.8 ? Colors.green : (progressPercent >= 0.5 ? Colors.orange : Colors.red)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '%${(progressPercent * 100).round()}',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo.shade900),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Remaining message
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: goalData['remainingPoints'] > 0.0 ? Colors.amber.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                goalData['remainingPoints'] > 0.0
                    ? 'Hedefe ulaşmak için ${goalData['remainingPoints'].toStringAsFixed(2)} puana daha ihtiyaç var.'
                    : 'Tebrikler! Öğrenci puan hedefine ulaştı.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: goalData['remainingPoints'] > 0.0 ? Colors.amber.shade900 : Colors.green.shade900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionB(double overallRate, Map<String, dynamic> studyStats) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.assignment_turned_in_rounded, color: Colors.indigo, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        'B. Çalışma Programı Analizi',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo.shade900),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                DropdownButton<String>(
                  value: _selectedRange,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.indigo.shade900, fontWeight: FontWeight.bold),
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: '1_week', child: Text('Son 1 Hafta')),
                    DropdownMenuItem(value: '1_month', child: Text('Son 1 Ay')),
                    DropdownMenuItem(value: 'all', child: Text('Tüm Dönem')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedRange = val;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        value: overallRate / 100,
                        strokeWidth: 10,
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(overallRate >= 80 ? Colors.green : (overallRate >= 50 ? Colors.orange : Colors.red)),
                      ),
                    ),
                    Text(
                      '%${overallRate.round()}',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Görev Uyum Yüzdesi',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Toplam Atanan: ${studyStats['total']} Görev\nTamamlanan: ${studyStats['completed']} Görev',
                        style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Ders Bazlı Uyum Dağılımları',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...(studyStats['lessonStats'] as Map<String, Map<String, int>>).entries.map((e) {
              final total = e.value['total']!;
              final comp = e.value['completed']!;
              final double lessonRate = total > 0 ? (comp / total) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(e.key, style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade800, fontWeight: FontWeight.w500)),
                        Text('%${(lessonRate * 100).round()} ($comp/$total)', style: GoogleFonts.inter(fontSize: 11, color: Colors.indigo.shade900, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: lessonRate,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo.shade400),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionC() {
    final trialExams = _portfolioData['trialExams'] as List? ?? [];
    final recentExams = trialExams.take(5).toList();

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.show_chart_rounded, color: Colors.purple, size: 24),
                const SizedBox(width: 10),
                Text(
                  'C. Deneme Sınavı Trendi',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo.shade900),
                ),
              ],
            ),
            const SizedBox(height: 16),
            recentExams.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'Henüz uygulanmış deneme sınavı kaydı bulunamadı.',
                        style: GoogleFonts.inter(color: Colors.grey),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
                      columns: [
                        DataColumn(label: Text('Sınav Adı', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('Tarih', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('Net Skoru', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('Toplam Puan', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('Başarı Oranı', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                      rows: recentExams.map((e) {
                        final dateStr = e['date'] != null ? DateFormat('dd.MM.yyyy').format(e['date'] as DateTime) : '-';
                        return DataRow(cells: [
                          DataCell(Text(e['examName'] ?? 'Deneme Sınavı', style: GoogleFonts.inter(fontSize: 12))),
                          DataCell(Text(dateStr, style: GoogleFonts.inter(fontSize: 12))),
                          DataCell(Text('${e['net']}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade700))),
                          DataCell(Text('${e['score']}', style: GoogleFonts.inter(fontSize: 12))),
                          DataCell(Text('%${(e['success'] as double).round()}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo))),
                        ]);
                      }).toList(),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionD() {
    final interviews = _portfolioData['interviews'] as List? ?? [];
    final recentInterviews = interviews.take(3).toList();

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.rate_review_rounded, color: Colors.teal, size: 24),
                const SizedBox(width: 10),
                Text(
                  'D. Mentör Yorumları ve Aksiyon Planı',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo.shade900),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Guidance logs summary
            Text(
              'Son Görüşme Logları Özeti',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 8),
            recentInterviews.isEmpty
                ? Text(
                    'Son 30 günde mentör görüşme logu girilmemiş.',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.red.shade400),
                  )
                : Column(
                    children: recentInterviews.map((i) {
                      final timestamp = i['date'] as Timestamp?;
                      final dateStr = timestamp != null ? DateFormat('dd.MM.yyyy').format(timestamp.toDate()) : '-';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.arrow_right_rounded, color: Colors.teal, size: 18),
                            Expanded(
                              child: Text(
                                '$dateStr - ${i['title'] ?? 'Rehberlik Görüşmesi'}: ${CryptoService.decrypt(i['notes']?.toString(), institutionId: widget.institutionId) ?? ''}',
                                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade700),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
            const Divider(height: 24),

            // Outcome Editor
            Text(
              'Sonuç Değerlendirmesi ve Önümüzdeki Ayın Aksiyon Planı',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _commentController,
              maxLines: 5,
              style: GoogleFonts.inter(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ahmet bu ay çalışma programına yüksek oranda uyum sağladı. Ancak denemelerde süre sorunu yaşadığı için önümüzdeki ay paragraf ve yeni nesil matematik sorularında kronometreli çözümlere ağırlık vereceğiz...',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 150,
              height: 38,
              child: ElevatedButton.icon(
                onPressed: _isSavingComment ? null : _saveComment,
                icon: _isSavingComment 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check, color: Colors.white, size: 16),
                label: Text(
                  _isSavingComment ? 'Kaydediliyor...' : 'Yorumu Kaydet',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade600,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
          ),
        ],
      ),
    );
  }
}
