import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../services/assessment_service.dart';
import '../../../../widgets/edukn_logo.dart';

class AssessmentActionPlanSelectionDialog extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final Function(List<String> examIds, Map<String, double> thresholds, double globalThreshold, String? classLevel) onConfirm;

  const AssessmentActionPlanSelectionDialog({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.onConfirm,
  }) : super(key: key);

  @override
  _AssessmentActionPlanSelectionDialogState createState() => _AssessmentActionPlanSelectionDialogState();
}

class _AssessmentActionPlanSelectionDialogState extends State<AssessmentActionPlanSelectionDialog> {
  final AssessmentService _service = AssessmentService();
  int _currentStep = 0; // 0: Exams, 1: Thresholds
  List<TrialExam> _allExams = [];
  List<TrialExam> _filteredExams = [];
  Set<String> _selectedExamIds = {};
  String? _selectedClassLevel;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  Map<String, double> _subjectThresholds = {};
  List<String> _availableSubjects = [];
  double _globalThreshold = 70.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _filterExams();
      });
    });
  }

  Future<void> _loadData() async {
    final examsStream = _service.getTrialExams(widget.institutionId);
    final exams = await examsStream.first;
    setState(() {
      _allExams = exams;
      _filterExams();
      _isLoading = false;
    });
  }

  void _filterExams() {
    _filteredExams = _allExams.where((exam) {
      final matchesClass = _selectedClassLevel == null || exam.classLevel == _selectedClassLevel;
      final matchesSearch = exam.name.toLowerCase().contains(_searchQuery);
      return matchesClass && matchesSearch;
    }).toList();
    _filteredExams.sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _updateAvailableSubjects() async {
    if (_selectedExamIds.isEmpty) {
      setState(() => _availableSubjects = []);
      return;
    }
    
    Set<String> subjects = {};
    for (var id in _selectedExamIds) {
      final exam = _allExams.firstWhere((e) => e.id == id);
      final examType = await _service.getExamType(exam.examTypeId);
      if (examType != null) {
        subjects.addAll(examType.subjects.map((s) => s.branchName));
      }
    }
    
    setState(() {
      _availableSubjects = subjects.toList()..sort();
      for (var s in _availableSubjects) {
        _subjectThresholds.putIfAbsent(s, () => _globalThreshold);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFD),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: _isLoading 
        ? const Center(child: EduKnLoader(size: 60))
        : Column(
            children: [
              _buildHeader(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _currentStep == 0 ? _buildExamsStep() : _buildThresholdsStep(),
                ),
              ),
              _buildFooter(),
            ],
          ),
    );
  }

  Widget _buildHeader() {
    String title = _currentStep == 0 ? 'Sınav Seçimi' : 'Başarı Hedefleri';
    String subtitle = _currentStep == 0 ? 'Analiz edilecek sınavları seçin.' : 'Branş bazlı başarı hedeflerinizi belirleyin.';
    
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isSmall = constraints.maxWidth < 450;
        return Container(
          padding: EdgeInsets.fromLTRB(24, 24, 24, isSmall ? 12 : 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Icon(_currentStep == 0 ? Icons.checklist_rtl : Icons.track_changes, color: Colors.indigo, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(fontSize: isSmall ? 16 : 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(subtitle, style: TextStyle(fontSize: isSmall ? 11 : 13, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20)),
                ],
              ),
              const SizedBox(height: 16),
              _buildStepIndicator(isSmall),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStepIndicator(bool isSmall) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _stepCircle(0, 'Sınavlar', isSmall),
          Expanded(child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 8), color: _currentStep > 0 ? Colors.indigo : Colors.grey.shade200)),
          _stepCircle(1, 'Hedefler', isSmall),
        ],
      ),
    );
  }

  Widget _stepCircle(int index, String label, bool isSmall) {
    bool isActive = _currentStep == index;
    bool isDone = _currentStep > index;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(
            color: isDone ? Colors.green : (isActive ? Colors.indigo : Colors.grey.shade200),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isDone 
              ? const Icon(Icons.check, size: 12, color: Colors.white)
              : Text('${index + 1}', style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ),
        if (!isSmall || isActive) ...[
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: isActive ? Colors.indigo : Colors.grey, fontSize: 11, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
        ],
      ],
    );
  }

  Widget _buildExamsStep() {
    final levels = _allExams.map((e) => e.classLevel).toSet().toList()..sort();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.indigo.shade50)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedClassLevel,
                      isExpanded: true,
                      hint: const Text('Tüm Sınıflar', style: TextStyle(fontSize: 13)),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Tüm Sınıflar', style: TextStyle(fontSize: 13))),
                        ...levels.map((l) => DropdownMenuItem(value: l, child: Text(l.toString().contains('Sınıf') ? l : '$l. Sınıf', style: const TextStyle(fontSize: 13)))),
                      ],
                      onChanged: (val) => setState(() { _selectedClassLevel = val; _filterExams(); }),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.indigo.shade50)),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Sınav ara...',
                      hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                      border: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                      icon: Icon(Icons.search, size: 18, color: Colors.indigo),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _filteredExams.isEmpty
            ? const Center(child: Text('Sınav bulunamadı'))
            : LayoutBuilder(
                builder: (context, gridConstraints) {
                  int crossAxisCount = gridConstraints.maxWidth > 600 ? 2 : 1;
                  double aspectRatio = gridConstraints.maxWidth > 600 ? 3.5 : 4.5;
                  
                  return GridView.builder(
                    padding: const EdgeInsets.all(24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: aspectRatio,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _filteredExams.length,
                    itemBuilder: (context, index) {
                      final exam = _filteredExams[index];
                      final isSelected = _selectedExamIds.contains(exam.id);
                      return InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) _selectedExamIds.remove(exam.id);
                            else _selectedExamIds.add(exam.id);
                          });
                          _updateAvailableSubjects();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.indigo.shade50 : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isSelected ? Colors.indigo.shade200 : Colors.grey.shade100),
                            boxShadow: isSelected ? null : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(exam.name, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text('${DateFormat('dd.MM.yyyy').format(exam.date)} • ${exam.classLevel.toString().contains('Sınıf') ? exam.classLevel : '${exam.classLevel}. Sınıf'}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                  ],
                                ),
                              ),
                              if (isSelected) const Icon(Icons.check_circle, color: Colors.indigo, size: 18),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildThresholdsStep() {
    if (_selectedExamIds.isEmpty) return const Center(child: Text('Lütfen önce sınav seçin.'));
    
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 600 ? 2 : 1);
        double aspectRatio = constraints.maxWidth > 600 ? 2.5 : 3.0;
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGlobalThresholdCard(constraints.maxWidth),
              const SizedBox(height: 32),
              const Text('Branş Bazlı Hedefler', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text('Seçili sınavlar üzerinden her branş için özel başarı eşiği belirleyin.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 20),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: aspectRatio,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _availableSubjects.length,
                itemBuilder: (context, index) => _buildThresholdCard(_availableSubjects[index]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGlobalThresholdCard(double maxWidth) {
    bool isSmall = maxWidth < 600;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.indigo.shade800, Colors.indigo.shade600]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: isSmall 
        ? Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.speed, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Genel Başarı Eşiği', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  Text('%${_globalThreshold.round()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                ],
              ),
              const SizedBox(height: 16),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(activeTrackColor: Colors.white, inactiveTrackColor: Colors.white24, thumbColor: Colors.white),
                child: Slider(
                  value: _globalThreshold, min: 0, max: 100, divisions: 20,
                  onChanged: (v) {
                    setState(() {
                      _globalThreshold = v;
                      for (var s in _availableSubjects) _subjectThresholds[s] = v;
                    });
                  },
                ),
              ),
            ],
          )
        : Row(
            children: [
              const Icon(Icons.speed, color: Colors.white, size: 32),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Genel Başarı Eşiği', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('Tüm branşları aynı anda güncelle.', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              SizedBox(
                width: 200,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(activeTrackColor: Colors.white, inactiveTrackColor: Colors.white24, thumbColor: Colors.white),
                  child: Slider(
                    value: _globalThreshold, min: 0, max: 100, divisions: 20,
                    onChanged: (v) {
                      setState(() {
                        _globalThreshold = v;
                        for (var s in _availableSubjects) _subjectThresholds[s] = v;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('%${_globalThreshold.round()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
    );
  }

  Widget _buildThresholdCard(String subject) {
    double value = _subjectThresholds[subject] ?? 70.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(subject, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('%${value.round()}', style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          Slider(
            value: value, min: 0, max: 100, divisions: 20,
            activeColor: Colors.indigo, inactiveColor: Colors.indigo.withOpacity(0.1),
            onChanged: (v) => setState(() => _subjectThresholds[subject] = v),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isSmall = constraints.maxWidth < 450;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEEEEE)))),
          child: Row(
            children: [
              if (_currentStep > 0)
                OutlinedButton(
                  onPressed: () => setState(() => _currentStep--),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: isSmall ? 16 : 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Geri'),
                ),
              const Spacer(),
              if (!isSmall) ...[
                Text('${_selectedExamIds.length} sınav seçildi', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(width: 16),
              ],
              ElevatedButton(
                onPressed: _selectedExamIds.isEmpty ? null : () {
                  if (_currentStep == 0) {
                    setState(() => _currentStep = 1);
                  } else {
                    // Inherit the exact class level from the exam's official metadata
                    String? finalClassLevel = _selectedClassLevel;
                    if (finalClassLevel == null && _selectedExamIds.isNotEmpty) {
                      final firstExamId = _selectedExamIds.first;
                      final exam = _allExams.firstWhere((e) => e.id == firstExamId);
                      finalClassLevel = exam.classLevel; // This is the official level from DB
                    }
                    widget.onConfirm(_selectedExamIds.toList(), _subjectThresholds, _globalThreshold, finalClassLevel);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade900, foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: isSmall ? 24 : 40, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(_currentStep == 0 ? 'Devam Et' : 'Analizi Başlat', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
        );
      },
    );
  }
}
