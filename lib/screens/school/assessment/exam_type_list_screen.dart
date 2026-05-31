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
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              leading: const BackButton(color: Colors.white),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Sınav Türleri', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(
                    'Tanımlar',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      color: Colors.white70,
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
                        title: const Text('Yeni Sınav Türü', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        iconTheme: const IconThemeData(color: Colors.white),
                        leading: const BackButton(color: Colors.white),
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
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            ),
          );
        } else {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Sınav Türleri Yönetimi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
              leading: const BackButton(color: Colors.white),
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
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: ElevatedButton.icon(
                          onPressed: _onCreateNew,
                          icon: const Icon(Icons.add),
                          label: const Text('Yeni Sınav Türü Ekle'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 45),
                            backgroundColor: Colors.orange,
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
          colors: [Colors.orange.shade600, Colors.orange.shade400],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Sınav Türleri',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              StreamBuilder<List<ExamType>>(
                stream: _getStream(),
                builder: (context, snapshot) {
                  final count = snapshot.hasData ? snapshot.data!.length : 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Sınav türü ara...',
              hintStyle: const TextStyle(color: Colors.white70),
              prefixIcon: const Icon(Icons.search, size: 20, color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.orange : Colors.white,
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
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          if (snapshot.error.toString().contains('permission-denied')) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'Yetki Hatası: Lütfen veritabanı kurallarını kontrol edin.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            );
          }
          return const Center(child: Text('Hata oluştu.'));
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
                const SizedBox(height: 16),
                const Text('Kayıt bulunamadı.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: types.length,
          itemBuilder: (context, index) {
            final type = types[index];
            final isSelected = !isMobile && _selectedExamType?.id == type.id;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: isSelected ? 2 : 1,
              color: isSelected ? Colors.orange[50] : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isSelected
                    ? const BorderSide(color: Colors.orange, width: 1.5)
                    : BorderSide.none,
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: CircleAvatar(
                  backgroundColor: isSelected
                      ? Colors.orange
                      : Colors.orange[50],
                  child: Icon(
                    Icons.assignment,
                    color: isSelected ? Colors.white : Colors.orange,
                  ),
                ),
                title: Text(
                  type.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: Text(
                  '${type.subjects.length} Ders • ${type.optionCount} Şık',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Colors.orange)
                    : Icon(Icons.chevron_right, color: Colors.grey[300]),
                onTap: () {
                  if (isMobile) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Scaffold(
                          appBar: AppBar(
                            title: Text(type.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            iconTheme: const IconThemeData(color: Colors.white),
                            leading: const BackButton(color: Colors.white),
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
