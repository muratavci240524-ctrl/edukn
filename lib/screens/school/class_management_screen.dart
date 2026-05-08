import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/class_model.dart';
import '../../services/term_service.dart';
import 'class_management_screen_student_card.dart';

class ClassManagementScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const ClassManagementScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<ClassManagementScreen> createState() => _ClassManagementScreenState();
}

class _ClassManagementScreenState extends State<ClassManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Set<String> _selectedClassTypes = {};
  Set<int> _selectedLevels = {};
  List<ClassTypeModel> _classTypes = [];
  String? _selectedClassId;
  Map<String, dynamic>? _selectedClass;
  String? _currentTermId; // Seçili dönem
  bool _isViewingPastTerm = false; // Geçmiş dönem görüntüleniyor mu?
  Set<int> _schoolTypeLevels = {}; // Okul türüne tanımlı aktif seviyeler
  final ValueNotifier<List<int>> _availableLevelsNotifier = ValueNotifier<List<int>>([]); // Hem tanımdan hem veriden gelen tüm seviyeler

  @override
  void initState() {
    super.initState();
    _loadTermAndInitialize();
    _loadSchoolTypeLevels();
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
  
  Future<void> _loadTermAndInitialize() async {
    final selectedTermId = await TermService().getSelectedTermId();
    final activeTermId = await TermService().getActiveTermId();
    final effectiveTermId = selectedTermId ?? activeTermId;
    if (mounted) {
      setState(() {
        _currentTermId = effectiveTermId;
        _isViewingPastTerm = selectedTermId != null && selectedTermId != activeTermId;
      });
    }
    _initializeDefaultClassType();
  }

  Future<void> _initializeDefaultClassType() async {
    // Önce mevcut tipleri kontrol et
    final snapshot = await FirebaseFirestore.instance
        .collection('classTypes')
        .where('institutionId', isEqualTo: widget.institutionId)
        .get();

    // Eğer hiç tip yoksa varsayılan tipi oluştur
    if (snapshot.docs.isEmpty) {
      await _createDefaultClassType();
    }
    
    // Tipleri yükle
    await _loadClassTypes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _availableLevelsNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadClassTypes() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('classTypes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final types = snapshot.docs
          .map((doc) => ClassTypeModel.fromMap(doc.data(), doc.id))
          .toList();

      // Manuel sıralama: önce varsayılan, sonra alfabetik
      types.sort((a, b) {
        if (a.isDefault && !b.isDefault) return -1;
        if (!a.isDefault && b.isDefault) return 1;
        return a.typeName.compareTo(b.typeName);
      });

      if (mounted) {
        setState(() {
          _classTypes = types;
        });
      }
    } catch (e) {
      print('Sınıf tipleri yüklenirken hata: $e');
    }
  }

  Future<void> _createDefaultClassType() async {
    try {
      final defaultType = ClassTypeModel(
        typeName: 'Ders Sınıfı',
        description: 'Varsayılan sınıf tipi',
        institutionId: widget.institutionId,
        createdAt: DateTime.now(),
        isDefault: true,
      );

      await FirebaseFirestore.instance
          .collection('classTypes')
          .add(defaultType.toMap());

      print('✅ Varsayılan "Ders Sınıfı" tipi oluşturuldu');
    } catch (e) {
      print('❌ Varsayılan tip oluşturulurken hata: $e');
    }
  }

  Future<void> _loadSchoolTypeLevels() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .doc(widget.schoolTypeId)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data();
        final levels = data?['activeGrades'] as List<dynamic>?;
        if (levels != null) {
          final parsedLevels = levels
              .map((e) {
                final s = e.toString();
                // Extract first number found in string (handles "5", "5. Sınıf", "5 Yaş" etc)
                final match = RegExp(r'\d+').firstMatch(s);
                return match != null ? int.tryParse(match.group(0)!) ?? 0 : 0;
              })
              .where((e) => e > 0)
              .toSet();

          setState(() {
            _schoolTypeLevels = parsedLevels;
            _updateAvailableLevels();
          });
        }
      }
    } catch (e) {
      print('Okul türü seviyeleri yüklenirken hata: $e');
    }
  }

  void _updateAvailableLevels([List<int>? dataLevels]) {
    final combined = {..._schoolTypeLevels, ...(dataLevels ?? [])}.toList();
    combined.sort();
    
    // Sadece farklıysa güncelle (sonsuz döngüyü önlemek için)
    if (_availableLevelsNotifier.value.length != combined.length ||
        !_availableLevelsNotifier.value.every((l) => combined.contains(l))) {
      _availableLevelsNotifier.value = combined;
    }
  }

  Stream<QuerySnapshot> _getClassesStream() {
    // Tüm sınıfları çek, dönem filtresi client-side yapılacak
    return FirebaseFirestore.instance
        .collection('classes')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  List<ClassModel> _filterClasses(List<ClassModel> classes) {
    final filtered = classes.where((c) {
      final matchesSearch = _searchQuery.isEmpty ||
          c.className.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.shortName.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesType =
          _selectedClassTypes.isEmpty || _selectedClassTypes.contains(c.classTypeId);

      final matchesLevel =
          _selectedLevels.isEmpty || _selectedLevels.contains(c.classLevel);

      // Dönem filtresi: sadece seçili döneme ait olanları göster
      final matchesTerm = _currentTermId == null || 
          c.termId == _currentTermId;

      return matchesSearch && matchesType && matchesLevel && matchesTerm;
    }).toList();

    // Manuel sıralama: önce seviye, sonra isim
    filtered.sort((a, b) {
      final levelCompare = a.classLevel.compareTo(b.classLevel);
      if (levelCompare != 0) return levelCompare;
      return a.className.compareTo(b.className);
    });

    return filtered;
  }

  void _showClassTypeDialog() {
    showDialog(
      context: context,
      builder: (context) => _ClassTypeDialog(
        institutionId: widget.institutionId,
        onTypesUpdated: _loadClassTypes,
      ),
    );
  }

  void _showClassFormBottomSheet({ClassModel? classToEdit}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ClassFormSheet(
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
        termId: _currentTermId,
        classTypes: _classTypes,
        classToEdit: classToEdit,
        onClassSaved: () {
          setState(() {});
        },
      ),
    );
  }

  // Sınıftaki öğrenci sayısını getir
  Future<int> _getStudentCount(String classId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('classId', isEqualTo: classId)
          .get();
      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }

  Future<void> _deleteClass(String classId, String className) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 12),
            Text('Şubeyi Sil'),
          ],
        ),
        content: Text(
          '$className şubesini silmek istediğinize emin misiniz?\n\nBu işlem geri alınamaz.',
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
      try {
        await FirebaseFirestore.instance
            .collection('classes')
            .doc(classId)
            .update({'isActive': false});

        if (_selectedClassId == classId) {
          setState(() {
            _selectedClassId = null;
            _selectedClass = null;
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Şube silindi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Hata: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.indigo.shade700 : Colors.white,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  void _showClassTypeFilterSheet() {
    final isWide = MediaQuery.of(context).size.width > 900;
    final items = _classTypes.map((t) => FilterItem<String>(
      value: t.id!,
      label: t.typeName,
      icon: Icons.layers_outlined,
    )).toList();

    if (isWide) {
      _showMultiSelectDropdownWeb<String>(
        title: 'Sınıf Tipi',
        icon: Icons.category_rounded,
        items: items,
        initialSelectedValues: _selectedClassTypes,
        onApply: (values) {
          setState(() => _selectedClassTypes = values);
        },
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => _MultiSelectFilterSheet<String>(
          title: 'Sınıf Tipi Seçin',
          icon: Icons.category_rounded,
          items: items,
          initialSelectedValues: _selectedClassTypes,
          onApply: (values) {
            setState(() => _selectedClassTypes = values);
          },
        ),
      );
    }
  }

  void _showLevelFilterSheet(List<int> availableLevels) {
    final isWide = MediaQuery.of(context).size.width > 900;
    final items = availableLevels.map((l) => FilterItem<int>(
      value: l,
      label: '$l. Sınıf',
      icon: Icons.grade_outlined,
    )).toList();

    if (isWide) {
      _showMultiSelectDropdownWeb<int>(
        title: 'Sınıf Seviyesi',
        icon: Icons.filter_list_rounded,
        items: items,
        initialSelectedValues: _selectedLevels,
        onApply: (values) {
          setState(() => _selectedLevels = values);
        },
        isGrid: true,
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => _MultiSelectFilterSheet<int>(
          title: 'Sınıf Seviyesi Seçin',
          icon: Icons.filter_list_rounded,
          isGrid: true,
          items: items,
          initialSelectedValues: _selectedLevels,
          onApply: (values) {
            setState(() => _selectedLevels = values);
          },
        ),
      );
    }
  }

  void _showMultiSelectDropdownWeb<T>({
    required String title,
    required IconData icon,
    required List<FilterItem<T>> items,
    required Set<T> initialSelectedValues,
    required Function(Set<T>) onApply,
    bool isGrid = false,
  }) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.05),
      builder: (context) => Stack(
        children: [
          Positioned(
            left: 20, // Filtre butonlarının olduğu yere yakın konumlandır
            top: 180, // Üst menünün altına denk gelecek şekilde
            child: Material(
              color: Colors.transparent,
              child: _MultiSelectFilterSheet<T>(
                title: title,
                icon: icon,
                items: items,
                initialSelectedValues: initialSelectedValues,
                onApply: onApply,
                isGrid: isGrid,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: isActive ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: Offset(0, 2),
            )
          ] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? Colors.indigo.shade700 : Colors.white,
            ),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.indigo.shade700 : Colors.white,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 900;

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
              'Şube Listesi',
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
            onPressed: _showClassTypeDialog,
            icon: Icon(Icons.category, size: 18),
            label: Text('Sınıf Tipi Tanımla'),
            style: TextButton.styleFrom(foregroundColor: Colors.indigo),
          ),
          SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _isViewingPastTerm
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showClassFormBottomSheet(),
              backgroundColor: Colors.indigo,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Yeni Şube Ekle', style: TextStyle(color: Colors.white)),
            ),
      body: Row(
        children: [
          // Sol Panel - Liste
          Container(
            width: isWideScreen ? 350 : MediaQuery.of(context).size.width,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                right: BorderSide(color: Colors.grey.shade300, width: 1),
              ),
            ),
            child: Column(
              children: [
                // Filtreler - Öğrenci listesi tarzında
                Container(
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
                      // Başlık
                      Row(
                        children: [
                          Icon(Icons.class_outlined, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Şubeler',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          StreamBuilder<QuerySnapshot>(
                            stream: _getClassesStream(),
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
                      SizedBox(height: 16),
                      
                      // Arama
                      SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Şube ara...',
                            hintStyle: TextStyle(color: Colors.white70, fontSize: 14),
                            prefixIcon: Icon(Icons.search, size: 20, color: Colors.white70),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, size: 18, color: Colors.white70),
                                    onPressed: () {
                                      setState(() {
                                        _searchController.clear();
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.2),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                        ),
                      ),
                      SizedBox(height: 12),
                      
                      // Filtre butonları
                      Row(
                        children: [
                          Expanded(
                            child: _buildFilterChip(
                              'Tümü',
                              _selectedClassTypes.isEmpty && _selectedLevels.isEmpty && _searchQuery.isEmpty,
                              () {
                                setState(() {
                                  _selectedClassTypes = {};
                                  _selectedLevels = {};
                                  _searchQuery = '';
                                  _searchController.clear();
                                });
                              },
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: _buildFilterButton(
                              icon: Icons.category,
                              label: _selectedClassTypes.isEmpty
                                  ? 'Tip'
                                  : _selectedClassTypes.length == 1
                                      ? _classTypes.firstWhere((t) => t.id == _selectedClassTypes.first).typeName
                                      : 'Tip (${_selectedClassTypes.length})',
                              isActive: _selectedClassTypes.isNotEmpty,
                              onTap: _showClassTypeFilterSheet,
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: ValueListenableBuilder<List<int>>(
                              valueListenable: _availableLevelsNotifier,
                              builder: (context, availableLevels, _) {
                                return _buildFilterButton(
                                  icon: Icons.filter_list,
                                  label: _selectedLevels.isEmpty
                                      ? 'Seviye'
                                      : _selectedLevels.length == 1
                                          ? '${_selectedLevels.first}. Sınıf'
                                          : 'Seviye (${_selectedLevels.length})',
                                  isActive: _selectedLevels.isNotEmpty,
                                  onTap: () => _showLevelFilterSheet(availableLevels),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 8),

                // Şube listesi
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _getClassesStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 60,
                                color: Colors.red.shade300,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Veri yüklenemedi',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.class_outlined,
                                size: 60,
                                color: Colors.grey.shade400,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Henüz Şube Yok',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'İlk şubeyi eklemek için\nalt taraftaki + butonuna tıklayın',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final allClasses = snapshot.data!.docs
                          .map((doc) => ClassModel.fromMap(
                              doc.data() as Map<String, dynamic>, doc.id))
                          .toList();

                      // Mevcut verilerden seviyeleri topla ve notifier'ı güncelle
                      final dataLevels = allClasses.map((c) => c.classLevel).toSet().toList();
                      dataLevels.sort();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _updateAvailableLevels(dataLevels);
                      });

                      final filteredClasses = _filterClasses(allClasses);

                      if (filteredClasses.isEmpty) {
                        return Center(
                          child: Text(
                            'Filtrelere uygun şube bulunamadı',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: filteredClasses.length,
                        itemBuilder: (context, index) {
                          final classItem = filteredClasses[index];
                          final isSelected = _selectedClassId == classItem.id;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedClassId = classItem.id;
                                _selectedClass = {
                                  'id': classItem.id,
                                  'className': classItem.className,
                                  'shortName': classItem.shortName,
                                  'classTypeId': classItem.classTypeId,
                                  'classTypeName': classItem.classTypeName,
                                  'classTeacherId': classItem.classTeacherId,
                                  'classTeacherName': classItem.classTeacherName,
                                  'classLevel': classItem.classLevel,
                                  'description': classItem.description,
                                  'schoolTypeId': classItem.schoolTypeId,
                                  'schoolTypeName': classItem.schoolTypeName,
                                  'institutionId': classItem.institutionId,
                                  'createdAt': classItem.createdAt,
                                  'updatedAt': classItem.updatedAt,
                                  'isActive': classItem.isActive,
                                };
                              });

                              // Dar ekranda sağ paneli göster
                              if (!isWideScreen) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => _ClassDetailScreen(
                                      classData: _selectedClass!,
                                      classTypes: _classTypes,
                                      onEdit: () {
                                        Navigator.pop(context);
                                        _showClassFormBottomSheet(
                                          classToEdit: classItem,
                                        );
                                      },
                                      onDelete: () {
                                        Navigator.pop(context);
                                        _deleteClass(
                                          classItem.id!,
                                          classItem.className,
                                        );
                                      },
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.indigo.shade50
                                    : Colors.white,
                                border: Border(
                                  left: BorderSide(
                                    color: isSelected
                                        ? Colors.indigo
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                  bottom: BorderSide(
                                    color: Colors.grey.shade200,
                                    width: 1,
                                  ),
                                ),
                              ),
                              padding: EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.indigo.shade100
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.class_outlined,
                                      color: isSelected
                                          ? Colors.indigo
                                          : Colors.grey.shade600,
                                      size: 20,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          classItem.className,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? Colors.indigo.shade900
                                                : Colors.grey.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Öğrenci sayısı
                                  FutureBuilder<int>(
                                    future: _getStudentCount(classItem.id!),
                                    builder: (context, snapshot) {
                                      final count = snapshot.data ?? 0;
                                      return Container(
                                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: count > 0 ? Colors.indigo.shade50 : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '$count',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: count > 0 ? Colors.indigo : Colors.grey,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 14,
                                    color: Colors.grey.shade400,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Sağ Panel - Detay (sadece geniş ekranda)
          if (isWideScreen)
            Expanded(
              child: _selectedClass == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.class_outlined,
                            size: 80,
                            color: Colors.grey.shade300,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Şube Seçilmedi',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Soldan bir şube seçerek\ndetayları görüntüleyin',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _ClassDetailScreen(
                      classData: _selectedClass!,
                      classTypes: _classTypes,
                      onEdit: () {
                        final classModel = ClassModel(
                          id: _selectedClass!['id'],
                          className: _selectedClass!['className'],
                          shortName: _selectedClass!['shortName'],
                          classTypeId: _selectedClass!['classTypeId'],
                          classTypeName: _selectedClass!['classTypeName'],
                          classTeacherId: _selectedClass!['classTeacherId'],
                          classTeacherName: _selectedClass!['classTeacherName'],
                          classLevel: _selectedClass!['classLevel'],
                          description: _selectedClass!['description'],
                          schoolTypeId: _selectedClass!['schoolTypeId'],
                          schoolTypeName: _selectedClass!['schoolTypeName'],
                          institutionId: _selectedClass!['institutionId'],
                          createdAt: _selectedClass!['createdAt'],
                          updatedAt: _selectedClass!['updatedAt'],
                          isActive: _selectedClass!['isActive'],
                        );
                        _showClassFormBottomSheet(classToEdit: classModel);
                      },
                      onDelete: () {
                        _deleteClass(
                          _selectedClass!['id'],
                          _selectedClass!['className'],
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

// Detay Ekranı Widget'ı
class _ClassDetailScreen extends StatelessWidget {
  final Map<String, dynamic> classData;
  final List<ClassTypeModel> classTypes;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ClassDetailScreen({
    required this.classData,
    required this.classTypes,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Geri butonu (mobil için)
          if (isMobile)
            Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back),
                tooltip: 'Geri',
              ),
            ),
          
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.class_outlined,
                  color: Colors.indigo,
                  size: 32,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: Text(
                        classData['className'] ?? '',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isMobile ? 18 : 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    SizedBox(height: 4),
                    Material(
                      color: Colors.transparent,
                      child: Text(
                        classData['shortName'] ?? '',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isMobile) ...[
                IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit, color: Colors.blue),
                  tooltip: 'Düzenle',
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete, color: Colors.red),
                  tooltip: 'Sil',
                ),
              ] else ...[
                PopupMenuButton(
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Text('Düzenle'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Text('Sil'),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                ),
              ],
            ],
          ),
          SizedBox(height: 24),

          // Bilgi Kartları
          _InfoCard(
            title: 'Genel Bilgiler',
            children: [
              _InfoRow('Sınıf Tipi', classData['classTypeName']),
              _InfoRow('Sınıf Seviyesi', '${classData['classLevel']}. Sınıf'),
              if (classData['description'] != null &&
                  classData['description'].toString().isNotEmpty)
                _InfoRow('Açıklama', classData['description']),
            ],
          ),
          SizedBox(height: 16),

          if (classData['classTeacherName'] != null)
            _InfoCard(
              title: 'Sınıf Öğretmeni',
              children: [
                _InfoRow('Öğretmen', classData['classTeacherName']),
              ],
            ),
          
          SizedBox(height: 16),
          
          // Öğrenci Listesi
          StudentListCard(
            key: ValueKey('students_${classData['id']}'),
            classId: classData['id'],
            className: classData['className'],
            classTypeId: classData['classTypeId'],
            classTypeName: classData['classTypeName'],
            schoolTypeId: classData['schoolTypeId'],
            institutionId: classData['institutionId'],
          ),
          
          SizedBox(height: 16),
          
          // Ders Listesi
          _ClassLessonListCard(
            key: ValueKey('lessons_${classData['id']}'),
            classId: classData['id'],
            className: classData['className'],
            schoolTypeId: classData['schoolTypeId'],
            institutionId: classData['institutionId'],
          ),
        ],
      ),
    );
  }
}

// Şubeye Atanan Dersler Kartı
class _ClassLessonListCard extends StatefulWidget {
  final String classId;
  final String className;
  final String schoolTypeId;
  final String institutionId;

  const _ClassLessonListCard({
    Key? key,
    required this.classId,
    required this.className,
    required this.schoolTypeId,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<_ClassLessonListCard> createState() => _ClassLessonListCardState();
}

class _ClassLessonListCardState extends State<_ClassLessonListCard> {
  int _lessonCount = 0;
  int _totalHours = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLessonData();
  }

  Future<void> _loadLessonData() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('classId', isEqualTo: widget.classId)
          .where('isActive', isEqualTo: true)
          .get();

      int totalHours = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        totalHours += (data['weeklyHours'] as int?) ?? 0;
      }

      if (mounted) {
        setState(() {
          _lessonCount = snapshot.docs.length;
          _totalHours = totalHours;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _copyLessonsToOtherClasses() async {
    // Önce mevcut dersleri al
    final lessonsSnapshot = await FirebaseFirestore.instance
        .collection('lessonAssignments')
        .where('classId', isEqualTo: widget.classId)
        .where('isActive', isEqualTo: true)
        .get();

    if (lessonsSnapshot.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bu şubede kopyalanacak ders yok')),
      );
      return;
    }

    // Diğer şubeleri al
    final classesSnapshot = await FirebaseFirestore.instance
        .collection('classes')
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('isActive', isEqualTo: true)
        .get();

    final otherClasses = classesSnapshot.docs
        .where((doc) => doc.id != widget.classId)
        .toList();

    if (otherClasses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kopyalanacak başka şube yok')),
      );
      return;
    }

    // Şube seçim dialogu
    final selectedClassIds = await showDialog<List<String>>(
      context: context,
      builder: (context) => _CopyLessonsDialog(
        classes: otherClasses,
        lessonCount: lessonsSnapshot.docs.length,
      ),
    );

    if (selectedClassIds == null || selectedClassIds.isEmpty) return;

    // Dersleri kopyala
    try {
      final batch = FirebaseFirestore.instance.batch();
      int copiedCount = 0;

      for (var classDoc in otherClasses.where((c) => selectedClassIds.contains(c.id))) {
        final classData = classDoc.data();
        
        for (var lessonDoc in lessonsSnapshot.docs) {
          final lessonData = lessonDoc.data();
          
          // Bu ders zaten bu şubede var mı kontrol et
          final existingCheck = await FirebaseFirestore.instance
              .collection('lessonAssignments')
              .where('classId', isEqualTo: classDoc.id)
              .where('lessonId', isEqualTo: lessonData['lessonId'])
              .where('isActive', isEqualTo: true)
              .get();

          if (existingCheck.docs.isEmpty) {
            final newDocRef = FirebaseFirestore.instance.collection('lessonAssignments').doc();
            batch.set(newDocRef, {
              'lessonId': lessonData['lessonId'],
              'lessonName': lessonData['lessonName'],
              'classId': classDoc.id,
              'className': classData['className'],
              'weeklyHours': lessonData['weeklyHours'],
              'teacherIds': lessonData['teacherIds'] ?? [],
              'teacherNames': lessonData['teacherNames'] ?? [],
              'schoolTypeId': widget.schoolTypeId,
              'institutionId': widget.institutionId,
              'isActive': true,
              'createdAt': FieldValue.serverTimestamp(),
            });
            copiedCount++;
          }
        }
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$copiedCount ders ${selectedClassIds.length} şubeye kopyalandı'),
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
    }
  }

  void _showLessonListDialog() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      builder: (context) => Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: isMobile ? null : const BoxConstraints(maxWidth: 850),
          height: isMobile ? MediaQuery.of(context).size.height : MediaQuery.of(context).size.height * 0.9,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: _LessonListDialog(
            classId: widget.classId,
            className: widget.className,
            schoolTypeId: widget.schoolTypeId,
            institutionId: widget.institutionId,
            onLessonsChanged: _loadLessonData,
            onCopyLessons: _copyLessonsToOtherClasses,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: _showLessonListDialog,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.book, color: Colors.teal, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ders Listesi',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Ders listesini görüntülemek için tıklayın',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_lessonCount Ders',
                        style: TextStyle(
                          color: Colors.teal,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '$_totalHours Saat',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
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

// Ders Listesi Dialog'u
class _LessonListDialog extends StatefulWidget {
  final String classId;
  final String className;
  final String schoolTypeId;
  final String institutionId;
  final VoidCallback onLessonsChanged;
  final VoidCallback onCopyLessons;

  const _LessonListDialog({
    required this.classId,
    required this.className,
    required this.schoolTypeId,
    required this.institutionId,
    required this.onLessonsChanged,
    required this.onCopyLessons,
  });

  @override
  State<_LessonListDialog> createState() => _LessonListDialogState();
}

class _LessonListDialogState extends State<_LessonListDialog> {
  List<Map<String, dynamic>> _lessons = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLessons();
  }

  Future<void> _loadLessons() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('classId', isEqualTo: widget.classId)
          .where('isActive', isEqualTo: true)
          .get();

      if (mounted) {
        final lessons = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();

        lessons.sort((a, b) => (a['lessonName'] ?? '').compareTo(b['lessonName'] ?? ''));

        setState(() {
          _lessons = lessons;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  int get _totalHours {
    int total = 0;
    for (var lesson in _lessons) {
      total += (lesson['weeklyHours'] as int?) ?? 0;
    }
    return total;
  }

  Future<void> _removeLesson(String assignmentId, String lessonName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Dersi Çıkar'),
        content: Text('$lessonName dersini bu şubeden çıkarmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Çıkar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('lessonAssignments')
            .doc(assignmentId)
            .update({'isActive': false});

        _loadLessons();
        widget.onLessonsChanged();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$lessonName dersi çıkarıldı'), backgroundColor: Colors.green),
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
  }

  Future<void> _showAddLessonDialog() async {
    // Mevcut atanmış ders ID'lerini al
    final assignedLessonIds = _lessons.map((l) => l['lessonId'] as String).toSet();

    // Tüm dersleri al
    final lessonsSnapshot = await FirebaseFirestore.instance
        .collection('lessons')
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('isActive', isEqualTo: true)
        .get();

    final availableLessons = lessonsSnapshot.docs
        .where((doc) => !assignedLessonIds.contains(doc.id))
        .toList();

    if (availableLessons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eklenebilecek ders kalmadı')),
      );
      return;
    }

    final selectedLessons = await showDialog<List<QueryDocumentSnapshot>>(
      context: context,
      builder: (context) => _AddLessonDialog(availableLessons: availableLessons),
    );

    if (selectedLessons == null || selectedLessons.isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();

      for (var lessonDoc in selectedLessons) {
        final lessonData = lessonDoc.data() as Map<String, dynamic>;
        final newDocRef = FirebaseFirestore.instance.collection('lessonAssignments').doc();
        batch.set(newDocRef, {
          'lessonId': lessonDoc.id,
          'lessonName': lessonData['lessonName'],
          'classId': widget.classId,
          'className': widget.className,
          'weeklyHours': lessonData['weeklyHours'] ?? 0,
          'teacherIds': [],
          'teacherNames': [],
          'schoolTypeId': widget.schoolTypeId,
          'institutionId': widget.institutionId,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      _loadLessons();
      widget.onLessonsChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${selectedLessons.length} ders eklendi'),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // HEADER
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade700, Colors.teal.shade500],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.book_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ders Listesi',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.className,
                        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _showAddLessonDialog,
                      icon: const Icon(Icons.add_task_rounded, color: Colors.white),
                      tooltip: 'Ders Ekle',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.15),
                        padding: const EdgeInsets.all(10),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onCopyLessons();
                      },
                      icon: const Icon(Icons.copy_all_rounded, color: Colors.white),
                      tooltip: 'Kopyala',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.15),
                        padding: const EdgeInsets.all(10),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.15),
                        padding: const EdgeInsets.all(10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // CONTENT
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Container(
              color: Colors.grey.shade50,
              child: _buildContent(),
            ),
          ),
        ),
        // FOOTER
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_lessons.length} Ders',
                    style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'Şubeye atanan toplam ders sayısı',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_totalHours Saat/Hafta',
                  style: TextStyle(color: Colors.teal.shade700, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_lessons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.book_outlined, size: 64, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 24),
            Text(
              'Bu şubeye henüz ders atanmamış',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showAddLessonDialog,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('Yeni Ders Ata'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: _lessons.length,
      itemBuilder: (context, index) {
        final lesson = _lessons[index];
        final teacherNames = (lesson['teacherNames'] as List<dynamic>?)?.join(', ') ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade400, Colors.teal.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.teal.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.book_rounded, color: Colors.white, size: 20),
            ),
            title: Text(
              lesson['lessonName'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: teacherNames.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            teacherNames,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${lesson['weeklyHours'] ?? 0}s',
                    style: TextStyle(
                      color: Colors.teal.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                  ),
                  tooltip: 'Dersi Çıkar',
                  onPressed: () => _removeLesson(lesson['id'], lesson['lessonName'] ?? ''),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Ders Ekleme Dialogu
class _AddLessonDialog extends StatefulWidget {
  final List<QueryDocumentSnapshot> availableLessons;

  const _AddLessonDialog({required this.availableLessons});

  @override
  State<_AddLessonDialog> createState() => _AddLessonDialogState();
}

class _AddLessonDialogState extends State<_AddLessonDialog> {
  final Set<String> _selectedLessonIds = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.add, color: Colors.teal),
          SizedBox(width: 12),
          Text('Ders Ekle'),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${widget.availableLessons.length} ders mevcut',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedLessonIds.length == widget.availableLessons.length) {
                        _selectedLessonIds.clear();
                      } else {
                        _selectedLessonIds.addAll(widget.availableLessons.map((l) => l.id));
                      }
                    });
                  },
                  child: Text(_selectedLessonIds.length == widget.availableLessons.length
                      ? 'Hiçbirini Seçme'
                      : 'Tümünü Seç'),
                ),
              ],
            ),
            SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: widget.availableLessons.length,
                itemBuilder: (context, index) {
                  final lessonDoc = widget.availableLessons[index];
                  final lessonData = lessonDoc.data() as Map<String, dynamic>;
                  final isSelected = _selectedLessonIds.contains(lessonDoc.id);

                  return Card(
                    margin: EdgeInsets.only(bottom: 8),
                    color: isSelected ? Colors.teal.shade50 : null,
                    child: CheckboxListTile(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedLessonIds.add(lessonDoc.id);
                          } else {
                            _selectedLessonIds.remove(lessonDoc.id);
                          }
                        });
                      },
                      title: Text(
                        lessonData['lessonName'] ?? '',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        '${lessonData['branchName'] ?? ''} • ${lessonData['weeklyHours'] ?? 0} saat/hafta',
                        style: TextStyle(fontSize: 12),
                      ),
                      secondary: CircleAvatar(
                        backgroundColor: isSelected ? Colors.teal : Colors.grey.shade300,
                        child: Icon(
                          Icons.book,
                          color: isSelected ? Colors.white : Colors.grey.shade600,
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('İptal'),
        ),
        ElevatedButton.icon(
          onPressed: _selectedLessonIds.isEmpty
              ? null
              : () {
                  final selectedDocs = widget.availableLessons
                      .where((doc) => _selectedLessonIds.contains(doc.id))
                      .toList();
                  Navigator.pop(context, selectedDocs);
                },
          icon: Icon(Icons.add),
          label: Text('Ekle (${_selectedLessonIds.length})'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
        ),
      ],
    );
  }
}

// Ders Kopyalama Dialogu
class _CopyLessonsDialog extends StatefulWidget {
  final List<QueryDocumentSnapshot> classes;
  final int lessonCount;

  const _CopyLessonsDialog({
    required this.classes,
    required this.lessonCount,
  });

  @override
  State<_CopyLessonsDialog> createState() => _CopyLessonsDialogState();
}

class _CopyLessonsDialogState extends State<_CopyLessonsDialog> {
  final Set<String> _selectedClassIds = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.copy, color: Colors.teal),
          SizedBox(width: 12),
          Text('Dersleri Kopyala'),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.teal, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.lessonCount} ders seçilen şubelere kopyalanacak',
                      style: TextStyle(color: Colors.teal.shade700, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Hedef Şubeler',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedClassIds.length == widget.classes.length) {
                        _selectedClassIds.clear();
                      } else {
                        _selectedClassIds.addAll(widget.classes.map((c) => c.id));
                      }
                    });
                  },
                  child: Text(_selectedClassIds.length == widget.classes.length ? 'Hiçbirini Seçme' : 'Tümünü Seç'),
                ),
              ],
            ),
            SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: widget.classes.length,
                itemBuilder: (context, index) {
                  final classDoc = widget.classes[index];
                  final classData = classDoc.data() as Map<String, dynamic>;
                  final isSelected = _selectedClassIds.contains(classDoc.id);

                  return Card(
                    margin: EdgeInsets.only(bottom: 8),
                    color: isSelected ? Colors.teal.shade50 : null,
                    child: CheckboxListTile(
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedClassIds.add(classDoc.id);
                          } else {
                            _selectedClassIds.remove(classDoc.id);
                          }
                        });
                      },
                      title: Text(
                        classData['className'] ?? '',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        '${classData['classLevel']}. Sınıf • ${classData['classTypeName'] ?? ''}',
                        style: TextStyle(fontSize: 12),
                      ),
                      secondary: CircleAvatar(
                        backgroundColor: isSelected ? Colors.teal : Colors.grey.shade300,
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('İptal'),
        ),
        ElevatedButton.icon(
          onPressed: _selectedClassIds.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedClassIds.toList()),
          icon: Icon(Icons.copy),
          label: Text('Kopyala (${_selectedClassIds.length})'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Sınıf Tipi Dialog - Devamı aynı kalacak...
class _ClassTypeDialog extends StatefulWidget {
  final String institutionId;
  final VoidCallback onTypesUpdated;

  const _ClassTypeDialog({
    required this.institutionId,
    required this.onTypesUpdated,
  });

  @override
  State<_ClassTypeDialog> createState() => _ClassTypeDialogState();
}

class _ClassTypeDialogState extends State<_ClassTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _typeNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  List<ClassTypeModel> _types = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _typeNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('classTypes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final types = snapshot.docs
          .map((doc) => ClassTypeModel.fromMap(doc.data(), doc.id))
          .toList();

      // Manuel sıralama: önce varsayılan, sonra alfabetik
      types.sort((a, b) {
        if (a.isDefault && !b.isDefault) return -1;
        if (!a.isDefault && b.isDefault) return 1;
        return a.typeName.compareTo(b.typeName);
      });

      setState(() {
        _types = types;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveType() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final newType = ClassTypeModel(
        typeName: _typeNameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        institutionId: widget.institutionId,
        createdAt: DateTime.now(),
        isDefault: false,
      );

      await FirebaseFirestore.instance
          .collection('classTypes')
          .add(newType.toMap());

      _typeNameController.clear();
      _descriptionController.clear();

      await _loadTypes();
      widget.onTypesUpdated();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Sınıf tipi eklendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Sınıf tipi eklenirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sınıf tipi eklenemedi. Lütfen tekrar deneyin.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteType(String typeId, String typeName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sınıf Tipini Sil'),
        content: Text(
          '$typeName tipini silmek istediğinize emin misiniz?\n\nBu tipe ait şubeler etkilenmeyecektir.',
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
      try {
        await FirebaseFirestore.instance
            .collection('classTypes')
            .doc(typeId)
            .delete();

        await _loadTypes();
        widget.onTypesUpdated();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Sınıf tipi silindi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Hata: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.category, color: Colors.indigo),
                  SizedBox(width: 12),
                  Text(
                    'Sınıf Tipi Tanımla',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Form
            Padding(
              padding: EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Yeni Sınıf Tipi Ekle',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      controller: _typeNameController,
                      decoration: InputDecoration(
                        labelText: 'Tip Adı *',
                        hintText: 'Örn: Sayısal, Sözel, LGS Grubu',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Tip adı zorunludur';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Açıklama (Opsiyonel)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                      ),
                      maxLines: 2,
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveType,
                        icon: _isSaving
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Icon(Icons.add),
                        label: Text(_isSaving ? 'Ekleniyor...' : 'Ekle'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Divider(),

            // Mevcut tipler listesi
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : _types.isEmpty
                      ? Center(
                          child: Text(
                            'Henüz sınıf tipi eklenmemiş',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _types.length,
                          itemBuilder: (context, index) {
                            final type = _types[index];
                            return Card(
                              margin: EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(
                                  Icons.label,
                                  color: type.isDefault
                                      ? Colors.green
                                      : Colors.indigo,
                                ),
                                title: Row(
                                  children: [
                                    Text(type.typeName),
                                    if (type.isDefault) ...[
                                      SizedBox(width: 8),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'Varsayılan',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: type.description != null
                                    ? Text(type.description!)
                                    : null,
                                trailing: type.isDefault
                                    ? null
                                    : IconButton(
                                        icon: Icon(Icons.delete,
                                            color: Colors.red),
                                        onPressed: () => _deleteType(
                                          type.id!,
                                          type.typeName,
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// Sınıf Form Sheet (Premium Bottom Sheet)
class _ClassFormSheet extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;
  final String? termId;
  final List<ClassTypeModel> classTypes;
  final ClassModel? classToEdit;
  final VoidCallback onClassSaved;

  const _ClassFormSheet({
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
    this.termId,
    required this.classTypes,
    this.classToEdit,
    required this.onClassSaved,
  });

  @override
  State<_ClassFormSheet> createState() => _ClassFormSheetState();
}

class _ClassFormSheetState extends State<_ClassFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _classNameController = TextEditingController();
  final _shortNameController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedClassTypeId;
  String? _selectedTeacherId;
  int _selectedLevel = 1;
  List<Map<String, dynamic>> _teachers = [];
  bool _isLoadingTeachers = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadTeachers();

    if (widget.classToEdit != null) {
      final c = widget.classToEdit!;
      _classNameController.text = c.className;
      _shortNameController.text = c.shortName;
      
      // Güvenli seçim: Liste içinde varsa seç, yoksa null bırak (crash engelleme)
      bool typeExists = widget.classTypes.any((t) => t.id == c.classTypeId);
      _selectedClassTypeId = typeExists ? c.classTypeId : (widget.classTypes.isNotEmpty ? widget.classTypes.first.id : null);
      
      _selectedTeacherId = c.classTeacherId;
      _selectedLevel = c.classLevel;
      _descriptionController.text = c.description ?? '';
    } else if (widget.classTypes.isNotEmpty) {
      final defaultType = widget.classTypes.firstWhere(
        (t) => t.isDefault,
        orElse: () => widget.classTypes.first,
      );
      _selectedClassTypeId = defaultType.id;
    }
  }

  @override
  void dispose() {
    _classNameController.dispose();
    _shortNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadTeachers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('type', isEqualTo: 'staff')
          .where('isActive', isEqualTo: true)
          .get();

      final teachers = snapshot.docs.where((doc) {
        final data = doc.data();
        final title = (data['title'] ?? '').toString().toLowerCase();
        if (title != 'ogretmen') return false;
        if (data['workLocations'] != null && data['workLocations'] is List) {
          final locations = List<String>.from(data['workLocations']);
          return locations.contains(widget.schoolTypeName);
        }
        return true;
      }).map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'fullName': data['fullName'] ?? '',
        };
      }).toList();

      setState(() {
        _teachers = teachers;
        _isLoadingTeachers = false;
      });
    } catch (e) {
      setState(() => _isLoadingTeachers = false);
    }
  }

  Future<void> _saveClass() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedClassTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen sınıf tipi seçiniz')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final selectedType = widget.classTypes.firstWhere(
        (t) => t.id == _selectedClassTypeId,
        orElse: () => widget.classTypes.first,
      );

      String? teacherName;
      if (_selectedTeacherId != null) {
        final teacher = _teachers.firstWhere(
          (t) => t['id'] == _selectedTeacherId,
          orElse: () => {'fullName': ''},
        );
        teacherName = teacher['fullName'];
      }

      final activeTermId = await TermService().getActiveTermId();

      final classData = ClassModel(
        id: widget.classToEdit?.id,
        className: _classNameController.text.trim(),
        shortName: _shortNameController.text.trim(),
        classTypeId: _selectedClassTypeId!,
        classTypeName: selectedType.typeName,
        classTeacherId: _selectedTeacherId,
        classTeacherName: teacherName,
        classLevel: _selectedLevel,
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        institutionId: widget.institutionId,
        termId: widget.classToEdit?.termId ?? activeTermId,
        createdAt: widget.classToEdit?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        isActive: true,
      );

      if (widget.classToEdit == null) {
        await FirebaseFirestore.instance.collection('classes').add(classData.toMap());
      } else {
        await FirebaseFirestore.instance.collection('classes').doc(widget.classToEdit!.id).update(classData.toMap());
      }

      widget.onClassSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.classToEdit == null ? '✅ Şube eklendi' : '✅ Şube güncellendi'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Hata: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Crash Fix: Dropdown değerlerinin listede olduğundan emin ol
    final String? safeClassTypeId = widget.classTypes.any((t) => t.id == _selectedClassTypeId) 
        ? _selectedClassTypeId 
        : (widget.classTypes.isNotEmpty ? widget.classTypes.first.id : null);
    
    final String? safeTeacherId = _teachers.any((t) => t['id'] == _selectedTeacherId)
        ? _selectedTeacherId
        : null; // Eğer listede yoksa "Seçilmedi"ye düşür

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.class_outlined, color: Colors.indigo.shade900, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.classToEdit == null ? 'Yeni Şube Ekle' : 'Şubeyi Düzenle',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1C1E)),
                      ),
                      Text(widget.schoolTypeName, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          const Divider(),
          
          // Form Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildInputField(
                      controller: _classNameController,
                      label: 'Şube Adı *',
                      hint: 'Örn: 8-A, 12-B',
                      icon: Icons.edit_note_rounded,
                      validator: (v) => (v == null || v.isEmpty) ? 'Zorunlu alan' : null,
                    ),
                    const SizedBox(height: 12),
                    _buildInputField(
                      controller: _shortNameController,
                      label: 'Kısa Ad *',
                      hint: 'Örn: 8A, 12B',
                      icon: Icons.short_text_rounded,
                      maxLength: 5,
                      validator: (v) => (v == null || v.isEmpty) ? 'Zorunlu alan' : null,
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown<String>(
                      value: safeClassTypeId,
                      label: 'Sınıf Tipi *',
                      items: widget.classTypes.map((t) => DropdownMenuItem(value: t.id, child: Text(t.typeName))).toList(),
                      onChanged: (v) => setState(() => _selectedClassTypeId = v),
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown<int>(
                      value: _selectedLevel,
                      label: 'Sınıf Seviyesi *',
                      items: List.generate(12, (i) => i + 1).map((l) => DropdownMenuItem(value: l, child: Text('$l. Sınıf'))).toList(),
                      onChanged: (v) => setState(() => _selectedLevel = v ?? 1),
                    ),
                    const SizedBox(height: 12),
                    _isLoadingTeachers 
                      ? const LinearProgressIndicator()
                      : _buildDropdown<String?>(
                          value: safeTeacherId,
                          label: 'Sınıf Öğretmeni (Opsiyonel)',
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Seçilmedi')),
                            ..._teachers.map((t) => DropdownMenuItem(value: t['id'] as String, child: Text(t['fullName'] as String))),
                          ],
                          onChanged: (v) => setState(() => _selectedTeacherId = v),
                        ),
                    const SizedBox(height: 12),
                    _buildInputField(
                      controller: _descriptionController,
                      label: 'Açıklama',
                      hint: 'Opsiyonel notlar...',
                      icon: Icons.description_outlined,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 32),
                    
                    // Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveClass,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo.shade900,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: _isSaving
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(widget.classToEdit == null ? 'Şubeyi Oluştur' : 'Değişiklikleri Kaydet', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int? maxLength,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLength: maxLength,
          maxLines: maxLines,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20, color: Colors.indigo.shade300),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.indigo.shade200, width: 2)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            counterText: "",
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    T? value,
    required String label,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ],
    );
  }
}

class FilterItem<T> {
  final T value;
  final String label;
  final IconData icon;

  FilterItem({required this.value, required this.label, required this.icon});
}

class _MultiSelectFilterSheet<T> extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<FilterItem<T>> items;
  final Set<T> initialSelectedValues;
  final Function(Set<T>) onApply;
  final bool isGrid;

  const _MultiSelectFilterSheet({
    Key? key,
    required this.title,
    required this.icon,
    required this.items,
    required this.initialSelectedValues,
    required this.onApply,
    this.isGrid = false,
  }) : super(key: key);

  @override
  _MultiSelectFilterSheetState<T> createState() => _MultiSelectFilterSheetState<T>();
}

class _MultiSelectFilterSheetState<T> extends State<_MultiSelectFilterSheet<T>> {
  late Set<T> _selectedValues;

  @override
  void initState() {
    super.initState();
    _selectedValues = Set<T>.from(widget.initialSelectedValues);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisAlignment: isMobile ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: isMobile ? double.infinity : 400,
              maxHeight: isMobile ? MediaQuery.of(context).size.height * 0.8 : 500,
            ),
            margin: isMobile ? EdgeInsets.zero : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: isMobile 
                  ? BorderRadius.vertical(top: Radius.circular(32))
                  : BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                // Header
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 16, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(widget.icon, color: Colors.indigo.shade700, size: 24),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              'Birden fazla seçim yapabilirsiniz',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blueGrey.shade400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded, color: Colors.blueGrey.shade400),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey.shade50,
                        ),
                      ),
                    ],
                  ),
                ),
                
                Divider(height: 1, color: Colors.grey.shade100),
                
                Flexible(
                  child: widget.isGrid 
                    ? GridView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.all(24),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isMobile ? 2 : 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 2.2,
                        ),
                        itemCount: widget.items.length,
                        itemBuilder: (context, index) => _buildItem(widget.items[index]),
                      )
                    : ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: 400),
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          itemCount: widget.items.length,
                          itemBuilder: (context, index) => Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: _buildItem(widget.items[index]),
                          ),
                        ),
                      ),
                ),
                
                // Action Buttons
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, isMobile ? 32 : 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            setState(() => _selectedValues.clear());
                          },
                          child: Text('Temizle'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey.shade600,
                            padding: EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            widget.onApply(_selectedValues);
                            Navigator.pop(context);
                          },
                          child: Text('Uygula', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo.shade600,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(FilterItem<T> item) {
    final isSelected = _selectedValues.contains(item.value);
    
    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedValues.remove(item.value);
          } else {
            _selectedValues.add(item.value);
          }
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.indigo.shade600 : Colors.grey.shade200,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: widget.isGrid ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(
              item.icon,
              size: 20,
              color: isSelected ? Colors.indigo.shade600 : Colors.indigo.shade300,
            ),
            SizedBox(width: 12),
            Flexible(
              child: Text(
                item.label,
                style: TextStyle(
                  color: isSelected ? Colors.indigo.shade700 : Color(0xFF334155),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!widget.isGrid && isSelected) ...[
              Spacer(),
              Icon(Icons.check_circle_rounded, color: Colors.indigo.shade600, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}
