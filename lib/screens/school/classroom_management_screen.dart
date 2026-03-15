import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/classroom_model.dart';
import '../../services/term_service.dart';

class ClassroomManagementScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const ClassroomManagementScreen({
    super.key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  });

  @override
  State<ClassroomManagementScreen> createState() =>
      _ClassroomManagementScreenState();
}

class _ClassroomManagementScreenState extends State<ClassroomManagementScreen>
    with WidgetsBindingObserver {
  String _searchQuery = '';
  String? _selectedClassroomId;
  Map<String, dynamic>? _selectedClassroom;
  String? _selectedTypeFilter; // Derslik tipi filtresi
  List<String> _classroomTypes = []; // Derslik tipleri
  List<Map<String, dynamic>> _lessons = []; // Dersler
  String? _currentTermId; // Dönem filtresi için
  bool _isViewingPastTerm = false; // Geçmiş dönem görüntüleniyor mu?

  // Varsayılan derslik tipleri
  static const List<String> _defaultClassroomTypes = [
    'Sınıf',
    'Laboratuvar',
    'Spor Salonu',
    'Müzik Odası',
    'Resim Atölyesi',
    'Bilgisayar Laboratuvarı',
    'Kütüphane',
    'Konferans Salonu',
    'Çok Amaçlı Salon',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTermAndData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadTermFilter();
    }
  }

  Future<void> _reloadTermFilter() async {
    final selectedTermId = await TermService().getSelectedTermId();
    final activeTermId = await TermService().getActiveTermId();
    final effectiveTermId = selectedTermId ?? activeTermId;
    if (mounted && _currentTermId != effectiveTermId) {
      setState(() {
        _currentTermId = effectiveTermId;
        _isViewingPastTerm =
            selectedTermId != null && selectedTermId != activeTermId;
      });
    }
  }

  Future<void> _loadTermAndData() async {
    final selectedTermId = await TermService().getSelectedTermId();
    final activeTermId = await TermService().getActiveTermId();
    final effectiveTermId = selectedTermId ?? activeTermId;
    if (mounted) {
      setState(() {
        _currentTermId = effectiveTermId;
        _isViewingPastTerm =
            selectedTermId != null && selectedTermId != activeTermId;
      });
    }
    _loadClassroomTypes();
    _loadLessons();
  }

  Future<void> _loadClassroomTypes() async {
    final allTypes = Set<String>.from(_defaultClassroomTypes);

    // Mevcut dersliklerden tipleri al
    try {
      final classrooms = await FirebaseFirestore.instance
          .collection('classrooms')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in classrooms.docs) {
        final type = doc.data()['classroomType'] as String?;
        if (type != null && type.isNotEmpty) {
          allTypes.add(type);
        }
      }
    } catch (e) {
      debugPrint('Derslik tipi yükleme hatası: $e');
    }

    final sortedList = allTypes.toList()..sort();
    setState(() {
      _classroomTypes = sortedList;
    });
  }

  Future<void> _loadLessons() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('lessons')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      setState(() {
        _lessons = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      });
    } catch (e) {
      debugPrint('Ders yükleme hatası: $e');
    }
  }

  Stream<QuerySnapshot> _getClassroomsStream() {
    return FirebaseFirestore.instance
        .collection('classrooms')
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  List<ClassroomModel> _filterClassrooms(List<ClassroomModel> classrooms) {
    var filtered = classrooms;

    // Dönem filtresi
    if (_currentTermId != null) {
      filtered = filtered.where((c) {
        final classroomData = c.toMap();
        final cTermId = classroomData['termId'];
        // Dersliğin termId'si yoksa veya mevcut termId'ye eşitse göster
        return cTermId == null || cTermId == _currentTermId;
      }).toList();
    }

    // Tip filtresi
    if (_selectedTypeFilter != null) {
      filtered = filtered
          .where((c) => c.classroomType == _selectedTypeFilter)
          .toList();
    }

    // Arama filtresi
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (c) =>
                c.classroomName.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                c.classroomCode.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                (c.classroomType?.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    ) ??
                    false),
          )
          .toList();
    }

    return filtered;
  }

  void _showClassroomFormDialog({ClassroomModel? classroomToEdit}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ClassroomFormDialog(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
        classroomTypes: _classroomTypes,
        classroomToEdit: classroomToEdit,
        onClassroomSaved: () {
          setState(() {});
          _loadClassroomTypes();
        },
      ),
    );
  }

  void _showLessonAssignmentDialog(ClassroomModel classroom) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _LessonAssignmentDialog(
        classroom: classroom,
        schoolTypeId: widget.schoolTypeId,
        institutionId: widget.institutionId,
        lessons: _lessons,
      ),
    );
  }

  Future<void> _deleteClassroom(
    String classroomId,
    String classroomName,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 12),
            Text('Dersliği Sil'),
          ],
        ),
        content: Text(
          '"$classroomName" dersliğini silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('classrooms')
          .doc(classroomId)
          .update({'isActive': false});

      setState(() {
        _selectedClassroomId = null;
        _selectedClassroom = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Derslik silindi')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey.shade900,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Derslik Listesi',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              widget.schoolTypeName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            return _buildWideLayout();
          } else {
            return _buildNarrowLayout();
          }
        },
      ),
      floatingActionButton: _isViewingPastTerm
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showClassroomFormDialog(),
              icon: Icon(Icons.add),
              label: Text('Yeni Derslik'),
            ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        // Sol Panel - Derslik Listesi
        SizedBox(
          width: 350,
          child: Column(
            children: [
              _buildLeftPanelHeader(),
              Expanded(child: _buildClassroomList()),
            ],
          ),
        ),
        // Sağ Panel - Derslik Detayı
        Expanded(
          child: _selectedClassroom != null
              ? _buildClassroomDetail(_selectedClassroom!)
              : _buildEmptyDetail(),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        _buildLeftPanelHeader(),
        Expanded(child: _buildClassroomList()),
      ],
    );
  }

  Widget _buildLeftPanelHeader() {
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
          // Başlık ve sayaç
          Row(
            children: [
              Icon(Icons.meeting_room_outlined, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Derslikler',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              StreamBuilder<QuerySnapshot>(
                stream: _getClassroomsStream(),
                builder: (context, snapshot) {
                  final count = snapshot.hasData
                      ? snapshot.data!.docs.length
                      : 0;
                  return Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
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
          // Arama
          SizedBox(
            height: 40,
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Derslik ara...',
                hintStyle: TextStyle(color: Colors.white70, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: Colors.white70, size: 20),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.2),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 12,
                ),
              ),
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          SizedBox(height: 12),
          // Filtreler
          Row(
            children: [
              // Tümü butonu
              _buildFilterChip('Tümü', _selectedTypeFilter == null, () {
                setState(() => _selectedTypeFilter = null);
              }),
              SizedBox(width: 8),
              // Tip filtresi
              Expanded(
                child: Container(
                  height: 32,
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _selectedTypeFilter != null
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedTypeFilter,
                      hint: Text(
                        'Tip',
                        style: TextStyle(
                          color: _selectedTypeFilter != null
                              ? Colors.indigo
                              : Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      icon: Icon(
                        Icons.arrow_drop_down,
                        size: 20,
                        color: _selectedTypeFilter != null
                            ? Colors.indigo
                            : Colors.white70,
                      ),
                      dropdownColor: Colors.white,
                      isExpanded: true,
                      isDense: true,
                      selectedItemBuilder: (context) {
                        return [
                          ..._classroomTypes.map(
                            (t) => Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                t,
                                style: TextStyle(
                                  color: Colors.indigo,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ];
                      },
                      items: _classroomTypes
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(
                                type,
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedTypeFilter = value),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white
              : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.indigo : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildClassroomList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getClassroomsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData ||
            snapshot.data!.docs.isEmpty ||
            _filterClassrooms(
              snapshot.data!.docs
                  .map(
                    (doc) => ClassroomModel.fromMap(
                      doc.data() as Map<String, dynamic>,
                      doc.id,
                    ),
                  )
                  .toList(),
            ).isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.meeting_room_outlined,
                    size: 64,
                    color: Colors.indigo.shade300,
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  'Derslik Bulunamadı',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  _searchQuery.isNotEmpty
                      ? 'Aramanıza uygun sonuç bulunamadı'
                      : 'Henüz derslik eklenmemiş',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                SizedBox(height: 24),
                if (!_isViewingPastTerm)
                  ElevatedButton.icon(
                    onPressed: () => _showClassroomFormDialog(),
                    icon: Icon(Icons.add),
                    label: Text('Yeni Derslik Ekle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        final classrooms = snapshot.data!.docs.map((doc) {
          return ClassroomModel.fromMap(
            doc.data() as Map<String, dynamic>,
            doc.id,
          );
        }).toList();

        final filteredClassrooms = _filterClassrooms(classrooms);

        if (filteredClassrooms.isEmpty) {
          return Center(child: Text('Filtrelere uygun derslik bulunamadı'));
        }

        return ListView.builder(
          padding: EdgeInsets.all(8),
          itemCount: filteredClassrooms.length,
          itemBuilder: (context, index) {
            final classroom = filteredClassrooms[index];
            final isSelected = _selectedClassroomId == classroom.id;

            return Card(
              margin: EdgeInsets.only(bottom: 8),
              color: isSelected ? Colors.indigo.shade50 : null,
              child: ListTile(
                onTap: () {
                  setState(() {
                    _selectedClassroomId = classroom.id;
                    _selectedClassroom = {
                      'id': classroom.id,
                      'classroomName': classroom.classroomName,
                      'classroomCode': classroom.classroomCode,
                      'classroomType': classroom.classroomType,
                      'capacity': classroom.capacity,
                      'floor': classroom.floor,
                      'building': classroom.building,
                      'description': classroom.description,
                    };
                  });

                  // Dar ekranda detay sayfasına git
                  if (MediaQuery.of(context).size.width <= 800) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => _ClassroomDetailPage(
                          classroom: classroom,
                          lessons: _lessons,
                          onEdit: () => _showClassroomFormDialog(
                            classroomToEdit: classroom,
                          ),
                          onDelete: () => _deleteClassroom(
                            classroom.id!,
                            classroom.classroomName,
                          ),
                          onAssign: () =>
                              _showLessonAssignmentDialog(classroom),
                        ),
                      ),
                    );
                  }
                },
                leading: CircleAvatar(
                  backgroundColor: isSelected
                      ? Colors.indigo
                      : Colors.grey.shade300,
                  child: Icon(
                    _getClassroomIcon(classroom.classroomType),
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                    size: 20,
                  ),
                ),
                title: Text(
                  classroom.classroomName,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${classroom.classroomType ?? 'Sınıf'} • ${classroom.capacity} kişilik',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right),
              ),
            );
          },
        );
      },
    );
  }

  IconData _getClassroomIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'laboratuvar':
      case 'bilgisayar laboratuvarı':
        return Icons.science;
      case 'spor salonu':
        return Icons.sports_basketball;
      case 'müzik odası':
        return Icons.music_note;
      case 'resim atölyesi':
        return Icons.palette;
      case 'kütüphane':
        return Icons.local_library;
      case 'konferans salonu':
      case 'çok amaçlı salon':
        return Icons.groups;
      default:
        return Icons.meeting_room;
    }
  }

  Widget _buildEmptyDetail() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.meeting_room_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          SizedBox(height: 16),
          Text(
            'Detayları görmek için bir derslik seçin',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildClassroomDetail(Map<String, dynamic> classroomData) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.indigo.shade100,
                child: Icon(
                  _getClassroomIcon(classroomData['classroomType']),
                  size: 28,
                  color: Colors.indigo,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      classroomData['classroomName'] ?? '',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${classroomData['classroomType'] ?? 'Sınıf'} • ${classroomData['capacity']} kişilik',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.edit, color: Colors.indigo),
                tooltip: 'Dersliği Düzenle',
                onPressed: () {
                  final classroom = ClassroomModel(
                    id: classroomData['id'],
                    classroomName: classroomData['classroomName'],
                    classroomCode: classroomData['classroomCode'] ?? '',
                    classroomType: classroomData['classroomType'],
                    capacity: classroomData['capacity'] ?? 0,
                    floor: classroomData['floor'],
                    building: classroomData['building'],
                    description: classroomData['description'],
                    schoolTypeId: widget.schoolTypeId,
                    schoolTypeName: widget.schoolTypeName,
                    institutionId: widget.institutionId,
                    createdAt: DateTime.now(),
                  );
                  _showClassroomFormDialog(classroomToEdit: classroom);
                },
              ),
              IconButton(
                icon: Icon(Icons.delete, color: Colors.red),
                tooltip: 'Dersliği Sil',
                onPressed: () => _deleteClassroom(
                  classroomData['id'],
                  classroomData['classroomName'],
                ),
              ),
            ],
          ),
          SizedBox(height: 24),

          // Ders Atama Butonu
          ElevatedButton.icon(
            onPressed: () {
              final classroom = ClassroomModel(
                id: classroomData['id'],
                classroomName: classroomData['classroomName'],
                classroomCode: classroomData['classroomCode'] ?? '',
                classroomType: classroomData['classroomType'],
                capacity: classroomData['capacity'] ?? 0,
                floor: classroomData['floor'],
                building: classroomData['building'],
                description: classroomData['description'],
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
                institutionId: widget.institutionId,
                createdAt: DateTime.now(),
              );
              _showLessonAssignmentDialog(classroom);
            },
            icon: Icon(Icons.add),
            label: Text('Ders Ata'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
          ),
          SizedBox(height: 24),

          // Atanan Dersler Listesi
          Text(
            'Atanan Dersler',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          _buildAssignedLessonsList(classroomData['id']),
        ],
      ),
    );
  }

  Widget _buildAssignedLessonsList(String classroomId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('classroomLessons')
          .where('classroomId', isEqualTo: classroomId)
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Bu dersliğe henüz ders atanmamış',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          );
        }

        return Column(
          children: snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            // classNames array veya eski className field'ını kontrol et
            final classNames = data['classNames'] as List<dynamic>? ?? [];
            final classNameStr = classNames.isNotEmpty
                ? classNames.join(', ')
                : (data['className'] ?? 'Genel');

            return Card(
              margin: EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => _showEditAssignedLessonDialog(doc.id, data),
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: Icon(Icons.book, color: Colors.green),
                ),
                title: Text(data['lessonName'] ?? ''),
                subtitle: Text(classNameStr),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Atamayı Sil',
                  onPressed: () => _confirmDeleteAssignedLesson(
                    doc.id,
                    data['lessonName'] ?? '',
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  void _confirmDeleteAssignedLesson(String assignmentId, String lessonName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 12),
            Text('Atamayı Sil'),
          ],
        ),
        content: Text(
          '"$lessonName" dersinin atamasını silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('classroomLessons')
                  .doc(assignmentId)
                  .update({'isActive': false});
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Atama silindi')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditAssignedLessonDialog(
    String assignmentId,
    Map<String, dynamic> data,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.edit, color: Colors.indigo),
            SizedBox(width: 12),
            Expanded(child: Text('${data['lessonName']} - Düzenle')),
          ],
        ),
        content: Text(
          'Bu atamayı düzenlemek için ders ataması ekranını kullanın.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Tamam'),
          ),
        ],
      ),
    );
  }
}

// ==================== DERSLİK FORM DIALOG ====================
class _ClassroomFormDialog extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final List<String> classroomTypes;
  final ClassroomModel? classroomToEdit;
  final VoidCallback onClassroomSaved;

  const _ClassroomFormDialog({
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    required this.classroomTypes,
    this.classroomToEdit,
    required this.onClassroomSaved,
  });

  @override
  State<_ClassroomFormDialog> createState() => _ClassroomFormDialogState();
}

class _ClassroomFormDialogState extends State<_ClassroomFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _codeController;
  late TextEditingController _capacityController;
  late TextEditingController _floorController;
  late TextEditingController _buildingController;
  late TextEditingController _descriptionController;
  String? _selectedType;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.classroomToEdit?.classroomName ?? '',
    );
    _codeController = TextEditingController(
      text: widget.classroomToEdit?.classroomCode ?? '',
    );
    _capacityController = TextEditingController(
      text: widget.classroomToEdit?.capacity.toString() ?? '30',
    );
    _floorController = TextEditingController(
      text: widget.classroomToEdit?.floor ?? '',
    );
    _buildingController = TextEditingController(
      text: widget.classroomToEdit?.building ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.classroomToEdit?.description ?? '',
    );
    _selectedType = widget.classroomToEdit?.classroomType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _capacityController.dispose();
    _floorController.dispose();
    _buildingController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveClassroom() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Yeni kayıtlar için aktif dönemi otomatik al
      final activeTermId = await TermService().getActiveTermId();

      final classroomData = {
        'classroomName': _nameController.text.trim(),
        'classroomCode': _codeController.text.trim(),
        'classroomType': _selectedType,
        'capacity': int.tryParse(_capacityController.text) ?? 30,
        'floor': _floorController.text.trim().isEmpty
            ? null
            : _floorController.text.trim(),
        'building': _buildingController.text.trim().isEmpty
            ? null
            : _buildingController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'schoolTypeId': widget.schoolTypeId,
        'schoolTypeName': widget.schoolTypeName,
        'institutionId': widget.institutionId,
        'termId': widget.classroomToEdit != null
            ? (widget.classroomToEdit!.toMap()['termId'] ?? activeTermId)
            : activeTermId,
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.classroomToEdit != null) {
        await FirebaseFirestore.instance
            .collection('classrooms')
            .doc(widget.classroomToEdit!.id)
            .update(classroomData);
      } else {
        classroomData['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance
            .collection('classrooms')
            .add(classroomData);
      }

      widget.onClassroomSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.classroomToEdit != null
                  ? 'Derslik güncellendi'
                  : 'Derslik eklendi',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Başlık
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.meeting_room, color: Colors.indigo),
                  ),
                  SizedBox(width: 16),
                  Text(
                    widget.classroomToEdit != null
                        ? 'Derslik Düzenle'
                        : 'Yeni Derslik Tanımla',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),

              // Derslik Adı
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Derslik Adı *',
                  hintText: 'Örn: 8A Sınıfı, Fen Laboratuvarı',
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Derslik adı gerekli'
                    : null,
              ),
              SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _codeController,
                      decoration: InputDecoration(
                        labelText: 'Kısa Ad *',
                        prefixIcon: Icon(Icons.label_outlined),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Gerekli'
                          : null,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _capacityController,
                      decoration: InputDecoration(
                        labelText: 'Kapasite *',
                        suffixText: 'kişi',
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _selectedType,
                decoration: InputDecoration(
                  labelText: 'Derslik Tipi',
                  prefixIcon: Icon(Icons.category_outlined),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: widget.classroomTypes
                    .map(
                      (type) =>
                          DropdownMenuItem(value: type, child: Text(type)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedType = value),
              ),
              SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _floorController,
                      decoration: InputDecoration(
                        labelText: 'Kat',
                        prefixIcon: Icon(Icons.stairs_outlined),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _buildingController,
                      decoration: InputDecoration(
                        labelText: 'Bina',
                        prefixIcon: Icon(Icons.business_outlined),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Açıklama',
                  prefixIcon: Icon(Icons.notes_outlined),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 2,
              ),
              SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'İptal',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveClassroom,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Kaydet',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
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

// ==================== DERS ATAMA DIALOG ====================
class _LessonAssignmentDialog extends StatefulWidget {
  final ClassroomModel classroom;
  final String schoolTypeId;
  final String institutionId;
  final List<Map<String, dynamic>> lessons;

  const _LessonAssignmentDialog({
    required this.classroom,
    required this.schoolTypeId,
    required this.institutionId,
    required this.lessons,
  });

  @override
  State<_LessonAssignmentDialog> createState() =>
      _LessonAssignmentDialogState();
}

class _LessonAssignmentDialogState extends State<_LessonAssignmentDialog> {
  int _currentStep = 0; // 0: Ders seçimi, 1: Sınıf seçimi
  List<Map<String, dynamic>> _selectedLessons = [];
  Map<String, List<Map<String, dynamic>>> _lessonClasses =
      {}; // lessonId -> classes
  Map<String, List<String>> _selectedClassesForLesson =
      {}; // lessonId -> [classIds] (çoklu seçim)
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingAssignments();
  }

  Set<String> _existingLessonIds = {};

  Future<void> _loadExistingAssignments() async {
    // Mevcut atamaları yükle
    final snapshot = await FirebaseFirestore.instance
        .collection('classroomLessons')
        .where('classroomId', isEqualTo: widget.classroom.id)
        .where('isActive', isEqualTo: true)
        .get();

    // Mevcut atanmış ders ID'lerini al
    final existingIds = snapshot.docs
        .map((doc) {
          final data = doc.data();
          return data['lessonId'] as String?;
        })
        .whereType<String>()
        .toSet();

    // Zaten atanmış dersleri işaretle
    setState(() {
      _existingLessonIds = existingIds;
    });
  }

  Future<void> _loadClassesForLesson(String lessonId) async {
    if (_lessonClasses.containsKey(lessonId)) return;

    setState(() => _isLoading = true);

    try {
      // Bu derse atanmış sınıfları getir
      final snapshot = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('lessonId', isEqualTo: lessonId)
          .where('isActive', isEqualTo: true)
          .get();

      final classes = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'classId': data['classId'],
          'className': data['className'],
          'weeklyHours': data['weeklyHours'],
        };
      }).toList();

      setState(() {
        _lessonClasses[lessonId] = classes;
      });
    } catch (e) {
      debugPrint('Sınıf yükleme hatası: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _proceedToClassSelection() {
    if (_selectedLessons.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('En az bir ders seçin')));
      return;
    }

    // Seçilen dersler için sınıfları yükle
    for (var lesson in _selectedLessons) {
      _loadClassesForLesson(lesson['id']);
    }

    setState(() => _currentStep = 1);
  }

  Future<void> _saveAssignments() async {
    setState(() => _isSaving = true);

    try {
      final batch = FirebaseFirestore.instance.batch();

      for (var lesson in _selectedLessons) {
        final lessonId = lesson['id'];
        final selectedClassIds = _selectedClassesForLesson[lessonId] ?? [];

        if (selectedClassIds.isEmpty) {
          // Sınıf seçilmemişse genel atama yap
          final docRef = FirebaseFirestore.instance
              .collection('classroomLessons')
              .doc();
          batch.set(docRef, {
            'classroomId': widget.classroom.id,
            'classroomName': widget.classroom.classroomName,
            'lessonId': lessonId,
            'lessonName': lesson['lessonName'],
            'lessonAssignmentIds': [],
            'classNames': [],
            'schoolTypeId': widget.schoolTypeId,
            'institutionId': widget.institutionId,
            'isActive': true,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Her seçilen sınıf için ayrı atama
          final classNames = <String>[];
          for (var classId in selectedClassIds) {
            if (_lessonClasses[lessonId] != null) {
              final classData = _lessonClasses[lessonId]!.firstWhere(
                (c) => c['id'] == classId,
                orElse: () => {},
              );
              if (classData['className'] != null) {
                classNames.add(classData['className']);
              }
            }
          }

          final docRef = FirebaseFirestore.instance
              .collection('classroomLessons')
              .doc();
          batch.set(docRef, {
            'classroomId': widget.classroom.id,
            'classroomName': widget.classroom.classroomName,
            'lessonId': lessonId,
            'lessonName': lesson['lessonName'],
            'lessonAssignmentIds': selectedClassIds,
            'classNames': classNames,
            'schoolTypeId': widget.schoolTypeId,
            'institutionId': widget.institutionId,
            'isActive': true,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedLessons.length} ders dersliğe atandı'),
            backgroundColor: Colors.green,
          ),
        );
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
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.book, color: Colors.indigo),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ders Ata'),
                Text(
                  widget.classroom.classroomName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 450,
        child: Column(
          children: [
            // Adım göstergesi
            Row(
              children: [
                _buildStepIndicator(0, 'Ders Seçimi'),
                Expanded(child: Divider()),
                _buildStepIndicator(1, 'Sınıf Seçimi'),
              ],
            ),
            SizedBox(height: 16),

            // İçerik
            Expanded(
              child: _currentStep == 0
                  ? _buildLessonSelection()
                  : _buildClassSelection(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('İptal'),
        ),
        if (_currentStep == 0)
          ElevatedButton.icon(
            onPressed: _proceedToClassSelection,
            icon: Icon(Icons.arrow_forward),
            label: Text('İleri (${_selectedLessons.length})'),
          )
        else ...[
          TextButton(
            onPressed: () => setState(() => _currentStep = 0),
            child: Text('Geri'),
          ),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAssignments,
            icon: _isSaving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.save),
            label: Text('Kaydet'),
          ),
        ],
      ],
    );
  }

  Widget _buildStepIndicator(int step, String label) {
    final isActive = _currentStep >= step;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: isActive ? Colors.indigo : Colors.grey.shade300,
          child: Text(
            '${step + 1}',
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey,
              fontSize: 12,
            ),
          ),
        ),
        SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.indigo : Colors.grey,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildLessonSelection() {
    if (widget.lessons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.book_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Henüz ders tanımlanmamış'),
            Text(
              'Önce Ders Listesi ekranından ders ekleyin',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bilgi
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bu derslikte yapılacak dersleri seçin',
                  style: TextStyle(color: Colors.blue.shade700, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),

        // Ders listesi
        Expanded(
          child: ListView.builder(
            itemCount: widget.lessons.length,
            itemBuilder: (context, index) {
              final lesson = widget.lessons[index];
              final isSelected = _selectedLessons.any(
                (l) => l['id'] == lesson['id'],
              );
              final isAlreadyAssigned = _existingLessonIds.contains(
                lesson['id'],
              );

              return Card(
                margin: EdgeInsets.only(bottom: 8),
                color: isAlreadyAssigned
                    ? Colors.green.shade50
                    : (isSelected ? Colors.indigo.shade50 : null),
                child: CheckboxListTile(
                  value: isSelected || isAlreadyAssigned,
                  onChanged: isAlreadyAssigned
                      ? null
                      : (value) {
                          setState(() {
                            if (value == true) {
                              _selectedLessons.add(lesson);
                            } else {
                              _selectedLessons.removeWhere(
                                (l) => l['id'] == lesson['id'],
                              );
                            }
                          });
                        },
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          lesson['lessonName'] ?? '',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (isAlreadyAssigned)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Atandı',
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    lesson['branchName'] ?? '',
                    style: TextStyle(fontSize: 12),
                  ),
                  secondary: CircleAvatar(
                    backgroundColor: isAlreadyAssigned
                        ? Colors.green
                        : (isSelected ? Colors.indigo : Colors.grey.shade300),
                    child: Icon(
                      isAlreadyAssigned ? Icons.check : Icons.book,
                      color: (isAlreadyAssigned || isSelected)
                          ? Colors.white
                          : Colors.grey.shade700,
                      size: 20,
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildClassSelection() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bilgi
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Her ders için hangi sınıfın bu dersliği kullanacağını seçin',
                  style: TextStyle(color: Colors.green.shade700, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),

        // Ders ve sınıf seçimi
        Expanded(
          child: ListView.builder(
            itemCount: _selectedLessons.length,
            itemBuilder: (context, index) {
              final lesson = _selectedLessons[index];
              final lessonId = lesson['id'];
              final classes = _lessonClasses[lessonId] ?? [];

              return Card(
                margin: EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ders başlığı
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.indigo.shade100,
                            child: Icon(
                              Icons.book,
                              size: 16,
                              color: Colors.indigo,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              lesson['lessonName'] ?? '',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),

                      // Sınıf seçimi (çoklu)
                      if (classes.isEmpty)
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber,
                                color: Colors.orange,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Bu ders henüz hiçbir sınıfa atanmamış (genel atama yapılacak)',
                                  style: TextStyle(
                                    color: Colors.orange.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sınıf Seçin (birden fazla seçebilirsiniz)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: classes.map((c) {
                                final classId = c['id'] as String;
                                final isSelected =
                                    (_selectedClassesForLesson[lessonId] ?? [])
                                        .contains(classId);
                                return FilterChip(
                                  label: Text(
                                    '${c['className']} (${c['weeklyHours']}s)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedColor: Colors.indigo,
                                  checkmarkColor: Colors.white,
                                  onSelected: (selected) {
                                    setState(() {
                                      if (_selectedClassesForLesson[lessonId] ==
                                          null) {
                                        _selectedClassesForLesson[lessonId] =
                                            [];
                                      }
                                      if (selected) {
                                        _selectedClassesForLesson[lessonId]!
                                            .add(classId);
                                      } else {
                                        _selectedClassesForLesson[lessonId]!
                                            .remove(classId);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            if ((_selectedClassesForLesson[lessonId] ?? [])
                                .isEmpty)
                              Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Seçim yapılmazsa genel atama yapılır',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ==================== DERSLİK DETAY SAYFASI (DAR EKRAN) ====================
class _ClassroomDetailPage extends StatelessWidget {
  final ClassroomModel classroom;
  final List<Map<String, dynamic>> lessons;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAssign;

  const _ClassroomDetailPage({
    required this.classroom,
    required this.lessons,
    required this.onEdit,
    required this.onDelete,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(classroom.classroomName),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: Icon(Icons.edit), onPressed: onEdit),
          IconButton(icon: Icon(Icons.delete), onPressed: onDelete),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Derslik bilgileri
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.indigo.shade100,
                          child: Icon(
                            Icons.meeting_room,
                            size: 28,
                            color: Colors.indigo,
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                classroom.classroomName,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Kod: ${classroom.classroomCode}',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Divider(height: 24),
                    _buildInfoRow(
                      Icons.category,
                      'Tip',
                      classroom.classroomType ?? 'Sınıf',
                    ),
                    _buildInfoRow(
                      Icons.people,
                      'Kapasite',
                      '${classroom.capacity} kişi',
                    ),
                    if (classroom.floor != null)
                      _buildInfoRow(Icons.stairs, 'Kat', classroom.floor!),
                    if (classroom.building != null)
                      _buildInfoRow(
                        Icons.business,
                        'Bina',
                        classroom.building!,
                      ),
                    if (classroom.description != null)
                      _buildInfoRow(
                        Icons.notes,
                        'Açıklama',
                        classroom.description!,
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),

            // Ders Ata butonu
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAssign,
                icon: Icon(Icons.add),
                label: Text('Ders Ata'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            SizedBox(height: 24),

            // Atanan dersler
            Text(
              'Atanan Dersler',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            _buildAssignedLessons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          SizedBox(width: 12),
          Text('$label: ', style: TextStyle(color: Colors.grey)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildAssignedLessons(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('classroomLessons')
          .where('classroomId', isEqualTo: classroom.id)
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Bu dersliğe henüz ders atanmamış',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          );
        }

        return Column(
          children: snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return Card(
              margin: EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: Icon(Icons.book, color: Colors.green),
                ),
                title: Text(data['lessonName'] ?? ''),
                subtitle: Text(data['className'] ?? 'Genel'),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
