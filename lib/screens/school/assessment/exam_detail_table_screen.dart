import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import 'evaluation_models.dart';
import 'student_report_card_dialog.dart';
import 'student_exam_comparison_dialog.dart';

class ExamDetailTableScreen extends StatefulWidget {
  final String examName;
  final List<Map<String, dynamic>> results;
  final List<String> availableSubjects;
  final TrialExam? currentExam;
  final List<TrialExam>? allExams;
  final String? institutionId;
  final String? schoolTypeName;
  final void Function(Map<String, dynamic> studentData)? onOpenReportCard;
  final void Function(Map<String, dynamic> studentData)? onCompareStudent;

  const ExamDetailTableScreen({
    Key? key,
    required this.examName,
    required this.results,
    required this.availableSubjects,
    this.currentExam,
    this.allExams,
    this.institutionId,
    this.schoolTypeName,
    this.onOpenReportCard,
    this.onCompareStudent,
  }) : super(key: key);

  @override
  _ExamDetailTableScreenState createState() => _ExamDetailTableScreenState();
}

class _ExamDetailTableScreenState extends State<ExamDetailTableScreen> {
  // Table View Settings
  bool _showColCorrect = false;
  bool _showColWrong = false;
  bool _showColEmpty = false;
  int _rowsPerPage = 24;

  List<String> _selectedClasses = []; // Empty = All
  List<String> _selectedSubjects = []; // Empty = All

  final Map<String, String> _customLessonShortNames = {};

  // Scroll & 2D Mouse Drag Pan Controllers
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  Offset? _lastPanPosition;
  double _panDistance = 0.0;
  bool _isPanning = false;

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  static const Map<String, String> _defaultShortNames = {
    'türkçe': 'TÜR',
    'turkce': 'TÜR',
    'matematik': 'MAT',
    'ilköğretim matematik': 'MAT',
    'ilkogretim matematik': 'MAT',
    'fen bilimleri': 'FEN',
    'fen ve teknoloji': 'FEN',
    'sosyal bilgiler': 'SOS',
    't.c. inkılap tarihi ve atatürkçülük': 'İNK',
    't.c. inkılap tarihi': 'İNK',
    'inkılap tarihi': 'İNK',
    'inkılap': 'İNK',
    'din kültürü ve ahlak bilgisi': 'DİN',
    'din kültürü': 'DİN',
    'din': 'DİN',
    'yabancı dil': 'İNG',
    'yabanci dil': 'İNG',
    'ingilizce': 'İNG',
    'almanca': 'ALM',
    'fransızca': 'FRA',
    'fizik': 'FİZ',
    'kimya': 'KİM',
    'biyoloji': 'BİY',
    'tarih': 'TAR',
    'coğrafya': 'COĞ',
    'cografya': 'COĞ',
    'felsefe': 'FEL',
    'felsefe grubu': 'FEL',
    'mantık': 'MAN',
    'psikoloji': 'PSİ',
    'sosyoloji': 'SOSY',
    'geometri': 'GEO',
    'türk dili ve edebiyatı': 'EDB',
    'edebiyat': 'EDB',
    'temel matematik': 'T.MAT',
    'ileri matematik': 'İ.MAT',
    'çağdaş türk ve dünya tarihi': 'Ç.TAR',
    'bilişim teknolojileri ve yazılım': 'BİL',
    'bilişim teknolojileri': 'BİL',
    'teknoloji ve tasarım': 'TEK',
    'müzik': 'MÜZ',
    'görsel sanatlar': 'GÖR',
    'beden eğitimi ve spor': 'BED',
    'beden eğitimi': 'BED',
    'trafik güvenliği': 'TRAF',
    'rehberlik': 'REH',
  };

  @override
  void initState() {
    super.initState();
    _loadLessonShortNames();
  }

  Future<void> _loadLessonShortNames() async {
    final instId = widget.institutionId ?? widget.currentExam?.institutionId;
    if (instId != null && instId.isNotEmpty) {
      try {
        final lessonsSnap = await FirebaseFirestore.instance
            .collection('lessons')
            .where('institutionId', isEqualTo: instId)
            .where('isActive', isEqualTo: true)
            .get();

        for (var doc in lessonsSnap.docs) {
          final data = doc.data();
          final lName = (data['lessonName'] ?? data['name'] ?? '')
              .toString()
              .toLowerCase()
              .trim();
          final bName = (data['branchName'] ?? '')
              .toString()
              .toLowerCase()
              .trim();
          final sName = (data['shortName'] ?? '').toString().toUpperCase().trim();
          if (sName.isNotEmpty) {
            if (lName.isNotEmpty) _customLessonShortNames[lName] = sName;
            if (bName.isNotEmpty) _customLessonShortNames[bName] = sName;
          }
        }
        if (mounted) setState(() {});
      } catch (e) {
        debugPrint('Error loading lesson short names in table: $e');
      }
    }
  }

  String _getSubjectShortName(String fullName) {
    final key = fullName.trim().toLowerCase();
    if (_customLessonShortNames.containsKey(key) &&
        _customLessonShortNames[key]!.isNotEmpty) {
      return _customLessonShortNames[key]!;
    }
    if (_defaultShortNames.containsKey(key)) {
      return _defaultShortNames[key]!;
    }
    for (var entry in _defaultShortNames.entries) {
      if (key.contains(entry.key) || entry.key.contains(key)) {
        return entry.value;
      }
    }
    final clean = fullName.trim();
    return clean.length <= 4
        ? clean.toUpperCase()
        : clean.substring(0, 4).toUpperCase();
  }

  // --- Helper Methods ---

  // --- Persistent Dropdown Helpers ---

  Widget _buildMultiSelectMenu({
    required String label,
    required IconData icon,
    required List<String> items,
    required List<String> selectedItems,
    required Function(List<String>) onChanged,
    required VoidCallback onForceRefresh, // New Param to force rebuild parent
  }) {
    return PopupMenuButton<String>(
      icon: Icon(
        icon,
        color: selectedItems.isNotEmpty ? Colors.indigo : Colors.grey.shade700,
      ),
      tooltip: '$label Filtrele',
      // We don't use onSelected because clicking items is handled inside.
      itemBuilder: (context) {
        // Initialize local state when menu opens to avoid stale closure values
        // If selectedItems is empty, it implies "All" in parent logic,
        // so we potentially need to start with all items checked visually?
        // Logic: filteredData where check checks `selectedClasses.contains`.
        // If empty, logic displays all.
        // So for the *Menu State*, we should likely treat Empty as "All Checkboxes Checked" or "None Checked"?
        // Previous logic: isAllSelected = selectedItems.isEmpty...
        // So we should initialize our temp list to be [items] if selectedItems is empty?
        // PROBABLY YES, so that unchecking one works correctly (removes from full list).

        List<String> tempSelectedItems;
        if (selectedItems.isEmpty) {
          tempSelectedItems = List.from(items);
        } else {
          tempSelectedItems = List.from(selectedItems);
        }

        return [
          PopupMenuItem(
            enabled: false, // Prevents menu from closing on tap
            child: Container(
              width: 300,
              height: 400, // Limit height
              child: StatefulBuilder(
                builder: (context, menuSetState) {
                  // Calculate "All" state based on our LOCAL temp list
                  bool isAllChecked = tempSelectedItems.length == items.length;

                  return Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          "$label Seçimi",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ),
                      Divider(height: 1),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            CheckboxListTile(
                              title: Text("Tümü"),
                              value: isAllChecked,
                              activeColor: Colors.indigo,
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (val) {
                                if (val == true) {
                                  // Select All -> fill temp list
                                  tempSelectedItems = List.from(items);
                                  // Parent usually expects [] for "All", but sending full list is also valid "All".
                                  // To be consistent with "Empty=All", we can send [];
                                  // But for local state, we need full list to show checks.
                                  // Let's send [] to parent if full.
                                  onChanged([]);
                                } else {
                                  // Unselect All -> Clear temp list
                                  tempSelectedItems.clear();
                                  // Parent expects non-empty to filter. Empty means all.
                                  // This is the tricky part.
                                  // If we want "None Selected" (show nothing), we need a way to say it.
                                  // If we pass an empty list, it shows ALL.
                                  // So technically we cannot show "Nothing".
                                  // Let's assume uncheck all means "Clear Filter" (Show All)?
                                  // Or we can pass a dummy value that matches nothing?
                                  // In this specific app, usually you wouldn't want to see "Nothing".
                                  // So Uncheck All -> Show All (reset) is a fine fallback.
                                  onChanged([]); // Reset
                                }
                                menuSetState(() {});
                                onForceRefresh();
                              },
                            ),
                            ...items.map((item) {
                              final isSelected = tempSelectedItems.contains(
                                item,
                              );

                              return CheckboxListTile(
                                title: Text(item),
                                value: isSelected,
                                activeColor: Colors.indigo,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged: (val) {
                                  if (val == true) {
                                    if (!tempSelectedItems.contains(item)) {
                                      tempSelectedItems.add(item);
                                    }
                                  } else {
                                    tempSelectedItems.remove(item);
                                  }

                                  // If effectively all are selected, we can send [] to parent
                                  // (if parent logic prefers [] for optimization/logic).
                                  if (tempSelectedItems.length ==
                                      items.length) {
                                    onChanged([]);
                                  } else {
                                    // If empty, parent treats as All.
                                    // If we *really* mean empty (user unchecked last item),
                                    // Parent will show All. This is acceptable UX (resetting).
                                    onChanged(tempSelectedItems);
                                  }

                                  menuSetState(() {});
                                  onForceRefresh(); // Update table BG
                                },
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ];
      },
    );
  }

  Widget _buildColumnVisibilityMenu() {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.view_column_outlined,
        color: (_showColCorrect || _showColWrong || _showColEmpty)
            ? Colors.indigo
            : Colors.grey.shade700,
      ),
      tooltip: 'Sütunları Göster/Gizle',
      itemBuilder: (context) {
        return [
          PopupMenuItem(
            enabled: false,
            child: Container(
              width: 200,
              child: StatefulBuilder(
                builder: (context, menuSetState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Sütun Görünümü",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      Divider(),
                      CheckboxListTile(
                        title: Text("Doğru (D)"),
                        value: _showColCorrect,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (val) {
                          setState(() => _showColCorrect = val ?? false);
                          menuSetState(() {});
                        },
                      ),
                      CheckboxListTile(
                        title: Text("Yanlış (Y)"),
                        value: _showColWrong,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (val) {
                          setState(() => _showColWrong = val ?? false);
                          menuSetState(() {});
                        },
                      ),
                      CheckboxListTile(
                        title: Text("Boş (B)"),
                        value: _showColEmpty,
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (val) {
                          setState(() => _showColEmpty = val ?? false);
                          menuSetState(() {});
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Filter by Class
    List<Map<String, dynamic>> filteredData = List.from(widget.results);
    if (_selectedClasses.isNotEmpty) {
      filteredData = filteredData
          .where((e) => _selectedClasses.contains(e['className']))
          .toList();
    }

    // Extract unique classes for filter
    final classes =
        widget.results
            .map((e) => e['className']?.toString() ?? '')
            .toSet()
            .toList()
          ..removeWhere((e) => e.isEmpty);
    classes.sort();

    return Scaffold(
      appBar: EduknAppBar(title: widget.examName),
      body: Column(
        children: [
          // Filter & Navigation Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: LayoutBuilder(
              builder: (context, barConstraints) {
                final isWide = barConstraints.maxWidth > 900;
                final isMedium = barConstraints.maxWidth > 650;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Sol Taraf: Mouse ile kaydırma ipucu ve Hızlı Yön Okları
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isMedium)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.indigo.shade100),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.pan_tool_alt_outlined,
                                      size: 14, color: Colors.indigo.shade700),
                                  const SizedBox(width: 6),
                                  Text(
                                    isWide
                                        ? 'Mouse ile basılı tutup her yöne kaydırabilirsiniz'
                                        : 'Mouse ile basılı tutup kaydırın',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.indigo.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(width: 8),
                          // Sola Kaydır Butonu
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_rounded,
                                size: 14),
                            tooltip: 'Tabloyu Sola Kaydır',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              if (_horizontalScrollController.hasClients) {
                                _horizontalScrollController.animateTo(
                                  (_horizontalScrollController.offset - 250)
                                      .clamp(
                                    0.0,
                                    _horizontalScrollController
                                        .position.maxScrollExtent,
                                  ),
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                );
                              }
                            },
                          ),
                          // Sağa Kaydır Butonu
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios_rounded,
                                size: 14),
                            tooltip: 'Tabloyu Sağa Kaydır',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              if (_horizontalScrollController.hasClients) {
                                _horizontalScrollController.animateTo(
                                  (_horizontalScrollController.offset + 250)
                                      .clamp(
                                    0.0,
                                    _horizontalScrollController
                                        .position.maxScrollExtent,
                                  ),
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    // Sağ Taraf: Filtreler
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Class Filter
                        _buildMultiSelectMenu(
                          label: 'Şube',
                          icon: Icons.maps_home_work_outlined,
                          items: classes,
                          selectedItems: _selectedClasses,
                          onForceRefresh: () => setState(() {}),
                          onChanged: (list) {
                            setState(() {
                              if (list.length == classes.length) {
                                _selectedClasses = [];
                              } else {
                                _selectedClasses = list;
                              }
                            });
                          },
                        ),
                        const SizedBox(width: 8),

                        // Subject Filter
                        _buildMultiSelectMenu(
                          label: 'Ders',
                          icon: Icons.menu_book_outlined,
                          items: widget.availableSubjects,
                          selectedItems: _selectedSubjects,
                          onForceRefresh: () => setState(() {}),
                          onChanged: (list) {
                            setState(() {
                              if (list.length ==
                                  widget.availableSubjects.length) {
                                _selectedSubjects = [];
                              } else {
                                _selectedSubjects = list;
                              }
                            });
                          },
                        ),
                        const SizedBox(width: 8),

                        // Column Visibility (D/Y/B) - Custom Multi Select Logic
                        _buildColumnVisibilityMenu(),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),

          // Table (Full Screen Width with 2D Mouse Drag Panning)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textSubjects = _selectedSubjects.isEmpty
                    ? widget.availableSubjects
                    : _selectedSubjects;

                return Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (event) {
                    if (event.buttons == kPrimaryMouseButton ||
                        event.kind == PointerDeviceKind.touch) {
                      _lastPanPosition = event.position;
                      _panDistance = 0.0;
                      _isPanning = false;
                    }
                  },
                  onPointerMove: (event) {
                    if (_lastPanPosition != null &&
                        (event.buttons == kPrimaryMouseButton ||
                            event.kind == PointerDeviceKind.touch)) {
                      final delta = event.position - _lastPanPosition!;
                      _lastPanPosition = event.position;
                      _panDistance += delta.distance;

                      if (!_isPanning && _panDistance > 3.0) {
                        if (mounted) setState(() => _isPanning = true);
                      }

                      // 1. Sağa / Sola Kaydırma (Horizontal Pan)
                      if (_horizontalScrollController.hasClients && delta.dx != 0) {
                        final maxH =
                            _horizontalScrollController.position.maxScrollExtent;
                        if (maxH > 0) {
                          final targetH = (_horizontalScrollController.offset -
                                  delta.dx)
                              .clamp(0.0, maxH);
                          _horizontalScrollController.jumpTo(targetH);
                        }
                      }

                      // 2. Yukarı / Aşağı Kaydırma (Vertical Pan)
                      if (_verticalScrollController.hasClients && delta.dy != 0) {
                        final maxV =
                            _verticalScrollController.position.maxScrollExtent;
                        if (maxV > 0) {
                          final targetV =
                              (_verticalScrollController.offset - delta.dy)
                                  .clamp(0.0, maxV);
                          _verticalScrollController.jumpTo(targetV);
                        }
                      }
                    }
                  },
                  onPointerUp: (event) {
                    _lastPanPosition = null;
                    _panDistance = 0.0;
                    if (_isPanning) {
                      if (mounted) setState(() => _isPanning = false);
                    }
                  },
                  onPointerCancel: (event) {
                    _lastPanPosition = null;
                    _panDistance = 0.0;
                    if (_isPanning) {
                      if (mounted) setState(() => _isPanning = false);
                    }
                  },
                  onPointerSignal: (pointerSignal) {
                    if (pointerSignal is PointerScrollEvent) {
                      // Shift + tekerlek yatay kaydırır
                      if (HardwareKeyboard.instance.isShiftPressed &&
                          pointerSignal.scrollDelta.dy != 0) {
                        if (_horizontalScrollController.hasClients) {
                          final maxH = _horizontalScrollController
                              .position.maxScrollExtent;
                          if (maxH > 0) {
                            final targetH = (_horizontalScrollController.offset +
                                    pointerSignal.scrollDelta.dy)
                                .clamp(0.0, maxH);
                            _horizontalScrollController.jumpTo(targetH);
                          }
                        }
                      }
                    }
                  },
                  child: MouseRegion(
                    cursor: _isPanning
                        ? SystemMouseCursors.grabbing
                        : MouseCursor.defer,
                    child: RawScrollbar(
                      controller: _verticalScrollController,
                      thumbVisibility: true,
                      thickness: 8,
                      radius: const Radius.circular(6),
                      thumbColor: Colors.indigo.shade300,
                      child: SingleChildScrollView(
                        controller: _verticalScrollController,
                        scrollDirection: Axis.vertical,
                        physics: const BouncingScrollPhysics(),
                        child: SizedBox(
                          width: constraints.maxWidth,
                          child: PaginatedDataTable(
                            controller: _horizontalScrollController,
                            header: Text(
                              _selectedSubjects.isEmpty
                                  ? 'Detaylı Sonuç Listesi (Tümü)'
                                  : '${_selectedSubjects.length} Ders Gösteriliyor',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            headingRowHeight: 65,
                            columns: _buildColumns(),
                            source: _ResultsDataSource(
                              filteredData,
                              availableSubjects: widget.availableSubjects,
                              displayedSubjects: textSubjects,
                              showCorrect: _showColCorrect,
                              showWrong: _showColWrong,
                              showEmpty: _showColEmpty,
                              onOpenReportCard: (studentData) {
                                if (widget.onOpenReportCard != null) {
                                  widget.onOpenReportCard!(studentData);
                                } else {
                                  _openDefaultReportCard(context, studentData);
                                }
                              },
                              onCompareStudent: (studentData) {
                                _openStudentComparison(context, studentData);
                              },
                            ),
                            rowsPerPage: _rowsPerPage,
                            availableRowsPerPage: const [10, 15, 20, 24, 50],
                            onRowsPerPageChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _rowsPerPage = val;
                                });
                              }
                            },
                            columnSpacing:
                                constraints.maxWidth > 1400 ? 28.0 : 16.0,
                            horizontalMargin: 20,
                            showCheckboxColumn: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openDefaultReportCard(BuildContext context, Map<String, dynamic> r) {
    if (widget.onOpenReportCard != null) {
      widget.onOpenReportCard!(r);
      return;
    }

    final answers = (r['answers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
        (r['cevaplar'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
        <String, String>{};

    final booklet = (r['booklet'] ?? 'A').toString();
    Map<String, String> correctAnswers = {};
    if (r['correctAnswers'] != null && r['correctAnswers'] is Map) {
      correctAnswers = (r['correctAnswers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    final Map<String, SubjectStats> subjectStats = {};
    if (r['subjects'] != null && r['subjects'] is Map) {
      (r['subjects'] as Map).forEach((k, v) {
        if (v is Map) {
          subjectStats[k.toString()] = SubjectStats(
            correct: int.tryParse(v['correct']?.toString() ?? '0') ?? 0,
            wrong: int.tryParse(v['wrong']?.toString() ?? '0') ?? 0,
            empty: int.tryParse(v['empty']?.toString() ?? '0') ?? 0,
            net: num.tryParse(v['net']?.toString() ?? '0')?.toDouble() ?? 0.0,
          );
        }
      });
    }

    final student = StudentResult(
      tcNo: (r['tcNo'] ?? '').toString(),
      studentNo: (r['studentNo'] ?? r['studentNumber'] ?? r['no'] ?? r['number'] ?? '').toString().trim(),
      name: (r['studentName'] ?? r['name'] ?? '').toString(),
      classLevel: (r['classLevel'] ?? '').toString(),
      branch: (r['className'] ?? r['branch'] ?? '').toString(),
      booklet: booklet,
      score: num.tryParse(r['totalScore']?.toString() ?? '0')?.toDouble() ?? 0.0,
      rankGeneral: r['rankGeneral'] ?? 0,
      rankInstitution: r['rankInstitution'] ?? r['rankGeneral'] ?? 0,
      rankBranch: r['rankBranch'] ?? 0,
      answers: answers,
      correctAnswers: correctAnswers,
      subjects: subjectStats,
    );

    final branchCount = widget.results.where((item) => item['className'] == r['className']).length;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => StudentReportCardDialog(
          student: student,
          examName: widget.examName,
          subjects: widget.availableSubjects,
          totalStudents: widget.results.length,
          schoolStudents: widget.results.length,
          branchStudents: branchCount,
          isRankingVisible: true,
          trialExamId: widget.currentExam?.id,
          schoolTypeName: _getEffectiveSchoolTypeName(student.classLevel),
        ),
      ),
    );
  }

  String _getEffectiveSchoolTypeName([String? studentLevel]) {
    if (widget.schoolTypeName != null &&
        widget.schoolTypeName!.trim().isNotEmpty &&
        widget.schoolTypeName!.trim().toLowerCase() != 'eğitim kurumu' &&
        widget.schoolTypeName!.trim().toLowerCase() != 'egitim kurumu') {
      return widget.schoolTypeName!.trim();
    }
    final level = studentLevel ?? widget.currentExam?.classLevel ?? '';
    final digits = RegExp(r'\d+').firstMatch(level)?.group(0);
    if (digits != null) {
      final grade = int.tryParse(digits);
      if (grade != null) {
        if (grade >= 1 && grade <= 4) return 'İlkokul';
        if (grade >= 5 && grade <= 8) return 'Ortaokul';
        if (grade >= 9 && grade <= 12) return 'Anadolu Lisesi';
      }
    }
    final clean = level.toLowerCase();
    if (clean.contains('anaokul') || clean.contains('kreş') || clean.contains('anasınıf')) return 'Anaokulu';
    if (clean.contains('ilkokul')) return 'İlkokul';
    if (clean.contains('ortaokul') || clean.contains('lgs')) return 'Ortaokul';
    if (clean.contains('lise') || clean.contains('yks') || clean.contains('tyt')) return 'Anadolu Lisesi';
    return 'Ortaokul';
  }

  void _openStudentComparison(BuildContext context, Map<String, dynamic> studentData) {
    if (widget.onCompareStudent != null) {
      widget.onCompareStudent!(studentData);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => StudentExamComparisonDialog(
        studentData: studentData,
        currentExam: widget.currentExam,
        currentExamName: widget.examName,
        allExams: widget.allExams ?? [],
        institutionId: widget.institutionId,
        availableSubjects: widget.availableSubjects,
      ),
    );
  }

  List<DataColumn> _buildColumns() {
    List<DataColumn> cols = [
      const DataColumn(
        label: Text('#', style: TextStyle(fontWeight: FontWeight.bold)),
        tooltip: 'Sıra No / Karşılaştır',
      ),
      const DataColumn(
        label: Text('Ad Soyad', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      const DataColumn(
        label: Text('Sınıf', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    ];

    // Determine which subjects to show
    List<String> textSubjects = _selectedSubjects.isEmpty
        ? widget.availableSubjects
        : _selectedSubjects;

    // Add columns for displayed subjects
    for (var subj in textSubjects) {
      cols.add(
        DataColumn(label: _buildStackedHeader(subj), tooltip: '$subj Detay'),
      );
    }

    if (_showColCorrect)
      cols.add(
        DataColumn(
          label: Text('Top D', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold)),
        ),
      );
    if (_showColWrong)
      cols.add(
        DataColumn(
          label: Text('Top Y', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
        ),
      );
    if (_showColEmpty)
      cols.add(
        DataColumn(
          label: Text('Top B', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
        ),
      );

    // Toplam Net
    cols.add(
      const DataColumn(
        label: Text('Top. Net', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );

    // Always Total Score at end
    cols.add(const DataColumn(label: Text('Puan', style: TextStyle(fontWeight: FontWeight.bold))));

    // New Ranks
    cols.add(
      const DataColumn(
        label: Text(
          'Genel Sıra',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
    cols.add(
      const DataColumn(
        label: Text('Şube Sıra', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );

    return cols;
  }

  Widget _buildStackedHeader(String subjectName) {
    bool anyDetail = _showColCorrect || _showColWrong || _showColEmpty;
    final shortName = _getSubjectShortName(subjectName);

    if (!anyDetail) {
      return Container(
        constraints: const BoxConstraints(minWidth: 55),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        child: Text(
          shortName,
          textAlign: TextAlign.center,
          maxLines: 1,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            shortName,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showColCorrect)
              const SizedBox(
                width: 32,
                child: Center(
                  child: Text(
                    "D",
                    style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            if (_showColWrong)
              const SizedBox(
                width: 32,
                child: Center(
                  child: Text(
                    "Y",
                    style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            if (_showColEmpty)
              const SizedBox(
                width: 32,
                child: Center(
                  child: Text(
                    "B",
                    style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            const SizedBox(
              width: 42,
              child: Center(
                child: Text(
                  "N",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ResultsDataSource extends DataTableSource {
  final List<Map<String, dynamic>> results;
  final List<String> availableSubjects;
  final List<String> displayedSubjects;
  final bool showCorrect;
  final bool showWrong;
  final bool showEmpty;
  final void Function(Map<String, dynamic> studentData)? onOpenReportCard;
  final void Function(Map<String, dynamic> studentData)? onCompareStudent;

  _ResultsDataSource(
    this.results, {
    required this.availableSubjects,
    required this.displayedSubjects,
    this.showCorrect = false,
    this.showWrong = false,
    this.showEmpty = false,
    this.onOpenReportCard,
    this.onCompareStudent,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= results.length) return null;
    final result = results[index];

    int displayIndex = index + 1;
    final studentNo = (result['studentNo'] ??
            result['studentNumber'] ??
            result['no'] ??
            result['number'] ??
            '')
        .toString()
        .trim();

    List<DataCell> cells = [
      DataCell(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: displayIndex <= 3
                    ? Colors.orange.shade100
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                displayIndex.toString(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: displayIndex <= 3 ? Colors.orange.shade900 : Colors.grey.shade800,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Öğrencinin Sınavlarını Karşılaştır',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onCompareStudent?.call(result),
                  borderRadius: BorderRadius.circular(14),
                  hoverColor: Colors.indigo.shade100,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFF6366F1), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.indigo.shade200.withValues(alpha: 0.35),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.compare_arrows_rounded,
                        size: 17,
                        color: Color(0xFF4338CA),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      DataCell(
        InkWell(
          onTap: () => onOpenReportCard?.call(result),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result['studentName']?.toString() ?? '-',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                if (studentNo.isNotEmpty && studentNo != displayIndex.toString())
                  Text(
                    'No: $studentNo',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
        ),
      ),
      DataCell(Text(result['className']?.toString() ?? '-')),
    ];


    Map<String, dynamic> subjectsMap = {};
    if (result['subjects'] != null && result['subjects'] is Map) {
      subjectsMap = result['subjects'];
    }

    // Loop through DISPLAYED subjects only
    for (var subj in displayedSubjects) {
      String netVal = '-';
      String c = '-', w = '-', e = '-';

      if (subjectsMap.containsKey(subj) && subjectsMap[subj] is Map) {
        final sData = subjectsMap[subj];
        double n =
            num.tryParse(sData['net']?.toString() ?? '0')?.toDouble() ?? 0.0;
        netVal = n.toStringAsFixed(2);

        int ci = int.tryParse(sData['correct']?.toString() ?? '0') ?? 0;
        int wi = int.tryParse(sData['wrong']?.toString() ?? '0') ?? 0;
        int ei = int.tryParse(sData['empty']?.toString() ?? '0') ?? 0;

        c = ci.toString();
        w = wi.toString();
        e = ei.toString();
      }

      // Build Cell Content
      bool anyDetail = showCorrect || showWrong || showEmpty;
      if (!anyDetail) {
        cells.add(
          DataCell(
            Center(
              child: Text(
                netVal,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );
      } else {
        cells.add(
          DataCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showCorrect)
                  Container(
                    width: 30,
                    child: Center(
                      child: Text(
                        c,
                        style: TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ),
                  ),
                if (showWrong)
                  Container(
                    width: 30,
                    child: Center(
                      child: Text(
                        w,
                        style: TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ),
                if (showEmpty)
                  Container(
                    width: 30,
                    child: Center(
                      child: Text(
                        e,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ),
                Container(
                  width: 40,
                  child: Center(
                    child: Text(
                      netVal,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    // Global Totals (Calculated from result item directly for accuracy)

    // Note: If we want to recalculate totals based on filtered subjects, we could.
    // But typically "Total Net" means Exam Total.
    // I will use the pre-calculated 'totalNet' from the record.

    int globalCorrect = 0, globalWrong = 0, globalEmpty = 0;
    // Recalculate global D/Y/B for display?
    // If the data source has it, better. BUT 'subjectsMap' has details.
    // Let's iterate ALL available subjects to get Global D/Y/B sums correctly, regardless of display.
    for (var subj in availableSubjects) {
      if (subjectsMap.containsKey(subj) && subjectsMap[subj] is Map) {
        final sData = subjectsMap[subj];
        globalCorrect += int.tryParse(sData['correct']?.toString() ?? '0') ?? 0;
        globalWrong += int.tryParse(sData['wrong']?.toString() ?? '0') ?? 0;
        globalEmpty += int.tryParse(sData['empty']?.toString() ?? '0') ?? 0;
      }
    }

    if (showCorrect)
      cells.add(
        DataCell(
          Text(globalCorrect.toString(), style: TextStyle(color: Colors.green)),
        ),
      );
    if (showWrong)
      cells.add(
        DataCell(
          Text(globalWrong.toString(), style: TextStyle(color: Colors.red)),
        ),
      );
    if (showEmpty)
      cells.add(
        DataCell(
          Text(globalEmpty.toString(), style: TextStyle(color: Colors.grey)),
        ),
      );

    double totalNet =
        double.tryParse(result['totalNet']?.toString() ?? '0') ?? 0.0;
    cells.add(
      DataCell(
        Text(
          totalNet.toStringAsFixed(2),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );

    double score =
        double.tryParse(result['totalScore']?.toString() ?? '0') ?? 0.0;
    cells.add(
      DataCell(
        Text(
          score.toStringAsFixed(3),
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
        ),
      ),
    );

    // Genel Sıra
    cells.add(
      DataCell(
        Center(
          child: Text(
            result['rankGeneral']?.toString() ?? '-',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );

    // Şube Sıra
    cells.add(
      DataCell(Center(child: Text(result['rankBranch']?.toString() ?? '-'))),
    );

    return DataRow(cells: cells);
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => results.length;
  @override
  int get selectedRowCount => 0;
}
