import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../services/assessment_service.dart';
import 'trial_exam_form.dart';

class TrialExamListScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const TrialExamListScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  State<TrialExamListScreen> createState() => _TrialExamListScreenState();
}

class _TrialExamListScreenState extends State<TrialExamListScreen> {
  final AssessmentService _service = AssessmentService();

  TrialExam? _selectedExam;
  bool _isCreatingNew = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('tr_TR', null);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  void _onCreateNew() {
    setState(() {
      _selectedExam = null;
      _isCreatingNew = true;
    });
  }

  void _onSelect(TrialExam exam) {
    setState(() {
      _selectedExam = exam;
      _isCreatingNew = false;
    });
  }

  void _onSaveSuccess() {
    if (MediaQuery.of(context).size.width < 768) {
      Navigator.pop(context);
    } else {
      setState(() {
        _selectedExam = null;
        _isCreatingNew = false;
      });
    }
  }

  Stream<List<TrialExam>> _getStream() {
    return _service.getTrialExams(widget.institutionId);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;

        if (isMobile) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Deneme Sınavları'),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            body: Column(
              children: [
                _buildLeftPanelHeader(isMobile: true),
                const SizedBox(height: 16),
                Expanded(child: _buildList(isMobile: true)),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => Scaffold(
                      appBar: AppBar(
                        title: const Text('Yeni Deneme Sınavı'),
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      body: TrialExamForm(
                        institutionId: widget.institutionId,
                        schoolTypeId: widget.schoolTypeId,
                        onSuccess: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                );
              },
              child: Icon(Icons.add),
            ),
          );
        } else {
          return Scaffold(
            appBar: AppBar(
              title: const Text(
                'Deneme Sınavı Yönetimi',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.indigo,
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
                      _buildLeftPanelHeader(isMobile: false),
                      SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: ElevatedButton.icon(
                          onPressed: _onCreateNew,
                          icon: Icon(Icons.add),
                          label: Text('Yeni Deneme Sınavı'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size(double.infinity, 45),
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Expanded(child: _buildList(isMobile: false)),
                    ],
                  ),
                ),
                // Detail Pane
                Expanded(
                  child: Container(
                    color: Colors.grey[50],
                    child: (_selectedExam != null || _isCreatingNew)
                        ? TrialExamForm(
                            key: ValueKey(_selectedExam?.id ?? 'new'),
                            institutionId: widget.institutionId,
                            schoolTypeId: widget.schoolTypeId,
                            trialExam: _selectedExam,
                            onSuccess: _onSaveSuccess,
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.touch_app,
                                  size: 64,
                                  color: Colors.grey[300],
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'İşlem yapmak için listeden seçim yapın.',
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

  Widget _buildLeftPanelHeader({required bool isMobile}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.indigo.shade600, Colors.indigo.shade400],
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
              Icon(Icons.edit_note, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Sınavlar',
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
          SizedBox(height: 12),
          // Filter Chips (Placeholder)
          Row(children: [_buildFilterChip('Tümü', true, () {})]),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.indigo : Colors.white,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
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
                  'Kayıtlı sınav yok.',
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
              color: isSelected ? Colors.indigo[50] : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isSelected
                    ? BorderSide(color: Colors.indigo, width: 1.5)
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
                    color: isSelected ? Colors.indigo : Colors.indigo[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('dd', 'tr_TR').format(exam.date),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.indigo,
                        ),
                      ),
                      Text(
                        DateFormat('MMM', 'tr_TR').format(exam.date),
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected ? Colors.white70 : Colors.indigo,
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
                        SizedBox(width: 12),
                        Icon(Icons.settings, size: 14, color: Colors.grey),
                        SizedBox(width: 4),
                        Text(
                          exam.applicationType.name,
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    if (exam.isLaunched) ...[
                      SizedBox(height: 6),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.rocket_launch,
                              size: 12,
                              color: Colors.green.shade700,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'SINAV OLARAK AÇILDI',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: Colors.indigo)
                    : Icon(Icons.chevron_right, color: Colors.grey[300]),
                onTap: () {
                  if (isMobile) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Scaffold(
                          appBar: AppBar(
                            title: Text(exam.name),
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                          body: TrialExamForm(
                            institutionId: widget.institutionId,
                            schoolTypeId: widget.schoolTypeId,
                            trialExam: exam,
                            onSuccess: () => Navigator.pop(context),
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
