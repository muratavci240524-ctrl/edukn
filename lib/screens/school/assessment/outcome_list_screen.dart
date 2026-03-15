import 'package:flutter/material.dart';
import '../../../services/assessment_service.dart';
import '../../../models/assessment/outcome_list_model.dart';
import 'outcome_list_form_screen.dart';

class OutcomeListScreen extends StatefulWidget {
  final String institutionId;

  const OutcomeListScreen({Key? key, required this.institutionId})
    : super(key: key);

  @override
  _OutcomeListScreenState createState() => _OutcomeListScreenState();
}

class _OutcomeListScreenState extends State<OutcomeListScreen> {
  final AssessmentService _service = AssessmentService();

  // Filters
  String? _selectedClassLevel;
  String _searchQuery = '';

  // Selection State
  OutcomeList? _selectedOutcomeList;
  bool _isCreatingNew = false;
  int _newCreationKey = 0;

  final List<String> _classLevels = [
    '1. Sınıf',
    '2. Sınıf',
    '3. Sınıf',
    '4. Sınıf',
    '5. Sınıf',
    '6. Sınıf',
    '7. Sınıf',
    '8. Sınıf',
    '9. Sınıf',
    '10. Sınıf',
    '11. Sınıf',
    '12. Sınıf',
    'Hazırlık',
    'Mezun',
  ];

  void _createNew() {
    final isMobile = MediaQuery.of(context).size.width < 800;
    if (isMobile) {
      _navigateToForm(null);
    } else {
      setState(() {
        _selectedOutcomeList = null;
        _isCreatingNew = true;
        _newCreationKey++;
      });
    }
  }

  void _selectList(OutcomeList list) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    if (isMobile) {
      _navigateToForm(list);
    } else {
      setState(() {
        _selectedOutcomeList = list;
        _isCreatingNew = false;
      });
    }
  }

  void _navigateToForm(OutcomeList? list) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              list == null ? 'Yeni Kazanım Listesi' : 'Listeyi Düzenle',
            ),
          ),
          body: OutcomeListForm(
            institutionId: widget.institutionId,
            outcomeList: list,
            onSaved: () {
              Navigator.pop(context);
            },
            onCancelled: () {
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  void _cancelSelection() {
    setState(() {
      _selectedOutcomeList = null;
      _isCreatingNew = false;
    });
  }

  void _deleteList(OutcomeList list) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Silme Onayı'),
        content: Text('Bu kazanım listesini silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _service.deleteOutcomeList(list.id);
      if (_selectedOutcomeList?.id == list.id) {
        _cancelSelection();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kazanım listesi silindi.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        if (isMobile) {
          // Mobile View: Only List
          return Scaffold(
            appBar: AppBar(
              title: const Text('Kazanım Yönetimi'),
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            body: Column(
              children: [
                _buildLeftPanelHeader(),
                SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ElevatedButton.icon(
                    onPressed: _createNew,
                    icon: Icon(Icons.add),
                    label: Text('Yeni Liste Oluştur'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size(double.infinity, 45),
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                SizedBox(height: 8),
                Expanded(child: _buildList()),
              ],
            ),
          );
        }

        // Desktop View: Split View
        return Scaffold(
          appBar: AppBar(
            title: const Text('Kazanım Yönetimi'),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT PANEL
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
                    _buildLeftPanelHeader(),
                    SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: ElevatedButton.icon(
                        onPressed: _createNew,
                        icon: Icon(Icons.add),
                        label: Text('Yeni Liste Oluştur'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(double.infinity, 45),
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Expanded(child: _buildList()),
                  ],
                ),
              ),

              // RIGHT PANEL
              Expanded(
                child: Container(
                  color: Colors.grey[50],
                  child: (_selectedOutcomeList != null || _isCreatingNew)
                      ? OutcomeListForm(
                          key: ValueKey(
                            _selectedOutcomeList?.id ?? 'new_$_newCreationKey',
                          ),
                          institutionId: widget.institutionId,
                          outcomeList: _selectedOutcomeList,
                          onSaved: () {
                            // Stay on page for desktop
                          },
                          onCancelled: _cancelSelection,
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
      },
    );
  }

  Widget _buildLeftPanelHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.teal.shade600, Colors.teal.shade400],
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
              Icon(Icons.list_alt, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Kazanım Listeleri',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              StreamBuilder<List<OutcomeList>>(
                stream: _service.getOutcomeLists(widget.institutionId),
                builder: (context, snapshot) {
                  final list = snapshot.data ?? [];
                  var count = list.length;
                  // Simple count logic based on active filters if any
                  if (_searchQuery.isNotEmpty) {
                    final q = _searchQuery.toLowerCase();
                    count = list
                        .where(
                          (l) =>
                              l.name.toLowerCase().contains(q) ||
                              l.classLevel.toLowerCase().contains(q) ||
                              l.branchName.toLowerCase().contains(q),
                        )
                        .length;
                  } else {
                    if (_selectedClassLevel != null) {
                      count = list
                          .where((l) => l.classLevel == _selectedClassLevel)
                          .length;
                    } // Logic gets complex with multiple filters, keep simple total or filtered total
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
          // SEARCH
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Liste ara...',
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
          // FILTERS (Horizontally scrollable chips)
          // We have Class Level and Branch. Maybe prioritize Class Level as chips?
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  'Tümü',
                  _selectedClassLevel == null,
                  () => setState(() => _selectedClassLevel = null),
                ),
                SizedBox(width: 8),
                ..._classLevels.map(
                  (level) => Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: _buildFilterChip(
                      level,
                      _selectedClassLevel == level,
                      () => setState(() => _selectedClassLevel = level),
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
            color: isSelected ? Colors.teal : Colors.white,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    return StreamBuilder<List<OutcomeList>>(
      stream: _service.getOutcomeLists(widget.institutionId),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Hata!'));
        if (snapshot.connectionState == ConnectionState.waiting)
          return Center(child: CircularProgressIndicator());

        var lists = snapshot.data ?? [];

        // Apply Filters
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          lists = lists
              .where(
                (l) =>
                    l.name.toLowerCase().contains(q) ||
                    l.classLevel.toLowerCase().contains(q) ||
                    l.branchName.toLowerCase().contains(q),
              )
              .toList();
        }
        if (_selectedClassLevel != null) {
          lists = lists
              .where((l) => l.classLevel == _selectedClassLevel)
              .toList();
        }
        // If we want to filter by branch too, we might need another UI element or just rely on search.
        // For visual consistency with Optical Form (which has exam types chips), class levels seem appropriate here.

        if (lists.isEmpty) {
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
          itemCount: lists.length,
          itemBuilder: (context, index) {
            final list = lists[index];
            final isSelected = _selectedOutcomeList?.id == list.id;

            return Card(
              margin: EdgeInsets.only(bottom: 8),
              elevation: isSelected ? 2 : 1,
              color: isSelected ? Colors.teal[50] : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isSelected
                    ? BorderSide(color: Colors.teal, width: 1.5)
                    : BorderSide.none,
              ),
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: CircleAvatar(
                  backgroundColor: isSelected ? Colors.teal : Colors.teal[50],
                  child: Icon(
                    Icons.list_alt,
                    color: isSelected ? Colors.white : Colors.teal,
                  ),
                ),
                title: Text(
                  list.name.isNotEmpty
                      ? list.name
                      : '${list.classLevel} - ${list.branchName}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: Text(
                  '${list.classLevel} • ${list.branchName}',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSelected)
                      Icon(Icons.check_circle, color: Colors.teal),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: Colors.grey),
                      onSelected: (value) {
                        if (value == 'delete') _deleteList(list);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red, size: 20),
                              SizedBox(width: 8),
                              Text('Sil', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                onTap: () => _selectList(list),
              ),
            );
          },
        );
      },
    );
  }
}
