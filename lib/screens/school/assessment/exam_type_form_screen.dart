import 'package:flutter/material.dart';
import '../../../../models/assessment/exam_type_model.dart';
import '../../../../services/assessment_service.dart';

class ExamTypeForm extends StatefulWidget {
  final String institutionId;
  final ExamType? examType; // Null if creating new
  final VoidCallback onSuccess;

  const ExamTypeForm({
    Key? key,
    required this.institutionId,
    this.examType,
    required this.onSuccess,
  }) : super(key: key);

  @override
  State<ExamTypeForm> createState() => _ExamTypeFormState();
}

class _ExamTypeFormState extends State<ExamTypeForm> {
  final _formKey = GlobalKey<FormState>();
  final _service = AssessmentService();

  late TextEditingController _nameController;
  late TextEditingController _baseScoreController;
  late TextEditingController _maxScoreController;
  late TextEditingController _wrongRatioController;

  int _optionCount = 4;
  List<ExamSubject> _subjects = [];
  List<String> _availableBranches = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initForm();
    _loadBranches();
  }

  @override
  void didUpdateWidget(covariant ExamTypeForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.examType?.id != widget.examType?.id) {
      _initForm();
    }
  }

  void _initForm() {
    _nameController = TextEditingController(text: widget.examType?.name ?? '');
    _baseScoreController = TextEditingController(
      text: widget.examType?.baseScore.toString() ?? '0',
    );
    _maxScoreController = TextEditingController(
      text: widget.examType?.maxScore.toString() ?? '500',
    );
    _wrongRatioController = TextEditingController(
      text: widget.examType?.wrongCorrectRatio.toString() ?? '3',
    );

    if (widget.examType != null) {
      _subjects = List.from(widget.examType!.subjects);
      _optionCount = widget.examType!.optionCount;
    } else {
      _subjects = [];
      _optionCount = 4;
    }
  }

  Future<void> _loadBranches() async {
    final branches = await _service.getAvailableBranches(widget.institutionId);
    if (mounted) {
      setState(() {
        _availableBranches = branches;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_subjects.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('En az bir ders eklemelisiniz.')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final newType = ExamType(
        id: widget.examType?.id ?? '',
        institutionId: widget.institutionId,
        name: _nameController.text.trim(),
        baseScore: double.tryParse(_baseScoreController.text) ?? 0,
        maxScore: double.tryParse(_maxScoreController.text) ?? 500,
        wrongCorrectRatio: double.tryParse(_wrongRatioController.text) ?? 3,
        optionCount: _optionCount,
        subjects: _subjects,
      );

      await _service.saveExamType(newType);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sınav türü başarıyla kaydedildi.')),
        );
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kayıt Başarısız: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addSubject(String branchName) {
    if (_subjects.any((s) => s.branchName == branchName)) return;
    setState(() {
      _subjects.add(
        ExamSubject(
          branchName: branchName,
          questionCount: 10,
          coefficient: 1.0,
        ),
      );
    });
  }

  void _updateSubject(int index, {int? count, double? coeff}) {
    final old = _subjects[index];
    setState(() {
      _subjects[index] = ExamSubject(
        branchName: old.branchName,
        questionCount: count ?? old.questionCount,
        coefficient: coeff ?? old.coefficient,
      );
    });
  }

  void _removeSubject(int index) {
    setState(() {
      _subjects.removeAt(index);
    });
  }

  void _showAddSubjectDialog() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8,
              ),
              child: Text(
                'Ders Seçin',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _availableBranches.length,
                itemBuilder: (context, i) {
                  final branch = _availableBranches[i];
                  final isAdded = _subjects.any((s) => s.branchName == branch);
                  return ListTile(
                    leading: Icon(
                      Icons.book,
                      color: isAdded ? Colors.grey : Colors.indigo,
                    ),
                    title: Text(
                      branch,
                      style: TextStyle(
                        color: isAdded ? Colors.grey : Colors.black,
                      ),
                    ),
                    trailing: isAdded
                        ? Icon(Icons.check_circle, color: Colors.green)
                        : Icon(Icons.add_circle_outline),
                    onTap: isAdded
                        ? null
                        : () {
                            _addSubject(branch);
                            Navigator.pop(ctx);
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _save,
                        icon: Icon(Icons.save),
                        label: Text('KAYDET'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  _buildBasicInfoCard(),
                  SizedBox(height: 16),
                  _buildScoringCard(),
                  SizedBox(height: 16),
                  _buildSubjectsCard(),
                  SizedBox(height: 40),
                ],
              ),
            ),
          );
  }

  Widget _buildBasicInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  'Temel Bilgiler',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Divider(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Sınav Türü Adı',
                hintText: 'Örn: LGS Deneme, TYT, Bursluluk',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Icon(Icons.text_fields),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Lütfen bir isim girin' : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoringCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Puanlama Ayarları',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildNumberInput(
                    controller: _baseScoreController,
                    label: 'Taban Puan',
                    icon: Icons.vertical_align_bottom,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: _buildNumberInput(
                    controller: _maxScoreController,
                    label: 'Tavan Puan',
                    icon: Icons.vertical_align_top,
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildNumberInput(
                    controller: _wrongRatioController,
                    label: 'Yanlış/Doğru',
                    icon: Icons.remove_circle_outline,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _optionCount,
                    decoration: InputDecoration(
                      labelText: 'Şık Sayısı',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.list_alt),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    items: [3, 4, 5]
                        .map(
                          (e) =>
                              DropdownMenuItem(value: e, child: Text('$e Şık')),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _optionCount = v!),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberInput({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    String? helper,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      ),
    );
  }

  Widget _buildSubjectsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.library_books, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'Dersler',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_subjects.length}',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _showAddSubjectDialog,
                  icon: Icon(Icons.add),
                  label: Text('Ders Ekle'),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.green[50],
                    foregroundColor: Colors.green[700],
                  ),
                ),
              ],
            ),
            Divider(height: 24),
            if (_subjects.isEmpty)
              Container(
                padding: EdgeInsets.all(32),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(
                      Icons.library_add_check_outlined,
                      size: 48,
                      color: Colors.grey[300],
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Henüz ders eklenmemiş.\nSınavda yer alacak dersleri ekleyiniz.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: _subjects.length,
                separatorBuilder: (c, i) => SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final subject = _subjects[index];
                  return Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey[200]!),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              subject.branchName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.indigo,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: Colors.red[400],
                              ),
                              onPressed: () => _removeSubject(index),
                              constraints: BoxConstraints(),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: subject.questionCount.toString(),
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  labelText: 'Soru',
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                ),
                                onChanged: (v) => _updateSubject(
                                  index,
                                  count: int.tryParse(v) ?? 0,
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('x', style: TextStyle(color: Colors.grey)),
                            SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: subject.coefficient.toString(),
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  labelText: 'Katsayı',
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                ),
                                onChanged: (v) => _updateSubject(
                                  index,
                                  coeff: double.tryParse(v) ?? 0,
                                ),
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('=', style: TextStyle(color: Colors.grey)),
                            SizedBox(width: 8),
                            Container(
                              width: 60,
                              alignment: Alignment.center,
                              child: Text(
                                '${subject.questionCount * subject.coefficient}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
