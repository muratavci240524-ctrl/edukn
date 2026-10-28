import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
import '../../../../services/assessment_service.dart';
import '../../../../services/announcement_service.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../models/assessment/exam_type_model.dart';
import '../../../../models/assessment/optical_form_model.dart';
import 'trial_exam_answer_key_screen.dart';
import '../../../../services/term_service.dart';
import '../../../../services/crypto_service.dart';
import '../../../../services/user_permission_service.dart';

import 'student_report_card_dialog.dart';
import 'evaluation_models.dart';
import 'unmatched_students_dialog.dart';
import 'matched_students_dialog.dart';
import 'absent_students_dialog.dart';
import 'stats_bottom_sheet.dart';
import 'optical_data_editor_screen.dart';
import 'package:edukn/services/optical_line_edits.dart';

class TrialExamForm extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final TrialExam? trialExam;
  final VoidCallback onSuccess;
  final bool
  isExamExecution; // NEW: Determines if this forms acts as "Sınav" (true) or "Deneme Tanımı" (false)

  const TrialExamForm({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
    this.trialExam,
    required this.onSuccess,
    this.isExamExecution = false,
  }) : super(key: key);

  @override
  State<TrialExamForm> createState() => _TrialExamFormState();
}

class _TrialExamFormState extends State<TrialExamForm>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final AssessmentService _service = AssessmentService();

  late TextEditingController _nameController;
  String? _examId; // Local ID state

  String? _selectedClassLevel;
  String? _selectedExamTypeId;
  String _selectedExamTypeName = '';
  TrialExamApplicationType _applicationType = TrialExamApplicationType.optical;
  int _bookletCount = 1;
  int _sessionCount = 1;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay(hour: 09, minute: 30);
  bool _isPublished = false;
  bool _isLaunched = false; // Local state for launched status

  // Booklet -> Subject -> AnswerString
  Map<String, Map<String, String>> _answerKeys = {};
  // Booklet -> Subject -> List<Outcome>
  Map<String, Map<String, List<String>>> _outcomes = {};
  // Booklet -> Subject -> MappingString
  Map<String, Map<String, String>> _bookletMapping = {};

  List<ExamType> _examTypes = [];
  List<String> _classLevels = [];
  List<String> _availableBranches = []; // NEW
  List<String> _selectedBranches = []; // NEW
  List<OpticalForm> _opticalForms = [];

  // Session Management
  List<TrialExamSession> _sessions = [];

  final Map<int, dynamic> _selectedFiles = {};
  String? _currentResultsJson;

  bool _isLoading = false;
  bool _isInfoExpanded = true;
  Map<String, dynamic> _sharingSettings =
      {}; // NEW: Local sharing settings state

  // Matching Stats
  int _totalSystemStudents = 0;
  int _participatingStudents = 0;
  int _matchedCount = 0;
  int _unmatchedCount = 0;
  final List<Map<String, dynamic>> _absentStudents = [];
  Map<String, Map<String, dynamic>> _systemStudentsMap =
      {}; // ID -> Student Data (Target Grade)
  Map<String, Map<String, dynamic>> _allSchoolStudentsMap =
      {}; // ID -> Student Data (All School Students)

  // Handled Results (Active State)
  List<StudentResult> _currentResults = [];

  @override
  void initState() {
    super.initState();
    _initForm();
    _loadExamTypes();
    _loadClassLevels();
    _loadOpticalForms();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TrialExamForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trialExam?.id != widget.trialExam?.id) {
      _initForm();
    }
  }

  void _initForm() {
    _examId = widget.trialExam?.id; // Initialize ID from widget
    _nameController = TextEditingController(text: widget.trialExam?.name ?? '');

    if (widget.trialExam != null) {
      _selectedClassLevel = widget.trialExam!.classLevel;
      _selectedExamTypeId = widget.trialExam!.examTypeId;
      _selectedExamTypeName = widget.trialExam!.examTypeName;
      _applicationType = widget.trialExam!.applicationType;
      _bookletCount = widget.trialExam!.bookletCount;
      _sessionCount = widget.trialExam!.sessionCount;
      _selectedDate = widget.trialExam!.date;
      _selectedTime = TimeOfDay.fromDateTime(widget.trialExam!.date);
      _isPublished = widget.trialExam!.isPublished;
      _isLaunched = widget.trialExam!.isLaunched; // Initialize
      _currentResultsJson = widget.trialExam!.resultsJson;

      // Restore results if available
      if (_currentResultsJson != null && _currentResultsJson!.isNotEmpty) {
        try {
          final List<dynamic> jsonList = jsonDecode(_currentResultsJson!);
          _currentResults = jsonList
              .map((e) => StudentResult.fromJson(e))
              .toList();
          _recalculateStats();
        } catch (e) {
          debugPrint("Error restoring results: $e");
        }
      }

      _sharingSettings = Map<String, dynamic>.from(
        widget.trialExam!.sharingSettings,
      );

      // If editing an existing exam, collapse info by default
      _isInfoExpanded = false;

      _answerKeys = Map.from(widget.trialExam!.answerKeys);
      _outcomes = Map.from(widget.trialExam!.outcomes);
      _bookletMapping = Map.from(widget.trialExam!.bookletMapping);

      if (widget.trialExam!.sessions.isNotEmpty) {
        _sessions = widget.trialExam!.sessions
            .map(
              (s) => TrialExamSession(
                sessionNumber: s.sessionNumber,
                selectedSubjects: List.from(s.selectedSubjects),
                opticalFormId: s.opticalFormId,
                opticalFormName: s.opticalFormName,
                fileName: s.fileName,
                fileUrl: s.fileUrl,
                uploadedAt: s.uploadedAt,
                lineEdits: List.from(s.lineEdits),
              ),
            )
            .toList();
      } else {
        _adjustSessionsList();
      }

      _selectedBranches = List.from(
        widget.trialExam!.selectedBranches,
      ); // Load saved branches
      _loadBranches(); // Fetch available options
    } else {
      _selectedClassLevel = null;
      _selectedExamTypeId = null;
      _selectedExamTypeName = '';
      _applicationType = TrialExamApplicationType.optical;
      _bookletCount = 1;
      _sessionCount = 1;
      _selectedDate = DateTime.now();
      _selectedTime = TimeOfDay(hour: 09, minute: 30);
      _isPublished = false;
      _isInfoExpanded = true;
      _answerKeys = {};
      _outcomes = {};
      _selectedBranches = [];
      _sharingSettings = {};
      _adjustSessionsList();
    }
  }

  void _adjustSessionsList() {
    if (_sessions.length < _sessionCount) {
      for (int i = _sessions.length; i < _sessionCount; i++) {
        _sessions.add(TrialExamSession(sessionNumber: i + 1));
      }
    } else if (_sessions.length > _sessionCount) {
      _sessions.removeRange(_sessionCount, _sessions.length);
    }
  }

  Future<void> _loadBranches() async {
    if (_selectedClassLevel == null) return;
    try {
      final instVariants = UserPermissionService.getInstitutionIdVariants(widget.institutionId);
      final targetInstId = instVariants.isNotEmpty ? instVariants.first : widget.institutionId;

      final snapshot = instVariants.length > 1
          ? await FirebaseFirestore.instance
              .collection('classes')
              .where('institutionId', whereIn: instVariants)
              .where('isActive', isEqualTo: true)
              .get()
          : await FirebaseFirestore.instance
              .collection('classes')
              .where('institutionId', isEqualTo: targetInstId)
              .where('isActive', isEqualTo: true)
              .get();

      // Robust matching: Compare only digits
      final selectedDigits = _selectedClassLevel!.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );

      final branches = snapshot.docs
          .where((doc) {
            final data = doc.data();
            final level = (data['classLevel'] ?? '').toString();
            final levelDigits = level.replaceAll(RegExp(r'[^0-9]'), '');
            final name = (data['className'] ?? '').toString();
            final nameDigits = RegExp(r'^\d+').firstMatch(name)?.group(0) ?? '';
            return (levelDigits == selectedDigits || nameDigits == selectedDigits) &&
                selectedDigits.isNotEmpty;
          })
          .map((doc) => doc.data()['className'].toString())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();

      branches.sort();

      if (mounted) {
        setState(() {
          _availableBranches = branches;
        });
        _fetchSystemStudents();
      }
    } catch (e) {
      debugPrint('Error loading branches: $e');
    }
  }

  void _showBranchSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final allSelected =
                _selectedBranches.length == _availableBranches.length;
            return AlertDialog(
              title: Text("Şube Seçimi"),
              content: Container(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: Checkbox(
                        value: allSelected,
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              _selectedBranches = List.from(_availableBranches);
                            } else {
                              _selectedBranches.clear();
                            }
                          });
                          setState(() {}); // Update Main UI Text
                        },
                      ),
                      title: Text("Tümünü Seç"),
                    ),
                    Divider(),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _availableBranches.length,
                        itemBuilder: (context, index) {
                          final branch = _availableBranches[index];
                          final isSelected = _selectedBranches.contains(branch);
                          return CheckboxListTile(
                            title: Text(branch),
                            value: isSelected,
                            onChanged: (val) {
                              setDialogState(() {
                                if (val == true) {
                                  _selectedBranches.add(branch);
                                } else {
                                  _selectedBranches.remove(branch);
                                }
                              });
                              setState(() {}); // Update Main UI Text
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
                  onPressed: () {
                    Navigator.pop(context);
                    _fetchSystemStudents(); // Update stats on close
                  },
                  child: Text("Tamam"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _loadClassLevels() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final Set<String> allGrades = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['activeGrades'] != null) {
          final grades = (data['activeGrades'] as List).map(
            (e) => e.toString(),
          );
          allGrades.addAll(grades);
        }
      }

      final sortedGrades = allGrades.toList();

      // Sort helper to handle numeric class levels correctly (e.g. 5. Sınıf, 10. Sınıf)
      sortedGrades.sort((a, b) {
        final int? aNum = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), ''));
        final int? bNum = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), ''));

        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum);
        }
        return a.compareTo(b);
      });

      if (mounted) {
        setState(() {
          _classLevels = sortedGrades;
        });
      }
    } catch (e) {
      debugPrint('Error loading class levels: $e');
    }
  }

  Future<void> _loadExamTypes() async {
    _service.getExamTypes(widget.institutionId).listen((types) {
      if (mounted) {
        setState(() {
          _examTypes = types;
        });
      }
    });
  }

  Future<void> _loadOpticalForms() async {
    _service
        .getOpticalForms(widget.institutionId)
        .listen(
          (forms) {
            if (mounted) {
              setState(() {
                _opticalForms = forms;
              });
            }
          },
          onError: (e) {
            debugPrint('Error loading optical forms: $e');
            if (mounted) {
              String message = 'Optik formlar yüklenirken hata oluştu: $e';
              if (e.toString().contains('permission-denied')) {
                message =
                    'Optik formları görüntüleme yetkiniz yok. Lütfen okul yöneticisiyle iletişime geçin.';
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 5),
                  action: SnackBarAction(
                    label: 'Tamam',
                    textColor: Colors.white,
                    onPressed: () {},
                  ),
                ),
              );
            }
          },
        );
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.indigo,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: _selectedTime,
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: Colors.indigo,
                onPrimary: Colors.white,
                onSurface: Colors.black,
              ),
            ),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        setState(() {
          _selectedDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
          _selectedTime = pickedTime;
        });
      }
    }
  }

  void _openAnswerKeyScreen() async {
    if (_selectedExamTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lütfen önce sınav türünü seçiniz.')),
      );
      return;
    }

    final selectedExamType = _examTypes.cast<ExamType?>().firstWhere(
      (e) => e?.id == _selectedExamTypeId,
      orElse: () => null,
    );

    if (selectedExamType == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TrialExamAnswerKeyScreen(
          bookletCount: _bookletCount,
          examType: selectedExamType,
          classLevel: _selectedClassLevel ?? widget.trialExam?.classLevel ?? '',
          initialAnswerKeys: _answerKeys,
          initialOutcomes: _outcomes,
          initialMapping: _bookletMapping,
        ),
      ),
    );

    if (result != null && result is Map) {
      final newAnswerKeys = (result['answerKeys'] as Map).map(
        (key, value) => MapEntry(
          key.toString(),
          (value as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
        ),
      );

      final newOutcomes = (result['outcomes'] as Map).map(
        (key, value) => MapEntry(
          key.toString(),
          (value as Map).map(
            (k, v) => MapEntry(
              k.toString(),
              (v as List).map((e) => e.toString()).toList(),
            ),
          ),
        ),
      );

      final newMapping = (result['bookletMapping'] as Map?)?.map(
            (key, value) => MapEntry(
              key.toString(),
              (value as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
            ),
          ) ??
          {};

      setState(() {
        _answerKeys = newAnswerKeys;
        _outcomes = newOutcomes;
        _bookletMapping = newMapping;
      });
    }
  }

  Future<void> _pickSessionFile(int index) async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'dat'],
        withData: true,
      );

      if (result != null) {
        final file = result.files.single;

        // Sadece yerel state'e kaydet
        setState(() {
          if (file.bytes != null || file.path != null) {
            _selectedFiles[index] = file;
          }

          final oldSession = _sessions[index];
          _sessions[index] = TrialExamSession(
            sessionNumber: oldSession.sessionNumber,
            selectedSubjects: oldSession.selectedSubjects,
            opticalFormId: oldSession.opticalFormId,
            opticalFormName: oldSession.opticalFormName,
            fileName: file.name,
            fileUrl: null,
            uploadedAt: DateTime.now(),
            // Aynı dosya yeniden yüklenirse düzeltmeler korunur; farklı dosyada
            // parmak izi tutmadığı için uygulanmaz.
            lineEdits: oldSession.lineEdits,
          );
        });

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.hourglass_top, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '"${file.name}" okunuyor, eşleşmeler hesaplanıyor...',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.indigo,
            duration: Duration(seconds: 3),
          ),
        );

        // Öğrenci listesi henüz yoksa çek
        if (_systemStudentsMap.isEmpty && _selectedClassLevel != null) {
          await _fetchSystemStudents();
        }

        // Ön eşleşme: istatistikleri dosya yüklenir yüklenmez göster
        await _previewMatchSession(index);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dosya seçimi hatası: $e')));
    }
  }

  /// Dosya seçildiğinde anlık ön eşleşme yapar.
  /// Sonuçları _currentResults'a ekler ama KAYDETMEZ.
  /// Kullanıcı eşleşmeyenleri düzelttikten sonra "Sınavı Değerlendir" ile kaydeder.
  Future<void> _previewMatchSession(int sessionIndex) async {
    final session = _sessions[sessionIndex];
    if (!_selectedFiles.containsKey(sessionIndex)) return;
    if (session.opticalFormId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uyarı: Optik form seçilmeden eşleşme yapılamaz.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Öğrenci listesi boşsa çek
    if (_systemStudentsMap.isEmpty && _selectedClassLevel != null) {
      await _fetchSystemStudents();
    }

    final matcher = StudentMatcher(
      _allSchoolStudentsMap.isNotEmpty
          ? _allSchoolStudentsMap.values
          : _systemStudentsMap.values,
    );

    // Bu oturumu işle (sonuçları kaydetme, sadece önizle)
    final touched = <String>{};
    final sessionResult = await _processSessionSingle(
      session,
      sessionIndex,
      matcher,
      null, // No examType for preview
      (_) {}, // İlerleme geri bildirimi gerekmiyor
      touchedKeys: touched,
    );

    if (sessionResult.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Dosya okundu ancak öğrenci verisi bulunamadı. Optik form ayarlarını kontrol edin.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    // Mevcut sonuçlara bu oturumu ekle/güncelle (overwrite this session's data)
    final Map<String, StudentResult> merged = {};
    // Önce mevcut sonuçları al
    for (var r in _currentResults) {
      final key = r.isMatched && r.systemStudentId != null
          ? r.systemStudentId!
          : r.tcNo.isNotEmpty
          ? 'UNMATCHED_TC_${r.tcNo}'
          : r.studentNo.isNotEmpty
          ? 'UNMATCHED_NO_${r.studentNo}'
          : 'UNKNOWN_${r.name}';
      merged[key] = r;
    }
    for (final k in touched) {
      merged.remove(k);
    }
    // Yeni oturumu ekle
    sessionResult.forEach((key, student) {
      merged[key] = student;
    });

    if (mounted) {
      setState(() {
        _currentResults = merged.values.toList();
        _recalculateStats();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${sessionResult.length} öğrenci bulundu. '
                  'Eşleşmeyen varsa düzeltin, sonra "Sınavı Değerlendir"e basın.',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  /// Dosyayı arka planda Firebase Storage'a yükler.
  /// Değerlendirme sürecini bloke etmez.
  /// Yükleme tamamlanınca session URL'si güncellenir ve Firestore'a sessizce kaydedilir.
  void _uploadFileInBackground({
    required Reference storageRef,
    required dynamic fileData,
    required int sessionIndex,
    required TrialExamSession session,
  }) {
    Future<void> doUpload() async {
      String? downloadUrl;
      try {
        if (kIsWeb) {
          if (fileData is PlatformFile && fileData.bytes != null) {
            await storageRef.putData(
              fileData.bytes!,
              SettableMetadata(contentType: 'text/plain'),
            );
            downloadUrl = await storageRef.getDownloadURL();
          }
        } else if (fileData is PlatformFile && fileData.bytes != null) {
          await storageRef.putData(
            fileData.bytes!,
            SettableMetadata(contentType: 'text/plain'),
          );
          downloadUrl = await storageRef.getDownloadURL();
        }

        if (downloadUrl != null && mounted) {
          // URL güncelle
          setState(() {
            _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
              fileUrl: downloadUrl,
              uploadedAt: DateTime.now(),
            );
          });

          // Firestore'a sessizce yeniden kaydet (sadece URL güncellemesi için)
          _saveData(showFeedback: false, silent: true);
          debugPrint('✅ Dosya arka planda yüklendi: $downloadUrl');
        }
      } catch (e) {
        // Sessizce hata yut — kullanıcı zaten yerel dosyayla çalışıyor
        debugPrint('⚠️ Arka plan yükleme hatası (önemli değil): $e');
      }
    }

    // Fire-and-forget
    doUpload();
  }

  Future<void> _removeSessionFile(int index) async {
    final session = _sessions[index];
    // 1. Delete from Storage if URL exists
    if (session.fileUrl != null) {
      try {
        await FirebaseStorage.instance.refFromURL(session.fileUrl!).delete();
      } catch (e) {
        debugPrint("Delete storage error: $e"); // Ignore if already gone
      }
    }

    // 2. Update Local State
    setState(() {
      _sessions[index] = TrialExamSession(
        sessionNumber: session.sessionNumber,
        selectedSubjects: session.selectedSubjects,
        opticalFormId: session.opticalFormId,
        opticalFormName: session.opticalFormName,
        fileName: null,
        fileUrl: null,
        uploadedAt: null,
        lineEdits: session.lineEdits,
      );
      _selectedFiles.remove(index);
    });

    // 3. Save to Firestore
    await _saveData(showFeedback: false);
    if (mounted) ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Dosya kaldırıldı.')));
  }

  Future<void> _publishExam() async {
    if (!_formKey.currentState!.validate()) return;

    // Validations (must have exam type etc)
    if (_selectedExamTypeId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sınav türü seçiniz.')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sınav Olarak Aç'),
        content: Text(
          'Bu denemeyi yayınlamak ve aktif sınav moduna geçirmek istiyor musunuz? Sınavlar listesinde görünecektir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Onayla'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isPublished = false; // Do not publish automatically
        _isLaunched = true; // NEW: Mark as launched/active
      });
      await _saveData(showFeedback: true);
      // Optional: The parent widget likely re-renders or navigates based on saved data.
      // If we need to trigger a mode switch, saving with ID usually suffices if the parent handles it.
      // But typically this button is only visible in "Definition" mode.
    }
  }

  Future<void> _saveData({
    bool showFeedback = true,
    bool silent = false,
    bool onlySettings = false,
  }) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      if (onlySettings && _examId != null) {
        // Optimization: Only update sharing settings to avoid sending massive resultsJson
        await _service.updateTrialExamSharingSettings(
          _examId!,
          _sharingSettings,
          _isPublished,
        );
      } else {
        // 1. Upload Files to Storage in background (fire-and-forget)
        if (_selectedFiles.isNotEmpty) {
          final entries = _selectedFiles.entries.toList();
          for (var entry in entries) {
            final index = entry.key;
            final fileData = entry.value;
            final session = _sessions[index];

            if (session.fileUrl != null &&
                session.fileUrl!.startsWith('http')) {
              continue;
            }

            if (session.fileName == null) continue;

            _examId ??= DateTime.now().millisecondsSinceEpoch.toString();

            final storageRef = FirebaseStorage.instance
                .ref()
                .child('trial_exams')
                .child(_examId!)
                .child('${session.sessionNumber}_${session.fileName}');

            _uploadFileInBackground(
              storageRef: storageRef,
              fileData: fileData,
              sessionIndex: index,
              session: session,
            );
          }
        }

        // Encode results only when saving to improve performance (Main Isolate Block Prevention)
        String? finalResultsJson = _currentResultsJson;
        if (_currentResults.isNotEmpty) {
          // Use compute to prevent main thread freeze for large lists
          finalResultsJson = await compute(_encodeResults, _currentResults);

          // Warning: Firestore has a 1MB limit per document.
          if (finalResultsJson!.length > 900000) {
            debugPrint(
              "WARNING: resultsJson is quite large (${finalResultsJson.length} bytes)",
            );
            if (finalResultsJson.length > 1048000) {
              throw "Hata: Öğrenci sonuç verisinden kaynaklı dosya boyutu 1MB sınırını aştı. Lütfen daha az öğrenci veya oturum ile deneyin.";
            }
          }
        }

        // Aktif / seçili dönem ID'sini al veya mevcut sınavın termId'sini koru
        final activeTermId = widget.trialExam?.termId ?? await TermService().getSelectedTermId() ?? await TermService().getActiveTermId();

        final exam = TrialExam(
          id: _examId ?? '', // Use consistent ID
          institutionId: widget.institutionId,
          name: _nameController.text.trim(),
          classLevel: _selectedClassLevel!,
          examTypeId: _selectedExamTypeId!,
          examTypeName: _selectedExamTypeName,
          applicationType: _applicationType,
          bookletCount: _bookletCount,
          sessionCount: _sessionCount,
          answerKeys: _answerKeys,
          outcomes: _outcomes,
          sessions: _sessions,
          selectedBranches: _selectedBranches,
          date: _selectedDate,
          isActive: true,
          isPublished: _isPublished,
          isLaunched: _isLaunched,
          resultsJson: finalResultsJson,
          sharingSettings: _sharingSettings,
          bookletMapping: _bookletMapping,
          termId: activeTermId,
        );

        await _service.saveTrialExam(exam);
      }

      if (showFeedback && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Kaydedildi.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteTrialExam() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sınavı Sil'),
        content: Text(
          'Bu sınavı ve tüm verilerini silmek istediğinize emin misiniz? Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Sil',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        if (_examId != null) {
          await _service.deleteTrialExam(_examId!);
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Sınav silindi.')));
          Navigator.pop(context); // Return to list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Hata: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Center(child: CircularProgressIndicator());

    // Determine if we show Execution tools (Sessions) or Definition tools (Publish button)
    final bool showExecution = widget.isExamExecution;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header / Save Button Row
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_examId != null) // Only show delete for existing exams
                  TextButton.icon(
                    onPressed: _deleteTrialExam,
                    icon: Icon(Icons.delete_forever, color: Colors.red),
                    label: Text(
                      'Sınavı Kaldır',
                      style: TextStyle(color: Colors.red),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                if (widget.trialExam != null) SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _saveData(showFeedback: true),
                  icon: Icon(Icons.save),
                  label: Text('KAYDET'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(),
                  if (_selectedExamTypeId != null) ...[
                    SizedBox(height: 24),
                    _buildAnswerKeyCard(),

                    if (!showExecution) ...[
                      // Definition Mode: Show Publish Button
                      SizedBox(height: 24),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: _publishExam,
                          icon: Icon(Icons.rocket_launch),
                          label: Text('SINAV OLARAK AÇ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            textStyle: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],

                    if (showExecution) ...[
                      // Execution Mode: Show Sessions and Evaluation Tools
                      SizedBox(height: 24),
                      _buildSessionManagement(),
                      SizedBox(height: 24),
                      _buildEvaluationStatistics(),
                      SizedBox(height: 32),
                      _buildActionButtons(),
                      SizedBox(height: 32),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            'Deneme Sınavı Bilgileri',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
          initiallyExpanded: _isInfoExpanded,
          onExpansionChanged: (v) => setState(() => _isInfoExpanded = v),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  Divider(height: 1),
                  SizedBox(height: 20),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Sınav Adı',
                      hintText: 'Örn: 8. Sınıf LGS Deneme 1',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.description, color: Colors.indigo),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (v) => v!.isEmpty ? 'Zorunlu' : null,
                  ),
                  SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Class Level
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedClassLevel,
                          decoration: InputDecoration(
                            labelText: 'Sınıf Seviyesi',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          onChanged: (value) {
                            setState(() {
                              _selectedClassLevel = value;
                              _selectedBranches.clear();
                            });
                            _loadBranches();
                            _fetchSystemStudents();
                          },
                          items: _classLevels
                              .map(
                                (level) => DropdownMenuItem(
                                  value: level,
                                  child: Text(
                                    "${level.replaceAll('. Sınıf', '')}. Sınıf",
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),

                      SizedBox(width: 16),

                      // Branch Selection
                      Expanded(
                        child: InkWell(
                          onTap:
                              _selectedClassLevel != null &&
                                  _availableBranches.isNotEmpty
                              ? _showBranchSelectionDialog
                              : null,
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Şube Seçimi',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: _selectedClassLevel == null
                                  ? Colors.grey[200]
                                  : Colors.grey[50],
                              suffixIcon: Icon(Icons.arrow_drop_down),
                            ),
                            child: Text(
                              _selectedClassLevel == null
                                  ? 'Önce Sınıf Seçiniz'
                                  : _availableBranches.isEmpty
                                  ? 'Şube bulunamadı'
                                  : _selectedBranches.isEmpty
                                  ? 'Tüm Şubeler (${_availableBranches.length} Adet)'
                                  : '${_selectedBranches.length} Şube Seçildi',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _selectedClassLevel == null
                                    ? Colors.grey
                                    : _availableBranches.isEmpty
                                    ? Colors.red.shade400
                                    : _selectedBranches.isEmpty
                                    ? Colors.grey.shade700
                                    : Colors.black,
                                fontWeight:
                                    _selectedBranches.isNotEmpty &&
                                        _selectedClassLevel != null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedExamTypeId,
                    items: _examTypes
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(e.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedExamTypeId = v;
                        if (v != null) {
                          _selectedExamTypeName = _examTypes
                              .firstWhere((e) => e.id == v)
                              .name;
                          if (widget.trialExam?.examTypeId != v) {
                            _answerKeys = {};
                            _outcomes = {};
                          }
                        }
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Sınav Türü',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: _buildBookletCountSelector()),
                      SizedBox(width: 16),
                      Expanded(child: _buildSessionCountSelector()),
                    ],
                  ),
                  SizedBox(height: 20),
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Sınav Tarihi ve Saati',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: Icon(
                          Icons.calendar_today,
                          color: Colors.indigo,
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      child: Text(
                        DateFormat('dd.MM.yyyy HH:mm').format(_selectedDate),
                        style: TextStyle(fontSize: 16),
                      ),
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

  Widget _buildAnswerKeyCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: _openAnswerKeyScreen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.fact_check, color: Colors.indigo, size: 32),
              ),
              SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cevap Anahtarı ve Kazanım Tablosu',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Cevap anahtarlarını, soru eşleşmelerini ve kazanımları buradan yönetebilirsiniz.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionManagement() {
    final selectedExam = _examTypes.firstWhere(
      (e) => e.id == _selectedExamTypeId,
      orElse: () => ExamType(
        id: '',
        institutionId: '',
        name: '',
        subjects: [],
        isActive: true,
      ),
    );
    final subjects = selectedExam.subjects.map((s) => s.branchName).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Oturum Yönetimi',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
        SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            // Determine column count based on available width
            final int crossAxisCount = constraints.maxWidth > 850 ? 2 : 1;
            final double spacing = 16.0;
            // Calculate item width: (Total Width - Total Spacing) / Count
            final double itemWidth =
                (constraints.maxWidth - (crossAxisCount - 1) * spacing) /
                crossAxisCount;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: List.generate(_sessions.length, (index) {
                final session = _sessions[index];
                return SizedBox(
                  width: itemWidth,
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.indigo,
                                child: Text(
                                  '${session.sessionNumber}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                '${session.sessionNumber}. Oturum',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Divider(height: 24),
                          Text(
                            'Ders Seçimi:',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 8),
                          // Use Wrap for chips to handle overflow gracefully within the card
                          Wrap(
                            spacing: 8.0,
                            runSpacing: 4.0,
                            alignment: WrapAlignment.center,
                            children: subjects.map((subject) {
                              final isSelected = session.selectedSubjects
                                  .contains(subject);
                              return FilterChip(
                                label: Text(
                                  subject,
                                  style: TextStyle(fontSize: 12),
                                ),
                                selected: isSelected,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.all(0),
                                onSelected: (bool selected) {
                                  setState(() {
                                    final newSubjects = List<String>.from(
                                      session.selectedSubjects,
                                    );
                                    if (selected) {
                                      newSubjects.add(subject);
                                    } else {
                                      newSubjects.remove(subject);
                                    }
                                    _sessions[index] = TrialExamSession(
                                      sessionNumber: session.sessionNumber,
                                      selectedSubjects: newSubjects,
                                      opticalFormId: session.opticalFormId,
                                      opticalFormName: session.opticalFormName,
                                      fileName: session.fileName,
                                      fileUrl: session.fileUrl,
                                      uploadedAt: session.uploadedAt,
                                      lineEdits: session.lineEdits,
                                    );
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue:
                                _opticalForms.any(
                                  (f) => f.id == session.opticalFormId,
                                )
                                ? session.opticalFormId
                                : null,
                            decoration: InputDecoration(
                              labelText: 'Optik Form Seçiniz',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                            isExpanded: true, // Prevents overflow in dropdown
                            items: _opticalForms.isEmpty
                                ? []
                                : _opticalForms
                                      .map(
                                        (form) => DropdownMenuItem(
                                          value: form.id,
                                          child: Text(
                                            form.name,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 13),
                                          ),
                                        ),
                                      )
                                      .toList(),
                            onChanged: _opticalForms.isEmpty
                                ? null
                                : (val) {
                                    if (val == null) return;
                                    final formName = _opticalForms
                                        .firstWhere((f) => f.id == val)
                                        .name;
                                    setState(() {
                                      _sessions[index] = TrialExamSession(
                                        sessionNumber: session.sessionNumber,
                                        selectedSubjects:
                                            session.selectedSubjects,
                                        opticalFormId: val,
                                        opticalFormName: formName,
                                        fileName: session.fileName,
                                        fileUrl: session.fileUrl,
                                        uploadedAt: session.uploadedAt,
                                        lineEdits: session.lineEdits,
                                      );
                                    });
                                  },
                            hint: _opticalForms.isEmpty
                                ? Text(
                                    'Yükleniyor...',
                                    style: TextStyle(fontSize: 12),
                                  )
                                : Text(
                                    'Seçiniz',
                                    style: TextStyle(fontSize: 12),
                                  ),
                          ),
                          SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Tooltip(
                                  message: session.opticalFormId == null
                                      ? 'Önce optik form seçmelisiniz'
                                      : session.fileName != null
                                      ? session.fileName!
                                      : 'Dosya seç',
                                  child: OutlinedButton.icon(
                                    // Optik form seçili değilse butonu devre dışı bırak
                                    onPressed: session.opticalFormId == null
                                        ? null
                                        : () => _pickSessionFile(index),
                                    icon: Icon(Icons.upload_file, size: 18),
                                    label: Text(
                                      session.opticalFormId == null
                                          ? 'Önce Optik Form Seçin'
                                          : session.fileName ?? 'Dosya Yükle',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 16,
                                        horizontal: 8,
                                      ),
                                      // Devre dışıyken soluk görünüm
                                      foregroundColor:
                                          session.opticalFormId == null
                                          ? Colors.grey
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                              if (session.fileName != null) ...[
                                SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(Icons.close, color: Colors.red),
                                  tooltip: 'Dosyayı Kaldır',
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(),
                                  onPressed: () => _removeSessionFile(index),
                                ),
                              ],
                            ],
                          ),
                          if (session.fileName != null &&
                              session.opticalFormId != null) ...[
                            SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                onPressed: () => _openDataEditor(index),
                                icon: Badge(
                                  isLabelVisible: session.lineEdits.isNotEmpty,
                                  label: Text('${session.lineEdits.length}'),
                                  backgroundColor: Colors.orange,
                                  child: Icon(Icons.fact_check, size: 18),
                                ),
                                label: Text(
                                  session.lineEdits.isEmpty
                                      ? 'Okunan Veriyi Gör / Düzenle'
                                      : 'Okunan Veri (${session.lineEdits.length} düzeltme)',
                                  style: TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: session.lineEdits.isEmpty
                                      ? Colors.indigo
                                      : Colors.orange.shade800,
                                  backgroundColor: (session.lineEdits.isEmpty
                                          ? Colors.indigo
                                          : Colors.orange)
                                      .withValues(alpha: 0.06),
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEvaluationStatistics() {
    // Always show stats, even if empty
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 900),
        child: Card(
          elevation: 2,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  "Değerlendirme İstatistikleri",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
                SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildStatItem(
                      "Sistemdeki",
                      _totalSystemStudents.toString(),
                      Colors.blueGrey,
                    ),
                    _buildStatItem(
                      "Sınava Giren",
                      _participatingStudents.toString(),
                      Colors.indigo,
                    ),

                    // Matched
                    InkWell(
                      onTap: _showMatchedStudentsDialog,
                      child: _buildStatItem(
                        "Eşleşen",
                        _matchedCount.toString(),
                        Colors.green,
                        isClickable: true,
                      ),
                    ),

                    // Unmatched
                    InkWell(
                      onTap: _showUnmatchedDialog,
                      child: _buildStatItem(
                        "Eşleşmeyen",
                        _unmatchedCount.toString(),
                        Colors.orange,
                        isClickable: true,
                      ),
                    ),

                    // Absent
                    InkWell(
                      onTap: _showAbsentStudentsDialog,
                      child: _buildStatItem(
                        "Katılmayan",
                        _absentStudents.length.toString(),
                        Colors.red,
                        isClickable: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAbsentStudentsDialog() {
    showStatsBottomSheet(
      context: context,
      builder: (context) => AbsentStudentsDialog(
        systemStudentsMap: _systemStudentsMap,
        results: _currentResults,
        sessions: _sessions,
        examName: _nameController.text,
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    Color color, {
    bool isClickable = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8)),
              ),
              if (isClickable) ...[
                SizedBox(width: 4),
                Icon(Icons.touch_app, size: 12, color: color),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        final buttons = <Widget>[
          // Use generic type <Widget>
          ElevatedButton.icon(
            onPressed: _evaluateExam,
            icon: Icon(Icons.analytics),
            label: Text('Sınavı Değerlendir'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ), // Taller buttons
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _viewSavedResults,
            icon: Icon(Icons.visibility),
            label: Text('Görüntüle'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (_currentResults.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Silinecek veri bulunamadı.')),
                );
                return;
              }
              _deleteExamData();
            },
            icon: Icon(Icons.delete_forever),
            label: Text('Veri Sil'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _showShareDialog,
            icon: Icon(Icons.share),
            label: Text('Paylaş'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ];

        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: buttons
                .map(
                  (btn) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: btn,
                  ),
                )
                .toList(),
          );
        } else {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: buttons
                .map(
                  (btn) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: btn,
                    ),
                  ),
                )
                .toList(),
          );
        }
      },
    );
  }

  void _showUnmatchedDialog() {
    if (_currentResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Henüz değerlendirme yapılmamış.")),
      );
      return;
    }

    final unmatched = _currentResults.where((r) => !r.isMatched).toList();
    if (unmatched.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Eşleşmeyen öğrenci bulunmuyor.")));
      return;
    }

    showStatsBottomSheet(
      context: context,
      builder: (context) => UnmatchedStudentsDialog(
        results: _currentResults,
        allSystemStudents: _allSchoolStudentsMap.isNotEmpty
            ? _allSchoolStudentsMap.values.toList()
            : _systemStudentsMap.values.toList(),
        sessions: _sessions,
        onMatch: (original, systemStudent) async {
          // 1. Update the original unmatched result to become matched
          original.isMatched = true;
          original.systemStudentId = systemStudent['id'];
          String? name = systemStudent['fullName'] ?? systemStudent['name'];
          original.name = (name ?? '').toString();
          original.classLevel = (systemStudent['classLevel'] ?? '').toString();
          String? branch =
              systemStudent['className'] ?? systemStudent['branch'];
          original.branch = (branch ?? '').toString();
          original.studentNo = (systemStudent['studentNo'] ?? '').toString();
          original.tcNo = (systemStudent['tcNo'] ?? '').toString();

          // 2. Check if this student ALREADY exists in the results (from another session)
          try {
            final existingMatch = _currentResults.firstWhere(
              (r) =>
                  r.isMatched &&
                  r.systemStudentId == systemStudent['id'] &&
                  r != original,
            );

            // MERGE LOGIC: Merge 'original' (newly matched) into 'existingMatch'

            // Merge Sessions
            for (var sessionNum in original.participatedSessions) {
              if (!existingMatch.participatedSessions.contains(sessionNum)) {
                existingMatch.participatedSessions.add(sessionNum);
              }
            }

            // Merge Booklet
            if (!existingMatch.booklet.contains(original.booklet)) {
              existingMatch.booklet += original.booklet;
            }

            // Merge Subject Stats
            original.subjects.forEach((subj, stats) {
              if (!existingMatch.subjects.containsKey(subj) ||
                  existingMatch.subjects[subj]!.correct == 0) {
                existingMatch.subjects[subj] = stats;
              }
            });

            // Merge Answers
            original.answers.forEach((subj, ans) {
              if (!existingMatch.answers.containsKey(subj) ||
                  existingMatch.answers[subj]!.isEmpty) {
                existingMatch.answers[subj] = ans;
              }
            });

            // Merge Correct Answers
            original.correctAnswers.forEach((subj, ans) {
              if (!existingMatch.correctAnswers.containsKey(subj) ||
                  existingMatch.correctAnswers[subj]!.isEmpty) {
                existingMatch.correctAnswers[subj] = ans;
              }
            });

            // Remove the 'original' duplicate object from list since it's merged
            _currentResults.remove(original);
          } catch (e) {
            // No existing match found. Keep original.
          }

          await _recalculateAllScoresLocally();
          setState(() {});
        },
      ),
    );
  }

  Future<void> _recalculateAllScoresLocally() async {
    Map<String, StudentResult> tempMap = {};
    for (var r in _currentResults) {
      String key = r.systemStudentId ?? "TEMP_${r.hashCode}";
      tempMap[key] = r;
    }

    await _calculateScores(tempMap, (_, __) {});

    _currentResults = tempMap.values.toList();
    _currentResults.sort((a, b) => b.score.compareTo(a.score));
    _recalculateStats();
  }

  void _showMatchedStudentsDialog() {
    showStatsBottomSheet(
      context: context,
      builder: (context) => MatchedStudentsDialog(
        results: _currentResults,
        sessions: _sessions,
        onUnmatch: (student) {
          setState(() {
            student.isMatched = false;
            student.systemStudentId = null;
            _recalculateStats();
          });
        },
      ),
    );
  }

  void _recalculateStats() {
    _matchedCount = _currentResults.where((s) => s.isMatched).length;
    _unmatchedCount = _currentResults.length - _matchedCount;
    _participatingStudents = _currentResults.length;

    _absentStudents.clear();
    _systemStudentsMap.forEach((id, data) {
      bool present = _currentResults.any((s) => s.systemStudentId == id);
      if (!present) {
        _absentStudents.add(data);
      }
    });

    if (_currentResults.isNotEmpty) {
      // Don't encode to JSON here; it's heavy. Encode only when saving.
    }
  }

  Future<void> _fetchSystemStudents() async {
    try {
      if (_selectedClassLevel == null) return;

      final instVariants = UserPermissionService.getInstitutionIdVariants(widget.institutionId);
      final targetInstId = instVariants.isNotEmpty ? instVariants.first : widget.institutionId;

      // 1. Sınıfları çek (classId eşleştirmesi için)
      QuerySnapshot<Map<String, dynamic>> classesSnap;
      if (instVariants.length > 1) {
        classesSnap = await FirebaseFirestore.instance
            .collection('classes')
            .where('institutionId', whereIn: instVariants)
            .where('isActive', isEqualTo: true)
            .get();
      } else {
        classesSnap = await FirebaseFirestore.instance
            .collection('classes')
            .where('institutionId', isEqualTo: targetInstId)
            .where('isActive', isEqualTo: true)
            .get();
      }

      final String selectedLevelDigits = _selectedClassLevel!.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );

      final Set<String> targetClassIds = {};
      final Map<String, String> classIdToName = {};
      final Map<String, String> classIdToLevel = {};

      for (var cDoc in classesSnap.docs) {
        final cData = cDoc.data();
        final cLevel = (cData['classLevel'] ?? '').toString();
        final cName = (cData['className'] ?? '').toString();
        classIdToName[cDoc.id] = cName;
        classIdToLevel[cDoc.id] = cLevel;

        final cLevelDigits = cLevel.replaceAll(RegExp(r'[^0-9]'), '');
        final cNameDigits = RegExp(r'^\d+').firstMatch(cName)?.group(0) ?? '';
        if ((cLevelDigits == selectedLevelDigits && selectedLevelDigits.isNotEmpty) ||
            (cNameDigits == selectedLevelDigits && selectedLevelDigits.isNotEmpty)) {
          targetClassIds.add(cDoc.id);
        }
      }

      // 2. Kurumun tüm öğrencilerini çek
      QuerySnapshot<Map<String, dynamic>> studentSnapshot;
      if (instVariants.length > 1) {
        studentSnapshot = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', whereIn: instVariants)
            .get();
      } else {
        studentSnapshot = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: targetInstId)
            .get();
      }

      // Kurum ID ile bulunamazsa okul türüne göre dene
      if (studentSnapshot.docs.isEmpty && widget.schoolTypeId.isNotEmpty) {
        studentSnapshot = await FirebaseFirestore.instance
            .collection('students')
            .where('schoolTypeId', isEqualTo: widget.schoolTypeId)
            .get();
      }

      final Map<String, Map<String, dynamic>> allSchoolMap = {};
      final Map<String, Map<String, dynamic>> targetGradeMap = {};

      for (var doc in studentSnapshot.docs) {
        var data = doc.data();
        if (data['isActive'] == false) continue;
        data['id'] = doc.id;

        // TC Kimlik ve Telefon gibi şifreli verileri çöz
        data = CryptoService.decryptMap(data, institutionId: widget.institutionId);

        // classId varsa eksik className veya classLevel alanlarını doldur
        final cid = data['classId']?.toString();
        if (cid != null && cid.isNotEmpty) {
          if ((data['className'] == null || data['className'].toString().isEmpty) &&
              classIdToName.containsKey(cid)) {
            data['className'] = classIdToName[cid];
          }
          if ((data['classLevel'] == null || data['classLevel'].toString().isEmpty) &&
              classIdToLevel.containsKey(cid)) {
            data['classLevel'] = classIdToLevel[cid];
          }
        }

        allSchoolMap[doc.id] = data;

        // Hedef sınıf seviyesine ait mi kontrol et
        final sLevelStr = (data['classLevel'] ?? data['level'] ?? data['grade'] ?? '').toString();
        final sLevelDigits = sLevelStr.replaceAll(RegExp(r'[^0-9]'), '');

        final sClassName = (data['className'] ?? data['branch'] ?? '').toString().trim();
        final sClassDigits = RegExp(r'^\d+').firstMatch(sClassName)?.group(0) ?? '';

        final bool isTargetGrade = (sLevelDigits == selectedLevelDigits && selectedLevelDigits.isNotEmpty) ||
            (sClassDigits == selectedLevelDigits && selectedLevelDigits.isNotEmpty) ||
            (cid != null && targetClassIds.contains(cid));

        if (isTargetGrade) {
          if (_selectedBranches.isNotEmpty) {
            final sBranch = sClassName;
            final matchesSelectedBranch = _selectedBranches.any((b) {
              final bClean = b.trim().toLowerCase();
              final sClean = sBranch.toLowerCase();
              return bClean == sClean || bClean.contains(sClean) || sClean.contains(bClean);
            });
            if (!matchesSelectedBranch) continue;
          }
          targetGradeMap[doc.id] = data;
        }
      }

      if (mounted) {
        setState(() {
          _allSchoolStudentsMap = allSchoolMap;
          _systemStudentsMap = targetGradeMap.isNotEmpty ? targetGradeMap : allSchoolMap;
          _totalSystemStudents = _systemStudentsMap.length;
          _recalculateStats();
        });
      }
    } catch (e) {
      debugPrint('Error fetching system students: $e');
    }
  }

  Future<void> _evaluateExam() async {
    if (_sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Değerlendirilecek oturum bulunamadı.')),
      );
      return;
    }

    if (_answerKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: Duration(seconds: 10),
          content: Text(
            'Cevap anahtarı tanımlanmamış. Lütfen önce cevap anahtarını giriniz.',
          ),
          action: SnackBarAction(
            label: 'Tanımla',
            textColor: Colors.amber,
            onPressed: () => _openAnswerKeyScreen(),
          ),
        ),
      );
      return;
    }

    // Use local ValueNotifiers to update dialog state
    final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
    final ValueNotifier<String> messageNotifier = ValueNotifier(
      "Hazırlanıyor...",
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (context, value, _) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 70,
                            height: 70,
                            child: CircularProgressIndicator(
                              value: (value <= 0 || value >= 1.0)
                                  ? null
                                  : value,
                              strokeWidth: 6,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.orange.shade700,
                              ),
                            ),
                          ),
                          if (value > 0)
                            Text(
                              '${(value * 100).toInt()}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  ValueListenableBuilder<String>(
                    valueListenable: messageNotifier,
                    builder: (context, value, _) {
                      return Text(
                        value,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'İşlem yapılıyor, lütfen sayfayı kapatmayınız.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    try {
      final resultsMap = await _processEvaluation((p, m) {
        progressNotifier.value = p;
        messageNotifier.value = m;
      });

      _currentResults = resultsMap.values.toList();
      setState(() {}); // Refresh stats panel

      messageNotifier.value = "Kaydediliyor...";
      progressNotifier.value = 0.95; // Show near completion

      final resultsList = resultsMap.values.toList();
      if (resultsList.isNotEmpty) {
        _currentResultsJson = jsonEncode(
          resultsList.map((e) => e.toJson()).toList(),
        );
        // Call _saveData with silent=true to avoid double spinner
        await _saveData(showFeedback: false, silent: true);
      }

      progressNotifier.value = 1.0;
      messageNotifier.value = "Tamamlandı!";
      await Future.delayed(Duration(milliseconds: 500));

      Navigator.pop(context); // Close Dialog

      if (resultsList.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hiçbir öğrenci okunamadı veya eşleştirilemedi.'),
          ),
        );
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sınav başarıyla değerlendirildi ve kaydedildi.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close Dialog on Error
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      progressNotifier.dispose();
      messageNotifier.dispose();
    }
  }

  Future<Map<String, StudentResult>> _processEvaluation(
    Function(double, String) onProgress,
  ) async {
    // 1. Fetch System Students First (0-15%)
    onProgress(0.01, "Sistemdeki öğrenci listesi çekiliyor...");
    await _fetchSystemStudents();
    onProgress(0.15, "Öğrenci listesi alındı.");

    final matcher = StudentMatcher(
      _allSchoolStudentsMap.isNotEmpty
          ? _allSchoolStudentsMap.values
          : _systemStudentsMap.values,
    );

    Map<String, StudentResult> mergedStudents = {};
    onProgress(0.20, "Oturumlar hazırlanıyor...");

    // 1.1. Initialize with Existing Results (Additive / Pool Logic)
    for (var result in _currentResults) {
      String key;
      if (result.isMatched && result.systemStudentId != null) {
        key = result.systemStudentId!;
      } else {
        if (result.tcNo.isNotEmpty) {
          key = "UNMATCHED_TC_${result.tcNo}";
        } else if (result.studentNo.isNotEmpty) {
          key = "UNMATCHED_NO_${result.studentNo}";
        } else {
          key = "UNKNOWN_${result.name}_${result.classLevel}";
        }
      }
      mergedStudents[key] = result;
    }

    // Process Sessions (20-80%)
    onProgress(0.2, "Oturumlar işleniyor...");

    // Map to keep track of progress for each session
    Map<int, double> sessionProgress = {};
    List<Future<Map<String, StudentResult>>> sessionTasks = [];

    // Get Exam Type Definition early for net calculation ratio
    ExamType? currentExamType;
    if (_selectedExamTypeId != null) {
      try {
        currentExamType = _examTypes.firstWhere((e) => e.id == _selectedExamTypeId);
      } catch (silentError) { debugPrint('[trial_exam_form] hata yutuldu: $silentError'); }
    }

    // Düzeltme yapılmış satırların öğrenci anahtarları (eski sonuçları silinecek)
    final touched = <String>{};
    for (int i = 0; i < _sessions.length; i++) {
      sessionTasks.add(
        _processSessionSingle(
          _sessions[i],
          i,
          matcher,
          currentExamType,
          (sessionP) {
            sessionProgress[i] = sessionP;
            // Calculate total progress in 20-80 range
            double totalP = 0;
            for (var v in sessionProgress.values) {
              totalP += v;
            }
            double weightedP = 0.2 + (totalP / _sessions.length) * 0.6;
            onProgress(weightedP, "${i + 1}. Oturum işleniyor...");
          },
          touchedKeys: touched,
        ),
      );
    }
    final results = await Future.wait(sessionTasks);
    // Düzeltilen öğrencilerin havuzdaki eski sonuçları temizlenir; dosyası olan
    // tüm oturumlar zaten yeniden işlendiği için güncel veri aşağıda eklenir.
    for (final k in touched) {
      mergedStudents.remove(k);
    }

    // Merge results from all sessions
    onProgress(0.8, "Sonuçlar birleştiriliyor...");
    for (var sessionResult in results) {
      sessionResult.forEach((key, student) {
        if (!mergedStudents.containsKey(key)) {
          mergedStudents[key] = student;
        } else {
          final existing = mergedStudents[key]!;

          for (var p in student.participatedSessions) {
            if (!existing.participatedSessions.contains(p)) {
              existing.participatedSessions.add(p);
            }
          }

          if (existing.booklet.isEmpty) existing.booklet = student.booklet;

          student.subjects.forEach((subj, stats) {
            existing.subjects[subj] = stats;
          });
          student.answers.forEach((subj, ans) {
            existing.answers[subj] = ans;
          });
          student.correctAnswers.forEach((subj, ans) {
            existing.correctAnswers[subj] = ans;
          });
        }
      });
    }

    return _calculateScores(mergedStudents, onProgress);
  }

  Future<Map<String, StudentResult>> _calculateScores(
    Map<String, StudentResult> mergedStudents,
    Function(double, String) onProgress,
  ) async {
    onProgress(0.9, "Puanlar hesaplanıyor...");

    // Get Exam Type Definition
    ExamType? examType;
    if (_selectedExamTypeId != null) {
      try {
        examType = _examTypes.firstWhere((e) => e.id == _selectedExamTypeId);
      } catch (silentError) { debugPrint('[trial_exam_form] hata yutuldu: $silentError'); }
    }

    // Calculate Scores
    for (var student in mergedStudents.values) {
      double score = 0.0;
      if (examType != null) {
        score = examType.baseScore;
        student.subjects.forEach((subjName, stats) {
          final subjectDef = examType!.subjects.firstWhere(
            (s) =>
                s.branchName.trim().toLowerCase() ==
                subjName.trim().toLowerCase(),
            orElse: () =>
                ExamSubject(branchName: '', questionCount: 0, coefficient: 0),
          );
          if (subjectDef.coefficient > 0) {
            score += stats.net * subjectDef.coefficient;
          }
        });
      }
      if (score < 0) score = 0;
      student.score = score;
    }

    // Calculate Ranks
    List<StudentResult> allList = mergedStudents.values.toList();
    // Sort by Score Descending
    allList.sort((a, b) => b.score.compareTo(a.score));

    // Aynı puanı alanlar aynı sırayı alır; sonraki farklı puan bir artar (1,1,1,2,2,3).
    int currentRank = 0;
    for (int i = 0; i < allList.length; i++) {
      if (i == 0 || (allList[i].score - allList[i - 1].score).abs() >= 0.001) {
        currentRank++;
      }
      allList[i].rankGeneral = currentRank;
      allList[i].rankInstitution = currentRank;
    }

    // Şube sıraları (aynı mantık)
    Map<String, List<StudentResult>> byBranch = {};
    for (var s in allList) {
      if (!byBranch.containsKey(s.branch)) byBranch[s.branch] = [];
      byBranch[s.branch]!.add(s);
    }
    byBranch.forEach((branch, list) {
      // List is already sorted by score desc because allList was sorted
      int branchRank = 0;
      for (int i = 0; i < list.length; i++) {
        if (i == 0 || (list[i].score - list[i - 1].score).abs() >= 0.001) {
          branchRank++;
        }
        list[i].rankBranch = branchRank;
      }
    });


    return mergedStudents;
  }

  /// Okunan optik veriyi görüntüleme / düzeltme ekranı. Orijinal dosyaya
  /// dokunulmaz; düzeltmeler oturumun `lineEdits` alanında saklanır.
  Future<void> _openDataEditor(int index) async {
    final session = _sessions[index];
    OpticalForm? form;
    for (final f in _opticalForms) {
      if (f.id == session.opticalFormId) {
        form = f;
        break;
      }
    }
    if (form == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bu oturumun optik formu bulunamadı.')),
      );
      return;
    }

    var content = await _readSessionContent(index);
    if (!mounted) return;
    if (content.isEmpty) {
      // Dosya sunucuda yok (arka plan yüklemesi tamamlanmamış) veya indirilemedi.
      final noUrl = _sessions[index].fileUrl == null;
      final pick = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Dosya bulunamadı'),
          content: Text(
            noUrl
                ? '"${session.fileName ?? ''}" dosyası sunucuya yüklenmemiş görünüyor, '
                    'bu yüzden okunamadı.\n\nAynı dosyayı bilgisayarınızdan seçerseniz '
                    'veriyi görüntüleyip düzeltebilirsiniz. Mevcut sonuçlar değişmez.'
                : '"${session.fileName ?? ''}" dosyası sunucudan indirilemedi.\n\n'
                    'Aynı dosyayı bilgisayarınızdan seçerek devam edebilirsiniz. '
                    'Mevcut sonuçlar değişmez.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Vazgeç'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: Icon(Icons.folder_open, size: 18),
              label: Text('Dosyayı Seç'),
            ),
          ],
        ),
      );
      if (pick != true || !mounted) return;
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'dat'],
        withData: true,
      );
      final file = picked?.files.single;
      if (file == null || file.bytes == null || !mounted) return;
      setState(() {
        _selectedFiles[index] = file;
        if (_sessions[index].fileName != file.name) {
          _sessions[index] = _sessions[index].copyWith(fileName: file.name);
        }
      });
      content = await _readSessionContent(index);
      if (!mounted) return;
      if (content.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Seçilen dosya boş veya okunamadı.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    final result = await Navigator.of(context).push<List<OpticalLineEdit>>(
      MaterialPageRoute(
        builder: (_) => OpticalDataEditorScreen(
          title: '${session.sessionNumber}. Oturum • ${session.fileName ?? ''}',
          rawLines: content.split('\n'),
          form: form!,
          initialEdits: session.lineEdits,
          booklets: _answerKeys.keys.toList()..sort(),
          sessionSubjects: session.selectedSubjects,
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _sessions[index] = _sessions[index].copyWith(lineEdits: result);
    });
    if (_examId != null) {
      await _saveData(showFeedback: false, silent: true);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _examId != null
              ? "Düzeltmeler kaydedildi. Sonuçlara yansıması için 'Sınavı Değerlendir'e basın."
              : "Düzeltmeler alındı; sınav kaydedilince saklanacak. Sonuçlara yansıması için 'Sınavı Değerlendir'e basın.",
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 5),
      ),
    );
  }

  /// Oturum dosyasının ham içeriğini okur (önce yerel seçilen dosya, yoksa
  /// Storage URL'si). Dosyaya hiçbir şekilde yazılmaz.
  Future<String> _readSessionContent(int sessionIndex) async {
    final fileData = _selectedFiles[sessionIndex];
    if (fileData is PlatformFile && fileData.bytes != null) {
      try {
        return utf8.decode(fileData.bytes!);
      } catch (_) {
        return latin1.decode(fileData.bytes!);
      }
    }
    final url = _sessions[sessionIndex].fileUrl;
    if (url != null) {
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          try {
            return utf8.decode(response.bodyBytes);
          } catch (_) {
            return latin1.decode(response.bodyBytes);
          }
        }
        debugPrint('[trial_exam_form] dosya indirilemedi: HTTP ${response.statusCode}');
      } catch (e) {
        debugPrint('[trial_exam_form] dosya indirilemedi: $e');
      }
    }
    return '';
  }

  /// Bir optik satırdan öğrenci kimliğini çıkarır ve sistemle eşleştirir.
  ({
    String key,
    Map<String, dynamic>? data,
    String tc,
    String no,
    String name,
    String cls,
    String branch,
  })? _identifyLine(String line, OpticalForm opticalForm, StudentMatcher matcher) {
    final fileTc = _extract(line, opticalForm.identityNo).trim();
    String fileNo = _extract(line, opticalForm.studentNo).trim();
    if (fileNo.isNotEmpty) fileNo = fileNo.replaceFirst(RegExp(r'^0+'), '');
    final fileName = _extract(line, opticalForm.studentNameField);
    final fileCls = _extract(line, opticalForm.classLevel);
    final fileBranch = _extract(line, opticalForm.branch);

    final systemData = matcher.match(
      fileTc: fileTc,
      fileNo: fileNo,
      fileName: fileName,
      fileBranch: fileBranch,
      fileCls: fileCls,
    );

    String key;
    if (systemData != null && systemData['id'] != null) {
      key = systemData['id'].toString();
    } else if (fileTc.isNotEmpty) {
      key = 'UNMATCHED_TC_$fileTc';
    } else if (fileNo.isNotEmpty) {
      key = 'UNMATCHED_NO_$fileNo';
    } else {
      final n = StudentMatcher.normalizeTurkishForSearch(
          StudentMatcher.fixWindows1254(fileName)).trim();
      if (n.isEmpty) return null;
      key = 'UNMATCHED_NAME_$n';
    }
    return (
      key: key,
      data: systemData,
      tc: fileTc,
      no: fileNo,
      name: fileName,
      cls: fileCls,
      branch: fileBranch,
    );
  }

  Future<Map<String, StudentResult>> _processSessionSingle(
    TrialExamSession session,
    int sessionIndex,
    StudentMatcher matcher,
    ExamType? examType,
    Function(double) onProgressCallback, {
    /// Verilirse: düzeltilen satırların (düzeltme öncesi ve sonrası) öğrenci
    /// anahtarları eklenir; çağıran, havuzdaki eski sonuçları bunlarla temizler.
    Set<String>? touchedKeys,
  }) async {
    Map<String, StudentResult> localResults = {};

    final hasLocalFile = _selectedFiles.containsKey(sessionIndex);
    if ((session.fileUrl == null && !hasLocalFile) ||
        session.opticalFormId == null)
      return {};

    OpticalForm? opticalForm;
    try {
      opticalForm = _opticalForms.firstWhere(
        (f) => f.id == session.opticalFormId,
      );
    } catch (_) {
      return {};
    }

    final content = await _readSessionContent(sessionIndex);
    if (content.isEmpty) return {};

    final rawLines = content.split('\n');
    // Okuma ekranında yapılan düzeltmeler (dosyaya dokunmadan) uygulanır.
    final lines =
        OpticalLineEdits.apply(rawLines, opticalForm, session.lineEdits);
    if (touchedKeys != null && session.lineEdits.isNotEmpty) {
      final valid = OpticalLineEdits.validEdits(rawLines, session.lineEdits);
      for (final li in valid.keys) {
        final before = _identifyLine(rawLines[li], opticalForm, matcher);
        if (before != null) touchedKeys.add(before.key);
        if (lines[li].trim().isNotEmpty) {
          final after = _identifyLine(lines[li], opticalForm, matcher);
          if (after != null) touchedKeys.add(after.key);
        }
      }
    }
    int lineCount = lines.length;
    int processedLines = 0;

    Stopwatch stopwatch = Stopwatch()..start();

    for (var line in lines) {
      processedLines++;

      if (stopwatch.elapsedMilliseconds > 100) {
        onProgressCallback(processedLines / lineCount);
        await Future.delayed(Duration.zero);
        stopwatch.reset();
      }

      if (line.trim().isEmpty) continue;

      final ident = _identifyLine(line, opticalForm, matcher);
      if (ident == null) continue;
      final fileTc = ident.tc;
      final fileNo = ident.no;
      final fileName = ident.name;
      final fileCls = ident.cls;
      final fileBranch = ident.branch;
      final systemData = ident.data;
      final key = ident.key;

      if (!localResults.containsKey(key)) {
        if (systemData != null) {
          localResults[key] = StudentResult(
            tcNo: (systemData['tcNo'] ?? fileTc).toString(),
            studentNo: (systemData['studentNo'] ?? systemData['studentNumber'] ?? fileNo).toString(),
            name: (systemData['fullName'] ?? systemData['name'] ?? fileName)
                .toString(),
            classLevel: (systemData['classLevel'] ?? fileCls).toString(),
            branch:
                (systemData['className'] ?? systemData['branch'] ?? fileBranch)
                    .toString(),
            isMatched: true,
            systemStudentId: systemData['id'],
          );
        } else {
          localResults[key] = StudentResult(
            tcNo: fileTc,
            studentNo: fileNo,
            name: StudentMatcher.fixWindows1254(fileName),
            classLevel: fileCls,
            branch: fileBranch,
            isMatched: false,
            systemStudentId: null,
          );
        }
      }

      final student = localResults[key]!;
      if (!student.participatedSessions.contains(session.sessionNumber)) {
        student.participatedSessions.add(session.sessionNumber);
      }

      String booklet = _answerKeys.keys.isNotEmpty
          ? _answerKeys.keys.first
          : 'A';
      if (opticalForm.bookletType.length > 0) {
        String bVal = _extract(line, opticalForm.bookletType).trim().toUpperCase();
        if (bVal.isNotEmpty) booklet = bVal;
      }
      if (!_answerKeys.containsKey(booklet)) {
        if (_answerKeys.isNotEmpty)
          booklet = _answerKeys.keys.first;
        else
          continue;
      }

      if (!student.booklet.contains(booklet)) {
        student.booklet += booklet;
      }

      final answerKeyMap = _answerKeys[booklet]!;
      final allowedSubjects = session.selectedSubjects.isNotEmpty
          ? session.selectedSubjects.toSet()
          : null;

      opticalForm.subjectFields.forEach((subjectName, field) {
        if (allowedSubjects != null && !allowedSubjects.contains(subjectName)) {
          return;
        }

        if (answerKeyMap.containsKey(subjectName)) {
          String sAns = _extract(line, field, trimResult: false);
          String cAns = answerKeyMap[subjectName]!;

          int correct = 0, wrong = 0, empty = 0;
          int len = sAns.length < cAns.length ? sAns.length : cAns.length;

          for (int i = 0; i < len; i++) {
            String s = sAns[i].toUpperCase();
            String c = cAns[i].toUpperCase();

            if (c == 'S') {
              // Herkes için doğru
              correct++;
            } else if (c == '#') {
              // Herkes için boş
              empty++;
            } else if (c == 'X') {
              // İptal (Yok sayılır)
            } else if (s == ' ' || s == '' || s == '-' || s == '.') {
              empty++;
            } else if (s == c) {
              correct++;
            } else {
              wrong++;
            }
          }
          if (cAns.length > len) {
            // Check remainder of the answer key for special characters
            for (int i = len; i < cAns.length; i++) {
              String c = cAns[i].toUpperCase();
              if (c == 'S') {
                correct++;
              } else {
                empty++;
              }
            }
          }

            double ratio = examType?.wrongCorrectRatio ?? 3.0;
            if (ratio <= 0) ratio = 3.0; // Fail-safe
            double net = correct - (wrong / ratio);

          final existing = student.subjects[subjectName];

          bool isNewEmpty = (correct == 0 && wrong == 0 && net == 0.0);
          bool hasExistingData =
              (existing != null &&
              (existing.correct > 0 || existing.wrong > 0));

          if (allowedSubjects == null && isNewEmpty && hasExistingData) {
          } else {
            student.subjects[subjectName] = SubjectStats(
              correct: correct,
              wrong: wrong,
              empty: empty,
              net: net,
            );
            student.answers[subjectName] = sAns;
            student.correctAnswers[subjectName] = cAns;
          }
        }
      });
    }
    return localResults;
  }

  String _extract(String line, OpticalField field, {bool trimResult = true}) {
    if (field.length <= 0) return '';
    // Convert 1-based start to 0-based index.
    // If user enters 1, it means column 1, which corresponds to index 0.
    int startIndex = field.start > 0 ? field.start - 1 : 0;

    String result = '';
    if (line.length >= startIndex + field.length) {
      result = line.substring(startIndex, startIndex + field.length);
    } else if (line.length > startIndex) {
      result = line.substring(startIndex);
      if (!trimResult) {
        result = result.padRight(field.length, ' ');
      }
    } else {
      if (!trimResult) {
        result = ''.padRight(field.length, ' ');
      }
    }
    return trimResult ? result.trim() : result;
  }

  void _viewSavedResults() {
    if (_currentResultsJson == null || _currentResultsJson!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Henüz kaydedilmiş değerlendirme sonucu bulunamadı.'),
        ),
      );
      return;
    }
    try {
      final List<dynamic> jsonList = jsonDecode(_currentResultsJson!);
      final results = jsonList.map((e) => StudentResult.fromJson(e)).toList();
      _showResultsDialog(results);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kayıtlı sonuçlar açılırken hata oluştu: $e')),
      );
    }
  }

  void _showResultsDialog(List<StudentResult> results) {
    // Initial Sort: Score Descending
    results.sort((a, b) {
      int cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return b.total.net.compareTo(a.total.net);
    });

    Set<String> orderedSubjects = {};
    for (var session in _sessions) {
      if (session.selectedSubjects.isNotEmpty) {
        orderedSubjects.addAll(session.selectedSubjects);
      }
    }
    // Add any remaining subjects
    results.expand((r) => r.subjects.keys).forEach((s) {
      if (!orderedSubjects.contains(s)) orderedSubjects.add(s);
    });

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ResultsTableDialog(
          results: results,
          subjects: orderedSubjects.toList(),
          examName: widget.trialExam?.name ?? 'Sınav Sonucu',
          outcomes: _outcomes,
          isRankingVisible:
              widget.trialExam?.sharingSettings['isRankingVisible'] ?? true,
          trialExamId: widget.trialExam?.id,
        ),
      ),
    );
  }

  Future<void> _deleteExamData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Verileri Sil'),
        content: Text(
          'Bu deneme sınavına ait TÜM öğrenci sonuçları, eşleşmeler ve hesaplamalar silinecektir.\n\nYüklenen dosya bağlantıları korunur ancak değerlendirme havuzu temizlenir.\nBu işlem geri alınamaz. Emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Evet, Sil',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _currentResults.clear();
        _currentResultsJson = null;
        _recalculateStats(); // Resets stats
      });
      await _saveData(showFeedback: true);
    }
  }

  void _showShareDialog() {
    // Determine initial state from whether it's published or not
    bool isActuallyPublished =
        _isPublished && (widget.trialExam?.isPublished ?? false);

    // Defaults for new share or pre-fill
    bool shareWithTeacher = false;
    bool shareWithParent = false;
    bool shareWithStudent = false;
    bool showRanking = _sharingSettings['isRankingVisible'] == true;
    DateTime scheduleDate = DateTime.now();
    TimeOfDay scheduleTime = TimeOfDay.now();

    // If currently published, pre-fill from existing settings if available
    if (isActuallyPublished) {
      final settings = _sharingSettings;
      final sharedWith =
          (settings['sharedWith'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      shareWithTeacher = sharedWith.contains('teacher');
      shareWithParent = sharedWith.contains('parent');
      shareWithStudent = sharedWith.contains('student');
      if (settings['shareDate'] != null) {
        DateTime d = (settings['shareDate'] as Timestamp).toDate();
        scheduleDate = d;
        scheduleTime = TimeOfDay.fromDateTime(d);
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isActuallyPublished ? 'Yayında' : 'Sonuçları Paylaş'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isActuallyPublished) ...[
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Bu sınav şu anda yayındadır. Paylaşım ayarlarını güncellemek veya yayından kaldırmak için aşağıyı kullanın.',
                                style: TextStyle(
                                  color: Colors.green.shade800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),
                    ] else ...[
                      Text(
                        'Bu sınavın sonuçlarını aşağıda seçilen gruplar için duyuru olarak paylaşın.',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                      SizedBox(height: 16),
                    ],

                    Text(
                      'Hedef Kitle:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    CheckboxListTile(
                      title: Text('Öğretmenler'),
                      value: shareWithTeacher,
                      onChanged: (v) =>
                          setDialogState(() => shareWithTeacher = v!),
                      dense: true,
                    ),
                    CheckboxListTile(
                      title: Text('Veliler'),
                      value: shareWithParent,
                      onChanged: (v) =>
                          setDialogState(() => shareWithParent = v!),
                      dense: true,
                    ),
                    CheckboxListTile(
                      title: Text('Öğrenciler'),
                      value: shareWithStudent,
                      onChanged: (v) =>
                          setDialogState(() => shareWithStudent = v!),
                      dense: true,
                    ),
                    Divider(),
                    Text(
                      'Görünürlük Ayarları:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SwitchListTile(
                      title: Text('Derecelendirme göster'),
                      subtitle: Text(
                        'Açıksa karnelerde genel/kurum/şube dereceleri görünür.',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: showRanking,
                      onChanged: (v) => setDialogState(() => showRanking = v),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    Divider(),
                    Text(
                      'Paylaşım Zamanı:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: scheduleDate,
                          firstDate: DateTime.now().subtract(Duration(days: 1)),
                          lastDate: DateTime.now().add(Duration(days: 365)),
                        );
                        if (d != null) {
                          final t = await showTimePicker(
                            context: context,
                            initialTime: scheduleTime,
                          );
                          if (t != null) {
                            setDialogState(() {
                              scheduleDate = d;
                              scheduleTime = t;
                            });
                          }
                        }
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "${DateFormat('dd.MM.yyyy').format(scheduleDate)} ${scheduleTime.format(context)}",
                            ),
                            Icon(Icons.access_time, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (isActuallyPublished)
                  TextButton(
                    onPressed: () async {
                      // Unpublish Logic
                      Navigator.pop(context);
                      setState(() {
                        _isPublished = false;
                        _sharingSettings['sharedWith'] = [];
                        _sharingSettings['unpublishedAt'] = Timestamp.now();
                      });
                      await _saveData(showFeedback: false, onlySettings: true);
                      if (mounted) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Sınav yayından kaldırıldı.')),
                        );
                      }
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: Text('Yayından Kaldır'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!shareWithTeacher &&
                        !shareWithParent &&
                        !shareWithStudent) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('En az bir hedef kitle seçin.')),
                      );
                      return;
                    }

                    Navigator.pop(context); // Close dialog

                    // Update local sharing settings
                    _sharingSettings['isRankingVisible'] = showRanking;
                    _sharingSettings['sharedWith'] = [
                      if (shareWithTeacher) 'teacher',
                      if (shareWithParent) 'parent',
                      if (shareWithStudent) 'student',
                    ];
                    _sharingSettings['shareDate'] = Timestamp.fromDate(
                      DateTime(
                        scheduleDate.year,
                        scheduleDate.month,
                        scheduleDate.day,
                        scheduleTime.hour,
                        scheduleTime.minute,
                      ),
                    );

                    // Remove unpublishedAt flag as we are publishing again
                    _sharingSettings.remove('unpublishedAt');

                    // Set published state to true
                    setState(() {
                      _isPublished = true;
                    });

                    // Save settings quietly (this calls _saveData which uses _isPublished and widget.trialExam.sharingSettings)
                    await _saveData(showFeedback: false, onlySettings: true);

                    DateTime scheduledDateTime = DateTime(
                      scheduleDate.year,
                      scheduleDate.month,
                      scheduleDate.day,
                      scheduleTime.hour,
                      scheduleTime.minute,
                    );

                    // AnnouncementService'in tanıdığı alıcı biçimleri:
                    // 'TEACHER' (tüm öğretmenler), kullanıcı ID'leri (öğrenci/veli).
                    List<String> recipients = [];
                    final Set<String> studentIds = _currentResults
                        .where(
                          (r) =>
                              r.isMatched &&
                              r.systemStudentId != null &&
                              r.systemStudentId!.isNotEmpty,
                        )
                        .map((r) => r.systemStudentId!)
                        .toSet();

                    try {
                      final service = AnnouncementService();
                      if (shareWithTeacher) recipients.add('TEACHER');
                      if (shareWithStudent) recipients.addAll(studentIds);
                      if (shareWithParent && studentIds.isNotEmpty) {
                        final parents = await service.getParentsByStudents(
                          studentIds.toList(),
                        );
                        for (final p in parents) {
                          final pid = p['id']?.toString();
                          if (pid != null && pid.isNotEmpty) recipients.add(pid);
                        }
                      }
                      recipients = recipients.toSet().toList();

                      await service.saveAnnouncement(
                        title: "${_nameController.text} Sonuçları",
                        content:
                            "${DateFormat('dd.MM.yyyy').format(_selectedDate)} tarihinde uygulanan ${_nameController.text} sonuçları değerlendirilmiş ve sisteme yüklenmiştir.",
                        recipients: recipients,
                        publishDate: scheduledDateTime,
                        publishTime: scheduleTime.format(context),
                        schoolTypeId: widget.schoolTypeId,
                        schedulePublish: scheduledDateTime.isAfter(
                          DateTime.now().add(Duration(minutes: 1)),
                        ),
                      );

                      if (mounted) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Sınav paylaşıldı ve duyuru oluşturuldu.',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Duyuru oluşturulamadı: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: Text(
                    isActuallyPublished ? 'Güncelle' : 'Paylaş ve Duyur',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBookletCountSelector() {
    return DropdownButtonFormField<int>(
      initialValue: _bookletCount,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Kitapçık Sayısı',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      items: List.generate(
        8,
        (index) => index + 1,
      ).map((i) => DropdownMenuItem(value: i, child: Text('$i Adet'))).toList(),
      onChanged: (v) {
        if (v != null)
          setState(() {
            _bookletCount = v;
          });
      },
    );
  }

  Widget _buildSessionCountSelector() {
    return DropdownButtonFormField<int>(
      initialValue: _sessionCount,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Oturum Sayısı',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      items: List.generate(
        4,
        (index) => index + 1,
      ).map((i) => DropdownMenuItem(value: i, child: Text('$i'))).toList(),
      onChanged: (v) {
        if (v != null)
          setState(() {
            _sessionCount = v;
            _adjustSessionsList();
          });
      },
    );
  }

  static String _encodeResults(List<StudentResult> results) {
    return jsonEncode(results.map((e) => e.toJson()).toList());
  }
}

class ResultsTableDialog extends StatefulWidget {
  final List<StudentResult> results;
  final List<String> subjects;
  final String examName;
  final Map<String, Map<String, List<String>>> outcomes;
  final bool isRankingVisible;
  final String? trialExamId;

  const ResultsTableDialog({
    Key? key,
    required this.results,
    required this.subjects,
    this.examName = 'Sınav Sonucu',
    this.outcomes = const {},
    this.isRankingVisible = true,
    this.trialExamId,
  }) : super(key: key);

  @override
  _ResultsTableDialogState createState() => _ResultsTableDialogState();
}

class _ResultsTableDialogState extends State<ResultsTableDialog> {
  late List<StudentResult> _sortedResults;
  String _sortColumn = 'Puan';
  bool _sortAscending = false;
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  void _showDetail(StudentResult student) {
    int total = widget.results.length;
    int branchCount = widget.results
        .where(
          (r) =>
              r.classLevel == student.classLevel && r.branch == student.branch,
        )
        .length;
    // Assuming school count is same as total for this trial exam context
    int schoolCount = total;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StudentReportCardDialog(
          student: student,
          examName: widget.examName,
          subjects: widget.subjects,
          outcomes: widget.outcomes,
          totalStudents: total,
          schoolStudents: schoolCount,
          branchStudents: branchCount,
          isRankingVisible: widget.isRankingVisible,
          trialExamId: widget.trialExamId,
        ),
      ),
    );
  }

  // Column Widths
  final double wIndex = 40;
  final double wInfo = 40;
  final double wNo = 60;
  final double wClass = 50;
  final double wBranch = 50;
  final double wName = 140;
  final double wBooklet = 60; // New Column
  final double wSubBlock = 160;
  final double wTotalBlock = 160;
  final double wScore = 80;
  final double wRank = 50;
  final double rowHeight = 30;

  @override
  void initState() {
    super.initState();
    _sortedResults = List.from(widget.results);
  }

  void _sort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        // Default desc for Net/Score, Asc for Strings
        if (column == 'Ad Soyad' ||
            column == 'Şube' ||
            column == 'Sınıf' ||
            column == 'Kitapçık') {
          _sortAscending = true;
        } else {
          _sortAscending = false;
        }
      }

      int sign = _sortAscending ? 1 : -1;

      _sortedResults.sort((a, b) {
        int cmp = 0;
        switch (column) {
          case '#':
            // Keep original index or generic sort? Let's sort by list index logic if needed,
            // but actually '#' is usually just row number. Let's make it sort by original index if stored?
            // simpler: sort by StudentNo as secondary
            return 0;
          case 'Ö.No':
            cmp = a.studentNo.compareTo(b.studentNo);
            break;
          case 'Sınıf':
            cmp = a.classLevel.compareTo(b.classLevel);
          case 'Şube':
            cmp = a.branch.compareTo(b.branch);
            break;
          case 'Ad Soyad':
            cmp = a.name.compareTo(b.name);
            break;
          case 'Kitapçık':
            cmp = a.booklet.compareTo(b.booklet);
            break;
          case 'Puan':
            cmp = a.score.compareTo(b.score);
            break;
          case 'G.Sıra':
            cmp = a.rankGeneral.compareTo(b.rankGeneral);
            break; // Note: Rank 1 is "smaller" but means "better".
          // If Ascending (1->10), it shows best first.
          // If we default Puan to Desc (High->Low), that matches Rank Asc (1->10).
          // Let's handle special inversion logic if needed, but standard compare works.

          case 'K.Sıra':
            cmp = a.rankInstitution.compareTo(b.rankInstitution);
            break;
          case 'Ş.Sıra':
            cmp = a.rankBranch.compareTo(b.rankBranch);
            break;
          case 'TOPLAM':
            cmp = a.total.net.compareTo(b.total.net);
            break;
          default:
            // Subject Net
            if (widget.subjects.contains(column)) {
              final sa = a.subjects[column]?.net ?? 0.0;
              final sb = b.subjects[column]?.net ?? 0.0;
              cmp = sa.compareTo(sb);
            }
            break;
        }
        return cmp * sign;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    double totalWidth =
        wIndex +
        wInfo + // Add width
        wNo +
        wClass +
        wBranch +
        wName +
        wBooklet + // Add width
        (wSubBlock * widget.subjects.length) +
        wTotalBlock +
        wScore +
        (wRank * 3);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: EduknAppBar(
        title: 'Sınav Sonuçları (${_sortedResults.length} Öğrenci)',
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: ScrollConfiguration(
        behavior: ScrollBehavior().copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: Scrollbar(
          controller: _horizontalController,
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            physics: BouncingScrollPhysics(),
            child: Container(
              width: totalWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  Container(height: 1, color: Colors.grey.shade300),
                  Expanded(
                    child: ListView.builder(
                      cacheExtent: 500, itemCount: _sortedResults.length,
                      itemExtent:
                          45, // Pre-render more pixels
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      itemBuilder: (context, index) {
                        return _buildRow(index);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 60, // Taller header
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          _buildHeaderCell('#', wIndex, onTap: null),
          _buildHeaderCell('', wInfo, onTap: null), // Added Info Header
          _buildHeaderCell('Ö.No', wNo, onTap: () => _sort('Ö.No')),
          _buildHeaderCell('Sınıf', wClass, onTap: () => _sort('Sınıf')),
          _buildHeaderCell('Şube', wBranch, onTap: () => _sort('Şube')),
          _buildHeaderCell('Ad Soyad', wName, onTap: () => _sort('Ad Soyad')),
          _buildHeaderCell(
            'Kitapçık',
            wBooklet,
            onTap: () => _sort('Kitapçık'),
          ), // Added Header
          ...widget.subjects.map((s) => _buildSubjectHeader(s)),
          _buildTotalHeader(),
          _buildHeaderCell(
            'Puan',
            wScore,
            color: Colors.orange.shade50,
            useBorder: true,
            onTap: () => _sort('Puan'),
          ),
          _buildHeaderCell(
            'G.Sıra',
            wRank,
            color: Colors.blue.shade50,
            useBorder: true,
            onTap: () => _sort('G.Sıra'),
          ),
          _buildHeaderCell(
            'K.Sıra',
            wRank,
            color: Colors.blue.shade50,
            useBorder: true,
            onTap: () => _sort('K.Sıra'),
          ),
          _buildHeaderCell(
            'Ş.Sıra',
            wRank,
            color: Colors.blue.shade50,
            useBorder: true,
            onTap: () => _sort('Ş.Sıra'),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectHeader(String subject) {
    return InkWell(
      onTap: () => _sort(subject),
      child: Container(
        width: wSubBlock,
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: Colors.grey.shade300)),
          color: Colors.white,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(
                subject.length > 8 ? subject.substring(0, 8) + '..' : subject,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.black87,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _buildSubHeaderLabel('D', Colors.green.shade700),
                ),
                Expanded(child: _buildSubHeaderLabel('Y', Colors.red.shade700)),
                Expanded(
                  child: _buildSubHeaderLabel('B', Colors.grey.shade700),
                ),
                Expanded(
                  child: _buildSubHeaderLabel(
                    'N',
                    Colors.black87,
                    isBold: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalHeader() {
    return InkWell(
      onTap: () => _sort('TOPLAM'),
      child: Container(
        width: wTotalBlock,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: Colors.grey.shade300, width: 2),
          ),
          color: Colors.grey.shade50,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(
                'TOPLAM',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: Colors.indigo.shade900,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _buildSubHeaderLabel('D', Colors.green.shade700),
                ),
                Expanded(child: _buildSubHeaderLabel('Y', Colors.red.shade700)),
                Expanded(
                  child: _buildSubHeaderLabel('B', Colors.grey.shade700),
                ),
                Expanded(
                  child: _buildSubHeaderLabel(
                    'NET',
                    Colors.indigo.shade900,
                    isBold: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubHeaderLabel(String text, Color color, {bool isBold = false}) {
    return Container(
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  Widget _buildRow(int index) {
    final student = _sortedResults[index];
    final total = student.total;
    final bool isEven = index % 2 == 0;
    final Color rowColor = isEven ? Colors.white : Colors.grey.shade50;

    return RepaintBoundary(
      child: Container(
        height: 45,
        decoration: BoxDecoration(
          color: rowColor,
          border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
        ),
        child: Row(
          children: [
            _buildCell((index + 1).toString(), wIndex, color: rowColor),
            Container(
              width: wInfo,
              height: rowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey.shade200)),
              ),
              child: IconButton(
                icon: Icon(Icons.info_outline, size: 18, color: Colors.blue),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
                splashRadius: 16,
                onPressed: () => _showDetail(student),
              ),
            ),
            _buildCell(student.studentNo, wNo, color: rowColor),
            _buildCell(student.classLevel, wClass, color: rowColor),
            _buildCell(student.branch, wBranch, color: rowColor),
            _buildCell(
              student.name,
              wName,
              align: TextAlign.left,
              color: rowColor,
            ),
            _buildCell(student.booklet, wBooklet, color: rowColor),
            ...widget.subjects.map((s) {
              final stat = student.subjects[s] ?? SubjectStats();
              return Container(
                width: wSubBlock,
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildFixedSubCell(
                        stat.correct.toString(),
                        Colors.green.shade700,
                      ),
                    ),
                    Expanded(
                      child: _buildFixedSubCell(
                        stat.wrong.toString(),
                        Colors.red.shade700,
                      ),
                    ),
                    Expanded(
                      child: _buildFixedSubCell(
                        stat.empty.toString(),
                        Colors.grey.shade500,
                      ),
                    ),
                    Expanded(
                      child: _buildFixedSubCell(
                        stat.net.toStringAsFixed(2),
                        Colors.black87,
                        isBold: true,
                      ),
                    ),
                  ],
                ),
              );
            }),
            Container(
              width: wTotalBlock,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.grey.shade300, width: 2),
                ),
                color: Colors.indigo.withValues(alpha: 0.02),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildFixedSubCell(
                      total.correct.toString(),
                      Colors.green.shade700,
                      isBold: true,
                    ),
                  ),
                  Expanded(
                    child: _buildFixedSubCell(
                      total.wrong.toString(),
                      Colors.red.shade700,
                      isBold: true,
                    ),
                  ),
                  Expanded(
                    child: _buildFixedSubCell(
                      total.empty.toString(),
                      Colors.grey.shade700,
                      isBold: true,
                    ),
                  ),
                  Expanded(
                    child: _buildFixedSubCell(
                      total.net.toStringAsFixed(2),
                      Colors.indigo.shade900,
                      isBold: true,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            _buildCell(
              student.score.toStringAsFixed(3),
              wScore,
              color: Colors.orange.shade50,
              useBorder: true,
            ),
            _buildCell(
              student.rankGeneral.toString(),
              wRank,
              color: Colors.blue.shade50,
              useBorder: true,
            ),
            _buildCell(
              student.rankInstitution.toString(),
              wRank,
              color: Colors.blue.shade50,
              useBorder: true,
            ),
            _buildCell(
              student.rankBranch.toString(),
              wRank,
              color: Colors.blue.shade50,
              useBorder: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(
    String text,
    double width, {
    Color? color,
    bool useBorder = false,
    VoidCallback? onTap,
  }) {
    Widget child = Container(
      width: width,
      decoration: useBorder
          ? BoxDecoration(
              color: color ?? Colors.transparent,
              border: Border(left: BorderSide(color: Colors.grey.shade300)),
            )
          : BoxDecoration(color: color ?? Colors.transparent),
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_sortColumn == text)
            Padding(
              padding: const EdgeInsets.only(left: 2.0),
              child: Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: Colors.blue,
              ),
            ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        hoverColor: Colors.grey.shade100,
        child: child,
      );
    }
    return child;
  }

  Widget _buildCell(
    String text,
    double width, {
    TextAlign align = TextAlign.center,
    Color? color,
    bool useBorder = false,
  }) {
    return Container(
      width: width,
      decoration: useBorder
          ? BoxDecoration(
              color: color,
              border: Border(left: BorderSide(color: Colors.grey.shade200)),
            )
          : BoxDecoration(color: color), // Simplified decoration
      alignment: align == TextAlign.center
          ? Alignment.center
          : Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: Colors.black87),
        textAlign: align,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildFixedSubCell(
    String text,
    Color color, {
    bool isBold = false,
    double fontSize = 12,
  }) {
    return Container(
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontSize: fontSize,
        ),
        overflow: TextOverflow.visible,
        softWrap: false,
      ),
    );
  }
}

