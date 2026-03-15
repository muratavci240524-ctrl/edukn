import 'package:flutter/material.dart';
import '../../../../models/assessment/optical_form_model.dart';
import '../../../../models/assessment/exam_type_model.dart';
import '../../../../services/assessment_service.dart';
import './optical_form_definition_screen.dart';

class OpticalFormListScreen extends StatefulWidget {
  final String institutionId;

  const OpticalFormListScreen({Key? key, required this.institutionId})
    : super(key: key);

  @override
  State<OpticalFormListScreen> createState() => _OpticalFormListScreenState();
}

class _OpticalFormListScreenState extends State<OpticalFormListScreen> {
  final AssessmentService _service = AssessmentService();

  OpticalForm? _selectedForm;
  bool _isCreatingNew = false;
  String _searchQuery = '';
  String? _selectedExamTypeFilter;
  List<ExamType> _examTypes = [];

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });

    // Load exam types for filter
    _service.getExamTypes(widget.institutionId).listen((types) {
      if (mounted) {
        setState(() {
          _examTypes = types;
        });
      }
    });
  }

  void _onCreateNew() {
    setState(() {
      _selectedForm = null;
      _isCreatingNew = true;
    });
  }

  void _onSelect(OpticalForm form) {
    setState(() {
      _selectedForm = form;
      _isCreatingNew = false;
    });
  }

  void _onSaveSuccess() {
    if (MediaQuery.of(context).size.width < 768) {
      Navigator.pop(context);
    } else {
      setState(() {
        _selectedForm = null;
        _isCreatingNew = false;
      });
    }
  }

  Stream<List<OpticalForm>> _getStream() {
    return _service.getOpticalForms(widget.institutionId);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;

        if (isMobile) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              elevation: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Optik Formlar'),
                  Text(
                    'Tanımlar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
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
                        title: const Text('Yeni Optik Form'),
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      body: OpticalFormDefinition(
                        institutionId: widget.institutionId,
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
              title: const Text('Optik Form Yönetimi'),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                          label: Text('Yeni Optik Form Ekle'),
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
                Expanded(
                  child: Container(
                    color: Colors.grey[50],
                    child: (_selectedForm != null || _isCreatingNew)
                        ? OpticalFormDefinition(
                            key: ValueKey(_selectedForm?.id ?? 'new'),
                            institutionId: widget.institutionId,
                            opticalForm: _selectedForm,
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
              Icon(Icons.document_scanner, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Optik Formlar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              StreamBuilder<List<OpticalForm>>(
                stream: _getStream(),
                builder: (context, snapshot) {
                  final list = snapshot.data ?? [];
                  var count = list.length;
                  if (_selectedExamTypeFilter != null) {
                    count = list
                        .where((f) => f.examTypeId == _selectedExamTypeFilter)
                        .length;
                  }
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
              hintText: 'Form ara...',
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  'Tümü',
                  _selectedExamTypeFilter == null,
                  () => setState(() => _selectedExamTypeFilter = null),
                ),
                SizedBox(width: 8),
                ..._examTypes.map(
                  (type) => Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: _buildFilterChip(
                      type.name,
                      _selectedExamTypeFilter == type.id,
                      () => setState(() => _selectedExamTypeFilter = type.id),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    return StreamBuilder<List<OpticalForm>>(
      stream: _getStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          if (snapshot.error.toString().contains('permission-denied')) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'Yetki Hatası: Lütfen veritabanı kurallarını kontrol edin.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            );
          }
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        var forms = snapshot.data ?? [];
        if (_searchQuery.isNotEmpty) {
          forms = forms
              .where((f) => f.name.toLowerCase().contains(_searchQuery))
              .toList();
        }
        if (_selectedExamTypeFilter != null) {
          forms = forms
              .where((f) => f.examTypeId == _selectedExamTypeFilter)
              .toList();
        }

        if (forms.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 48, color: Colors.grey[300]),
                SizedBox(height: 16),
                Text('Kayıt bulunamadı.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 16),
          itemCount: forms.length,
          itemBuilder: (context, index) {
            final form = forms[index];
            final isSelected = !isMobile && _selectedForm?.id == form.id;

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
                  vertical: 4,
                ),
                leading: CircleAvatar(
                  backgroundColor: isSelected
                      ? Colors.indigo
                      : Colors.indigo[50],
                  child: Icon(
                    Icons.document_scanner,
                    color: isSelected ? Colors.white : Colors.indigo,
                  ),
                ),
                title: Text(
                  form.name,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: Text(
                  'Sınav: ${form.examTypeName}',
                  style: TextStyle(fontSize: 12),
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
                            title: Text(form.name),
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                          body: OpticalFormDefinition(
                            institutionId: widget.institutionId,
                            opticalForm: form,
                            onSuccess: () => Navigator.pop(context),
                          ),
                        ),
                      ),
                    );
                  } else {
                    _onSelect(form);
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
