import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/lesson_model.dart';
import '../../services/term_service.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';


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
  String? _selectedSubTermId; // Seçili alt dönem
  String? _selectedSubTermName; // Seçili alt dönemin adı
  String? _autoDetectedPeriodId; // Tarihe göre otomatik tespit edilen alt dönem
  List<Map<String, dynamic>> _workPeriods = []; // Aktif akademik dönemdeki alt dönemler

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
      await _autoSelectActiveSubTerm(effectiveTermId);
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
    await _autoSelectActiveSubTerm(effectiveTermId);
    _loadBranchNames();
    _loadTeachers();
  }

  /// Mevcut tarihe (DateTime.now) göre uygun alt dönemi otomatik tespit eder ve seçer.
  Future<void> _autoSelectActiveSubTerm(String? termId) async {
    if (termId == null || termId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('workPeriods')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('termId', isEqualTo: termId)
          .where('isActive', isEqualTo: true)
          .get();

      final periods = snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList()
        ..sort((a, b) {
          final aStart = (a['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          final bStart = (b['startDate'] as Timestamp?)?.toDate() ?? DateTime(2000);
          return aStart.compareTo(bStart);
        });

      if (periods.isEmpty) {
        if (mounted) {
          setState(() {
            _workPeriods = [];
            _selectedSubTermId = null;
            _selectedSubTermName = null;
            _autoDetectedPeriodId = null;
          });
        }
        return;
      }

      final now = DateTime.now();
      Map<String, dynamic>? matchedPeriod;

      // 1. Bugünün başlangıç ve bitiş tarihi arasında olduğu alt dönemi bul
      for (final p in periods) {
        final start = (p['startDate'] as Timestamp?)?.toDate();
        final end = (p['endDate'] as Timestamp?)?.toDate();
        if (start != null && end != null) {
          final startDay = DateTime(start.year, start.month, start.day);
          final endDay = DateTime(end.year, end.month, end.day, 23, 59, 59);
          if (!now.isBefore(startDay) && !now.isAfter(endDay)) {
            matchedPeriod = p;
            break;
          }
        }
      }

      // 2. Tarih aralığında bulunamadıysa: Gelecek en yakın veya en sonuncu alt dönemi seç
      if (matchedPeriod == null) {
        for (final p in periods) {
          final start = (p['startDate'] as Timestamp?)?.toDate();
          if (start != null && start.isAfter(now)) {
            matchedPeriod = p;
            break;
          }
        }
        matchedPeriod ??= periods.last;
      }

      if (mounted) {
        final autoId = matchedPeriod['id'] as String;
        final autoName = matchedPeriod['periodName'] as String? ?? 'Alt Dönem';
        setState(() {
          _workPeriods = periods;
          _autoDetectedPeriodId = autoId;
          if (_selectedSubTermId == null || !periods.any((p) => p['id'] == _selectedSubTermId)) {
            _selectedSubTermId = autoId;
            _selectedSubTermName = autoName;
          } else {
            final cur = periods.firstWhere((p) => p['id'] == _selectedSubTermId);
            _selectedSubTermName = cur['periodName'] as String? ?? 'Alt Dönem';
          }
        });
      }
    } catch (e) {
      debugPrint('Otomatik alt dönem belirleme hatası: $e');
    }
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

  /// Her ders için atanmış sınıf sayısını canlı izle (seçili alt döneme göre filtrelenmiş)
  Stream<int> _getAssignmentCountStream(String lessonId) {
    return FirebaseFirestore.instance
        .collection('lessonAssignments')
        .where('lessonId', isEqualTo: lessonId)
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.where((d) {
              final data = d.data();
              final stId = data['subTermId'] ?? data['periodId'];
              if (_selectedSubTermId != null && _selectedSubTermId!.isNotEmpty) {
                return stId == _selectedSubTermId;
              }
              return true;
            }).length);
  }

  List<LessonModel> _filterLessons(List<LessonModel> lessons) {
    var filtered = lessons;
    
    // Dönem filtresi: sadece seçili döneme ait olanları göster
    final effectiveTermId = _currentTermId ?? 'loading_term_id';
    filtered = filtered.where((l) => l.termId == effectiveTermId).toList();

    // Alt dönem filtresi: Seçili alt döneme ait dersleri göster (yalnızca o alt döneme ait olanlar)
    if (_selectedSubTermId != null && _selectedSubTermId!.isNotEmpty) {
      filtered = filtered.where((l) => l.subTermId == _selectedSubTermId).toList();
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
        subTermId: _selectedSubTermId,
        subTermName: _selectedSubTermName,
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
        termId: _currentTermId,
        subTermId: _selectedSubTermId ?? lesson.subTermId,
        subTermName: _selectedSubTermName ?? lesson.subTermName,
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

  Future<void> _deleteAllAssignments(String lessonId, String lessonName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.playlist_remove, color: Colors.orange),
          SizedBox(width: 12),
          Expanded(child: Text('Tum Atamalari Kaldir')),
        ]),
        content: const Text('Bu dersin tum sinif atamalari kaldirilacak. Bu islem geri alinamaz!'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Iptal')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            icon: const Icon(Icons.delete_sweep, size: 18),
            label: const Text('Evet, Tumunu Sil'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lessonAssignments')
          .where('lessonId', isEqualTo: lessonId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      int deletedCount = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final stId = data['subTermId'] ?? data['periodId'];
        if (_selectedSubTermId != null && stId != null && stId.toString().isNotEmpty && stId != _selectedSubTermId) {
          continue; // Farklı alt döneme ait atamalara dokunma
        }
        batch.update(doc.reference, {'isActive': false});
        deletedCount++;
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$deletedCount atama kaldırıldı'), backgroundColor: Colors.orange.shade700),
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

  Future<void> _showCopyLessonsFromTermDialog() async {
    if (_selectedSubTermId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lutfen once hedef alt donemi secin.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String sourceType = 'sub';
    String? selectedSourceId;
    String? selectedSourceName;
    List<Map<String, dynamic>> sourceSubTerms = [];
    List<Map<String, dynamic>> sourceTerms = [];
    List<Map<String, dynamic>> sourceLessonsList = [];
    Set<String> selectedLessonIds = {};
    bool copyAll = true;
    bool copyAssignments = false;
    bool copyTeachers = false;
    bool isLoadingLessons = false;

    Future<List<Map<String, dynamic>>> fetchLessonsForSource(String? sourceId, String sType) async {
      if (sourceId == null || sourceId.isEmpty) return [];
      try {
        final snap = await FirebaseFirestore.instance
            .collection('lessons')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('isActive', isEqualTo: true)
            .get();

        final filtered = snap.docs.where((d) {
          final data = d.data();
          if (sType == 'sub') {
            final sId = data['subTermId'] ?? data['periodId'];
            return sId == sourceId;
          } else {
            return data['termId'] == sourceId;
          }
        }).toList();

        return filtered.map((d) {
          final data = d.data();
          return <String, dynamic>{
            'id': d.id,
            'lessonName': data['lessonName'] ?? '',
            'branchName': data['branchName'] ?? '',
          };
        }).toList();
      } catch (e) {
        debugPrint('Ders listesi yukleme hatasi: $e');
        return [];
      }
    }

    try {
      final periodsSnap = await FirebaseFirestore.instance
          .collection('workPeriods')
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('termId', isEqualTo: _currentTermId)
          .where('isActive', isEqualTo: true)
          .get();
      sourceSubTerms = periodsSnap.docs
          .where((d) => d.id != _selectedSubTermId)
          .map((d) => <String, dynamic>{'id': d.id, 'name': d.data()['periodName'] ?? 'Alt Donem'})
          .toList();

      final termsSnap = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      sourceTerms = termsSnap.docs
          .map((d) => <String, dynamic>{
                'id': d.id,
                'name': d.data()['name'] ?? '${d.data()['startYear']}-${d.data()['endYear']}'
              })
          .toList();

      if (sourceSubTerms.isNotEmpty) {
        selectedSourceId = sourceSubTerms.first['id'];
        selectedSourceName = sourceSubTerms.first['name'];
      } else if (sourceTerms.isNotEmpty) {
        sourceType = 'term';
        selectedSourceId = sourceTerms.first['id'];
        selectedSourceName = sourceTerms.first['name'];
      }

      if (selectedSourceId != null) {
        sourceLessonsList = await fetchLessonsForSource(selectedSourceId, sourceType);
        selectedLessonIds = sourceLessonsList.map((l) => l['id'] as String).toSet();
      }
    } catch (e) {
      debugPrint('Kopyala kaynak yukleme hatasi: $e');
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (ctx2, scrollCtrl) => StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> loadSourceLessons() async {
              if (selectedSourceId == null) return;
              setSheetState(() => isLoadingLessons = true);
              final lessons = await fetchLessonsForSource(selectedSourceId, sourceType);
              setSheetState(() {
                sourceLessonsList = lessons;
                selectedLessonIds = sourceLessonsList.map((l) => l['id'] as String).toSet();
                isLoadingLessons = false;
              });
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.copy_all, color: Colors.deepPurple, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Farkli Donemden Kopyala', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                              Text('Hedef: ${_selectedSubTermName ?? 'Secili Alt Donem'}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Expanded(
                    child: ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      children: [
                        Text('Kaynak Secimi', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700, fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _copyTabButton(
                                label: 'Farkli Alt Donem',
                                icon: Icons.subdirectory_arrow_right,
                                selected: sourceType == 'sub',
                                onTap: () {
                                  setSheetState(() {
                                    sourceType = 'sub';
                                    selectedSourceId = sourceSubTerms.isNotEmpty ? sourceSubTerms.first['id'] : null;
                                    selectedSourceName = sourceSubTerms.isNotEmpty ? sourceSubTerms.first['name'] : null;
                                    sourceLessonsList = [];
                                    selectedLessonIds.clear();
                                  });
                                  if (selectedSourceId != null) loadSourceLessons();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _copyTabButton(
                                label: 'Farkli Donem',
                                icon: Icons.calendar_month,
                                selected: sourceType == 'term',
                                onTap: () {
                                  setSheetState(() {
                                    sourceType = 'term';
                                    selectedSourceId = sourceTerms.isNotEmpty ? sourceTerms.first['id'] : null;
                                    selectedSourceName = sourceTerms.isNotEmpty ? sourceTerms.first['name'] : null;
                                    sourceLessonsList = [];
                                    selectedLessonIds.clear();
                                  });
                                  if (selectedSourceId != null) loadSourceLessons();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Builder(builder: (_) {
                          final items = sourceType == 'sub' ? sourceSubTerms : sourceTerms;
                          if (items.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: Text(
                                sourceType == 'sub' ? 'Bu donemde baska alt donem bulunamadi.' : 'Baska donem bulunamadi.',
                                style: TextStyle(color: Colors.orange.shade800),
                              ),
                            );
                          }
                          return DropdownButtonFormField<String>(
                            decoration: InputDecoration(
                              labelText: sourceType == 'sub' ? 'Kaynak Alt Donem' : 'Kaynak Donem',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              prefixIcon: const Icon(Icons.source),
                            ),
                            initialValue: selectedSourceId,
                            items: items.map((item) {
                              return DropdownMenuItem<String>(
                                value: item['id'] as String,
                                child: Text(item['name'] as String),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val == null) return;
                              setSheetState(() {
                                selectedSourceId = val;
                                final src = items.firstWhere((s) => s['id'] == val);
                                selectedSourceName = src['name'] as String;
                                sourceLessonsList = [];
                                selectedLessonIds.clear();
                              });
                              loadSourceLessons();
                            },
                          );
                        }),
                        const SizedBox(height: 20),
                        const Divider(),
                        SwitchListTile(
                          title: const Text('Tum Dersleri Kopyala', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('Kapatinca kopyalamak istedigin dersleri secebilirsin'),
                          value: copyAll,
                          activeThumbColor: Colors.deepPurple,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) {
                            setSheetState(() {
                              copyAll = val;
                              if (val && sourceLessonsList.isNotEmpty) {
                                selectedLessonIds = sourceLessonsList.map((l) => l['id'] as String).toSet();
                              }
                            });
                          },
                        ),
                        if (!copyAll) ...[
                          const SizedBox(height: 8),
                          if (isLoadingLessons)
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(strokeWidth: 2.5),
                                    SizedBox(height: 12),
                                    Text('Dersler yükleniyor...', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            )
                          else if (sourceLessonsList.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.amber.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.amber.shade800),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      sourceType == 'sub'
                                          ? 'Seçilen kaynak alt dönemde kopyalanacak ders bulunamadı.'
                                          : 'Seçilen kaynak dönemde kopyalanacak ders bulunamadı.',
                                      style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${selectedLessonIds.length} / ${sourceLessonsList.length} ders seçildi',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                                ),
                                Row(
                                  children: [
                                    TextButton(
                                      onPressed: () {
                                        setSheetState(() {
                                          selectedLessonIds = sourceLessonsList.map((l) => l['id'] as String).toSet();
                                        });
                                      },
                                      child: const Text('Tümünü Seç', style: TextStyle(fontSize: 12)),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        setSheetState(() {
                                          selectedLessonIds.clear();
                                        });
                                      },
                                      child: const Text('Temizle', style: TextStyle(fontSize: 12, color: Colors.red)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 260),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: sourceLessonsList.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                                itemBuilder: (context, idx) {
                                  final lesson = sourceLessonsList[idx];
                                  final lid = lesson['id'] as String;
                                  return CheckboxListTile(
                                    dense: true,
                                    title: Text(lesson['lessonName'] as String, style: const TextStyle(fontWeight: FontWeight.w500)),
                                    subtitle: Text(lesson['branchName'] as String, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                    value: selectedLessonIds.contains(lid),
                                    activeColor: Colors.deepPurple,
                                    onChanged: (val) {
                                      setSheetState(() {
                                        if (val == true) {
                                          selectedLessonIds.add(lid);
                                        } else {
                                          selectedLessonIds.remove(lid);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                        ],
                        const Divider(),
                        SwitchListTile(
                          title: const Text('Dersleri Sinifa Ata', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('Kaynak donemdeki sinif atamalari (ayni saatlerle) kopyalanir'),
                          value: copyAssignments,
                          activeThumbColor: Colors.green,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) => setSheetState(() {
                            copyAssignments = val;
                            if (!val) copyTeachers = false;
                          }),
                        ),
                        SwitchListTile(
                          title: const Text('Ogretmen Atamalarini Kopyala', style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            copyAssignments ? 'Atanan ogretmenler de kopyalanir' : 'Once Dersleri Sinifa Ata secenegini acin',
                            style: TextStyle(fontSize: 12, color: copyAssignments ? Colors.grey.shade600 : Colors.grey.shade400),
                          ),
                          value: copyTeachers,
                          activeThumbColor: Colors.blue,
                          contentPadding: EdgeInsets.zero,
                          onChanged: copyAssignments ? (val) => setSheetState(() => copyTeachers = val) : null,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(context).padding.bottom + 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: selectedSourceId == null
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                await _executeCopyLessons(
                                  sourceId: selectedSourceId!,
                                  sourceName: selectedSourceName ?? '',
                                  sourceType: sourceType,
                                  lessonIdFilter: copyAll ? null : Set<String>.from(selectedLessonIds),
                                  copyAssignments: copyAssignments,
                                  copyTeachers: copyTeachers,
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.copy_all),
                        label: const Text('Kopyala', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _copyTabButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? Colors.deepPurple : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: selected ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? Colors.white : Colors.grey.shade700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeCopyLessons({
    required String sourceId,
    required String sourceName,
    required String sourceType,
    Set<String>? lessonIdFilter,
    required bool copyAssignments,
    required bool copyTeachers,
  }) async {
    final targetSubTermId = _selectedSubTermId;
    final targetSubTermName = _selectedSubTermName;
    final activeTermId = _currentTermId;
    if (targetSubTermId == null || activeTermId == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final lessonsSnap = await FirebaseFirestore.instance
          .collection('lessons')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      var sourceLessonDocs = lessonsSnap.docs.where((d) {
        final data = d.data();
        if (sourceType == 'sub') {
          final sId = data['subTermId'] ?? data['periodId'];
          return sId == sourceId;
        } else {
          return data['termId'] == sourceId;
        }
      }).toList();

      if (lessonIdFilter != null) {
        sourceLessonDocs = sourceLessonDocs.where((d) => lessonIdFilter.contains(d.id)).toList();
      }
      if (sourceLessonDocs.isEmpty) {
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$sourceName kaynaginda kopyalanacak ders bulunamadi.'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      final targetLessonsSnap = await FirebaseFirestore.instance
          .collection('lessons')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();
      final targetLessonMap = <String, String>{};
      for (final d in targetLessonsSnap.docs) {
        final data = d.data();
        final sId = data['subTermId'] ?? data['periodId'];
        if (sId == targetSubTermId) {
          final name = (data['lessonName'] ?? '').toString().trim().toLowerCase();
          targetLessonMap[name] = d.id;
        }
      }

      List<QueryDocumentSnapshot<Map<String, dynamic>>> sourceAssignmentDocs = [];
      final targetAssignmentSet = <String>{};
      final targetClassesSnap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('termId', isEqualTo: activeTermId)
          .where('isActive', isEqualTo: true)
          .get();
      final targetClassMap = <String, Map<String, dynamic>>{};
      for (final d in targetClassesSnap.docs) {
        final cn = (d.data()['className'] ?? '').toString().trim().toLowerCase();
        targetClassMap[cn] = {'id': d.id, 'name': d.data()['className'] ?? ''};
      }

      if (copyAssignments) {
        final srcAssignSnap = await FirebaseFirestore.instance
            .collection('lessonAssignments')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('isActive', isEqualTo: true)
            .get();
        sourceAssignmentDocs = srcAssignSnap.docs.where((d) {
          final data = d.data();
          if (sourceType == 'sub') {
            final sId = data['subTermId'] ?? data['periodId'];
            return sId == sourceId;
          } else {
            return data['termId'] == sourceId;
          }
        }).toList();

        final tgtAssignSnap = await FirebaseFirestore.instance
            .collection('lessonAssignments')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('isActive', isEqualTo: true)
            .get();
        for (final d in tgtAssignSnap.docs) {
          final data = d.data();
          final sId = data['subTermId'] ?? data['periodId'];
          if (sId == targetSubTermId) {
            targetAssignmentSet.add('${data['classId']}_${data['lessonId']}');
          }
        }
      }

      final batch = FirebaseFirestore.instance.batch();
      int copiedLessons = 0;
      int copiedAssignmentsCount = 0;

      for (final doc in sourceLessonDocs) {
        final data = doc.data();
        final lessonName = (data['lessonName'] ?? '').toString().trim();
        final lessonNameLower = lessonName.toLowerCase();
        String targetLessonId;
        if (targetLessonMap.containsKey(lessonNameLower)) {
          targetLessonId = targetLessonMap[lessonNameLower]!;
        } else {
          final newRef = FirebaseFirestore.instance.collection('lessons').doc();
          targetLessonId = newRef.id;
          batch.set(newRef, {
            'lessonName': lessonName,
            'shortName': data['shortName'] ?? '',
            'branchId': data['branchId'] ?? '',
            'branchName': data['branchName'] ?? '',
            'schoolTypeId': widget.schoolTypeId,
            'institutionId': widget.institutionId,
            'termId': activeTermId,
            'subTermId': targetSubTermId,
            'periodId': targetSubTermId,
            'subTermName': targetSubTermName,
            'periodName': targetSubTermName,
            'isActive': true,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          targetLessonMap[lessonNameLower] = targetLessonId;
          copiedLessons++;
        }

        if (copyAssignments) {
          final assignsForLesson = sourceAssignmentDocs.where((a) => a.data()['lessonId'] == doc.id).toList();
          for (final aDoc in assignsForLesson) {
            final aData = aDoc.data();
            final className = (aData['className'] ?? '').toString().trim();
            final targetClassEntry = targetClassMap[className.toLowerCase()];
            final targetClassId = targetClassEntry?['id'] as String? ?? aData['classId'] as String?;
            final targetClassName = targetClassEntry?['name'] as String? ?? className;
            if (targetClassId == null) continue;
            final key = '${targetClassId}_$targetLessonId';
            if (!targetAssignmentSet.contains(key)) {
              final newAssignRef = FirebaseFirestore.instance.collection('lessonAssignments').doc();
              batch.set(newAssignRef, {
                'classId': targetClassId,
                'className': targetClassName,
                'lessonId': targetLessonId,
                'lessonName': lessonName,
                'weeklyHours': aData['weeklyHours'] ?? 0,
                'teacherIds': copyTeachers ? (aData['teacherIds'] ?? []) : [],
                'teacherNames': copyTeachers ? (aData['teacherNames'] ?? []) : [],
                'schoolTypeId': widget.schoolTypeId,
                'institutionId': widget.institutionId,
                'termId': activeTermId,
                'subTermId': targetSubTermId,
                'periodId': targetSubTermId,
                'subTermName': targetSubTermName,
                'periodName': targetSubTermName,
                'isActive': true,
                'createdAt': FieldValue.serverTimestamp(),
              });
              targetAssignmentSet.add(key);
              copiedAssignmentsCount++;
            }
          }
        }
      }

      await batch.commit();
      if (!mounted) return;
      Navigator.pop(context);
      String msg = '$copiedLessons ders kopyalandi.';
      if (copyAssignments) msg += ' $copiedAssignmentsCount atama olusturuldu.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green, duration: const Duration(seconds: 4)),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kopyalama hatasi: $e'), backgroundColor: Colors.red),
        );
      }
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.indigo),
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
          if (_selectedSubTermId != null)
            TextButton.icon(
              onPressed: () => _showCopyLessonsFromTermDialog(),
              icon: const Icon(Icons.copy_all, size: 18),
              label: const Text('Kopyala'),
              style: TextButton.styleFrom(foregroundColor: Colors.deepPurple),
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
              SafeStreamBuilder<QuerySnapshot>(
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
          if (_selectedSubTermName != null || _workPeriods.isNotEmpty) ...[
            const SizedBox(height: 10),
            Theme(
              data: Theme.of(context).copyWith(
                cardColor: Colors.white,
              ),
              child: PopupMenuButton<String>(
                tooltip: 'Alt Dönem Değiştir',
                offset: const Offset(0, 42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedSubTermId == _autoDetectedPeriodId
                            ? Icons.event_available_rounded
                            : Icons.calendar_month_rounded,
                        color: _selectedSubTermId == _autoDetectedPeriodId
                            ? Colors.greenAccent
                            : Colors.amberAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedSubTermName != null
                              ? (_selectedSubTermId == _autoDetectedPeriodId
                                  ? '$_selectedSubTermName (Aktif)'
                                  : '$_selectedSubTermName')
                              : 'Alt Dönem Seç',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.swap_horiz_rounded, color: Colors.white70, size: 16),
                    ],
                  ),
                ),
                itemBuilder: (context) {
                  return _workPeriods.map((period) {
                    final id = period['id'] as String;
                    final name = period['periodName'] as String? ?? 'Alt Dönem';
                    final isSelected = id == _selectedSubTermId;
                    final isCurrentByDate = id == _autoDetectedPeriodId;

                    return PopupMenuItem<String>(
                      value: id,
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                            color: isSelected ? Colors.indigo : Colors.grey.shade400,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    color: isSelected ? Colors.indigo.shade900 : Colors.black87,
                                    fontSize: 13,
                                  ),
                                ),
                                if (isCurrentByDate)
                                  Text(
                                    'Şu anki tarih dönemi',
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isCurrentByDate)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Text(
                                'Aktif',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList();
                },
                onSelected: (val) {
                  if (_selectedSubTermId == val) return;
                  final selected = _workPeriods.firstWhere((p) => p['id'] == val, orElse: () => {});
                  setState(() {
                    _selectedSubTermId = val;
                    _selectedSubTermName = selected['periodName'] as String? ?? 'Alt Dönem';
                    _selectedLessonId = null;
                    _selectedLesson = null;
                    _clearAssignmentsStream();
                  });
                },
              ),
            ),
          ],
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
    return SafeStreamBuilder<QuerySnapshot>(
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
                    SafeStreamBuilder<int>(
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
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade500),
                      tooltip: 'Secenekler',
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'edit',
                          child: Row(children: [Icon(Icons.edit, size: 16, color: Colors.indigo), SizedBox(width: 10), Text('Dersi Duzenle')]),
                        ),
                        PopupMenuItem<String>(
                          value: 'assign',
                          child: Row(children: [Icon(Icons.add_circle_outline, size: 16, color: Colors.green), SizedBox(width: 10), Text('Sinif Ata')]),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem<String>(
                          value: 'delete_all',
                          child: Row(children: [Icon(Icons.playlist_remove, size: 16, color: Colors.orange), SizedBox(width: 10), Text('Tum Atamalari Kaldir', style: TextStyle(color: Colors.orange))]),
                        ),
                        PopupMenuItem<String>(
                          value: 'delete_lesson',
                          child: Row(children: [Icon(Icons.delete_forever, size: 16, color: Colors.red), SizedBox(width: 10), Text('Dersi Sil', style: TextStyle(color: Colors.red))]),
                        ),
                      ],
                      onSelected: (value) {
                        switch (value) {
                          case 'edit': _showLessonFormSheet(lessonToEdit: lesson); break;
                          case 'assign': _showClassAssignmentSheet(lesson); break;
                          case 'delete_all': _deleteAllAssignments(lesson.id!, lesson.lessonName); break;
                          case 'delete_lesson': _deleteLesson(lesson.id!, lesson.lessonName); break;
                        }
                      },
                    ),
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
                          subTermId: _selectedSubTermId,
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
                    termId: _currentTermId,
                    subTermId: _selectedSubTermId,
                    subTermName: _selectedSubTermName,
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
                termId: _currentTermId,
                subTermId: _selectedSubTermId,
                subTermName: _selectedSubTermName,
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
            subTermId: _selectedSubTermId,
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
  final String? subTermId;
  final String? subTermName;
  final List<String> branchNames;
  final LessonModel? lessonToEdit;
  final VoidCallback onLessonSaved;

  const _LessonFormSheet({
    required this.schoolTypeId,
    required this.institutionId,
    this.termId,
    this.subTermId,
    this.subTermName,
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
      final effectiveTermId = widget.lessonToEdit?.termId ?? widget.termId ?? activeTermId;
      final effectiveSubTermId = widget.lessonToEdit?.subTermId ?? widget.subTermId;
      final effectiveSubTermName = widget.lessonToEdit?.subTermName ?? widget.subTermName;

      final lessonData = {
        'lessonName': _lessonNameController.text.trim(),
        'shortName': _shortNameController.text.trim().toUpperCase(),
        'branchId': _selectedBranchName,
        'branchName': _selectedBranchName,
        'schoolTypeId': widget.schoolTypeId,
        'institutionId': widget.institutionId,
        'termId': effectiveTermId,
        'subTermId': effectiveSubTermId,
        'periodId': effectiveSubTermId,
        'subTermName': effectiveSubTermName,
        'periodName': effectiveSubTermName,
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
  final String? termId;
  final String? subTermId;
  final String? subTermName;
  final List<Map<String, dynamic>> teachers;

  const _ClassAssignmentSheet({
    required this.lesson,
    required this.schoolTypeId,
    required this.institutionId,
    this.termId,
    this.subTermId,
    this.subTermName,
    required this.teachers,
  });

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
  final Map<String, TextEditingController> _hourControllers = {};

  @override
  void initState() { super.initState(); _loadData(); }

  @override
  void dispose() {
    for (var c in _hourControllers.values) {
      c.dispose();
    }
    _hourControllers.clear();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // termId burada kullanılmıyor, _save() metodunda ayrıca alınıyor
      final classSnap = await FirebaseFirestore.instance.collection('classes').where('schoolTypeId', isEqualTo: widget.schoolTypeId).where('institutionId', isEqualTo: widget.institutionId).where('termId', isEqualTo: widget.termId ?? '').where('isActive', isEqualTo: true).get();
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

      if (mounted) setState(() { _classes = classes; _allTeachers = teachers; _classTypes = classes.map((c) => c['classTypeName'] as String?).whereType<String>().toSet().toList()..sort(); _availableLevels = classes.map((c) { final v = c['classLevel']; if (v is int) return v; if (v is double) return v.toInt(); return int.tryParse(v?.toString() ?? '') ?? 0; }).toSet(); _isLoading = false; });
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
        const SizedBox(height: 12),
        // Secim ozeti + Tumunu Sec
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Text(
                '${_selectedClassIds.where((id) => filtered.any((c) => c['id'] == id)).length} / ${filtered.length} secili',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  final allSelected = filtered.every((c) => _selectedClassIds.contains(c['id']));
                  setState(() {
                    if (allSelected) {
                      for (final c in filtered) _selectedClassIds.remove(c['id']);
                    } else {
                      for (final c in filtered) {
                        if (!_selectedClassIds.contains(c['id'])) _selectedClassIds.add(c['id']);
                      }
                    }
                  });
                },
                icon: Icon(
                  filtered.every((c) => _selectedClassIds.contains(c['id']))
                      ? Icons.deselect
                      : Icons.select_all,
                  size: 18,
                ),
                label: Text(
                  filtered.every((c) => _selectedClassIds.contains(c['id']))
                      ? 'Secimi Kaldir'
                      : 'Tumunu Sec',
                  style: const TextStyle(fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.indigo,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
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
    final oldHours = {for (var a in _assignments) a['classId'] as String: a['weeklyHours']};
    final oldTeacherIds = {for (var a in _assignments) a['classId'] as String: a['teacherIds']};
    final oldTeacherNames = {for (var a in _assignments) a['classId'] as String: a['teacherNames']};

    _assignments = _selectedClassIds.map((id) {
      final c = _classes.firstWhere((cl) => cl['id'] == id);
      return {
        'classId': id,
        'className': c['className'],
        'weeklyHours': oldHours[id] ?? 0,
        'teacherIds': oldTeacherIds[id] ?? <String>[],
        'teacherNames': oldTeacherNames[id] ?? <String>[]
      };
    }).toList();
    _assignments.sort((a, b) {
      final nameA = (a['className'] ?? '').toString();
      final nameB = (b['className'] ?? '').toString();
      return compareClassNamesNatural(nameA, nameB);
    });

    _hourControllers.forEach((_, c) => c.dispose());
    _hourControllers.clear();
    for (var a in _assignments) {
      final classId = a['classId'] as String;
      final hours = a['weeklyHours'] as int? ?? 0;
      _hourControllers[classId] = TextEditingController(
        text: hours == 0 ? '' : '$hours',
      );
    }

    setState(() => _step = 2);
  }

  Widget _buildStep2() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _assignments.length,
      itemBuilder: (context, i) {
        final a = _assignments[i];
        final classId = a['classId'] as String;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Sınıf adı + Tümüne Uygula menüsü
              Row(
                children: [
                  Expanded(child: Text(a['className'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                  PopupMenuButton<String>(
                    tooltip: 'Tümüne Uygula',
                    icon: const Icon(Icons.more_horiz, size: 18, color: Colors.grey),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'hours',
                          child: Row(children: [
                            Icon(Icons.access_time, size: 16, color: Colors.indigo),
                            SizedBox(width: 10),
                            Text('Saati Tümüne Uygula'),
                          ]),
                        ),
                        const PopupMenuItem(
                          value: 'teacher',
                          child: Row(children: [
                            Icon(Icons.person, size: 16, color: Colors.orange),
                            SizedBox(width: 10),
                            Text('Öğretmeni Tümüne Uygula'),
                          ]),
                        ),
                        const PopupMenuItem(
                          value: 'both',
                          child: Row(children: [
                            Icon(Icons.copy_all, size: 16, color: Colors.green),
                            SizedBox(width: 10),
                            Text('İkisini de Tümüne Uygula'),
                          ]),
                        ),
                      ],
                    onSelected: (val) {
                      setState(() {
                        final targetHours = a['weeklyHours'] as int? ?? 0;
                        final hourText = targetHours == 0 ? '' : '$targetHours';
                        for (int j = 0; j < _assignments.length; j++) {
                          if (j == i) continue;
                          final cId = _assignments[j]['classId'] as String;
                          if (val == 'hours' || val == 'both') {
                            _assignments[j]['weeklyHours'] = targetHours;
                            if (_hourControllers.containsKey(cId)) {
                              _hourControllers[cId]!.text = hourText;
                            }
                          }
                          if (val == 'teacher' || val == 'both') {
                            _assignments[j]['teacherIds'] = List<String>.from(a['teacherIds']);
                            _assignments[j]['teacherNames'] = List<String>.from(a['teacherNames']);
                          }
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(children: [
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    controller: _hourControllers[classId],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Saat', border: OutlineInputBorder()),
                    onChanged: (v) => a['weeklyHours'] = int.tryParse(v) ?? 0,
                  ),
                ),
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
      final termId = await TermService().getSelectedTermId() ?? await TermService().getActiveTermId() ?? widget.termId;
      final subTermId = widget.subTermId ?? widget.lesson.subTermId;
      final subTermName = widget.subTermName ?? widget.lesson.subTermName;

      for (var a in _assignments) {
        final ref = FirebaseFirestore.instance.collection('lessonAssignments').doc();
        batch.set(ref, {
          ...a,
          'lessonId': widget.lesson.id,
          'lessonName': widget.lesson.lessonName,
          'institutionId': widget.institutionId,
          'schoolTypeId': widget.schoolTypeId,
          'termId': termId,
          'subTermId': subTermId,
          'periodId': subTermId,
          'subTermName': subTermName,
          'periodName': subTermName,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
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
  final String? subTermId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAssign;

  const _LessonDetailPage({
    required this.lesson,
    required this.teachers,
    this.subTermId,
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
            SafeStreamBuilder<QuerySnapshot>(
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

                final docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['isActive'] == false) return false;
                  final stId = data['subTermId'] ?? data['periodId'];
                  if (widget.subTermId != null && stId != null && stId.toString().isNotEmpty) {
                    return stId == widget.subTermId;
                  }
                  return true;
                }).toList();

                if (docs.isEmpty) {
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
                  children: docs.map((doc) {
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
  
  bool _isTeacherMatch(Map<String, dynamic> t) {
    if (widget.lessonBranch.isEmpty) return false;
    final tBranch = (t['branch'] ?? t['branchName'] ?? t['mainBranch'] ?? '').toString().trim().toLowerCase();
    final tRole = (t['role'] ?? '').toString().trim().toLowerCase();
    final target = widget.lessonBranch.trim().toLowerCase();

    final List<String> tBranches = [];
    if (t['branches'] is List) {
      tBranches.addAll((t['branches'] as List).map((e) => e.toString().trim().toLowerCase()));
    }

    if (tBranch == target || tBranch.contains(target) || target.contains(tBranch)) return true;
    if (tRole == target || tRole.contains(target) || target.contains(tRole)) return true;
    if (tBranches.any((b) => b == target || b.contains(target) || target.contains(b))) return true;

    return false;
  }

  @override
  void initState() { 
    super.initState(); 
    _selIds = List.from(widget.initialIds); 
    
    // Öğretmenleri sırala: İlgili branşta olanlar en üste, geri kalanı alfabetik
    _sortedTeachers = List.from(widget.teachers);
    _sortedTeachers.sort((a, b) {
      final isMatchA = _isTeacherMatch(a);
      final isMatchB = _isTeacherMatch(b);
      
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
      final branch = (t['branch'] ?? t['branchName'] ?? '').toString().toLowerCase();
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
        if (widget.lessonBranch.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Color(0xFF059669), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ders Branşı: "${widget.lessonBranch}" • Branş öğretmenleri en üstte listeleniyor',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF065F46)),
                    ),
                  ),
                ],
              ),
            ),
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
                    final isMatch = _isTeacherMatch(t);
                    final branch = (t['branch'] ?? t['branchName'] ?? '').toString();
                    return CheckboxListTile(
                      value: sel,
                      title: Row(
                        children: [
                          Expanded(child: Text(t['fullName'] ?? '', style: TextStyle(fontWeight: (sel || isMatch) ? FontWeight.bold : FontWeight.normal))),
                          if (isMatch)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF6EE7B7)),
                              ),
                              child: const Text(
                                'Branş Öğretmeni',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                              ),
                            ),
                        ],
                      ),
                      subtitle: branch.isNotEmpty
                          ? Text(
                              branch,
                              style: TextStyle(
                                color: isMatch ? const Color(0xFF059669) : Colors.grey.shade600,
                                fontWeight: isMatch ? FontWeight.w600 : FontWeight.normal,
                              ),
                            )
                          : null,
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
  final String? subTermId;
  final void Function(String docId, Map<String, dynamic> data) onEditAssignment;
  final void Function(String docId, String className) onDeleteAssignment;

  const _LessonAssignmentsPanel({
    required this.lessonId,
    required this.lessonBranchName,
    required this.institutionId,
    this.subTermId,
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
    if (oldWidget.lessonId != widget.lessonId || oldWidget.subTermId != widget.subTermId) {
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
    return SafeStreamBuilder<QuerySnapshot>(
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
          if (data['isActive'] == false) return false;
          final stId = data['subTermId'] ?? data['periodId'];
          if (widget.subTermId != null && stId != null && stId.toString().isNotEmpty) {
            return stId == widget.subTermId;
          }
          return true;
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
