import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:edukn/widgets/safe_stream_builder.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../services/assessment_service.dart';
import '../../../../services/term_service.dart';
import '../../../../services/user_permission_service.dart';
import 'error_booklet_editor_screen.dart';
import 'error_booklet_student_list_screen.dart';

class ErrorBookletDashboardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String? schoolTypeName;
  final bool showAppBar;

  const ErrorBookletDashboardScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.schoolTypeName,
    this.showAppBar = true,
  }) : super(key: key);

  @override
  State<ErrorBookletDashboardScreen> createState() =>
      _ErrorBookletDashboardScreenState();
}

class _ErrorBookletDashboardScreenState
    extends State<ErrorBookletDashboardScreen> {
  final AssessmentService _assessmentService = AssessmentService();
  final Set<String> _selectedExamIds = {};
  final TextEditingController _searchController = TextEditingController();

  List<TrialExam> _allExams = [];
  List<String>? _filterClassLevels;
  String? _selectedLevelKey; // null = Tümü
  String _searchQuery = '';
  bool _isLoadingFilter = true;
  bool _viewAllTerms = false;
  String? _realInstitutionId;
  String? _activeTermId;
  Stream<List<TrialExam>>? _examsStream;
  final Map<String, int> _croppedCountsByExamId = {};
  final Set<String> _loadingCroppedCountExamIds = {};

  @override
  void initState() {
    super.initState();
    _loadFilterData();
  }

  @override
  void didUpdateWidget(covariant ErrorBookletDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.institutionId != widget.institutionId ||
        oldWidget.schoolTypeId != widget.schoolTypeId) {
      _croppedCountsByExamId.clear();
      _loadingCroppedCountExamIds.clear();
      _loadFilterData();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static String _normalizeLevelKey(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final lowered = trimmed
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase();
    final numMatch = RegExp(
      r'^(\d{1,2})\s*\.?\s*(sınıf|sinif)?$',
    ).firstMatch(lowered);
    if (numMatch != null) {
      return numMatch.group(1)!;
    }
    return trimmed;
  }

  static String _formatLevelLabel(String key) {
    if (int.tryParse(key) != null) {
      return '$key. Sınıf';
    }
    return key;
  }

  static int _compareLevelKeys(String a, String b) {
    final na = int.tryParse(a);
    final nb = int.tryParse(b);
    if (na != null && nb != null) return na.compareTo(nb);
    if (na != null) return -1;
    if (nb != null) return 1;
    return a.compareTo(b);
  }

  Future<void> _loadFilterData() async {
    if (!mounted) return;
    setState(() => _isLoadingFilter = true);
    try {
      if (widget.institutionId == 'SUPER_ADMIN') {
        _realInstitutionId = 'SUPER_ADMIN';
        _filterClassLevels = null;
      } else {
        final userData = await UserPermissionService.loadUserData();
        final userEmail =
            (userData?['email'] ?? FirebaseAuth.instance.currentUser?.email) ??
            '';
        _realInstitutionId = await UserPermissionService.resolveInstitutionId(
          userEmail,
          userData: userData,
        );

        if (widget.schoolTypeId.isNotEmpty &&
            widget.schoolTypeId != 'SUPER_ADMIN') {
          final stDoc = await FirebaseFirestore.instance
              .collection('schoolTypes')
              .doc(widget.schoolTypeId)
              .get();

          if (stDoc.exists) {
            final data = stDoc.data();
            if (data != null && data['activeGrades'] != null) {
              List<String> grades = List<String>.from(
                data['activeGrades'].map((e) => e.toString()),
              );

              if (userData != null &&
                  (userData['role'] == 'ogretmen' ||
                      userData['role'] == 'teacher')) {
                final classesQuery = await FirebaseFirestore.instance
                    .collection('classes')
                    .where('institutionId', isEqualTo: _realInstitutionId)
                    .where(
                      'classTeacherId',
                      isEqualTo: userData['authUserId'] ?? userData['id'],
                    )
                    .get();

                if (classesQuery.docs.isNotEmpty) {
                  final teacherGrades = classesQuery.docs
                      .map((d) => d['classLevel'].toString())
                      .toSet();
                  grades = grades
                      .where((g) => teacherGrades.contains(g))
                      .toList();

                  if (grades.isEmpty && teacherGrades.isNotEmpty) {
                    grades = teacherGrades.toList();
                  }
                }
              }
              _filterClassLevels = grades;
            }
          }
        }
      }
      _activeTermId =
          await TermService().getSelectedTermId() ??
          await TermService().getActiveTermId();
      _loadExams();
    } catch (e) {
      debugPrint('Error loading filter data: $e');
      _loadExams();
    } finally {
      if (mounted) setState(() => _isLoadingFilter = false);
    }
  }

  void _loadExams() {
    final effectiveInstId = _realInstitutionId ?? widget.institutionId;
    _examsStream = _assessmentService.getTrialExams(
      effectiveInstId,
      classLevels: _filterClassLevels,
      termId: effectiveInstId == 'SUPER_ADMIN'
          ? null
          : (_viewAllTerms ? null : _activeTermId),
    );
  }

  void _ensureCroppedCountsLoaded(List<TrialExam> exams) {
    final toLoad = <TrialExam>[];
    for (final ex in exams) {
      if (!_croppedCountsByExamId.containsKey(ex.id) &&
          !_loadingCroppedCountExamIds.contains(ex.id)) {
        _loadingCroppedCountExamIds.add(ex.id);
        toLoad.add(ex);
      }
    }
    if (toLoad.isEmpty) return;
    Future.microtask(() async {
      const int chunkSize = 8;
      for (int i = 0; i < toLoad.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, toLoad.length);
        final chunk = toLoad.sublist(i, end);
        await Future.wait(
          chunk.map((ex) => _fetchCroppedCountForExam(ex, notify: false)),
        );
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _fetchCroppedCountForExam(
    TrialExam exam, {
    bool notify = true,
  }) async {
    try {
      final uniqueKeys = <String>{};
      void collectDocs(QuerySnapshot<Map<String, dynamic>> snap) {
        for (final doc in snap.docs) {
          final data = doc.data();
          final subj = (data['subject'] ?? '').toString().trim().toLowerCase();
          final qNo = (data['questionNo'] ?? '').toString().trim();
          uniqueKeys.add(
            subj.isNotEmpty || qNo.isNotEmpty ? '${subj}_$qNo' : doc.id,
          );
        }
      }

      final centralId = (exam.centralExamId ?? '').trim();
      if (exam.isCentralExam && centralId.isNotEmpty && centralId != exam.id) {
        final centralSnap = await FirebaseFirestore.instance
            .collection('trial_exams')
            .doc(centralId)
            .collection('questions_pool')
            .get();
        collectDocs(centralSnap);
      }

      final localSnap = await FirebaseFirestore.instance
          .collection('trial_exams')
          .doc(exam.id)
          .collection('questions_pool')
          .get();
      collectDocs(localSnap);

      _croppedCountsByExamId[exam.id] = uniqueKeys.length;
    } catch (_) {
      _croppedCountsByExamId.putIfAbsent(exam.id, () => 0);
    } finally {
      _loadingCroppedCountExamIds.remove(exam.id);
      if (notify && mounted) {
        setState(() {});
      }
    }
  }

  List<String> _buildAvailableLevelKeys(List<TrialExam> exams) {
    final keys = <String>{};
    if (_filterClassLevels != null) {
      for (final g in _filterClassLevels!) {
        final k = _normalizeLevelKey(g);
        if (k.isNotEmpty) keys.add(k);
      }
    }
    for (final e in exams) {
      final k = _normalizeLevelKey(e.classLevel);
      if (k.isNotEmpty) keys.add(k);
    }
    final sorted = keys.toList()..sort(_compareLevelKeys);
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 640;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: widget.showAppBar
          ? EduknAppBar(
              title: 'Hata Kitapçığı Yönetimi',
              subtitle: widget.schoolTypeName,
              actions: [
                if (_selectedExamIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_selectedExamIds.length} Sınav Seçildi',
                              style: GoogleFonts.inter(
                                color: Colors.indigo.shade700,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () =>
                                  setState(() => _selectedExamIds.clear()),
                              child: Icon(
                                Icons.close_rounded,
                                size: 15,
                                color: Colors.indigo.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : null,
      body: _isLoadingFilter
          ? const Center(child: CircularProgressIndicator())
          : SafeStreamBuilder<List<TrialExam>>(
              stream: _examsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                _allExams = snapshot.data ?? [];
                _ensureCroppedCountsLoaded(_allExams);
                final levelKeys = _buildAvailableLevelKeys(_allExams);

                // Sınıf başına sınav sayıları
                final countByLevel = <String, int>{};
                for (final ex in _allExams) {
                  final k = _normalizeLevelKey(ex.classLevel);
                  if (k.isNotEmpty) {
                    countByLevel[k] = (countByLevel[k] ?? 0) + 1;
                  }
                }

                final q = _searchQuery.trim().toLowerCase();
                final visibleExams = _allExams.where((ex) {
                  if (_selectedLevelKey != null) {
                    if (_normalizeLevelKey(ex.classLevel) !=
                        _selectedLevelKey) {
                      return false;
                    }
                  }
                  if (q.isNotEmpty) {
                    final hay = '${ex.name} ${ex.examTypeName} ${ex.classLevel}'
                        .toLowerCase();
                    if (!hay.contains(q)) return false;
                  }
                  return true;
                }).toList();

                return Column(
                  children: [
                    _buildTopFilterBar(
                      isMobile: isMobile,
                      levelKeys: levelKeys,
                      countByLevel: countByLevel,
                      totalCount: _allExams.length,
                    ),
                    Expanded(
                      child: visibleExams.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: EdgeInsets.fromLTRB(
                                isMobile ? 14 : 24,
                                8,
                                isMobile ? 14 : 24,
                                96,
                              ),
                              itemCount: visibleExams.length,
                              itemBuilder: (context, index) {
                                return _buildExamCard(visibleExams[index]);
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
      floatingActionButton: _selectedExamIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _openStudentListForSelected,
              backgroundColor: Colors.indigo,
              icon: const Icon(Icons.auto_awesome, color: Colors.white),
              label: Text(
                _selectedExamIds.length == 1
                    ? 'Öğrenci Listesi'
                    : 'Karma Kitapçık Oluştur (${_selectedExamIds.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildTopFilterBar({
    required bool isMobile,
    required List<String> levelKeys,
    required Map<String, int> countByLevel,
    required int totalCount,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 24,
        14,
        isMobile ? 14 : 24,
        12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.filter_alt_outlined,
                size: 18,
                color: Colors.indigo.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                'Sınıf Seviyesi',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.indigo.shade900,
                ),
              ),
              const Spacer(),
              if (!isMobile) SizedBox(width: 280, child: _buildSearchField()),
            ],
          ),
          if (isMobile) ...[const SizedBox(height: 10), _buildSearchField()],
          if (levelKeys.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildLevelChip(
                    label: 'Tümü',
                    count: totalCount,
                    isSelected: _selectedLevelKey == null,
                    onTap: () => setState(() => _selectedLevelKey = null),
                  ),
                  ...levelKeys.map((lvlKey) {
                    final cnt = countByLevel[lvlKey] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _buildLevelChip(
                        label: _formatLevelLabel(lvlKey),
                        count: cnt,
                        isSelected: _selectedLevelKey == lvlKey,
                        onTap: () {
                          setState(() {
                            _selectedLevelKey = _selectedLevelKey == lvlKey
                                ? null
                                : lvlKey;
                          });
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _searchQuery = v),
      style: GoogleFonts.inter(
        fontSize: 13.4,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF0F172A),
      ),
      decoration: InputDecoration(
        hintText: 'Sınav adı veya türü ara...',
        hintStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF94A3B8),
        ),
        isDense: true,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 10, right: 8),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.search_rounded,
              size: 16,
              color: Color(0xFF4F46E5),
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 34,
        ),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 17,
                  color: Color(0xFF64748B),
                ),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        hoverColor: const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD5DFEC), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD5DFEC), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.8),
        ),
      ),
    );
  }

  Widget _buildLevelChip({
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo.shade600 : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.indigo.shade600 : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : Colors.blueGrey.shade800,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : Colors.indigo.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasFilter =
        _selectedLevelKey != null || _searchQuery.trim().isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            hasFilter
                ? 'Seçilen sınıf seviyesinde veya aramada sınav bulunamadı.'
                : 'Henüz tanımlanmış sınav bulunmuyor.',
            style: GoogleFonts.inter(color: Colors.grey.shade500),
          ),
          if (hasFilter) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _selectedLevelKey = null;
                  _searchQuery = '';
                });
              },
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text('Filtreyi Temizle'),
            ),
          ],
        ],
      ),
    );
  }

  void _openStudentListForSelected() {
    final selectedExams = _allExams
        .where((e) => _selectedExamIds.contains(e.id))
        .toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ErrorBookletStudentListScreen(exams: selectedExams),
      ),
    );
  }

  Widget _buildExamCard(TrialExam exam) {
    final bool isSelected = _selectedExamIds.contains(exam.id);
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final String normalizedLevel = _normalizeLevelKey(exam.classLevel);
    final String levelLabel = normalizedLevel.isNotEmpty
        ? _formatLevelLabel(normalizedLevel)
        : '';

    return Container(
      margin: EdgeInsets.only(bottom: isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isSelected ? Colors.indigo : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedExamIds.remove(exam.id);
            } else {
              _selectedExamIds.add(exam.id);
            }
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: isSelected,
                  activeColor: Colors.indigo,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedExamIds.add(exam.id);
                      } else {
                        _selectedExamIds.remove(exam.id);
                      }
                    });
                  },
                ),
              ),
              SizedBox(width: isMobile ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (levelLabel.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              levelLabel,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.indigo.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            exam.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: isMobile ? 13 : 16,
                              color: Colors.indigo.shade900,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Builder(
                      builder: (context) {
                        final count = _croppedCountsByExamId[exam.id] ?? 0;
                        final total = _getTotalQuestions(exam);
                        final formattedDate =
                            '${exam.date.day}/${exam.date.month}/${exam.date.year}';

                        return Text(
                          '${exam.examTypeName} - $formattedDate - $count/$total',
                          style: GoogleFonts.inter(
                            fontSize: isMobile ? 10 : 12,
                            fontWeight: FontWeight.w400,
                            color: Colors.blueGrey.shade500,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
                child: IconButton(
                  icon: Icon(
                    Icons.design_services_outlined,
                    color: Colors.indigo,
                    size: isMobile ? 18 : 20,
                  ),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => ErrorBookletEditorScreen(exam: exam),
                      ),
                    );
                    if (mounted) {
                      _fetchCroppedCountForExam(exam);
                    }
                  },
                  constraints: BoxConstraints(
                    minWidth: isMobile ? 32 : 38,
                    minHeight: isMobile ? 32 : 38,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'Soruları Kırp',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _getTotalQuestions(TrialExam exam) {
    if (exam.answerKeys.isEmpty) return 0;
    try {
      final firstBooklet = exam.answerKeys.keys.first;
      final subjects = exam.answerKeys[firstBooklet] ?? {};
      int total = 0;
      subjects.forEach((_, answers) => total += answers.trim().length);
      return total;
    } catch (e) {
      return 0;
    }
  }
}
