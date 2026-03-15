import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../models/guidance/development_report/development_report_model.dart';
import '../../../models/guidance/development_report/development_report_session_model.dart';
import 'development_evaluation_input_screen.dart';

class DevelopmentReportSessionDetailScreen extends StatefulWidget {
  final DevelopmentReportSession session;
  final String institutionId;

  const DevelopmentReportSessionDetailScreen({
    Key? key,
    required this.session,
    required this.institutionId,
  }) : super(key: key);

  @override
  _DevelopmentReportSessionDetailScreenState createState() =>
      _DevelopmentReportSessionDetailScreenState();
}

class _DevelopmentReportSessionDetailScreenState
    extends State<DevelopmentReportSessionDetailScreen>
    with SingleTickerProviderStateMixin {
  Map<String, String> _targetNames = {};
  Map<String, String> _reviewerNames = {};
  Map<String, Set<String>> _reviewerCompletedTargets = {};

  bool _isLoading = true;
  String? _selectedTargetId;
  DevelopmentReport? _selectedReport;
  bool _isLoadingReport = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load names
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      Map<String, String> names = {};
      for (var doc in usersSnapshot.docs) {
        names[doc.id] = doc.data()['fullName'] ?? 'İsimsiz';
      }
      for (var doc in studentsSnapshot.docs) {
        names[doc.id] = doc.data()['fullName'] ?? 'İsimsiz';
      }

      // We need to fetch evaluations where reportId IN (reports of this session).
      // Let's first fetch the reports for this session.
      final reportsSnapshot = await FirebaseFirestore.instance
          .collection('development_reports')
          .where('sessionId', isEqualTo: widget.session.id)
          .get();

      final reportIds = reportsSnapshot.docs.map((e) => e.id).toList();

      Map<String, Set<String>> completedTargets = {};
      for (var rId in widget.session.assignedReviewerIds) {
        completedTargets[rId] = {};
      }

      // Fetch evaluations for these reports
      if (reportIds.isNotEmpty) {
        for (var i = 0; i < reportIds.length; i += 10) {
          final chunk = reportIds.sublist(
            i,
            i + 10 > reportIds.length ? reportIds.length : i + 10,
          );
          final chunkEvals = await FirebaseFirestore.instance
              .collection('development_evaluations')
              .where('reportId', whereIn: chunk)
              .get();

          for (var doc in chunkEvals.docs) {
            final data = doc.data();
            final evalId = data['evaluatorId'] as String?;
            final rId = data['reportId'] as String?;

            if (evalId != null) {
              if (!completedTargets.containsKey(evalId)) {
                completedTargets[evalId] = {};
              }

              // We need to map reportId back to targetId
              final matchedReport = reportsSnapshot.docs.firstWhere(
                (r) => r.id == rId,
              );
              final targetId = matchedReport.data()['targetId'] as String?;
              if (targetId != null) {
                completedTargets[evalId]!.add(targetId);
              }
            }
          }
        }
      }

      setState(() {
        _targetNames = {
          for (var id in widget.session.targetUserIds)
            id: names[id] ?? 'Bilinmiyor',
        };
        _reviewerNames = {
          for (var id in widget.session.assignedReviewerIds)
            id: names[id] ?? 'Bilinmiyor',
        };
        _reviewerCompletedTargets = completedTargets;
        _isLoading = false;
      });
    } catch (e) {
      print("Error loading session details: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectTargetUser(String targetId) async {
    setState(() {
      _selectedTargetId = targetId;
      _isLoadingReport = true;
      _selectedReport = null;
    });

    try {
      // Find the report for this session & target match
      final snapshot = await FirebaseFirestore.instance
          .collection('development_reports')
          .where('sessionId', isEqualTo: widget.session.id)
          .where('targetId', isEqualTo: targetId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        setState(() {
          _selectedReport = DevelopmentReport.fromMap({
            ...data,
            'id': snapshot.docs.first.id,
          });
          _isLoadingReport = false;
        });
      } else {
        // Not found? Should have been created by createSession.
        setState(() => _isLoadingReport = false);
      }
    } catch (e) {
      print("Error loading target report: $e");
      setState(() => _isLoadingReport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text("Oturum Yükleniyor...")),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    bool isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session.title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo,
        elevation: 1,
        actions: [
          IconButton(
            tooltip: 'Değerlendirici İstatistikleri',
            icon: Icon(Icons.analytics),
            onPressed: _showStatisticsFullScreenDialog,
          ),
          SizedBox(width: 8),
        ],
      ),
      body: _buildTargetsTab(isWide),
    );
  }

  Widget _buildTargetsTab(bool isWide) {
    // Current user's completed evaluations
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final myCompletedTargets = currentUserId != null
        ? (_reviewerCompletedTargets[currentUserId] ?? {})
        : <String>{};

    Widget listWidget = ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: widget.session.targetUserIds.length,
      separatorBuilder: (context, index) => SizedBox(height: 8),
      itemBuilder: (context, index) {
        final targetId = widget.session.targetUserIds[index];
        final name = _targetNames[targetId] ?? 'Bilinmiyor';
        final isSelected = targetId == _selectedTargetId;
        final isCompletedByMe = myCompletedTargets.contains(targetId);

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (isWide) {
              _selectTargetUser(targetId);
            } else {
              _navigateMobileToReport(targetId, name);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            decoration: BoxDecoration(
              color: isSelected ? Colors.indigo.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? Colors.indigo.shade400
                    : Colors.grey.shade300,
                width: isSelected ? 1.5 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Colors.indigo.withOpacity(0.05),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isSelected
                      ? Colors.indigo.shade200
                      : Colors.indigo.shade100,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Colors.indigo.shade900,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCompletedByMe)
                  Icon(Icons.check_circle, color: Colors.green, size: 20)
                else
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 280,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(right: BorderSide(color: Colors.grey.shade300)),
              ),
              child: listWidget,
            ),
          ),
          Expanded(
            child: _selectedTargetId == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assignment,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        SizedBox(height: 16),
                        Text(
                          "Değerlendirme yapmak için sol taraftan bir kişi seçin.",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : _isLoadingReport
                ? Center(child: CircularProgressIndicator())
                : _selectedReport == null
                ? Center(
                    child: Text("Bu kişi için başlatılmış rapor bulunamadı."),
                  )
                : DevelopmentEvaluationInputScreen(
                    report: _selectedReport!,
                    evaluatorRole: 'teacher',
                    onEvaluationSaved: _loadData,
                  ),
          ),
        ],
      );
    } else {
      return listWidget;
    }
  }

  Future<void> _navigateMobileToReport(String targetId, String name) async {
    showDialog(
      context: context,
      builder: (c) => Center(child: CircularProgressIndicator()),
    );

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('development_reports')
          .where('sessionId', isEqualTo: widget.session.id)
          .where('targetId', isEqualTo: targetId)
          .limit(1)
          .get();

      if (!mounted) return;
      Navigator.pop(context); // close dialog

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final report = DevelopmentReport.fromMap({
          ...data,
          'id': snapshot.docs.first.id,
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DevelopmentEvaluationInputScreen(
              report: report,
              evaluatorRole: 'teacher',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Rapor bulunamadı.")));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Hata: $e")));
      }
    }
  }

  void _showStatisticsFullScreenDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) {
          final totalTargets = widget.session.targetUserIds.length;

          return Scaffold(
            appBar: AppBar(
              title: Text("Değerlendirici İstatistikleri"),
              backgroundColor: Colors.white,
              foregroundColor: Colors.indigo,
              elevation: 1,
              leading: IconButton(
                icon: Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  tooltip: "Raporu İndir (Excel/PDF)",
                  icon: Icon(Icons.download),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Eksik değerlendirmeler listesi indiriliyor...",
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(width: 8),
              ],
            ),
            body: Column(
              children: [
                // Overall Chart Section
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Builder(
                    builder: (context) {
                      int totalPossible =
                          totalTargets *
                          widget.session.assignedReviewerIds.length;
                      int totalCompleted = 0;
                      for (var set in _reviewerCompletedTargets.values) {
                        totalCompleted += set.length;
                      }
                      int totalMissing = totalPossible - totalCompleted;

                      if (totalPossible == 0) return SizedBox.shrink();

                      return Row(
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: PieChart(
                              PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 40,
                                sections: [
                                  PieChartSectionData(
                                    color: Colors.green.shade500,
                                    value: totalCompleted.toDouble(),
                                    title: '',
                                    radius: 12,
                                  ),
                                  PieChartSectionData(
                                    color: Colors.orange.shade300,
                                    value: totalMissing.toDouble(),
                                    title: '',
                                    radius: 12,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: 32),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Genel İlerleme Durumu",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo.shade900,
                                  ),
                                ),
                                SizedBox(height: 16),
                                Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade500,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "Tamamlanan: $totalCompleted",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade300,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      "Bekleyen: $totalMissing",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: widget.session.assignedReviewerIds.length,
                    itemBuilder: (context, index) {
                      final rId = widget.session.assignedReviewerIds[index];
                      final name = _reviewerNames[rId] ?? 'Bilinmiyor';
                      final completedSet = _reviewerCompletedTargets[rId] ?? {};
                      final completedCount = completedSet.length;
                      final double progress = totalTargets == 0
                          ? 0
                          : completedCount / totalTargets;

                      final missingTargets = widget.session.targetUserIds
                          .where((id) => !completedSet.contains(id))
                          .toList();

                      return Card(
                        margin: EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: progress == 1.0
                                          ? Colors.green.withOpacity(0.1)
                                          : Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      "$completedCount / $totalTargets",
                                      style: TextStyle(
                                        color: progress == 1.0
                                            ? Colors.green.shade700
                                            : Colors.orange.shade800,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.grey.shade200,
                                  color: progress == 1.0
                                      ? Colors.green
                                      : Colors.indigo,
                                  minHeight: 10,
                                ),
                              ),
                              if (progress < 1.0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12.0),
                                  child: InkWell(
                                    onTap: () {
                                      // Show missing targets dialog
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: Text(
                                            "$name - Eksik Listesi",
                                            style: TextStyle(fontSize: 18),
                                          ),
                                          content: Container(
                                            width: 300,
                                            height: 300,
                                            child: ListView.separated(
                                              itemCount: missingTargets.length,
                                              separatorBuilder: (c, i) =>
                                                  Divider(height: 1),
                                              itemBuilder: (context, i) {
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 8.0,
                                                      ),
                                                  child: Text(
                                                    _targetNames[missingTargets[i]] ??
                                                        "Bilinmiyor",
                                                    style: TextStyle(
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx),
                                              child: Text("Kapat"),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.orange.shade200,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.info_outline,
                                            color: Colors.orange.shade800,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            "Tamamlanmayan ${missingTargets.length} Değerlendirme Var",
                                            style: TextStyle(
                                              color: Colors.orange.shade900,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(top: 12.0),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 18,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        "Tüm değerlendirmeler tamamlandı",
                                        style: TextStyle(
                                          color: Colors.green.shade800,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
