import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../constants/turkey_address_data.dart';
import '../../../models/assessment/central_exam_model.dart';
import '../../../models/assessment/exam_type_model.dart';
import '../../../services/central_assessment_service.dart';
import '../../school/assessment/trial_exam_answer_key_screen.dart';

class CentralExamWizardScreen extends StatefulWidget {
  final CentralExam? existingExam;

  const CentralExamWizardScreen({super.key, this.existingExam});

  @override
  State<CentralExamWizardScreen> createState() =>
      _CentralExamWizardScreenState();
}

class _CentralExamWizardScreenState extends State<CentralExamWizardScreen> {
  final _formKey = GlobalKey<FormState>();
  final CentralAssessmentService _service = CentralAssessmentService();

  late TextEditingController _nameController;
  late TextEditingController _durationController;
  final TextEditingController _schoolSearchController = TextEditingController();

  static const List<String> _classLevelOptions = [
    '5. Sınıf',
    '6. Sınıf',
    '7. Sınıf',
    '8. Sınıf',
    '9. Sınıf',
    '10. Sınıf',
    '11. Sınıf',
    '12. Sınıf',
    'Mezun',
  ];

  String _selectedClassLevel = '8. Sınıf';
  String? _selectedExamTypeId;
  String _selectedExamTypeName = '';
  int _bookletCount = 2;
  int _sessionCount = 1;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));

  Map<String, Map<String, String>> _answerKeys = {};
  Map<String, Map<String, List<String>>> _outcomes = {};
  Map<String, Map<String, String>> _bookletMapping = {};

  List<ExamType> _examTypes = [];
  List<CentralSchoolNode> _schools = [];
  final Map<String, CentralExamTarget> _selectedTargetsByTypeId = {};

  // Filters for Target Selector
  String _regionFilter = 'Tümü';
  String _cityFilter = 'Tümü';
  String _categoryFilter = 'Tümü';
  String _searchQuery = '';

  bool _isLoadingData = true;
  bool _isSaving = false;
  bool _isCreatingTemplate = false;
  final bool _isActive = true;
  StreamSubscription<List<ExamType>>? _examTypesSub;

  @override
  void initState() {
    super.initState();
    final ex = widget.existingExam;
    _nameController = TextEditingController(text: ex?.name ?? '');
    _durationController = TextEditingController(
      text: '${ex?.durationMinutes ?? 120}',
    );

    if (ex != null) {
      _selectedClassLevel = _classLevelOptions.contains(ex.classLevel)
          ? ex.classLevel
          : '8. Sınıf';
      _selectedExamTypeId = ex.examTypeId.isNotEmpty ? ex.examTypeId : null;
      _selectedExamTypeName = ex.examTypeName;
      _bookletCount = ex.bookletCount.clamp(1, 4);
      _sessionCount = ex.sessionCount.clamp(1, 2);
      _selectedDate = ex.date;
      _answerKeys = _deepCopyAnswerKeys(ex.answerKeys);
      _outcomes = _deepCopyOutcomes(ex.outcomes);
      _bookletMapping = _deepCopyAnswerKeys(ex.bookletMapping);
      for (final t in ex.targets) {
        _selectedTargetsByTypeId[t.schoolTypeId] = t;
      }
    }

    _schoolSearchController.addListener(() {
      setState(() {
        _searchQuery = _schoolSearchController.text.trim().toLowerCase();
      });
    });

    _loadInitialData();
  }

  Map<String, Map<String, String>> _deepCopyAnswerKeys(
    Map<String, Map<String, String>> src,
  ) {
    final out = <String, Map<String, String>>{};
    src.forEach((b, subjs) {
      out[b] = Map<String, String>.from(subjs);
    });
    return out;
  }

  Map<String, Map<String, List<String>>> _deepCopyOutcomes(
    Map<String, Map<String, List<String>>> src,
  ) {
    final out = <String, Map<String, List<String>>>{};
    src.forEach((b, subjs) {
      final sm = <String, List<String>>{};
      subjs.forEach((s, list) {
        sm[s] = List<String>.from(list);
      });
      out[b] = sm;
    });
    return out;
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingData = true);
    try {
      await _examTypesSub?.cancel();
      _examTypesSub = _service.streamHqExamTypes().listen((types) {
        if (!mounted) return;
        setState(() {
          _examTypes = types;
          if (_selectedExamTypeId != null &&
              !_examTypes.any((t) => t.id == _selectedExamTypeId)) {
            // Keep selected ID if existingExam had it, or select first if null
          } else if (_selectedExamTypeId == null && _examTypes.isNotEmpty) {
            _selectedExamTypeId = _examTypes.first.id;
            _selectedExamTypeName = _examTypes.first.name;
          }
        });
      });

      final tree = await _service.fetchSchoolsTree();
      if (mounted) {
        setState(() {
          _schools = tree;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingData = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veriler yüklenirken hata oluştu: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _examTypesSub?.cancel();
    _nameController.dispose();
    _durationController.dispose();
    _schoolSearchController.dispose();
    super.dispose();
  }

  Future<void> _createQuickTemplate(String templateKey) async {
    setState(() => _isCreatingTemplate = true);
    try {
      final created = await _service.createStandardExamTypeTemplate(
        templateKey,
      );
      if (!mounted) return;
      setState(() {
        if (!_examTypes.any((e) => e.id == created.id)) {
          _examTypes = [..._examTypes, created];
        }
        _selectedExamTypeId = created.id;
        _selectedExamTypeName = created.name;
        if (templateKey == 'LGS') {
          _selectedClassLevel = '8. Sınıf';
          _sessionCount = 2;
          _durationController.text = '155';
        } else if (templateKey == 'TYT') {
          _selectedClassLevel = '12. Sınıf';
          _sessionCount = 1;
          _durationController.text = '165';
        } else if (templateKey == 'AYT') {
          _selectedClassLevel = '12. Sınıf';
          _sessionCount = 1;
          _durationController.text = '180';
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${created.name}" sınav türü şablonu oluşturuldu.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Şablon oluşturma hatası: $e')));
      }
    } finally {
      if (mounted) setState(() => _isCreatingTemplate = false);
    }
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (!mounted) return;

    setState(() {
      _selectedDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime?.hour ?? _selectedDate.hour,
        pickedTime?.minute ?? _selectedDate.minute,
      );
    });
  }

  Future<void> _openAnswerKeyEditor() async {
    if (_selectedExamTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen önce sınav türünü seçiniz.')),
      );
      return;
    }

    ExamType? examType;
    for (final et in _examTypes) {
      if (et.id == _selectedExamTypeId) {
        examType = et;
        break;
      }
    }

    if (examType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seçili sınav türü bulunamadı.')),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrialExamAnswerKeyScreen(
          bookletCount: _bookletCount,
          examType: examType!,
          classLevel: _selectedClassLevel,
          initialAnswerKeys: _answerKeys,
          initialOutcomes: _outcomes,
          initialMapping: _bookletMapping,
        ),
      ),
    );

    if (result is Map && mounted) {
      final newKeys = <String, Map<String, String>>{};
      if (result['answerKeys'] is Map) {
        (result['answerKeys'] as Map).forEach((b, sMap) {
          if (sMap is Map) {
            newKeys[b.toString()] = sMap.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            );
          }
        });
      }

      final newOutcomes = <String, Map<String, List<String>>>{};
      if (result['outcomes'] is Map) {
        (result['outcomes'] as Map).forEach((b, sMap) {
          if (sMap is Map) {
            final sub = <String, List<String>>{};
            sMap.forEach((k, v) {
              if (v is List) {
                sub[k.toString()] = v.map((e) => e.toString()).toList();
              }
            });
            newOutcomes[b.toString()] = sub;
          }
        });
      }

      final newMapping = <String, Map<String, String>>{};
      if (result['bookletMapping'] is Map) {
        (result['bookletMapping'] as Map).forEach((b, sMap) {
          if (sMap is Map) {
            newMapping[b.toString()] = sMap.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            );
          }
        });
      }

      setState(() {
        _answerKeys = newKeys;
        _outcomes = newOutcomes;
        _bookletMapping = newMapping;
      });
    }
  }

  List<CentralSchoolNode> _getFilteredSchools([String? cityFilterOverride]) {
    final activeCityFilter = cityFilterOverride ?? _cityFilter;
    return _schools.where((s) {
      if (_regionFilter != 'Tümü' && s.region != _regionFilter) return false;
      if (activeCityFilter != 'Tümü' &&
          TurkeyAddressData.toUpperTr(s.city) != activeCityFilter) {
        return false;
      }
      if (_categoryFilter != 'Tümü') {
        final hasCat = s.schoolTypes.any((t) => t.category == _categoryFilter);
        if (!hasCat) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final hay =
            '${s.schoolName} ${s.institutionId} ${s.city} ${s.district} ${s.region}'
                .toLowerCase();
        final typeMatch = s.schoolTypes.any(
          (t) => t.schoolTypeName.toLowerCase().contains(_searchQuery),
        );
        if (!hay.contains(_searchQuery) && !typeMatch) return false;
      }
      return true;
    }).toList();
  }

  List<CentralSchoolTypeNode> _visibleTypesForSchool(CentralSchoolNode school) {
    if (_categoryFilter == 'Tümü') return school.schoolTypes;
    return school.schoolTypes
        .where((t) => t.category == _categoryFilter)
        .toList();
  }

  void _toggleSchoolType(
    CentralSchoolNode school,
    CentralSchoolTypeNode st,
    bool select,
  ) {
    setState(() {
      if (select) {
        final examId = widget.existingExam?.id ?? 'pending';
        _selectedTargetsByTypeId[st.schoolTypeId] = CentralExamTarget(
          schoolId: school.schoolId,
          institutionId: school.institutionId,
          schoolName: school.schoolName,
          schoolTypeId: st.schoolTypeId,
          schoolTypeName: st.schoolTypeName,
          schoolTypeCategory: st.category,
          city: school.city,
          district: school.district,
          region: school.region,
          childTrialExamId: CentralExamTarget.buildChildDocId(
            examId,
            st.schoolTypeId,
          ),
        );
      } else {
        _selectedTargetsByTypeId.remove(st.schoolTypeId);
      }
    });
  }

  void _selectByCategory(String category, [String? effectiveCityFilter]) {
    setState(() {
      final examId = widget.existingExam?.id ?? 'pending';
      final filteredSet = category == 'ALL_FILTERED'
          ? _getFilteredSchools(effectiveCityFilter).toSet()
          : const <CentralSchoolNode>{};
      for (final school in _schools) {
        if (category == 'ALL_FILTERED' && !filteredSet.contains(school)) {
          continue;
        }
        final visibleSet = category == 'ALL_FILTERED'
            ? _visibleTypesForSchool(school).toSet()
            : const <CentralSchoolTypeNode>{};
        for (final st in school.schoolTypes) {
          if (category == 'ALL_FILTERED') {
            if (!visibleSet.contains(st)) continue;
          } else if (st.category != category) {
            continue;
          }
          _selectedTargetsByTypeId[st.schoolTypeId] = CentralExamTarget(
            schoolId: school.schoolId,
            institutionId: school.institutionId,
            schoolName: school.schoolName,
            schoolTypeId: st.schoolTypeId,
            schoolTypeName: st.schoolTypeName,
            schoolTypeCategory: st.category,
            city: school.city,
            district: school.district,
            region: school.region,
            childTrialExamId: CentralExamTarget.buildChildDocId(
              examId,
              st.schoolTypeId,
            ),
          );
        }
      }
    });
  }

  int get _selectedUniqueSchoolCount {
    return _selectedTargetsByTypeId.values
        .map((t) => t.schoolId)
        .toSet()
        .length;
  }

  int get _filledAnswerKeySubjectsCount {
    final keysA = _answerKeys['A'] ?? {};
    return keysA.values.where((v) => v.trim().isNotEmpty).length;
  }

  Future<void> _saveExam() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedExamTypeId == null || _selectedExamTypeId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir sınav türü seçiniz.')),
      );
      return;
    }

    ExamType? selectedExamType;
    for (final et in _examTypes) {
      if (et.id == _selectedExamTypeId) {
        selectedExamType = et;
        break;
      }
    }

    if (_isActive) {
      final keysA = _answerKeys['A'] ?? const <String, String>{};
      final missingDetails = <String>[];
      if (selectedExamType != null && selectedExamType.subjects.isNotEmpty) {
        for (final subj in selectedExamType.subjects) {
          final enteredLen = (keysA[subj.branchName] ?? '').trim().length;
          if (enteredLen < subj.questionCount) {
            missingDetails.add(
              '• ${subj.branchName}: $enteredLen / ${subj.questionCount} soru',
            );
          }
        }
      } else if (keysA.values.every((v) => v.trim().isEmpty)) {
        missingDetails.add('• A kitapçığı cevap anahtarı henüz girilmemiş.');
      }

      if (missingDetails.isNotEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Cevap Anahtarı Eksik'),
            content: Text(
              'A kitapçığı için bazı branşların cevap anahtarı eksik veya boş görünüyor:\n\n'
              '${missingDetails.take(8).join('\n')}\n\n'
              'Cevap anahtarı tamamlanmadan okullar optik değerlendirme yapamaz. Yine de kaydetmek ve okullara tanımlamak istiyor musunuz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  minimumSize: const Size(0, 38),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Yine de Kaydet'),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final duration = int.tryParse(_durationController.text.trim()) ?? 120;
      final targets = _selectedTargetsByTypeId.values.toList();

      final draft = CentralExam(
        id: widget.existingExam?.id ?? '',
        name: _nameController.text.trim(),
        classLevel: _selectedClassLevel,
        examTypeId: _selectedExamTypeId!,
        examTypeName: _selectedExamTypeName,
        bookletCount: _bookletCount,
        sessionCount: _sessionCount,
        durationMinutes: duration,
        date: _selectedDate,
        answerKeys: _answerKeys,
        outcomes: _outcomes,
        bookletMapping: _bookletMapping,
        targets: targets,
        isPublished: widget.existingExam?.isPublished ?? false,
        status: widget.existingExam?.status ?? 'draft',
        totalParticipants: widget.existingExam?.totalParticipants ?? 0,
        participatingSchoolsCount:
            widget.existingExam?.participatingSchoolsCount ?? 0,
        lastEvaluatedAt: widget.existingExam?.lastEvaluatedAt,
        analyticsSummary: widget.existingExam?.analyticsSummary ?? const {},
        termId: widget.existingExam?.termId,
        createdAt: widget.existingExam?.createdAt ?? DateTime.now(),
      );

      final saved = await _service.saveAndProvisionCentralExam(draft);
      if (!mounted) return;

      final uniqueSchools = saved.targets.map((t) => t.schoolId).toSet().length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved.targets.isEmpty
                ? 'Merkezi deneme taslak olarak kaydedildi.'
                : '$uniqueSchools okulun ${saved.targets.length} okul türüne merkezi deneme otomatik tanımlandı!',
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
      Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kaydetme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableCities =
        _schools
            .where((s) => _regionFilter == 'Tümü' || s.region == _regionFilter)
            .map((s) => TurkeyAddressData.toUpperTr(s.city))
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    final effectiveCityFilter =
        (_cityFilter != 'Tümü' && availableCities.contains(_cityFilter))
        ? _cityFilter
        : 'Tümü';
    final isCompactHeader = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existingExam == null
                  ? 'Yeni Merkezi Deneme Sınavı Oluştur'
                  : 'Merkezi Deneme Düzenle & Okul Ata',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              'Genel Merkez Ölçme Değerlendirme Yönetimi',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveExam,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.rocket_launch_rounded, size: 18),
              label: Text(
                _isSaving
                    ? 'Kaydediliyor...'
                    : (isCompactHeader ? 'Kaydet' : 'Kaydet ve Okullara Tanımla'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                minimumSize: const Size(0, 38),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildStep1BasicInfoCard(),
                      const SizedBox(height: 20),
                      _buildStep2AnswerKeyCard(),
                      const SizedBox(height: 20),
                      _buildStep3TargetSelectorCard(
                        availableCities,
                        effectiveCityFilter,
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildStep1BasicInfoCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            step: '1',
            title: 'Deneme Sınavı Kimlik ve Oturum Bilgileri',
            subtitle:
                'Sınav adı, hedef sınıf seviyesi, merkezi sınav türü, oturum ve kitapçık ayarlarını belirleyin.',
            color: const Color(0xFF4F46E5),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Merkezi Deneme Adı',
              hintText: 'Örn: Türkiye Geneli LGS Kurumsal Deneme - 1',
              prefixIcon: const Icon(
                Icons.assignment_outlined,
                color: Color(0xFF4F46E5),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Deneme adı zorunludur'
                : null,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 680;
              final classDropdown = DropdownButtonFormField<String>(
                initialValue: _selectedClassLevel,
                decoration: InputDecoration(
                  labelText: 'Sınıf Seviyesi',
                  prefixIcon: const Icon(
                    Icons.school_outlined,
                    color: Color(0xFF4F46E5),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: _classLevelOptions
                    .map(
                      (lvl) => DropdownMenuItem(value: lvl, child: Text(lvl)),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedClassLevel = val);
                },
              );

              final examTypeDropdown = DropdownButtonFormField<String>(
                initialValue: _examTypes.any((e) => e.id == _selectedExamTypeId)
                    ? _selectedExamTypeId
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Merkezi Sınav Türü (Branş & Katsayı Şablonu)',
                  prefixIcon: const Icon(
                    Icons.tune_rounded,
                    color: Color(0xFF4F46E5),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                hint: const Text(
                  'Sınav türü seçin veya aşağıdan şablon ekleyin',
                ),
                items: _examTypes
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(
                          '${e.name} (${e.subjects.length} Ders)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  final found = _examTypes.firstWhere((e) => e.id == val);
                  setState(() {
                    _selectedExamTypeId = val;
                    _selectedExamTypeName = found.name;
                  });
                },
              );

              if (isWide) {
                return Row(
                  children: [
                    Expanded(flex: 2, child: classDropdown),
                    const SizedBox(width: 16),
                    Expanded(flex: 3, child: examTypeDropdown),
                  ],
                );
              }
              return Column(
                children: [
                  classDropdown,
                  const SizedBox(height: 16),
                  examTypeDropdown,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          // Quick Standard ExamType Template Generator Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFC7D2FE)),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFF4F46E5),
                  size: 18,
                ),
                Text(
                  'Hızlı Sınav Türü Şablonu Oluştur:',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF312E81),
                  ),
                ),
                _templateChipButton('LGS', 'LGS (8. Sınıf)'),
                _templateChipButton('TYT', 'TYT (120 Soru)'),
                _templateChipButton('AYT', 'AYT (160 Soru)'),
                _templateChipButton('ORTAOKUL', '5-6-7 Kurumsal'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(
                width: 250,
                child: InkWell(
                  onTap: _pickDateTime,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Uygulama Tarihi ve Saati',
                      prefixIcon: const Icon(
                        Icons.calendar_today_rounded,
                        color: Color(0xFF4F46E5),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      DateFormat('dd.MM.yyyy HH:mm').format(_selectedDate),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextFormField(
                  controller: _durationController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Süre (Dakika)',
                    prefixIcon: const Icon(
                      Icons.timer_outlined,
                      color: Color(0xFF4F46E5),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                  initialValue: _sessionCount,
                  decoration: InputDecoration(
                    labelText: 'Oturum Sayısı',
                    prefixIcon: const Icon(
                      Icons.layers_outlined,
                      color: Color(0xFF4F46E5),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 Oturum')),
                    DropdownMenuItem(value: 2, child: Text('2 Oturum')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _sessionCount = v);
                  },
                ),
              ),
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<int>(
                  initialValue: _bookletCount,
                  decoration: InputDecoration(
                    labelText: 'Kitapçık Türü Sayısı',
                    prefixIcon: const Icon(
                      Icons.menu_book_rounded,
                      color: Color(0xFF4F46E5),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 (A)')),
                    DropdownMenuItem(value: 2, child: Text('2 (A - B)')),
                    DropdownMenuItem(value: 3, child: Text('3 (A - B - C)')),
                    DropdownMenuItem(
                      value: 4,
                      child: Text('4 (A - B - C - D)'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _bookletCount = v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _templateChipButton(String key, String label) {
    return ActionChip(
      avatar: _isCreatingTemplate
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_circle_outline, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: Colors.white,
      onPressed: _isCreatingTemplate ? null : () => _createQuickTemplate(key),
    );
  }

  Widget _buildStep2AnswerKeyCard() {
    final filledCount = _filledAnswerKeySubjectsCount;
    final hasKey = filledCount > 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            step: '2',
            title:
                'Merkezi Cevap Anahtarı, Kazanım ve B/C/D Kitapçık Eşleştirme',
            subtitle:
                'Girilen cevap anahtarı ve kazanımlar atanan tüm okullara salt-okunur olarak kilitli şekilde aktarılır.',
            color: const Color(0xFF0D9488),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _openAnswerKeyEditor,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: hasKey
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasKey
                      ? const Color(0xFF6EE7B7)
                      : const Color(0xFFCBD5E1),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isStacked = constraints.maxWidth < 580;
                  final actionButton = ElevatedButton.icon(
                    onPressed: _openAnswerKeyEditor,
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: Text(hasKey ? 'Düzenle' : 'Cevap Anahtarı Gir'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasKey
                          ? const Color(0xFF059669)
                          : const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      minimumSize: const Size(0, 38),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                  final infoRow = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: hasKey
                              ? const Color(0xFF059669)
                              : const Color(0xFF4F46E5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.fact_check_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasKey
                                  ? 'Cevap Anahtarı Hazır ($filledCount Branş Tanımlandı)'
                                  : 'Cevap Anahtarı ve Kazanım Tablosunu Düzenle',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Excel şablonu ile toplu yükleme yapabilir, A kitapçığından B/C/D dönüşümlerini ve kazanım eşleştirmelerini tanımlayabilirsiniz.',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  if (isStacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        infoRow,
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: actionButton,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: infoRow),
                      const SizedBox(width: 12),
                      actionButton,
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3TargetSelectorCard(
    List<String> availableCities,
    String effectiveCityFilter,
  ) {
    final filteredSchools = _getFilteredSchools(effectiveCityFilter);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _sectionHeader(
                  step: '3',
                  title: 'Hedef Okul ve Okul Türü (Kademe) Seçimi',
                  subtitle:
                      'Bölge, il veya okul türü kategorisine göre filtreleyerek sınavı tek tıkla hedef kademelere tanımlayın.',
                  color: const Color(0xFFD97706),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: Text(
                  '$_selectedUniqueSchoolCount Okul • ${_selectedTargetsByTypeId.length} Kademe Seçildi',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: const Color(0xFF3730A3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Quick Bulk Selection Buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _selectByCategory('Ortaokul'),
                icon: const Icon(Icons.check_box_outlined, size: 16),
                label: const Text('Tüm Ortaokulları Seç'),
              ),
              OutlinedButton.icon(
                onPressed: () => _selectByCategory('Lise'),
                icon: const Icon(Icons.check_box_outlined, size: 16),
                label: const Text('Tüm Liseleri Seç'),
              ),
              OutlinedButton.icon(
                onPressed: () => _selectByCategory('İlkokul'),
                icon: const Icon(Icons.check_box_outlined, size: 16),
                label: const Text('Tüm İlkokulları Seç'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _selectByCategory('ALL_FILTERED', effectiveCityFilter),
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: const Text('Filtrelenenleri Seç'),
              ),
              if (_selectedTargetsByTypeId.isNotEmpty)
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _selectedTargetsByTypeId.clear()),
                  icon: const Icon(
                    Icons.clear_all_rounded,
                    color: Colors.red,
                    size: 18,
                  ),
                  label: const Text(
                    'Seçimi Temizle',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Filter Controls Row
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _regionFilter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Bölge Filtresi',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'Tümü',
                      child: Text('Tüm Bölgeler'),
                    ),
                    ...TurkeyAddressData.regions.map(
                      (r) => DropdownMenuItem(value: r, child: Text(r)),
                    ),
                    const DropdownMenuItem(
                      value: 'Belirtilmemiş',
                      child: Text('Belirtilmemiş'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _regionFilter = val;
                        _cityFilter = 'Tümü';
                      });
                    }
                  },
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('city_$effectiveCityFilter'),
                  initialValue: effectiveCityFilter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'İl Filtresi',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'Tümü',
                      child: Text('Tüm İller'),
                    ),
                    ...availableCities.map(
                      (c) => DropdownMenuItem(value: c, child: Text(c)),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _cityFilter = val);
                  },
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _categoryFilter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Okul Türü Kategorisi',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Tümü',
                      child: Text('Tüm Kademeler'),
                    ),
                    DropdownMenuItem(
                      value: 'Ortaokul',
                      child: Text('Ortaokul'),
                    ),
                    DropdownMenuItem(value: 'Lise', child: Text('Lise')),
                    DropdownMenuItem(value: 'İlkokul', child: Text('İlkokul')),
                    DropdownMenuItem(
                      value: 'Anaokulu',
                      child: Text('Anaokulu'),
                    ),
                    DropdownMenuItem(
                      value: 'Kurs Merkezi',
                      child: Text('Kurs Merkezi'),
                    ),
                    DropdownMenuItem(value: 'Diğer', child: Text('Diğer')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _categoryFilter = val);
                  },
                ),
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _schoolSearchController,
                  decoration: InputDecoration(
                    hintText: 'Okul adı, kurum kodu veya ilçe ara...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (filteredSchools.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Filtre kriterlerine uygun okul veya okul türü bulunamadı.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            )
          else
            SizedBox(
              height: 480,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ListView.separated(
                  shrinkWrap: false,
                  itemCount: filteredSchools.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  itemBuilder: (context, idx) {
                    final school = filteredSchools[idx];
                    final visibleTypes = _visibleTypesForSchool(school);
                    final selectedInSchool = visibleTypes
                        .where(
                          (t) => _selectedTargetsByTypeId.containsKey(
                            t.schoolTypeId,
                          ),
                        )
                        .length;
                    final allSelected =
                        visibleTypes.isNotEmpty &&
                        selectedInSchool == visibleTypes.length;
                    final someSelected = selectedInSchool > 0 && !allSelected;

                    return ExpansionTile(
                      initiallyExpanded: filteredSchools.length <= 6,
                      leading: Checkbox(
                        tristate: true,
                        value: allSelected
                            ? true
                            : (someSelected ? null : false),
                        onChanged: visibleTypes.isEmpty
                            ? null
                            : (val) {
                                final shouldSelect = val == true;
                                for (final st in visibleTypes) {
                                  _toggleSchoolType(school, st, shouldSelect);
                                }
                              },
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              school.schoolName,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${school.region} • ${school.city.isNotEmpty ? school.city : "-"}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        visibleTypes.isEmpty
                            ? 'Bu okula tanımlı aktif okul türü bulunmuyor.'
                            : '${visibleTypes.length} okul türü • Seçilen: $selectedInSchool',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      children: visibleTypes.map((st) {
                        final isChecked = _selectedTargetsByTypeId.containsKey(
                          st.schoolTypeId,
                        );
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: const EdgeInsets.only(
                            left: 40,
                            right: 20,
                          ),
                          value: isChecked,
                          onChanged: (v) =>
                              _toggleSchoolType(school, st, v == true),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  st.schoolTypeName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isChecked
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isChecked
                                        ? const Color(0xFF312E81)
                                        : const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  st.category,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF4338CA),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: st.activeGrades.isNotEmpty
                              ? Text(
                                  'Sınıflar: ${st.activeGrades.join(", ")}',
                                  style: const TextStyle(fontSize: 11),
                                )
                              : null,
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required String step,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            step,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
