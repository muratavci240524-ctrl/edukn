import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../services/error_booklet_generator_service.dart';

class ErrorBookletStudentListScreen extends StatefulWidget {
  final List<TrialExam> exams;

  const ErrorBookletStudentListScreen({Key? key, required this.exams}) : super(key: key);

  @override
  State<ErrorBookletStudentListScreen> createState() => _ErrorBookletStudentListScreenState();
}

class _StudentInfo {
  final String name;
  final String branch;
  final String level;
  final List<Map<String, dynamic>?> results;
  bool isSelected = false;

  _StudentInfo({
    required this.name,
    required this.branch,
    required this.level,
    required this.results,
    this.isSelected = false,
  });
}

class _ErrorBookletStudentListScreenState extends State<ErrorBookletStudentListScreen> {
  List<_StudentInfo> _allStudents = [];
  List<_StudentInfo> _filteredStudents = [];
  
  bool _isLoading = true;
  bool _isGeneratingBulk = false;
  final ErrorBookletGeneratorService _generatorService = ErrorBookletGeneratorService();

  // Progress State for Premium Loading Overlay
  bool _showProgress = false;
  int _progressCurrent = 0;
  int _progressTotal = 0;
  String _progressStudentName = '';

  // Filters
  String _searchQuery = '';
  Set<String> _selectedLevels = {};
  Set<String> _selectedBranches = {};

  List<String> _availableLevels = [];
  List<String> _availableBranches = [];

  @override
  void initState() {
    super.initState();
    _parseAggregatedResults();
  }

  void _parseAggregatedResults() {
    Map<String, _StudentInfo> aggregated = {};

    for (int i = 0; i < widget.exams.length; i++) {
        final exam = widget.exams[i];
        if (exam.resultsJson != null && exam.resultsJson!.isNotEmpty) {
          try {
            final decoded = jsonDecode(exam.resultsJson!);
            if (decoded is List) {
              for (var res in decoded) {
                final studentRes = Map<String, dynamic>.from(res);
                final name = (studentRes['studentName'] ?? studentRes['name'] ?? 'İsimsiz').toString().trim().toUpperCase();
                final branch = (studentRes['branch'] ?? studentRes['className'] ?? studentRes['sube'] ?? 'Bilinmeyen').toString();
                final level = (studentRes['classLevel'] ?? studentRes['level'] ?? studentRes['sinif'] ?? '').toString();
                
                if (!aggregated.containsKey(name)) {
                  aggregated[name] = _StudentInfo(
                    name: name,
                    branch: branch,
                    level: level,
                    results: List.generate(widget.exams.length, (index) => null),
                  );
                }
                
                // Fix potential backend missing keys by standardizing
                studentRes['studentName'] = name;
                studentRes['branch'] = branch;
                studentRes['booklet'] = (studentRes['booklet'] ?? studentRes['kitapcik'] ?? studentRes['Kitapçık'] ?? studentRes['bookletType'] ?? 'A').toString().toUpperCase(); // guarantee booklet
                
                aggregated[name]!.results[i] = studentRes;
              }
            }
          } catch (e) {
            debugPrint('Error parsing results: $e');
          }
        }
    }

    final list = aggregated.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));

    setState(() {
      _allStudents = list;
      _filteredStudents = list;
      _availableLevels = list.map((e) => e.level).where((e) => e.isNotEmpty).toSet().toList()..sort();
      _availableBranches = list.map((e) => e.branch).where((e) => e.isNotEmpty && e != 'Bilinmeyen').toSet().toList()..sort();
      _isLoading = false;
    });
  }

  void _applyFilters() {
    setState(() {
      _filteredStudents = _allStudents.where((student) {
        final matchesSearch = student.name.toLowerCase().contains(_searchQuery.toLowerCase());
        final matchesLevel = _selectedLevels.isEmpty || _selectedLevels.contains(student.level);
        final matchesBranch = _selectedBranches.isEmpty || _selectedBranches.contains(student.branch);
        return matchesSearch && matchesLevel && matchesBranch;
      }).toList();
    });
  }

  void _toggleSelectAll(bool? val) {
    setState(() {
      final target = val ?? false;
      for (var student in _filteredStudents) {
        student.isSelected = target;
      }
    });
  }

  void _showCriteriaBottomSheet({
    required Function(bool prioritizeCritical, int? maxQuestions, bool fillFromPool, bool individualPDFs) onGenerate,
  }) {
    bool prioritizeCritical = true;
    bool hasMaxLimit = false;
    bool fillFromPool = false;
    bool individualPDFs = false;
    final textController = TextEditingController(text: '20');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return AnimatedPadding(
              padding: MediaQuery.of(context).viewInsets + const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              duration: const Duration(milliseconds: 100),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.tune_rounded, color: Colors.indigo.shade600, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Kitapçık Oluşturma Kriterleri',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.picture_as_pdf_rounded, color: Colors.indigo.shade600, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Oluşturma Modu',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setSheetState(() => individualPDFs = false),
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !individualPDFs ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: !individualPDFs
                                    ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
                                    : [],
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.library_books_rounded, size: 16, color: !individualPDFs ? Colors.indigo.shade700 : Colors.grey.shade600),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Tek Birleşik PDF',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: !individualPDFs ? FontWeight.bold : FontWeight.normal,
                                        color: !individualPDFs ? Colors.indigo.shade900 : Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setSheetState(() => individualPDFs = true),
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: individualPDFs ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: individualPDFs
                                    ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
                                    : [],
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.person_pin_rounded, size: 16, color: individualPDFs ? Colors.indigo.shade700 : Colors.grey.shade600),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Kişiye Özel PDF',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: individualPDFs ? FontWeight.bold : FontWeight.normal,
                                        color: individualPDFs ? Colors.indigo.shade900 : Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kritik Soruları Önceliklendir',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Yıldızladığınız kritik sorular öğrencinin yanlışları arasındaysa önce onları seçer.',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: prioritizeCritical,
                          activeColor: Colors.indigo.shade600,
                          onChanged: (val) {
                            setSheetState(() => prioritizeCritical = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Maksimum Soru Limiti Koy',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Kitapçıkta bulunacak maksimum soru sayısını sınırlandırır.',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: hasMaxLimit,
                              activeColor: Colors.indigo.shade600,
                              onChanged: (val) {
                                setSheetState(() {
                                  hasMaxLimit = val;
                                  if (!val) fillFromPool = false;
                                });
                              },
                            ),
                          ],
                        ),
                        if (hasMaxLimit) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                'Maksimum Soru Sayısı:',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 80,
                                height: 40,
                                child: TextField(
                                  controller: textController,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                  decoration: InputDecoration(
                                    contentPadding: EdgeInsets.zero,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: Colors.indigo.shade600),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Soru Sayısını Sabitle',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Öğrencinin yanlışları eksikse, havuzdaki diğer zeki sorulardan (zordan kolaya) tamamlayarak standart kitapçık boyutu sunar.',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: fillFromPool,
                                activeColor: Colors.indigo.shade600,
                                onChanged: (val) {
                                  setSheetState(() => fillFromPool = val);
                                },
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(context);
                        final int? maxQ = hasMaxLimit ? int.tryParse(textController.text) : null;
                        onGenerate(prioritizeCritical, maxQ, fillFromPool, individualPDFs);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.indigo.shade600,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'KİTAPÇIĞI HAZIRLA',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _generateBulk() async {
    final selectedStudents = _allStudents.where((s) => s.isSelected).toList();
    if (selectedStudents.isEmpty) return;

    _showCriteriaBottomSheet(
      onGenerate: (prioritizeCritical, maxQuestions, fillFromPool, individualPDFs) async {
        setState(() {
          _showProgress = true;
          _progressCurrent = 0;
          _progressTotal = selectedStudents.length;
          _progressStudentName = 'Hazırlanıyor...';
        });

        try {
          final bulkData = selectedStudents.map((s) => s.results.map((r) => r ?? {}).toList()).toList();
          await _generatorService.generateBulkBooklets(
            exams: widget.exams,
            bulkStudentResults: bulkData,
            prioritizeCritical: prioritizeCritical,
            maxQuestions: maxQuestions,
            fillFromPool: fillFromPool,
            individualPDFs: individualPDFs,
            onProgress: (current, total, studentName) {
              if (mounted) {
                setState(() {
                  _progressCurrent = current;
                  _progressTotal = total;
                  _progressStudentName = studentName;
                });
              }
            },
          );
        } catch (e) {
          debugPrint('Error generating bulk booklet: $e');
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
        } finally {
          if (mounted) setState(() => _showProgress = false);
        }
      },
    );
  }

  void _showFilterSheet(String title, List<String> items, Set<String> currentSelected, Function(Set<String>) onApply) {
    Set<String> tempSelected = Set.from(currentSelected);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      backgroundColor: Colors.white,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
                    const SizedBox(height: 16),
                    Text('$title Filtresi', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: items.map((item) {
                        final isSelected = tempSelected.contains(item);
                        return FilterChip(
                          label: Text(item),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.indigo.shade900,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          backgroundColor: Colors.grey.shade100,
                          selectedColor: Colors.indigo.shade500,
                          checkmarkColor: Colors.white,
                          selected: isSelected,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300)),
                          onSelected: (val) {
                            setSheetState(() {
                              if (val) tempSelected.add(item);
                              else tempSelected.remove(item);
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          onApply(tempSelected);
                          Navigator.pop(context);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Uygula', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _allStudents.where((s) => s.isSelected).length;
    final isAllSelected = _filteredStudents.isNotEmpty && _filteredStudents.every((s) => s.isSelected);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            title: Text(
              widget.exams.length == 1 
                ? 'Öğrenci Listesi' 
                : 'Karma Kitapçık: ${widget.exams.length} Sınav',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            elevation: 0,
            backgroundColor: const Color(0xFFF8FAFC),
            foregroundColor: Colors.indigo.shade900,
            centerTitle: true,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildPremiumHeader(),
                    const SizedBox(height: 8),
                    _buildActionRow(isAllSelected),
                    Expanded(
                      child: _filteredStudents.isEmpty
                          ? Center(child: Text('Arama kriterlerine uygun öğrenci bulunamadı.', style: GoogleFonts.inter(color: Colors.grey)))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                              itemCount: _filteredStudents.length,
                              itemBuilder: (context, index) {
                                return _buildStudentCard(_filteredStudents[index]);
                              },
                            ),
                    ),
                  ],
                ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
          floatingActionButton: selectedCount > 0 ? _buildBulkActionBar(selectedCount) : null,
        ),
        if (_showProgress) _buildProgressOverlay(),
      ],
    );
  }

  Widget _buildProgressOverlay() {
    final percent = _progressTotal > 0 ? (_progressCurrent / _progressTotal) : 0.0;
    final displayPercent = (percent * 100).toInt();

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Glassmorphic background blur
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                color: Colors.indigo.shade900.withOpacity(0.4),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Circular Progress with percentage inside!
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CircularProgressIndicator(
                            value: percent,
                            strokeWidth: 6.0, // Clean, sleek stroke width for the large circle
                            backgroundColor: Colors.indigo.shade50,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo.shade600),
                          ),
                        ),
                        Text(
                          '$displayPercent%',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 26, // Large, highly premium typography
                            color: Colors.indigo.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Hata Kitapçığı Hazırlanıyor',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.indigo.shade900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _progressStudentName,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.grey.shade800,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_progressCurrent / $_progressTotal Öğrenci',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  // Linear progress bar at the very bottom of the card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: percent,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo.shade400),
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

  Widget _buildPremiumHeader() {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Öğrenci Ara...',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 22),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.indigo)),
            ),
            onChanged: (val) {
              _searchQuery = val;
              _applyFilters();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_availableLevels.isNotEmpty)
                Expanded(
                  child: _buildFilterPill(
                    title: 'Sınıf Seviyesi',
                    selectedCount: _selectedLevels.length,
                    onTap: () => _showFilterSheet('Sınıf', _availableLevels, _selectedLevels, (val) {
                      setState(() => _selectedLevels = val);
                      _applyFilters();
                    }),
                  ),
                ),
              if (_availableLevels.isNotEmpty && _availableBranches.isNotEmpty) const SizedBox(width: 12),
              if (_availableBranches.isNotEmpty)
                Expanded(
                  child: _buildFilterPill(
                    title: 'Şube',
                    selectedCount: _selectedBranches.length,
                    onTap: () => _showFilterSheet('Şube', _availableBranches, _selectedBranches, (val) {
                      setState(() => _selectedBranches = val);
                      _applyFilters();
                    }),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill({required String title, required int selectedCount, required VoidCallback onTap}) {
    final bool isActive = selectedCount > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isActive ? Colors.indigo.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? Colors.indigo.shade300 : Colors.grey.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                isActive ? '$title ($selectedCount)' : title,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: isActive ? Colors.indigo.shade700 : Colors.grey.shade700,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: isActive ? Colors.indigo : Colors.grey.shade500, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(bool isAllSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_filteredStudents.length} Öğrenci',
            style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (_filteredStudents.isNotEmpty)
            InkWell(
              onTap: () => _toggleSelectAll(!isAllSelected),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Text('Tümünü Seç', style: GoogleFonts.inter(color: Colors.indigo.shade700, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isAllSelected ? Colors.indigo : Colors.transparent,
                        border: Border.all(color: Colors.indigo, width: 2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: isAllSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(_StudentInfo student) {
    final enterCount = student.results.where((r) => r != null).length;
    final isSelected = student.isSelected;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? Colors.indigo.withOpacity(0.03) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSelected ? Colors.indigo.shade300 : Colors.grey.withOpacity(0.15), width: isSelected ? 1.5 : 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() { student.isSelected = !student.isSelected; });
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.indigo.shade50,
                  child: Text(
                    student.name.isNotEmpty ? student.name.substring(0, 1) : '?',
                    style: TextStyle(color: Colors.indigo.shade700, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black87),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (student.level.isNotEmpty || student.branch != 'Bilinmeyen')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                              child: Text('${student.level} - ${student.branch}', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                            ),
                          if (student.level.isNotEmpty || student.branch != 'Bilinmeyen')
                            const SizedBox(width: 8),
                          Text('$enterCount Sınav', style: GoogleFonts.inter(fontSize: 12, color: Colors.indigo.shade400, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),

                // Single Generate Button
                IconButton(
                  onPressed: () {
                    _showCriteriaBottomSheet(
                      onGenerate: (prioritizeCritical, maxQuestions, fillFromPool, individualPDFs) async {
                        setState(() {
                          _showProgress = true;
                          _progressCurrent = 0;
                          _progressTotal = 1;
                          _progressStudentName = student.name;
                        });
                        try {
                          await _generatorService.generateBulkBooklets(
                            exams: widget.exams,
                            bulkStudentResults: [student.results.map((r) => r ?? {}).toList()],
                            prioritizeCritical: prioritizeCritical,
                            maxQuestions: maxQuestions,
                            fillFromPool: fillFromPool,
                            individualPDFs: individualPDFs,
                            onProgress: (current, total, studentName) {
                              if (mounted) {
                                setState(() {
                                  _progressCurrent = current;
                                  _progressTotal = total;
                                  _progressStudentName = studentName;
                                });
                              }
                            },
                          );
                        } catch (e) {
                          debugPrint('Error: $e');
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                        } finally {
                          if (mounted) setState(() => _showProgress = false);
                        }
                      },
                    );
                  },
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.auto_awesome, color: Colors.indigo.shade600, size: 20),
                  ),
                  tooltip: 'Bu öğrenci için oluştur',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBulkActionBar(int selectedCount) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.indigo.shade600, Colors.indigo.shade900]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.indigo.shade200, blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Toplu İşlem', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
              Text('$selectedCount Öğrenci Seçili', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          _isGeneratingBulk
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : FilledButton.icon(
                onPressed: _generateBulk,
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('ÜRET', style: TextStyle(fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.indigo.shade900,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
        ],
      ),
    );
  }
}
