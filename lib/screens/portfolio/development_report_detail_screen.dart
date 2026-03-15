import 'package:flutter/material.dart';
import '../guidance/reports/development_report_pdf_helper.dart';
import '../../models/guidance/development_report/development_report_model.dart';

class DevelopmentReportDetailScreen extends StatelessWidget {
  final DevelopmentReport report;
  final String studentName;

  const DevelopmentReportDetailScreen({
    Key? key,
    required this.report,
    required this.studentName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('${studentName} - Gelişim Raporu'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Color(0xFF1E293B),
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
        iconTheme: IconThemeData(color: Color(0xFF1E293B)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: Icon(Icons.picture_as_pdf, color: Colors.blue),
              onPressed: () {
                DevelopmentReportPdfHelper.generateAndPrint(
                  report,
                  studentName,
                );
              },
              tooltip: "PDF İndir",
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: DevelopmentReportContent(
          report: report,
          studentName: studentName,
        ),
      ),
    );
  }
}

class DevelopmentReportContent extends StatelessWidget {
  final DevelopmentReport report;
  final String studentName;
  final bool showHeader;

  const DevelopmentReportContent({
    Key? key,
    required this.report,
    required this.studentName,
    this.showHeader = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(showHeader ? 16 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[_buildHeader(), SizedBox(height: 24)],
          _buildRiskAlert(),
          if (report.analysis['riskFactors'] != null &&
              (report.analysis['riskFactors'] as List).isNotEmpty)
            SizedBox(height: 24),
          _buildSummaryChart(context),
          SizedBox(height: 24),
          _buildAIAnalysis(),
          SizedBox(height: 24),
          _buildCategoryComments(context),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.indigo,
            child: Icon(Icons.analytics, color: Colors.white),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${report.term} Dönemi Raporu",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.indigo.shade900,
                  ),
                ),
                Text(
                  "Genel Gelişim Endeksi: ${report.growthIndex ?? '-'}",
                  style: TextStyle(
                    color: Colors.indigo.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (report.riskScore != null && report.riskScore! > 30)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "Yüksek Risk",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRiskAlert() {
    final risks = report.analysis['riskFactors'] as List?;
    if (risks == null || risks.isEmpty) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text(
                "Risk Erken Uyarı Sistemi",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          ...risks.map(
            (risk) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 6, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      risk.toString(),
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChart(BuildContext context) {
    final scores = report.categoryScores;
    if (scores.isEmpty) return SizedBox.shrink();

    final categories = scores.keys.toList();
    // Sort by name or score? Let's sort by score descending for better impact
    categories.sort((a, b) => (scores[b] ?? 0).compareTo(scores[a] ?? 0));

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.04),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
        border: Border.all(color: Colors.indigo.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.bar_chart_rounded,
                  color: Colors.indigo,
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Text(
                "Gelişim Alanları Özeti",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          SizedBox(height: 24),
          ...categories.map((cat) {
            final score = scores[cat] ?? 0;
            final percentage = score / 5.0;
            final color = score < 2.5
                ? Colors.red
                : (score < 3.5 ? Colors.orange : Colors.green);

            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        cat,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF475569),
                        ),
                      ),
                      Text(
                        score.toStringAsFixed(1),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Stack(
                    children: [
                      Container(
                        height: 8,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      AnimatedContainer(
                        duration: Duration(milliseconds: 500),
                        height: 8,
                        width:
                            MediaQuery.of(context).size.width *
                            0.75 *
                            percentage,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color.withOpacity(0.6), color],
                          ),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: color.withOpacity(0.2),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAIAnalysis() {
    final analysis = report.analysis;
    final summary = analysis['summary'];
    if (summary == null) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.purple.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.auto_awesome, color: Colors.purple, size: 20),
              ),
              SizedBox(width: 12),
              Text(
                "Akıllı Analiz & Yorum",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            summary.toString(),
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF334155),
            ),
          ),
          if (analysis['prevention'] != null) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tips_and_updates_outlined,
                        color: Colors.orange,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Text(
                        "Öneriler",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    analysis['prevention'].toString(),
                    style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryComments(BuildContext context) {
    final comments =
        report.analysis['categoryComments'] as Map<String, dynamic>? ?? {};
    if (comments.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            children: [
              Icon(Icons.forum_outlined, color: Colors.indigo, size: 20),
              SizedBox(width: 12),
              Text(
                "Değerlendirme Notları & Yorumlar",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        ...comments.entries.map((entry) {
          final categoryName = entry.key;
          final categoryComments = entry.value as List?;
          if (categoryComments == null || categoryComments.isEmpty)
            return SizedBox.shrink();

          return Container(
            margin: EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4.0, bottom: 10),
                  child: Text(
                    categoryName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.indigo.shade700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                ...categoryComments.map((commentStr) {
                  final parts = commentStr.toString().split(': ');
                  final author = parts.length > 1 ? parts[0] : "Bilinmeyen";
                  final content = parts.length > 1
                      ? parts.sublist(1).join(': ')
                      : parts[0];

                  return Container(
                    margin: EdgeInsets.only(bottom: 10),
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(20),
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                      border: Border.all(color: Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.person,
                                size: 12,
                                color: Colors.indigo,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              author,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          content,
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF1E293B),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}
