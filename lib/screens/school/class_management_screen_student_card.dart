import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/term_service.dart';

// Öğrenci Listesi Kartı
class StudentListCard extends StatefulWidget {
  final String classId;
  final String className;
  final String classTypeId;
  final String classTypeName;
  final String schoolTypeId;
  final String institutionId;

  const StudentListCard({
    Key? key,
    required this.classId,
    required this.className,
    required this.classTypeId,
    required this.classTypeName,
    required this.schoolTypeId,
    required this.institutionId,
  }) : super(key: key);

  @override
  State<StudentListCard> createState() => _StudentListCardState();
}

class _StudentListCardState extends State<StudentListCard> {
  int _studentCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStudentCount();
  }

  Future<void> _loadStudentCount() async {
    try {
      print('📊 Öğrenci sayısı yükleniyor...');
      print('   classId: ${widget.classId}');
      print('   className: ${widget.className}');
      
      // Sadece classId ile sorgula (isActive filtresini kaldırdık)
      final snapshotById = await FirebaseFirestore.instance
          .collection('students')
          .where('classId', isEqualTo: widget.classId)
          .get();

      print('   classId ile bulunan: ${snapshotById.docs.length}');

      final snapshotByName = await FirebaseFirestore.instance
          .collection('students')
          .where('className', isEqualTo: widget.className)
          .get();
      
      print('   className ile bulunan: ${snapshotByName.docs.length}');

      // İki sonucu birleştir ve tekrarları kaldır
      final allIds = <String>{};
      
      for (var doc in snapshotById.docs) {
        allIds.add(doc.id);
      }
      
      for (var doc in snapshotByName.docs) {
        allIds.add(doc.id);
      }

      final count = allIds.length;
      print('✅ Toplam öğrenci sayısı: $count (tekrarsız)');

      if (mounted) {
        setState(() {
          _studentCount = count;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Öğrenci sayısı yükleme hatası: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          final isMobile = MediaQuery.of(context).size.width < 600;
          
          if (isMobile) {
            // Mobil: Yeni sayfa olarak aç
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StudentListDialog(
                  classId: widget.classId,
                  className: widget.className,
                  classTypeId: widget.classTypeId,
                  classTypeName: widget.classTypeName,
                  schoolTypeId: widget.schoolTypeId,
                  institutionId: widget.institutionId,
                  onStudentsChanged: _loadStudentCount,
                ),
              ),
            );
          } else {
            // Desktop: Dialog olarak aç
            showDialog(
              context: context,
              builder: (context) => StudentListDialog(
                classId: widget.classId,
                className: widget.className,
                classTypeId: widget.classTypeId,
                classTypeName: widget.classTypeName,
                schoolTypeId: widget.schoolTypeId,
                institutionId: widget.institutionId,
                onStudentsChanged: _loadStudentCount,
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.people, color: Colors.indigo, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Öğrenci Listesi',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  if (_isLoading)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$_studentCount Öğrenci',
                        style: TextStyle(
                          color: Colors.indigo,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'Öğrenci listesini görüntülemek için tıklayın',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Öğrenci Listesi Dialog'u
class StudentListDialog extends StatefulWidget {
  final String classId;
  final String className;
  final String classTypeId;
  final String classTypeName;
  final String schoolTypeId;
  final String institutionId;
  final VoidCallback onStudentsChanged;

  const StudentListDialog({
    Key? key,
    required this.classId,
    required this.className,
    required this.classTypeId,
    required this.classTypeName,
    required this.schoolTypeId,
    required this.institutionId,
    required this.onStudentsChanged,
  }) : super(key: key);

  @override
  State<StudentListDialog> createState() => _StudentListDialogState();
}

class _StudentListDialogState extends State<StudentListDialog> {
  List<Map<String, dynamic>> _students = [];
  bool _isLoading = true;

  String _getInitial(dynamic value) {
    if (value == null) return '?';
    final str = value.toString();
    if (str.isEmpty) return '?';
    return str.substring(0, 1).toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      print('🔍 Öğrenciler yükleniyor...');
      print('   classId: ${widget.classId}');
      print('   className: ${widget.className}');
      
      // Seçili veya aktif dönemi al
      final selectedTermId = await TermService().getSelectedTermId();
      final activeTermId = await TermService().getActiveTermId();
      final effectiveTermId = selectedTermId ?? activeTermId;
      print('   effectiveTermId: $effectiveTermId');
      
      // Hem classId hem className ile sorgula
      final snapshotById = await FirebaseFirestore.instance
          .collection('students')
          .where('classId', isEqualTo: widget.classId)
          .get();

      print('   classId ile bulunan: ${snapshotById.docs.length}');

      final snapshotByName = await FirebaseFirestore.instance
          .collection('students')
          .where('className', isEqualTo: widget.className)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();
      
      print('   className + schoolTypeId ile bulunan: ${snapshotByName.docs.length}');

      // İki sonucu birleştir ve tekrarları kaldır
      final allDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      
      for (var doc in snapshotById.docs) {
        allDocs[doc.id] = doc;
      }
      
      for (var doc in snapshotByName.docs) {
        allDocs[doc.id] = doc;
      }

      if (mounted) {
        // Dönem filtresi uygula
        final students = allDocs.values.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).where((student) {
          // Dönem filtresi: seçili dönemle eşleşen veya termId null olan (legacy)
          final studentTermId = student['termId'] as String?;
          return effectiveTermId == null || 
                 studentTermId == effectiveTermId ||
                 studentTermId == null;
        }).toList();
        
        // Manuel sıralama
        students.sort((a, b) => (a['fullName']?.toString() ?? '').compareTo(b['fullName']?.toString() ?? ''));
        
        print('✅ Toplam ${students.length} öğrenci yüklendi (dönem filtreli)');
        
        setState(() {
          _students = students;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Öğrenci yükleme hatası: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _removeStudent(String studentId, String studentName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Öğrenciyi Çıkar'),
        content: Text('$studentName öğrencisini bu sınıftan çıkarmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Çıkar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        print('🗑️ Öğrenci sınıftan çıkarılıyor: $studentId');
        
        await FirebaseFirestore.instance
            .collection('students')
            .doc(studentId)
            .update({
          'classId': null,
          'className': null,
          'classLevel': null,
          'updatedAt': DateTime.now().toIso8601String(),
        });

        print('✅ Öğrenci başarıyla çıkarıldı');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Öğrenci sınıftan çıkarıldı')),
        );

        // Kısa bir gecikme ile listeyi yenile
        await Future.delayed(Duration(milliseconds: 300));
        _loadStudents();
        widget.onStudentsChanged();
      } catch (e) {
        print('❌ Sınıftan çıkarma hatası: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Hata: $e')),
        );
      }
    }
  }

  void _showAddStudentDialog() async {
    try {
      final allStudentsSnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();

      final List<Map<String, dynamic>> availableStudents = [];
      
      for (var doc in allStudentsSnapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        
        // Bu sınıfta zaten olanları atla
        if (data['classId'] == widget.classId) continue;
        
        // Sınıf bilgisi ekle
        if (data['className'] != null && data['className'].toString().isNotEmpty) {
          data['currentClassInfo'] = '(${data['className']})';
        }
        
        availableStudents.add(data);
      }

      availableStudents.sort((a, b) => 
        (a['fullName']?.toString() ?? '').compareTo(b['fullName']?.toString() ?? ''));

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AddStudentToClassDialog(
          classId: widget.classId,
          className: widget.className,
          availableStudents: availableStudents,
          onStudentAdded: () async {
            await Future.delayed(Duration(milliseconds: 300));
            _loadStudents();
            widget.onStudentsChanged();
          },
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Hata: $e')),
      );
    }
  }

  void _copyStudentsToClass() {
    // Öğrencileri kopyalama dialog'unu aç
    showDialog(
      context: context,
      builder: (context) => CopyStudentsDialog(
        sourceClassId: widget.classId,
        sourceClassName: widget.className,
        students: _students,
      ),
    );
  }

  Widget _buildStudentList() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }
    
    if (_students.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Bu sınıfta henüz öğrenci yok',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _students.length,
      itemBuilder: (context, index) {
        final student = _students[index];
        return Card(
          margin: EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.indigo.shade100,
              child: Text(
                _getInitial(student['fullName']),
                style: TextStyle(color: Colors.indigo),
              ),
            ),
            title: Text(student['fullName']?.toString() ?? ''),
            subtitle: Text('No: ${student['studentNo'] ?? '-'}'),
            trailing: IconButton(
              onPressed: () => _removeStudent(
                student['id']?.toString() ?? '',
                student['fullName']?.toString() ?? '',
              ),
              icon: Icon(Icons.remove_circle, color: Colors.red),
              tooltip: 'Sınıftan Çıkar',
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    // Mobil: Scaffold ile tam sayfa
    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.className),
              Text(
                '${_students.length} Öğrenci',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () {
                _showAddStudentDialog();
              },
              icon: Icon(Icons.person_add),
              tooltip: 'Yeni Öğrenci Ekle',
            ),
            if (_students.isNotEmpty)
              IconButton(
                onPressed: _copyStudentsToClass,
                icon: Icon(Icons.copy_all),
                tooltip: 'Öğrencileri Kopyala',
              ),
          ],
        ),
        body: _buildStudentList(),
      );
    }
    
    // Desktop: Dialog
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.indigo,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.people, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.className,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_students.length} Öğrenci',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      // Yeni öğrenci ekle dialog'unu aç
                      _showAddStudentDialog();
                    },
                    icon: Icon(Icons.person_add, color: Colors.white),
                    tooltip: 'Yeni Öğrenci Ekle',
                  ),
                  if (_students.isNotEmpty)
                    IconButton(
                      onPressed: _copyStudentsToClass,
                      icon: Icon(Icons.copy_all, color: Colors.white),
                      tooltip: 'Öğrencileri Kopyala',
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Öğrenci Listesi
            Expanded(
              child: _buildStudentList(),
            ),
          ],
        ),
      ),
    );
  }
}

// Öğrencileri Kopyalama Dialog'u
class CopyStudentsDialog extends StatefulWidget {
  final String sourceClassId;
  final String sourceClassName;
  final List<Map<String, dynamic>> students;

  const CopyStudentsDialog({
    Key? key,
    required this.sourceClassId,
    required this.sourceClassName,
    required this.students,
  }) : super(key: key);

  @override
  State<CopyStudentsDialog> createState() => _CopyStudentsDialogState();
}

class _CopyStudentsDialogState extends State<CopyStudentsDialog> {
  List<Map<String, dynamic>> _targetClasses = [];
  String? _selectedTargetClassId;
  bool _isLoading = true;
  bool _isCopying = false;

  @override
  void initState() {
    super.initState();
    _loadTargetClasses();
  }

  Future<void> _loadTargetClasses() async {
    try {
      // Kaynak sınıfın bilgilerini al
      final sourceClassDoc = await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.sourceClassId)
          .get();

      final sourceData = sourceClassDoc.data();
      final sourceSchoolTypeId = sourceData?['schoolTypeId'];
      final sourceClassLevel = sourceData?['classLevel'];

      // Aynı okul türü ve sınıf seviyesindeki FARKLI TİPTEKİ sınıfları getir
      final snapshot = await FirebaseFirestore.instance
          .collection('classes')
          .where('schoolTypeId', isEqualTo: sourceSchoolTypeId)
          .where('classLevel', isEqualTo: sourceClassLevel)
          .where('isActive', isEqualTo: true)
          .get();

      final classes = snapshot.docs
          .where((doc) {
            // Kaynak sınıfı ve "Ders Sınıfı" tipindeki sınıfları hariç tut
            return doc.id != widget.sourceClassId &&
                doc.data()['classTypeName'] != 'Ders Sınıfı';
          })
          .map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          })
          .toList();

      if (mounted) {
        setState(() {
          _targetClasses = classes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _copyStudents() async {
    if (_selectedTargetClassId == null) return;

    setState(() => _isCopying = true);

    try {
      final targetClass = _targetClasses.firstWhere(
        (c) => c['id'] == _selectedTargetClassId,
      );

      final batch = FirebaseFirestore.instance.batch();

      for (final student in widget.students) {
        final studentRef = FirebaseFirestore.instance
            .collection('students')
            .doc(student['id']);

        // Öğrencinin mevcut ekstra sınıflarını al
        List<dynamic> extraClasses = student['extraClasses'] ?? [];

        // Yeni sınıfı ekle
        extraClasses.add({
          'classId': _selectedTargetClassId,
          'className': targetClass['className'],
          'classTypeId': targetClass['classTypeId'],
          'classTypeName': targetClass['classTypeName'],
          'addedAt': DateTime.now().toIso8601String(),
        });

        batch.update(studentRef, {
          'extraClasses': extraClasses,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }

      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${widget.students.length} öğrenci ${targetClass['className']} sınıfına kopyalandı'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCopying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Öğrencileri Kopyala'),
      content: Container(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.sourceClassName} sınıfındaki ${widget.students.length} öğrenciyi farklı bir sınıfa kopyalayın.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            SizedBox(height: 20),
            if (_isLoading)
              Center(child: CircularProgressIndicator())
            else if (_targetClasses.isEmpty)
              Text(
                'Kopyalanabilecek uygun sınıf bulunamadı.',
                style: TextStyle(color: Colors.red),
              )
            else
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Hedef Sınıf',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.class_),
                ),
                value: _selectedTargetClassId,
                items: _targetClasses.map((c) {
                  return DropdownMenuItem<String>(
                    value: c['id'] as String,
                    child: Text('${c['className']} - ${c['classTypeName']}'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedTargetClassId = value);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCopying ? null : () => Navigator.pop(context),
          child: Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _isCopying || _selectedTargetClassId == null
              ? null
              : _copyStudents,
          child: _isCopying
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Kopyala'),
        ),
      ],
    );
  }
}

// Sınıfa Öğrenci Ekleme Dialog'u
class AddStudentToClassDialog extends StatefulWidget {
  final String classId;
  final String className;
  final List<Map<String, dynamic>> availableStudents;
  final VoidCallback onStudentAdded;

  const AddStudentToClassDialog({
    Key? key,
    required this.classId,
    required this.className,
    required this.availableStudents,
    required this.onStudentAdded,
  }) : super(key: key);

  @override
  State<AddStudentToClassDialog> createState() => _AddStudentToClassDialogState();
}

class _AddStudentToClassDialogState extends State<AddStudentToClassDialog> {
  List<String> _selectedStudentIds = [];
  String _searchQuery = '';
  bool _isAdding = false;

  String _getStudentInitial(dynamic value) {
    if (value == null) return '?';
    final str = value.toString();
    if (str.isEmpty) return '?';
    return str.substring(0, 1).toUpperCase();
  }

  List<Map<String, dynamic>> get _filteredStudents {
    if (_searchQuery.isEmpty) {
      print('🔍 Arama boş, tüm öğrenciler gösteriliyor: ${widget.availableStudents.length}');
      return widget.availableStudents;
    }
    
    final filtered = widget.availableStudents.where((student) {
      final fullName = (student['fullName'] ?? '').toLowerCase();
      final studentNo = (student['studentNo'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return fullName.contains(query) || studentNo.contains(query);
    }).toList();
    
    print('🔍 Arama: "$_searchQuery" - Bulunan: ${filtered.length}');
    return filtered;
  }

  Future<void> _addStudents() async {
    if (_selectedStudentIds.isEmpty) return;

    // Öğrencilerin mevcut sınıf bilgilerini kontrol et
    final studentsWithClass = <String>[];
    for (final studentId in _selectedStudentIds) {
      final student = widget.availableStudents.firstWhere(
        (s) => s['id'] == studentId,
        orElse: () => {},
      );
      if (student['className'] != null && student['className'].toString().isNotEmpty) {
        studentsWithClass.add('${student['fullName']} (${student['className']})');
      }
    }

    // Eğer öğrenciler başka sınıftaysa, onay iste
    if (studentsWithClass.isNotEmpty && mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('⚠️ Sınıf Değişikliği'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Aşağıdaki öğrenciler başka bir sınıfta kayıtlı:'),
              SizedBox(height: 8),
              ...studentsWithClass.map((s) => Text('• $s')),
              SizedBox(height: 12),
              Text('Bu öğrencilerin sınıfını değiştirmek istiyor musunuz?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Değiştir'),
            ),
          ],
        ),
      );

      if (confirm != true) {
        setState(() => _isAdding = false);
        return;
      }
    }

    setState(() => _isAdding = true);

    try {
      final batch = FirebaseFirestore.instance.batch();

      // Sınıf seviyesini al
      final classDoc = await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.classId)
          .get();
      final classLevel = classDoc.data()?['classLevel'];

      for (final studentId in _selectedStudentIds) {
        final studentRef = FirebaseFirestore.instance
            .collection('students')
            .doc(studentId);

        batch.update(studentRef, {
          'classId': widget.classId,
          'className': widget.className,
          'classLevel': classLevel,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }

      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
        
        // Kısa bir gecikme ile listeyi yenile
        await Future.delayed(Duration(milliseconds: 300));
        widget.onStudentAdded();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${_selectedStudentIds.length} öğrenci sınıfa eklendi'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.6,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.indigo,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_add, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Öğrenci Ekle',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.className,
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Arama
            Padding(
              padding: EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Öğrenci ara (ad veya numara)...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
              ),
            ),

            // Seçili öğrenci sayısı
            if (_selectedStudentIds.isNotEmpty)
              Container(
                margin: EdgeInsets.symmetric(horizontal: 16),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.indigo, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '${_selectedStudentIds.length} öğrenci seçildi',
                      style: TextStyle(
                        color: Colors.indigo,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() => _selectedStudentIds.clear());
                      },
                      child: Text('Temizle'),
                    ),
                  ],
                ),
              ),

            SizedBox(height: 8),

            // Öğrenci Listesi
            Expanded(
              child: _filteredStudents.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'Eklenebilecek öğrenci bulunamadı'
                                : 'Arama sonucu bulunamadı',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filteredStudents.length,
                      itemBuilder: (context, index) {
                        final student = _filteredStudents[index];
                        final studentId = student['id'];
                        final isSelected = _selectedStudentIds.contains(studentId);

                        final isDifferentSchoolType = student['isDifferentSchoolType'] == true;
                        
                        return Card(
                          margin: EdgeInsets.only(bottom: 8),
                          color: isSelected 
                              ? Colors.indigo.shade50 
                              : (isDifferentSchoolType ? Colors.orange.shade50 : null),
                          child: CheckboxListTile(
                            value: isSelected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedStudentIds.add(studentId);
                                } else {
                                  _selectedStudentIds.remove(studentId);
                                }
                              });
                            },
                            title: Row(
                              children: [
                                Expanded(child: Text(student['fullName']?.toString() ?? '')),
                                if (isDifferentSchoolType)
                                  Tooltip(
                                    message: 'Farklı okul türü',
                                    child: Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              'No: ${student['studentNo'] ?? '-'} ${student['currentClassInfo'] ?? ''}',
                            ),
                            secondary: CircleAvatar(
                              backgroundColor: isSelected
                                  ? Colors.indigo
                                  : Colors.grey.shade300,
                              child: Text(
                                _getStudentInitial(student['fullName']),
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Footer
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isAdding ? null : () => Navigator.pop(context),
                    child: Text('İptal'),
                  ),
                  SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isAdding || _selectedStudentIds.isEmpty
                        ? null
                        : _addStudents,
                    icon: _isAdding
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(Icons.add),
                    label: Text(_isAdding ? 'Ekleniyor...' : 'Ekle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
