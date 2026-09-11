import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../models/school/butterfly_exam_model.dart';
import '../../../../models/school/seating_plan_model.dart';
import '../../../../models/assessment/trial_exam_model.dart';
import '../../../../services/butterfly_distribution_service.dart';
import '../../../../services/term_service.dart';
import '../../../../widgets/edukn_app_bar.dart';
import '../../../../widgets/custom_date_range_picker.dart';
import '../../../../widgets/custom_time_picker.dart';
import 'butterfly_exam_detail_screen.dart';

/// Kelebek Sınav Oluşturma Sihirbazı (4 Adımlı, Deneme Sınavı & Derslik & Gözetmen Entegreli)
class ButterflyExamWizardScreen extends StatefulWidget {
  final String institutionId;
  final String schoolTypeId;
  final String schoolTypeName;

  const ButterflyExamWizardScreen({
    super.key,
    required this.institutionId,
    required this.schoolTypeId,
    required this.schoolTypeName,
  });

  @override
  State<ButterflyExamWizardScreen> createState() => _ButterflyExamWizardScreenState();
}

class _ButterflyExamWizardScreenState extends State<ButterflyExamWizardScreen> {
  int _currentStep = 0;

  // 1. Adım: Sınav Bilgileri & Deneme Sınavı Entegrasyonu
  bool _isTrialExamMode = false;
  List<TrialExam> _availableTrialExams = [];
  TrialExam? _selectedTrialExam;

  final _titleController = TextEditingController(text: '1. Dönem Ortak Sınavı');
  final _lessonController = TextEditingController(text: 'Matematik');
  DateTime _examDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _examTime = const TimeOfDay(hour: 9, minute: 30);
  final _notesController = TextEditingController();

  // 2. Adım: Sınıflar, Öğrenciler & 3 Dağıtım Modu
  bool _isLoadingClasses = true;
  bool _isLoadingStudents = false;
  DistributionMode _distributionMode = DistributionMode.fullCross;
  List<Map<String, dynamic>> _availableClasses = [];
  final Set<String> _selectedClassIds = {};
  final List<ExamStudent> _selectedStudents = [];

  // 3. Adım: Sınav Salonları, Masa Düzenleri & Gözetmenler
  bool _isLoadingLayouts = true;
  bool _isLoadingClassrooms = true;
  bool _isLoadingTeachers = true;

  List<ClassroomLayout> _availableLayouts = [];
  List<Map<String, dynamic>> _availableClassrooms = [];
  List<Map<String, dynamic>> _availableTeachers = [];
  final List<Map<String, dynamic>> _configuredRooms = []; // {classroomId, classroomName, layoutId, layout, customCapacity, supervisorId, supervisorName}

  // 4. Adım: Dağıtım Ayarları (Boşlukları Eşit Dağıt Switch & PDF Sınav Adı Switch)
  bool _balanceEmptySeats = true;
  bool _showExamTitleOnPdf = true;
  bool _isDistributing = false;

  @override
  void initState() {
    super.initState();
    _loadAllInitialData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _lessonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // TÜM ENTEGRE VERİLERİ YÜKLEME (GÜVENLİ & SIRALI)
  // ===========================================================================
  Future<void> _loadAllInitialData() async {
    await _loadLayouts();
    await Future.wait([
      _loadTrialExams(),
      _loadClasses(),
      _loadClassrooms(),
      _loadTeachers(),
    ]);
  }

  /// 1. Tanımlanmış Deneme Sınavlarını Yükle
  Future<void> _loadTrialExams() async {
    try {
      final activeTermId = await TermService().getSelectedTermId() ?? await TermService().getActiveTermId();
      final snap = await FirebaseFirestore.instance
          .collection('trial_exams')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final list = snap.docs
          .map((d) => TrialExam.fromMap(d.data(), d.id))
          .where((e) => activeTermId == null || activeTermId.isEmpty || e.termId == activeTermId)
          .toList();
      list.sort((a, b) => b.date.compareTo(a.date));

      if (mounted) {
        setState(() {
          _availableTrialExams = list;
        });
      }
    } catch (e) {
      debugPrint('Deneme sınavları yüklenirken hata: $e');
    }
  }

  /// 2. Şubeleri Yükle
  Future<void> _loadClasses() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('classes')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final list = snap.docs.map((d) {
        final data = d.data();
        final cName = data['className']?.toString() ??
            data['name']?.toString() ??
            data['shortName']?.toString() ??
            'Şube';
        final gLevel = data['classLevel']?.toString() ??
            data['gradeLevel']?.toString() ??
            (cName.split('-').first.replaceAll(RegExp(r'[^0-9]'), ''));

        return {
          'id': d.id,
          'name': cName,
          'gradeLevel': gLevel.isNotEmpty ? '$gLevel. Sınıf' : '',
          'rawLevel': gLevel,
          'studentCount': data['studentCount'] ?? 0,
        };
      }).toList();

      list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      if (mounted) {
        setState(() {
          _availableClasses = list;
          _isLoadingClasses = false;
        });
      }
    } catch (e) {
      debugPrint('Sınıflar yüklenirken hata: $e');
      if (mounted) setState(() => _isLoadingClasses = false);
    }
  }

  /// 3. Masa Şablonlarını Yükle
  Future<void> _loadLayouts() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('seating_layouts')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      List<ClassroomLayout> layouts = snap.docs
          .map((d) => ClassroomLayout.fromMap(d.data(), d.id))
          .toList();

      if (layouts.isEmpty) {
        layouts = [
          ClassroomLayout.createPreset(
            presetType: '3_col_double_with_aisles',
            name: 'Standart 3 Blok (18 Masa / 36 Koltuk)',
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
          ),
          ClassroomLayout.createPreset(
            presetType: '3_col_double',
            name: '2 Geniş Blok (16 Masa / 32 Koltuk)',
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
          ),
          ClassroomLayout.createPreset(
            presetType: '2_col_single',
            name: 'Tekli Sınav Düzeni (20 Masa / 20 Koltuk)',
            institutionId: widget.institutionId,
            schoolTypeId: widget.schoolTypeId,
          ),
        ];
      }

      if (mounted) {
        setState(() {
          _availableLayouts = layouts;
          _isLoadingLayouts = false;
        });
      }
    } catch (e) {
      debugPrint('Şablonlar yüklenirken hata: $e');
      if (mounted) {
        setState(() {
          _availableLayouts = [
            ClassroomLayout.createPreset(
              presetType: '3_col_double_with_aisles',
              name: 'Standart 3 Blok (18 Masa / 36 Koltuk)',
              institutionId: widget.institutionId,
              schoolTypeId: widget.schoolTypeId,
            ),
          ];
          _isLoadingLayouts = false;
        });
      }
    }
  }

  /// 4. Derslikleri Yükle (Derslik Adı Temiz & Şifresiz)
  Future<void> _loadClassrooms() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('classrooms')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final list = snap.docs.asMap().entries.map((entry) {
        final idx = entry.key;
        final d = entry.value;
        final data = d.data();
        final cName = data['classroomName']?.toString() ??
            data['name']?.toString() ??
            data['classroomCode']?.toString() ??
            data['code']?.toString() ??
            'Salon ${idx + 1}';

        final cap = (data['capacity'] as num?)?.toInt() ?? 24;

        return {
          'id': d.id,
          'name': cName,
          'capacity': cap,
          'layoutId': data['layoutId']?.toString() ?? data['seatingLayoutId']?.toString(),
        };
      }).toList();

      list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      if (mounted) {
        setState(() {
          _availableClassrooms = list;
          _isLoadingClassrooms = false;

          // Varsayılan salonları derslik listesinden oluştur
          if (_configuredRooms.isEmpty) {
            final defaultLayout = _availableLayouts.isNotEmpty ? _availableLayouts.first : null;
            final defaultLayoutId = defaultLayout?.id ?? 'preset_default';

            if (list.isNotEmpty) {
              for (int i = 0; i < list.length.clamp(1, 2); i++) {
                final cr = list[i];
                final l = _findLayoutForClassroom(cr['layoutId'] as String?);
                _configuredRooms.add({
                  'classroomId': cr['id'] as String,
                  'classroomName': cr['name'] as String,
                  'layoutId': l.id ?? defaultLayoutId,
                  'layout': l,
                  'customCapacity': (cr['capacity'] as int?) ?? l.totalCapacity,
                  'supervisorId': null,
                  'supervisorName': '',
                });
              }
            } else {
              final l = _findLayoutForClassroom(null);
              _configuredRooms.add({
                'classroomId': 'salon_1',
                'classroomName': 'Salon 1',
                'layoutId': l.id ?? defaultLayoutId,
                'layout': l,
                'customCapacity': l.totalCapacity,
                'supervisorId': null,
                'supervisorName': '',
              });
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Derslikler yüklenirken hata: $e');
      if (mounted) setState(() => _isLoadingClassrooms = false);
    }
  }

  /// 5. Öğretmenleri ve Gerçek İsimlerini Yükle
  Future<void> _loadTeachers() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();

      final list = snap.docs.where((d) {
        final data = d.data();
        final role = data['role']?.toString().toLowerCase() ?? '';
        return role == 'teacher' || role == 'ogretmen' || role == 'admin' || role == 'manager' || data['branch'] != null;
      }).map((d) {
        final data = d.data();

        // Tüm olası isim alanlarını tara
        final String fullName = (data['fullName']?.toString() ??
            data['displayName']?.toString() ??
            data['nameSurname']?.toString() ??
            '${data['name'] ?? data['firstName'] ?? ''} ${data['surname'] ?? data['lastName'] ?? ''}').trim();

        final String finalName = fullName.isNotEmpty ? fullName : (data['email']?.toString() ?? 'Öğretmen');
        final branch = data['branch']?.toString() ?? data['department']?.toString() ?? 'Öğretmen';

        return {
          'id': d.id,
          'name': finalName,
          'branch': branch,
          'isAvailable': true,
          'busyInfo': '',
        };
      }).toList();

      list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      if (mounted) {
        setState(() {
          _availableTeachers = list;
          _isLoadingTeachers = false;
        });
      }
    } catch (e) {
      debugPrint('Öğretmenler yüklenirken hata: $e');
      if (mounted) setState(() => _isLoadingTeachers = false);
    }
  }

  ClassroomLayout _findLayoutForClassroom(String? layoutId) {
    if (layoutId != null && layoutId.isNotEmpty && _availableLayouts.isNotEmpty) {
      final match = _availableLayouts.where((l) => l.id == layoutId);
      if (match.isNotEmpty) return match.first;
    }
    if (_availableLayouts.isNotEmpty) {
      return _availableLayouts.first;
    }
    return ClassroomLayout.createPreset(
      presetType: '3_col_double_with_aisles',
      name: 'Standart 3 Blok (18 Masa / 36 Koltuk)',
      institutionId: widget.institutionId,
      schoolTypeId: widget.schoolTypeId,
    );
  }

  // ===========================================================================
  // MODALLER: DENEME SINAVI, DERSLİK VE GÖZETMEN SEÇİCİLER
  // ===========================================================================
  void _onTrialExamSelected(TrialExam? exam) {
    setState(() {
      _selectedTrialExam = exam;
      if (exam != null) {
        _titleController.text = exam.name;
        _lessonController.text = exam.examTypeName.isNotEmpty ? exam.examTypeName : 'Deneme Sınavı';
        _examDate = exam.date;

        _selectedClassIds.clear();
        final targetLevel = exam.classLevel.replaceAll(RegExp(r'[^0-9]'), '');

        for (final cls in _availableClasses) {
          final clsLevel = (cls['rawLevel'] as String?)?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
          final clsName = cls['name'] as String;

          final matchesLevel = targetLevel.isNotEmpty && clsLevel == targetLevel;
          final matchesBranch = exam.selectedBranches.any((b) => clsName.contains(b));

          if (matchesLevel || matchesBranch) {
            _selectedClassIds.add(cls['id'] as String);
          }
        }
      }
    });
  }

  /// Deneme Sınavı Arama ve Seçim Bottom Sheet Modalı
  void _showTrialExamPickerBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _availableTrialExams.where((e) {
              final q = searchQuery.toLowerCase();
              return e.name.toLowerCase().contains(q) ||
                  e.classLevel.toLowerCase().contains(q) ||
                  e.examTypeName.toLowerCase().contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Deneme Sınavı Seçin',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'Deneme sınavı adı veya sınıf ara...',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onChanged: (val) {
                          setModalState(() => searchQuery = val);
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Uygun deneme sınavı bulunamadı.',
                              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, idx) {
                              final exam = filtered[idx];
                              final isSelected = _selectedTrialExam?.id == exam.id;
                              final dStr = DateFormat('dd.MM.yyyy').format(exam.date);

                              return InkWell(
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _onTrialExamSelected(exam);
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.assignment_rounded,
                                          color: isSelected ? Colors.white : const Color(0xFF4F46E5),
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              exam.name,
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: const Color(0xFF1E293B),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${exam.classLevel} • $dStr • ${exam.examTypeName}',
                                              style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        const Icon(Icons.check_circle_rounded, color: Color(0xFF4F46E5), size: 20),
                                    ],
                                  ),
                                ),
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

  /// Derslik Seçim Modalı (Arama Çubuklu & Kompakt)
  void _showClassroomPickerModal(Map<String, dynamic> room) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _availableClassrooms.where((c) {
              final q = searchQuery.toLowerCase();
              final name = (c['name'] as String).toLowerCase();
              return name.contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.60,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Sınav Salonu / Derslik Seçin',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'Derslik veya salon adı ara...',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onChanged: (val) {
                          setModalState(() => searchQuery = val);
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 14),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, idx) {
                        final cr = filtered[idx];
                        final isSelected = room['classroomId'] == cr['id'];

                        return InkWell(
                          onTap: () {
                            setState(() {
                              room['classroomId'] = cr['id'];
                              room['classroomName'] = cr['name'];
                              room['customCapacity'] = (cr['capacity'] as int?) ?? 24;
                              if (cr['layoutId'] != null) {
                                final l = _findLayoutForClassroom(cr['layoutId']);
                                room['layout'] = l;
                                room['layoutId'] = l.id;
                              }
                            });
                            Navigator.pop(ctx);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.meeting_room_rounded, color: Color(0xFF4F46E5), size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cr['name'] as String,
                                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5, color: const Color(0xFF1E293B)),
                                      ),
                                      Text(
                                        'Kapasite: ${cr['capacity']} Koltuk',
                                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF4F46E5), size: 20),
                              ],
                            ),
                          ),
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

  /// Gözetmen Öğretmen Seçim Modalı (Öğretmen İsimleri Net, Müsaitler Yeşil Üstte)
  void _showSupervisorPickerModal(Map<String, dynamic> room) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _availableTeachers.where((t) {
              final q = searchQuery.toLowerCase();
              final name = (t['name'] as String).toLowerCase();
              final branch = (t['branch'] as String).toLowerCase();
              return name.contains(q) || branch.contains(q);
            }).toList();

            filtered.sort((a, b) {
              final aAv = (a['isAvailable'] as bool?) ?? true;
              final bAv = (b['isAvailable'] as bool?) ?? true;
              if (aAv == bAv) {
                return (a['name'] as String).compareTo(b['name'] as String);
              }
              return aAv ? -1 : 1;
            });

            return Container(
              height: MediaQuery.of(context).size.height * 0.60,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Gözetmen Öğretmen Seçin',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        autofocus: false,
                        decoration: InputDecoration(
                          hintText: 'Öğretmen adı veya branş ara...',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onChanged: (val) {
                          setModalState(() => searchQuery = val);
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          room['supervisorId'] = null;
                          room['supervisorName'] = '';
                        });
                        Navigator.pop(ctx);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_off_rounded, color: Color(0xFFEF4444), size: 18),
                            const SizedBox(width: 10),
                            Text(
                              'Gözetmen Atanmadı (İsteğe Bağlı)',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5, color: const Color(0xFFDC2626)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, idx) {
                        final t = filtered[idx];
                        final isSelected = room['supervisorId'] == t['id'];
                        final isAv = (t['isAvailable'] as bool?) ?? true;

                        return InkWell(
                          onTap: () {
                            setState(() {
                              room['supervisorId'] = t['id'];
                              room['supervisorName'] = t['name'];
                            });
                            Navigator.pop(ctx);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isAv ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isAv ? Icons.person_rounded : Icons.schedule_rounded,
                                    color: isAv ? const Color(0xFF10B981) : const Color(0xFFD97706),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              t['name'] as String,
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: const Color(0xFF1E293B),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isAv ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isAv ? 'Müsait' : 'Dersi Var',
                                              style: GoogleFonts.inter(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 10.5,
                                                color: isAv ? const Color(0xFF059669) : const Color(0xFFD97706),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${t['branch']}',
                                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle_rounded, color: Color(0xFF4F46E5), size: 20),
                              ],
                            ),
                          ),
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

  // ===========================================================================
  // ÖĞRENCİLERİ ÇEKME
  // ===========================================================================
  Future<void> _fetchStudentsForSelectedClasses() async {
    if (_selectedClassIds.isEmpty) return;

    setState(() => _isLoadingStudents = true);

    try {
      final List<ExamStudent> loaded = [];
      final classIdList = _selectedClassIds.toList();

      for (int i = 0; i < classIdList.length; i += 10) {
        final chunk = classIdList.sublist(i, (i + 10).clamp(0, classIdList.length));
        final snap = await FirebaseFirestore.instance
            .collection('students')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('classId', whereIn: chunk)
            .get();

        for (final doc in snap.docs) {
          final data = doc.data();
          final classInfo = _availableClasses.firstWhere(
            (c) => c['id'] == data['classId'],
            orElse: () => {'name': data['className'] ?? '', 'gradeLevel': ''},
          );

          loaded.add(ExamStudent(
            id: doc.id,
            name: data['name']?.toString() ?? '',
            surname: data['surname']?.toString() ?? '',
            studentNumber: data['studentNumber']?.toString() ?? '',
            classId: data['classId']?.toString() ?? '',
            className: classInfo['name']?.toString() ?? data['className']?.toString() ?? '',
            gradeLevel: classInfo['gradeLevel']?.toString() ?? '',
            gender: data['gender']?.toString(),
            photoUrl: data['photoUrl']?.toString(),
          ));
        }
      }

      setState(() {
        _selectedStudents.clear();
        _selectedStudents.addAll(loaded);
        _isLoadingStudents = false;
      });
    } catch (e) {
      debugPrint('Öğrenciler çekilirken hata: $e');
      setState(() => _isLoadingStudents = false);
    }
  }

  int get _totalConfiguredCapacity {
    int sum = 0;
    for (final r in _configuredRooms) {
      if (r['customCapacity'] != null) {
        sum += (r['customCapacity'] as int);
      } else {
        final layout = (r['layout'] as ClassroomLayout?) ?? _findLayoutForClassroom(r['layoutId'] as String?);
        sum += layout.totalCapacity;
      }
    }
    return sum;
  }

  // ===========================================================================
  // ARAYÜZ (GÖVDE)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: 'Kelebek Sınav Sihirbazı',
        subtitle: '${widget.schoolTypeName} • Adım ${_currentStep + 1} / 4',
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        subtitleColor: const Color(0xFF64748B),
        backButtonColor: const Color(0xFF4F46E5),
        borderColor: const Color(0xFFE2E8F0),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildCustomStepper(isMobile),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: _buildStepContent(isMobile),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(isMobile),
    );
  }

  Widget _buildCustomStepper(bool isMobile) {
    final steps = ['Sınav Bilgisi', 'Şubeler', 'Salon & Gözetmen', 'Kelebek Dağıtımı'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: List.generate(steps.length, (idx) {
          final isCompleted = _currentStep > idx;
          final isCurrent = _currentStep == idx;

          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? const Color(0xFF10B981)
                        : (isCurrent ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0)),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                        : Text(
                            '${idx + 1}',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isCurrent ? Colors.white : const Color(0xFF64748B),
                            ),
                          ),
                  ),
                ),
                if (!isMobile) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      steps[idx],
                      style: GoogleFonts.inter(
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                        fontSize: 12,
                        color: isCurrent ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                if (idx < steps.length - 1)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      height: 2.5,
                      color: isCompleted ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent(bool isMobile) {
    switch (_currentStep) {
      case 0:
        return _buildStep1ExamInfo();
      case 1:
        return _buildStep2ClassesSelection(isMobile);
      case 2:
        return _buildStep3RoomsAndLayouts(isMobile);
      case 3:
        return _buildStep4ReviewAndDistribute(isMobile);
      default:
        return const SizedBox();
    }
  }

  // ===========================================================================
  // 1. ADIM: SINAV BİLGİSİ
  // ===========================================================================
  Widget _buildStep1ExamInfo() {
    final dateStr = DateFormat('dd.MM.yyyy').format(_examDate);
    final timeStr = _examTime.format(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Sınav Oturum Bilgileri', 'Manuel sınav bilgisi girebilir veya Ölçme Değerlendirme modülünden tanımlı deneme sınavı seçebilirsiniz.'),
        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _isTrialExamMode = false;
                      _selectedTrialExam = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: !_isTrialExamMode ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: !_isTrialExamMode
                          ? [
                              BoxShadow(
                                color: const Color(0xFF64748B).withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        'Manuel Sınav Tanımla',
                        style: GoogleFonts.inter(
                          fontWeight: !_isTrialExamMode ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 13,
                          color: !_isTrialExamMode ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() => _isTrialExamMode = true);
                    _showTrialExamPickerBottomSheet();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _isTrialExamMode ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _isTrialExamMode
                          ? [
                              BoxShadow(
                                color: const Color(0xFF64748B).withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.assignment_outlined, size: 16, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 6),
                        Text(
                          'Deneme Sınavı Seç',
                          style: GoogleFonts.inter(
                            fontWeight: _isTrialExamMode ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 13,
                            color: _isTrialExamMode ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_isTrialExamMode) ...[
          InkWell(
            onTap: _showTrialExamPickerBottomSheet,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFC7D2FE), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF4F46E5), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedTrialExam != null ? _selectedTrialExam!.name : 'Deneme Sınavı Seçmek İçin Dokunun',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: const Color(0xFF1E293B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedTrialExam != null
                              ? '${_selectedTrialExam!.classLevel} • ${DateFormat("dd.MM.yyyy").format(_selectedTrialExam!.date)} • ${_selectedTrialExam!.examTypeName}'
                              : 'Ölçme ve Değerlendirme modülündeki sınavlar',
                          style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF4F46E5)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        _buildPremiumTextField(
          controller: _titleController,
          label: 'Sınav Başlığı',
          hint: 'Örn: 1. Dönem 1. Ortak Matematik Sınavı',
          icon: Icons.title_rounded,
        ),
        const SizedBox(height: 14),

        _buildPremiumTextField(
          controller: _lessonController,
          label: 'Ders Adı / Türü',
          hint: 'Örn: Matematik, Fen Bilimleri',
          icon: Icons.book_rounded,
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: Builder(
                builder: (btnCtx) => InkWell(
                  onTap: () => _pickDate(btnCtx),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            dateStr,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Builder(
                builder: (btnCtx) => InkWell(
                  onTap: () => _pickTime(btnCtx),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            timeStr,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        _buildPremiumTextField(
          controller: _notesController,
          label: 'Sınav Notları / Talimatlar (Opsiyonel)',
          hint: 'Örn: Optik formlar sınav başlamadan dağıtılacaktır.',
          icon: Icons.notes_rounded,
          maxLines: 2,
        ),
        const SizedBox(height: 14),

        // PDF Başlığında Sınav Adını Gösterme / Gizleme Switch'i
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF4F46E5), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PDF Başlığında Gerçek Sınav Adını Göster',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
                    ),
                    Text(
                      _showExamTitleOnPdf
                          ? 'PDF çıktılarında "${_titleController.text.isNotEmpty ? _titleController.text : 'Sınav Adı'}" görünecek'
                          : 'PDF çıktılarında gizlenecek, sadece "Deneme Sınavı" yazacak',
                      style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _showExamTitleOnPdf,
                activeTrackColor: const Color(0xFFC7D2FE),
                activeThumbColor: const Color(0xFF4F46E5),
                onChanged: (val) => setState(() => _showExamTitleOnPdf = val),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. ADIM: ŞUBELER, ÖĞRENCİLER & 3 FARKLI DAĞITIM MODU
  // ===========================================================================
  Widget _buildStep2ClassesSelection(bool isMobile) {
    if (_isLoadingClasses || _isLoadingStudents) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Sınav Dağıtım Modu & Şubeler', 'Öğrencilerin nasıl dağıtılacağını ve sınava girecek şubeleri belirleyin.'),
        const SizedBox(height: 12),

        _buildDistributionModeSelector(),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _selectedClassIds.addAll(_availableClasses.map((c) => c['id'] as String));
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.select_all_rounded, size: 16, color: Color(0xFF4F46E5)),
                    const SizedBox(width: 6),
                    Text('Tümünü Seç', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: const Color(0xFF4F46E5))),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: () {
                setState(() => _selectedClassIds.clear());
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.clear_all_rounded, size: 16, color: Color(0xFFEF4444)),
                    const SizedBox(width: 6),
                    Text('Seçimi Temizle', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: const Color(0xFFEF4444))),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _availableClasses.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isMobile ? 3 : 6,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.3,
          ),
          itemBuilder: (context, idx) {
            final cls = _availableClasses[idx];
            final id = cls['id'] as String;
            final isSelected = _selectedClassIds.contains(id);
            final branchName = cls['name'] as String;

            return InkWell(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedClassIds.remove(id);
                  } else {
                    _selectedClassIds.add(id);
                  }
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF4F46E5) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSelected ? const Color(0xFF4F46E5).withValues(alpha: 0.2) : const Color(0xFF64748B).withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        branchName,
                        style: GoogleFonts.inter(
                          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                          fontSize: 13,
                          color: isSelected ? Colors.white : const Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFC7D2FE)),
          ),
          child: Row(
            children: [
              const Icon(Icons.people_alt_rounded, color: Color(0xFF4F46E5), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_selectedClassIds.length} Şube Seçildi',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF312E81)),
                    ),
                    Text(
                      _getDistributionDescription(),
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF4338CA)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDistributionModeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          _buildModeRadioTile(
            mode: DistributionMode.fullCross,
            title: '1. Tam Kelebek (Seviyeler & Şubeler Çapraz)',
            subtitle: 'Farklı sınıf seviyeleri (örn. 5 ve 8) ve şubeler tam çapraz karışır.',
            icon: Icons.shuffle_rounded,
            iconColor: const Color(0xFF4F46E5),
          ),
          const Divider(height: 1),
          _buildModeRadioTile(
            mode: DistributionMode.gradeLevelCross,
            title: '2. Seviye İçi Çapraz (Seviyeler Ayrı, Şubeler Çapraz)',
            subtitle: 'Sınıf seviyeleri korunur, şubeler (8-A, 8-B) kendi içinde çapraz karışır.',
            icon: Icons.alt_route_rounded,
            iconColor: const Color(0xFF0284C7),
          ),
          const Divider(height: 1),
          _buildModeRadioTile(
            mode: DistributionMode.sequential,
            title: '3. Mevcut Şubelere Göre Sıralı Dağıtım',
            subtitle: 'Öğrenciler şube ve okul numarası sırasına göre standart ardışık yerleştirilir.',
            icon: Icons.format_list_numbered_rounded,
            iconColor: const Color(0xFF64748B),
          ),
        ],
      ),
    );
  }

  Widget _buildModeRadioTile({
    required DistributionMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    final isSelected = _distributionMode == mode;

    return InkWell(
      onTap: () => setState(() => _distributionMode = mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? iconColor.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: isSelected ? iconColor : const Color(0xFF64748B), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      fontSize: 13,
                      color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? iconColor : const Color(0xFFCBD5E1),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  String _getDistributionDescription() {
    switch (_distributionMode) {
      case DistributionMode.fullCross:
        return 'Tam Kelebek: Seviyeler ve şubeler yan yana/arka arkaya gelmeyecek şekilde çapraz yerleştirilir.';
      case DistributionMode.gradeLevelCross:
        return 'Seviye İçi Çapraz: Sınıf seviyeleri korunur, aynı seviyedeki şubeler kendi içinde çapraz dağıtılır.';
      case DistributionMode.sequential:
        return 'Sıralı: Öğrenciler şube ve okul numaralarına göre standart sıralı olarak salonlara yerleştirilir.';
    }
  }

  // ===========================================================================
  // 3. ADIM: SALONLAR, MASA DÜZENLERİ & ÖZEL KAPASİTE (PREMIUM MODAL SEÇİCİLER)
  // ===========================================================================
  Widget _buildStep3RoomsAndLayouts(bool isMobile) {
    if (_isLoadingLayouts || _isLoadingClassrooms || _isLoadingTeachers) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)));
    }

    final totalStudents = _selectedStudents.length;
    final totalCapacity = _totalConfiguredCapacity;
    final isCapacitySufficient = totalCapacity >= totalStudents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Sınav Salonları, Oturma Planları & Gözetmenler', 'Derslik belirleyin, kapasiteyi ayarlayın ve gözetmen öğretmen atayın.'),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isCapacitySufficient ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isCapacitySufficient ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
          ),
          child: Row(
            children: [
              Icon(
                isCapacitySufficient ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                color: isCapacitySufficient ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Toplam Kapasite: $totalCapacity Koltuk / $totalStudents Öğrenci',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        color: isCapacitySufficient ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                      ),
                    ),
                    Text(
                      isCapacitySufficient
                          ? 'Kapasite sınav için yeterli. Tüm öğrenciler oturma planlarına yerleştirilebilir.'
                          : 'Kapasite yetersiz! Lütfen yeni salon ekleyin veya salon kapasitesini artırın.',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: isCapacitySufficient ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: _configuredRooms.asMap().entries.map((entry) {
            final idx = entry.key;
            final room = entry.value;
            final selectedLayoutId = (room['layoutId'] as String?) ??
                ((room['layout'] as ClassroomLayout?)?.id ?? (_availableLayouts.isNotEmpty ? _availableLayouts.first.id : 'default'));

            final currentCap = (room['customCapacity'] as int?) ?? 24;

            final cardWidth = isMobile
                ? double.infinity
                : (MediaQuery.of(context).size.width - 64) / 2;

            return SizedBox(
              width: cardWidth,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF64748B).withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.meeting_room_rounded, color: Color(0xFF4F46E5), size: 18),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Salon ${idx + 1}',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14.5, color: const Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                        if (_configuredRooms.length > 1)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                            onPressed: () {
                              setState(() => _configuredRooms.removeAt(idx));
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 1. Derslik Seçici Kartı (Modal Açan Şık Buton)
                    InkWell(
                      onTap: () => _showClassroomPickerModal(room),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.domain_rounded, color: Color(0xFF4F46E5), size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                room['classroomName'] != null && (room['classroomName'] as String).isNotEmpty
                                    ? 'Derslik: ${room['classroomName']}'
                                    : 'Derslik Seçin',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1E293B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 2. Kapasite Değiştirme Stepper Çubuğu
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Kullanılacak Kapasite:',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5, color: const Color(0xFF475569)),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () {
                              if (currentCap > 1) {
                                setState(() => room['customCapacity'] = currentCap - 1);
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.remove_circle_outline_rounded, color: Color(0xFF64748B), size: 22),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Text(
                              '$currentCap Koltuk',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13, color: const Color(0xFF4F46E5)),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              setState(() => room['customCapacity'] = currentCap + 1);
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.add_circle_outline_rounded, color: Color(0xFF4F46E5), size: 22),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 3. Masa Düzeni Şablonu Dropdown
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _availableLayouts.any((l) => l.id == selectedLayoutId)
                          ? selectedLayoutId
                          : (_availableLayouts.isNotEmpty ? _availableLayouts.first.id : null),
                      decoration: _buildPremiumInputDecoration('Masa Şablonu'),
                      items: _availableLayouts.map((l) {
                        return DropdownMenuItem<String>(
                          value: l.id ?? l.name,
                          child: Text(
                            '${l.name} (${l.totalCapacity} Koltuk)',
                            style: GoogleFonts.inter(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (newLayoutId) {
                        if (newLayoutId != null) {
                          final match = _availableLayouts.firstWhere(
                            (l) => l.id == newLayoutId || l.name == newLayoutId,
                            orElse: () => _availableLayouts.first,
                          );
                          setState(() {
                            room['layoutId'] = match.id;
                            room['layout'] = match;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),

                    // 4. Gözetmen Öğretmen Seçici Butonu (Özel Bottom Sheet)
                    InkWell(
                      onTap: () => _showSupervisorPickerModal(room),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              room['supervisorName'] != null && (room['supervisorName'] as String).isNotEmpty
                                  ? Icons.person_rounded
                                  : Icons.person_add_alt_1_rounded,
                              color: const Color(0xFF4F46E5),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                room['supervisorName'] != null && (room['supervisorName'] as String).isNotEmpty
                                    ? 'Gözetmen: ${room['supervisorName']}'
                                    : 'Gözetmen Öğretmen Seç (İsteğe Bağlı)',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: room['supervisorName'] != null && (room['supervisorName'] as String).isNotEmpty
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: room['supervisorName'] != null && (room['supervisorName'] as String).isNotEmpty
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFF94A3B8),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF4F46E5),
              side: const BorderSide(color: Color(0xFFC7D2FE), width: 1.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              final nextIdx = _configuredRooms.length + 1;
              final classroom = _availableClassrooms.length >= nextIdx
                  ? _availableClassrooms[nextIdx - 1]
                  : null;
              final l = classroom?['layoutId'] != null
                  ? _findLayoutForClassroom(classroom!['layoutId'] as String?)
                  : _findLayoutForClassroom(null);

              setState(() {
                _configuredRooms.add({
                  'classroomId': classroom?['id'] ?? 'salon_$nextIdx',
                  'classroomName': classroom?['name'] ?? 'Salon $nextIdx',
                  'layoutId': l.id ?? 'preset_$nextIdx',
                  'layout': l,
                  'customCapacity': (classroom?['capacity'] as int?) ?? l.totalCapacity,
                  'supervisorId': null,
                  'supervisorName': '',
                });
              });
            },
            child: Text(
              'Yeni Sınav Salonu Ekle',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 4. ADIM: KELEBEK DAĞITIMI ÖZETİ & BOŞLUK DAĞITIM SWITCH'İ
  // ===========================================================================
  Widget _buildStep4ReviewAndDistribute(bool isMobile) {
    final totalStudents = _selectedStudents.length;
    final totalCapacity = _totalConfiguredCapacity;

    if (_isDistributing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Color(0xFF4F46E5)),
            const SizedBox(height: 20),
            Text(
              'Dağıtım Algoritması Çalıştırılıyor...',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14.5, color: const Color(0xFF1E293B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _getDistributionDescription(),
              style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Kelebek Dağıtımı Özeti', 'Dağıtım motorunu çalıştırmadan önce salon ve boşluk ayarlarını kontrol edin.'),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF64748B).withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildSummaryRow('Sınav Başlığı:', _titleController.text),
              _buildSummaryRow('Ders / Türü:', _lessonController.text),
              _buildSummaryRow('Tarih & Saat:', '${DateFormat("dd.MM.yyyy").format(_examDate)} • ${_examTime.format(context)}'),
              _buildSummaryRow('Seçilen Mod:', _getModeTitle(_distributionMode)),
              const Divider(height: 20),
              _buildSummaryRow('Dahil Edilen Şubeler:', '${_selectedClassIds.length} Şube'),
              _buildSummaryRow('Sınava Girecek Öğrenci:', '$totalStudents Öğrenci'),
              _buildSummaryRow('Açılan Salon Sayısı:', '${_configuredRooms.length} Salon'),
              _buildSummaryRow('Toplam Koltuk Kapasitesi:', '$totalCapacity Koltuk'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Boşluk Dağıtım Stratejisi Switch Butonu
        if (totalCapacity > totalStudents) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF64748B).withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.tune_rounded, color: Color(0xFF4F46E5), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Boş Koltuk Dağıtım Stratejisi',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
                      ),
                      Text(
                        _balanceEmptySeats
                            ? 'Boşlukları tüm salonlara eşit/dengeli paylaştır'
                            : 'Salonları sırayla doldur, boşluğu son sınıfa ver',
                        style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _balanceEmptySeats,
                  activeTrackColor: const Color(0xFFC7D2FE),
                  activeThumbColor: const Color(0xFF4F46E5),
                  onChanged: (val) => setState(() => _balanceEmptySeats = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _runDistributionAndPreview,
            icon: const Icon(Icons.auto_awesome_rounded, size: 22),
            label: Text(
              'DAĞITIMI YAP VE ÖNİZLE / DÜZENLE',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 13.5, letterSpacing: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  String _getModeTitle(DistributionMode mode) {
    switch (mode) {
      case DistributionMode.fullCross:
        return 'Tam Kelebek (Çapraz)';
      case DistributionMode.gradeLevelCross:
        return 'Seviye İçi Çapraz';
      case DistributionMode.sequential:
        return 'Mevcut Şubelere Göre Sıralı';
    }
  }

  // ===========================================================================
  // DAĞITIMI ÇALIŞTIRMA VE ÖNİZLEME / DÜZENLEME EKRANINA GEÇİŞ
  // ===========================================================================
  Future<void> _runDistributionAndPreview() async {
    final formattedTime = _examTime.format(context);
    setState(() => _isDistributing = true);

    try {
      final selectedClassNames = _availableClasses
          .where((c) => _selectedClassIds.contains(c['id']))
          .map((c) => c['name'] as String)
          .toList();

      final gradeLevels = _selectedStudents.map((s) => s.gradeLevel).toSet().toList();

      final params = ButterflyDistributionParams(
        title: _titleController.text.trim(),
        lessonName: _lessonController.text.trim(),
        institutionId: widget.institutionId,
        schoolTypeId: widget.schoolTypeId,
        schoolTypeName: widget.schoolTypeName,
        examDate: _examDate,
        examTime: formattedTime,
        selectedClassIds: _selectedClassIds.toList(),
        selectedClassNames: selectedClassNames,
        gradeLevels: gradeLevels,
        students: _selectedStudents,
        roomConfigs: _configuredRooms,
        notes: _notesController.text.trim(),
        distributionMode: _distributionMode,
        balanceEmptySeats: _balanceEmptySeats,
        showExamTitleOnPdf: _showExamTitleOnPdf,
      );

      final distribution = await ButterflyDistributionService.distributeExam(params);

      setState(() {
        _isDistributing = false;
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ButterflyExamDetailScreen(
              distribution: distribution,
              institutionId: widget.institutionId,
              schoolTypeId: widget.schoolTypeId,
              schoolTypeName: widget.schoolTypeName,
              isDraft: true,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Dağıtım hatası: $e');
      setState(() => _isDistributing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dağıtım sırasında hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ===========================================================================
  // ALT NAVİGASYON
  // ===========================================================================
  Widget _buildBottomNav(bool isMobile) {
    if (_currentStep == 3 && _isDistributing) return const SizedBox();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF64748B).withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: const Color(0xFF64748B),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => setState(() => _currentStep--),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Geri'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _onNextStepPressed,
                icon: Icon(_currentStep == 3 ? Icons.auto_awesome_rounded : Icons.arrow_forward_rounded, size: 18),
                label: Text(
                  _currentStep == 3 ? 'Dağıtımı Yap' : 'Sonraki Adım',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onNextStepPressed() async {
    if (_currentStep == 0) {
      if (_titleController.text.trim().isEmpty || _lessonController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen sınav başlığı ve ders adını doldurun.')),
        );
        return;
      }
      setState(() => _currentStep++);
    } else if (_currentStep == 1) {
      if (_selectedClassIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen sınava dahil edilecek en az bir şube seçin.')),
        );
        return;
      }
      await _fetchStudentsForSelectedClasses();
      setState(() => _currentStep++);
    } else if (_currentStep == 2) {
      if (_configuredRooms.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen en az bir sınav salonu tanımlayın.')),
        );
        return;
      }
      setState(() => _currentStep++);
    } else if (_currentStep == 3) {
      _runDistributionAndPreview();
    }
  }

  // ===========================================================================
  // YARDIMCI GÖRSEL BİLEŞENLER
  // ===========================================================================
  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15.5, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
        ),
      ],
    );
  }

  InputDecoration _buildPremiumInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _buildPremiumTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
          hintText: hint,
          hintStyle: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
          prefixIcon: Icon(icon, color: const Color(0xFF4F46E5), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B))),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B)),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate([BuildContext? btnContext]) async {
    final picked = await CustomDateRangePicker.showSingle(
      context,
      sourceContext: btnContext,
      initialDate: _examDate,
    );
    if (picked != null) setState(() => _examDate = picked);
  }

  Future<void> _pickTime([BuildContext? btnContext]) async {
    final picked = await CustomTimePicker.show(
      context,
      sourceContext: btnContext,
      initialTime: _examTime,
    );
    if (picked != null) setState(() => _examTime = picked);
  }
}
