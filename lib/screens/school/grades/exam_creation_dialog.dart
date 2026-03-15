import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

class ExamCreationDialog extends StatefulWidget {
  final String institutionId;
  final String classId;
  final String lessonId;
  final String lessonName;
  final Map<String, dynamic>?
  examToEdit; // If editing an existing exam definition

  const ExamCreationDialog({
    super.key,
    required this.institutionId,
    required this.classId,
    required this.lessonId,
    required this.lessonName,
    this.examToEdit,
  });

  @override
  State<ExamCreationDialog> createState() => _ExamCreationDialogState();
}

class _ExamCreationDialogState extends State<ExamCreationDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _examNameController = TextEditingController();
  final TextEditingController _instructionController = TextEditingController();
  DateTime _examDate = DateTime.now();
  bool _showInstruction = false;

  // Attachments
  List<Map<String, dynamic>> _attachments = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.examToEdit != null) {
      _examNameController.text = widget.examToEdit!['examName'] ?? '';
      final ts = widget.examToEdit!['date'] as Timestamp?;
      if (ts != null) _examDate = ts.toDate();

      _instructionController.text = widget.examToEdit!['instruction'] ?? '';
      _showInstruction = (widget.examToEdit!['hasInstruction'] == true);

      if (widget.examToEdit!['attachments'] != null) {
        _attachments = List<Map<String, dynamic>>.from(
          widget.examToEdit!['attachments'],
        );
      }
    } else {
      _examNameController.text = "${widget.lessonName} ";
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _examDate = picked);
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null) {
        final file = result.files.first;
        setState(() {
          _attachments.add({
            'type': 'file',
            'name': file.name,
            'url': '', // Will be filled after upload
            'bytes': file.bytes,
            'isNewFile': true,
          });
        });
      }
    } catch (e) {
      debugPrint('File picker error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dosya seçimi başarısız: $e')));
    }
  }

  Future<String?> _uploadFile(Map<String, dynamic> fileData) async {
    try {
      if (fileData['bytes'] == null) return null;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${timestamp}_${fileData['name']}';
      final ref = FirebaseStorage.instance.ref().child(
        'exam_instructions/${widget.institutionId}/$fileName',
      );

      await ref.putData(fileData['bytes'] as Uint8List);
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _saveExam() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // 1. Upload attachments if any
      List<Map<String, dynamic>> finalAttachments = [];
      for (var item in _attachments) {
        if (item['isNewFile'] == true) {
          final downloadUrl = await _uploadFile(item);
          if (downloadUrl != null) {
            finalAttachments.add({
              'name': item['name'],
              'url': downloadUrl,
              'type': 'file',
            });
          }
        } else {
          // Existing
          finalAttachments.add(item);
        }
      }

      // 2. Save only Exam Definition (No grades yet)
      final docRef = widget.examToEdit != null
          ? FirebaseFirestore.instance
                .collection('class_exams')
                .doc(widget.examToEdit!['id'])
          : FirebaseFirestore.instance.collection('class_exams').doc();

      final data = {
        'institutionId': widget.institutionId,
        'classId': widget.classId,
        'lessonId': widget.lessonId,
        'lessonName': widget.lessonName,
        'examName': _examNameController.text.trim(),
        'date': Timestamp.fromDate(_examDate),
        'instruction': _showInstruction
            ? _instructionController.text.trim()
            : null,
        'hasInstruction': _showInstruction,
        'attachments': finalAttachments,
        // We do NOT overwrite grades here if editing, unless we want to reset them (usually not)
        // If creating new, grades will be missing or empty map.
        if (widget.examToEdit == null) 'grades': {},
        if (widget.examToEdit == null)
          'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.examToEdit != null) {
        await docRef.update(data);
      } else {
        await docRef.set(data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sınav tanımlandı.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.grading, color: Colors.blue.shade700),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.examToEdit != null
                        ? 'Sınavı Düzenle'
                        : 'Yeni Sınav Oluştur',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _examNameController,
                decoration: InputDecoration(
                  labelText: 'Sınav Adı',
                  hintText: 'Örn: Türkçe 1. Dönem 1. Yazılı',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.edit_note),
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Sınav adı zorunludur' : null,
              ),
              const SizedBox(height: 16),

              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Sınav Tarihi',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    DateFormat('dd.MM.yyyy').format(_examDate),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              SwitchListTile(
                title: const Text('Yönerge Ekle'),
                subtitle: const Text('Sınav açıklaması veya dosyalar'),
                value: _showInstruction,
                onChanged: (val) => setState(() => _showInstruction = val),
                contentPadding: EdgeInsets.zero,
              ),

              if (_showInstruction) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _instructionController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Yönerge Metni',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: const Text('Dosya Ekle'),
                ),
                if (_attachments.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _attachments.length,
                      itemBuilder: (context, index) {
                        final f = _attachments[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.insert_drive_file,
                            size: 20,
                          ),
                          title: Text(
                            f['name'],
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.red,
                            ),
                            onPressed: () =>
                                setState(() => _attachments.removeAt(index)),
                          ),
                        );
                      },
                    ),
                  ),
              ],

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveExam,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.examToEdit != null ? 'Güncelle' : 'Kaydet',
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
