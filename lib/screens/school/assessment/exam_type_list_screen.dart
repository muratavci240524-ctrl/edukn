import 'package:flutter/material.dart';
import '../../../../models/assessment/exam_type_model.dart';
import '../../../../services/assessment_service.dart';
import './exam_type_form_screen.dart';

class ExamTypeListScreen extends StatefulWidget {
  final String institutionId;

  const ExamTypeListScreen({Key? key, required this.institutionId})
    : super(key: key);

  @override
  State<ExamTypeListScreen> createState() => _ExamTypeListScreenState();
}

class _ExamTypeListScreenState extends State<ExamTypeListScreen> {
  final AssessmentService _service = AssessmentService();

  ExamType? _selectedExamType;
  bool _isCreatingNew = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  void _onCreateNew() {
    setState(() {
      _selectedExamType = null;
      _isCreatingNew = true;
    });
  }

  void _onSelect(ExamType type) {
    setState(() {
      _selectedExamType = type;
      _isCreatingNew = false;
    });
  }

  void _onSaveSuccess() {
    if (MediaQuery.of(context).size.width < 768) {
      Navigator.pop(context);
    } else {
      setState(() {
        _isCreatingNew = false;
        _selectedExamType = null;
      });
    }
  }

  Stream<List<ExamType>> _getStream() {
    return _service.getExamTypes(widget.institutionId);
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
                  Text('Sınav Türleri'),
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
                const SizedBox(height: 10),
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
                        title: const Text('Yeni Sınav Türü'),
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      body: ExamTypeForm(
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
              title: const Text('Sınav Türleri Yönetimi'),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              elevation: 0,
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
                      SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: ElevatedButton.icon(
                          onPressed: _onCreateNew,
                          icon: Icon(Icons.add),
                          label: Text('Yeni Sınav Türü Ekle'),
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
                    child: (_selectedExamType != null || _isCreatingNew)
                        ? ExamTypeForm(
                            key: ValueKey(_selectedExamType?.id ?? 'new'),
                            institutionId: widget.institutionId,
                            examType: _selectedExamType,
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
              Icon(Icons.assignment, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Sınav Türleri',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              StreamBuilder<List<ExamType>>(
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
              hintText: 'Sınav türü ara...',
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
          // Filter Chips (Placeholder to match look)
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
    return StreamBuilder<List<ExamType>>(
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
          return Center(child: Text('Hata oluştu.'));
        }

        var types = snapshot.data ?? [];
        if (_searchQuery.isNotEmpty) {
          types = types
              .where((t) => t.name.toLowerCase().contains(_searchQuery))
              .toList();
        }

        if (types.isEmpty) {
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
          itemCount: types.length,
          itemBuilder: (context, index) {
            final type = types[index];
            final isSelected = !isMobile && _selectedExamType?.id == type.id;

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
                    Icons.assignment,
                    color: isSelected ? Colors.white : Colors.indigo,
                  ),
                ),
                title: Text(
                  type.name,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: Text(
                  '${type.subjects.length} Ders • ${type.optionCount} Şık',
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
                            title: Text(type.name),
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                          body: ExamTypeForm(
                            institutionId: widget.institutionId,
                            examType: type,
                            onSuccess: () => Navigator.pop(context),
                          ),
                        ),
                      ),
                    );
                  } else {
                    _onSelect(type);
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
