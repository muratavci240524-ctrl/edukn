import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class GradeEntryDialog extends StatefulWidget {
  final String institutionId;
  final String classId;
  final String lessonId;
  final String lessonName;
  final String? examId;
  final Map<String, dynamic>? initialData;

  const GradeEntryDialog({
    super.key,
    required this.institutionId,
    required this.classId,
    required this.lessonId,
    required this.lessonName,
    this.examId,
    this.initialData,
  });

  @override
  State<GradeEntryDialog> createState() => _GradeEntryDialogState();
}

class _GradeEntryDialogState extends State<GradeEntryDialog> {
  final TextEditingController _examNameController = TextEditingController();
  final TextEditingController _instructionController = TextEditingController();
  final TextEditingController _bulkGradeController = TextEditingController();

  DateTime _examDate = DateTime.now();

  bool _isSaving = false;

  // Students & Grades
  List<Map<String, dynamic>> _students = [];
  final Map<String, TextEditingController> _gradeControllers = {};
  bool _isLoadingStudents = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _examNameController.text = widget.initialData!['examName'] ?? '';
      final ts = widget.initialData!['date'] as Timestamp?;
      if (ts != null) _examDate = ts.toDate();

      _instructionController.text = widget.initialData!['instruction'] ?? '';
    } else {
      _examNameController.text = "${widget.lessonName} Sınavı";
    }
    _loadStudents();
  }

  @override
  void dispose() {
    _bulkGradeController.dispose();
    _examNameController.dispose();
    _instructionController.dispose();
    for (var c in _gradeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadStudents() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('classId', isEqualTo: widget.classId)
          .get();

      setState(() {
        _students = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();

        // Client-side sorting by Name
        _students.sort((a, b) {
          final nameA = (a['name'] ?? a['fullName'] ?? '')
              .toString()
              .toLowerCase();
          final nameB = (b['name'] ?? b['fullName'] ?? '')
              .toString()
              .toLowerCase();
          return nameA.compareTo(nameB);
        });

        // Initialize controllers for each student
        for (var s in _students) {
          _gradeControllers[s['id']] = TextEditingController();
        }

        // Populate existing grades if editing
        if (widget.initialData != null) {
          final grades =
              widget.initialData!['grades'] as Map<String, dynamic>? ?? {};
          for (var s in _students) {
            final sid = s['id'];
            if (grades.containsKey(sid)) {
              _gradeControllers[sid]?.text = grades[sid].toString();
            }
          }
        }

        _isLoadingStudents = false;
      });
    } catch (e) {
      debugPrint('Error loading students: $e');
      if (mounted) setState(() => _isLoadingStudents = false);
    }
  }

  void _applyToAll(String value) {
    for (var controller in _gradeControllers.values) {
      controller.text = value;
    }
  }

  Future<void> _saveGrades() async {
    // Validate grades format
    for (var controller in _gradeControllers.values) {
      final text = controller.text.trim().toUpperCase();
      if (text.isNotEmpty) {
        if (text == 'G' || text == 'K') continue;

        final val = int.tryParse(text);
        if (val == null || val < 0 || val > 100) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Notlar 0-100 arasında veya G/K olmalıdır.'),
            ),
          );
          return;
        }
      }
    }

    setState(() {
      _isSaving = true;
    });

    try {
      Map<String, dynamic> studentGrades = {};
      for (var s in _students) {
        final text = _gradeControllers[s['id']]!.text.trim().toUpperCase();
        if (text.isNotEmpty) {
          final val = int.tryParse(text);
          if (val != null) {
            studentGrades[s['id']] = val;
          } else {
            studentGrades[s['id']] = text; // G or K
          }
        }
      }

      final docRef = widget.examId != null
          ? FirebaseFirestore.instance
                .collection('class_exams')
                .doc(widget.examId)
          : FirebaseFirestore.instance.collection('class_exams').doc();

      if (widget.examId != null) {
        await docRef.update({
          'grades': studentGrades,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final data = {
          'institutionId': widget.institutionId,
          'classId': widget.classId,
          'lessonId': widget.lessonId,
          'lessonName': widget.lessonName,
          'examName': _examNameController.text.trim(),
          'date': Timestamp.fromDate(_examDate),
          'hasInstruction': false,
          'attachments': [],
          'grades': studentGrades,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        };
        await docRef.set(data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notlar başarıyla kaydedildi.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Save Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB), // Very light grey background
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Not Girişi',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              onPressed: _isSaving ? null : _saveGrades,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.check_circle_outline,
                      color: Colors.blue.shade700,
                    ),
              label: Text(
                _isSaving ? 'KAYDEDİLİYOR...' : 'KAYDET',
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoadingStudents
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Info Header Section (Like the image)
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        '${widget.lessonName} - ${widget.initialData?['examName'] ?? 'Sınav'}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'DERS SINAVI', // Subtitle
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Date Chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Sınav Tarihi: ${DateFormat('dd.MM.yyyy').format(_examDate)}',
                              style: TextStyle(
                                color: Colors.red.shade800,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, color: Color(0xFFEEEEEE)),

                // List Header & Bulk Actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      Text(
                        'ÖĞRENCİ LİSTESİ (${_students.length})',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),

                      // Bulk Input
                      Text(
                        'TÜMÜNE UYGULA:',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 50,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        alignment: Alignment.center,
                        child: TextField(
                          controller: _bulkGradeController,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          decoration: const InputDecoration(
                            hoverColor: Colors.transparent,
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                            hintText: '...',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          if (_bulkGradeController.text.isNotEmpty) {
                            _applyToAll(_bulkGradeController.text);
                            FocusScope.of(context).unfocus(); // Close keyboard
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Icon(
                            Icons.check,
                            size: 20,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Students List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    itemCount: _students.length,
                    itemBuilder: (context, index) {
                      final student = _students[index];
                      final controller = _gradeControllers[student['id']]!;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.shade200,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            // Avatar Placeholder or Icon
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.blue.shade50,
                              child: Text(
                                (student['fullName'] ?? student['name'] ?? 'A')
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Name
                            Expanded(
                              child: Text(
                                student['fullName'] ??
                                    student['name'] ??
                                    'İsimsiz',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),

                            // Grade Input Field (Stylish)
                            Container(
                              width: 70,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFF3F4F6,
                                ), // Soft grey fill
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: TextField(
                                controller: controller,
                                maxLength: 3,
                                textAlign: TextAlign.center,
                                cursorColor: Colors.blue,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                                decoration: const InputDecoration(
                                  hoverColor: Colors.transparent,
                                  counterText: '',
                                  border: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                  hintText: '-',
                                  hintStyle: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Bottom Safe Area
                SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
              ],
            ),
    );
  }
}
