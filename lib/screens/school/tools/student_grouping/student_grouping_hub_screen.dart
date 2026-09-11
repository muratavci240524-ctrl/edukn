import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../../models/class_model.dart';
import '../../../../models/school/student_grouping_model.dart';
import '../../../../services/student_grouping_service.dart';
import '../../../../services/student_grouping_pdf_service.dart';
import '../../../../widgets/edukn_app_bar.dart';

class StudentGroupingHubScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;
  final String? initialClassId;

  const StudentGroupingHubScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
    this.initialClassId,
  }) : super(key: key);

  @override
  State<StudentGroupingHubScreen> createState() => _StudentGroupingHubScreenState();
}

class _StudentGroupingHubScreenState extends State<StudentGroupingHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<ClassModel> _classes = [];
  int? _selectedClassLevel;
  String _selectedBranchId = 'all'; // 'all' = Tüm Şubeler, veya class.id
  String _selectedClassName = '';

  List<int> get _availableClassLevels => _classes.map((c) => c.classLevel).toSet().toList()..sort();
  List<ClassModel> get _branchesForSelectedLevel => _selectedClassLevel == null
      ? []
      : (_classes.where((c) => c.classLevel == _selectedClassLevel).toList()
        ..sort((a, b) => a.className.compareTo(b.className)));

  List<GroupingStudent> _classStudents = [];
  bool _isLoadingClasses = true;
  bool _isLoadingStudents = false;
  bool _isSaving = false;

  // Deneme Sınavı Seviye Entegrasyonu
  List<Map<String, dynamic>> _trialExams = [];
  Set<String> _selectedSubjects = {'all'}; // 'all' = Genel Toplam, veya {'Matematik', 'Fen Bilimleri'}
  List<String> _availableExamSubjects = ['Türkçe', 'Matematik', 'Fen Bilimleri', 'Sosyal Bilgiler', 'İngilizce', 'Din Kültürü'];
  int _matchedExamStudentCount = 0;
  int _evaluatedExamsCount = 0;

  // Grup Ayarları
  GroupingMode _selectedMode = GroupingMode.balanced;
  bool _groupByStudentCount = false; // false = Grup Sayısına göre, true = Gruptaki kişi sayısına göre
  int _targetGroupCount = 4;
  int _targetStudentsPerGroup = 5;
  bool _balanceGender = false;
  List<BlacklistRule> _blacklistRules = [];
  List<String> _spreadStudentIds = []; // Haşarı / Enerji ayrık dağıtılacak öğrenci ID'leri
  bool _isKanbanView = true; // Yatay kaydırma (Kanban / Sütunlar) vs Izgara görünümü

  // Oluşturulan Aktif Gruplar
  List<StudentGroup> _generatedGroups = [];
  String _workTitle = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final now = DateTime.now();
    _workTitle = '${now.year}-${now.year + 1} Çalışma Grupları (${DateFormat('dd.MM.yyyy').format(now)})';

    _loadClasses();
    _loadTrialExams();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _getSubjectColor(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('mat')) return const Color(0xFF2563EB); // Mavi
    if (s.contains('türk') || s.contains('turk')) return const Color(0xFFDC2626); // Kırmızı
    if (s.contains('fen')) return const Color(0xFF059669); // Yeşil
    if (s.contains('sosyal') || s.contains('inkılap') || s.contains('tarih')) return const Color(0xFFD97706); // Kehribar
    if (s.contains('ing') || s.contains('dil')) return const Color(0xFF7C3AED); // Mor
    if (s.contains('din')) return const Color(0xFF0D9488); // Teal
    return const Color(0xFF4F46E5); // İndigo
  }

  IconData _getSubjectIcon(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('mat')) return Icons.calculate_rounded;
    if (s.contains('türk') || s.contains('turk')) return Icons.menu_book_rounded;
    if (s.contains('fen')) return Icons.science_rounded;
    if (s.contains('sosyal') || s.contains('inkılap') || s.contains('tarih')) return Icons.public_rounded;
    if (s.contains('ing') || s.contains('dil')) return Icons.language_rounded;
    if (s.contains('din')) return Icons.auto_stories_rounded;
    return Icons.school_rounded;
  }

  String _normalizeTurkish(String val) {
    return val
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
  }

  int? _extractLevelNumber(dynamic levelVal) {
    if (levelVal == null) return null;
    if (levelVal is int) return levelVal;
    if (levelVal is num) return levelVal.toInt();
    final match = RegExp(r'\d+').firstMatch(levelVal.toString());
    if (match != null) {
      return int.tryParse(match.group(0)!);
    }
    return null;
  }

  Future<void> _loadTrialExams() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('trial_exams')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final list = snap.docs.map((d) {
        return {
          'id': d.id,
          ...d.data(),
        };
      }).toList();

      if (mounted) {
        setState(() {
          _trialExams = list;
        });
        _calculateLevelExamScores();
      }
    } catch (_) {}
  }

  /// Seçili sınıf seviyesindeki TÜM deneme sınavlarını ortaklaşa hesaplar
  void _calculateLevelExamScores({Set<String>? subjects, bool showToast = false}) {
    if (subjects != null) {
      _selectedSubjects = subjects.isEmpty ? {'all'} : subjects;
    }
    final isAll = _selectedSubjects.contains('all');

    // 1. O sınıf seviyesindeki tüm sonuçları girilmiş deneme sınavlarını bul
    final matchingExams = _trialExams.where((e) {
      if (_selectedClassLevel != null) {
        final examLvl = _extractLevelNumber(e['classLevel']);
        if (examLvl != null) {
          return examLvl == _selectedClassLevel;
        }
      }
      return true;
    }).where((e) => e['resultsJson'] != null && e['resultsJson'].toString().trim().isNotEmpty).toList();

    final Set<String> foundSubjects = {};
    // Her öğrenci ID/numara/isim için tüm sınavlardan toplanan puan listesi
    final Map<String, List<double>> studentScoresMap = {};

    for (var exam in matchingExams) {
      final resultsJson = exam['resultsJson'] as String?;
      if (resultsJson == null || resultsJson.trim().isEmpty) continue;

      try {
        final dynamic rawDecoded = jsonDecode(resultsJson);
        final List<dynamic> decoded = rawDecoded is List ? rawDecoded : (rawDecoded is Map ? rawDecoded.values.toList() : []);

        for (var item in decoded) {
          if (item is! Map) continue;
          final sId = (item['systemStudentId'] ?? item['studentId'] ?? item['id'] ?? '').toString().trim();
          final sNo = (item['studentNumber'] ?? item['studentNo'] ?? item['number'] ?? item['no'] ?? item['okulNo'] ?? '').toString().trim();
          final sName = (item['name'] ?? item['studentName'] ?? item['ogrenci'] ?? item['adSoyad'] ?? item['ad_soyad'] ?? '').toString().trim();

          // Sınavdaki branşları topla
          if (item['subjects'] != null && item['subjects'] is Map) {
            for (var k in (item['subjects'] as Map).keys) {
              foundSubjects.add(k.toString().trim());
            }
          }

          double examScore = 0.0;
          if (isAll) {
            // Genel Toplam Puan veya Toplam Net
            examScore = num.tryParse(
              item['totalScore']?.toString() ??
              item['score']?.toString() ??
              item['puan']?.toString() ??
              item['toplamPuan']?.toString() ??
              item['totalNet']?.toString() ??
              item['net']?.toString() ??
              '0',
            )?.toDouble() ?? 0.0;
          } else {
            // Seçilen branş(lar)ın net toplamı
            double branchSum = 0.0;
            if (item['subjects'] != null && item['subjects'] is Map) {
              final subMap = item['subjects'] as Map;
              for (var sel in _selectedSubjects) {
                final normSel = _normalizeTurkish(sel);
                final matchedKey = subMap.keys.firstWhere(
                  (k) {
                    final normK = _normalizeTurkish(k.toString());
                    return normK == normSel || normK.contains(normSel) || normSel.contains(normK);
                  },
                  orElse: () => null,
                );

                if (matchedKey != null) {
                  final sData = subMap[matchedKey];
                  if (sData is Map) {
                    branchSum += num.tryParse(sData['net']?.toString() ?? sData['score']?.toString() ?? sData['puan']?.toString() ?? sData['dogru']?.toString() ?? '0')?.toDouble() ?? 0.0;
                  } else if (sData is num) {
                    branchSum += sData.toDouble();
                  }
                }
              }
            }
            examScore = branchSum;
          }

          if (sId.isNotEmpty) {
            studentScoresMap.putIfAbsent('id_$sId', () => []).add(examScore);
          }
          if (sNo.isNotEmpty) {
            studentScoresMap.putIfAbsent('no_$sNo', () => []).add(examScore);
            final parsedNo = int.tryParse(sNo);
            if (parsedNo != null) {
              studentScoresMap.putIfAbsent('no_${parsedNo.toString()}', () => []).add(examScore);
            }
          }
          if (sName.isNotEmpty) {
            studentScoresMap.putIfAbsent('name_${_normalizeTurkish(sName)}', () => []).add(examScore);
          }
        }
      } catch (_) {}
    }

    setState(() {
      _evaluatedExamsCount = matchingExams.length;
      if (foundSubjects.isNotEmpty) {
        _availableExamSubjects = foundSubjects.toList()..sort();
      } else {
        _availableExamSubjects = ['Türkçe', 'Matematik', 'Fen Bilimleri', 'Sosyal Bilgiler', 'İngilizce', 'Din Kültürü'];
      }
    });

    // 2. Her öğrenciyi eşleştir ve puanını güncelle
    int matchedCount = 0;
    for (var student in _classStudents) {
      final sIdKey = 'id_${student.id}';
      final sNoRaw = (student.studentNumber ?? '').trim();
      final sNoKey = 'no_$sNoRaw';
      final sNoParsedKey = 'no_${int.tryParse(sNoRaw)?.toString() ?? sNoRaw}';
      final sNameKey = 'name_${_normalizeTurkish(student.name)}';

      final scoresList = studentScoresMap[sIdKey] ??
          (sNoRaw.isNotEmpty ? (studentScoresMap[sNoKey] ?? studentScoresMap[sNoParsedKey]) : null) ??
          studentScoresMap[sNameKey];

      if (scoresList != null && scoresList.isNotEmpty) {
        matchedCount++;
        final avgScore = scoresList.reduce((a, b) => a + b) / scoresList.length;
        student.academicScore = avgScore;
      }
    }

    setState(() {
      _matchedExamStudentCount = matchedCount;
    });

    // 3. Eğer gruplar zaten oluşturulmuşsa, anında yeni puanlarla yeniden dağıt
    if (_generatedGroups.isNotEmpty) {
      int computedGroupCount = _targetGroupCount;
      if (_groupByStudentCount) {
        computedGroupCount = (_classStudents.length / _targetStudentsPerGroup).ceil().clamp(1, _classStudents.length);
      }

      final newGroups = StudentGroupingService.generateGroups(
        students: _classStudents,
        targetGroupCount: computedGroupCount,
        mode: _selectedMode,
        blacklistRules: _blacklistRules,
        spreadStudentIds: _spreadStudentIds,
        balanceGender: _balanceGender,
      );

      setState(() {
        _generatedGroups = newGroups;
      });
    }

    if (showToast && mounted) {
      final label = isAll ? 'Genel Toplam' : _selectedSubjects.join(' + ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${matchingExams.length} deneme sınavı ortalamasından "$label" başarıyla hesaplandı ($matchedCount öğrenci eşleşti)!'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadClasses() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
          .where('isActive', isEqualTo: true)
          .get();

      final list = snap.docs.map((d) => ClassModel.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => a.className.compareTo(b.className));

      if (mounted) {
        setState(() {
          _classes = list;
          _isLoadingClasses = false;

          final levels = list.map((c) => c.classLevel).toSet().toList()..sort();
          if (levels.isNotEmpty) {
            if (_selectedClassLevel == null || !levels.contains(_selectedClassLevel)) {
              _selectedClassLevel = levels.first;
            }
            _selectedBranchId = 'all';
          }
        });

        if (_selectedClassLevel != null) {
          _loadStudentsForSelection();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingClasses = false);
    }
  }

  Future<void> _loadStudentsForSelection() async {
    if (_selectedClassLevel == null) return;
    setState(() => _isLoadingStudents = true);

    try {
      final List<GroupingStudent> students = [];
      int counter = 1;

      List<ClassModel> targetClasses = [];
      if (_selectedBranchId == 'all') {
        targetClasses = _branchesForSelectedLevel;
      } else {
        targetClasses = _classes.where((c) => c.id == _selectedBranchId).toList();
      }

      for (var cls in targetClasses) {
        QuerySnapshot snap = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('classId', isEqualTo: cls.id)
            .get();

        if (snap.docs.isEmpty) {
          snap = await FirebaseFirestore.instance
              .collection('students')
              .where('institutionId', isEqualTo: widget.institutionId)
              .where('className', isEqualTo: cls.className)
              .get();
        }

        for (var doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final firstName = data['firstName'] ?? data['name'] ?? '';
          final lastName = data['lastName'] ?? data['surname'] ?? '';
          String fullName = '$firstName $lastName'.trim();
          if (fullName.isEmpty) fullName = 'Öğrenci $counter';

          final genderStr = (data['gender'] ?? '').toString().toLowerCase().trim();
          final isGirl = genderStr.startsWith('k') || genderStr.startsWith('f') || genderStr == 'kadın' || genderStr == 'kız';
          final isBoy = genderStr.startsWith('e') || genderStr.startsWith('m') || genderStr == 'erkek';
          final gender = isGirl ? 'K' : (isBoy ? 'E' : 'unspecified');

          // Başarı puanı
          double score = 0.0;
          if (data['gpa'] != null && data['gpa'] is num) {
            score = (data['gpa'] as num).toDouble();
          } else if (data['academicScore'] != null && data['academicScore'] is num) {
            score = (data['academicScore'] as num).toDouble();
          } else if (data['puan'] != null && data['puan'] is num) {
            score = (data['puan'] as num).toDouble();
          } else if (data['score'] != null && data['score'] is num) {
            score = (data['score'] as num).toDouble();
          }

          students.add(GroupingStudent(
            id: doc.id,
            name: fullName,
            studentNumber: data['studentNumber']?.toString() ?? data['schoolNumber']?.toString(),
            className: cls.className,
            gender: gender,
            academicScore: score,
          ));
          counter++;
        }
      }

      students.sort((a, b) => a.name.compareTo(b.name));

      if (mounted) {
        setState(() {
          _classStudents = students;
          _isLoadingStudents = false;
          _blacklistRules.clear();
          _spreadStudentIds.clear();
          _generatedGroups.clear();

          if (students.isNotEmpty) {
            _targetGroupCount = (students.length / 5).ceil().clamp(2, 12);
          }
        });

        _calculateLevelExamScores();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStudents = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Öğrenciler yüklenirken hata oluştu: $e')),
        );
      }
    }
  }

  void _runGroupingAlgorithm() {
    if (_classStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gruplama yapmak için önce sınıf seçmelisiniz!')),
      );
      return;
    }

    int computedGroupCount = _targetGroupCount;
    if (_groupByStudentCount) {
      computedGroupCount = (_classStudents.length / _targetStudentsPerGroup).ceil().clamp(1, _classStudents.length);
    }

    final groups = StudentGroupingService.generateGroups(
      students: _classStudents,
      targetGroupCount: computedGroupCount,
      mode: _selectedMode,
      blacklistRules: _blacklistRules,
      spreadStudentIds: _spreadStudentIds,
      balanceGender: _balanceGender,
    );

    setState(() {
      _generatedGroups = groups;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${groups.length} grup başarıyla oluşturuldu! Dokunarak taşıyabilir / takas edebilirsiniz.',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _onStudentDropped(GroupingStudent student, String targetGroupId) {
    setState(() {
      // 1. Öğrenciyi bulunduğu mevcut gruptan çıkar
      for (var group in _generatedGroups) {
        group.students.removeWhere((s) => s.id == student.id);
      }

      // 2. Hedef gruba ekle
      final targetGroup = _generatedGroups.firstWhere((g) => g.id == targetGroupId);
      targetGroup.students.add(student);
    });
  }

  Future<void> _saveGroupingPlan() async {
    if (_generatedGroups.isEmpty || _selectedClassLevel == null) return;
    setState(() => _isSaving = true);

    try {
      final classNameToSave = _selectedBranchId == 'all'
          ? '$_selectedClassLevel. Sınıflar (Tümü)'
          : (_selectedClassName.isNotEmpty ? _selectedClassName : '$_selectedClassLevel. Sınıf');

      final plan = GroupingPlanModel(
        institutionId: widget.institutionId,
        classId: _selectedBranchId,
        className: classNameToSave,
        title: _workTitle.trim().isNotEmpty ? _workTitle.trim() : 'Grup Çalışması',
        mode: _selectedMode,
        groupCount: _generatedGroups.length,
        totalStudents: _classStudents.length,
        createdAt: DateTime.now(),
        groups: _generatedGroups,
        blacklistRules: _blacklistRules,
        spreadStudentIds: _spreadStudentIds,
      );

      await FirebaseFirestore.instance.collection('student_grouping_plans').add(plan.toMap());

      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Grup çalışması başarıyla buluta kaydedildi!'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydetme hatası: $e')),
        );
      }
    }
  }

  Future<void> _printPdf() async {
    if (_generatedGroups.isEmpty || _selectedClassLevel == null) return;

    final classNameToPrint = _selectedBranchId == 'all'
        ? '$_selectedClassLevel. Sınıflar (Tümü)'
        : (_selectedClassName.isNotEmpty ? _selectedClassName : '$_selectedClassLevel. Sınıf');

    final plan = GroupingPlanModel(
      institutionId: widget.institutionId,
      classId: _selectedBranchId,
      className: classNameToPrint,
      title: _workTitle,
      mode: _selectedMode,
      groupCount: _generatedGroups.length,
      totalStudents: _classStudents.length,
      createdAt: DateTime.now(),
      groups: _generatedGroups,
      blacklistRules: _blacklistRules,
      spreadStudentIds: _spreadStudentIds,
    );

    final bytes = await StudentGroupingPdfService.generateGroupingPlanPdf(
      plan: plan,
      schoolTypeName: widget.schoolTypeName,
    );

    await Printing.layoutPdf(onLayout: (_) => bytes);
  }

  void _copyToClipboard() {
    if (_generatedGroups.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('📋 ${_workTitle.toUpperCase()}');
    buffer.writeln('Sınıf: $_selectedClassName | Mod: ${_selectedMode.title}');
    buffer.writeln('------------------------------------------');

    for (var g in _generatedGroups) {
      buffer.writeln('\n🔹 ${g.groupName} (Ort: ${g.averageScore.toStringAsFixed(1)}p • ${g.totalStudents} Kişi)');
      for (int i = 0; i < g.students.length; i++) {
        final s = g.students[i];
        buffer.writeln('  ${i + 1}. ${s.name} (${s.academicScore.toStringAsFixed(0)}p)');
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Gruplar metin olarak panoya kopyalandı!'),
        backgroundColor: Color(0xFF5C6BC0),
      ),
    );
  }

  Future<GroupingStudent?> _showStudentSearchPicker({
    required String title,
    GroupingStudent? currentSelection,
    GroupingStudent? excludeStudent,
  }) async {
    final searchController = TextEditingController();
    String query = '';

    return showModalBottomSheet<GroupingStudent>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredList = _classStudents.where((s) {
              if (excludeStudent != null && s.id == excludeStudent.id) return false;
              if (query.trim().isEmpty) return true;
              final q = query.trim().toLowerCase();
              return s.name.toLowerCase().contains(q) ||
                  (s.studentNumber != null && s.studentNumber!.contains(q)) ||
                  (s.className != null && s.className!.toLowerCase().contains(q));
            }).toList()
              ..sort((a, b) => a.name.compareTo(b.name));

            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.person_search_rounded, color: Color(0xFF5C6BC0), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchController,
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText: 'Öğrenci adı, no veya şube ile ara...',
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF5C6BC0), size: 20),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                searchController.clear();
                                setModalState(() => query = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onChanged: (val) => setModalState(() => query = val),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${filteredList.length} öğrenci listeleniyor (Alfabetik)',
                      style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade500),
                    ),
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: filteredList.isEmpty
                        ? Center(
                            child: Text(
                              'Aradığınız kriterde öğrenci bulunamadı.',
                              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade500),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredList.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final student = filteredList[idx];
                              final isSelected = currentSelection?.id == student.id;

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: student.isFemale
                                      ? const Color(0xFFFCE7F3)
                                      : (student.isMale ? const Color(0xFFDBEAFE) : Colors.grey.shade200),
                                  child: Text(
                                    student.name.isNotEmpty ? student.name[0] : '?',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: student.isFemale ? const Color(0xFFDB2777) : (student.isMale ? const Color(0xFF2563EB) : Colors.black87),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  student.name,
                                  style: GoogleFonts.inter(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    fontSize: 13.5,
                                    color: isSelected ? const Color(0xFF5C6BC0) : const Color(0xFF1E293B),
                                  ),
                                ),
                                subtitle: Row(
                                  children: [
                                    if (student.className != null) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                                        child: Text(student.className!, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    if (student.studentNumber != null)
                                      Text('No: ${student.studentNumber}', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500)),
                                  ],
                                ),
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle_rounded, color: Color(0xFF5C6BC0), size: 22)
                                    : const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                                onTap: () {
                                  Navigator.pop(ctx, student);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddBlacklistDialog() {
    if (_classStudents.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kural eklemek için sınıfta en az 2 öğrenci olmalıdır.')),
      );
      return;
    }

    GroupingStudent student1 = _classStudents.first;
    GroupingStudent student2 = _classStudents.length > 1 ? _classStudents[1] : _classStudents.first;
    GroupingRuleType ruleType = GroupingRuleType.together;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isTogether = ruleType == GroupingRuleType.together;

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isTogether ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isTogether ? Icons.link_rounded : Icons.block_rounded,
                          color: isTogether ? const Color(0xFF059669) : const Color(0xFFDC2626),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isTogether ? 'Birlikte Olsun (Whitelist) Kuralı' : 'Birlikte Olmasın (Blacklist) Kuralı',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Kural Türü Seçimi (🟢 Birlikte Olsun / 🔴 Birlikte Olmasın)
                  Text(
                    'Kural Türünü Belirleyiniz:',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // 🟢 Birlikte Olsun Butonu
                      Expanded(
                        child: InkWell(
                          onTap: () => setModalState(() => ruleType = GroupingRuleType.together),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                            decoration: BoxDecoration(
                              color: isTogether ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isTogether ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                                width: isTogether ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.link_rounded,
                                    size: 18, color: isTogether ? const Color(0xFF059669) : Colors.grey),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Birlikte Olsun',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: isTogether ? const Color(0xFF065F46) : const Color(0xFF64748B),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 🔴 Birlikte Olmasın Butonu
                      Expanded(
                        child: InkWell(
                          onTap: () => setModalState(() => ruleType = GroupingRuleType.apart),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                            decoration: BoxDecoration(
                              color: !isTogether ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: !isTogether ? const Color(0xFFEF4444) : const Color(0xFFE2E8F0),
                                width: !isTogether ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.block_rounded,
                                    size: 18, color: !isTogether ? const Color(0xFFDC2626) : Colors.grey),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Birlikte Olmasın',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: !isTogether ? const Color(0xFF991B1B) : const Color(0xFF64748B),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Bilgilendirme Kutusu
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isTogether ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isTogether ? const Color(0xFFBBF7D0) : const Color(0xFFFECDD3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isTogether ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                          size: 16,
                          color: isTogether ? const Color(0xFF16A34A) : const Color(0xFFE11D48),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isTogether
                                ? 'Seçtiğiniz bu iki öğrenci otomatik dağıtımda MUTLAKA aynı gruba atanacaktır.'
                                : 'Seçtiğiniz bu iki öğrenci otomatik dağıtımda ASLA aynı gruba konulmayacaktır.',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              color: isTogether ? const Color(0xFF14532D) : const Color(0xFF881337),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 1. Öğrenci Seçim Kartı
                  Text('1. Öğrenciyi Seçiniz:', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final selected = await _showStudentSearchPicker(
                        title: '1. Öğrenciyi Seçiniz',
                        currentSelection: student1,
                        excludeStudent: student2,
                      );
                      if (selected != null) {
                        setModalState(() => student1 = selected);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: student1.isFemale ? const Color(0xFFFCE7F3) : const Color(0xFFDBEAFE),
                            child: Text(student1.name.isNotEmpty ? student1.name[0] : '?',
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: student1.isFemale ? const Color(0xFFDB2777) : const Color(0xFF2563EB))),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(student1.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                if (student1.className != null)
                                  Text('${student1.className} Şubesi', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          const Icon(Icons.search_rounded, size: 18, color: Color(0xFF5C6BC0)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 2. Öğrenci Seçim Kartı
                  Text('2. Öğrenciyi Seçiniz:', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final selected = await _showStudentSearchPicker(
                        title: '2. Öğrenciyi Seçiniz',
                        currentSelection: student2,
                        excludeStudent: student1,
                      );
                      if (selected != null) {
                        setModalState(() => student2 = selected);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: student2.isFemale ? const Color(0xFFFCE7F3) : const Color(0xFFDBEAFE),
                            child: Text(student2.name.isNotEmpty ? student2.name[0] : '?',
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: student2.isFemale ? const Color(0xFFDB2777) : const Color(0xFF2563EB))),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(student2.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                if (student2.className != null)
                                  Text('${student2.className} Şubesi', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          const Icon(Icons.search_rounded, size: 18, color: Color(0xFF5C6BC0)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isTogether ? const Color(0xFF059669) : const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      if (student1.id == student2.id) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Lütfen birbirinden farklı iki öğrenci seçiniz!')),
                        );
                        return;
                      }

                      final alreadyExists = _blacklistRules.any((r) => r.conflicts(student1.id, student2.id));
                      if (alreadyExists) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Bu iki öğrenci arasında zaten bir kural tanımlanmış!')),
                        );
                        return;
                      }

                      setState(() {
                        _blacklistRules.add(BlacklistRule(
                          student1Id: student1.id,
                          student1Name: student1.name,
                          student2Id: student2.id,
                          student2Name: student2.name,
                          type: ruleType,
                        ));
                      });

                      Navigator.pop(ctx);
                    },
                    child: Text(
                      isTogether ? 'Birlikte Olsun Kuralını Kaydet' : 'Birlikte Olmasın Kuralını Kaydet',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: EduknAppBar(
        title: 'Akıllı Öğrenci Gruplama',
        subtitle: widget.schoolTypeName,
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: const Color(0xFF5C6BC0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: const Color(0xFF64748B),
                  labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                  unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                  tabs: const [
                    Tab(icon: Icon(Icons.group_work_rounded, size: 20), text: 'Grup Oluştur & Düzenle'),
                    Tab(icon: Icon(Icons.history_rounded, size: 20), text: 'Kayıtlı Gruplar'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildGroupingWorkspaceTab(),
            _buildSavedPlansTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupingWorkspaceTab() {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return _isLoadingClasses
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, isMobile ? 90 : 40),
            children: [
              // 1. Sınıf Seçimi & Başlık Kartı
              _buildClassAndTitleCard(isMobile),
              const SizedBox(height: 14),

              // 2. Grup Ayarları, Dağıtım Modu & Branş Seçimi Kartı
              _buildSettingsCard(isMobile),
              const SizedBox(height: 14),

              // 3. Blacklist / Dışlama Kuralları Kartı
              _buildBlacklistCard(),
              const SizedBox(height: 14),

              // 4. Ayrık Dağıtım (Haşarı / Enerji) Kartı
              _buildSpreadDistributionCard(),
              const SizedBox(height: 16),

              // "Grupları Oluştur" Büyük Aksiyon Butonu
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5C6BC0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                onPressed: _classStudents.isEmpty ? null : _runGroupingAlgorithm,
                icon: const Icon(Icons.bolt_rounded, size: 22),
                label: Text(
                  'Grupları Akıllı Oluştur (${_classStudents.length} Öğrenci)',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              const SizedBox(height: 20),

              // 4. Dağıtılan Gruplar & İnteraktif Sürükle-Bırak Paneli
              if (_generatedGroups.isNotEmpty) ...[
                _buildResultsHeaderBar(isMobile),
                const SizedBox(height: 12),
                _buildInteractiveGroupsBoard(isMobile),
              ],
            ],
          );
  }

  Widget _buildClassAndTitleCard(bool isMobile) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF5C6BC0).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.school_rounded, color: Color(0xFF5C6BC0), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sınıf Seviyesi ve Şube Seçimi', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14.5)),
                      Text(
                        _selectedBranchId == 'all'
                            ? '${_selectedClassLevel ?? ''}. Sınıfların tüm şubeleri (${_classStudents.length} öğrenci)'
                            : '$_selectedClassName Şubesi (${_classStudents.length} öğrenci)',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (isMobile) ...[
              // Sınıf Seviyesi
              DropdownButtonFormField<int>(
                isExpanded: true,
                isDense: true,
                value: _selectedClassLevel,
                decoration: InputDecoration(
                  labelText: 'Sınıf Seviyesi',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF5C6BC0), width: 1.5)),
                  prefixIcon: const Icon(Icons.layers_rounded, color: Color(0xFF5C6BC0), size: 20),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                ),
                items: _availableClassLevels.map((lvl) {
                  return DropdownMenuItem<int>(
                    value: lvl,
                    child: Text('$lvl. Sınıflar', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  );
                }).toList(),
                onChanged: (lvl) {
                  if (lvl == null || lvl == _selectedClassLevel) return;
                  setState(() {
                    _selectedClassLevel = lvl;
                    _selectedBranchId = 'all';
                  });
                  _loadStudentsForSelection();
                },
              ),
              const SizedBox(height: 10),

              // Şube Seçimi
              DropdownButtonFormField<String>(
                isExpanded: true,
                isDense: true,
                value: _selectedBranchId,
                decoration: InputDecoration(
                  labelText: 'Şube Seçiniz',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF5C6BC0), width: 1.5)),
                  prefixIcon: const Icon(Icons.groups_rounded, color: Color(0xFF5C6BC0), size: 20),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: 'all',
                    child: Text('✨ Tümü (Tüm ${_selectedClassLevel ?? ''}. Sınıf Şubeleri)',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF4338CA), fontSize: 13), overflow: TextOverflow.ellipsis),
                  ),
                  ..._branchesForSelectedLevel.map((c) {
                    return DropdownMenuItem<String>(
                      value: c.id!,
                      child: Text('${c.className} Şubesi', style: GoogleFonts.inter(fontSize: 13), overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                ],
                onChanged: (val) {
                  if (val == null || val == _selectedBranchId) return;
                  setState(() {
                    _selectedBranchId = val;
                    if (val != 'all') {
                      final match = _classes.where((c) => c.id == val).toList();
                      _selectedClassName = match.isNotEmpty ? match.first.className : '';
                    }
                  });
                  _loadStudentsForSelection();
                },
              ),
              const SizedBox(height: 10),

              TextField(
                decoration: InputDecoration(
                  labelText: 'Çalışma / Etkinlik Başlığı',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF5C6BC0), width: 1.5)),
                  prefixIcon: const Icon(Icons.edit_note_rounded, color: Color(0xFF5C6BC0), size: 20),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                style: GoogleFonts.inter(fontSize: 13),
                controller: TextEditingController(text: _workTitle),
                onChanged: (v) => _workTitle = v,
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      isDense: true,
                      value: _selectedClassLevel,
                      decoration: InputDecoration(
                        labelText: 'Sınıf Seviyesi',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF5C6BC0), width: 1.5)),
                        prefixIcon: const Icon(Icons.layers_rounded, color: Color(0xFF5C6BC0), size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      ),
                      items: _availableClassLevels.map((lvl) {
                        return DropdownMenuItem<int>(
                          value: lvl,
                          child: Text('$lvl. Sınıflar', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (lvl) {
                        if (lvl == null || lvl == _selectedClassLevel) return;
                        setState(() {
                          _selectedClassLevel = lvl;
                          _selectedBranchId = 'all';
                        });
                        _loadStudentsForSelection();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      isDense: true,
                      value: _selectedBranchId,
                      decoration: InputDecoration(
                        labelText: 'Şube Seçiniz',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF5C6BC0), width: 1.5)),
                        prefixIcon: const Icon(Icons.groups_rounded, color: Color(0xFF5C6BC0), size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      ),
                      items: [
                        DropdownMenuItem<String>(
                          value: 'all',
                          child: Text('✨ Tümü (Tüm ${_selectedClassLevel ?? ''}. Sınıf Şubeleri)',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF4338CA), fontSize: 13), overflow: TextOverflow.ellipsis),
                        ),
                        ..._branchesForSelectedLevel.map((c) {
                          return DropdownMenuItem<String>(
                            value: c.id!,
                            child: Text('${c.className} Şubesi', style: GoogleFonts.inter(fontSize: 13), overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                      ],
                      onChanged: (val) {
                        if (val == null || val == _selectedBranchId) return;
                        setState(() {
                          _selectedBranchId = val;
                          if (val != 'all') {
                            final match = _classes.where((c) => c.id == val).toList();
                            _selectedClassName = match.isNotEmpty ? match.first.className : '';
                          }
                        });
                        _loadStudentsForSelection();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Çalışma / Etkinlik Başlığı',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF5C6BC0), width: 1.5)),
                        prefixIcon: const Icon(Icons.edit_note_rounded, color: Color(0xFF5C6BC0), size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      style: GoogleFonts.inter(fontSize: 13),
                      controller: TextEditingController(text: _workTitle),
                      onChanged: (v) => _workTitle = v,
                    ),
                  ),
                ],
              ),
            ],
            if (_isLoadingStudents)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard(bool isMobile) {
    final List<String> subjectsList = [
      ..._availableExamSubjects,
    ];
    if (subjectsList.isEmpty) {
      subjectsList.addAll(['Türkçe', 'Matematik', 'Fen Bilimleri', 'Sosyal Bilgiler', 'İngilizce', 'Din Kültürü']);
    }

    final isAllSelected = _selectedSubjects.contains('all') || _selectedSubjects.isEmpty;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.tune_rounded, color: Color(0xFF10B981), size: 20),
                ),
                const SizedBox(width: 10),
                Text('Dağıtım Modu ve Boyut Ayarı', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14.5)),
              ],
            ),
            const SizedBox(height: 14),

            // Dağıtım Modları (3 Kart - Tıksız / Seçim Çerçeveli)
            ...GroupingMode.values.map((mode) {
              final isSelected = _selectedMode == mode;
              return InkWell(
                onTap: () => setState(() => _selectedMode = mode),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? mode.color.withValues(alpha: 0.08) : const Color(0xFFFAFAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? mode.color : const Color(0xFFE2E8F0),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: mode.color.withValues(alpha: isSelected ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(mode.icon, color: mode.color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mode.title,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: isSelected ? mode.color : const Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              mode.description,
                              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: mode.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Aktif',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: mode.color),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),

            // Seviye veya Dengeli Modu Seçiliyse: Branş / Ders Seçim Paneli
            if (_selectedMode != GroupingMode.random) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.school_rounded, size: 16, color: Color(0xFF4F46E5)),
                            const SizedBox(width: 6),
                            Text(
                              'Puanlama Branşı (Ders Seçimi):',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5, color: const Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                        if (!isAllSelected)
                          InkWell(
                            onTap: () => _calculateLevelExamScores(subjects: {'all'}, showToast: true),
                            child: Text(
                              'Tümüne Sıfırla (Genel Puan)',
                              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        // ✨ Tümü
                        FilterChip(
                          showCheckmark: false,
                          avatar: Icon(
                            isAllSelected ? Icons.stars_rounded : Icons.all_inclusive_rounded,
                            size: 15,
                            color: isAllSelected ? Colors.white : const Color(0xFF4F46E5),
                          ),
                          label: const Text('✨ Tümü (Genel Puan)'),
                          selected: isAllSelected,
                          selectedColor: const Color(0xFF4F46E5),
                          backgroundColor: Colors.white,
                          side: BorderSide(
                            color: isAllSelected ? const Color(0xFF4F46E5) : const Color(0xFFCBD5E1),
                            width: isAllSelected ? 1.5 : 1,
                          ),
                          labelStyle: GoogleFonts.inter(
                            fontWeight: isAllSelected ? FontWeight.bold : FontWeight.w600,
                            fontSize: 11.5,
                            color: isAllSelected ? Colors.white : const Color(0xFF334155),
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              _calculateLevelExamScores(subjects: {'all'}, showToast: true);
                            }
                          },
                        ),

                        // Branş Çipleri
                        ...subjectsList.map((subject) {
                          final isSelected = _selectedSubjects.contains(subject);
                          final subjectColor = _getSubjectColor(subject);

                          return FilterChip(
                            showCheckmark: false,
                            avatar: Icon(
                              _getSubjectIcon(subject),
                              size: 15,
                              color: isSelected ? Colors.white : subjectColor,
                            ),
                            label: Text(subject),
                            selected: isSelected,
                            selectedColor: subjectColor,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: isSelected ? subjectColor : const Color(0xFFCBD5E1),
                              width: isSelected ? 1.5 : 1,
                            ),
                            labelStyle: GoogleFonts.inter(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              fontSize: 11.5,
                              color: isSelected ? Colors.white : const Color(0xFF334155),
                            ),
                            onSelected: (selected) {
                              final newSet = Set<String>.from(_selectedSubjects);
                              if (selected) {
                                newSet.remove('all');
                                newSet.add(subject);
                              } else {
                                newSet.remove(subject);
                                if (newSet.isEmpty) newSet.add('all');
                              }
                              _calculateLevelExamScores(subjects: newSet, showToast: true);
                            },
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF64748B)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            _evaluatedExamsCount > 0
                                ? '${_selectedClassLevel ?? ""}. Sınıf düzeyindeki $_evaluatedExamsCount deneme sınavının ${isAllSelected ? "genel puan ortalamaları" : "${_selectedSubjects.join(" + ")} net ortalamaları"} baz alınmaktadır ($_matchedExamStudentCount/${_classStudents.length} öğrenci eşleşti).'
                                : 'Bu sınıf seviyesinde henüz kayıtlı deneme sınavı bulunamadı; genel başarı puanları kullanılıyor.',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),
            const Divider(height: 20),

            // Grup Sayısı / Kişi Sayısı Seçim Çipleri (Tıksız)
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    showCheckmark: false,
                    label: Center(
                      child: Text(
                        'Grup Sayısı Belirle',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: !_groupByStudentCount ? FontWeight.bold : FontWeight.w500,
                          color: !_groupByStudentCount ? Colors.white : const Color(0xFF475569),
                        ),
                      ),
                    ),
                    selected: !_groupByStudentCount,
                    selectedColor: const Color(0xFF5C6BC0),
                    backgroundColor: Colors.white,
                    side: BorderSide(color: !_groupByStudentCount ? const Color(0xFF5C6BC0) : const Color(0xFFE2E8F0)),
                    onSelected: (_) => setState(() => _groupByStudentCount = false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    showCheckmark: false,
                    label: Center(
                      child: Text(
                        'Kişi Sayısı Belirle',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: _groupByStudentCount ? FontWeight.bold : FontWeight.w500,
                          color: _groupByStudentCount ? Colors.white : const Color(0xFF475569),
                        ),
                      ),
                    ),
                    selected: _groupByStudentCount,
                    selectedColor: const Color(0xFF5C6BC0),
                    backgroundColor: Colors.white,
                    side: BorderSide(color: _groupByStudentCount ? const Color(0xFF5C6BC0) : const Color(0xFFE2E8F0)),
                    onSelected: (_) => setState(() => _groupByStudentCount = true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Sayı Artırma / Azaltma Satırı
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _groupByStudentCount ? 'Grup Başı Öğrenci:' : 'Toplam Grup Sayısı:',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded, color: Color(0xFF5C6BC0), size: 22),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () {
                        setState(() {
                          if (_groupByStudentCount) {
                            if (_targetStudentsPerGroup > 2) _targetStudentsPerGroup--;
                          } else {
                            if (_targetGroupCount > 2) _targetGroupCount--;
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFC7D2FE)),
                      ),
                      child: Text(
                        _groupByStudentCount ? '$_targetStudentsPerGroup Kişi' : '$_targetGroupCount Grup',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF4338CA)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF5C6BC0), size: 22),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () {
                        setState(() {
                          if (_groupByStudentCount) {
                            if (_targetStudentsPerGroup < 15) _targetStudentsPerGroup++;
                          } else {
                            if (_targetGroupCount < 12) _targetGroupCount++;
                          }
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),

            // Dengeleme ve Artık Bilgi Önizlemesi
            if (_classStudents.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF475569)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _groupByStudentCount
                            ? 'Toplam ${_classStudents.length} öğrenci, $_targetStudentsPerGroup\'şer kişilik yaklaşık ${(_classStudents.length / _targetStudentsPerGroup).ceil()} gruba ayrılacaktır.'
                            : 'Toplam ${_classStudents.length} öğrenci, $_targetGroupCount gruba yaklaşık ${(_classStudents.length / _targetGroupCount).floor()} - ${(_classStudents.length / _targetGroupCount).ceil()}\'şer kişi olarak dengeli dağıtılacaktır.',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF334155), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),
            // Cinsiyet Dengesi Switch
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Kız / Erkek Dağılımını Dengele', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Gruplardaki cinsiyet oranlarını mümkün olduğunca eşitler.', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
              value: _balanceGender,
              activeColor: const Color(0xFF5C6BC0),
              onChanged: (v) => setState(() => _balanceGender = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlacklistCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.rule_rounded, color: Color(0xFF4F46E5), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Birlikte Olsun / Olmasın Kuralları',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _showAddBlacklistDialog,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFC7D2FE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded, size: 16, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 4),
                        Text(
                          'Kural Ekle',
                          style: GoogleFonts.inter(color: const Color(0xFF4F46E5), fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Öğrenci çiftlerinin aynı grupta toplanmasını (Yeşil 🟢) veya farklı gruplara dağılmasını (Kırmızı 🔴) belirleyebilirsiniz.',
              style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),

            if (_blacklistRules.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Center(
                  child: Text(
                    'Henüz eşleşme veya dışlama kuralı eklenmedi. (İsteğe bağlı)',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _blacklistRules.map((rule) {
                  final isTogether = rule.isTogether;

                  return Chip(
                    backgroundColor: isTogether ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                    side: BorderSide(color: isTogether ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
                    avatar: Icon(
                      isTogether ? Icons.link_rounded : Icons.block_rounded,
                      color: isTogether ? const Color(0xFF059669) : const Color(0xFFDC2626),
                      size: 16,
                    ),
                    label: Text(
                      isTogether
                          ? '${rule.student1Name} 🔗 ${rule.student2Name} (Birlikte)'
                          : '${rule.student1Name} ✖ ${rule.student2Name} (Ayrı)',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isTogether ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                      ),
                    ),
                    deleteIcon: Icon(Icons.close_rounded, size: 16, color: isTogether ? const Color(0xFF059669) : const Color(0xFFDC2626)),
                    onDeleted: () {
                      setState(() {
                        _blacklistRules.removeWhere((r) => r.conflicts(rule.student1Id, rule.student2Id));
                      });
                    },
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpreadDistributionCard() {
    final selectedStudents = _classStudents.where((s) => _spreadStudentIds.contains(s.id)).toList();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.bolt_rounded, color: Color(0xFFEA580C), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ayrık (Haşarı / Enerji) Dağıtımı',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _showAddSpreadStudentDialog,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_add_alt_1_rounded, size: 16, color: Color(0xFFEA580C)),
                        const SizedBox(width: 4),
                        Text(
                          'Öğrenci Seç (${_spreadStudentIds.length})',
                          style: GoogleFonts.inter(color: const Color(0xFFEA580C), fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Seçtiğiniz enerjik/haşarı öğrencileri gruplara eşit olarak paylaştırır (Örn: 8 grup varsa 8 öğrenci seçtiğinizde her gruba 1\'er, 16 ise 2\'şer dağıtılır).',
              style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            if (_spreadStudentIds.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Center(
                  child: Text(
                    'Henüz ayrık dağıtılacak öğrenci seçilmedi. (İsteğe bağlı)',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: selectedStudents.map((s) {
                  return Chip(
                    avatar: const CircleAvatar(
                      backgroundColor: Color(0xFFEA580C),
                      radius: 10,
                      child: Icon(Icons.bolt_rounded, size: 12, color: Colors.white),
                    ),
                    label: Text(
                      '${s.name} ${s.className != null && _selectedBranchId == "all" ? "(${s.className})" : ""}',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF9A3412)),
                    ),
                    backgroundColor: const Color(0xFFFFF7ED),
                    side: const BorderSide(color: Color(0xFFFED7AA)),
                    deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFEA580C)),
                    onDeleted: () {
                      setState(() {
                        _spreadStudentIds.remove(s.id);
                      });
                    },
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  void _showAddSpreadStudentDialog() {
    if (_classStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce sınıf/şube seçmelisiniz!')),
      );
      return;
    }

    final tempSelected = Set<String>.from(_spreadStudentIds);
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = _classStudents.where((s) {
              if (searchQuery.isEmpty) return true;
              return s.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
                  (s.className?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
            }).toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.bolt_rounded, color: Color(0xFFEA580C), size: 20),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ayrık (Haşarı) Öğrenci Seçimi', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text('Gruplara eşit sayıda dağıtılacaklar', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Öğrenci adı veya şube ile ara...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFFEA580C)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFEA580C), width: 1.5)),
                      ),
                      onChanged: (v) => setDialogState(() => searchQuery = v.trim()),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Seçilen: ${tempSelected.length} Öğrenci', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFFEA580C))),
                          if (tempSelected.isNotEmpty)
                            TextButton(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 24)),
                              onPressed: () => setDialogState(() => tempSelected.clear()),
                              child: const Text('Tümünü Temizle', style: TextStyle(fontSize: 11.5, color: Colors.red)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final student = filtered[idx];
                          final isChecked = tempSelected.contains(student.id);

                          return CheckboxListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            value: isChecked,
                            activeColor: const Color(0xFFEA580C),
                            title: Text(student.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: Text('${student.className ?? ""} • ${student.academicScore.toStringAsFixed(1)}p', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade600)),
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  tempSelected.add(student.id);
                                } else {
                                  tempSelected.remove(student.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Vazgeç'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    setState(() {
                      _spreadStudentIds = tempSelected.toList();
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text('Kaydet (${tempSelected.length})'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildResultsHeaderBar(bool isMobile) {
    return Card(
      elevation: 1,
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFBBF24), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Oluşturulan Çalışma Grupları (${_generatedGroups.length} Grup)',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                        ),
                      ),
                      // Görünüm Değiştirici
                      IconButton(
                        tooltip: _isKanbanView ? 'Izgara Görünümüne Geç' : 'Yatay Kaydırmaya Geç',
                        icon: Icon(_isKanbanView ? Icons.grid_view_rounded : Icons.view_column_rounded, color: Colors.white70, size: 20),
                        onPressed: () => setState(() => _isKanbanView = !_isKanbanView),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _printPdf,
                          icon: const Icon(Icons.print_rounded, size: 16),
                          label: const Text('PDF'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _copyToClipboard,
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Kopyala'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _isSaving ? null : _saveGroupingPlan,
                          icon: const Icon(Icons.save_rounded, size: 16),
                          label: const Text('Kaydet'),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFBBF24), size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Oluşturulan Çalışma Grupları (${_generatedGroups.length} Grup)',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Web Görünüm Değiştirici Buton
                      InkWell(
                        onTap: () => setState(() => _isKanbanView = !_isKanbanView),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_isKanbanView ? Icons.grid_view_rounded : Icons.view_column_rounded, color: Colors.white, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                _isKanbanView ? 'Izgara Görünümü' : 'Yatay (Mouse Kaydırma)',
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _printPdf,
                        icon: const Icon(Icons.print_rounded, size: 16),
                        label: const Text('Yazdır / PDF'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _copyToClipboard,
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Panoya Kopyala'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isSaving ? null : _saveGroupingPlan,
                        icon: const Icon(Icons.save_rounded, size: 16),
                        label: const Text('Buluta Kaydet'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildInteractiveGroupsBoard(bool isMobile) {
    if (_isKanbanView) {
      return ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _generatedGroups.map((group) {
                return Container(
                  width: isMobile ? 290 : 330,
                  height: 420,
                  margin: const EdgeInsets.only(right: 14),
                  child: _buildSingleGroupDragTargetCard(group),
                );
              }).toList(),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = isMobile ? 1 : (constraints.maxWidth > 900 ? 3 : 2);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 420,
          ),
          itemCount: _generatedGroups.length,
          itemBuilder: (context, index) {
            final group = _generatedGroups[index];
            return _buildSingleGroupDragTargetCard(group);
          },
        );
      },
    );
  }

  Widget _buildSingleGroupDragTargetCard(StudentGroup group) {
    final collisions = StudentGroupingService.findCollisionsInGroup(group, _blacklistRules);

    return DragTarget<GroupingStudent>(
      onWillAccept: (incomingStudent) {
        // Zaten bu grupta değilse kabul et
        return incomingStudent != null && !group.students.any((s) => s.id == incomingStudent.id);
      },
      onAccept: (incomingStudent) {
        _onStudentDropped(incomingStudent, group.id);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isHovered
                  ? const Color(0xFF10B981)
                  : (collisions.isNotEmpty ? Colors.red.shade400 : group.groupColor.withOpacity(0.5)),
              width: isHovered ? 2.5 : (collisions.isNotEmpty ? 2.0 : 1.5),
            ),
            boxShadow: [
              BoxShadow(
                color: isHovered
                    ? const Color(0xFF10B981).withOpacity(0.15)
                    : group.groupColor.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grup Başlığı & Renkli Bar
              InkWell(
                onTap: () => _showEditGroupNameDialog(group),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14.5)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: group.groupColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(14.5)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                group.groupName,
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.edit_rounded, size: 14, color: Colors.white70),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${group.totalStudents} Öğrenci',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11.5, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // İstatistik Şeridi (Ortalama Puan & Kız/Erkek)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: group.groupColor.withOpacity(0.08),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_selectedMode != GroupingMode.random)
                      Text(
                        _selectedSubjects.contains('all') || _selectedSubjects.isEmpty
                            ? 'Ortalama: ${group.averageScore.toStringAsFixed(1)} Puan'
                            : 'Ortalama: ${group.averageScore.toStringAsFixed(1)} Net (${_selectedSubjects.length == 1 ? _selectedSubjects.first : "${_selectedSubjects.length} Branş"})',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: group.groupColor),
                      )
                    else
                      Text(
                        'Rastgele Dağıtım',
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: group.groupColor),
                      ),
                    Text(
                      '${group.femaleCount} Kız  •  ${group.maleCount} Erkek',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF475569), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

              // Blacklist Çarpışma Uyarısı (Varsa)
              if (collisions.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  color: Colors.red.shade50,
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Blacklist: ${collisions.first.student1Name} & ${collisions.first.student2Name}',
                          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              // Sürüklenebilir Öğrenci Listesi
              Expanded(
                child: group.students.isEmpty
                    ? Center(
                        child: Text(
                          isHovered ? 'Buraya Bırakın' : 'Grup Boş\n(Öğrenci Sürükleyin)',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: isHovered ? const Color(0xFF10B981) : Colors.grey.shade400,
                            fontWeight: isHovered ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: group.students.length,
                        itemBuilder: (context, sIdx) {
                          final student = group.students[sIdx];
                          return _buildDraggableStudentTile(student, group);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditGroupNameDialog(StudentGroup group) {
    final controller = TextEditingController(text: group.groupName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Grup Adını Değiştir', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Grup Adı',
            hintText: 'Örn: Kartallar, A Grubu...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5C6BC0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  group.groupName = controller.text.trim();
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  void _showMoveStudentBottomSheet(GroupingStudent student, StudentGroup sourceGroup) {
    final otherGroups = _generatedGroups.where((g) => g.id != sourceGroup.id).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String selectedSwapGroupId = otherGroups.isNotEmpty ? otherGroups.first.id : '';

        return StatefulBuilder(
          builder: (context, setModalState) {
            final targetSwapGroup = otherGroups.firstWhere(
              (g) => g.id == selectedSwapGroupId,
              orElse: () => otherGroups.isNotEmpty ? otherGroups.first : sourceGroup,
            );

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: DefaultTabController(
                length: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sürükleme Çubuğu
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Başlık ve Öğrenci Bilgisi
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: student.isFemale
                                ? const Color(0xFFFCE7F3)
                                : (student.isMale ? const Color(0xFFDBEAFE) : Colors.grey.shade200),
                            child: Text(
                              student.name.isNotEmpty ? student.name[0] : '?',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: student.isFemale
                                    ? const Color(0xFFDB2777)
                                    : (student.isMale ? const Color(0xFF2563EB) : Colors.black87),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  student.name,
                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Mevcut Grup: ${sourceGroup.groupName} • ${student.academicScore.toStringAsFixed(1)}p',
                                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),

                    // Sekmeler: 1. Gruba Taşı, 2. Öğrenci ile Takas Et
                    Container(
                      color: const Color(0xFFF8FAFC),
                      child: TabBar(
                        labelColor: const Color(0xFF4F46E5),
                        unselectedLabelColor: const Color(0xFF64748B),
                        indicatorColor: const Color(0xFF4F46E5),
                        indicatorWeight: 3,
                        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                        tabs: const [
                          Tab(icon: Icon(Icons.arrow_forward_rounded, size: 18), text: 'Gruba Taşı'),
                          Tab(icon: Icon(Icons.swap_horiz_rounded, size: 18), text: 'Öğrenci ile Takas Et'),
                        ],
                      ),
                    ),

                    Expanded(
                      child: TabBarView(
                        children: [
                          // 1. TAB: GRUBA TAŞI
                          ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              Text(
                                '${student.name} adlı öğrenciyi hangi gruba aktarmak istiyorsunuz?',
                                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155), fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 12),
                              if (otherGroups.isEmpty)
                                const Center(child: Text('Taşınabilecek başka grup bulunmuyor.'))
                              else
                                ...otherGroups.map((targetGroup) {
                                  return Card(
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: targetGroup.groupColor.withValues(alpha: 0.3), width: 1.5),
                                    ),
                                    color: targetGroup.groupColor.withValues(alpha: 0.05),
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: targetGroup.groupColor,
                                        radius: 14,
                                        child: const Icon(Icons.group_rounded, color: Colors.white, size: 16),
                                      ),
                                      title: Text(
                                        targetGroup.groupName,
                                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF1E293B)),
                                      ),
                                      subtitle: Text(
                                        '${targetGroup.totalStudents} Öğrenci • Ort: ${targetGroup.averageScore.toStringAsFixed(1)}p',
                                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                      ),
                                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF4F46E5)),
                                      onTap: () {
                                        _onStudentDropped(student, targetGroup.id);
                                        Navigator.pop(ctx);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('✅ ${student.name}, ${targetGroup.groupName} adlı gruba taşındı.'),
                                            backgroundColor: const Color(0xFF10B981),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                }),
                            ],
                          ),

                          // 2. TAB: ÖĞRENCİ İLE TAKAS ET
                          ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              Text(
                                'Takas yapmak istediğiniz hedef grubu seçiniz:',
                                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF334155)),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: otherGroups.map((grp) {
                                    final isSelected = grp.id == selectedSwapGroupId;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        showCheckmark: false,
                                        label: Text('${grp.groupName} (${grp.totalStudents})'),
                                        selected: isSelected,
                                        selectedColor: grp.groupColor,
                                        backgroundColor: const Color(0xFFF1F5F9),
                                        labelStyle: GoogleFonts.inter(
                                          color: isSelected ? Colors.white : const Color(0xFF334155),
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                        onSelected: (val) {
                                          if (val) {
                                            setModalState(() {
                                              selectedSwapGroupId = grp.id;
                                            });
                                          }
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '${targetSwapGroup.groupName} içinden ${student.name} ile takas edilecek öğrenci:',
                                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF334155)),
                              ),
                              const SizedBox(height: 8),
                              if (targetSwapGroup.students.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  alignment: Alignment.center,
                                  child: Text('Bu grupta takas edilecek öğrenci bulunmuyor.', style: GoogleFonts.inter(color: Colors.grey.shade500)),
                                )
                              else
                                ...targetSwapGroup.students.map((targetStudent) {
                                  return Card(
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                      leading: CircleAvatar(
                                        radius: 14,
                                        backgroundColor: targetStudent.isFemale
                                            ? const Color(0xFFFCE7F3)
                                            : (targetStudent.isMale ? const Color(0xFFDBEAFE) : Colors.grey.shade200),
                                        child: Text(
                                          targetStudent.name.isNotEmpty ? targetStudent.name[0] : '?',
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            color: targetStudent.isFemale
                                                ? const Color(0xFFDB2777)
                                                : (targetStudent.isMale ? const Color(0xFF2563EB) : Colors.black87),
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        targetStudent.name,
                                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        '${targetStudent.className ?? ""} • ${targetStudent.academicScore.toStringAsFixed(1)}p',
                                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                      ),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.swap_horiz_rounded, size: 15, color: Color(0xFF4F46E5)),
                                            const SizedBox(width: 4),
                                            Text('Takas Et', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: const Color(0xFF4F46E5))),
                                          ],
                                        ),
                                      ),
                                      onTap: () {
                                        setState(() {
                                          sourceGroup.students.removeWhere((s) => s.id == student.id);
                                          targetSwapGroup.students.removeWhere((s) => s.id == targetStudent.id);

                                          sourceGroup.students.add(targetStudent);
                                          targetSwapGroup.students.add(student);
                                        });

                                        Navigator.pop(ctx);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('🔄 ${student.name} ↔️ ${targetStudent.name} başarıyla takas edildi!'),
                                            backgroundColor: const Color(0xFF10B981),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDraggableStudentTile(GroupingStudent student, StudentGroup sourceGroup) {
    final tileContent = InkWell(
      onTap: () => _showMoveStudentBottomSheet(student, sourceGroup),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: student.isFemale ? const Color(0xFFFDF2F8) : (student.isMale ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: student.isFemale ? const Color(0xFFFBCFE8) : (student.isMale ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator_rounded, size: 16, color: Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 12,
              backgroundColor: student.isFemale ? const Color(0xFFFCE7F3) : (student.isMale ? const Color(0xFFDBEAFE) : Colors.grey.shade200),
              child: Text(
                student.name.isNotEmpty ? student.name[0] : '?',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: student.isFemale ? const Color(0xFFDB2777) : (student.isMale ? const Color(0xFF2563EB) : Colors.black87),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      student.name,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: const Color(0xFF1E293B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (student.className != null && _selectedBranchId == 'all') ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        student.className!,
                        style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_selectedMode != GroupingMode.random)
              InkWell(
                onTap: () => _showEditScoreDialog(student),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFC7D2FE)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedSubjects.contains('all') || _selectedSubjects.isEmpty
                            ? '${student.academicScore.toStringAsFixed(0)}p'
                            : '${student.academicScore.toStringAsFixed(1)}n',
                        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF4338CA)),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.edit_rounded, size: 10, color: Color(0xFF5C6BC0)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return LongPressDraggable<GroupingStudent>(
      data: student,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 220,
          child: tileContent,
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: tileContent,
      ),
      child: tileContent,
    );
  }

  void _showEditScoreDialog(GroupingStudent student) {
    final controller = TextEditingController(text: student.academicScore.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${student.name} - Başarı Puanı', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Öğrencinin bu etkinlik veya gruplamada kullanılacak başarı puanını belirleyiniz (0 - 100):',
              style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Başarı Puanı (0-100)',
                prefixIcon: const Icon(Icons.grade_rounded, color: Color(0xFF5C6BC0)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5C6BC0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final val = double.tryParse(controller.text.trim());
              if (val != null) {
                setState(() {
                  student.academicScore = val.clamp(0.0, 100.0);
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedPlansTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('student_grouping_plans')
          .where('institutionId', isEqualTo: widget.institutionId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final plans = snapshot.data!.docs.map((doc) {
          return GroupingPlanModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        }).toList();

        plans.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (plans.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.group_work_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'Henüz Kayıtlı Grup Çalışması Yok',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Grup oluştur sekmesinden oluşturduğunuz grupları buluta kaydedebilirsiniz.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          );
        }

        final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          itemCount: plans.length,
          itemBuilder: (context, index) {
            final plan = plans[index];
            return Card(
              elevation: 1,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: plan.mode.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(plan.mode.icon, color: plan.mode.color, size: 22),
                ),
                title: Text(
                  plan.title,
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EAF6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        plan.className,
                        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: const Color(0xFF3949AB)),
                      ),
                    ),
                    Text(
                      '${plan.groups.length} Grup • ${plan.totalStudents} Öğrenci',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade700),
                    ),
                    Text(
                      '• ${dateFormat.format(plan.createdAt)}',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onSelected: (val) async {
                    if (val == 'load') {
                      setState(() {
                        _selectedBranchId = plan.classId;
                        _selectedClassName = plan.className;
                        _workTitle = plan.title;
                        _selectedMode = plan.mode;
                        _generatedGroups = plan.groups.map((g) => g.clone()).toList();
                        _blacklistRules = plan.blacklistRules.map((r) => r.clone()).toList();
                        _tabController.animateTo(0);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Grup çalışması çalışma alanına yüklendi.')),
                      );
                    } else if (val == 'print') {
                      final bytes = await StudentGroupingPdfService.generateGroupingPlanPdf(plan: plan);
                      await Printing.layoutPdf(onLayout: (_) => bytes);
                    } else if (val == 'delete' && plan.id != null) {
                      await FirebaseFirestore.instance.collection('student_grouping_plans').doc(plan.id).delete();
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'load',
                      child: Row(
                        children: [
                          const Icon(Icons.open_in_browser_rounded, size: 18, color: Color(0xFF5C6BC0)),
                          const SizedBox(width: 8),
                          Text('Çalışma Alanına Yükle', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'print',
                      child: Row(
                        children: [
                          const Icon(Icons.print_rounded, size: 18, color: Colors.teal),
                          const SizedBox(width: 8),
                          Text('Yazdır / PDF', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                          const SizedBox(width: 8),
                          Text('Sil', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
                onTap: () {
                  setState(() {
                    _selectedBranchId = plan.classId;
                    _selectedClassName = plan.className;
                    _workTitle = plan.title;
                    _selectedMode = plan.mode;
                    _generatedGroups = plan.groups.map((g) => g.clone()).toList();
                    _blacklistRules = plan.blacklistRules.map((r) => r.clone()).toList();
                    _tabController.animateTo(0);
                  });
                },
              ),
            );
          },
        );
      },
    );
  }
}
