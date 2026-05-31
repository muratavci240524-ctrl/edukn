import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:archive/archive.dart';
import 'dart:typed_data';
import 'parent_report_pdf_helper.dart';

class ParentReportDashboard extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;

  const ParentReportDashboard({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  _ParentReportDashboardState createState() => _ParentReportDashboardState();
}

class _ParentReportDashboardState extends State<ParentReportDashboard> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // General States
  bool _isLoading = false;
  bool _isDetailLoading = false;
  String _searchQuery = '';
  String? _selectedClassFilter;
  final ScrollController _examsScrollController = ScrollController();

  // Çoklu öğrenci seçimi ve navigasyon states
  final Set<String> _selectedStudentIds = {};
  int _currentStudentIndex = 0;
  bool _isGeneratingPdf = false;

  List<Map<String, dynamic>> get _selectedStudentsList {
    // Listeyi orijinal _students sıralamasında tutuyoruz
    return _students.where((s) => _selectedStudentIds.contains(s['id'])).toList();
  }

  List<Map<String, dynamic>> get _navigationStudentsList {
    return _selectedStudentIds.isNotEmpty ? _selectedStudentsList : _filteredStudents;
  }

  void _navigateToStudent(int index) {
    final list = _navigationStudentsList;
    if (list.isEmpty) return;
    
    // Ensure index bounds
    if (index < 0) index = list.length - 1;
    if (index >= list.length) index = 0;
    
    setState(() {
      _currentStudentIndex = index;
      _selectedStudent = list[index];
    });
    _loadStudentSpecificDetails(_selectedStudent!['id']);
  }

  // Data Lists
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  List<String> _classLevels = [];
  List<Map<String, dynamic>> _allExams = [];
  List<Map<String, dynamic>> _allAgmCycles = [];
  List<Map<String, dynamic>> _allCampCycles = [];
  List<Map<String, dynamic>> _allStudyPrograms = [];

  // Current Selections
  Map<String, dynamic>? _selectedStudent;
  final List<Map<String, dynamic>> _selectedExamsToInclude = [];
  final Set<String> _selectedExamIds = {};

  final Set<String> _selectedAgmCycleIds = {};
  final Set<String> _selectedCampCycleIds = {};
  String? _selectedStudyProgramId;

  // Include flags
  bool _includeExams = true;
  bool _includeAgm = true;
  bool _includeCamp = true;
  bool _includeStudyPrograms = true;

  // AGM sütun görünürlükleri
  bool _agmShowBranch = true;
  bool _agmShowTeacher = true;
  bool _agmShowKazanim = true;
  bool _agmShowDurum = true;

  // Kamp sütun görünürlükleri
  bool _campShowBranch = true;
  bool _campShowTeacher = true;
  bool _campShowKazanim = true;
  bool _campShowDurum = true;
  bool _campShowExcludedAsNotParticipated = true;
  bool _campShowAbsentAsNotParticipated = true;

  // Çalışma programı kazanım listesi
  bool _includeKazanimList = false;


  // Loaded Details for PDF
  List<Map<String, dynamic>> _pdfSelectedExamsData = [];
  List<Map<String, dynamic>> _pdfAgmAssignments = [];
  List<Map<String, dynamic>> _pdfCampAssignments = [];
  List<Map<String, dynamic>> _pdfStudyPrograms = [];

  // Custom metadata states
  Map<String, String> _lessonAbbreviations = {};
  Map<String, List<String>> _examTypeSubjectOrders = {};
  String _classTeacherName = 'Belirtilmedi';
  String _principalName = 'Belirtilmedi';

  // Section 6 & 7 States
  bool _includeTopicAnalysis = false;
  bool _topicAnalysisShowPriority = false;
  bool _topicAnalysisShowReinforcement = true;
  Map<String, int> _topicAnalysisThresholds = {};
  List<dynamic> _studentTopicAnalysis = [];
  
  bool _includeLessonPlans = true;
  late DateTime _selectedLessonPlanWeekStart;
  List<Map<String, dynamic>> _pdfLessonPlans = [];

  // Section 8 (Alt Bilgi / Footer) States
  bool _includeFooter = true;
  bool _footerShowTeacher = true;
  bool _footerShowPageNumber = true;
  bool _footerShowPrincipal = true;
  String _footerSlogan = 'Eğitim ve Gelişimde Başarılar Dileriz.';

  // Mektup (Letter) Controller
  late TextEditingController _letterController;
  final String _defaultLetterTemplate =
      'Öğrencimizin bu dönemki gelişim raporunu, katıldığı akademik faaliyetleri, yoğunlaştırılmış programları ve deneme sınavı başarı durumunu içeren bilgilendirme yazımız aşağıda bilgilerinize sunulmuştur.\n\nÖğrencimizin gelişim durumunu yakından takip etmeye ve başarılarını desteklemeye devam ediyoruz. Gösterdiği gayret ve disiplin için öğrencimizi tebrik eder, eğitim sürecindeki iş birliğiniz için teşekkür ederiz.';

  Future<Uint8List> _generateCurrentPdfBytes() async {
    if (_selectedStudent == null) return Uint8List(0);
    return await ParentReportPdfHelper.generateReport(
      studentName: _selectedStudent!['name'],
      studentClass: _selectedStudent!['class'],
      studentNo: _selectedStudent!['studentNo'],
      letterContent: _letterController.text,
      selectedExams: _pdfSelectedExamsData,
      agmAssignments: _pdfAgmAssignments,
      campAssignments: _pdfCampAssignments,
      studyPrograms: _pdfStudyPrograms,
      includeExams: _includeExams,
      includeAgm: _includeAgm,
      includeCamp: _includeCamp,
      includeStudyPrograms: _includeStudyPrograms,
      lessonAbbreviations: _lessonAbbreviations,
      examTypeSubjectOrders: _examTypeSubjectOrders,
      classTeacherName: _classTeacherName,
      principalName: _principalName,
      agmShowBranch: _agmShowBranch,
      agmShowTeacher: _agmShowTeacher,
      agmShowKazanim: _agmShowKazanim,
      agmShowDurum: _agmShowDurum,
      campShowBranch: _campShowBranch,
      campShowTeacher: _campShowTeacher,
      campShowKazanim: _campShowKazanim,
      campShowDurum: _campShowDurum,
      includeKazanimList: _includeKazanimList,
      includeTopicAnalysis: _includeTopicAnalysis,
      topicAnalysisThresholds: _topicAnalysisThresholds,
      studentTopicAnalysis: _studentTopicAnalysis,
      topicAnalysisShowPriority: _topicAnalysisShowPriority,
      topicAnalysisShowReinforcement: _topicAnalysisShowReinforcement,
      includeLessonPlans: _includeLessonPlans,
      lessonPlans: _pdfLessonPlans,
      includeFooter: _includeFooter,
      footerShowTeacher: _footerShowTeacher,
      footerShowPageNumber: _footerShowPageNumber,
      footerShowPrincipal: _footerShowPrincipal,
      footerSlogan: _footerSlogan,
    );
  }

  Future<void> _printCurrentReport() async {
    if (_selectedStudent == null || _isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final bytes = await _generateCurrentPdfBytes();
      await Printing.layoutPdf(onLayout: (format) => bytes);
    } catch (e) {
      print('Yazdirma Hatasi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yazdırma hatası: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  Future<void> _shareCurrentReport() async {
    if (_selectedStudent == null || _isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final bytes = await _generateCurrentPdfBytes();
      final filename = 'Veli_Bilgilendirme_${_selectedStudent!['name'].toString().replaceAll(' ', '_')}.pdf';
      await Printing.sharePdf(
        bytes: bytes,
        filename: filename,
      );
    } catch (e) {
      print('Paylasma Hatasi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paylaşma hatası: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  static DateTime _getStartOfWeek(DateTime date) {
    final weekday = date.weekday;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    _selectedLessonPlanWeekStart = _getStartOfWeek(DateTime.now());
    _letterController = TextEditingController(text: _defaultLetterTemplate);
    _letterController.addListener(() {
      setState(() {}); // Trigger PDF preview rebuild on letter edit
    });
    _loadInitialData();
  }

  @override
  void dispose() {
    _letterController.dispose();
    _examsScrollController.dispose();
    super.dispose();
  }

  // Load Students, Exams, AGM, Camps
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch Students
      final studentSnap = await _db
          .collection('students')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      final List<Map<String, dynamic>> loadedStudents = [];
      final Set<String> classes = {};

      for (var doc in studentSnap.docs) {
        final data = doc.data();
        final name = data['fullName'] ?? '${data['name'] ?? ''} ${data['surname'] ?? ''}'.trim();
        final className = data['className'] ?? data['studentBranch'] ?? 'Belirtilmedi';

        if (className != 'Belirtilmedi' && className.isNotEmpty) {
          classes.add(className);
        }

        loadedStudents.add({
          'id': doc.id,
          'name': name.isEmpty ? 'İsimsiz Öğrenci' : name,
          'class': className,
          'studentNo': data['studentNo'] ?? data['number'] ?? data['schoolNumber'] ?? data['studentNumber'] ?? data['no'] ?? '-',
          'rawData': data,
        });
      }

      // Sort students
      loadedStudents.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));

      // 2. Fetch Trial Exams
      final examSnap = await _db
          .collection('trial_exams')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final List<Map<String, dynamic>> loadedExams = examSnap.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? 'Deneme Sınavı',
          'date': (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
          'resultsJson': data['resultsJson'] ?? '',
          'examTypeId': data['examTypeId'] ?? '',
          'outcomes': data['outcomes'] ?? {},
          'answerKeys': data['answerKeys'] ?? {},
        };
      }).toList();

      loadedExams.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

      // 3. Fetch AGM Cycles
      final agmSnap = await _db
          .collection('agm_cycles')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();

      final List<Map<String, dynamic>> loadedAgm = agmSnap.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['title'] ?? data['name'] ?? data['donemAdi'] ?? 'AGM Dönemi',
        };
      }).toList();

      // 4. Fetch Camp Cycles
      final campSnap = await _db
          .collection('camp_cycles')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .get();

      final List<Map<String, dynamic>> loadedCamp = campSnap.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['title'] ?? data['name'] ?? data['donemAdi'] ?? 'Kamp Dönemi',
          'excludedStudentIds': List<String>.from(data['excludedStudentIds'] ?? []),
        };
      }).toList();

      // 5. Fetch lessons for custom abbreviations
      final lessonsSnap = await _db
          .collection('lessons')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      final Map<String, String> lessonAbbreviations = {};
      for (var doc in lessonsSnap.docs) {
        final data = doc.data();
        final lessonName = (data['lessonName'] ?? '').toString().toLowerCase().trim();
        final branchName = (data['branchName'] ?? '').toString().toLowerCase().trim();
        final shortName = (data['shortName'] ?? '').toString().trim();
        if (shortName.isNotEmpty) {
          if (lessonName.isNotEmpty) lessonAbbreviations[lessonName] = shortName;
          if (branchName.isNotEmpty) lessonAbbreviations[branchName] = shortName;
        }
      }

      // 6. Fetch exam types for subject ordering
      final examTypesSnap = await _db
          .collection('exam_types')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final Map<String, List<String>> examTypeSubjectOrders = {};
      for (var doc in examTypesSnap.docs) {
        final data = doc.data();
        final subjectsRaw = data['subjects'] as List<dynamic>? ?? [];
        final List<String> orderedBranches = [];
        for (var sub in subjectsRaw) {
          if (sub is Map) {
            final bName = sub['branchName']?.toString() ?? '';
            if (bName.isNotEmpty) {
              orderedBranches.add(bName);
            }
          }
        }
        examTypeSubjectOrders[doc.id] = orderedBranches;
      }

      setState(() {
        _students = loadedStudents;
        _classLevels = classes.toList()..sort();
        _allExams = loadedExams;
        _allAgmCycles = loadedAgm;
        _allCampCycles = loadedCamp;
        _lessonAbbreviations = lessonAbbreviations;
        _examTypeSubjectOrders = examTypeSubjectOrders;

        // Pre-select latest 2 exams if none selected
        if (_selectedExamIds.isEmpty) {
          for (int i = 0; i < 2 && i < _allExams.length; i++) {
            final exam = _allExams[i];
            _selectedExamIds.add(exam['id']);
            _selectedExamsToInclude.add(exam);
          }
        }

        // Pre-select latest AGM and Camp cycles if none selected
        if (_selectedAgmCycleIds.isEmpty && _allAgmCycles.isNotEmpty) {
          _selectedAgmCycleIds.add(_allAgmCycles.first['id']);
        }
        if (_selectedCampCycleIds.isEmpty && _allCampCycles.isNotEmpty) {
          _selectedCampCycleIds.add(_allCampCycles.first['id']);
        }

        _filterStudents();
        _isLoading = false;
      });
    } catch (e) {
      print('Parent Reports Loader Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterStudents() {
    setState(() {
      _filteredStudents = _students.where((s) {
        final nameMatch = s['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            s['studentNo'].toString().contains(_searchQuery);
        final classMatch = _selectedClassFilter == null || s['class'] == _selectedClassFilter;
        return nameMatch && classMatch;
      }).toList();
    });
  }

  // Fetch Student Specific Details (Exams, AGM, Camps, Study Programs)
  Future<void> _loadStudentSpecificDetails(String studentId) async {
    setState(() => _isDetailLoading = true);
    try {
      // Clear previous student specific detail states
      _pdfSelectedExamsData.clear();
      _pdfAgmAssignments.clear();
      _pdfCampAssignments.clear();
      _pdfStudyPrograms.clear();
      _selectedStudyProgramId = null;

      // 1. Fetch study programs for this student
      final studyProgramSnap = await _db
          .collection('institutions')
          .doc(widget.institutionId)
          .collection('study_programs')
          .where('studentId', isEqualTo: studentId)
          .orderBy('createdAt', descending: true)
          .get();

      _allStudyPrograms = studyProgramSnap.docs.map((doc) {
        final data = doc.data();
        final createdVal = data['createdAt'];
        String formattedDate = '';
        if (createdVal is Timestamp) {
          final d = createdVal.toDate();
          formattedDate = '${d.day}.${d.month}.${d.year}';
        }
        return {
          'id': doc.id,
          'title': data['title'] ?? 'Bireysel Çalışma Programı',
          'description': data['description'] ?? '',
          'subjects': data['subjects'] ?? [],
          'schedule': (data['schedule'] is Map) ? Map<String, dynamic>.from(data['schedule'] as Map) : <String, dynamic>{},
          'executionStatus': (data['executionStatus'] is Map) ? Map<String, dynamic>.from(data['executionStatus'] as Map) : <String, dynamic>{},
          'createdAtLabel': formattedDate,
          'topicAnalysis': data['topicAnalysis'] ?? [],
          'thresholds': (data['thresholds'] is Map) ? Map<String, dynamic>.from(data['thresholds'] as Map) : <String, dynamic>{},
        };
      }).toList();

      // Pre-select latest study program if available
      if (_allStudyPrograms.isNotEmpty) {
        _selectedStudyProgramId = _allStudyPrograms.first['id'];
        _pdfStudyPrograms = [_allStudyPrograms.first];
        
        final firstProg = _allStudyPrograms.first;
        _studentTopicAnalysis = firstProg['topicAnalysis'] ?? [];
        final Map<String, int> thresh = {};
        final rawThresholds = firstProg['thresholds'] ?? {};
        rawThresholds.forEach((k, v) {
          thresh[k.toString()] = int.tryParse(v.toString()) ?? 70;
        });
        _topicAnalysisThresholds = thresh;
        
        final Set<String> uniqueSubjects = {};
        for (var item in _studentTopicAnalysis) {
          if (item is Map) {
            final sub = item['dersAdi']?.toString() ?? item['ders']?.toString() ?? item['subject']?.toString() ?? '';
            if (sub.isNotEmpty) uniqueSubjects.add(sub);
          }
        }
        for (var sub in uniqueSubjects) {
          if (!_topicAnalysisThresholds.containsKey(sub)) {
            _topicAnalysisThresholds[sub] = 70;
          }
        }
        if (!_topicAnalysisThresholds.containsKey('Genel')) {
          _topicAnalysisThresholds['Genel'] = 70;
        }
      } else {
        _studentTopicAnalysis = [];
        _topicAnalysisThresholds = {'Genel': 70};
      }

      _rebuildPdfExamsData();

      await _fetchAgmAssignments(studentId, _selectedAgmCycleIds);
      await _fetchCampAssignments(studentId, _selectedCampCycleIds);

      // Fetch Sınıf Rehber Öğretmeni
      String teacherName = 'Belirtilmedi';
      final studentData = (_selectedStudent?['rawData'] is Map)
          ? Map<String, dynamic>.from(_selectedStudent!['rawData'] as Map)
          : <String, dynamic>{};
      final classId = studentData['classId']?.toString() ?? '';
      final className = _selectedStudent?['class']?.toString() ?? studentData['className']?.toString() ?? '';

      if (classId.isNotEmpty) {
        final classDoc = await _db.collection('classes').doc(classId).get();
        if (classDoc.exists) {
          teacherName = classDoc.data()?['classTeacherName']?.toString() ?? 'Belirtilmedi';
        }
      }

      if (teacherName == 'Belirtilmedi' && className.isNotEmpty && className != 'Belirtilmedi') {
        final classQuery = await _db
            .collection('classes')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('className', isEqualTo: className)
            .where('isActive', isEqualTo: true)
            .get();
        if (classQuery.docs.isNotEmpty) {
          teacherName = classQuery.docs.first.data()['classTeacherName']?.toString() ?? 'Belirtilmedi';
        }
      }

      // Fetch Kurum Yöneticisi (Müdür) — önce bu okul türüne atanmış Müdür, yoksa Genel Müdür
      String principalName = 'Belirtilmedi';
      try {
        final usersSnap = await _db
            .collection('users')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('isActive', isEqualTo: true)
            .get();

        // Priority buckets:
        //  1 = okul türüne atanmış Müdür       ← en yüksek
        //  2 = okul türüne atanmış Müdür Yrd.
        //  3 = herhangi bir Müdür (okul türü ataması olmayan)
        //  4 = Genel Müdür                     ← son çare
        Map<String, dynamic>? bestPrincipal;
        int bestPriority = 99;

        for (var doc in usersSnap.docs) {
          final uData = doc.data();
          final role = (uData['role'] ?? '').toString().toLowerCase().trim();
          final title = (uData['title'] ?? uData['empTitle'] ?? '').toString().toLowerCase().trim();
          final uName = (uData['fullName'] ?? '${uData['name'] ?? ''} ${uData['surname'] ?? ''}'.trim()).toString().trim();
          if (uName.isEmpty) continue;

          // schoolTypes: bu kullanıcının atandığı okul türü ID listesi
          final schoolTypesRaw = uData['schoolTypes'];
          final List<String> userSchoolTypes = (schoolTypesRaw is List)
              ? schoolTypesRaw.map((e) => e.toString()).toList()
              : [];
          final bool assignedToThisSchool = userSchoolTypes.contains(widget.schoolTypeId);

          final bool isMudur = role == 'mudur' || title == 'mudur' ||
              role == 'müdür' || title == 'müdür' ||
              role.contains('müdür') || title.contains('müdür');
          final bool isMudurYrd = role == 'mudur_yardimcisi' || title == 'mudur_yardimcisi' ||
              role.contains('yardımcı') || title.contains('yardımcı');
          final bool isGenelMudur = role == 'genel_mudur' || title == 'genel_mudur' ||
              role.contains('genel müdür') || title.contains('genel müdür') ||
              role.contains('genel_mudur') || title.contains('genel_mudur');

          int priority = 99;
          if (isMudur && assignedToThisSchool) {
            priority = 1; // Bu okul türünün müdürü — en iyi seçim
          } else if (isMudurYrd && assignedToThisSchool) {
            priority = 2; // Bu okul türünün müdür yardımcısı
          } else if (isMudur && !isGenelMudur) {
            priority = 3; // Okul türü ataması olmayan genel müdür
          } else if (isGenelMudur) {
            priority = 4; // Son çare: genel müdür
          }

          if (priority < bestPriority) {
            bestPriority = priority;
            bestPrincipal = uData;
          }
        }

        if (bestPrincipal != null) {
          principalName = (bestPrincipal['fullName'] ?? '${bestPrincipal['name'] ?? ''} ${bestPrincipal['surname'] ?? ''}'.trim()).toString().trim();
        }
      } catch (e) {
        print('Error fetching principal: $e');
      }

      await _fetchLessonPlans(classId);

      setState(() {
        _classTeacherName = teacherName;
        _principalName = principalName;
        _isDetailLoading = false;
      });
    } catch (e) {
      print('Load Student Details Error: $e');
      setState(() => _isDetailLoading = false);
    }
  }

  Future<void> _fetchLessonPlans(String classId) async {
    try {
      if (classId.isEmpty) {
        setState(() {
          _pdfLessonPlans = [];
        });
        return;
      }
      
      final snap = await _db
          .collection('classLessonPlans')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('classId', isEqualTo: classId)
          .get();
          
      final startOfWeek = _selectedLessonPlanWeekStart;
      final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
      
      final List<Map<String, dynamic>> temp = [];
      for (var doc in snap.docs) {
        final data = doc.data();
        final dateVal = data['date'];
        
        DateTime? dt;
        if (dateVal is Timestamp) {
          dt = dateVal.toDate();
        } else if (dateVal is String) {
          dt = DateTime.tryParse(dateVal);
        }
        
        if (dt != null) {
          if (dt.isAfter(startOfWeek.subtract(const Duration(seconds: 1))) && 
              dt.isBefore(endOfWeek.add(const Duration(seconds: 1)))) {
            temp.add({
              'id': doc.id,
              'lessonName': data['lessonName'] ?? data['lesson'] ?? '-',
              'title': data['title'] ?? '',
              'content': data['content'] ?? '',
              'outcome': data['outcome'] ?? data['kazanim'] ?? '-',
              'date': dt,
            });
          }
        }
      }
      
      temp.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
      
      setState(() {
        _pdfLessonPlans = temp;
      });
    } catch (e) {
      print('Fetch Lesson Plans Error: $e');
    }
  }

  // Fetch specific AGM assignments for multiple cycles
  Future<void> _fetchAgmAssignments(String studentId, Set<String> cycleIds) async {
    if (cycleIds.isEmpty) {
      setState(() {
        _pdfAgmAssignments = [];
      });
      return;
    }

    try {
      final List<Map<String, dynamic>> tempAgm = [];
      for (final cycleId in cycleIds) {
        final cycleMap = _allAgmCycles.firstWhere(
          (c) => c['id'] == cycleId,
          orElse: () => <String, dynamic>{},
        );
        final cycleName = cycleMap['name'] ?? 'AGM Dönemi';

        final assignSnap = await _db
            .collection('agm_assignments')
            .where('cycleId', isEqualTo: cycleId)
            .where('ogrenciId', isEqualTo: studentId)
            .get();

        for (var doc in assignSnap.docs) {
          final data = doc.data();
          final groupId = data['groupId']?.toString() ?? '';
          final isAbsent = data['isAbsent'] as bool? ?? false;

          // Get group details
          final groupDoc = await _db.collection('agm_groups').doc(groupId).get();
          if (groupDoc.exists) {
            final gData = groupDoc.data() ?? {};
            final kazanimlar = gData['kazanimlar'];
            final List<String> kazanimList = (kazanimlar is List)
                ? kazanimlar.map((e) => e.toString()).toList()
                : [];
            final String anaKazanim = kazanimList.isNotEmpty ? kazanimList.first : '-';

            // Fetch etüt attendance
            bool attended = !isAbsent;
            try {
              final etutSnap = await _db
                  .collection('etut_requests')
                  .where('agmCycleId', isEqualTo: cycleId)
                  .where('agmGroupId', isEqualTo: groupId)
                  .limit(1)
                  .get();

              if (etutSnap.docs.isNotEmpty) {
                final etutData = etutSnap.docs.first.data();
                final attendanceMapRaw = etutData['attendance'];
                final attendanceMap = (attendanceMapRaw is Map)
                    ? Map<String, dynamic>.from(attendanceMapRaw)
                    : <String, dynamic>{};
                if (attendanceMap.containsKey(studentId)) {
                  attended = attendanceMap[studentId] == true;
                }
              }
            } catch (e) {
              print('Error fetching AGM etut attendance: $e');
            }

            tempAgm.add({
              'cycleId': cycleId,
              'cycleName': cycleName,
              'dersAdi': gData['dersAdi'] ?? gData['ders'] ?? '-',
              'ogretmenAdi': gData['ogretmenAdi'] ?? gData['ogretmen'] ?? '-',
              'derslikAdi': gData['derslikAdi'] ?? gData['derslik'] ?? '-',
              'saatDilimi': gData['saatDilimiAdi'] ?? gData['saatDilimiId'] ?? '',
              'anaKazanim': anaKazanim,
              'kazanimList': kazanimList,
              'attended': attended,
            });
          }
        }
      }
      setState(() {
        _pdfAgmAssignments = tempAgm;
      });
    } catch (e) {
      print('Fetch AGM Assignments Error: $e');
    }
  }

  // Fetch specific Camp assignments for multiple cycles
  Future<void> _fetchCampAssignments(String studentId, Set<String> cycleIds) async {
    if (cycleIds.isEmpty) {
      setState(() {
        _pdfCampAssignments = [];
      });
      return;
    }

    try {
      final List<Map<String, dynamic>> tempCamp = [];
      for (final cycleId in cycleIds) {
        final cycleMap = _allCampCycles.firstWhere(
          (c) => c['id'] == cycleId,
          orElse: () => <String, dynamic>{},
        );
        final cycleName = cycleMap['name'] ?? 'Kamp Dönemi';
        final excludedStudentIds = List<String>.from(cycleMap['excludedStudentIds'] ?? []);

        // Check if student is excluded from this camp cycle
        if (excludedStudentIds.contains(studentId)) {
          tempCamp.add({
            'cycleId': cycleId,
            'cycleName': cycleName,
            'isExcluded': true,
            'dersAdi': '-',
            'ogretmenAdi': '-',
            'anaKazanim': '-',
            'attended': false,
          });
          continue;
        }

        final assignSnap = await _db
            .collection('camp_assignments')
            .where('cycleId', isEqualTo: cycleId)
            .where('ogrenciId', isEqualTo: studentId)
            .get();

        if (assignSnap.docs.isEmpty) {
          tempCamp.add({
            'cycleId': cycleId,
            'cycleName': cycleName,
            'isExcluded': true,
            'dersAdi': '-',
            'ogretmenAdi': '-',
            'anaKazanim': '-',
            'attended': false,
          });
          continue;
        }

        for (var doc in assignSnap.docs) {
          final data = doc.data();
          final groupId = data['groupId'];
          final isAbsent = data['isAbsent'] as bool? ?? false;

          // Get group details
          final groupDoc = await _db.collection('camp_groups').doc(groupId).get();
          if (groupDoc.exists) {
            final gData = groupDoc.data() ?? {};
            final kazanimlar = gData['kazanimlar'] as List<dynamic>? ?? [];
            final String anaKazanim = kazanimlar.isNotEmpty ? kazanimlar.first.toString() : '-';

            bool attended = !isAbsent;
            try {
              final etutSnap = await _db
                  .collection('etut_requests')
                  .where('campCycleId', isEqualTo: cycleId)
                  .where('campGroupId', isEqualTo: groupId)
                  .limit(1)
                  .get();

              if (etutSnap.docs.isNotEmpty) {
                final etutData = etutSnap.docs.first.data();
                final attendanceMapRaw = etutData['attendance'];
                final attendanceMap = (attendanceMapRaw is Map) ? Map<String, dynamic>.from(attendanceMapRaw) : <String, dynamic>{};
                if (attendanceMap.containsKey(studentId)) {
                  attended = attendanceMap[studentId] == true;
                }
              }
            } catch (e) {
              print('Error fetching etut attendance: $e');
            }

            tempCamp.add({
              'cycleId': cycleId,
              'cycleName': cycleName,
              'isExcluded': false,
              'dersAdi': gData['dersAdi'] ?? gData['ders'] ?? '-',
              'ogretmenAdi': gData['ogretmenAdi'] ?? gData['ogretmen'] ?? '-',
              'anaKazanim': anaKazanim,
              'attended': attended,
            });
          }
        }
      }
      setState(() {
        _pdfCampAssignments = tempCamp;
      });
    } catch (e) {
      print('Fetch Camp Assignments Error: $e');
    }
  }

  // Helper to find student in resultsJson decoded array
  Map<String, dynamic>? _findStudentInExamResults(List<dynamic> results, String studentId, {Map<String, dynamic>? targetStudent}) {
    final sMap = targetStudent ?? _selectedStudent;
    if (sMap == null) return null;
    final sNo = sMap['studentNo']?.toString().trim();

    for (var r in results) {
      if (r is! Map) continue;
      final rMap = Map<String, dynamic>.from(r);

      // Match by system id
      if (rMap['systemStudentId']?.toString() == studentId) return rMap;

      // Match by student no
      final rNo = (rMap['studentNo'] ?? rMap['studentNumber'] ?? rMap['number'] ?? rMap['no'])?.toString().trim();
      if (sNo != null && sNo.isNotEmpty && rNo != null && rNo.isNotEmpty && sNo == rNo) return rMap;

      // Match by name
      final rawRName = (rMap['name'] ?? rMap['studentName'] ?? rMap['ogrenci'] ?? rMap['adSoyad'] ?? rMap['ad_soyad'] ?? '').toString();
      final rawSName = (sMap['name'] as String? ?? '').toString();
      if (rawSName.isNotEmpty && rawRName.isNotEmpty) {
        final normS = _normalizeName(rawSName);
        final normR = _normalizeName(rawRName);
        if (normS == normR || normR.contains(normS) || normS.contains(normR)) {
          return rMap;
        }

        final lowerS = rawSName.toLowerCase().trim();
        final lowerR = rawRName.toLowerCase().trim();
        if (lowerS == lowerR || lowerR.contains(lowerS) || lowerS.contains(lowerR)) {
          return rMap;
        }
      }
    }
    return null;
  }

  String _normalizeName(String val) {
    return val
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  // When exam selection toggles
  void _onExamToggled(Map<String, dynamic> exam, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedExamIds.add(exam['id']);
        _selectedExamsToInclude.add(exam);
      } else {
        _selectedExamIds.remove(exam['id']);
        _selectedExamsToInclude.removeWhere((e) => e['id'] == exam['id']);
      }
      _rebuildPdfExamsData();
    });
  }

  void _rebuildPdfExamsData() {
    if (_selectedStudent == null) return;
    final List<Map<String, dynamic>> temp = [];

    for (var exam in _selectedExamsToInclude) {
      final resJson = exam['resultsJson'] as String? ?? '';
      bool foundStudent = false;
      if (resJson.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(resJson);
          final studentRow = _findStudentInExamResults(decoded, _selectedStudent!['id']);
          if (studentRow != null) {
            foundStudent = true;
            final Map<String, double> subjectNets = {};
            if (studentRow['subjects'] != null && studentRow['subjects'] is Map) {
              (studentRow['subjects'] as Map).forEach((k, v) {
                if (v is Map) {
                  subjectNets[k.toString()] = num.tryParse(v['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
                }
              });
            }
            
            double totalNet = num.tryParse(studentRow['totalNet']?.toString() ?? '0')?.toDouble() ?? 0.0;
            if (totalNet == 0.0 && subjectNets.isNotEmpty) {
              totalNet = subjectNets.values.fold(0.0, (sum, item) => sum + item);
            }

            temp.add({
              'examName': exam['name'],
              'examTypeId': exam['examTypeId'] ?? '',
              'rankGeneral': studentRow['rankGeneral'] ?? studentRow['rank'] ?? '-',
              'rankBranch': studentRow['rankBranch'] ?? '-',
              'totalScore': studentRow['score'] ?? studentRow['totalScore'] ?? 0.0,
              'totalNet': totalNet,
              'subjectNets': subjectNets,
            });
          }
        } catch (_) {}
      }
      
      if (!foundStudent) {
        temp.add({
          'examName': exam['name'],
          'examTypeId': exam['examTypeId'] ?? '',
          'didNotParticipate': true,
          'rankGeneral': '-',
          'rankBranch': '-',
          'totalScore': 0.0,
          'totalNet': 0.0,
          'subjectNets': <String, double>{},
        });
      }
    }

    _calculateStudentTopicAnalysis(); // Recalculate dynamic topic analysis!

    setState(() {
      _pdfSelectedExamsData = temp;
    });
  }

  void _calculateStudentTopicAnalysis() {
    if (_selectedStudent == null) return;
    final String studentId = _selectedStudent!['id'].toString();

    print('--- _calculateStudentTopicAnalysis START for studentId: $studentId ---');

    // 1. If study program is selected, load its saved topicAnalysis
    if (_selectedStudyProgramId != null) {
      final selectedProg = _allStudyPrograms.firstWhere(
        (p) => p['id'] == _selectedStudyProgramId,
        orElse: () => <String, dynamic>{},
      );
      final list = selectedProg['topicAnalysis'] ?? [];
      if (list is List && list.isNotEmpty) {
        final List<Map<String, dynamic>> cleanList = [];
        for (var item in list) {
          if (item is Map) {
            cleanList.add(Map<String, dynamic>.from(item));
          } else if (item is String) {
            try {
              final decoded = jsonDecode(item);
              if (decoded is Map) {
                cleanList.add(Map<String, dynamic>.from(decoded));
              }
            } catch (_) {}
          }
        }
        if (cleanList.isNotEmpty) {
          _studentTopicAnalysis = cleanList;

          // Ensure thresholds exist
          final Set<String> uniqueSubjects = {};
          for (var item in _studentTopicAnalysis) {
            final sub = item['dersAdi']?.toString() ?? item['ders']?.toString() ?? item['subject']?.toString() ?? '';
            if (sub.isNotEmpty) uniqueSubjects.add(sub);
          }
          final int genelVal = _topicAnalysisThresholds['Genel'] ?? 70;
          final Map<String, int> updatedThresholds = Map<String, int>.from(_topicAnalysisThresholds);
          for (var sub in uniqueSubjects) {
            if (!updatedThresholds.containsKey(sub)) {
              updatedThresholds[sub] = genelVal;
            }
          }
          _topicAnalysisThresholds = updatedThresholds;

          print('Loaded _studentTopicAnalysis from selected study program: ${_studentTopicAnalysis.length} items');
          return;
        }
      }
    }

    // 2. Otherwise fallback to calculating dynamically from selected exams
    // Map<Subject, Map<Topic, Map<Metric, Val>>>
    final Map<String, Map<String, Map<String, double>>> allSubjectStats = {};

    for (var exam in _selectedExamsToInclude) {
      final resJson = exam['resultsJson'] as String? ?? '';
      if (resJson.isEmpty) {
        print('Exam ${exam['name']} has empty resultsJson');
        continue;
      }

      try {
        final List<dynamic> decoded = jsonDecode(resJson);
        final studentRow = _findStudentInExamResults(decoded, studentId);
        if (studentRow == null) {
          print('Student not found in results for exam: ${exam['name']}');
          continue;
        }

        print('Student found in results for exam: ${exam['name']}!');
        
        var outcomes = exam['outcomes'];
        var answerKeys = exam['answerKeys'];
        var studentAnswers = studentRow['answers'] ?? studentRow['studentAnswers'] ?? studentRow['cevaplar'];

        if (outcomes is String && outcomes.isNotEmpty) {
          try { outcomes = jsonDecode(outcomes); } catch (_) {}
        }
        if (answerKeys is String && answerKeys.isNotEmpty) {
          try { answerKeys = jsonDecode(answerKeys); } catch (_) {}
        }
        if (studentAnswers is String && studentAnswers.isNotEmpty) {
          try { studentAnswers = jsonDecode(studentAnswers); } catch (_) {}
        }

        print('  - outcomes type: ${outcomes?.runtimeType}');
        print('  - answerKeys type: ${answerKeys?.runtimeType}');
        print('  - studentAnswers type: ${studentAnswers?.runtimeType}');

        final Map<String, dynamic> outcomesMapRaw = outcomes is Map ? Map<String, dynamic>.from(outcomes) : {};
        final Map<String, dynamic> answerKeysMapRaw = answerKeys is Map ? Map<String, dynamic>.from(answerKeys) : {};
        final Map<String, dynamic> studentAnswersMap = studentAnswers is Map ? Map<String, dynamic>.from(studentAnswers) : {};

        var booklet = studentRow['booklet']?.toString() ?? 'A';
        var outcomesMap = outcomesMapRaw[booklet];
        var answerKeysMap = answerKeysMapRaw[booklet];

        // Fallback logic for booklets
        if (outcomesMap == null && outcomesMapRaw.isNotEmpty) {
          outcomesMap = outcomesMapRaw['A'] ?? outcomesMapRaw.values.first;
          booklet = outcomesMapRaw.keys.firstWhere(
            (k) => outcomesMapRaw[k] == outcomesMap,
            orElse: () => 'A',
          );
          answerKeysMap = answerKeysMapRaw[booklet];
        }
        if (answerKeysMap == null && answerKeysMapRaw.isNotEmpty) {
          answerKeysMap = answerKeysMapRaw['A'] ?? answerKeysMapRaw.values.first;
        }

        if (outcomesMap is! Map || answerKeysMap is! Map) {
          print('  - outcomesMap or answerKeysMap is not Map');
          continue;
        }

        final Map<String, dynamic> cleanOutcomesMap = Map<String, dynamic>.from(outcomesMap);
        final Map<String, dynamic> cleanAnswerKeysMap = Map<String, dynamic>.from(answerKeysMap);

        cleanOutcomesMap.forEach((subject, outcomeList) {
          if (outcomeList is! List) return;

          final String subjectStr = subject.toString().trim();
          String? validSubjectKey;

          if (cleanAnswerKeysMap.containsKey(subjectStr)) {
            validSubjectKey = subjectStr;
          } else {
            validSubjectKey = cleanAnswerKeysMap.keys.firstWhere(
              (k) => _normalizeName(k.toString()) == _normalizeName(subjectStr) ||
                     _normalizeName(k.toString()).contains(_normalizeName(subjectStr)) ||
                     _normalizeName(subjectStr).contains(_normalizeName(k.toString())),
              orElse: () => '',
            );
          }

          if (validSubjectKey == null || validSubjectKey.isEmpty) {
            print('    - Subject key not found in answer keys: $subjectStr');
            return;
          }

          final correctKey = cleanAnswerKeysMap[validSubjectKey]?.toString() ?? '';
          
          String? validAnswerKey;
          if (studentAnswersMap.containsKey(validSubjectKey)) {
            validAnswerKey = validSubjectKey;
          } else {
            validAnswerKey = studentAnswersMap.keys.firstWhere(
              (k) => _normalizeName(k.toString()) == _normalizeName(validSubjectKey!) ||
                     _normalizeName(k.toString()).contains(_normalizeName(validSubjectKey!)) ||
                     _normalizeName(validSubjectKey!).contains(_normalizeName(k.toString())),
              orElse: () => '',
            );
          }

          final studentAns = validAnswerKey.isNotEmpty ? (studentAnswersMap[validAnswerKey]?.toString() ?? '') : '';

          if (correctKey.isEmpty || studentAns.isEmpty) {
            print('    - correctKey or studentAns is empty for $subjectStr (correctKey: ${correctKey.isNotEmpty}, studentAns: ${studentAns.isNotEmpty})');
            return;
          }

          allSubjectStats.putIfAbsent(subjectStr, () => {});

          for (int i = 0; i < outcomeList.length; i++) {
            if (i >= correctKey.length || i >= studentAns.length) break;

            final topic = outcomeList[i]?.toString() ?? 'Diğer';

            allSubjectStats[subjectStr]!.putIfAbsent(
              topic,
              () => {'correct': 0.0, 'wrong': 0.0, 'empty': 0.0},
            );

            final c = correctKey[i].toUpperCase();
            final s = studentAns[i].toUpperCase();

            if (s == c) {
              allSubjectStats[subjectStr]![topic]!['correct'] =
                  allSubjectStats[subjectStr]![topic]!['correct']! + 1.0;
            } else if (s == ' ' || s.isEmpty || s == '#') {
              allSubjectStats[subjectStr]![topic]!['empty'] =
                  allSubjectStats[subjectStr]![topic]!['empty']! + 1.0;
            } else {
              allSubjectStats[subjectStr]![topic]!['wrong'] =
                  allSubjectStats[subjectStr]![topic]!['wrong']! + 1.0;
            }
          }
        });
      } catch (e) {
        print('Error calculating topic analysis for exam ${exam['id']}: $e');
      }
    }

    final List<Map<String, dynamic>> calculatedTopics = [];
    allSubjectStats.forEach((subject, topicsMap) {
      topicsMap.forEach((topic, stats) {
        final double corr = stats['correct']!;
        final double wrng = stats['wrong']!;
        final double empty = stats['empty']!;
        final double total = corr + wrng + empty;
        final int successRate = total > 0 ? ((corr / total) * 100).round() : 0;

        calculatedTopics.add({
          'dersAdi': subject,
          'konu': topic,
          'basariYuzdesi': successRate,
        });
      });
    });

    print('--- _calculateStudentTopicAnalysis END: calculated ${calculatedTopics.length} topics ---');

    // Ensure thresholds exist for all unique subjects
    final Set<String> uniqueSubjects = {};
    for (var item in calculatedTopics) {
      final sub = item['dersAdi']?.toString() ?? '';
      if (sub.isNotEmpty) uniqueSubjects.add(sub);
    }

    final int genelVal = _topicAnalysisThresholds['Genel'] ?? 70;
    final Map<String, int> updatedThresholds = Map<String, int>.from(_topicAnalysisThresholds);
    for (var sub in uniqueSubjects) {
      if (!updatedThresholds.containsKey(sub)) {
        updatedThresholds[sub] = genelVal;
      }
    }
    if (!updatedThresholds.containsKey('Genel')) {
      updatedThresholds['Genel'] = genelVal;
    }

    _studentTopicAnalysis = calculatedTopics;
    _topicAnalysisThresholds = updatedThresholds;
  }


  void _showThresholdsSliderDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final Set<String> uniqueSubjects = {};
        for (var item in _studentTopicAnalysis) {
          if (item is Map) {
            final sub = item['dersAdi']?.toString() ?? item['ders']?.toString() ?? item['subject']?.toString() ?? '';
            if (sub.isNotEmpty) uniqueSubjects.add(sub);
          }
        }
        final sortedSubjects = uniqueSubjects.toList()..sort();

        return StatefulBuilder(
          builder: (context, dialogSetState) {
            final int genelVal = _topicAnalysisThresholds['Genel'] ?? 70;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: EdgeInsets.zero,
              contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              title: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade900,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tune, color: Colors.white),
                    const SizedBox(width: 12),
                    const Text(
                      'Hedef Başarı Oranları',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Global threshold card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Genel Hedef (Varsayılan)',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade900, fontSize: 13),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade900,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '%$genelVal',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Slider(
                              value: genelVal.toDouble(),
                              min: 0,
                              max: 100,
                              divisions: 20,
                              activeColor: Colors.indigo,
                              inactiveColor: Colors.indigo.shade100,
                              onChanged: (val) {
                                dialogSetState(() {
                                  _topicAnalysisThresholds['Genel'] = val.round();
                                });
                                setState(() {}); // update dashboard state for live PDF rebuild
                              },
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  dialogSetState(() {
                                    for (var sub in sortedSubjects) {
                                      _topicAnalysisThresholds[sub] = genelVal;
                                    }
                                  });
                                  setState(() {});
                                },
                                icon: const Icon(Icons.copy_all, size: 14),
                                label: const Text('Tüm Derslere Uygula', style: TextStyle(fontSize: 11)),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: Colors.indigo.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (sortedSubjects.isNotEmpty) ...[
                        const Text(
                          'Ders Bazlı Başarı Hedefleri',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        ...sortedSubjects.map((sub) {
                          final int subVal = _topicAnalysisThresholds[sub] ?? genelVal;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      sub,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                                    ),
                                    Text(
                                      '%$subVal',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: subVal.toDouble(),
                                  min: 0,
                                  max: 100,
                                  divisions: 20,
                                  activeColor: Colors.blueAccent,
                                  inactiveColor: Colors.blue.shade50,
                                  onChanged: (val) {
                                    dialogSetState(() {
                                      _topicAnalysisThresholds[sub] = val.round();
                                    });
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ] else ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'Bu çalışma programında ders analizi verisi bulunmamaktadır.',
                              style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tamam', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWeekSliderSelector() {
    final start = _selectedLessonPlanWeekStart;
    final end = start.add(const Duration(days: 6));
    final format = DateFormat('dd.MM.yyyy');
    final rangeStr = '${format.format(start)} - ${format.format(end)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _selectedLessonPlanWeekStart = _selectedLessonPlanWeekStart.subtract(const Duration(days: 7));
              });
              final studentData = (_selectedStudent?['rawData'] is Map)
                  ? Map<String, dynamic>.from(_selectedStudent!['rawData'] as Map)
                  : <String, dynamic>{};
              final classId = studentData['classId']?.toString() ?? '';
              _fetchLessonPlans(classId);
            },
            icon: const Icon(Icons.chevron_left, color: Colors.indigo),
            tooltip: 'Önceki Hafta',
          ),
          Expanded(
            child: Center(
              child: Text(
                rangeStr,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade900,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _selectedLessonPlanWeekStart = _selectedLessonPlanWeekStart.add(const Duration(days: 7));
              });
              final studentData = (_selectedStudent?['rawData'] is Map)
                  ? Map<String, dynamic>.from(_selectedStudent!['rawData'] as Map)
                  : <String, dynamic>{};
              final classId = studentData['classId']?.toString() ?? '';
              _fetchLessonPlans(classId);
            },
            icon: const Icon(Icons.chevron_right, color: Colors.indigo),
            tooltip: 'Sonraki Hafta',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text(
          'Veli Bilgilendirme Raporları',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo.shade900,
        centerTitle: true,
        leading: const BackButton(color: Colors.white),
        elevation: 0,
        actions: _selectedStudent == null
            ? null
            : [
                if (_isGeneratingPdf)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.print, color: Colors.white),
                    tooltip: 'Yazdır',
                    onPressed: _printCurrentReport,
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.white),
                    tooltip: 'Paylaş',
                    onPressed: _shareCurrentReport,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
          : LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 1000;
                if (isMobile) {
                  return _buildMobileLayout();
                }
                return _buildDesktopLayout();
              },
            ),
    );
  }

  // Desktop Side-by-Side View
  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left Column: Configuration Controls
        Container(
          width: 480,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            children: [
              _buildStudentSelectionHeader(),
              Expanded(
                child: _selectedStudent == null
                    ? _buildStudentSelectorList()
                    : _isDetailLoading
                        ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
                        : _buildConfigurationPanel(),
              ),
            ],
          ),
        ),

        // Right Column: Live PDF Preview
        Expanded(
          child: Container(
            color: const Color(0xFFEBEFF5),
            child: _selectedStudent == null
                ? _buildEmptyState()
                : _isDetailLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
                    : _buildPdfPreviewer(),
          ),
        ),
      ],
    );
  }

  // Mobile Sequential/Tabbed View
  Widget _buildMobileLayout() {
    if (_selectedStudent == null) {
      return Column(
        children: [
          _buildStudentSelectionHeader(),
          Expanded(child: _buildStudentSelectorList()),
        ],
      );
    }

    if (_isDetailLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.indigo));
    }

    return DefaultTabController(
      key: ValueKey('tab_ctrl_${_selectedStudent!['id']}'),
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              labelColor: Colors.indigo.shade900,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.indigo.shade900,
              tabs: const [
                Tab(icon: Icon(Icons.settings), text: 'Rapor Yapılandır'),
                Tab(icon: Icon(Icons.picture_as_pdf), text: 'Rapor Önizle'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildConfigurationPanel(),
                Container(color: const Color(0xFFEBEFF5), child: _buildPdfPreviewer()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Student Selection Panel Header
  Widget _buildStudentSelectionHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedStudent != null)
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedStudent = null;
                    });
                  },
                  icon: const Icon(Icons.arrow_back, color: Colors.indigo),
                  tooltip: 'Öğrenci Değiştir',
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedStudent!['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${_selectedStudent!['class']} • Sınıf Numarası: ${_selectedStudent!['studentNo']}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Öğrenci Seçimi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                ),
                if (_selectedStudentIds.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedStudentIds.clear();
                      });
                    },
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Seçimleri Temizle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Class filter
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedClassFilter,
                        hint: const Text('Şube Seç', style: TextStyle(fontSize: 13)),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Tüm Şubeler', style: TextStyle(fontSize: 13)),
                          ),
                          ..._classLevels.map((c) {
                            return DropdownMenuItem<String>(
                              value: c,
                              child: Text(c, style: const TextStyle(fontSize: 13)),
                            );
                          }).toList(),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedClassFilter = val;
                            _filterStudents();
                          });
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Search field
                Expanded(
                  flex: 3,
                  child: TextField(
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _filterStudents();
                      });
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Ara...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_filteredStudents.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _filteredStudents.every((s) => _selectedStudentIds.contains(s['id'])),
                          activeColor: Colors.indigo,
                          tristate: true,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                for (var s in _filteredStudents) {
                                  _selectedStudentIds.add(s['id']);
                                }
                              } else {
                                for (var s in _filteredStudents) {
                                  _selectedStudentIds.remove(s['id']);
                                }
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Tümünü Seç (${_filteredStudents.length} Öğrenci)',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87),
                      ),
                    ],
                  ),
                  if (_selectedStudentIds.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.indigo.shade100),
                      ),
                      child: Text(
                        '${_selectedStudentIds.length} Seçili',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  // Left panel student selector list
  Widget _buildStudentSelectorList() {
    if (_filteredStudents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('Öğrenci bulunamadı.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _filteredStudents.length,
      padding: const EdgeInsets.all(12),
      itemBuilder: (context, index) {
        final s = _filteredStudents[index];
        final isChecked = _selectedStudentIds.contains(s['id']);
        return Card(
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: isChecked,
                  activeColor: Colors.indigo,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedStudentIds.add(s['id']);
                      } else {
                        _selectedStudentIds.remove(s['id']);
                      }
                    });
                  },
                ),
                CircleAvatar(
                  backgroundColor: Colors.indigo.shade50,
                  radius: 16,
                  child: Text(
                    s['name'][0],
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade900, fontSize: 12),
                  ),
                ),
              ],
            ),
            title: Text(
              s['name'],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text('Sınıf: ${s['class']} • No: ${s['studentNo']}'),
            trailing: Icon(Icons.chevron_right, color: Colors.indigo.shade400),
            onTap: () {
              setState(() {
                _selectedStudentIds.add(s['id']);
                _selectedStudent = s;
                
                // Seçilenler içindeki index'ini bulalım
                final selectedList = _selectedStudentsList;
                _currentStudentIndex = selectedList.indexWhere((element) => element['id'] == s['id']);
                if (_currentStudentIndex == -1) _currentStudentIndex = 0;
              });
              _loadStudentSpecificDetails(s['id']);
            },
          ),
        );
      },
    );
  }

  // Left panel configuration details
  Widget _buildConfigurationPanel() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ─── 1. VELİ MEKTUBU YAZISI ───
        _buildSectionHeader('1. Veli Mektubu Gövdesi', Icons.edit_note_rounded),
        const SizedBox(height: 8),
        TextField(
          controller: _letterController,
          maxLines: 6,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Velimize iletilecek kişiye özel veya genel mesajınızı girin...',
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ─── 2. DENEME SINAVLARI DAHİL ETME ───
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('2. Deneme Sınavları', Icons.analytics_outlined),
            Switch.adaptive(
              value: _includeExams,
              onChanged: (val) => setState(() => _includeExams = val),
              activeColor: Colors.indigo,
            ),
          ],
        ),
        if (_includeExams) ...[
          const SizedBox(height: 8),
          if (_allExams.isEmpty)
            const Text('Kuruma tanımlı deneme sınavı bulunmamaktadır.',
                style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade50,
              ),
              child: Scrollbar(
                controller: _examsScrollController,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _examsScrollController,
                  shrinkWrap: false,
                  itemCount: _allExams.length,
                  itemBuilder: (context, idx) {
                    final exam = _allExams[idx];
                    final isChecked = _selectedExamIds.contains(exam['id']);
                    return CheckboxListTile(
                      title: Text(exam['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Text(DateFormat('dd.MM.yyyy').format(exam['date']), style: const TextStyle(fontSize: 11)),
                      value: isChecked,
                      onChanged: (val) {
                        if (val != null) _onExamToggled(exam, val);
                      },
                      activeColor: Colors.indigo,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
            ),
        ],
        const SizedBox(height: 24),

        // ─── 3. AKADEMİK GÜÇLENDİRME (AGM) DAHİL ETME ───
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('3. Akademik Güçlendirme (AGM)', Icons.auto_awesome_rounded),
            Switch.adaptive(
              value: _includeAgm,
              onChanged: (val) => setState(() => _includeAgm = val),
              activeColor: Colors.indigo,
            ),
          ],
        ),
        if (_includeAgm) ...[
          const SizedBox(height: 8),
          if (_allAgmCycles.isEmpty)
            const Text('Kuruma tanımlı AGM programı bulunmamaktadır.',
                style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade50,
              ),
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _allAgmCycles.length,
                  itemBuilder: (context, idx) {
                    final cycle = _allAgmCycles[idx];
                    final isChecked = _selectedAgmCycleIds.contains(cycle['id']);
                    return CheckboxListTile(
                      title: Text(cycle['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      value: isChecked,
                      onChanged: (val) async {
                        if (val != null && _selectedStudent != null) {
                          setState(() {
                            if (val) {
                              _selectedAgmCycleIds.add(cycle['id']);
                            } else {
                              _selectedAgmCycleIds.remove(cycle['id']);
                            }
                          });
                          await _fetchAgmAssignments(_selectedStudent!['id'], _selectedAgmCycleIds);
                          setState(() {}); // Rebuild PDF preview
                        }
                      },
                      activeColor: Colors.indigo,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 8),
          // AGM sütun görünürlük toggle'ları
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildColumnToggleChip('Branş', _agmShowBranch, (v) => setState(() => _agmShowBranch = v)),
              _buildColumnToggleChip('Öğretmen', _agmShowTeacher, (v) => setState(() => _agmShowTeacher = v)),
              _buildColumnToggleChip('Ana Kazanım', _agmShowKazanim, (v) => setState(() => _agmShowKazanim = v)),
              _buildColumnToggleChip('Durum', _agmShowDurum, (v) => setState(() => _agmShowDurum = v)),
            ],
          ),
        ],
        const SizedBox(height: 24),

        // ─── 4. KAMP PROGRAMI DAHİL ETME ───
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('4. Kamp Programı', Icons.campaign_rounded),
            Switch.adaptive(
              value: _includeCamp,
              onChanged: (val) => setState(() => _includeCamp = val),
              activeColor: Colors.indigo,
            ),
          ],
        ),
        if (_includeCamp) ...[
          const SizedBox(height: 8),
          if (_allCampCycles.isEmpty)
            const Text('Kuruma tanımlı Kamp programı bulunmamaktadır.',
                style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade50,
              ),
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _allCampCycles.length,
                  itemBuilder: (context, idx) {
                    final cycle = _allCampCycles[idx];
                    final isChecked = _selectedCampCycleIds.contains(cycle['id']);
                    return CheckboxListTile(
                      title: Text(cycle['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      value: isChecked,
                      onChanged: (val) async {
                        if (val != null && _selectedStudent != null) {
                          setState(() {
                            if (val) {
                              _selectedCampCycleIds.add(cycle['id']);
                            } else {
                              _selectedCampCycleIds.remove(cycle['id']);
                            }
                          });
                          await _fetchCampAssignments(_selectedStudent!['id'], _selectedCampCycleIds);
                          setState(() {}); // Rebuild PDF preview
                        }
                      },
                      activeColor: Colors.indigo,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Kamp sütun görünürlük toggle'ları
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildColumnToggleChip('Branş', _campShowBranch, (v) => setState(() => _campShowBranch = v)),
              _buildColumnToggleChip('Öğretmen', _campShowTeacher, (v) => setState(() => _campShowTeacher = v)),
              _buildColumnToggleChip('Ana Kazanım', _campShowKazanim, (v) => setState(() => _campShowKazanim = v)),
              _buildColumnToggleChip('Durum', _campShowDurum, (v) => setState(() => _campShowDurum = v)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Hariç Tutulanları "Katılmadı" Olarak Göster', style: TextStyle(fontSize: 12, color: Colors.black87)),
              Switch.adaptive(
                value: _campShowExcludedAsNotParticipated,
                onChanged: (val) {
                  setState(() => _campShowExcludedAsNotParticipated = val);
                  if (_selectedStudent != null) {
                    _fetchCampAssignments(_selectedStudent!['id'], _selectedCampCycleIds).then((_) => setState(() {}));
                  }
                },
                activeColor: Colors.indigo,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Sınava Girmeyenleri "Katılmadı" Olarak Göster', style: TextStyle(fontSize: 12, color: Colors.black87)),
              Switch.adaptive(
                value: _campShowAbsentAsNotParticipated,
                onChanged: (val) {
                  setState(() => _campShowAbsentAsNotParticipated = val);
                  if (_selectedStudent != null) {
                    _fetchCampAssignments(_selectedStudent!['id'], _selectedCampCycleIds).then((_) => setState(() {}));
                  }
                },
                activeColor: Colors.indigo,
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),

        // ─── 5. GÜÇLENDİRME PROGRAMLARI DAHİL ETME ───
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('5. Çalışma / Güçlendirme Planı', Icons.trending_up_rounded),
            Switch.adaptive(
              value: _includeStudyPrograms,
              onChanged: (val) => setState(() => _includeStudyPrograms = val),
              activeColor: Colors.indigo,
            ),
          ],
        ),
        if (_includeStudyPrograms) ...[
          const SizedBox(height: 8),
          if (_allStudyPrograms.isEmpty)
            const Text('Öğrenciye ait çalışma programı bulunmamaktadır.',
                style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedStudyProgramId,
                  hint: const Text('Çalışma Programı Seçin', style: TextStyle(fontSize: 13)),
                  isExpanded: true,
                  items: _allStudyPrograms.map((prog) {
                    return DropdownMenuItem<String>(
                      value: prog['id'],
                      child: Text(
                        '${prog['title']} (${prog['createdAtLabel']})',
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      final selectedProg = _allStudyPrograms.firstWhere((p) => p['id'] == val);
                      setState(() {
                        _selectedStudyProgramId = val;
                        _pdfStudyPrograms = [selectedProg];
                        
                        final Map<String, int> thresh = {};
                        final rawThresholds = selectedProg['thresholds'] ?? {};
                        rawThresholds.forEach((k, v) {
                          thresh[k.toString()] = int.tryParse(v.toString()) ?? 70;
                        });
                        _topicAnalysisThresholds = thresh;
                        
                        _calculateStudentTopicAnalysis(); // Dynamically recalculate!
                      });
                    }
                  },
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Kazanım listesi kaldırıldı
          const SizedBox(height: 24),

          // ─── 6. KONU ANALİZİ (ÇALIŞMASI/PEKİŞTİRİLMESİ GEREKENLER) DAHİL ETME ───
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionHeader('6. Konu Analizi', Icons.radar_rounded),
              Switch.adaptive(
                value: _includeTopicAnalysis,
                onChanged: (val) => setState(() => _includeTopicAnalysis = val),
                activeColor: Colors.indigo,
              ),
            ],
          ),
          if (_includeTopicAnalysis) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Öncelikli Konuları Göster', style: TextStyle(fontSize: 12)),
                Switch.adaptive(
                  value: _topicAnalysisShowPriority,
                  onChanged: (val) => setState(() => _topicAnalysisShowPriority = val),
                  activeColor: Colors.indigo,
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Pekiştirilecek Konuları Göster', style: TextStyle(fontSize: 12)),
                Switch.adaptive(
                  value: _topicAnalysisShowReinforcement,
                  onChanged: (val) => setState(() => _topicAnalysisShowReinforcement = val),
                  activeColor: Colors.indigo,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _showThresholdsSliderDialog,
                icon: const Icon(Icons.settings_input_component, size: 14),
                label: const Text('Başarı Hedeflerini Ayarla', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.indigo.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  backgroundColor: Colors.indigo.shade50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // ─── 7. HAFTALIK DERS PLANLARI DAHİL ETME ───
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionHeader('7. Haftalık Ders Planları', Icons.calendar_today_rounded),
              Switch.adaptive(
                value: _includeLessonPlans,
                onChanged: (val) => setState(() => _includeLessonPlans = val),
                activeColor: Colors.indigo,
              ),
            ],
          ),
          if (_includeLessonPlans) ...[
            const SizedBox(height: 8),
            _buildWeekSliderSelector(),
            const SizedBox(height: 8),
            if (_pdfLessonPlans.isEmpty)
              const Text(
                'Seçilen haftada bu sınıfın girilmiş ders planı bulunmamaktadır.',
                style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic),
              )
            else
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: _pdfLessonPlans.take(3).map<Widget>((plan) {
                    final String dateStr = DateFormat('dd.MM.yyyy').format(plan['date'] as DateTime);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${plan['lessonName']} (${plan['title']})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '$dateStr • Kazanım: ${plan['outcome']}',
                        style: const TextStyle(fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList()..addAll(
                    _pdfLessonPlans.length > 3
                        ? [
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '...ve ${_pdfLessonPlans.length - 3} ders planı daha.',
                                style: const TextStyle(color: Colors.indigo, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            )
                          ]
                        : [],
                  ),
                ),
              ),
          ],
        ],
        const SizedBox(height: 24),

        // ─── 8. ALT BİLGİ (FOOTER) ───
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('8. Alt Bilgi (Footer)', Icons.branding_watermark_outlined),
            Switch.adaptive(
              value: _includeFooter,
              onChanged: (val) => setState(() => _includeFooter = val),
              activeColor: Colors.indigo,
            ),
          ],
        ),
        if (_includeFooter) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 28.0),
            child: Column(
              children: [
                const SizedBox(height: 8),
                TextField(
                  controller: TextEditingController(text: _footerSlogan)..selection = TextSelection.collapsed(offset: _footerSlogan.length),
                  onChanged: (val) {
                    _footerSlogan = val;
                    setState(() {});
                  },
                  decoration: const InputDecoration(
                    labelText: 'Slogan (Sadece son sayfada gösterilir)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Sınıf Öğretmeni İsmi', style: TextStyle(fontSize: 12, color: Colors.black87)),
                    Switch.adaptive(
                      value: _footerShowTeacher,
                      onChanged: (val) => setState(() => _footerShowTeacher = val),
                      activeColor: Colors.indigo,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Sayfa Numarası', style: TextStyle(fontSize: 12, color: Colors.black87)),
                    Switch.adaptive(
                      value: _footerShowPageNumber,
                      onChanged: (val) => setState(() => _footerShowPageNumber = val),
                      activeColor: Colors.indigo,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Kurum Yöneticisi İsmi', style: TextStyle(fontSize: 12, color: Colors.black87)),
                    Switch.adaptive(
                      value: _footerShowPrincipal,
                      onChanged: (val) => setState(() => _footerShowPrincipal = val),
                      activeColor: Colors.indigo,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.indigo.shade800),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildColumnToggleChip(String label, bool active, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 11, color: active ? Colors.white : Colors.grey.shade700)),
      selected: active,
      onSelected: onChanged,
      selectedColor: Colors.indigo.shade600,
      backgroundColor: Colors.grey.shade100,
      checkmarkColor: Colors.white,
      side: BorderSide(color: active ? Colors.indigo.shade400 : Colors.grey.shade300),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      visualDensity: VisualDensity.compact,
    );
  }

  // Right side panel previewer
  Widget _buildPdfPreviewer() {
    if (_selectedStudent == null) return _buildEmptyState();

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) return;
              if (details.primaryVelocity! < -200) {
                // Swiped left -> Next student
                _navigateToStudent(_currentStudentIndex + 1);
              } else if (details.primaryVelocity! > 200) {
                // Swiped right -> Previous student
                _navigateToStudent(_currentStudentIndex - 1);
              }
            },
            child: PdfPreview(
              key: ValueKey(
                'pdf_preview_${_selectedStudent!['id']}_'
                '${_includeExams}_${_includeAgm}_${_includeCamp}_${_includeStudyPrograms}_'
                '${_includeFooter}_${_footerShowTeacher}_${_footerShowPageNumber}_${_footerShowPrincipal}_'
                '${_pdfSelectedExamsData.length}_${_pdfAgmAssignments.length}_'
                '${_pdfCampAssignments.length}_${_pdfStudyPrograms.length}'
              ),
              build: (format) => ParentReportPdfHelper.generateReport(
                studentName: _selectedStudent!['name'],
                studentClass: _selectedStudent!['class'],
                studentNo: _selectedStudent!['studentNo'],
                letterContent: _letterController.text,
                selectedExams: _pdfSelectedExamsData,
                agmAssignments: _pdfAgmAssignments,
                campAssignments: _pdfCampAssignments,
                studyPrograms: _pdfStudyPrograms,
                includeExams: _includeExams,
                includeAgm: _includeAgm,
                includeCamp: _includeCamp,
                includeStudyPrograms: _includeStudyPrograms,
                lessonAbbreviations: _lessonAbbreviations,
                examTypeSubjectOrders: _examTypeSubjectOrders,
                classTeacherName: _classTeacherName,
                principalName: _principalName,
                // AGM sütun görünürlükleri
                agmShowBranch: _agmShowBranch,
                agmShowTeacher: _agmShowTeacher,
                agmShowKazanim: _agmShowKazanim,
                agmShowDurum: _agmShowDurum,
                // Kamp sütun görünürlükleri
                campShowBranch: _campShowBranch,
                campShowTeacher: _campShowTeacher,
                campShowKazanim: _campShowKazanim,
                campShowDurum: _campShowDurum,
                // Kazanım listesi
                includeKazanimList: _includeKazanimList,
                // 6. alan Konu Analizi
                includeTopicAnalysis: _includeTopicAnalysis,
                topicAnalysisThresholds: _topicAnalysisThresholds,
                studentTopicAnalysis: _studentTopicAnalysis,
                topicAnalysisShowPriority: _topicAnalysisShowPriority,
                topicAnalysisShowReinforcement: _topicAnalysisShowReinforcement,
                // 7. alan Haftalık Ders Planları
                includeLessonPlans: _includeLessonPlans,
                lessonPlans: _pdfLessonPlans,
                // 8. alan Alt Bilgi (Footer)
                includeFooter: _includeFooter,
                footerShowTeacher: _footerShowTeacher,
                footerShowPageNumber: _footerShowPageNumber,
                footerShowPrincipal: _footerShowPrincipal,
                footerSlogan: _footerSlogan,
              ),
              allowPrinting: false,
              allowSharing: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              loadingWidget: const Center(
                child: CircularProgressIndicator(color: Colors.indigo),
              ),
              pdfFileName: 'Veli_Bilgilendirme_${_selectedStudent!['name'].toString().replaceAll(' ', '_')}.pdf',
            ),
          ),
        ),
        _buildPaginationAndBulkActionsBar(),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_ind_rounded, size: 72, color: Colors.indigo.shade100),
          const SizedBox(height: 16),
          Text(
            'Lütfen Bir Öğrenci Seçin',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo.shade900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sol taraftaki listeden öğrenci seçerek veli raporu hazırlamaya başlayabilirsiniz.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationAndBulkActionsBar() {
    final list = _navigationStudentsList;
    if (list.isEmpty) return const SizedBox.shrink();
    
    // Ensure index is within range
    if (_currentStudentIndex < 0 || _currentStudentIndex >= list.length) {
      _currentStudentIndex = 0;
    }
    
    final currentStudentName = list[_currentStudentIndex]['name'] ?? 'Öğrenci';
    final totalCount = list.length;
    final displayIndex = _currentStudentIndex + 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Arrow & student navigation
          Expanded(
            child: Row(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _navigateToStudent(_currentStudentIndex - 1),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.indigo.shade900),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentStudentName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.indigo.shade900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Öğrenci $displayIndex / $totalCount',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _navigateToStudent(_currentStudentIndex + 1),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Colors.indigo.shade900),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Right: "Rapor İndir" Bulk Action Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo.shade900,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 2,
            ),
            onPressed: _showDownloadOptionsDialog,
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text(
              'Rapor İndir',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  void _showDownloadOptionsDialog() {
    if (_selectedStudent == null) return;
    
    // Default selections
    bool onlyActive = true;
    bool combinedPdf = true;
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedCount = _selectedStudentIds.isNotEmpty 
                ? _selectedStudentIds.length 
                : _filteredStudents.length;
            final isMultiSelectAvailable = selectedCount > 1;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.download_rounded, color: Colors.indigo.shade900),
                  const SizedBox(width: 8),
                  Text(
                    'Rapor İndirme Seçenekleri',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kapsam Seçimi',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<bool>(
                    title: const Text(
                      'Sadece Aktif Öğrenci',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      _selectedStudent!['name'],
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    value: true,
                    groupValue: onlyActive,
                    activeColor: Colors.indigo.shade900,
                    onChanged: (val) {
                      setDialogState(() {
                        onlyActive = val ?? true;
                      });
                    },
                  ),
                  RadioListTile<bool>(
                    title: const Text(
                      'Tüm Seçili Öğrenciler',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '$selectedCount Öğrenci',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    value: false,
                    groupValue: onlyActive,
                    activeColor: Colors.indigo.shade900,
                    onChanged: isMultiSelectAvailable 
                        ? (val) {
                            setDialogState(() {
                              onlyActive = val ?? false;
                            });
                          }
                        : null,
                  ),
                  const Divider(height: 24),
                  const Text(
                    'Dosya Formatı',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<bool>(
                    title: const Text('Tek Birleştirilmiş PDF', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Tüm sayfalar tek bir PDF belgesinde birleşir', style: TextStyle(fontSize: 12)),
                    value: true,
                    groupValue: combinedPdf,
                    activeColor: Colors.indigo.shade900,
                    onChanged: (val) {
                      setDialogState(() {
                        combinedPdf = val ?? true;
                      });
                    },
                  ),
                  RadioListTile<bool>(
                    title: const Text('Şube Gruplu ZIP Arşivi', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Her öğrenciye ayrı PDF üretilip şube klasöründe ZIP’lenir', style: TextStyle(fontSize: 12)),
                    value: false,
                    groupValue: combinedPdf,
                    activeColor: Colors.indigo.shade900,
                    onChanged: (val) {
                      setDialogState(() {
                        combinedPdf = val ?? false;
                      });
                    },
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'İptal',
                    style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade900,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _startBulkDownload(
                      onlyActive: onlyActive,
                      combinedPdf: combinedPdf,
                    );
                  },
                  child: const Text('İndirmeyi Başlat', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>> _fetchStudentPdfData(Map<String, dynamic> student) async {
    final studentId = student['id'];
    final studentData = (student['rawData'] is Map)
        ? Map<String, dynamic>.from(student['rawData'] as Map)
        : <String, dynamic>{};
    final classId = studentData['classId']?.toString() ?? '';
    final className = student['class']?.toString() ?? studentData['className']?.toString() ?? '';

    // Define parallel fetch groups
    Future<List<Map<String, dynamic>>> fetchStudyProgramsFuture() async {
      final studyProgramSnap = await _db
          .collection('institutions')
          .doc(widget.institutionId)
          .collection('study_programs')
          .where('studentId', isEqualTo: studentId)
          .orderBy('createdAt', descending: true)
          .get();

      return studyProgramSnap.docs.map((doc) {
        final data = doc.data();
        final createdVal = data['createdAt'];
        String formattedDate = '';
        if (createdVal is Timestamp) {
          final d = createdVal.toDate();
          formattedDate = '${d.day}.${d.month}.${d.year}';
        }
        return {
          'id': doc.id,
          'title': data['title'] ?? 'Bireysel Çalışma Programı',
          'description': data['description'] ?? '',
          'subjects': data['subjects'] ?? [],
          'schedule': (data['schedule'] is Map) ? Map<String, dynamic>.from(data['schedule'] as Map) : <String, dynamic>{},
          'executionStatus': (data['executionStatus'] is Map) ? Map<String, dynamic>.from(data['executionStatus'] as Map) : <String, dynamic>{},
          'createdAtLabel': formattedDate,
          'topicAnalysis': data['topicAnalysis'] ?? [],
          'thresholds': (data['thresholds'] is Map) ? Map<String, dynamic>.from(data['thresholds'] as Map) : <String, dynamic>{},
        };
      }).toList();
    }

    Future<List<Map<String, dynamic>>> fetchAgmAssignmentsFuture() async {
      if (_selectedAgmCycleIds.isEmpty) return [];
      
      final List<Map<String, dynamic>> tempAgm = [];
      try {
        final cycleFutures = _selectedAgmCycleIds.map((cycleId) async {
          final cycleMap = _allAgmCycles.firstWhere(
            (c) => c['id'] == cycleId,
            orElse: () => <String, dynamic>{},
          );
          final cycleName = cycleMap['name'] ?? 'AGM Dönemi';

          final assignSnap = await _db
              .collection('agm_assignments')
              .where('cycleId', isEqualTo: cycleId)
              .where('ogrenciId', isEqualTo: studentId)
              .get();

          if (assignSnap.docs.isEmpty) return <Map<String, dynamic>>[];

          final docFutures = assignSnap.docs.map((doc) async {
            final data = doc.data();
            final groupId = data['groupId']?.toString() ?? '';
            final isAbsent = data['isAbsent'] as bool? ?? false;

            if (groupId.isEmpty) return null;

            final groupDocFuture = _db.collection('agm_groups').doc(groupId).get();
            final etutSnapFuture = _db
                .collection('etut_requests')
                .where('agmCycleId', isEqualTo: cycleId)
                .where('agmGroupId', isEqualTo: groupId)
                .limit(1)
                .get();

            final groupResults = await Future.wait([groupDocFuture, etutSnapFuture]);
            final groupDoc = groupResults[0] as DocumentSnapshot<Map<String, dynamic>>;
            final etutSnap = groupResults[1] as QuerySnapshot<Map<String, dynamic>>;

            if (groupDoc.exists) {
              final gData = groupDoc.data() ?? {};
              final kazanimlar = gData['kazanimlar'];
              final List<String> kazanimList = (kazanimlar is List)
                  ? kazanimlar.map((e) => e.toString()).toList()
                  : [];
              final String anaKazanim = kazanimList.isNotEmpty ? kazanimList.first : '-';

              bool attended = !isAbsent;
              if (etutSnap.docs.isNotEmpty) {
                final etutData = etutSnap.docs.first.data();
                final attendanceMapRaw = etutData['attendance'];
                final attendanceMap = (attendanceMapRaw is Map)
                    ? Map<String, dynamic>.from(attendanceMapRaw)
                    : <String, dynamic>{};
                if (attendanceMap.containsKey(studentId)) {
                  attended = attendanceMap[studentId] == true;
                }
              }

              return {
                'cycleId': cycleId,
                'cycleName': cycleName,
                'dersAdi': gData['dersAdi'] ?? gData['ders'] ?? '-',
                'ogretmenAdi': gData['ogretmenAdi'] ?? gData['ogretmen'] ?? '-',
                'derslikAdi': gData['derslikAdi'] ?? gData['derslik'] ?? '-',
                'saatDilimi': gData['saatDilimiAdi'] ?? gData['saatDilimiId'] ?? '',
                'anaKazanim': anaKazanim,
                'kazanimList': kazanimList,
                'attended': attended,
              };
            }
            return null;
          }).toList();

          final docResults = await Future.wait(docFutures);
          return docResults.whereType<Map<String, dynamic>>().toList();
        }).toList();

        final cycleResults = await Future.wait(cycleFutures);
        for (var res in cycleResults) {
          tempAgm.addAll(res);
        }
      } catch (e) {
        print('Error fetching AGM for background student: $e');
      }
      return tempAgm;
    }

    Future<List<Map<String, dynamic>>> fetchCampAssignmentsFuture() async {
      if (_selectedCampCycleIds.isEmpty) return [];
      
      final List<Map<String, dynamic>> tempCamp = [];
      try {
        final cycleFutures = _selectedCampCycleIds.map((cycleId) async {
          final cycleMap = _allCampCycles.firstWhere(
            (c) => c['id'] == cycleId,
            orElse: () => <String, dynamic>{},
          );
          final cycleName = cycleMap['name'] ?? 'Kamp Dönemi';
          final excludedStudentIds = List<String>.from(cycleMap['excludedStudentIds'] ?? []);

          if (excludedStudentIds.contains(studentId)) {
            if (_campShowExcludedAsNotParticipated) {
              return [
                {
                  'cycleId': cycleId,
                  'cycleName': cycleName,
                  'isExcluded': true,
                  'dersAdi': '-',
                  'ogretmenAdi': '-',
                  'anaKazanim': '-',
                  'attended': false,
                }
              ];
            }
            return <Map<String, dynamic>>[];
          }

          final assignSnap = await _db
              .collection('camp_assignments')
              .where('cycleId', isEqualTo: cycleId)
              .where('ogrenciId', isEqualTo: studentId)
              .get();

          if (assignSnap.docs.isEmpty) {
            if (_campShowAbsentAsNotParticipated) {
              return [
                {
                  'cycleId': cycleId,
                  'cycleName': cycleName,
                  'isExcluded': true,
                  'dersAdi': '-',
                  'ogretmenAdi': '-',
                  'anaKazanim': '-',
                  'attended': false,
                }
              ];
            }
            return <Map<String, dynamic>>[];
          }

          final docFutures = assignSnap.docs.map((doc) async {
            final data = doc.data();
            final groupId = data['groupId'];
            final isAbsent = data['isAbsent'] as bool? ?? false;

            if (groupId == null || groupId.toString().isEmpty) {
              return null;
            }

            final groupDocFuture = _db.collection('camp_groups').doc(groupId).get();
            final etutSnapFuture = _db
                .collection('etut_requests')
                .where('campCycleId', isEqualTo: cycleId)
                .where('campGroupId', isEqualTo: groupId)
                .limit(1)
                .get();

            final groupResults = await Future.wait([groupDocFuture, etutSnapFuture]);
            final groupDoc = groupResults[0] as DocumentSnapshot<Map<String, dynamic>>;
            final etutSnap = groupResults[1] as QuerySnapshot<Map<String, dynamic>>;

            if (groupDoc.exists) {
              final gData = groupDoc.data() ?? {};
              final kazanimlar = gData['kazanimlar'] as List<dynamic>? ?? [];
              final String anaKazanim = kazanimlar.isNotEmpty ? kazanimlar.first.toString() : '-';

              bool attended = !isAbsent;
              if (etutSnap.docs.isNotEmpty) {
                final etutData = etutSnap.docs.first.data();
                final attendanceMapRaw = etutData['attendance'];
                final attendanceMap = (attendanceMapRaw is Map) ? Map<String, dynamic>.from(attendanceMapRaw) : <String, dynamic>{};
                if (attendanceMap.containsKey(studentId)) {
                  attended = attendanceMap[studentId] == true;
                }
              }

              return {
                'cycleId': cycleId,
                'cycleName': cycleName,
                'isExcluded': false,
                'dersAdi': gData['dersAdi'] ?? gData['ders'] ?? '-',
                'ogretmenAdi': gData['ogretmenAdi'] ?? gData['ogretmen'] ?? '-',
                'saatDilimi': gData['saatDilimiAdi'] ?? gData['saatDilimiId'] ?? '',
                'anaKazanim': anaKazanim,
                'attended': attended,
              };
            }
            return null;
          }).toList();

          final docResults = await Future.wait(docFutures);
          final validDocs = docResults.whereType<Map<String, dynamic>>().toList();

          if (validDocs.isEmpty && _campShowAbsentAsNotParticipated) {
            return [
              {
                'cycleId': cycleId,
                'cycleName': cycleName,
                'isExcluded': true,
                'dersAdi': '-',
                'ogretmenAdi': '-',
                'anaKazanim': '-',
                'attended': false,
              }
            ];
          }
          return validDocs;
        }).toList();

        final cycleResults = await Future.wait(cycleFutures);
        for (var res in cycleResults) {
          tempCamp.addAll(res);
        }
      } catch (e) {
        print('Error fetching Camp for background student: $e');
      }
      return tempCamp;
    }

    Future<String> fetchTeacherNameFuture() async {
      String teacherName = 'Belirtilmedi';
      if (classId.isNotEmpty) {
        final classDoc = await _db.collection('classes').doc(classId).get();
        if (classDoc.exists) {
          teacherName = classDoc.data()?['classTeacherName']?.toString() ?? 'Belirtilmedi';
        }
      }

      if (teacherName == 'Belirtilmedi' && className.isNotEmpty && className != 'Belirtilmedi') {
        final classQuery = await _db
            .collection('classes')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .where('className', isEqualTo: className)
            .where('isActive', isEqualTo: true)
            .get();
        if (classQuery.docs.isNotEmpty) {
          teacherName = classQuery.docs.first.data()['classTeacherName']?.toString() ?? 'Belirtilmedi';
        }
      }
      return teacherName;
    }

    Future<List<Map<String, dynamic>>> fetchLessonPlansFuture() async {
      List<Map<String, dynamic>> lessonPlans = [];
      if (_includeLessonPlans && classId.isNotEmpty) {
        try {
          final snap = await _db
              .collection('classLessonPlans')
              .where('institutionId', isEqualTo: widget.institutionId)
              .where('classId', isEqualTo: classId)
              .get();
              
          final startOfWeek = _selectedLessonPlanWeekStart;
          final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
          
          for (var doc in snap.docs) {
            final data = doc.data();
            final dateVal = data['date'];
            
            DateTime? dt;
            if (dateVal is Timestamp) {
              dt = dateVal.toDate();
            } else if (dateVal is String) {
              dt = DateTime.tryParse(dateVal);
            }
            
            if (dt != null) {
              if (dt.isAfter(startOfWeek.subtract(const Duration(seconds: 1))) && 
                  dt.isBefore(endOfWeek.add(const Duration(seconds: 1)))) {
                lessonPlans.add({
                  'id': doc.id,
                  'date': dateVal,
                  'lessonName': data['lessonName'] ?? '',
                  'topicName': data['topicName'] ?? '',
                  'homework': data['homework'] ?? '',
                  'order': data['order'] ?? 0,
                });
              }
            }
          }
          lessonPlans.sort((a, b) {
            final dateA = (a['date'] is Timestamp) ? (a['date'] as Timestamp).toDate() : DateTime.now();
            final dateB = (b['date'] is Timestamp) ? (b['date'] as Timestamp).toDate() : DateTime.now();
            final cmp = dateA.compareTo(dateB);
            if (cmp != 0) return cmp;
            return (a['order'] as int).compareTo(b['order'] as int);
          });
        } catch (e) {
          print('Error fetching lesson plans for background student: $e');
        }
      }
      return lessonPlans;
    }

    // Execute all top-level queries concurrently!
    final results = await Future.wait([
      fetchStudyProgramsFuture(),
      fetchAgmAssignmentsFuture(),
      fetchCampAssignmentsFuture(),
      fetchTeacherNameFuture(),
      fetchLessonPlansFuture(),
    ]);

    final List<Map<String, dynamic>> studentStudyPrograms = results[0] as List<Map<String, dynamic>>;
    final List<Map<String, dynamic>> agmAssignments = results[1] as List<Map<String, dynamic>>;
    final List<Map<String, dynamic>> campAssignments = results[2] as List<Map<String, dynamic>>;
    final String teacherName = results[3] as String;
    final List<Map<String, dynamic>> lessonPlans = results[4] as List<Map<String, dynamic>>;

    List<Map<String, dynamic>> selectedStudyProg = [];
    List<dynamic> topicAnalysis = [];
    Map<String, int> thresh = {'Genel': 70};

    if (studentStudyPrograms.isNotEmpty) {
      final firstProg = studentStudyPrograms.first;
      selectedStudyProg = [firstProg];
      topicAnalysis = firstProg['topicAnalysis'] ?? [];
      final rawThresholds = firstProg['thresholds'] ?? {};
      rawThresholds.forEach((k, v) {
        thresh[k.toString()] = int.tryParse(v.toString()) ?? 70;
      });
      final Set<String> uniqueSubjects = {};
      for (var item in topicAnalysis) {
        if (item is Map) {
          final sub = item['dersAdi']?.toString() ?? item['ders']?.toString() ?? item['subject']?.toString() ?? '';
          if (sub.isNotEmpty) uniqueSubjects.add(sub);
        }
      }
      for (var sub in uniqueSubjects) {
        if (!thresh.containsKey(sub)) {
          thresh[sub] = 70;
        }
      }
    }

    List<Map<String, dynamic>> selectedExamsData = [];
    for (var exam in _selectedExamsToInclude) {
      final resJson = exam['resultsJson'] as String? ?? '';
      bool foundStudent = false;
      if (resJson.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(resJson);
          final studentRow = _findStudentInExamResults(decoded, studentId, targetStudent: student);
          if (studentRow != null) {
            foundStudent = true;
            final Map<String, double> subjectNets = {};
            if (studentRow['subjects'] != null && studentRow['subjects'] is Map) {
              (studentRow['subjects'] as Map).forEach((k, v) {
                if (v is Map) {
                  subjectNets[k.toString()] = num.tryParse(v['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
                }
              });
            }
            
            double totalNet = num.tryParse(studentRow['totalNet']?.toString() ?? '0')?.toDouble() ?? 0.0;
            if (totalNet == 0.0 && subjectNets.isNotEmpty) {
              totalNet = subjectNets.values.fold(0.0, (sum, item) => sum + item);
            }

            selectedExamsData.add({
              'examName': exam['name'],
              'examTypeId': exam['examTypeId'] ?? '',
              'rankGeneral': studentRow['rankGeneral'] ?? studentRow['rank'] ?? '-',
              'rankBranch': studentRow['rankBranch'] ?? '-',
              'totalScore': studentRow['score'] ?? studentRow['totalScore'] ?? 0.0,
              'totalNet': totalNet,
              'subjectNets': subjectNets,
            });
          }
        } catch (_) {}
      }
      
      if (!foundStudent) {
        selectedExamsData.add({
          'examName': exam['name'],
          'examTypeId': exam['examTypeId'] ?? '',
          'didNotParticipate': true,
          'rankGeneral': '-',
          'rankBranch': '-',
          'totalScore': 0.0,
          'totalNet': 0.0,
          'subjectNets': <String, double>{},
        });
      }
    }

    return {
      'studyPrograms': selectedStudyProg,
      'topicAnalysis': topicAnalysis,
      'thresholds': thresh,
      'agmAssignments': agmAssignments,
      'campAssignments': campAssignments,
      'classTeacherName': teacherName,
      'lessonPlans': lessonPlans,
      'selectedExamsData': selectedExamsData,
    };
  }

  Future<void> _startBulkDownload({required bool onlyActive, required bool combinedPdf}) async {
    if (_selectedStudent == null) return;
    
    final List<Map<String, dynamic>> studentsToProcess = onlyActive 
        ? [_selectedStudent!] 
        : _navigationStudentsList;

    if (studentsToProcess.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İşlem yapılacak öğrenci bulunamadı.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    final progressNotifier = ValueNotifier<Map<String, dynamic>>({
      'current': 0,
      'total': studentsToProcess.length,
      'studentName': '',
      'stage': 'fetching',
      'detail': 'Hazırlanıyor...',
    });

    BuildContext? progressDialogContext;
    // Show Progress Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        progressDialogContext = dialogCtx;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: progressNotifier,
            builder: (context, val, child) {
              final current = val['current'] as int;
              final total = val['total'] as int;
              final studentName = val['studentName'] as String;
              final stage = val['stage'] as String;
              final detail = val['detail'] as String? ?? '';
              
              double progress = total > 0 ? current / total : 0.0;
              if (stage == 'zipping') progress = 0.95;
              if (stage == 'saving') progress = 1.0;
              
              String titleText = 'Raporlar Hazırlanıyor';
              Color themeColor = Colors.indigo.shade900;
              IconData stageIcon = Icons.sync_rounded;
              
              if (stage == 'fetching') {
                titleText = 'Veritabanından Veriler Çekiliyor';
                themeColor = Colors.indigo.shade800;
                stageIcon = Icons.cloud_download_rounded;
              } else if (stage == 'generating') {
                titleText = 'PDF Raporları Üretiliyor';
                themeColor = Colors.blue.shade800;
                stageIcon = Icons.picture_as_pdf_rounded;
              } else if (stage == 'zipping') {
                titleText = 'Arşiv Paketleniyor';
                themeColor = Colors.amber.shade800;
                stageIcon = Icons.folder_zip_rounded;
              } else if (stage == 'saving') {
                titleText = 'İndirme Başlatılıyor';
                themeColor = Colors.green.shade800;
                stageIcon = Icons.download_done_rounded;
              }
              
              return Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        stageIcon,
                        size: 36,
                        color: themeColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      titleText,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: themeColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (studentName.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        studentName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      detail,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        color: themeColor,
                        backgroundColor: themeColor.withOpacity(0.1),
                        minHeight: 8,
                      ),
                    ),
                    if (total > 0 && stage != 'zipping' && stage != 'saving') ...[
                      const SizedBox(height: 12),
                      Text(
                        '$current / $total',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: themeColor,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    try {
      final List<Map<String, dynamic>> compiledStudentsData = [];
      
      // 1. Fetch data sequentially (highly optimized internal calls, extremely smooth animation!)
      for (int i = 0; i < studentsToProcess.length; i++) {
        final s = studentsToProcess[i];
        final sName = s['name'] ?? 'Öğrenci';
        final sClass = s['class'] ?? '';
        final displayName = sClass.isNotEmpty ? '$sName ($sClass)' : sName;
        
        if (mounted) {
          progressNotifier.value = {
            'current': i + 1,
            'total': studentsToProcess.length,
            'studentName': displayName,
            'stage': 'fetching',
            'detail': 'Firestore veritabanı bağlantısı kuruluyor, akademik kazanımlar ve sınav netleri analiz ediliyor...',
          };
        }
        
        final fetched = await _fetchStudentPdfData(s);
        compiledStudentsData.add({
          'student': s,
          'data': fetched,
        });

        // Micro-delay for a buttery-smooth visual UI progression
        await Future.delayed(const Duration(milliseconds: 150));
      }
      
      // 2. Generate PDF bytes
      if (combinedPdf) {
        if (mounted) {
          progressNotifier.value = {
            'current': studentsToProcess.length,
            'total': studentsToProcess.length,
            'studentName': 'Birleşik PDF Belgesi',
            'stage': 'generating',
            'detail': 'Tüm öğrenci şablonları birleştiriliyor, sayfa yerleşim düzenleri hesaplanıyor...',
          };
        }
        await Future.delayed(const Duration(milliseconds: 300));
        
        final pdfStudentsList = compiledStudentsData.map((item) {
          final s = item['student'] as Map<String, dynamic>;
          final fetched = item['data'] as Map<String, dynamic>;
          return {
            'studentName': s['name'] ?? '',
            'studentClass': s['class'] ?? '',
            'studentNo': s['studentNo'] ?? '',
            'selectedExams': fetched['selectedExamsData'],
            'agmAssignments': fetched['agmAssignments'],
            'campAssignments': fetched['campAssignments'],
            'studyPrograms': fetched['studyPrograms'],
            'classTeacherName': fetched['classTeacherName'],
            'principalName': _principalName,
            'topicAnalysisThresholds': fetched['thresholds'],
            'studentTopicAnalysis': fetched['topicAnalysis'],
            'lessonPlans': fetched['lessonPlans'],
          };
        }).toList();
        
        if (mounted) {
          progressNotifier.value = {
            'current': studentsToProcess.length,
            'total': studentsToProcess.length,
            'studentName': 'Birleşik PDF Belgesi',
            'stage': 'generating',
            'detail': 'Vektörel PDF belgesi çiziliyor ve yazdırılmaya hazırlanıyor...',
          };
        }
        
        final bytes = await ParentReportPdfHelper.generateCombinedReport(
          studentsData: pdfStudentsList,
          letterContent: _letterController.text,
          includeExams: _includeExams,
          includeAgm: _includeAgm,
          includeCamp: _includeCamp,
          includeStudyPrograms: _includeStudyPrograms,
          lessonAbbreviations: _lessonAbbreviations,
          examTypeSubjectOrders: _examTypeSubjectOrders,
          agmShowBranch: _agmShowBranch,
          agmShowTeacher: _agmShowTeacher,
          agmShowKazanim: _agmShowKazanim,
          agmShowDurum: _agmShowDurum,
          campShowBranch: _campShowBranch,
          campShowTeacher: _campShowTeacher,
          campShowKazanim: _campShowKazanim,
          campShowDurum: _campShowDurum,
          includeKazanimList: _includeKazanimList,
          includeTopicAnalysis: _includeTopicAnalysis,
          topicAnalysisShowPriority: _topicAnalysisShowPriority,
          topicAnalysisShowReinforcement: _topicAnalysisShowReinforcement,
          includeLessonPlans: _includeLessonPlans,
          includeFooter: _includeFooter,
          footerShowTeacher: _footerShowTeacher,
          footerShowPageNumber: _footerShowPageNumber,
          footerShowPrincipal: _footerShowPrincipal,
        );
        
        if (mounted) {
          progressNotifier.value = {
            'current': studentsToProcess.length,
            'total': studentsToProcess.length,
            'studentName': '',
            'stage': 'saving',
            'detail': 'PDF indirmesi sisteminizde başlatılıyor...',
          };
        }
        
        final filename = 'Veli_Bilgilendirme_Raporlari_Birlesik.pdf';
        
        if (kIsWeb) {
          final blob = html.Blob([bytes], 'application/pdf');
          final url = html.Url.createObjectUrlFromBlob(blob);
          html.AnchorElement(href: url)
            ..setAttribute("download", filename)
            ..click();
          html.Url.revokeObjectUrl(url);
        } else {
          await Printing.sharePdf(bytes: bytes, filename: filename);
        }
      } else {
        if (mounted) {
          progressNotifier.value = {
            'current': 0,
            'total': studentsToProcess.length,
            'studentName': '',
            'stage': 'generating',
            'detail': 'ZIP arşivi için bireysel PDF dosyaları sırayla oluşturuluyor...',
          };
        }
        
        final archive = Archive();
        
        for (int i = 0; i < compiledStudentsData.length; i++) {
          final item = compiledStudentsData[i];
          final s = item['student'] as Map<String, dynamic>;
          final fetched = item['data'] as Map<String, dynamic>;
          final sName = s['name'] ?? 'Öğrenci';
          final sClass = s['class'] ?? '';
          final displayName = sClass.isNotEmpty ? '$sName ($sClass)' : sName;
          
          if (mounted) {
            progressNotifier.value = {
              'current': i + 1,
              'total': studentsToProcess.length,
              'studentName': displayName,
              'stage': 'generating',
              'detail': '$sName için özel PDF belgesi tasarlanıyor ve sayfa düzeni hesaplanıyor...',
            };
          }
          
          final bytes = await ParentReportPdfHelper.generateReport(
            studentName: s['name'] ?? '',
            studentClass: s['class'] ?? '',
            studentNo: s['studentNo'] ?? '',
            letterContent: _letterController.text,
            selectedExams: List<Map<String, dynamic>>.from(fetched['selectedExamsData'] ?? []),
            agmAssignments: List<Map<String, dynamic>>.from(fetched['agmAssignments'] ?? []),
            campAssignments: List<Map<String, dynamic>>.from(fetched['campAssignments'] ?? []),
            studyPrograms: List<Map<String, dynamic>>.from(fetched['studyPrograms'] ?? []),
            includeExams: _includeExams,
            includeAgm: _includeAgm,
            includeCamp: _includeCamp,
            includeStudyPrograms: _includeStudyPrograms,
            lessonAbbreviations: _lessonAbbreviations,
            examTypeSubjectOrders: _examTypeSubjectOrders,
            classTeacherName: fetched['classTeacherName'] ?? 'Belirtilmedi',
            principalName: _principalName,
            agmShowBranch: _agmShowBranch,
            agmShowTeacher: _agmShowTeacher,
            agmShowKazanim: _agmShowKazanim,
            agmShowDurum: _agmShowDurum,
            campShowBranch: _campShowBranch,
            campShowTeacher: _campShowTeacher,
            campShowKazanim: _campShowKazanim,
            campShowDurum: _campShowDurum,
            includeKazanimList: _includeKazanimList,
            includeTopicAnalysis: _includeTopicAnalysis,
            topicAnalysisThresholds: Map<String, int>.from(fetched['thresholds'] ?? {}),
            studentTopicAnalysis: List<dynamic>.from(fetched['topicAnalysis'] ?? []),
            topicAnalysisShowPriority: _topicAnalysisShowPriority,
            topicAnalysisShowReinforcement: _topicAnalysisShowReinforcement,
            includeLessonPlans: _includeLessonPlans,
            lessonPlans: List<Map<String, dynamic>>.from(fetched['lessonPlans'] ?? []),
            includeFooter: _includeFooter,
            footerShowTeacher: _footerShowTeacher,
            footerShowPageNumber: _footerShowPageNumber,
            footerShowPrincipal: _footerShowPrincipal,
          );
          
          final className = s['class']?.toString() ?? 'Diger';
          final studentName = s['name']?.toString() ?? 'Ogrenci';
          final filePath = '$className/$studentName - Veli Bilgilendirme Mektubu.pdf';
          
          archive.addFile(ArchiveFile(filePath, bytes.length, bytes));

          // Micro-delay for a buttery-smooth PDF generation UI progression
          await Future.delayed(const Duration(milliseconds: 100));
        }
        
        if (mounted) {
          progressNotifier.value = {
            'current': studentsToProcess.length,
            'total': studentsToProcess.length,
            'studentName': 'ZIP Arşivi Paketleniyor',
            'stage': 'zipping',
            'detail': 'Tüm bireysel PDF raporları sıkıştırılarak şube klasörlerine göre arşivleniyor...',
          };
        }
        await Future.delayed(const Duration(milliseconds: 300));
        
        final zipBytes = ZipEncoder().encode(archive);
        if (zipBytes != null) {
          if (mounted) {
            progressNotifier.value = {
              'current': studentsToProcess.length,
              'total': studentsToProcess.length,
              'studentName': '',
              'stage': 'saving',
              'detail': 'ZIP arşivi indirmesi sisteminizde başlatılıyor...',
            };
          }
          
          final zipFilename = 'Veli_Bilgilendirme_Raporlari.zip';
          if (kIsWeb) {
            final blob = html.Blob([zipBytes], 'application/zip');
            final url = html.Url.createObjectUrlFromBlob(blob);
            html.AnchorElement(href: url)
              ..setAttribute("download", zipFilename)
              ..click();
            html.Url.revokeObjectUrl(url);
          } else {
            await Printing.sharePdf(bytes: Uint8List.fromList(zipBytes), filename: zipFilename);
          }
        }
      }
      
      if (progressDialogContext != null && Navigator.of(progressDialogContext!).canPop()) {
        Navigator.of(progressDialogContext!).pop();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Raporlar başarıyla oluşturuldu ve indirildi.'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      print('Bulk Download Error: $e');
      if (progressDialogContext != null && Navigator.of(progressDialogContext!).canPop()) {
        Navigator.of(progressDialogContext!).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata oluştu: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }
}
