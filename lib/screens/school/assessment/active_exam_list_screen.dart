import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../services/assessment_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'trial_exam_form.dart';

class ActiveExamListScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const ActiveExamListScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<ActiveExamListScreen> createState() => _ActiveExamListScreenState();
}

class _ActiveExamListScreenState extends State<ActiveExamListScreen> {
  final AssessmentService _service = AssessmentService();

  TrialExam? _selectedExam;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<String> _activeGrades = [];
  bool _isLoadingGrades = true;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('tr_TR', null);
    _loadActiveGrades();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  Future<void> _loadActiveGrades() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .doc(widget.schoolTypeId)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (data['activeGrades'] != null) {
          if (mounted) {
            setState(() {
              _activeGrades = (data['activeGrades'] as List)
                  .map((e) => e.toString())
                  .toList();
              _isLoadingGrades = false;
            });
          }
        }
      }
    } catch (e) {
      print('Error loading active grades: $e');
      if (mounted) setState(() => _isLoadingGrades = false);
    }
  }

  void _onSelect(TrialExam exam) {
    setState(() {
      _selectedExam = exam;
    });
  }

  void _onSaveSuccess() {
    if (MediaQuery.of(context).size.width < 768) {
      Navigator.pop(context);
    } else {
      setState(() {
        _selectedExam = null;
      });
    }
  }

  Stream<List<TrialExam>> _getStream() {
    // Filter for Launched exams only and matching School Type grades
    return _service.getTrialExams(widget.institutionId).map((exams) {
      return exams.where((e) {
        // Must be launched (activated)
        if (!e.isLaunched) return false;

        // Must match active grades of this school type (if grades loaded)
        if (!_isLoadingGrades && _activeGrades.isNotEmpty) {
          return _activeGrades.contains(e.classLevel);
        }

        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;

        if (isMobile) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Uygulanan Sınavlar'),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            body: Column(
              children: [
                _buildLeftPanelHeader(),
                const SizedBox(height: 16),
                Expanded(child: _buildList(isMobile: true)),
              ],
            ),
          );
        } else {
          return Scaffold(
            appBar: AppBar(
              title: const Text(
                'Sınav Yönetimi',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
              elevation: 0,
              leading: const BackButton(color: Colors.white),
            ),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // List Pane
                Container(
                  width: 350,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border(
                      right: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildLeftPanelHeader(),
                      SizedBox(height: 8),
                      Expanded(child: _buildList(isMobile: false)),
                    ],
                  ),
                ),
                // Detail Pane
                Expanded(
                  child: Container(
                    color: Colors.grey[50],
                    child: _selectedExam != null
                        ? TrialExamForm(
                            key: ValueKey(_selectedExam!.id),
                            institutionId: widget.institutionId,
                            schoolTypeId: widget.schoolTypeId,
                            trialExam: _selectedExam,
                            onSuccess: _onSaveSuccess,
                            isExamExecution: true, // IMPORTANT: Execution Mode
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.assignment_turned_in,
                                  size: 64,
                                  color: Colors.grey[300],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'İşlem yapmak için listeden bir sınav seçin.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildLeftPanelHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.green.shade600,
            Colors.green.shade400,
          ], // Distinct Color
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Uygulanan Sınavlar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              StreamBuilder<List<TrialExam>>(
                stream: _getStream(),
                builder: (context, snapshot) {
                  final count = snapshot.hasData ? snapshot.data!.length : 0;
                  return Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          SizedBox(height: 12),
          TextField(
            controller: _searchController,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Sınav ara...',
              hintStyle: TextStyle(color: Colors.white70),
              prefixIcon: Icon(Icons.search, size: 20, color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList({required bool isMobile}) {
    return StreamBuilder<List<TrialExam>>(
      stream: _getStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SelectableText(
                'Hata: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        var exams = snapshot.data ?? [];
        if (_searchQuery.isNotEmpty) {
          exams = exams
              .where((e) => e.name.toLowerCase().contains(_searchQuery))
              .toList();
        }

        if (exams.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 48, color: Colors.grey[300]),
                SizedBox(height: 16),
                Text(
                  'Yayında olan sınav yok.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 16),
          itemCount: exams.length,
          itemBuilder: (context, index) {
            final exam = exams[index];
            final isSelected = !isMobile && _selectedExam?.id == exam.id;

            return Card(
              margin: EdgeInsets.only(bottom: 8),
              elevation: isSelected ? 2 : 1,
              color: isSelected ? Colors.green[50] : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isSelected
                    ? BorderSide(color: Colors.green, width: 1.5)
                    : BorderSide.none,
              ),
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.green : Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('dd', 'tr_TR').format(exam.date),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.green,
                        ),
                      ),
                      Text(
                        DateFormat('MMM', 'tr_TR').format(exam.date),
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected ? Colors.white70 : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                title: Text(
                  exam.name,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 4),
                    Text('${exam.classLevel} • ${exam.examTypeName}'),
                    SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 14,
                          color: Colors.grey,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Kitapçık: ${exam.bookletCount}',
                          style: TextStyle(fontSize: 12),
                        ),
                        Spacer(),
                        if (exam.isPublished)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'YAYINDA',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: Colors.green)
                    : Icon(Icons.chevron_right, color: Colors.grey[300]),
                onTap: () {
                  if (isMobile) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Scaffold(
                          appBar: AppBar(
                            title: Text(exam.name),
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                          body: TrialExamForm(
                            institutionId: widget.institutionId,
                            schoolTypeId: widget.schoolTypeId,
                            trialExam: exam,
                            onSuccess: () => Navigator.pop(context),
                            isExamExecution: true,
                          ),
                        ),
                      ),
                    );
                  } else {
                    _onSelect(exam);
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}
