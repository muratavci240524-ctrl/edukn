import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/lesson_model.dart';
import '../../services/term_service.dart';

class LessonManagementScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const LessonManagementScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<LessonManagementScreen> createState() => _LessonManagementScreenState();
}

class _LessonManagementScreenState extends State<LessonManagementScreen> {
  String _searchQuery = '';
  String? _selectedLessonId;
  Map<String, dynamic>? _selectedLesson;
  String? _selectedBranchFilter; // Branş filtresi
  List<String> _branchNames = []; // Branş adları listesi
  List<Map<String, dynamic>> _teachers = [];
  String _assignmentSortBy = 'class'; // 'class' veya 'teacher'
  String? _currentTermId; // Seçili dönem
  bool _isViewingPastTerm = false; // Geçmiş dönem görüntüleniyor mu?

  @override
  void initState() {
    super.initState();
    _loadTermAndData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reloadTermFilter();
  }

  Future<void> _reloadTermFilter() async {
    final selectedTermId = await TermService().getSelectedTermId();
    final activeTermId = await TermService().getActiveTermId();
    final effectiveTermId = selectedTermId ?? activeTermId;
    if (mounted && _currentTermId != effectiveTermId) {
      setState(() {
        _currentTermId = effectiveTermId;
        _isViewingPastTerm = selectedTermId != null && selectedTermId != activeTermId;
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
        _isViewingPastTerm = selectedTermId != null && selectedTermId != activeTermId;
      });
    }
    _loadBranchNames();
    _loadTeachers();
  }

  // Öğretmen formundaki sabit branş listesi (aynı liste)
  static const List<String> _defaultBranches = [
    'Almanca', 'Arapça', 'Beden Eğitimi ve Spor', 'Bilişim Teknolojileri ve Yazılım',
    'Biyoloji', 'Coğrafya', 'Din Kültürü ve Ahlak Bilgisi', 'Felsefe', 'Fen Bilimleri',
    'Fizik', 'Fransızca', 'Görsel Sanatlar', 'İlköğretim Matematik', 'İngilizce',
    'İspanyolca', 'Kimya', 'Kulüp', 'Matematik', 'Müzik', 'Okul Öncesi', 'Özel Eğitim',
    'Rehberlik ve Psikolojik Danışmanlık', 'Rusça', 'Sınıf Öğretmenliği', 'Sosyal Bilgiler',
    'Tarih', 'Teknoloji ve Tasarım', 'Türk Dili ve Edebiyatı', 'Türkçe',
  ];

  Future<void> _loadBranchNames() async {
    final allBranches = Set<String>.from(_defaultBranches);
    
    // Firestore'dan özel branşları ekle
    try {
      final customBranches = await FirebaseFirestore.instance
          .collection('branches')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in customBranches.docs) {
        final name = doc.data()['branchName'] as String?;
        if (name != null && name.isNotEmpty) {
          allBranches.add(name);
        }
      }
    } catch (e) {
      print('Özel branş yükleme hatası: $e');
    }

    final sortedList = allBranches.toList()..sort();
    setState(() {
      _branchNames = sortedList;
    });
  }

  Future<void> _loadTeachers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('staff')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .where('role', isEqualTo: 'teacher')
          .get();

      setState(() {
        _teachers = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      });
    } catch (e) {
      print('Öğretmen yükleme hatası: $e');
    }
  }

  Stream<QuerySnapshot> _getLessonsStream() {
    // Tüm dersleri çek, dönem filtresi client-side yapılacak
    return FirebaseFirestore.instance
        .collection('lessons')
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  List<LessonModel> _filterLessons(List<LessonModel> lessons) {
    var filtered = lessons;
    
    // Dönem filtresi: sadece seçili döneme ait olanları göster
    if (_currentTermId != null) {
      filtered = filtered.where((l) => l.termId == _currentTermId).toList();
    }
    
    // Branş filtresi
    if (_selectedBranchFilter != null) {
      filtered = filtered.where((l) => l.branchName == _selectedBranchFilter).toList();
    }
    
    // Arama filtresi
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((l) =>
        l.lessonName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        l.branchName.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
    
    return filtered;
  }

  void _showLessonFormSheet({LessonModel? lessonToEdit}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LessonFormSheet(
        schoolTypeId: widget.schoolTypeId,
        institutionId: widget.institutionId,
        termId: _currentTermId,
        branchNames: _branchNames,
        lessonToEdit: lessonToEdit,
        onLessonSaved: () {
          setState(() {});
        },
      ),
    );
  }

  void _showBranchManagementSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BranchManagementSheet(
        institutionId: widget.institutionId,
        onBranchesChanged: () => _loadBranchNames(),
      ),
    );
  }

  void _showClassAssignmentSheet(LessonModel lesson) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ClassAssignmentSheet(
        lesson: lesson,
        schoolTypeId: widget.schoolTypeId,
        institutionId: widget.institutionId,
        teachers: _teachers,
      ),
    );
  }

  Future<void> _deleteLesson(String lessonId, String lessonName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 12),
            Text('Dersi Sil'),
          ],
        ),
        content: Text('$lessonName dersini silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('lessons')
          .doc(lessonId)
          .update({'isActive': false});
      
      if (_selectedLessonId == lessonId) {
        setState(() {
          _selectedLessonId = null;
          _selectedLesson = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Her build'de dönem kontrolü yap
    _reloadTermFilter();
    
    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.indigo),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ders Listesi',
              style: TextStyle(
                color: Colors.grey.shade900,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.schoolTypeName,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _showBranchManagementSheet(),
            icon: Icon(Icons.category, size: 18),
            label: Text('Branş Yönetimi'),
            style: TextButton.styleFrom(foregroundColor: Colors.indigo),
          ),
          SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _isViewingPastTerm
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showLessonFormSheet(),
              backgroundColor: Colors.indigo,
              icon: Icon(Icons.add, color: Colors.white),
              label: Text('Yeni Ders', style: TextStyle(color: Colors.white)),
            ),
      body: isWide ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        // Sol Panel - Ders Listesi (Sınıf listesi tarzında)
        Container(
          width: 350,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(right: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Column(
            children: [
              _buildLeftPanelHeader(),
              SizedBox(height: 8),
              Expanded(child: _buildLessonList()),
            ],
          ),
        ),
        // Sağ Panel - Detay
        Expanded(
          child: _selectedLesson != null
              ? _buildLessonDetail(_selectedLesson!)
              : _buildEmptyState(),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        _buildLeftPanelHeader(),
        SizedBox(height: 8),
        Expanded(child: _buildLessonList()),
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
              Icon(Icons.book_outlined, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Dersler',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              StreamBuilder<QuerySnapshot>(
                stream: _getLessonsStream(),
                builder: (context, snapshot) {
                  final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
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
          
          // Arama
          TextField(
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Ders ara...',
              hintStyle: TextStyle(color: Colors.white70),
              prefixIcon: Icon(Icons.search, size: 20, color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          SizedBox(height: 12),
          
          // Filtre butonları
          Row(
            children: [
              // Tümü butonu
              Expanded(
                child: _buildFilterChip(
                  'Tümü',
                  _selectedBranchFilter == null,
                  () => setState(() => _selectedBranchFilter = null),
                ),
              ),
              SizedBox(width: 8),
              // Branş filtresi
              Expanded(
                flex: 2,
                child: PopupMenuButton<String>(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _selectedBranchFilter != null
                          ? Colors.white
                          : Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.category,
                          size: 16,
                          color: _selectedBranchFilter != null
                              ? Colors.indigo
                              : Colors.white,
                        ),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _selectedBranchFilter ?? 'Branş',
                            style: TextStyle(
                              color: _selectedBranchFilter != null
                                  ? Colors.indigo
                                  : Colors.white,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 16,
                          color: _selectedBranchFilter != null
                              ? Colors.indigo
                              : Colors.white,
                        ),
                      ],
                    ),
                  ),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: '',
                      child: Text('Tümü'),
                    ),
                    ..._branchNames.map((name) {
                      return PopupMenuItem(
                        value: name,
                        child: Text(name),
                      );
                    }).toList(),
                  ],
                  onSelected: (value) {
                    setState(() {
                      _selectedBranchFilter = value.isEmpty ? null : value;
                    });
                  },
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

  Widget _buildLessonList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getLessonsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.book_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('Henüz ders tanımlanmamış'),
                SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _showLessonFormSheet(),
                  icon: Icon(Icons.add),
                  label: Text('İlk Dersi Ekle'),
                ),
              ],
            ),
          );
        }

        final lessons = snapshot.data!.docs
            .map((doc) => LessonModel.fromFirestore(doc))
            .toList();
        final filtered = _filterLessons(lessons);

        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 16),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final lesson = filtered[index];
            final isSelected = _selectedLessonId == lesson.id;

            return Card(
              margin: EdgeInsets.only(bottom: 8),
              color: isSelected ? Colors.indigo.shade50 : null,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSelected ? Colors.indigo : Colors.grey.shade300,
                  child: Icon(Icons.book, color: isSelected ? Colors.white : Colors.grey),
                ),
                title: Text(
                  lesson.lessonName,
                  style: TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (lesson.shortName.isNotEmpty)
                      Container(
                        margin: EdgeInsets.only(bottom: 2),
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          lesson.shortName,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ),
                    Text(
                      lesson.branchName,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sınıf atama sayısı
                    FutureBuilder<int>(
                      future: _getAssignmentCount(lesson.id!),
                      builder: (context, snap) {
                        final count = snap.data ?? 0;
                        return Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: count > 0 ? Colors.green.shade50 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$count sınıf',
                            style: TextStyle(
                              fontSize: 12,
                              color: count > 0 ? Colors.green : Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_ios, size: 14),
                  ],
                ),
                onTap: () {
                  final isWide = MediaQuery.of(context).size.width > 900;
                  if (isWide) {
                    setState(() {
                      _selectedLessonId = lesson.id;
                      _selectedLesson = {
                        'id': lesson.id,
                        'lessonName': lesson.lessonName,
                        'shortName': lesson.shortName,
                        'branchId': lesson.branchId,
                        'branchName': lesson.branchName,
                      };
                    });
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => _LessonDetailPage(
                          lesson: lesson,
                          teachers: _teachers,
                          onEdit: () => _showLessonFormSheet(lessonToEdit: lesson),
                          onDelete: () => _deleteLesson(lesson.id!, lesson.lessonName),
                          onAssign: () => _showClassAssignmentSheet(lesson),
                        ),
                      ),
                    );
                  }
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<int> _getAssignmentCount(String lessonId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('lessonAssignments')
        .where('lessonId', isEqualTo: lessonId)
        .where('isActive', isEqualTo: true)
        .get();
    return snapshot.docs.length;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app, size: 64, color: Colors.grey.shade400),
          SizedBox(height: 16),
          Text(
            'Detayları görmek için bir ders seçin',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonDetail(Map<String, dynamic> lessonData) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık ve Aksiyonlar
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.indigo.shade100,
                child: Icon(Icons.book, size: 28, color: Colors.indigo),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          lessonData['lessonName'] ?? '',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        if ((lessonData['shortName'] ?? '').toString().isNotEmpty) ...[
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.indigo.shade200),
                            ),
                            child: Text(
                              lessonData['shortName'],
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      lessonData['branchName'] ?? '',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.edit, color: Colors.indigo),
                tooltip: 'Dersi Düzenle',
                onPressed: () {
                  final lesson = LessonModel(
                    id: lessonData['id'],
                    lessonName: lessonData['lessonName'],
                    shortName: lessonData['shortName'] ?? '',
                    branchId: lessonData['branchId'],
                    branchName: lessonData['branchName'],
                    schoolTypeId: widget.schoolTypeId,
                    institutionId: widget.institutionId,
                  );
                  _showLessonFormSheet(lessonToEdit: lesson);
                },
              ),
              IconButton(
                icon: Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteLesson(
                  lessonData['id'],
                  lessonData['lessonName'],
                ),
              ),
            ],
          ),
          SizedBox(height: 24),

          // Sınıf Atama Butonu
          ElevatedButton.icon(
            onPressed: () {
              final lesson = LessonModel(
                id: lessonData['id'],
                lessonName: lessonData['lessonName'],
                shortName: lessonData['shortName'] ?? '',
                branchId: lessonData['branchId'],
                branchName: lessonData['branchName'],
                schoolTypeId: widget.schoolTypeId,
                institutionId: widget.institutionId,
              );
              _showClassAssignmentSheet(lesson);
            },
            icon: Icon(Icons.add),
            label: Text('Sınıf Ata'),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          SizedBox(height: 24),

          // Atanan Sınıflar Listesi
          Text(
            'Atanan Sınıflar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          _buildAssignmentsList(lessonData['id'], lessonData['branchName'] ?? ''),
        ],
      ),
    );
  }

  Widget _buildAssignmentsList(String lessonId, String lessonBranchName) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('lessonId', isEqualTo: lessonId)
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Bu ders henüz hiçbir sınıfa atanmamış',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          );
        }

        // Verileri sırala
        final docs = snapshot.data!.docs.toList();
        docs.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;
          
          if (_assignmentSortBy == 'teacher') {
            // Öğretmene göre sırala
            final teacherA = ((dataA['teacherNames'] as List?)?.isNotEmpty == true)
                ? (dataA['teacherNames'] as List).first.toString()
                : 'zzz'; // Öğretmeni olmayanlar sona
            final teacherB = ((dataB['teacherNames'] as List?)?.isNotEmpty == true)
                ? (dataB['teacherNames'] as List).first.toString()
                : 'zzz';
            final teacherCompare = teacherA.compareTo(teacherB);
            if (teacherCompare != 0) return teacherCompare;
            // Aynı öğretmense sınıfa göre
            return _compareClassNames(dataA['className'] ?? '', dataB['className'] ?? '');
          } else {
            // Sınıfa göre sırala (varsayılan)
            return _compareClassNames(dataA['className'] ?? '', dataB['className'] ?? '');
          }
        });

        return Column(
          children: [
            // Sıralama butonları
            Row(
              children: [
                Text(
                  '${docs.length} sınıf atanmış',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Spacer(),
                // Sıralama toggle butonları
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSortButton('class', 'Sınıf', Icons.class_),
                      _buildSortButton('teacher', 'Öğretmen', Icons.person),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            // Liste
            ...docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return Card(
                margin: EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => _showEditAssignmentSheet(doc.id, data, lessonBranchName: lessonBranchName),
                  leading: CircleAvatar(
                    backgroundColor: Colors.green.shade100,
                    child: Icon(Icons.class_, color: Colors.green),
                  ),
                  title: Text(data['className'] ?? ''),
                  subtitle: Text(
                    '${data['weeklyHours']} saat/hafta • ${(data['teacherNames'] as List?)?.join(', ') ?? 'Öğretmen atanmamış'}',
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Atamayı Sil',
                    onPressed: () => _confirmDeleteAssignment(doc.id, data['className'] ?? ''),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  // Sınıf adlarını karşılaştır (sayısal ve alfabetik)
  int _compareClassNames(String a, String b) {
    // Sayısal kısımları ayır
    final numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), ''));
    final numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), ''));
    
    if (numA != null && numB != null) {
      final numCompare = numA.compareTo(numB);
      if (numCompare != 0) return numCompare;
    }
    
    // Sayısal eşitse veya sayı yoksa alfabetik
    return a.compareTo(b);
  }

  Widget _buildSortButton(String value, String label, IconData icon) {
    final isSelected = _assignmentSortBy == value;
    return InkWell(
      onTap: () => setState(() => _assignmentSortBy = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
            SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAssignment(String assignmentId, String className) {
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
          '"$className" sınıfına yapılan atamayı silmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('lessonAssignments')
                  .doc(assignmentId)
                  .update({'isActive': false});
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Atama silindi')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditAssignmentSheet(String assignmentId, Map<String, dynamic> data, {String? lessonBranchName}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditAssignmentSheet(
        assignmentId: assignmentId,
        data: data,
        lessonBranchName: lessonBranchName,
        teachers: _teachers,
        onSaved: () => setState(() {}),
      ),
    );
  }
}

// ==================== DERS FORM SHEET (PREMIUM) ====================
class _LessonFormSheet extends StatefulWidget {
  final String schoolTypeId;
  final String institutionId;
  final String? termId;
  final List<String> branchNames;
  final LessonModel? lessonToEdit;
  final VoidCallback onLessonSaved;

  const _LessonFormSheet({
    required this.schoolTypeId,
    required this.institutionId,
    this.termId,
    required this.branchNames,
    this.lessonToEdit,
    required this.onLessonSaved,
  });

  @override
  State<_LessonFormSheet> createState() => _LessonFormSheetState();
}

class _LessonFormSheetState extends State<_LessonFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _lessonNameController = TextEditingController();
  final _shortNameController = TextEditingController();
  String? _selectedBranchName;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.lessonToEdit != null) {
      _lessonNameController.text = widget.lessonToEdit!.lessonName;
      _shortNameController.text = widget.lessonToEdit!.shortName;
      _selectedBranchName = widget.lessonToEdit!.branchName;
    }
  }

  @override
  void dispose() {
    _lessonNameController.dispose();
    _shortNameController.dispose();
    super.dispose();
  }

  Future<void> _saveLesson() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBranchName == null || _selectedBranchName!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen bir branş seçin')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final activeTermId = await TermService().getActiveTermId();
      final lessonData = {
        'lessonName': _lessonNameController.text.trim(),
        'shortName': _shortNameController.text.trim().toUpperCase(),
        'branchId': _selectedBranchName,
        'branchName': _selectedBranchName,
        'schoolTypeId': widget.schoolTypeId,
        'institutionId': widget.institutionId,
        'termId': widget.lessonToEdit?.termId ?? activeTermId,
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.lessonToEdit != null) {
        await FirebaseFirestore.instance.collection('lessons').doc(widget.lessonToEdit!.id).update(lessonData);
      } else {
        lessonData['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('lessons').add(lessonData);
      }

      widget.onLessonSaved();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Ders başarıyla kaydedildi'), backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Hata: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.lessonToEdit == null ? 'Yeni Ders Ekle' : 'Dersi Düzenle', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  _buildField(controller: _lessonNameController, label: 'Ders Adı *', icon: Icons.book, validator: (v) => v?.isEmpty == true ? 'Zorunlu alan' : null),
                  const SizedBox(height: 16),
                  _buildField(controller: _shortNameController, label: 'Kısa Ad *', icon: Icons.short_text, maxLength: 4, hint: 'Örn: MAT, TUR'),
                  const SizedBox(height: 16),
                  _buildDropdown(),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveLesson,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade900, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('Kaydet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

  Widget _buildField({required TextEditingController controller, required String label, required IconData icon, int? maxLength, String? hint, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      maxLength: maxLength,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.indigo),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }

  Widget _buildDropdown() {
    return DropdownButtonFormField<String>(
      value: widget.branchNames.contains(_selectedBranchName) ? _selectedBranchName : null,
      decoration: InputDecoration(
        labelText: 'Branş *',
        prefixIcon: const Icon(Icons.category, color: Colors.indigo),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      items: widget.branchNames.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
      onChanged: (v) => setState(() => _selectedBranchName = v),
    );
  }
}

// ==================== SINIF ATAMA SHEET (PREMIUM) ====================
class _ClassAssignmentSheet extends StatefulWidget {
  final LessonModel lesson;
  final String schoolTypeId;
  final String institutionId;
  final List<Map<String, dynamic>> teachers;

  const _ClassAssignmentSheet({required this.lesson, required this.schoolTypeId, required this.institutionId, required this.teachers});

  @override
  State<_ClassAssignmentSheet> createState() => _ClassAssignmentSheetState();
}

class _ClassAssignmentSheetState extends State<_ClassAssignmentSheet> {
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _allTeachers = [];
  List<String> _selectedClassIds = [];
  List<Map<String, dynamic>> _assignments = [];
  bool _isLoading = true;
  bool _isSaving = false;
  int _step = 1;
  int? _selectedLevel;
  String? _selectedClassType;
  List<String> _classTypes = [];
  Set<int> _availableLevels = {};

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    try {
      final termId = await TermService().getSelectedTermId() ?? await TermService().getActiveTermId();
      final classSnap = await FirebaseFirestore.instance.collection('classes').where('schoolTypeId', isEqualTo: widget.schoolTypeId).where('institutionId', isEqualTo: widget.institutionId).where('isActive', isEqualTo: true).get();
      final classes = classSnap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      classes.sort((a, b) => (a['classLevel'] ?? 0).toString().compareTo((b['classLevel'] ?? 0).toString()));
      
      final userSnap = await FirebaseFirestore.instance.collection('users').where('institutionId', isEqualTo: widget.institutionId).where('type', isEqualTo: 'staff').where('isActive', isEqualTo: true).get();
      final teachers = userSnap.docs.where((d) => (d.data()['title'] ?? '').toString().toLowerCase() == 'ogretmen').map((d) => {...d.data(), 'id': d.id, 'totalHours': 0}).toList();

      if (mounted) setState(() { _classes = classes; _allTeachers = teachers; _classTypes = classes.map((c) => c['classTypeName'] as String?).whereType<String>().toSet().toList()..sort(); _availableLevels = classes.map((c) => (c['classLevel'] as int?) ?? 0).toSet(); _isLoading = false; });
    } catch (e) { print(e); if (mounted) setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Icon(Icons.assignment, color: Colors.indigo),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Sınıf Atama', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(widget.lesson.lessonName, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ])),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          if (_isLoading) const Expanded(child: Center(child: CircularProgressIndicator()))
          else Expanded(child: _step == 1 ? _buildStep1() : _buildStep2()),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                if (_step == 2) TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Geri')),
                const Spacer(),
                ElevatedButton(
                  onPressed: _isSaving ? null : (_step == 1 ? _proceedToStep2 : _save),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade900, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(_step == 1 ? 'İleri' : 'Atamaları Kaydet'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    final filtered = _classes.where((c) => (_selectedLevel == null || c['classLevel'] == _selectedLevel) && (_selectedClassType == null || c['classTypeName'] == _selectedClassType)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: [
            Expanded(child: _buildFilter('Seviye', _selectedLevel, _availableLevels.toList()..sort(), (v) => setState(() => _selectedLevel = v))),
            const SizedBox(width: 8),
            Expanded(child: _buildFilter('Tip', _selectedClassType, _classTypes, (v) => setState(() => _selectedClassType = v))),
          ]),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final c = filtered[i];
              final sel = _selectedClassIds.contains(c['id']);
              return Card(
                color: sel ? Colors.indigo.shade50 : null,
                child: CheckboxListTile(
                  value: sel,
                  title: Text(c['className'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${c['classLevel']}. Sınıf'),
                  onChanged: (v) => setState(() => v! ? _selectedClassIds.add(c['id']) : _selectedClassIds.remove(c['id'])),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilter<T>(String hint, T? val, List<T> items, ValueChanged<T?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: val != null ? Colors.indigo.shade50 : Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(child: DropdownButton<T>(value: val, hint: Text(hint, style: const TextStyle(fontSize: 12)), isExpanded: true, items: [DropdownMenuItem<T>(value: null, child: const Text('Tümü')), ...items.map((it) => DropdownMenuItem(value: it, child: Text(it.toString())))], onChanged: onChanged)),
    );
  }

  void _proceedToStep2() {
    if (_selectedClassIds.isEmpty) return;
    _assignments = _selectedClassIds.map((id) {
      final c = _classes.firstWhere((cl) => cl['id'] == id);
      return {'classId': id, 'className': c['className'], 'weeklyHours': 0, 'teacherIds': <String>[], 'teacherNames': <String>[]};
    }).toList();
    setState(() => _step = 2);
  }

  Widget _buildStep2() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _assignments.length,
      itemBuilder: (context, i) {
        final a = _assignments[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a['className'], style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(children: [
                SizedBox(width: 80, child: TextField(keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Saat', border: OutlineInputBorder()), onChanged: (v) => a['weeklyHours'] = int.tryParse(v) ?? 0)),
                const SizedBox(width: 12),
                Expanded(child: _buildTeacherPicker(i)),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildTeacherPicker(int index) {
    final selNames = List<String>.from(_assignments[index]['teacherNames']);
    return InkWell(
      onTap: () async {
        final res = await _showTeacherSheet(_assignments[index]['teacherIds']);
        if (res != null) setState(() { _assignments[index]['teacherIds'] = res['ids']; _assignments[index]['teacherNames'] = res['names']; });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
        child: Text(selNames.isEmpty ? 'Öğretmen seç...' : selNames.join(', '), overflow: TextOverflow.ellipsis, style: TextStyle(color: selNames.isEmpty ? Colors.grey : Colors.black87)),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showTeacherSheet(List<String> initialIds) async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TeacherPickerSheet(teachers: _allTeachers, initialIds: initialIds, lessonBranch: widget.lesson.branchName),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final termId = await TermService().getActiveTermId();
      for (var a in _assignments) {
        final ref = FirebaseFirestore.instance.collection('lessonAssignments').doc();
        batch.set(ref, {...a, 'lessonId': widget.lesson.id, 'lessonName': widget.lesson.lessonName, 'institutionId': widget.institutionId, 'schoolTypeId': widget.schoolTypeId, 'termId': termId, 'isActive': true, 'createdAt': FieldValue.serverTimestamp()});
      }
      await batch.commit();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Atamalar kaydedildi'), backgroundColor: Colors.green));
    } catch (e) { print(e); } finally { setState(() => _isSaving = false); }
  }
}

// ==================== ATAMA DÜZENLEME SHEET (PREMIUM) ====================
class _EditAssignmentSheet extends StatefulWidget {
  final String assignmentId;
  final Map<String, dynamic> data;
  final String? lessonBranchName;
  final List<Map<String, dynamic>> teachers;
  final VoidCallback onSaved;

  const _EditAssignmentSheet({required this.assignmentId, required this.data, this.lessonBranchName, required this.teachers, required this.onSaved});

  @override
  State<_EditAssignmentSheet> createState() => _EditAssignmentSheetState();
}

class _EditAssignmentSheetState extends State<_EditAssignmentSheet> {
  late TextEditingController _hoursController;
  late List<String> _teacherIds;
  late List<String> _teacherNames;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _hoursController = TextEditingController(text: widget.data['weeklyHours']?.toString() ?? '0');
    _teacherIds = List<String>.from(widget.data['teacherIds'] ?? []);
    _teacherNames = List<String>.from(widget.data['teacherNames'] ?? []);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [const Icon(Icons.edit, color: Colors.indigo), const SizedBox(width: 12), Text('${widget.data['className']} - Düzenle', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]),
                const SizedBox(height: 24),
                TextField(controller: _hoursController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Haftalık Ders Saati', prefixIcon: const Icon(Icons.timer), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final res = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => _TeacherPickerSheet(teachers: widget.teachers, initialIds: _teacherIds, lessonBranch: widget.lessonBranchName ?? ''));
                    if (res != null) setState(() { _teacherIds = res['ids']; _teacherNames = res['names']; });
                  },
                  child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.person, color: Colors.indigo), const SizedBox(width: 12), Expanded(child: Text(_teacherNames.isEmpty ? 'Öğretmen seç...' : _teacherNames.join(', '), overflow: TextOverflow.ellipsis)), const Icon(Icons.arrow_drop_down)])),
                ),
                const SizedBox(height: 32),
                SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: _isSaving ? null : _save, style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade900, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('Güncelle', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('lessonAssignments').doc(widget.assignmentId).update({'weeklyHours': int.tryParse(_hoursController.text) ?? 0, 'teacherIds': _teacherIds, 'teacherNames': _teacherNames});
      widget.onSaved();
      Navigator.pop(context);
    } catch (e) { print(e); } finally { if (mounted) setState(() => _isSaving = false); }
  }
}

// ==================== DERS DETAY SAYFASI (MOBİL) ====================
class _LessonDetailPage extends StatelessWidget {
  final LessonModel lesson;
  final List<Map<String, dynamic>> teachers;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAssign;

  const _LessonDetailPage({
    required this.lesson,
    required this.teachers,
    required this.onEdit,
    required this.onDelete,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(lesson.lessonName),
        actions: [
          IconButton(
            icon: Icon(Icons.edit),
            onPressed: onEdit,
          ),
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: onDelete,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onAssign,
        icon: Icon(Icons.add),
        label: Text('Sınıf Ata'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.indigo.shade100,
                      child: Icon(Icons.book, size: 28, color: Colors.indigo),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lesson.lessonName,
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            lesson.branchName,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Atanan Sınıflar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('lessonAssignments')
                  .where('lessonId', isEqualTo: lesson.id)
                  .where('isActive', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Bu ders henüz hiçbir sınıfa atanmamış',
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
                          child: Icon(Icons.class_, color: Colors.green),
                        ),
                        title: Text(data['className'] ?? ''),
                        subtitle: Text(
                          '${data['weeklyHours']} saat/hafta • ${(data['teacherNames'] as List?)?.join(', ') ?? 'Öğretmen atanmamış'}',
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () async {
                            await FirebaseFirestore.instance
                                .collection('lessonAssignments')
                                .doc(doc.id)
                                .update({'isActive': false});
                          },
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== BRANŞ YÖNETİM SHEET (PREMIUM) ====================
class _BranchManagementSheet extends StatefulWidget {
  final String institutionId;
  final VoidCallback onBranchesChanged;

  const _BranchManagementSheet({required this.institutionId, required this.onBranchesChanged});

  @override
  State<_BranchManagementSheet> createState() => _BranchManagementSheetState();
}

class _BranchManagementSheetState extends State<_BranchManagementSheet> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _allBranches = [];
  bool _isLoading = true;

  static const List<String> _defaultBranches = [
    'Almanca', 'Arapça', 'Beden Eğitimi ve Spor', 'Bilişim Teknolojileri ve Yazılım',
    'Biyoloji', 'Coğrafya', 'Din Kültürü ve Ahlak Bilgisi', 'Felsefe', 'Fen Bilimleri',
    'Fizik', 'Fransızca', 'Görsel Sanatlar', 'İlköğretim Matematik', 'İngilizce',
    'İspanyolca', 'Kimya', 'Kulüp', 'Matematik', 'Müzik', 'Okul Öncesi', 'Özel Eğitim',
    'Rehberlik ve Psikolojik Danışmanlık', 'Rusça', 'Sınıf Öğretmenliği', 'Sosyal Bilgiler',
    'Tarih', 'Teknoloji ve Tasarım', 'Türk Dili ve Edebiyatı', 'Türkçe',
  ];

  @override
  void initState() {
    super.initState();
    _loadAllBranches();
  }

  Future<void> _loadAllBranches() async {
    final branches = <Map<String, dynamic>>[];
    for (var name in _defaultBranches) {
      branches.add({'id': null, 'branchName': name, 'isDefault': true});
    }
    try {
      final customBranches = await FirebaseFirestore.instance.collection('branches').where('institutionId', isEqualTo: widget.institutionId) .where('isActive', isEqualTo: true).get();
      for (var doc in customBranches.docs) {
        final name = doc.data()['branchName'] as String?;
        if (name != null && !_defaultBranches.contains(name)) {
          branches.add({'id': doc.id, 'branchName': name, 'isDefault': false});
        }
      }
    } catch (e) { print(e); }
    branches.sort((a, b) => (a['branchName'] as String).compareTo(b['branchName'] as String));
    if (mounted) setState(() { _allBranches = branches; _isLoading = false; });
  }

  Future<void> _addBranch() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('branches').add({'branchName': name, 'institutionId': widget.institutionId, 'isDefault': false, 'isActive': true});
      _controller.clear();
      widget.onBranchesChanged();
      _loadAllBranches();
    } catch (e) { print(e); }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Icon(Icons.category, color: Colors.indigo),
                const SizedBox(width: 12),
                const Text('Branş Yönetimi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _controller, decoration: InputDecoration(hintText: 'Yeni branş...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey.shade50))),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _addBranch, icon: const Icon(Icons.add), style: IconButton.styleFrom(backgroundColor: Colors.indigo)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
              itemCount: _allBranches.length,
              itemBuilder: (context, index) {
                final b = _allBranches[index];
                final isDefault = b['isDefault'] == true;
                return ListTile(
                  leading: CircleAvatar(backgroundColor: isDefault ? Colors.indigo.shade50 : Colors.orange.shade50, child: Icon(Icons.category, size: 18, color: isDefault ? Colors.indigo : Colors.orange)),
                  title: Text(b['branchName'] ?? ''),
                  subtitle: Text(isDefault ? 'Varsayılan' : 'Özel', style: const TextStyle(fontSize: 11)),
                  trailing: isDefault ? null : IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => _deleteBranch(b['id'])),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteBranch(String id) async {
    await FirebaseFirestore.instance.collection('branches').doc(id).update({'isActive': false});
    widget.onBranchesChanged();
    _loadAllBranches();
  }
}

// ==================== ÖĞRETMEN SEÇİM SHEET (PREMIUM) ====================
class _TeacherPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> teachers;
  final List<String> initialIds;
  final String lessonBranch;
  const _TeacherPickerSheet({required this.teachers, required this.initialIds, required this.lessonBranch});
  @override
  State<_TeacherPickerSheet> createState() => _TeacherPickerSheetState();
}

class _TeacherPickerSheetState extends State<_TeacherPickerSheet> {
  late List<String> _selIds;
  @override
  void initState() { super.initState(); _selIds = List.from(widget.initialIds); }
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.all(24), child: Row(children: [const Text('Öğretmen Seç', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const Spacer(), Text('${_selIds.length} seçili', style: const TextStyle(color: Colors.indigo))])),
        Expanded(child: ListView.builder(
          itemCount: widget.teachers.length,
          itemBuilder: (context, i) {
            final t = widget.teachers[i];
            final sel = _selIds.contains(t['id']);
            final isMatch = t['branch'] == widget.lessonBranch;
            return CheckboxListTile(
              value: sel,
              title: Text(t['fullName'] ?? ''),
              subtitle: Text(t['branch'] ?? '', style: TextStyle(color: isMatch ? Colors.green : null)),
              onChanged: (v) => setState(() => v! ? _selIds.add(t['id']) : _selIds.remove(t['id'])),
            );
          },
        )),
        Padding(padding: const EdgeInsets.all(24), child: SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: () {
          final names = _selIds.map((id) => widget.teachers.firstWhere((t) => t['id'] == id)['fullName'] as String).toList();
          Navigator.pop(context, {'ids': _selIds, 'names': names});
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white), child: const Text('Tamam')))),
      ]),
    );
  }
}
