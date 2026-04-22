import 'dart:convert';
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

class _ErrorBookletStudentListScreenState extends State<ErrorBookletStudentListScreen> {
  // Map key: Student Name (as unique id for now)
  // Map value: List of results (one for each exam in widget.exams)
  Map<String, List<Map<String, dynamic>?>> _aggregatedResults = {};
  bool _isLoading = true;
  final ErrorBookletGeneratorService _generatorService = ErrorBookletGeneratorService();

  @override
  void initState() {
    super.initState();
    _parseAggregatedResults();
  }

  void _parseAggregatedResults() {
    Map<String, List<Map<String, dynamic>?>> aggregated = {};

    for (int i = 0; i < widget.exams.length; i++) {
        final exam = widget.exams[i];
        if (exam.resultsJson != null && exam.resultsJson!.isNotEmpty) {
          try {
            final decoded = jsonDecode(exam.resultsJson!);
            if (decoded is List) {
              for (var res in decoded) {
                final studentRes = Map<String, dynamic>.from(res);
                final name = studentRes['studentName'] ?? studentRes['name'] ?? 'İsimsiz';
                
                if (!aggregated.containsKey(name)) {
                  // Initialize with nulls for all exams
                  aggregated[name] = List.generate(widget.exams.length, (index) => null);
                }
                // Assign result to the correct exam index
                aggregated[name]![i] = studentRes;
              }
            }
          } catch (e) {
            debugPrint('Error parsing results: $e');
          }
        }
    }

    setState(() {
      _aggregatedResults = aggregated;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final studentNames = _aggregatedResults.keys.toList();
    studentNames.sort();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          widget.exams.length == 1 
            ? 'Öğrenci Listesi' 
            : 'Karma Kitapçık: ${widget.exams.length} Sınav',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : studentNames.isEmpty
              ? Center(child: Text('Girilen sınav sonuçları bulunamadı.', style: GoogleFonts.inter(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: studentNames.length,
                  itemBuilder: (context, index) {
                    final name = studentNames[index];
                    final results = _aggregatedResults[name]!;
                    
                    // Count how many exams this student entered
                    final enterCount = results.where((r) => r != null).length;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.indigo.withOpacity(0.1))),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade50,
                          child: Text(name[0], style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                        subtitle: Text('$enterCount sınava katıldı', style: const TextStyle(fontSize: 12)),
                        trailing: ElevatedButton.icon(
                          onPressed: () {
                            // Filter out null results for the generator
                            // (Though the service expects parallel lists, we can send full lists and service skips nulls)
                            _generatorService.generateAndDownloadBooklet(
                              exams: widget.exams,
                              studentResults: results.map((r) => r ?? {}).toList(),
                            );
                          },
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: Text(widget.exams.length == 1 ? 'KİTAPÇIK' : 'KARMA BAS'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
