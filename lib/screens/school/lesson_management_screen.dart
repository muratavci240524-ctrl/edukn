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

  void _showLessonFormDialog({LessonModel? lessonToEdit}) {
    showDialog(
      context: context,
      builder: (context) => _LessonFormDialog(
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

  void _showClassAssignmentDialog(LessonModel lesson) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ClassAssignmentDialog(
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ders Listesi'),
            Text(
              widget.schoolTypeName,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          Container(
            margin: EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: () => _showBranchManagementDialog(),
              icon: Icon(Icons.category, size: 18),
              label: Text('Branş Yönetimi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.indigo,
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _isViewingPastTerm
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showLessonFormDialog(),
              icon: Icon(Icons.add),
              label: Text('Yeni Ders'),
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
                  onPressed: () => _showLessonFormDialog(),
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
                          onEdit: () => _showLessonFormDialog(lessonToEdit: lesson),
                          onDelete: () => _deleteLesson(lesson.id!, lesson.lessonName),
                          onAssign: () => _showClassAssignmentDialog(lesson),
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
                  _showLessonFormDialog(lessonToEdit: lesson);
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
              _showClassAssignmentDialog(lesson);
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
                  onTap: () => _showEditAssignmentDialog(doc.id, data, lessonBranchName: lessonBranchName),
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

  void _showEditAssignmentDialog(String assignmentId, Map<String, dynamic> data, {String? lessonBranchName}) {
    final hoursController = TextEditingController(text: data['weeklyHours']?.toString() ?? '0');
    List<String> selectedTeacherIds = List<String>.from(data['teacherIds'] ?? []);
    List<String> selectedTeacherNames = List<String>.from(data['teacherNames'] ?? []);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.edit, color: Colors.indigo),
              SizedBox(width: 12),
              Expanded(child: Text('${data['className']} - Düzenle')),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ders Saati
                Text('Haftalık Ders Saati', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                SizedBox(height: 8),
                TextFormField(
                  controller: hoursController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                    suffixText: 'saat',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                SizedBox(height: 16),
                
                // Öğretmenler
                Text('Öğretmen(ler)', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final result = await _showTeacherPickerDialog(
                      selectedTeacherIds, 
                      lessonBranchName: lessonBranchName,
                    );
                    if (result != null) {
                      setDialogState(() {
                        selectedTeacherIds = result['ids'];
                        selectedTeacherNames = result['names'];
                      });
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person, size: 20, color: Colors.grey),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedTeacherNames.isEmpty 
                                ? 'Öğretmen seç...' 
                                : selectedTeacherNames.join(', '),
                            style: TextStyle(
                              color: selectedTeacherNames.isEmpty ? Colors.grey : Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('İptal'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('lessonAssignments')
                    .doc(assignmentId)
                    .update({
                  'weeklyHours': int.tryParse(hoursController.text) ?? 0,
                  'teacherIds': selectedTeacherIds,
                  'teacherNames': selectedTeacherNames,
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Atama güncellendi'), backgroundColor: Colors.green),
                );
              },
              icon: Icon(Icons.save),
              label: Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showTeacherPickerDialog(List<String> initialSelectedIds, {String? lessonBranchName}) async {
    List<String> selectedIds = List.from(initialSelectedIds);
    
    // Öğretmenleri yükle
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('type', isEqualTo: 'staff')
        .where('isActive', isEqualTo: true)
        .get();

    final allTeachers = snapshot.docs.where((doc) {
      final data = doc.data();
      final title = (data['title'] ?? '').toString().toLowerCase();
      return title == 'ogretmen';
    }).map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'fullName': data['fullName'] ?? '',
        'branch': data['branch'] ?? '',
      };
    }).toList();

    // Branşa göre sırala - dersin branşına ait öğretmenler önce
    final teachers = [...allTeachers];
    if (lessonBranchName != null && lessonBranchName.isNotEmpty) {
      teachers.sort((a, b) {
        final aBranch = (a['branch'] ?? '').toString();
        final bBranch = (b['branch'] ?? '').toString();
        final aMatch = aBranch == lessonBranchName;
        final bMatch = bBranch == lessonBranchName;
        if (aMatch && !bMatch) return -1;
        if (!aMatch && bMatch) return 1;
        return (a['fullName'] as String).compareTo(b['fullName'] as String);
      });
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.person, color: Colors.indigo),
              SizedBox(width: 12),
              Text('Öğretmen Seç'),
              Spacer(),
              Text(
                '${selectedIds.length} seçili',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          content: SizedBox(
            width: 350,
            height: 400,
            child: teachers.isEmpty
                ? Center(child: Text('Kayıtlı öğretmen bulunamadı'))
                : ListView.builder(
                    itemCount: teachers.length,
                    itemBuilder: (context, index) {
                      final teacher = teachers[index];
                      final isSelected = selectedIds.contains(teacher['id']);
                      final teacherBranch = (teacher['branch'] ?? '').toString();
                      final isMatchingBranch = lessonBranchName != null && teacherBranch == lessonBranchName;
                      
                      return Container(
                        margin: EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: isMatchingBranch ? Colors.green.shade50 : null,
                          borderRadius: BorderRadius.circular(8),
                          border: isMatchingBranch ? Border.all(color: Colors.green.shade200) : null,
                        ),
                        child: CheckboxListTile(
                          value: isSelected,
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                selectedIds.add(teacher['id'] as String);
                              } else {
                                selectedIds.remove(teacher['id']);
                              }
                            });
                          },
                          secondary: CircleAvatar(
                            backgroundColor: isMatchingBranch ? Colors.green : Colors.grey.shade300,
                            child: Text(
                              (teacher['fullName'] as String).isNotEmpty 
                                  ? (teacher['fullName'] as String)[0].toUpperCase()
                                  : '?',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(
                            teacher['fullName'] as String,
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            teacherBranch.isNotEmpty ? teacherBranch : 'Branş belirtilmemiş',
                            style: TextStyle(
                              fontSize: 12,
                              color: isMatchingBranch ? Colors.green.shade700 : Colors.grey,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final names = selectedIds.map((id) {
                  final t = teachers.firstWhere((t) => t['id'] == id, orElse: () => {'fullName': ''});
                  return t['fullName'] as String;
                }).toList();
                Navigator.pop(context, {'ids': selectedIds, 'names': names});
              },
              child: Text('✓ Tamam (${selectedIds.length})'),
            ),
          ],
        ),
      ),
    );
  }

  void _showBranchManagementDialog() {
    showDialog(
      context: context,
      builder: (context) => _BranchManagementDialog(
        institutionId: widget.institutionId,
        onBranchesChanged: _loadBranchNames,
      ),
    );
  }
}

// ==================== DERS FORM DIALOG ====================
class _LessonFormDialog extends StatefulWidget {
  final String schoolTypeId;
  final String institutionId;
  final String? termId;
  final List<String> branchNames;
  final LessonModel? lessonToEdit;
  final VoidCallback onLessonSaved;

  const _LessonFormDialog({
    required this.schoolTypeId,
    required this.institutionId,
    this.termId,
    required this.branchNames,
    this.lessonToEdit,
    required this.onLessonSaved,
  });

  @override
  State<_LessonFormDialog> createState() => _LessonFormDialogState();
}

class _LessonFormDialogState extends State<_LessonFormDialog> {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lütfen bir branş seçin')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Yeni kayıtlar için aktif dönemi otomatik al
      final activeTermId = await TermService().getActiveTermId();
      
      final lessonData = {
        'lessonName': _lessonNameController.text.trim(),
        'shortName': _shortNameController.text.trim().toUpperCase(),
        'branchId': _selectedBranchName, // Branş adını ID olarak da kullan
        'branchName': _selectedBranchName,
        'schoolTypeId': widget.schoolTypeId,
        'institutionId': widget.institutionId,
        'termId': widget.lessonToEdit?.termId ?? activeTermId,
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.lessonToEdit != null) {
        await FirebaseFirestore.instance
            .collection('lessons')
            .doc(widget.lessonToEdit!.id)
            .update(lessonData);
      } else {
        lessonData['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('lessons').add(lessonData);
      }

      widget.onLessonSaved();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ders kaydedildi')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.lessonToEdit != null ? 'Ders Düzenle' : 'Yeni Ders Ekle'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _lessonNameController,
                decoration: InputDecoration(
                  labelText: 'Ders Adı *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.book),
                ),
                validator: (v) => v?.isEmpty == true ? 'Ders adı gerekli' : null,
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _shortNameController,
                decoration: InputDecoration(
                  labelText: 'Kısa Adı *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.short_text),
                  helperText: 'En fazla 4 karakter (örn: MAT, TUR, FEN)',
                  counterText: '${_shortNameController.text.length}/4',
                ),
                maxLength: 4,
                textCapitalization: TextCapitalization.characters,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Kısa ad gerekli';
                  if (v.length > 4) return 'En fazla 4 karakter';
                  return null;
                },
                onChanged: (v) => setState(() {}),
              ),
              SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: widget.branchNames.contains(_selectedBranchName) ? _selectedBranchName : null,
                decoration: InputDecoration(
                  labelText: 'Branş *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                  helperText: 'Yeni branş eklemek için AppBar\'daki "Branş Yönetimi" butonunu kullanın',
                  helperStyle: TextStyle(fontSize: 11),
                ),
                items: widget.branchNames.map((name) {
                  return DropdownMenuItem(
                    value: name,
                    child: Text(name),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedBranchName = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveLesson,
          child: _isSaving
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Kaydet'),
        ),
      ],
    );
  }
}

// ==================== SINIF ATAMA DIALOG ====================
class _ClassAssignmentDialog extends StatefulWidget {
  final LessonModel lesson;
  final String schoolTypeId;
  final String institutionId;
  final List<Map<String, dynamic>> teachers;

  const _ClassAssignmentDialog({
    required this.lesson,
    required this.schoolTypeId,
    required this.institutionId,
    required this.teachers,
  });

  @override
  State<_ClassAssignmentDialog> createState() => _ClassAssignmentDialogState();
}

class _ClassAssignmentDialogState extends State<_ClassAssignmentDialog> {
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _allTeachers = [];
  List<String> _selectedClassIds = [];
  List<Map<String, dynamic>> _assignments = [];
  bool _isLoading = true;
  bool _isSaving = false;
  int _step = 1;
  
  // Filtreler
  int? _selectedLevel;
  String? _selectedClassType;
  List<String> _classTypes = [];
  Set<int> _availableLevels = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadClasses(),
      _loadTeachers(),
    ]);
  }

  Future<void> _loadClasses() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final classes = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      
      // Client-side sıralama
      classes.sort((a, b) {
        final levelA = (a['classLevel'] ?? 0) is int ? a['classLevel'] : int.tryParse(a['classLevel'].toString()) ?? 0;
        final levelB = (b['classLevel'] ?? 0) is int ? b['classLevel'] : int.tryParse(b['classLevel'].toString()) ?? 0;
        final levelCompare = levelA.compareTo(levelB);
        if (levelCompare != 0) return levelCompare;
        return (a['className'] ?? '').toString().compareTo((b['className'] ?? '').toString());
      });

      // Filtreleme seçeneklerini çıkar
      final types = <String>{};
      final levels = <int>{};
      for (var c in classes) {
        if (c['classTypeName'] != null) types.add(c['classTypeName']);
        final level = c['classLevel'];
        if (level != null) {
          levels.add(level is int ? level : int.tryParse(level.toString()) ?? 0);
        }
      }

      setState(() {
        _classes = classes;
        _classTypes = types.toList()..sort();
        _availableLevels = levels;
        _isLoading = false;
      });
    } catch (e) {
      print('Sınıf yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTeachers() async {
    try {
      // Seçili veya aktif dönemi al
      final selectedTermId = await TermService().getSelectedTermId();
      final activeTermId = await TermService().getActiveTermId();
      final effectiveTermId = selectedTermId ?? activeTermId;
      
      print('📚 Öğretmenler yükleniyor - effectiveTermId: $effectiveTermId');
      
      // users koleksiyonundan öğretmenleri çek (sınıf yönetimi ile aynı)
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('type', isEqualTo: 'staff')
          .where('isActive', isEqualTo: true)
          .get();

      // Sadece öğretmenleri filtrele
      final teachers = snapshot.docs.where((doc) {
        final data = doc.data();
        final title = (data['title'] ?? '').toString().toLowerCase();
        return title == 'ogretmen';
      }).map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'fullName': data['fullName'] ?? '',
          'branch': data['branch'] ?? '',
          'title': data['title'] ?? '',
          'totalHours': 0, // Başlangıçta 0
        };
      }).toList();

      // Öğretmenlerin toplam ders saatlerini hesapla - DÖNEM FİLTRELİ
      final activeLessonsSnapshot = await FirebaseFirestore.instance
          .collection('lessons')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();
      final activeLessonIds = activeLessonsSnapshot.docs.map((d) => d.id).toSet();

      final assignmentsSnapshot = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      // Her öğretmenin toplam saatini hesapla - DÖNEM FİLTRELİ
      final Map<String, int> teacherHours = {};
      for (var doc in assignmentsSnapshot.docs) {
        final data = doc.data();
        
        // Dönem filtresi uygula
        final assignmentTermId = data['termId'] as String?;
        if (effectiveTermId != null && assignmentTermId != effectiveTermId) {
          // Bu atama farklı döneme ait, atla
          continue;
        }

        final lessonId = (data['lessonId'] ?? '').toString();
        if (lessonId.isEmpty || !activeLessonIds.contains(lessonId)) {
          continue;
        }
        
        final teacherIds = List<String>.from(data['teacherIds'] ?? []);

        final dynamic weeklyHoursRaw = data['weeklyHours'];
        final int weeklyHours = weeklyHoursRaw is int
            ? weeklyHoursRaw
            : int.tryParse((weeklyHoursRaw ?? '').toString()) ?? 0;

        if (weeklyHours <= 0) continue;
        
        for (var teacherId in teacherIds) {
          teacherHours[teacherId] = (teacherHours[teacherId] ?? 0) + weeklyHours;
        }
      }

      // Öğretmenlere toplam saatleri ekle
      for (var teacher in teachers) {
        teacher['totalHours'] = teacherHours[teacher['id']] ?? 0;
      }
      
      print('✅ ${teachers.length} öğretmen yüklendi (dönem filtreli ders saatleri)');

      setState(() {
        _allTeachers = teachers;
      });
    } catch (e) {
      print('Öğretmen yükleme hatası: $e');
    }
  }

  List<Map<String, dynamic>> get _filteredClasses {
    return _classes.where((c) {
      if (_selectedLevel != null) {
        final level = c['classLevel'];
        final classLevel = level is int ? level : int.tryParse(level.toString()) ?? 0;
        if (classLevel != _selectedLevel) return false;
      }
      if (_selectedClassType != null && c['classTypeName'] != _selectedClassType) {
        return false;
      }
      return true;
    }).toList();
  }

  void _proceedToDetails() {
    if (_selectedClassIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lütfen en az bir sınıf seçin')),
      );
      return;
    }

    // Seçilen sınıflar için atama listesi oluştur
    _assignments = _selectedClassIds.map((classId) {
      final classData = _classes.firstWhere((c) => c['id'] == classId);
      return {
        'classId': classId,
        'className': classData['className'],
        'weeklyHours': 0,
        'teacherIds': <String>[],
        'teacherNames': <String>[],
      };
    }).toList();

    setState(() => _step = 2);
  }

  Future<void> _saveAssignments() async {
    // Validasyon
    for (var assignment in _assignments) {
      if (assignment['weeklyHours'] == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${assignment['className']} için ders saati giriniz')),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      // Aktif dönemi al
      final activeTermId = await TermService().getActiveTermId();
      
      final batch = FirebaseFirestore.instance.batch();

      for (var assignment in _assignments) {
        final docRef = FirebaseFirestore.instance.collection('lessonAssignments').doc();
        batch.set(docRef, {
          'lessonId': widget.lesson.id,
          'lessonName': widget.lesson.lessonName,
          'classId': assignment['classId'],
          'className': assignment['className'],
          'weeklyHours': assignment['weeklyHours'],
          'teacherIds': assignment['teacherIds'],
          'teacherNames': assignment['teacherNames'],
          'schoolTypeId': widget.schoolTypeId,
          'institutionId': widget.institutionId,
          'termId': activeTermId,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_assignments.length} sınıfa atama yapıldı')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 700,
        height: 600,
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık
            Row(
              children: [
                Icon(Icons.assignment, color: Colors.indigo),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sınıf Atama',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.lesson.lessonName,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close),
                ),
              ],
            ),
            Divider(height: 32),

            // Step indicator
            Row(
              children: [
                _buildStepIndicator(1, 'Sınıf Seçimi'),
                Expanded(child: Divider()),
                _buildStepIndicator(2, 'Detay Girişi'),
              ],
            ),
            SizedBox(height: 24),

            // İçerik
            Expanded(
              child: _step == 1 ? _buildClassSelection() : _buildDetailsEntry(),
            ),

            // Butonlar
            Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_step == 2)
                  TextButton(
                    onPressed: () => setState(() => _step = 1),
                    child: Text('Geri'),
                  ),
                SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('İptal'),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isSaving
                      ? null
                      : (_step == 1 ? _proceedToDetails : _saveAssignments),
                  child: _isSaving
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_step == 1 ? 'İleri' : 'Kaydet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label) {
    final isActive = _step >= step;
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: isActive ? Colors.indigo : Colors.grey.shade300,
          child: Text(
            '$step',
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
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? Colors.indigo : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildClassSelection() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (_classes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.class_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Bu okul türünde henüz sınıf tanımlanmamış'),
          ],
        ),
      );
    }

    final filtered = _filteredClasses;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filtreler - Kompakt
        Row(
          children: [
            // Sınıf Seviyesi Filtresi
            Expanded(
              child: Container(
                height: 36,
                padding: EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _selectedLevel != null ? Colors.indigo : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedLevel,
                    hint: Text('Seviye', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                    icon: Icon(Icons.arrow_drop_down, size: 20, color: _selectedLevel != null ? Colors.white : Colors.grey.shade700),
                    dropdownColor: Colors.white,
                    isExpanded: true,
                    isDense: true,
                    selectedItemBuilder: (context) {
                      return [
                        Align(alignment: Alignment.centerLeft, child: Text('Seviye', style: TextStyle(color: Colors.grey.shade700, fontSize: 12))),
                        ...(_availableLevels.toList()..sort()).map((l) => 
                          Align(alignment: Alignment.centerLeft, child: Text('$l. Sınıf', style: TextStyle(color: Colors.white, fontSize: 12)))
                        ),
                      ];
                    },
                    items: [
                      DropdownMenuItem<int>(value: null, child: Text('Tümü', style: TextStyle(color: Colors.black87, fontSize: 13))),
                      ...(_availableLevels.toList()..sort()).map((level) => 
                        DropdownMenuItem(value: level, child: Text('$level. Sınıf', style: TextStyle(color: Colors.black87, fontSize: 13)))
                      ),
                    ],
                    onChanged: (value) => setState(() => _selectedLevel = value),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),
            // Sınıf Tipi Filtresi
            Expanded(
              child: Container(
                height: 36,
                padding: EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _selectedClassType != null ? Colors.indigo : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedClassType,
                    hint: Text('Tip', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                    icon: Icon(Icons.arrow_drop_down, size: 20, color: _selectedClassType != null ? Colors.white : Colors.grey.shade700),
                    dropdownColor: Colors.white,
                    isExpanded: true,
                    isDense: true,
                    selectedItemBuilder: (context) {
                      return [
                        Align(alignment: Alignment.centerLeft, child: Text('Tip', style: TextStyle(color: Colors.grey.shade700, fontSize: 12))),
                        ..._classTypes.map((t) => 
                          Align(alignment: Alignment.centerLeft, child: Text(t, style: TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis))
                        ),
                      ];
                    },
                    items: [
                      DropdownMenuItem<String>(value: null, child: Text('Tümü', style: TextStyle(color: Colors.black87, fontSize: 13))),
                      ..._classTypes.map((type) => DropdownMenuItem(value: type, child: Text(type, style: TextStyle(color: Colors.black87, fontSize: 13)))),
                    ],
                    onChanged: (value) => setState(() => _selectedClassType = value),
                  ),
                ),
              ),
            ),
            // Filtreleri temizle butonu
            if (_selectedLevel != null || _selectedClassType != null) ...[
              SizedBox(width: 6),
              InkWell(
                onTap: () => setState(() {
                  _selectedLevel = null;
                  _selectedClassType = null;
                }),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.clear, size: 18, color: Colors.grey.shade700),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 12),
        
        // Seçim bilgisi ve Tümünü Seç
        Row(
          children: [
            Text(
              '${filtered.length} sınıf listeleniyor',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            SizedBox(width: 12),
            // Tümünü Seç / Seçimi Kaldır butonu
            if (filtered.isNotEmpty)
              InkWell(
                onTap: () {
                  setState(() {
                    final filteredIds = filtered.map((c) => c['id'] as String).toList();
                    final allSelected = filteredIds.every((id) => _selectedClassIds.contains(id));
                    if (allSelected) {
                      // Tümünü kaldır
                      _selectedClassIds.removeWhere((id) => filteredIds.contains(id));
                    } else {
                      // Tümünü seç
                      for (var id in filteredIds) {
                        if (!_selectedClassIds.contains(id)) {
                          _selectedClassIds.add(id);
                        }
                      }
                    }
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        filtered.every((c) => _selectedClassIds.contains(c['id'])) 
                            ? Icons.deselect 
                            : Icons.select_all,
                        size: 14,
                        color: Colors.green.shade700,
                      ),
                      SizedBox(width: 4),
                      Text(
                        filtered.every((c) => _selectedClassIds.contains(c['id'])) 
                            ? 'Seçimi Kaldır' 
                            : 'Tümünü Seç',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Spacer(),
            if (_selectedClassIds.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.indigo,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_selectedClassIds.length} seçili',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
          ],
        ),
        SizedBox(height: 8),
        
        // Sınıf Listesi
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text('Filtrelere uygun sınıf bulunamadı'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final classData = filtered[index];
                    final isSelected = _selectedClassIds.contains(classData['id']);

                    return Card(
                      margin: EdgeInsets.only(bottom: 8),
                      color: isSelected ? Colors.indigo.shade50 : null,
                      child: CheckboxListTile(
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedClassIds.add(classData['id']);
                            } else {
                              _selectedClassIds.remove(classData['id']);
                            }
                          });
                        },
                        title: Text(
                          classData['className'] ?? '',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${classData['classLevel']}. Sınıf • ${classData['classTypeName'] ?? ''}',
                          style: TextStyle(fontSize: 12),
                        ),
                        secondary: CircleAvatar(
                          backgroundColor: isSelected ? Colors.indigo : Colors.grey.shade300,
                          child: Text(
                            '${classData['classLevel']}',
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.grey.shade700,
                              fontWeight: FontWeight.bold,
                            ),
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

  Widget _buildDetailsEntry() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Başlık
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.green.shade700, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Her sınıf için haftalık ders saati ve öğretmen atayın',
                  style: TextStyle(color: Colors.green.shade700, fontSize: 13),
                ),
              ),
              Text(
                '${_allTeachers.length} öğretmen mevcut',
                style: TextStyle(color: Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        
        // Atama Listesi
        Expanded(
          child: ListView.builder(
            itemCount: _assignments.length,
            itemBuilder: (context, index) {
              final assignment = _assignments[index];
              return Card(
                margin: EdgeInsets.only(bottom: 16),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sınıf Başlığı
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.indigo.shade100,
                            child: Icon(Icons.class_, size: 18, color: Colors.indigo),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              assignment['className'],
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          // Durum göstergesi
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: assignment['weeklyHours'] > 0 
                                  ? Colors.green.shade100 
                                  : Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              assignment['weeklyHours'] > 0 
                                  ? '${assignment['weeklyHours']} saat' 
                                  : 'Saat girilmedi',
                              style: TextStyle(
                                fontSize: 11,
                                color: assignment['weeklyHours'] > 0 
                                    ? Colors.green.shade700 
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Divider(height: 24),
                      
                      // Ders Saati ve Öğretmen
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Ders Saati (dar alan - max 3 hane)
                          SizedBox(
                            width: 90,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Saat/Hafta',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                ),
                                SizedBox(height: 6),
                                TextFormField(
                                  initialValue: assignment['weeklyHours'] > 0
                                      ? assignment['weeklyHours'].toString()
                                      : '',
                                  decoration: InputDecoration(
                                    hintText: '0',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  keyboardType: TextInputType.number,
                                  maxLength: 3,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                                  onChanged: (value) {
                                    setState(() {
                                      _assignments[index]['weeklyHours'] = int.tryParse(value) ?? 0;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 12),
                          
                          // Öğretmen Seçimi
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Öğretmen(ler)',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                ),
                                SizedBox(height: 6),
                                _buildTeacherMultiSelect(index),
                              ],
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

  Widget _buildTeacherMultiSelect(int assignmentIndex) {
    final selectedIds = List<String>.from(_assignments[assignmentIndex]['teacherIds']);
    
    return InkWell(
      onTap: () => _showTeacherSelectionDialog(assignmentIndex),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade50,
        ),
        child: selectedIds.isEmpty
            ? Row(
                children: [
                  Icon(Icons.person_add, size: 18, color: Colors.grey),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Öğretmen seç...',
                      style: TextStyle(color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: selectedIds.map((id) {
                  final teacher = _allTeachers.firstWhere(
                    (t) => t['id'] == id,
                    orElse: () => {'fullName': 'Bilinmiyor'},
                  );
                  return Chip(
                    label: Text(teacher['fullName'] ?? '', style: TextStyle(fontSize: 12)),
                    avatar: CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.indigo.shade100,
                      child: Text(
                        (teacher['fullName'] ?? 'B')[0].toUpperCase(),
                        style: TextStyle(fontSize: 10, color: Colors.indigo),
                      ),
                    ),
                    deleteIcon: Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _assignments[assignmentIndex]['teacherIds'].remove(id);
                        _assignments[assignmentIndex]['teacherNames'].remove(teacher['fullName']);
                      });
                    },
                    backgroundColor: Colors.indigo.shade50,
                  );
                }).toList(),
              ),
      ),
    );
  }

  Future<void> _showTeacherSelectionDialog(int assignmentIndex) async {
    final selectedIds = List<String>.from(_assignments[assignmentIndex]['teacherIds']);
    final lessonBranchName = widget.lesson.branchName;
    final currentAssignmentHours = _assignments[assignmentIndex]['weeklyHours'] as int? ?? 0;
    
    print('🔍 Öğretmen seçimi - Ders branşı: "$lessonBranchName", Saat: $currentAssignmentHours');
    
    // Öğretmenleri ve güncel ders saatlerini yeniden yükle
    await _loadTeachers();
    
    // Henüz kaydedilmemiş atamalardaki saatleri de ekle
    // (Mevcut dialog'daki diğer atamalarda seçili öğretmenlerin saatlerini hesapla)
    final Map<String, int> pendingHours = {};
    for (int i = 0; i < _assignments.length; i++) {
      if (i == assignmentIndex) continue; // Şu anki atamayı atla
      final assignmentTeacherIds = List<String>.from(_assignments[i]['teacherIds'] ?? []);
      final hours = _assignments[i]['weeklyHours'] as int? ?? 0;
      for (var teacherId in assignmentTeacherIds) {
        pendingHours[teacherId] = (pendingHours[teacherId] ?? 0) + hours;
      }
    }
    
    // Öğretmenleri branşa göre grupla ve pending saatleri ekle
    final Map<String, List<Map<String, dynamic>>> teachersByBranch = {};
    for (var teacher in _allTeachers) {
      final branch = (teacher['branch'] ?? '').toString();
      final branchKey = branch.isEmpty ? 'Branş Belirtilmemiş' : branch;
      teachersByBranch.putIfAbsent(branchKey, () => []);
      // Pending saatleri ekle
      final teacherWithPending = Map<String, dynamic>.from(teacher);
      teacherWithPending['totalHours'] = (teacher['totalHours'] ?? 0) + (pendingHours[teacher['id']] ?? 0);
      teachersByBranch[branchKey]!.add(teacherWithPending);
    }
    
    print('📚 Bulunan branşlar: ${teachersByBranch.keys.toList()}');
    
    // Branşları alfabetik sırala, ama dersin branşı en üstte olsun
    final sortedBranches = teachersByBranch.keys.toList();
    sortedBranches.sort((a, b) {
      // Dersin branşı en üstte
      if (lessonBranchName != null && lessonBranchName.isNotEmpty) {
        if (a == lessonBranchName) return -1;
        if (b == lessonBranchName) return 1;
      }
      // "Branş Belirtilmemiş" en altta
      if (a == 'Branş Belirtilmemiş') return 1;
      if (b == 'Branş Belirtilmemiş') return -1;
      // Diğerleri alfabetik
      return a.compareTo(b);
    });
    
    print('📋 Sıralanmış branşlar: $sortedBranches');
    
    // Her branş içindeki öğretmenleri alfabetik sırala
    for (var branch in teachersByBranch.keys) {
      teachersByBranch[branch]!.sort((a, b) => 
        (a['fullName'] ?? '').toString().compareTo((b['fullName'] ?? '').toString())
      );
    }
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.person, color: Colors.indigo),
              SizedBox(width: 12),
              Expanded(child: Text('Öğretmen Seç')),
              Text(
                '${selectedIds.length} seçili',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          content: SizedBox(
            width: 450,
            height: 500,
            child: _allTeachers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_off, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Kayıtlı öğretmen bulunamadı'),
                        SizedBox(height: 8),
                        Text(
                          'Personel yönetiminden öğretmen ekleyin',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: sortedBranches.length,
                    itemBuilder: (context, branchIndex) {
                      final branch = sortedBranches[branchIndex];
                      final teachers = teachersByBranch[branch]!;
                      final isLessonBranch = branch == lessonBranchName;
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Branş Başlığı
                          Container(
                            width: double.infinity,
                            margin: EdgeInsets.only(top: branchIndex > 0 ? 16 : 0, bottom: 8),
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isLessonBranch ? Colors.green.shade100 : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                              border: isLessonBranch ? Border.all(color: Colors.green.shade400, width: 2) : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isLessonBranch ? Icons.star : Icons.category,
                                  size: 16,
                                  color: isLessonBranch ? Colors.green.shade700 : Colors.grey.shade700,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    branch,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: isLessonBranch ? Colors.green.shade800 : Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${teachers.length} öğretmen',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isLessonBranch ? Colors.green.shade600 : Colors.grey.shade600,
                                  ),
                                ),
                                if (isLessonBranch) ...[
                                  SizedBox(width: 8),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade600,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Ders Branşı',
                                      style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Branştaki Öğretmenler
                          ...teachers.map((teacher) {
                            final isSelected = selectedIds.contains(teacher['id']);
                            final totalHours = teacher['totalHours'] ?? 0;
                            return Container(
                              margin: EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? Colors.indigo.shade50 
                                    : (isLessonBranch ? Colors.green.shade50 : null),
                                borderRadius: BorderRadius.circular(8),
                                border: isSelected ? Border.all(color: Colors.indigo.shade300) : null,
                              ),
                              child: CheckboxListTile(
                                value: isSelected,
                                onChanged: (value) {
                                  setDialogState(() {
                                    if (value == true) {
                                      selectedIds.add(teacher['id']);
                                    } else {
                                      selectedIds.remove(teacher['id']);
                                    }
                                  });
                                },
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        teacher['fullName'] ?? '',
                                        style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: totalHours > 0 
                                            ? Colors.orange.shade100 
                                            : Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '($totalHours)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: totalHours > 0 
                                              ? Colors.orange.shade800 
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                secondary: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: isSelected 
                                      ? Colors.indigo 
                                      : (isLessonBranch ? Colors.green.shade300 : Colors.grey.shade300),
                                  child: Text(
                                    (teacher['fullName'] ?? 'Ö')[0].toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                controlAffinity: ListTileControlAffinity.trailing,
                                dense: true,
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('İptal'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _assignments[assignmentIndex]['teacherIds'] = selectedIds;
                  _assignments[assignmentIndex]['teacherNames'] = selectedIds.map((id) {
                    final teacher = _allTeachers.firstWhere(
                      (t) => t['id'] == id,
                      orElse: () => {'fullName': 'Bilinmiyor'},
                    );
                    return teacher['fullName'] as String;
                  }).toList();
                });
                Navigator.pop(context);
              },
              icon: Icon(Icons.check),
              label: Text('Tamam (${selectedIds.length})'),
            ),
          ],
        ),
      ),
    );
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

// ==================== BRANŞ YÖNETİM DIALOG ====================
class _BranchManagementDialog extends StatefulWidget {
  final String institutionId;
  final VoidCallback onBranchesChanged;

  const _BranchManagementDialog({
    required this.institutionId,
    required this.onBranchesChanged,
  });

  @override
  State<_BranchManagementDialog> createState() => _BranchManagementDialogState();
}

class _BranchManagementDialogState extends State<_BranchManagementDialog> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _allBranches = [];
  bool _isLoading = true;

  // Varsayılan branşlar
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
    
    // Varsayılan branşları ekle
    for (var name in _defaultBranches) {
      branches.add({
        'id': null,
        'branchName': name,
        'isDefault': true,
      });
    }

    // Firestore'dan özel branşları yükle
    try {
      final customBranches = await FirebaseFirestore.instance
          .collection('branches')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in customBranches.docs) {
        final name = doc.data()['branchName'] as String?;
        if (name != null && !_defaultBranches.contains(name)) {
          branches.add({
            'id': doc.id,
            'branchName': name,
            'isDefault': false,
          });
        }
      }
    } catch (e) {
      print('Özel branş yükleme hatası: $e');
    }

    branches.sort((a, b) => (a['branchName'] as String).compareTo(b['branchName'] as String));
    
    setState(() {
      _allBranches = branches;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addBranch() async {
    if (_controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Branş adı boş olamaz')),
      );
      return;
    }
    
    final newName = _controller.text.trim();
    
    // Zaten var mı kontrol et
    if (_allBranches.any((b) => b['branchName'] == newName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bu branş zaten mevcut')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('branches').add({
        'branchName': newName,
        'institutionId': widget.institutionId,
        'isDefault': false,
        'isActive': true,
      });

      _controller.clear();
      widget.onBranchesChanged();
      await _loadAllBranches();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$newName" branşı eklendi'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteBranch(String branchId) async {
    await FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .update({'isActive': false});
    widget.onBranchesChanged();
    _loadAllBranches();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.category, color: Colors.indigo),
          SizedBox(width: 12),
          Text('Branş Yönetimi'),
        ],
      ),
      content: SizedBox(
        width: 450,
        height: 500,
        child: Column(
          children: [
            // Yeni branş ekleme
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Yeni branş adı girin',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.add),
                    ),
                    onSubmitted: (_) => _addBranch(),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _addBranch,
                  icon: Icon(Icons.add),
                  label: Text('Ekle'),
                ),
              ],
            ),
            SizedBox(height: 16),
            Divider(),
            SizedBox(height: 8),
            // Branş sayısı
            Row(
              children: [
                Text(
                  'Toplam ${_allBranches.length} branş',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                Spacer(),
                Text(
                  '${_allBranches.where((b) => b['isDefault'] == true).length} varsayılan, '
                  '${_allBranches.where((b) => b['isDefault'] == false).length} özel',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            SizedBox(height: 8),
            // Branş listesi
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _allBranches.length,
                      itemBuilder: (context, index) {
                        final branch = _allBranches[index];
                        final isDefault = branch['isDefault'] == true;

                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: isDefault ? Colors.indigo.shade100 : Colors.orange.shade100,
                            child: Icon(
                              Icons.category,
                              size: 16,
                              color: isDefault ? Colors.indigo : Colors.orange,
                            ),
                          ),
                          title: Text(branch['branchName'] ?? ''),
                          subtitle: Text(
                            isDefault ? 'Varsayılan branş' : 'Özel branş (silinebilir)',
                            style: TextStyle(fontSize: 11),
                          ),
                          trailing: isDefault
                              ? Icon(Icons.lock, size: 16, color: Colors.grey)
                              : IconButton(
                                  icon: Icon(Icons.delete, color: Colors.red, size: 20),
                                  onPressed: () => _deleteBranch(branch['id']),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Kapat'),
        ),
      ],
    );
  }
}
