import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/term_service.dart';

class ClassPromotionScreen extends StatefulWidget {
  final String schoolTypeId;
  final String schoolTypeName;
  final String institutionId;

  const ClassPromotionScreen({
    Key? key,
    required this.schoolTypeId,
    required this.schoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  _ClassPromotionScreenState createState() => _ClassPromotionScreenState();
}

class _ClassPromotionScreenState extends State<ClassPromotionScreen> {
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _currentTermId;
  String? _targetTermId;
  String? _selectedClassFilterId;
  String? _selectedLevelFilter;
  bool _promoteWithClasses = true;

  List<Map<String, dynamic>> _terms = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  final Set<String> _selectedStudentIds = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 1. Get current active/selected term
      final selectedTermId = await TermService().getSelectedTermId();
      final activeTermId = await TermService().getActiveTermId();
      _currentTermId = selectedTermId ?? activeTermId;

      // 2. Fetch all terms for dropdown (exclude current term)
      final termsSnapshot = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final termsList = termsSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      termsList.sort((a, b) {
        final aYear = a['startYear'] ?? 0;
        final bYear = b['startYear'] ?? 0;
        return bYear.compareTo(aYear);
      });

      // 3. Fetch classes for this school type in current term
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('termId', isEqualTo: _currentTermId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();

      final classesList = classesSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      classesList.sort((a, b) => (a['className'] ?? '').toString().compareTo((b['className'] ?? '').toString()));

      // 4. Fetch students of this school type in current term
      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('termId', isEqualTo: _currentTermId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();

      final studentsList = studentsSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      studentsList.sort((a, b) => (a['fullName'] ?? '').toString().compareTo((b['fullName'] ?? '').toString()));

      final targetTerms = termsList.where((t) => t['id'] != _currentTermId).toList();

      setState(() {
        _terms = targetTerms;
        if (targetTerms.isNotEmpty) {
          _targetTermId = targetTerms.first['id'];
        }
        _classes = classesList;
        _students = studentsList;
        _filteredStudents = studentsList;
        // Select all by default
        _selectedStudentIds.addAll(studentsList.map((s) => s['id'] as String));
        _isLoading = false;
      });
    } catch (e) {
      print('Sınıf atlatma verileri yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  List<String> get _availableClassLevels {
    final levels = _students
        .map((s) => s['classLevel']?.toString())
        .where((l) => l != null && l.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    levels.sort((a, b) {
      final aInt = int.tryParse(a);
      final bInt = int.tryParse(b);
      if (aInt != null && bInt != null) return aInt.compareTo(bInt);
      return a.compareTo(b);
    });
    return levels;
  }

  void _filterStudents() {
    setState(() {
      _filteredStudents = _students.where((s) {
        final matchesClass = _selectedClassFilterId == null || s['classId'] == _selectedClassFilterId;
        final matchesLevel = _selectedLevelFilter == null || s['classLevel']?.toString() == _selectedLevelFilter;
        return matchesClass && matchesLevel;
      }).toList();
    });
  }

  InputDecoration _getInputDecoration(String label, IconData icon, Color themeColor, {String? helperText}) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: 2,
      labelStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13, fontWeight: FontWeight.bold),
      prefixIcon: Icon(icon, color: themeColor, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: themeColor, width: 1.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  String getNextLevel(String currentLevel, String schoolTypeName) {
    final type = schoolTypeName.toLowerCase();
    if (type.contains('anaokul') || type.contains('kreş')) {
      if (currentLevel == 'Kreş') return 'Anaokulu';
      return 'Mezun';
    } else if (type.contains('ilkokul')) {
      if (currentLevel == '1') return '2';
      if (currentLevel == '2') return '3';
      if (currentLevel == '3') return '4';
      return 'Mezun';
    } else if (type.contains('ortaokul')) {
      if (currentLevel == '5') return '6';
      if (currentLevel == '6') return '7';
      if (currentLevel == '7') return '8';
      return 'Mezun';
    } else if (type.contains('lise')) {
      if (currentLevel == '9') return '10';
      if (currentLevel == '10') return '11';
      if (currentLevel == '11') return '12';
      return 'Mezun';
    }
    
    final numericLevel = int.tryParse(currentLevel);
    if (numericLevel != null) {
      return (numericLevel + 1).toString();
    }
    return 'Mezun';
  }

  String getNextClassName(String currentName, String currentLevel, String nextLevel) {
    if (currentName.startsWith(currentLevel)) {
      return nextLevel + currentName.substring(currentLevel.length);
    }
    return nextLevel + currentName;
  }

  Future<void> _promoteAndCopy() async {
    if (_targetTermId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir hedef dönem seçin.'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir öğrenci seçin.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      int classesCount = 0;
      int studentsCount = 0;

      // 1. Get chosen students
      final selectedStudents = _students.where((s) => _selectedStudentIds.contains(s['id'])).toList();

      // 2. Load target term classes to map class IDs
      final targetClassesQuery = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('termId', isEqualTo: _targetTermId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();

      final targetClassesMap = <String, String>{};
      for (var doc in targetClassesQuery.docs) {
        final data = doc.data();
        final cName = data['className']?.toString() ?? '';
        if (cName.isNotEmpty) {
          targetClassesMap[cName] = doc.id;
        }
      }

      final classMapping = <String, String>{};
      final graduatedClassId = 'mezun';

      // 3. Promote classes if checked
      if (_promoteWithClasses) {
        for (var classObj in _classes) {
          final currentClassName = classObj['className']?.toString() ?? '';
          final currentClassLevel = classObj['classLevel']?.toString() ?? '';
          
          final nextLevel = getNextLevel(currentClassLevel, widget.schoolTypeName);
          if (nextLevel == 'Mezun') {
            classMapping[classObj['id']] = graduatedClassId;
            continue;
          }

          final nextClassName = getNextClassName(currentClassName, currentClassLevel, nextLevel);

          String targetClassId;
          if (targetClassesMap.containsKey(nextClassName)) {
            targetClassId = targetClassesMap[nextClassName]!;
          } else {
            // Create upgraded class
            final newClassData = Map<String, dynamic>.from(classObj);
            newClassData.remove('id');
            newClassData['termId'] = _targetTermId;
            newClassData['className'] = nextClassName;
            newClassData['classLevel'] = nextLevel;
            newClassData['createdAt'] = FieldValue.serverTimestamp();
            newClassData['updatedAt'] = FieldValue.serverTimestamp();
            newClassData['copiedFrom'] = _currentTermId;

            final newClassRef = await FirebaseFirestore.instance
                .collection('classes')
                .add(newClassData);
            targetClassId = newClassRef.id;
            targetClassesMap[nextClassName] = targetClassId;
            classesCount++;
          }

          classMapping[classObj['id']] = targetClassId;
        }
      }

      // 4. Duplicate and upgrade students
      for (var student in selectedStudents) {
        final studentData = Map<String, dynamic>.from(student);
        studentData.remove('id');
        studentData['termId'] = _targetTermId;
        studentData['createdAt'] = FieldValue.serverTimestamp();
        studentData['updatedAt'] = FieldValue.serverTimestamp();
        studentData['copiedFrom'] = _currentTermId;

        final currentLevel = studentData['classLevel']?.toString() ?? '';
        final nextLevel = getNextLevel(currentLevel, widget.schoolTypeName);

        studentData['classLevel'] = nextLevel;

        final currentClassId = studentData['classId']?.toString() ?? '';
        if (nextLevel == 'Mezun') {
          studentData['classId'] = null;
          studentData['className'] = 'Mezun';
          studentData['isActive'] = false;
        } else if (_promoteWithClasses && classMapping.containsKey(currentClassId)) {
          final targetClassId = classMapping[currentClassId]!;
          studentData['classId'] = targetClassId;
          
          final className = targetClassesMap.entries
              .firstWhere((entry) => entry.value == targetClassId, orElse: () => const MapEntry('', ''))
              .key;
          studentData['className'] = className.isNotEmpty ? className : null;
        } else {
          studentData['classId'] = null;
          studentData['className'] = null;
        }

        await FirebaseFirestore.instance.collection('students').add(studentData);
        studentsCount++;
      }

      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ $classesCount sınıf oluşturuldu, $studentsCount öğrenci sınıf atlatılarak kopyalandı!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('Sınıf atlatılırken hata: $e');
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Colors.indigo.shade800;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.schoolTypeName} - Sınıf Atlatma',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: themeColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    // Configuration header
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.indigo.shade50),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.indigo.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Section title: HEDEF SEÇİMİ
                          Row(
                            children: [
                              Icon(Icons.near_me_rounded, color: themeColor, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Hedef Bilgiler (Kopyalanacak Yeni Yer)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Dropdown for target term
                          DropdownButtonFormField<String>(
                            decoration: _getInputDecoration(
                              'Hedef Dönem (Aktarılacak Yeni Dönem) *',
                              Icons.calendar_today_rounded,
                              themeColor,
                              helperText: 'Öğrencilerin kopyalanacağı gelecek okul dönemi.',
                            ),
                            value: _targetTermId,
                            items: _terms.map((t) {
                              return DropdownMenuItem(
                                value: t['id'] as String,
                                child: Text(t['name'] ?? ''),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() => _targetTermId = val);
                            },
                          ),
                          const SizedBox(height: 12),
                          // Checkbox row
                          InkWell(
                            onTap: () {
                              setState(() => _promoteWithClasses = !_promoteWithClasses);
                            },
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _promoteWithClasses,
                                  activeColor: themeColor,
                                  onChanged: (val) {
                                    setState(() => _promoteWithClasses = val ?? true);
                                  },
                                ),
                                const Expanded(
                                  child: Text(
                                    'Sınıfları otomatik yükselterek kopyala (İşaretlenmezse öğrenciler yeni döneme şubesiz/sınıfsız kopyalanır)',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 24, thickness: 1),
                          // Section title: FİLTRELEME
                          Row(
                            children: [
                              Icon(Icons.filter_alt_rounded, color: themeColor, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Filtreleme (Mevcut Dönem)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  decoration: _getInputDecoration(
                                    'Sınıf Seviyesi',
                                    Icons.grade_rounded,
                                    themeColor,
                                  ),
                                  value: _selectedLevelFilter,
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('Tüm Seviyeler')),
                                    ..._availableClassLevels.map((lvl) {
                                      return DropdownMenuItem(
                                        value: lvl,
                                        child: Text('$lvl. Seviye'),
                                      );
                                    }).toList(),
                                  ],
                                  onChanged: (val) {
                                    _selectedLevelFilter = val;
                                    _filterStudents();
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  decoration: _getInputDecoration(
                                    'Şube / Sınıf',
                                    Icons.filter_alt_outlined,
                                    themeColor,
                                  ),
                                  value: _selectedClassFilterId,
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('Tüm Şubeler')),
                                    ..._classes.map((c) {
                                      return DropdownMenuItem(
                                        value: c['id'] as String,
                                        child: Text(c['className'] ?? ''),
                                      );
                                    }).toList(),
                                  ],
                                  onChanged: (val) {
                                    _selectedClassFilterId = val;
                                    _filterStudents();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Checkbox all header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Colors.indigo.shade50,
                      child: Row(
                        children: [
                          Checkbox(
                            value: _selectedStudentIds.length == _filteredStudents.length && _filteredStudents.isNotEmpty,
                            activeColor: themeColor,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedStudentIds.addAll(_filteredStudents.map((s) => s['id'] as String));
                                } else {
                                  _selectedStudentIds.removeAll(_filteredStudents.map((s) => s['id'] as String));
                                }
                              });
                            },
                          ),
                          Text(
                            'Tümünü Seç (${_filteredStudents.length} öğrenci listede, ${_selectedStudentIds.length} seçili)',
                            style: TextStyle(fontWeight: FontWeight.bold, color: themeColor),
                          ),
                        ],
                      ),
                    ),
                    // Student List
                    Expanded(
                      child: _filteredStudents.isEmpty
                          ? const Center(child: Text('Bu kriterlere uyan öğrenci bulunamadı.'))
                          : ListView.builder(
                              itemCount: _filteredStudents.length,
                              itemBuilder: (context, index) {
                                final student = _filteredStudents[index];
                                final id = student['id'] as String;
                                final isChecked = _selectedStudentIds.contains(id);

                                return CheckboxListTile(
                                  value: isChecked,
                                  activeColor: themeColor,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedStudentIds.add(id);
                                      } else {
                                        _selectedStudentIds.remove(id);
                                      }
                                    });
                                  },
                                  title: Text(
                                    student['fullName'] ?? 'İsimsiz',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    'No: ${student['studentNo'] ?? '-'} | Sınıf: ${student['className'] ?? 'Sınıfsız'} (${student['classLevel'] ?? '-'}. Sınıf)',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                  secondary: CircleAvatar(
                                    backgroundColor: Colors.indigo.shade100,
                                    child: const Icon(Icons.person, color: Colors.indigo),
                                  ),
                                );
                              },
                            ),
                    ),
                    // Action footer
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _promoteAndCopy,
                        icon: const Icon(Icons.upgrade),
                        label: Text('SEÇİLİ ÖĞRENCİLERİ SINIF ATLAT & KOPYALA (${_selectedStudentIds.length})'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(width: 16),
                              Text('İşlem gerçekleştiriliyor, lütfen bekleyin...'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}


class StudentTransferScreen extends StatefulWidget {
  final String sourceSchoolTypeId;
  final String sourceSchoolTypeName;
  final String institutionId;

  const StudentTransferScreen({
    Key? key,
    required this.sourceSchoolTypeId,
    required this.sourceSchoolTypeName,
    required this.institutionId,
  }) : super(key: key);

  @override
  _StudentTransferScreenState createState() => _StudentTransferScreenState();
}

class _StudentTransferScreenState extends State<StudentTransferScreen> {
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _currentTermId;
  
  String? _targetSchoolTypeId;
  String? _targetTermId;
  String? _targetClassLevel;
  String? _selectedClassFilterId;
  String? _selectedLevelFilter;

  List<Map<String, dynamic>> _schoolTypes = [];
  List<Map<String, dynamic>> _terms = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  final Set<String> _selectedStudentIds = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 1. Get current active/selected term
      final selectedTermId = await TermService().getSelectedTermId();
      final activeTermId = await TermService().getActiveTermId();
      _currentTermId = selectedTermId ?? activeTermId;

      // 2. Fetch all school types (exclude source school type)
      final schoolTypesSnapshot = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final schoolTypesList = schoolTypesSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      final targetSchoolTypes = schoolTypesList.where((st) => st['id'] != widget.sourceSchoolTypeId).toList();

      // 3. Fetch all terms for dropdown
      final termsSnapshot = await FirebaseFirestore.instance
          .collection('terms')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final termsList = termsSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      termsList.sort((a, b) {
        final aYear = a['startYear'] ?? 0;
        final bYear = b['startYear'] ?? 0;
        return bYear.compareTo(aYear);
      });

      // 4. Fetch classes for this school type in current term (for filtering)
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('termId', isEqualTo: _currentTermId)
          .where('schoolTypeId', isEqualTo: widget.sourceSchoolTypeId)
          .get();

      final classesList = classesSnapshot.docs.map((doc) {
        final actualData = doc.data();
        actualData['id'] = doc.id;
        return actualData;
      }).toList();

      classesList.sort((a, b) => (a['className'] ?? '').toString().compareTo((b['className'] ?? '').toString()));

      // 5. Fetch students of this school type in current term
      final studentsSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('termId', isEqualTo: _currentTermId)
          .where('schoolTypeId', isEqualTo: widget.sourceSchoolTypeId)
          .get();

      final studentsList = studentsSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      studentsList.sort((a, b) => (a['fullName'] ?? '').toString().compareTo((b['fullName'] ?? '').toString()));

      setState(() {
        _schoolTypes = targetSchoolTypes;
        if (targetSchoolTypes.isNotEmpty) {
          _targetSchoolTypeId = targetSchoolTypes.first['id'];
        }
        _terms = termsList;
        if (termsList.isNotEmpty) {
          _targetTermId = _currentTermId;
        }
        _classes = classesList;
        _students = studentsList;
        _filteredStudents = studentsList;
        _isLoading = false;
        _updateTargetClassLevels();
      });
    } catch (e) {
      print('Nakil verileri yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  void _updateTargetClassLevels() {
    if (_targetSchoolTypeId == null) return;
    
    final selectedSchoolType = _schoolTypes.firstWhere(
      (st) => st['id'] == _targetSchoolTypeId,
      orElse: () => {},
    );

    final typeName = (selectedSchoolType['schoolTypeName'] ?? selectedSchoolType['typeName'] ?? '').toString().toLowerCase();

    List<String> levels = [];
    if (typeName.contains('anaokul') || typeName.contains('kreş')) {
      levels = ['Kreş', 'Anaokulu'];
    } else if (typeName.contains('ilkokul')) {
      levels = ['1', '2', '3', '4'];
    } else if (typeName.contains('ortaokul')) {
      levels = ['5', '6', '7', '8'];
    } else if (typeName.contains('lise')) {
      levels = ['9', '10', '11', '12'];
    } else {
      levels = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'];
    }

    setState(() {
      _targetClassLevel = levels.isNotEmpty ? levels.first : null;
    });
  }

  List<String> _getCurrentTargetClassLevels() {
    if (_targetSchoolTypeId == null) return [];
    
    final selectedSchoolType = _schoolTypes.firstWhere(
      (st) => st['id'] == _targetSchoolTypeId,
      orElse: () => {},
    );

    final typeName = (selectedSchoolType['schoolTypeName'] ?? selectedSchoolType['typeName'] ?? '').toString().toLowerCase();

    if (typeName.contains('anaokul') || typeName.contains('kreş')) {
      return ['Kreş', 'Anaokulu'];
    } else if (typeName.contains('ilkokul')) {
      return ['1', '2', '3', '4'];
    } else if (typeName.contains('ortaokul')) {
      return ['5', '6', '7', '8'];
    } else if (typeName.contains('lise')) {
      return ['9', '10', '11', '12'];
    }
    return ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'];
  }

  List<String> get _availableClassLevels {
    final levels = _students
        .map((s) => s['classLevel']?.toString())
        .where((l) => l != null && l.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    levels.sort((a, b) {
      final aInt = int.tryParse(a);
      final bInt = int.tryParse(b);
      if (aInt != null && bInt != null) return aInt.compareTo(bInt);
      return a.compareTo(b);
    });
    return levels;
  }

  void _filterStudents() {
    setState(() {
      _filteredStudents = _students.where((s) {
        final matchesClass = _selectedClassFilterId == null || s['classId'] == _selectedClassFilterId;
        final matchesLevel = _selectedLevelFilter == null || s['classLevel']?.toString() == _selectedLevelFilter;
        return matchesClass && matchesLevel;
      }).toList();
    });
  }

  InputDecoration _getInputDecoration(String label, IconData icon, Color themeColor, {String? helperText}) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      helperMaxLines: 2,
      labelStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13, fontWeight: FontWeight.bold),
      prefixIcon: Icon(icon, color: themeColor, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: themeColor, width: 1.5),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Future<void> _transferStudents() async {
    if (_targetSchoolTypeId == null || _targetTermId == null || _targetClassLevel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen hedef okul türü, dönem ve sınıf seviyesini seçin.'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_selectedStudentIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen nakil edilecek en az bir öğrenci seçin.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      int transferCount = 0;

      final targetSchoolTypeDoc = _schoolTypes.firstWhere((st) => st['id'] == _targetSchoolTypeId);
      final targetSchoolTypeName = (targetSchoolTypeDoc['schoolTypeName'] ?? targetSchoolTypeDoc['typeName'] ?? '').toString();

      final selectedStudents = _students.where((s) => _selectedStudentIds.contains(s['id'])).toList();

      for (var student in selectedStudents) {
        final studentData = Map<String, dynamic>.from(student);
        studentData.remove('id');
        studentData['termId'] = _targetTermId;
        studentData['schoolTypeId'] = _targetSchoolTypeId;
        studentData['schoolTypeName'] = targetSchoolTypeName;
        studentData['classLevel'] = _targetClassLevel;
        studentData['classId'] = null;
        studentData['className'] = null;
        studentData['createdAt'] = FieldValue.serverTimestamp();
        studentData['updatedAt'] = FieldValue.serverTimestamp();
        studentData['copiedFrom'] = _currentTermId;
        studentData['isActive'] = true;

        await FirebaseFirestore.instance.collection('students').add(studentData);
        transferCount++;
      }

      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ $transferCount öğrenci başarıyla ${targetSchoolTypeName}\'ne nakledildi!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('Nakil edilirken hata: $e');
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Colors.teal.shade800;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.sourceSchoolTypeName} - Nakil İşlemleri',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: themeColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    // Configuration header
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.teal.shade50),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.teal.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Section title: HEDEF SEÇİMİ
                          Row(
                            children: [
                              Icon(Icons.near_me_rounded, color: themeColor, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Hedef Bilgiler (Aktarılacak Yeni Yer)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Dropdown for target school type
                          DropdownButtonFormField<String>(
                            decoration: _getInputDecoration(
                              'Hedef Okul Türü (Yeni Seviye) *',
                              Icons.school_outlined,
                              themeColor,
                              helperText: 'Öğrencilerin nakledileceği okul türü (örn: İlkokuldan Ortaokula).',
                            ),
                            value: _targetSchoolTypeId,
                            items: _schoolTypes.map((st) {
                              final name = st['schoolTypeName'] ?? st['typeName'] ?? '';
                              return DropdownMenuItem(
                                value: st['id'] as String,
                                child: Text(name),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _targetSchoolTypeId = val;
                                _updateTargetClassLevels();
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  decoration: _getInputDecoration(
                                    'Hedef Dönem (Yeni Dönem) *',
                                    Icons.calendar_today_rounded,
                                    themeColor,
                                    helperText: 'Öğrencilerin kopyalanacağı gelecek okul dönemi.',
                                  ),
                                  value: _targetTermId,
                                  items: _terms.map((t) {
                                    return DropdownMenuItem(
                                      value: t['id'] as String,
                                      child: Text(t['name'] ?? ''),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    setState(() => _targetTermId = val);
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  decoration: _getInputDecoration(
                                    'Hedef Sınıf Seviyesi (Yeni Derece) *',
                                    Icons.grade_outlined,
                                    themeColor,
                                    helperText: 'Yeni okul türünde başlayacağı sınıf seviyesi (örn: Lise için 9. Sınıf).',
                                  ),
                                  value: _targetClassLevel,
                                  items: _getCurrentTargetClassLevels().map((lvl) {
                                    return DropdownMenuItem(
                                      value: lvl,
                                      child: Text('$lvl. Sınıf'),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    setState(() => _targetClassLevel = val);
                                  },
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24, thickness: 1),
                          // Section title: FİLTRELEME
                          Row(
                            children: [
                              Icon(Icons.filter_alt_rounded, color: themeColor, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'Filtreleme (Mevcut Dönem)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  decoration: _getInputDecoration(
                                    'Sınıf Seviyesi',
                                    Icons.grade_rounded,
                                    themeColor,
                                  ),
                                  value: _selectedLevelFilter,
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('Tüm Seviyeler')),
                                    ..._availableClassLevels.map((lvl) {
                                      return DropdownMenuItem(
                                        value: lvl,
                                        child: Text('$lvl. Seviye'),
                                      );
                                    }).toList(),
                                  ],
                                  onChanged: (val) {
                                    _selectedLevelFilter = val;
                                    _filterStudents();
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String?>(
                                  decoration: _getInputDecoration(
                                    'Şube / Sınıf',
                                    Icons.filter_alt_outlined,
                                    themeColor,
                                  ),
                                  value: _selectedClassFilterId,
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('Tüm Şubeler')),
                                    ..._classes.map((c) {
                                      return DropdownMenuItem(
                                        value: c['id'] as String,
                                        child: Text(c['className'] ?? ''),
                                      );
                                    }).toList(),
                                  ],
                                  onChanged: (val) {
                                    _selectedClassFilterId = val;
                                    _filterStudents();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Checkbox all header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Colors.teal.shade50,
                      child: Row(
                        children: [
                          Checkbox(
                            value: _selectedStudentIds.length == _filteredStudents.length && _filteredStudents.isNotEmpty,
                            activeColor: themeColor,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedStudentIds.addAll(_filteredStudents.map((s) => s['id'] as String));
                                } else {
                                  _selectedStudentIds.removeAll(_filteredStudents.map((s) => s['id'] as String));
                                }
                              });
                            },
                          ),
                          Text(
                            'Tümünü Seç (${_filteredStudents.length} öğrenci listede, ${_selectedStudentIds.length} seçili)',
                            style: TextStyle(fontWeight: FontWeight.bold, color: themeColor),
                          ),
                        ],
                      ),
                    ),
                    // Student List
                    Expanded(
                      child: _filteredStudents.isEmpty
                          ? const Center(child: Text('Bu kriterlere uyan öğrenci bulunamadı.'))
                          : ListView.builder(
                              itemCount: _filteredStudents.length,
                              itemBuilder: (context, index) {
                                final student = _filteredStudents[index];
                                final id = student['id'] as String;
                                final isChecked = _selectedStudentIds.contains(id);

                                return CheckboxListTile(
                                  value: isChecked,
                                  activeColor: themeColor,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedStudentIds.add(id);
                                      } else {
                                        _selectedStudentIds.remove(id);
                                      }
                                    });
                                  },
                                  title: Text(
                                    student['fullName'] ?? 'İsimsiz',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    'No: ${student['studentNo'] ?? '-'} | Sınıf: ${student['className'] ?? 'Sınıfsız'} (${student['classLevel'] ?? '-'}. Sınıf)',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                  secondary: CircleAvatar(
                                    backgroundColor: Colors.teal.shade100,
                                    child: const Icon(Icons.transfer_within_a_station, color: Colors.teal),
                                  ),
                                );
                              },
                            ),
                    ),
                    // Action footer
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _transferStudents,
                        icon: const Icon(Icons.send_rounded),
                        label: Text('SEÇİLİ ÖĞRENCİLERİ NAKLET (${_selectedStudentIds.length})'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(width: 16),
                              Text('Nakil işlemi yapılıyor, lütfen bekleyin...'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
