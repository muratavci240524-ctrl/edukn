import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:typed_data';

class ClassLessonPlanEntryDialog extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? periodId;
  final String classId;
  final String lessonId;
  final String lessonName;
  final String? existingPlanId;
  final Map<String, dynamic>? existingPlanData;

  const ClassLessonPlanEntryDialog({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.periodId,
    required this.classId,
    required this.lessonId,
    required this.lessonName,
    this.existingPlanId,
    this.existingPlanData,
  }) : super(key: key);

  @override
  State<ClassLessonPlanEntryDialog> createState() =>
      _ClassLessonPlanEntryDialogState();
}

class _ClassLessonPlanEntryDialogState
    extends State<ClassLessonPlanEntryDialog> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _outcomeController = TextEditingController();

  bool _useYearlyPlan = false;
  bool _isLoadingPlans = false;
  bool _isSaving = false;

  List<QueryDocumentSnapshot> _availableYearlyPlans = [];
  String? _selectedYearlyPlanId;

  List<QueryDocumentSnapshot> _availableWeeks = [];
  String? _selectedWeekId;

  List<Map<String, dynamic>> _attachments = [];
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    if (widget.periodId != null) {
      _loadYearlyPlans();
    }

    if (widget.existingPlanData != null) {
      final data = widget.existingPlanData!;
      _titleController.text = data['title'] ?? '';
      _contentController.text = data['content'] ?? '';
      _outcomeController.text = data['outcome'] ?? '';
      _useYearlyPlan = data['isFromYearlyPlan'] ?? false;
      _selectedYearlyPlanId = data['yearlyPlanId'];
      _selectedWeekId = data['weeklyPlanId'];

      if (_selectedYearlyPlanId != null) {
        _loadWeeks(_selectedYearlyPlanId!);
      }

      if (data['attachments'] != null) {
        _attachments = List<Map<String, dynamic>>.from(data['attachments']);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _outcomeController.dispose();
    super.dispose();
  }

  Future<void> _loadYearlyPlans() async {
    setState(() => _isLoadingPlans = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('yearlyPlans')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('lessonId', isEqualTo: widget.lessonId)
          .where('isActive', isEqualTo: true)
          //.where('classIds', arrayContains: widget.classId) // Removed to broaden search
          //.where('periodId', isEqualTo: widget.periodId) // Optional: restrict to current period
          .get();

      setState(() {
        _availableYearlyPlans = snapshot.docs;
        // If only one plan exists, auto-select it
        if (_availableYearlyPlans.length == 1) {
          _selectedYearlyPlanId = _availableYearlyPlans.first.id;
          _loadWeeks(_selectedYearlyPlanId!);
        }
      });
    } catch (e) {
      print('Error loading yearly plans: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPlans = false);
    }
  }

  Future<void> _loadWeeks(String planId) async {
    setState(() => _isLoadingPlans = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('yearlyPlans')
          .doc(planId)
          .collection('weeklyPlans')
          .orderBy('weekNumber')
          .get();

      setState(() {
        _availableWeeks = snapshot.docs;
      });
    } catch (e) {
      print('Error loading weeks: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPlans = false);
    }
  }

  void _onWeekSelected(String? weekId) {
    setState(() {
      _selectedWeekId = weekId;
    });

    if (weekId != null) {
      final weekDoc = _availableWeeks.firstWhere((doc) => doc.id == weekId);
      final data = weekDoc.data() as Map<String, dynamic>;

      final weekNum = data['weekNumber'];
      final topic = data['topic'] ?? '';
      final outcome = data['outcome'] ?? '';

      _titleController.text = '$weekNum. Hafta ${widget.lessonName} Planı';
      _contentController.text = topic;
      _outcomeController.text = outcome;
    }
  }

  Future<void> _addLink() async {
    final titleController = TextEditingController();
    final urlController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Link Ekle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'Başlık',
                hintText: 'Örn: Konu Anlatım Videosu',
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: 'Link (URL)',
                hintText: 'https://...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.isNotEmpty &&
                  urlController.text.isNotEmpty) {
                setState(() {
                  _attachments.add({
                    'type': 'link',
                    'name': titleController.text,
                    'url': urlController.text,
                  });
                });
                Navigator.pop(context);
              }
            },
            child: Text('Ekle'),
          ),
        ],
      ),
    );
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
      print('File picker error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dosya seççimi başarırsız: $e')));
    }
  }

  Future<String?> _uploadFile(Map<String, dynamic> fileData) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || fileData['bytes'] == null) return null;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${timestamp}_${fileData['name']}';
      final ref = FirebaseStorage.instance.ref().child(
        'lesson_plan_attachments/${user.uid}/$fileName',
      );

      await ref.putData(fileData['bytes'] as Uint8List);
      return await ref.getDownloadURL();
    } catch (e) {
      print('Upload error: $e');
      return null;
    }
  }

  Future<void> _savePlan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isUploading) return;

    setState(() {
      _isSaving = true;
      _isUploading = true;
    });

    try {
      // 1. Upload files first
      List<Map<String, dynamic>> finalAttachments = [];

      for (var item in _attachments) {
        if (item['type'] == 'file' && item['isNewFile'] == true) {
          final downloadUrl = await _uploadFile(item);
          if (downloadUrl != null) {
            finalAttachments.add({
              'type': 'file',
              'name': item['name'],
              'url': downloadUrl,
            });
          }
        } else {
          // Links or existing files
          finalAttachments.add({
            'type': item['type'],
            'name': item['name'],
            'url': item['url'],
          });
        }
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Kullanıcı oturumu bulunamadı');

      final batch = FirebaseFirestore.instance.batch();

      // 2. Create or Update Class Lesson Plan
      final docRef = widget.existingPlanId != null
          ? FirebaseFirestore.instance
                .collection('classLessonPlans')
                .doc(widget.existingPlanId)
          : FirebaseFirestore.instance.collection('classLessonPlans').doc();

      final data = {
        'institutionId': widget.institutionId,
        'schoolTypeId': widget.schoolTypeId,
        'periodId': widget.periodId,
        'classId': widget.classId,
        'lessonId': widget.lessonId,
        'lessonName': widget.lessonName,
        'teacherId': user.uid,
        'title': _titleController.text,
        'content': _contentController.text, // İşleniş / Konu
        'outcome': _outcomeController.text, // Kazanım
        'yearlyPlanId': _selectedYearlyPlanId,
        'weeklyPlanId': _selectedWeekId,
        'isFromYearlyPlan': _useYearlyPlan,
        'updatedAt': FieldValue.serverTimestamp(),
        'attachments': finalAttachments,
      };

      if (widget.existingPlanId == null) {
        data['date'] = FieldValue.serverTimestamp();
        data['createdAt'] = FieldValue.serverTimestamp();
        batch.set(docRef, data);
      } else {
        batch.update(docRef, data);
      }

      // 3. Update Yearly Plan Week (if selected)
      if (_useYearlyPlan &&
          _selectedYearlyPlanId != null &&
          _selectedWeekId != null) {
        final weekRef = FirebaseFirestore.instance
            .collection('yearlyPlans')
            .doc(_selectedYearlyPlanId)
            .collection('weeklyPlans')
            .doc(_selectedWeekId);

        batch.update(weekRef, {
          'coveredClassIds': FieldValue.arrayUnion([widget.classId]),
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ders planı kaydedildi'),
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
      if (mounted)
        setState(() {
          _isSaving = false;
          _isUploading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.existingPlanId != null ? 'Planı Düzenle' : 'Ders Planı Gir',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Container(
          color: Colors.white,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: Form(key: _formKey, child: _buildFormContent()),
                ),
              ),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _savePlan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'Kaydet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: EdgeInsets.all(24),
        constraints: BoxConstraints(maxWidth: 500, maxHeight: 800),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.event_note, color: Colors.blue),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.existingPlanId != null
                            ? 'Planı Düzenle'
                            : 'Ders Planı Gir',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                SizedBox(height: 24),
                _buildFormContent(),
                SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _savePlan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'Kaydet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Switch: Yıllık Plandan Seç
        if (_availableYearlyPlans.isNotEmpty)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Yıllık Plandan Seç',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('Konu ve kazanımları otomatik doldur'),
            value: _useYearlyPlan,
            onChanged: (val) {
              setState(() {
                _useYearlyPlan = val;
                if (!val) {
                  _selectedWeekId = null;
                  _titleController.clear();
                  _contentController.clear();
                  _outcomeController.clear();
                }
              });
            },
            activeColor: Colors.blue,
          ),

        if (_useYearlyPlan) ...[
          if (_availableYearlyPlans.length > 1)
            DropdownButtonFormField<String>(
              value: _selectedYearlyPlanId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Yıllık Plan Seçiniz',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              items: _availableYearlyPlans.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return DropdownMenuItem(
                  value: doc.id,
                  child: Text(
                    data['planTitle'] ?? 'Plansız',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedYearlyPlanId = val;
                  _selectedWeekId = null;
                });
                if (val != null) _loadWeeks(val);
              },
            ),

          SizedBox(height: 16),

          if (_isLoadingPlans)
            Center(child: CircularProgressIndicator())
          else if (_selectedYearlyPlanId != null)
            DropdownButtonFormField<String>(
              value: _selectedWeekId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Hafta Seçiniz',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              items: _availableWeeks.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final weekNum = data['weekNumber'];
                final weekStart = (data['weekStart'] as Timestamp?)?.toDate();
                // Check if covered
                final coveredClasses = List<String>.from(
                  data['coveredClassIds'] ?? [],
                );
                final isCovered = coveredClasses.contains(widget.classId);

                final dateFormat = DateFormat('dd.MM');
                final dateStr = weekStart != null
                    ? ' (${dateFormat.format(weekStart)})'
                    : '';

                return DropdownMenuItem(
                  value: doc.id,
                  child: Row(
                    children: [
                      Text(
                        '$weekNum. Hafta$dateStr',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (isCovered)
                        Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Colors.green,
                          ),
                        ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          data['topic'] ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            decoration: isCovered
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: _onWeekSelected,
              validator: (val) => val == null ? 'Lütfen bir hafta seçin' : null,
            ),
        ],

        SizedBox(height: 24),

        TextFormField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: 'Ders Planı Başlığı',
            hintText: 'Örn: 1. Hafta Türkçe Ders Planı',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(Icons.title),
          ),
          validator: (val) =>
              val == null || val.isEmpty ? 'Başlık zorunludur' : null,
        ),
        SizedBox(height: 16),

        TextFormField(
          controller: _contentController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'İçerik / İşleniş',
            hintText: 'Derste işlenen konular...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(Icons.subject),
            alignLabelWithHint: true,
          ),
          validator: (val) =>
              val == null || val.isEmpty ? 'İçerik zorunludur' : null,
        ),
        SizedBox(height: 16),

        TextFormField(
          controller: _outcomeController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Kazanım',
            hintText: 'İlgili kazanımlar...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: Icon(Icons.check_circle_outline),
            alignLabelWithHint: true,
          ),
          validator: (val) =>
              val == null || val.isEmpty ? 'Kazanım zorunludur' : null,
        ),

        SizedBox(height: 24),

        // Attachments Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Materyaller / Ekler',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _addLink,
                  icon: Icon(Icons.link, size: 20),
                  label: Text('Link'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickFile,
                  icon: Icon(Icons.upload_file, size: 20),
                  label: Text('Dosya'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: 8),
        if (_attachments.isEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Text(
                'Henüz materyal eklenmedi',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: _attachments.length,
            separatorBuilder: (_, __) => SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = _attachments[index];
              final isLink = item['type'] == 'link';
              return Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isLink
                            ? Colors.blue.withOpacity(0.1)
                            : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isLink ? Icons.link : Icons.description,
                        color: isLink ? Colors.blue : Colors.orange,
                        size: 20,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['name'],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isLink)
                            Text(
                              item['url'],
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (item['isNewFile'] == true)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade400,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _attachments.removeAt(index);
                        });
                      },
                      tooltip: 'Kaldır',
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
