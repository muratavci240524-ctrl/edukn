import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../services/guidance_service.dart';
import 'study_program_printing_helper.dart';

class StudyProgramDetailScreen extends StatefulWidget {
  final String institutionId;
  final Map<String, dynamic> program;

  const StudyProgramDetailScreen({
    Key? key,
    required this.institutionId,
    required this.program,
  }) : super(key: key);

  @override
  _StudyProgramDetailScreenState createState() =>
      _StudyProgramDetailScreenState();
}

class _StudyProgramDetailScreenState extends State<StudyProgramDetailScreen> {
  late Map<String, List<int>> _executionStatus;
  final _guidanceService = GuidanceService();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initializeStatus();
  }

  void _initializeStatus() {
    if (widget.program['executionStatus'] != null) {
      _executionStatus = Map<String, List<int>>.from(
        (widget.program['executionStatus'] as Map).map(
          (k, v) => MapEntry(k, List<int>.from(v)),
        ),
      );
    } else {
      _executionStatus = {};
      final schedule = widget.program['schedule'] as Map<String, dynamic>;
      schedule.forEach((day, lessons) {
        _executionStatus[day] = List.filled((lessons as List).length, 0);
      });
    }
  }

  Future<void> _toggleStatus(String day, int index) async {
    setState(() {
      int current = _executionStatus[day]?[index] ?? 0;
      // Cycle: 0(White) -> 1(Green) -> 2(Yellow) -> 3(Red) -> 0
      int next = (current + 1) % 4;
      _executionStatus[day]![index] = next;
    });

    await _saveStatus();
  }

  Future<void> _saveStatus() async {
    setState(() => _isSaving = true);
    try {
      await _guidanceService.updateStudyProgramStatus(
        widget.institutionId,
        widget.program['id'],
        _executionStatus,
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 1:
        return Colors.green.shade100; // Yapıldı
      case 2:
        return Colors.orange.shade100; // Eksik
      case 3:
        return Colors.red.shade100; // Yapılmadı
      default:
        return Colors.white; // Atandı
    }
  }

  Color _getStatusBorderColor(int status) {
    switch (status) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.red;
      default:
        return Colors.grey.shade300;
    }
  }

  IconData? _getStatusIcon(int status) {
    switch (status) {
      case 1:
        return Icons.check_circle;
      case 2:
        return Icons.warning_rounded;
      case 3:
        return Icons.cancel;
      default:
        return null;
    }
  }

  Map<String, int> _calculateStats() {
    int total = 0;
    int done = 0;
    int incomplete = 0;
    int missed = 0;

    _executionStatus.values.forEach((list) {
      total += list.length;
      done += list.where((s) => s == 1).length;
      incomplete += list.where((s) => s == 2).length;
      missed += list.where((s) => s == 3).length;
    });

    return {
      'total': total,
      'done': done,
      'incomplete': incomplete,
      'missed': missed,
      'percentage': total > 0
          ? ((done + (incomplete * 0.5)) / total * 100).round()
          : 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final schedule = widget.program['schedule'] as Map<String, dynamic>;
    final stats = _calculateStats();
    final studentName = widget.program['studentName'] ?? 'Öğrenci';
    final examName = widget.program['examName'] ?? 'Program';

    // Sort days
    final days = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(studentName),
        actions: [
          IconButton(
            icon: Icon(Icons.print),
            onPressed: () {
              StudyProgramPrintingHelper.generateBulkPdf(context, [
                widget.program,
              ]);
            },
          ),
          if (_isSaving)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Header Stats
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.indigo.shade50,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        examName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text("Program Takip Özeti"),
                      // Show Date if available
                      if (widget.program['startDate'] != null ||
                          widget.program['createdAt'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            _formatDateRange(widget.program),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _buildStatBadge("Tamamlanan", stats['done']!, Colors.green),
                SizedBox(width: 8),
                _buildStatBadge("Eksik", stats['incomplete']!, Colors.orange),
                SizedBox(width: 8),
                _buildStatBadge("Yapılmadı", stats['missed']!, Colors.red),
                SizedBox(width: 12),
                Container(
                  // Percentage
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "%${stats['percentage']}",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: days.length,
              itemBuilder: (context, index) {
                final day = days[index];
                if (!schedule.containsKey(day)) return SizedBox.shrink();

                final lessons = List<String>.from(schedule[day] ?? []);
                if (lessons.isEmpty) return SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        day,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent:
                            300, // Allows more columns on wide screens
                        childAspectRatio:
                            2.5, // Taller ratio = shorter box height
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: lessons.length,
                      itemBuilder: (context, lessonIndex) {
                        final lesson = lessons[lessonIndex];
                        final status = _executionStatus[day]?[lessonIndex] ?? 0;
                        final color = _getStatusColor(status);
                        final borderColor = _getStatusBorderColor(status);
                        final icon = _getStatusIcon(status);

                        return InkWell(
                          onTap: () => _toggleStatus(day, lessonIndex),
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 200),
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: color,
                              border: Border.all(
                                color: borderColor,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 1,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                if (icon != null) ...[
                                  Icon(icon, size: 18, color: borderColor),
                                  SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    lesson.replaceAll('\n', ' '),
                                    maxLines: 3, // Allow a bit more text
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11, // Slightly smaller font
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    Divider(height: 24),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  String _formatDateRange(Map<String, dynamic> data) {
    // Helper to format date
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final start = parse(data['startDate']) ?? parse(data['createdAt']);
    final end = parse(data['endDate']);
    // Generic format: DD.MM.YYYY
    String fmt(DateTime d) => "${d.day}.${d.month}.${d.year}";

    if (start != null) {
      return "${fmt(start)} ${end != null ? '- ' + fmt(end) : ''}";
    }
    return "";
  }
}
