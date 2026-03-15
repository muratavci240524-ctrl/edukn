import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/school/homework_model.dart';

class CreateHomeworkDialog extends StatefulWidget {
  final String institutionId;
  final String classId;
  final String lessonId;
  final String lessonName;
  final String teacherId;

  const CreateHomeworkDialog({
    super.key,
    required this.institutionId,
    required this.classId,
    required this.lessonId,
    required this.lessonName,
    required this.teacherId,
  });

  @override
  State<CreateHomeworkDialog> createState() => _CreateHomeworkDialogState();
}

class _CreateHomeworkDialogState extends State<CreateHomeworkDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  final _contentController = TextEditingController();

  DateTime _assignedDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 1));

  List<HomeworkAttachment> _attachments = [];
  List<Map<String, dynamic>> _students = [];
  List<String> _selectedStudentIds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: '${widget.lessonName} - ');
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where(
            'classId',
            isEqualTo: widget.classId,
          ) // Changed from currentClassId
          .where('isActive', isEqualTo: true)
          .get();

      if (!mounted) return;

      setState(() {
        _students = snap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return data;
        }).toList();

        _students.sort(
          (a, b) =>
              (a['fullName'] ?? '').toString().compareTo(b['fullName'] ?? ''),
        );
        _selectedStudentIds = _students.map((e) => e['id'] as String).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching students: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addAttachmentDialog() {
    String type = 'link';
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Dosya veya Link Ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Link', style: TextStyle(fontSize: 14)),
                      value: 'link',
                      groupValue: type,
                      activeColor: const Color(0xFF4F46E5),
                      onChanged: (val) => setState(() => type = val!),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text(
                        'Dosya (URL)',
                        style: TextStyle(fontSize: 14),
                      ),
                      value: 'file',
                      groupValue: type,
                      activeColor: const Color(0xFF4F46E5),
                      onChanged: (val) => setState(() => type = val!),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Başlık (Görünecek İsim)',
                  filled: true,
                  fillColor: Colors.blueGrey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                decoration: InputDecoration(
                  labelText: 'URL / Adres',
                  filled: true,
                  fillColor: Colors.blueGrey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                if (titleCtrl.text.isNotEmpty && urlCtrl.text.isNotEmpty) {
                  this.setState(() {
                    _attachments.add(
                      HomeworkAttachment(
                        type: type,
                        title: titleCtrl.text,
                        url: urlCtrl.text,
                      ),
                    );
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Ekle', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az bir öğrenci seçmelisiniz.')),
      );
      return;
    }

    try {
      setState(() => _isLoading = true);

      final hw = Homework(
        id: '',
        institutionId: widget.institutionId,
        classId: widget.classId,
        lessonId: widget.lessonId,
        teacherId: widget.teacherId,
        title: _titleController.text,
        content: _contentController.text,
        createdAt: DateTime.now(),
        assignedDate: _assignedDate,
        dueDate: _dueDate,
        attachments: _attachments,
        targetStudentIds: _selectedStudentIds,
        studentStatuses: {for (var uid in _selectedStudentIds) uid: 0},
      );

      await FirebaseFirestore.instance.collection('homeworks').add(hw.toMap());

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ödev başarıyla verildi.'),
            backgroundColor: Color(0xFF4F46E5),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving homework: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  Widget _buildDateSelector(
    String label,
    DateTime date,
    Function(DateTime) onSelect,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                builder: (context, child) {
                  return Theme(
                    data: ThemeData.light().copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: Color(0xFF4F46E5),
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) onSelect(picked);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: Color(0xFF4F46E5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('dd.MM.yyyy').format(date),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
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

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Yeni Ödev',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                widget.lessonName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _isLoading && _students.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
              )
            : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Form(key: _formKey, child: _buildFormContent()),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'ÖDEVİ OLUŞTUR',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
      );
    }

    // Desktop/Tablet Dialog
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFFF8FAFC),
      child: Container(
        width: 700,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Yeni Ödev',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.lessonName,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blueGrey.shade500,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.blueGrey.shade400,
                    ),
                    tooltip: 'Kapat',
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading && _students.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF4F46E5),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(key: _formKey, child: _buildFormContent()),
                    ),
            ),

            // Footer Action
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'ÖDEVİ OLUŞTUR',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
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

  Widget _buildFormContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Ödev Bilgileri Kartı
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Ödev Başlığı',
                  labelStyle: TextStyle(color: Colors.blueGrey.shade500),
                  filled: true,
                  fillColor: Colors.blueGrey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(
                    Icons.title,
                    color: Colors.blueGrey.shade400,
                  ),
                ),
                validator: (v) => v?.isEmpty == true ? 'Başlık gerekli' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Ödev İçeriği ve Açıklama',
                  labelStyle: TextStyle(color: Colors.blueGrey.shade500),
                  filled: true,
                  fillColor: Colors.blueGrey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  alignLabelWithHint: true,
                ),
                validator: (v) => v?.isEmpty == true ? 'İçerik gerekli' : null,
              ),
              const SizedBox(height: 20),

              // Tarihler Yan Yana
              Row(
                children: [
                  _buildDateSelector(
                    'GÖNDERİM TARİHİ',
                    _assignedDate,
                    (d) => setState(() => _assignedDate = d),
                  ),
                  const SizedBox(width: 16),
                  _buildDateSelector(
                    'SON KONTROL TARİHİ',
                    _dueDate,
                    (d) => setState(() => _dueDate = d),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // 2. Öğrenci Listesi (Üstte)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Öğrenciler (${_selectedStudentIds.length}/${_students.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      if (_selectedStudentIds.length == _students.length) {
                        _selectedStudentIds.clear();
                      } else {
                        _selectedStudentIds = _students
                            .map((e) => e['id'] as String)
                            .toList();
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      _selectedStudentIds.length == _students.length
                          ? 'Temizle'
                          : 'Tümünü Seç',
                      style: const TextStyle(
                        color: Color(0xFF4F46E5),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueGrey.shade200),
              ),
              child: _students.isEmpty
                  ? Center(
                      child: Text(
                        'Bu sınıfta kayıtlı öğrenci bulunamadı.',
                        style: TextStyle(
                          color: Colors.blueGrey.shade400,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _students.length,
                      separatorBuilder: (c, i) => Divider(
                        height: 1,
                        color: Colors.blueGrey.shade100,
                        indent: 12,
                        endIndent: 12,
                      ),
                      itemBuilder: (context, index) {
                        final s = _students[index];
                        final uid = s['id'];
                        final name = s['fullName'] ?? s['name'] ?? '';
                        final isSelected = _selectedStudentIds.contains(uid);

                        return SimpleDialogOption(
                          padding: EdgeInsets.zero,
                          child: CheckboxListTile(
                            value: isSelected,
                            activeColor: const Color(0xFF4F46E5),
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              name,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.black87
                                    : Colors.blueGrey.shade700,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedStudentIds.add(uid);
                                } else {
                                  _selectedStudentIds.remove(uid);
                                }
                              });
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 3. Dosyalar (Altta)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Dosyalar & Linkler',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addAttachmentDialog,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Ekle'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF4F46E5),
                  ),
                ),
              ],
            ),
            if (_attachments.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueGrey.shade200),
                ),
                child: Center(
                  child: Text(
                    'Henüz dosya eklenmedi',
                    style: TextStyle(
                      color: Colors.blueGrey.shade400,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              ..._attachments.map(
                (a) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueGrey.shade200),
                  ),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      a.type == 'link' ? Icons.link : Icons.attach_file,
                      color: const Color(0xFF4F46E5),
                    ),
                    title: Text(
                      a.title,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      a.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.red,
                      ),
                      onPressed: () => setState(() => _attachments.remove(a)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
