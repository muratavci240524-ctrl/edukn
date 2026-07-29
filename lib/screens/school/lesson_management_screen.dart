import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/lesson_model.dart';
import '../../services/term_service.dart';

int compareClassNamesNatural(String nameA, String nameB) {
  final reg = RegExp(r'\d+');
  final matchA = reg.firstMatch(nameA);
  final matchB = reg.firstMatch(nameB);

  final int numA = matchA != null ? int.parse(matchA.group(0)!) : 0;
  final int numB = matchB != null ? int.parse(matchB.group(0)!) : 0;

  if (numA != numB) {
    return numA.compareTo(numB);
  }
  return nameA.compareTo(nameB);
}

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
  Stream<QuerySnapshot>? _lessonsStream; // Caching Stream object for lessons
  Stream<QuerySnapshot>? _selectedLessonAssignmentsStream; // Stabil stream — sadece ders değişince yenilenir
  String? _streamLessonId; // Hangi lessonId için stream açık?

  void _updateLessonsStream() {
    _lessonsStream = FirebaseFirestore.instance
        .collection('lessons')
        .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('termId', isEqualTo: _currentTermId ?? 'loading_term_id')
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  /// Sadece farklı bir ders seçildiğinde stream'i yeniler.
  /// Build() içinde değil, setState() içinde çağrılmalı.
  void _updateAssignmentsStream(String lessonId) {
    if (_streamLessonId != lessonId) {
      _streamLessonId = lessonId;
      _selectedLessonAssignmentsStream = FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('lessonId', isEqualTo: lessonId)
          .where('isActive', isEqualTo: true)
          .snapshots();
    }
  }

  void _clearAssignmentsStream() {
    _streamLessonId = null;
    _selectedLessonAssignmentsStream = null;
  }

  @override
  void initState() {
    super.initState();
    _updateLessonsStream();
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
    if (effectiveTermId == null) return;
    if (mounted && _currentTermId != effectiveTermId) {
      setState(() {
        _currentTermId = effectiveTermId;
        _isViewingPastTerm = selectedTermId != null && selectedTermId != activeTermId;
        _selectedLessonId = null;
        _selectedLesson = null;
        _clearAssignmentsStream();
        _updateLessonsStream();
      });
    }
  }
  
  Future<void> _loadTermAndData() async {
    final selectedTermId = await TermService().getSelectedTermId();
    final activeTermId = await TermService().getActiveTermId();
    final effectiveTermId = selectedTermId ?? activeTermId;
    if (mounted) {
      final termChanged = _currentTermId != effectiveTermId;
      setState(() {
        _currentTermId = effectiveTermId;
        _isViewingPastTerm = selectedTermId != null && selectedTermId != activeTermId;
        if (termChanged) {
          _selectedLessonId = null;
          _selectedLesson = null;
          _clearAssignmentsStream();
        }
        _updateLessonsStream();
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
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .where('type', isEqualTo: 'staff')
          .get();

      setState(() {
        _teachers = snapshot.docs
            .where((d) => (d.data()['title'] ?? '').toString().toLowerCase() == 'ogretmen')
            .map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          if (data['fullName'] == null || data['fullName'].toString().trim().isEmpty) {
            data['fullName'] = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
          }
          return data;
        }).toList();
      });
    } catch (e) {
      print('Öğretmen yükleme hatası: $e');
    }
  }

  Stream<QuerySnapshot> _getLessonsStream() {
    return _lessonsStream ?? const Stream.empty();
  }

  /// Her ders için atanmış sınıf sayısını canlı izle
  Stream<int> _getAssignmentCountStream(String lessonId) {
    return FirebaseFirestore.instance
        .collection('lessonAssignments')
        .where('lessonId', isEqualTo: lessonId)
        .where('institutionId', isEqualTo: widget.institutionId)
        .snapshots()
        .map((s) => s.docs.length);
  }

  List<LessonModel> _filterLessons(List<LessonModel> lessons) {
    var filtered = lessons;
    
    // Dönem filtresi: sadece seçili döneme ait olanları göster
    final effectiveTermId = _currentTermId ?? 'loading_term_id';
    filtered = filtered.where((l) => l.termId == effectiveTermId).toList();
    
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

  Future<void> _showClassAssignmentSheet(LessonModel lesson) async {
    await showModalBottomSheet(
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
    // StreamBuilder direkt Firestore'dan dinlediği için ek setState gerekmez
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

  Future<void> _showCopyLessonsFromTermDialog() async {
    try {
      // 1. Fetch terms
      final termsSnapshot = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final termsList = termsSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Filter out the current term
      final targetTerms = termsList.where((t) => t['id'] != _currentTermId).toList();

      if (targetTerms.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kopyalama yapılabilecek başka bir dönem bulunamadı.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      String selectedSourceTermId = targetTerms.first['id'];
      String selectedSourceTermName = targetTerms.first['name'] ?? '${targetTerms.first['startYear']}-${targetTerms.first['endYear']}';
      bool copyClasses = true;
      bool copyTeachers = false;

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    const Icon(Icons.copy_all, color: Colors.indigo),
                    const SizedBox(width: 8),
                    const Text('Dönemden Ders Kopyala'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Seçeceğiniz kaynak dönemdeki tüm aktif dersler bu döneme kopyalanacaktır.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Kaynak Dönem',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        prefixIcon: const Icon(Icons.calendar_today),
                      ),
                      value: selectedSourceTermId,
                      items: targetTerms.map((t) {
                        final name = t['name'] ?? '${t['startYear']}-${t['endYear']}';
                        return DropdownMenuItem(
                          value: t['id'] as String,
                          child: Text(name),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedSourceTermId = val;
                            final term = targetTerms.firstWhere((t) => t['id'] == val);
                            selectedSourceTermName = term['name'] ?? '${term['startYear']}-${term['endYear']}';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Derslerin Şube Atamalarını Kopyala', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Derslerin hangi şubelere atandığını (haftalık saatleriyle) aktarır.', style: TextStyle(fontSize: 12)),
                      value: copyClasses,
                      activeColor: Colors.indigo,
                      onChanged: (val) {
                        setDialogState(() {
                          copyClasses = val;
                          if (!copyClasses) {
                            copyTeachers = false;
                          }
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Atamalarla Birlikte Öğretmenleri de Kopyala', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Derslerde atanan öğretmenleri de yeni döneme aktarır.', style: TextStyle(fontSize: 12)),
                      value: copyTeachers,
                      activeColor: Colors.indigo,
                      onChanged: copyClasses
                          ? (val) {
                              setDialogState(() {
                                copyTeachers = val;
                              });
                            }
                          : null,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('İptal'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(dialogContext); // Close dialog
                      await _executeCopyLessons(
                        selectedSourceTermId,
                        selectedSourceTermName,
                        copyClasses: copyClasses,
                        copyTeachers: copyTeachers,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Kopyala'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _executeCopyLessons(
    String sourceTermId, 
    String sourceTermName, {
    required bool copyClasses,
    required bool copyTeachers,
  }) async {
    // Show a loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final activeTermId = _currentTermId;
      if (activeTermId == null) throw 'Aktif dönem yüklenemedi.';

      // 1. Fetch all lessons of the source term for this school type
      final sourceLessonsSnap = await FirebaseFirestore.instance
          .collection('lessons')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('termId', isEqualTo: sourceTermId)
          .where('isActive', isEqualTo: true)
          .get();

      if (sourceLessonsSnap.docs.isEmpty) {
        Navigator.pop(context); // Close loader
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$sourceTermName döneminde kopyalanacak ders bulunamadı.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // 2. Fetch target lessons & classes to prevent duplicates and map names
      final targetLessonsSnap = await FirebaseFirestore.instance
          .collection('lessons')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('termId', isEqualTo: activeTermId)
          .where('isActive', isEqualTo: true)
          .get();

      // Maps lessonName (lowercase) -> lessonId in target term
      final targetLessonMap = {
        for (var doc in targetLessonsSnap.docs)
          (doc.data()['lessonName'] ?? '').toString().trim().toLowerCase(): doc.id
      };

      // Fetch all classes of source term
      final sourceClassesSnap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('termId', isEqualTo: sourceTermId)
          .where('isActive', isEqualTo: true)
          .get();

      // Fetch all classes of target term
      final targetClassesSnap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('termId', isEqualTo: activeTermId)
          .where('isActive', isEqualTo: true)
          .get();

      // Maps className (lowercase) -> classDoc/id in target term
      final targetClassMap = {
        for (var doc in targetClassesSnap.docs)
          (doc.data()['className'] ?? '').toString().trim().toLowerCase(): doc.id
      };

      // Fetch all lessonAssignments of source term
      final sourceAssignmentsSnap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('termId', isEqualTo: sourceTermId)
          .where('isActive', isEqualTo: true)
          .get();

      // Fetch target lessonAssignments to prevent duplicates
      final targetAssignmentsSnap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('termId', isEqualTo: activeTermId)
          .where('isActive', isEqualTo: true)
          .get();

      final targetAssignmentSet = {
        for (var doc in targetAssignmentsSnap.docs)
          '${doc.data()['classId']}_${doc.data()['lessonId']}'
      };

      final batch = FirebaseFirestore.instance.batch();
      int copiedLessons = 0;
      int copiedClasses = 0;
      int copiedAssignments = 0;

      // First step: Copy or map lessons
      for (var doc in sourceLessonsSnap.docs) {
        final data = doc.data();
        final lessonName = (data['lessonName'] ?? '').toString().trim();
        final lessonNameLower = lessonName.toLowerCase();

        String targetLessonId;
        if (targetLessonMap.containsKey(lessonNameLower)) {
          targetLessonId = targetLessonMap[lessonNameLower]!;
        } else {
          // Create new lesson
          final newLessonRef = FirebaseFirestore.instance.collection('lessons').doc();
          targetLessonId = newLessonRef.id;

          final newLessonData = {
            'lessonName': lessonName,
            'shortName': (data['shortName'] ?? '').toString().trim(),
            'branchId': data['branchId'],
            'branchName': data['branchName'],
            'schoolTypeId': widget.schoolTypeId,
            'institutionId': widget.institutionId,
            'termId': activeTermId,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'isActive': true,
          };
          batch.set(newLessonRef, newLessonData);
          targetLessonMap[lessonNameLower] = targetLessonId;
          copiedLessons++;
        }

        // Second step: If copyClasses is enabled, process assignments for this lesson
        if (copyClasses) {
          final sourceLessonId = doc.id;
          final assignmentsForThisLesson = sourceAssignmentsSnap.docs.where(
            (aDoc) => aDoc.data()['lessonId'] == sourceLessonId
          ).toList();

          for (var aDoc in assignmentsForThisLesson) {
            final aData = aDoc.data();
            final sourceClassId = aData['classId'] as String;

            // Find source class name using safe type-safe iteration
            QueryDocumentSnapshot<Map<String, dynamic>>? sourceClassDoc;
            for (final cDoc in sourceClassesSnap.docs) {
              if (cDoc.id == sourceClassId) {
                sourceClassDoc = cDoc;
                break;
              }
            }
            if (sourceClassDoc == null) continue;

            final classData = sourceClassDoc.data();
            final className = (classData['className'] ?? '').toString().trim();
            final classNameLower = className.toLowerCase();

            // Find or copy target class
            String targetClassId;
            if (targetClassMap.containsKey(classNameLower)) {
              targetClassId = targetClassMap[classNameLower]!;
            } else {
              // Copy class
              final newClassRef = FirebaseFirestore.instance.collection('classes').doc();
              targetClassId = newClassRef.id;

              final newClassData = {
                'className': className,
                'shortName': (classData['shortName'] ?? '').toString().trim(),
                'classTypeId': classData['classTypeId'],
                'classTypeName': classData['classTypeName'],
                'classTeacherId': null,
                'classTeacherName': null,
                'classLevel': classData['classLevel'],
                'description': classData['description'],
                'schoolTypeId': widget.schoolTypeId,
                'schoolTypeName': widget.schoolTypeName,
                'institutionId': widget.institutionId,
                'termId': activeTermId,
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
                'isActive': true,
              };
              batch.set(newClassRef, newClassData);
              targetClassMap[classNameLower] = targetClassId;
              copiedClasses++;
            }

            // Copy assignment if not exists
            final assignmentKey = '${targetClassId}_$targetLessonId';
            if (!targetAssignmentSet.contains(assignmentKey)) {
              final newAssignmentRef = FirebaseFirestore.instance.collection('lessonAssignments').doc();
              final newAssignmentData = {
                'classId': targetClassId,
                'className': className,
                'lessonId': targetLessonId,
                'lessonName': lessonName,
                'weeklyHours': aData['weeklyHours'] ?? 0,
                'teacherIds': copyTeachers ? (aData['teacherIds'] ?? []) : [],
                'teacherNames': copyTeachers ? (aData['teacherNames'] ?? []) : [],
                'schoolTypeId': widget.schoolTypeId,
                'institutionId': widget.institutionId,
                'termId': activeTermId,
                'isActive': true,
                'createdAt': FieldValue.serverTimestamp(),
              };
              batch.set(newAssignmentRef, newAssignmentData);
              targetAssignmentSet.add(assignmentKey);
              copiedAssignments++;
            }
          }
        }
      }

      await batch.commit();

      Navigator.pop(context); // Close loader

      String successMessage = '$copiedLessons adet ders kopyalandı.';
      if (copyClasses) {
        successMessage += '\n$copiedClasses adet şube ve $copiedAssignments adet ders ataması başarıyla aktarıldı.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ $successMessage'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Close loader
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Kopyalama hatası: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.indigo),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (value) {
              if (value == 'copy_from_term') {
                _showCopyLessonsFromTermDialog();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'copy_from_term',
                child: Row(
                  children: [
                    Icon(Icons.copy_all, size: 18, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('Dönemden Ders Kopyala'),
                  ],
                ),
              ),
            ],
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
                    // Sınıf atama sayısı — canlı stream ile güncellenir
                    StreamBuilder<int>(
                      stream: _getAssignmentCountStream(lesson.id!),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          print('Count Error: ${snap.error}');
                          return Icon(Icons.error, size: 16, color: Colors.red);
                        }
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
                      // Stream'i stabil tut: sadece ders değişince yenilenir
                      _updateAssignmentsStream(lesson.id!);
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
          _LessonAssignmentsPanel(
            lessonId: lessonData['id'],
            lessonBranchName: lessonData['branchName'] ?? '',
            institutionId: widget.institutionId,
            onEditAssignment: (docId, data) =>
                _showEditAssignmentSheet(docId, data, lessonBranchName: lessonData['branchName'] ?? ''),
            onDeleteAssignment: (docId, className) =>
                _confirmDeleteAssignment(docId, className),
          ),
        ],
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
      menuMaxHeight: 260,
      borderRadius: BorderRadius.circular(16),
      elevation: 8,
      dropdownColor: Colors.white,
      decoration: InputDecoration(
        labelText: 'Branş *',
        prefixIcon: const Icon(Icons.category, color: Colors.indigo),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      items: widget.branchNames.map((n) => DropdownMenuItem(
        value: n,
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.indigo.shade400,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              n,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
            ),
          ],
        ),
      )).toList(),
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
      // termId burada kullanılmıyor, _save() metodunda ayrıca alınıyor
      final classSnap = await FirebaseFirestore.instance.collection('classes').where('schoolTypeId', isEqualTo: widget.schoolTypeId).where('institutionId', isEqualTo: widget.institutionId).where('isActive', isEqualTo: true).get();
      final classes = classSnap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      classes.sort((a, b) {
        final nameA = (a['className'] ?? a['name'] ?? '').toString();
        final nameB = (b['className'] ?? b['name'] ?? '').toString();
        return compareClassNamesNatural(nameA, nameB);
      });
      
      final userSnap = await FirebaseFirestore.instance.collection('users').where('institutionId', isEqualTo: widget.institutionId).where('type', isEqualTo: 'staff').where('isActive', isEqualTo: true).get();
      final teachers = userSnap.docs.where((d) => (d.data()['title'] ?? '').toString().toLowerCase() == 'ogretmen').map((d) {
        final data = d.data();
        if (data['fullName'] == null || data['fullName'].toString().trim().isEmpty) {
          data['fullName'] = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        }
        return {...data, 'id': d.id, 'totalHours': 0};
      }).toList();

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
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: val,
          hint: Text(hint, style: const TextStyle(fontSize: 12)),
          isExpanded: true,
          menuMaxHeight: 260,
          borderRadius: BorderRadius.circular(16),
          elevation: 8,
          dropdownColor: Colors.white,
          items: [
            DropdownMenuItem<T>(value: null, child: const Text('Tümü')),
            ...items.map((it) => DropdownMenuItem(value: it, child: Text(it.toString()))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  void _proceedToStep2() {
    if (_selectedClassIds.isEmpty) return;
    _assignments = _selectedClassIds.map((id) {
      final c = _classes.firstWhere((cl) => cl['id'] == id);
      return {'classId': id, 'className': c['className'], 'weeklyHours': 0, 'teacherIds': <String>[], 'teacherNames': <String>[]};
    }).toList();
    _assignments.sort((a, b) {
      final nameA = (a['className'] ?? '').toString();
      final nameB = (b['className'] ?? '').toString();
      return compareClassNamesNatural(nameA, nameB);
    });
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
      final termId = await TermService().getSelectedTermId() ?? await TermService().getActiveTermId();
      for (var a in _assignments) {
        final ref = FirebaseFirestore.instance.collection('lessonAssignments').doc();
        batch.set(ref, {...a, 'lessonId': widget.lesson.id, 'lessonName': widget.lesson.lessonName, 'institutionId': widget.institutionId, 'schoolTypeId': widget.schoolTypeId, 'termId': termId, 'isActive': true, 'createdAt': FieldValue.serverTimestamp()});
      }
      await batch.commit();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Atamalar kaydedildi'), backgroundColor: Colors.green));
      }
    } catch (e) {
      print(e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
class _LessonDetailPage extends StatefulWidget {
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
  State<_LessonDetailPage> createState() => _LessonDetailPageState();
}

class _LessonDetailPageState extends State<_LessonDetailPage> {
  late Stream<QuerySnapshot> _assignmentsStream;

  @override
  void initState() {
    super.initState();
    _assignmentsStream = FirebaseFirestore.instance
        .collection('lessonAssignments')
        .where('lessonId', isEqualTo: widget.lesson.id)
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lesson.lessonName),
        actions: [
          IconButton(
            icon: Icon(Icons.edit),
            onPressed: widget.onEdit,
          ),
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: widget.onDelete,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onAssign,
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
                            widget.lesson.lessonName,
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            widget.lesson.branchName,
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
              stream: _assignmentsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
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
  late List<Map<String, dynamic>> _sortedTeachers;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  @override
  void initState() { 
    super.initState(); 
    _selIds = List.from(widget.initialIds); 
    
    // Öğretmenleri sırala: İlgili branşta olanlar en üste, geri kalanı alfabetik
    _sortedTeachers = List.from(widget.teachers);
    _sortedTeachers.sort((a, b) {
      final isMatchA = a['branch'] == widget.lessonBranch;
      final isMatchB = b['branch'] == widget.lessonBranch;
      
      if (isMatchA && !isMatchB) return -1;
      if (!isMatchA && isMatchB) return 1;
      
      final nameA = (a['fullName'] ?? '').toString().toLowerCase();
      final nameB = (b['fullName'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final filteredTeachers = _sortedTeachers.where((t) {
      if (_searchQuery.isEmpty) return true;
      final name = (t['fullName'] ?? '').toString().toLowerCase();
      final branch = (t['branch'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery) || branch.contains(_searchQuery);
    }).toList();

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(children: [
            const Text('Öğretmen Seç', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${_selIds.length} seçili', style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Öğretmen veya branş ara...',
              prefixIcon: const Icon(Icons.search, color: Colors.indigo),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.indigo, width: 2),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
        ),
        Expanded(
          child: filteredTeachers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Aradığınız kriterlere uygun öğretmen bulunamadı',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: filteredTeachers.length,
                  itemBuilder: (context, i) {
                    final t = filteredTeachers[i];
                    final sel = _selIds.contains(t['id']);
                    final isMatch = t['branch'] == widget.lessonBranch;
                    return CheckboxListTile(
                      value: sel,
                      title: Text(t['fullName'] ?? ''),
                      subtitle: Text(
                        t['branch'] ?? '',
                        style: TextStyle(color: isMatch ? Colors.green.shade700 : Colors.grey),
                      ),
                      onChanged: (v) => setState(() => v! ? _selIds.add(t['id']) : _selIds.remove(t['id'])),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                final names = _selIds.map((id) => widget.teachers.firstWhere((t) => t['id'] == id, orElse: () => {'fullName': ''})['fullName'] as String).where((n) => n.isNotEmpty).toList();
                Navigator.pop(context, {'ids': _selIds, 'names': names});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade900,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Tamam', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Atanan Sınıflar Paneli — tam izole StatefulWidget
// Parent setState çağrılarından BAĞIMSIZ stream yönetimi sağlar.
// ─────────────────────────────────────────────────────────────────────────────
class _LessonAssignmentsPanel extends StatefulWidget {
  final String lessonId;
  final String lessonBranchName;
  final String institutionId;
  final void Function(String docId, Map<String, dynamic> data) onEditAssignment;
  final void Function(String docId, String className) onDeleteAssignment;

  const _LessonAssignmentsPanel({
    required this.lessonId,
    required this.lessonBranchName,
    required this.institutionId,
    required this.onEditAssignment,
    required this.onDeleteAssignment,
  });

  @override
  State<_LessonAssignmentsPanel> createState() => _LessonAssignmentsPanelState();
}

class _LessonAssignmentsPanelState extends State<_LessonAssignmentsPanel> {
  late Stream<QuerySnapshot> _stream;
  String _sortBy = 'class';

  @override
  void initState() {
    super.initState();
    _createStream();
  }

  @override
  void didUpdateWidget(_LessonAssignmentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lessonId != widget.lessonId) {
      _createStream();
    }
  }

  void _createStream() {
    // isActive filtresi YOK: Belgede isActive eksik veya false olsa bile görünsün.
    // Silme işlemi için isActive:false kullanılıyorsa aşağıya eklenebilir.
    _stream = FirebaseFirestore.instance
        .collection('lessonAssignments')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('lessonId', isEqualTo: widget.lessonId)
        .snapshots();
  }

  Widget _sortButton(String value, String label, IconData icon) {
    final isSelected = _sortBy == value;
    return InkWell(
      onTap: () => setState(() => _sortBy = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.grey.shade700),
            const SizedBox(width: 4),
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          print('Panel Error: ${snapshot.error}');
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Bir hata oluştu: ${snapshot.error}', style: TextStyle(color: Colors.red)),
          );
        }

        // Yüklenirken — ama daha önce veri varsa onu saklamadan bekle
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Bu ders henüz hiçbir sınıfa atanmamış',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ),
          );
        }

        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['isActive'] != false;
        }).toList();

        if (docs.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Bu ders henüz hiçbir sınıfa atanmamış',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ),
          );
        }
        docs.sort((a, b) {
          final dA = a.data() as Map<String, dynamic>;
          final dB = b.data() as Map<String, dynamic>;
          if (_sortBy == 'teacher') {
            final tA = ((dA['teacherNames'] as List?)?.isNotEmpty == true)
                ? (dA['teacherNames'] as List).first.toString()
                : 'zzz';
            final tB = ((dB['teacherNames'] as List?)?.isNotEmpty == true)
                ? (dB['teacherNames'] as List).first.toString()
                : 'zzz';
            final cmp = tA.compareTo(tB);
            if (cmp != 0) return cmp;
          }
          return compareClassNamesNatural(dA['className'] ?? '', dB['className'] ?? '');
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${docs.length} sınıf atanmış',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Spacer(),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _sortButton('class', 'Sınıf', Icons.class_),
                      _sortButton('teacher', 'Öğretmen', Icons.person),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => widget.onEditAssignment(doc.id, data),
                  leading: CircleAvatar(
                    backgroundColor: Colors.green.shade100,
                    child: const Icon(Icons.class_, color: Colors.green),
                  ),
                  title: Text(data['className'] ?? ''),
                  subtitle: Text(
                    '${data['weeklyHours']} saat/hafta • '
                    '${(data['teacherNames'] as List?)?.join(', ') ?? 'Öğretmen atanmamış'}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Atamayı Sil',
                    onPressed: () => widget.onDeleteAssignment(doc.id, data['className'] ?? ''),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
