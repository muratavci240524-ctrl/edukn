import 'dart:async';
import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../../../services/pdf_service.dart';
import '../../../models/school/duty_model.dart';
import '../../../services/term_service.dart';
import 'duty_settings_screen.dart';


class DutyProgramDetailScreen extends StatefulWidget {
  final String periodId;
  final String periodName;
  final String institutionId;
  /// 'alt_donem' | 'donem' — nöbetin hangi kapsam modunda oluşturulduğu
  final String scopeType;
  final String? schoolTypeId;
  final String? schoolTypeName;
  final DateTime? periodStartDate;
  final DateTime? periodEndDate;
  final String? termId;

  const DutyProgramDetailScreen({
    Key? key,
    required this.periodId,
    required this.periodName,
    required this.institutionId,
    this.scopeType = 'alt_donem', // geriye dönük uyumluluk için default
    this.periodStartDate,
    this.periodEndDate,
    this.schoolTypeId,
    this.schoolTypeName,
    this.termId,
  }) : super(key: key);

  @override
  State<DutyProgramDetailScreen> createState() =>
      _DutyProgramDetailScreenState();
}

class _DutyProgramDetailScreenState extends State<DutyProgramDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Calendar Data
  List<DutyLocation> _locations = [];
  Map<String, DutyScheduleItem> _matrix = {}; // key: "locId_day"
  bool _isLoading = false;
  late DateTime _selectedWeekStart;

  // Statistics Data
  List<DutyScheduleItem> _statsItems = [];
  List<DutyScheduleItem> _allPeriodDutyItems = []; // Anlık tüm alt dönem nöbetleri
  List<QueryDocumentSnapshot> _teachers = []; // Cache teachers
  late DateTime _statsStartDate;
  late DateTime _statsEndDate;
  DateTime? _periodStartDate;
  DateTime? _periodEndDate;
  bool _isStatsLoading = false;
  // İstatistik tablosunda öğretmen arama
  bool _statsSearchOpen = false;
  String _statsSearch = '';
  final TextEditingController _statsSearchCtrl = TextEditingController();

  /// Türkçe uyumlu, büyük/küçük harf ve aksan duyarsız normalleştirme.
  /// "YILMAZ", "yılmaz", "yilmaz" → hepsi eşleşir.
  static String _normalizeTr(String s) {
    return s
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('i̇', 'i') // birleşik nokta (İ.toLowerCase())
        .replaceAll('ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
  bool _customStatsDateRangePicked = false;
  bool _isFabMenuOpen = false;

  // Real-time Firestore Dinleyici
  StreamSubscription<QuerySnapshot>? _dutyItemsSub;
  String? _termId;

  @override
  void initState() {
    super.initState();
    _termId = widget.termId;
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        if (_tabController.index == 1) {
          _updateStatsForSelectedRange();
        }
        if (_tabController.index != 0) {
          _isFabMenuOpen = false;
        }
        setState(() {});
      }
    });

    // 1. Calendar: Current Week's Monday
    final now = DateTime.now();
    _selectedWeekStart = now.subtract(Duration(days: now.weekday - 1));
    _selectedWeekStart = DateTime(
      _selectedWeekStart.year,
      _selectedWeekStart.month,
      _selectedWeekStart.day,
    );

    // 2. Stats: SADECE alt dönemin tarihleri (kullanıcı talebi)
    if (widget.periodStartDate != null && widget.periodEndDate != null) {
      _periodStartDate = widget.periodStartDate;
      _periodEndDate = widget.periodEndDate;
      _statsStartDate = widget.periodStartDate!;
      _statsEndDate = widget.periodEndDate!;
    } else {
      _statsStartDate = DateTime(now.year, now.month, 1);
      _statsEndDate = DateTime(now.year, now.month + 1, 0); // Last day of month
    }

    _loadData(); // Load Calendar & Teachers
    _loadStatsData(); // Load Stats
    _initDutyItemsStream(); // Anlık Firestore dinleyiciyi başlat
  }

  @override
  void dispose() {
    _dutyItemsSub?.cancel();
    _tabController.dispose();
    _statsSearchCtrl.dispose();
    super.dispose();
  }

  bool _isVicePrincipal(Map<String, dynamic> data) {
    final checkStrings = <String>[];
    for (var key in ['role', 'title', 'position', 'duty', 'subRole', 'userRole', 'department']) {
      final val = data[key];
      if (val != null) checkStrings.add(val.toString().toLowerCase().trim());
    }
    if (data['roles'] is List) {
      for (var r in (data['roles'] as List)) {
        if (r != null) checkStrings.add(r.toString().toLowerCase().trim());
      }
    }

    for (var str in checkStrings) {
      if (str == 'mudur_yardimcisi' ||
          str == 'mudir_yardimcisi' ||
          str == 'müdür yardımcısı' ||
          str == 'mudur yardimcisi' ||
          str == 'müdür yrd.' ||
          str == 'müdür yrd' ||
          str == 'mudur yrd' ||
          str == 'vice_principal' ||
          (str.contains('müdür') && (str.contains('yardımc') || str.contains('yrd'))) ||
          (str.contains('mudur') && (str.contains('yardimc') || str.contains('yrd')))) {
        return true;
      }
    }
    return false;
  }

  bool _isPrincipalOrManager(Map<String, dynamic> data) {
    if (_isVicePrincipal(data)) return false;

    final checkStrings = <String>[];
    for (var key in ['role', 'title', 'position', 'duty', 'subRole', 'userRole']) {
      final val = data[key];
      if (val != null) checkStrings.add(val.toString().toLowerCase().trim());
    }
    if (data['roles'] is List) {
      for (var r in (data['roles'] as List)) {
        if (r != null) checkStrings.add(r.toString().toLowerCase().trim());
      }
    }

    for (var str in checkStrings) {
      if (str == 'mudur' ||
          str == 'müdür' ||
          str == 'okul_muduru' ||
          str == 'okul müdürü' ||
          str == 'okul muduru' ||
          str == 'genel_mudur' ||
          str == 'genel müdür' ||
          str == 'kurum_muduru' ||
          str == 'kurum müdürü' ||
          str == 'kurum yöneticisi' ||
          str == 'kurum_yoneticisi' ||
          str == 'yonetici' ||
          str == 'yönetici' ||
          str == 'principal' ||
          str == 'director' ||
          (str.contains('müdür') && !str.contains('yardımc') && !str.contains('yrd')) ||
          (str.contains('mudur') && !str.contains('yardimc') && !str.contains('yrd'))) {
        return true;
      }
    }
    return false;
  }

  String _getUserDisplayTitle(Map<String, dynamic> data) {
    if (_isVicePrincipal(data)) {
      return 'Müdür Yardımcısı';
    }
    if (_isPrincipalOrManager(data)) {
      return 'Okul Müdürü';
    }
    if (data['branches'] is List && (data['branches'] as List).isNotEmpty) {
      return (data['branches'] as List).first.toString();
    } else if (data['branch'] is String && (data['branch'] as String).trim().isNotEmpty) {
      return (data['branch'] as String).trim();
    }
    final title = data['title']?.toString().trim();
    if (title != null && title.isNotEmpty && title.toLowerCase() != 'öğretmen') {
      return title;
    }
    return 'Öğretmen';
  }

  bool _isUserInSchoolType(
    Map<String, dynamic> data,
    String? targetSchoolTypeId, {
    String? targetSchoolTypeName,
  }) {
    final targetId = targetSchoolTypeId?.trim() ?? '';
    final targetName = targetSchoolTypeName?.trim() ?? '';

    if (targetId.isEmpty && targetName.isEmpty) {
      return true;
    }

    final targetIdLower = targetId.toLowerCase();
    final targetNameLower = targetName.toLowerCase();

    final userSchoolTypes = <String>{};

    // 1. data['schoolTypes'] (List of IDs, names or Maps)
    if (data['schoolTypes'] is List) {
      for (var item in (data['schoolTypes'] as List)) {
        if (item is Map) {
          final mId = item['id']?.toString().trim();
          if (mId != null && mId.isNotEmpty) {
            userSchoolTypes.add(mId);
            userSchoolTypes.add(mId.toLowerCase());
          }
          final mName = item['name']?.toString().trim();
          if (mName != null && mName.isNotEmpty) {
            userSchoolTypes.add(mName);
            userSchoolTypes.add(mName.toLowerCase());
          }
        } else {
          final str = item?.toString().trim();
          if (str != null && str.isNotEmpty) {
            userSchoolTypes.add(str);
            userSchoolTypes.add(str.toLowerCase());
          }
        }
      }
    }

    // 2. data['workLocations'] (List of school type names, e.g. ['İlkokul', 'Ortaokul'])
    if (data['workLocations'] is List) {
      for (var item in (data['workLocations'] as List)) {
        final str = item?.toString().trim();
        if (str != null && str.isNotEmpty) {
          userSchoolTypes.add(str);
          userSchoolTypes.add(str.toLowerCase());
        }
      }
    }

    // 3. data['workLocation'] (String, e.g. 'İlkokul')
    final wLoc = data['workLocation']?.toString().trim();
    if (wLoc != null && wLoc.isNotEmpty) {
      userSchoolTypes.add(wLoc);
      userSchoolTypes.add(wLoc.toLowerCase());
    }

    // 4. data['schoolTypePermissions'] (Map)
    if (data['schoolTypePermissions'] is Map) {
      final perms = data['schoolTypePermissions'] as Map;
      for (var key in perms.keys) {
        final str = key?.toString().trim();
        if (str != null && str.isNotEmpty) {
          userSchoolTypes.add(str);
          userSchoolTypes.add(str.toLowerCase());
        }
      }
    }

    // 5. data['schoolTypeId'] (String)
    final sId = data['schoolTypeId']?.toString().trim();
    if (sId != null && sId.isNotEmpty) {
      userSchoolTypes.add(sId);
      userSchoolTypes.add(sId.toLowerCase());
    }

    // 6. data['schoolTypeIds'] (List)
    if (data['schoolTypeIds'] is List) {
      for (var item in (data['schoolTypeIds'] as List)) {
        final str = item?.toString().trim();
        if (str != null && str.isNotEmpty) {
          userSchoolTypes.add(str);
          userSchoolTypes.add(str.toLowerCase());
        }
      }
    }

    // 7. data['schoolType'] / schoolTypeName / school / schoolName / schools / assignedSchools
    for (var key in ['schoolType', 'schoolTypeName', 'school', 'schoolName']) {
      final s = data[key]?.toString().trim();
      if (s != null && s.isNotEmpty) {
        userSchoolTypes.add(s);
        userSchoolTypes.add(s.toLowerCase());
      }
    }
    for (var key in ['schools', 'assignedSchools']) {
      if (data[key] is List) {
        for (var item in (data[key] as List)) {
          final str = item?.toString().trim();
          if (str != null && str.isNotEmpty) {
            userSchoolTypes.add(str);
            userSchoolTypes.add(str.toLowerCase());
          }
        }
      }
    }

    // 8. Eğer kullanıcının herhangi bir okul türü kaydı varsa hedef ile eşleşiyor mu kontrol et:
    if (userSchoolTypes.isNotEmpty) {
      if (targetId.isNotEmpty &&
          (userSchoolTypes.contains(targetId) || userSchoolTypes.contains(targetIdLower))) {
        return true;
      }
      if (targetName.isNotEmpty &&
          (userSchoolTypes.contains(targetName) || userSchoolTypes.contains(targetNameLower))) {
        return true;
      }
      return false;
    }

    // Kullanıcıda okul türü bulunamadıysa ve işlem yapılan okul türü belliyse sızmaları önlemek için gösterme
    return false;
  }

  bool _isUserActive(
    Map<String, dynamic> data, {
    String? termId,
    String? schoolTypeId,
    String? schoolTypeName,
  }) {
    // 0. Okul Müdürü / Kurum Müdürü kontrolü: Müdür yetkisinde olanlara nöbet yazılamaz
    if (_isPrincipalOrManager(data)) {
      return false;
    }

    // 1. Pasiflik kontrolleri
    final isActive = data['isActive'];
    if (isActive != null) {
      if (isActive == false || isActive == 'false') return false;
    }
    if (data['isPassive'] == true || data['isPassive'] == 'true') return false;

    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    if (status == 'passive' || status == 'pasif' || status == 'inactive') return false;

    // 2. Eğer kullanıcıda dönem tanımlıysa mevcut dönemle eşleşmeli
    if (termId != null && termId.isNotEmpty) {
      final uTermId = data['termId']?.toString().trim();
      if (uTermId != null && uTermId.isNotEmpty && uTermId != termId) {
        return false;
      }
      final uAcadTermId = data['academicTermId']?.toString().trim();
      if (uAcadTermId != null && uAcadTermId.isNotEmpty && uAcadTermId != termId) {
        return false;
      }
      if (data['termIds'] is List) {
        final tList = (data['termIds'] as List).map((e) => e.toString().trim()).toList();
        if (tList.isNotEmpty && !tList.contains(termId)) {
          return false;
        }
      }
    }

    // 3. Okul türü kontrolü: Farklı okul türündekiler görünmeyecek, birden fazlasında görevliyse görünecek
    if (!_isUserInSchoolType(data, schoolTypeId, targetSchoolTypeName: schoolTypeName)) {
      return false;
    }

    return true;
  }

  // --- Calendar Loading ---
  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      // 0. Resolve termId if not provided
      if (_termId == null || _termId!.isEmpty) {
        if (widget.scopeType == 'donem') {
          _termId = widget.periodId;
        } else {
          try {
            final pDoc = await FirebaseFirestore.instance
                .collection('workPeriods')
                .doc(widget.periodId)
                .get();
            _termId = pDoc.data()?['termId']?.toString();
          } catch (silentError) { debugPrint('[duty_program_detail_screen] hata yutuldu: $silentError'); }
          if (_termId == null || _termId!.isEmpty) {
            final selectedTermId = await TermService().getSelectedTermId();
            final activeTermId = await TermService().getActiveTermId();
            _termId = selectedTermId ?? activeTermId;
          }
        }
      }

      // 1. Load Teachers (if not loaded) - sadece aktif ve mevcut okul türüyle uyumlu olanlar
      if (_teachers.isEmpty) {
        final selectedTermId = await TermService().getSelectedTermId();
        final activeTermId = await TermService().getActiveTermId();
        final effectiveTermId = _termId ?? selectedTermId ?? activeTermId;

        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('institutionId', isEqualTo: widget.institutionId)
            .where('type', whereIn: ['teacher', 'staff', 'admin'])
            .get();
        _teachers = userSnap.docs
            .where((d) => _isUserActive(
                  d.data(),
                  termId: effectiveTermId,
                  schoolTypeId: widget.schoolTypeId,
                  schoolTypeName: widget.schoolTypeName,
                ))
            .toList();
      }

      // 2. Load Locations (shared + period overrides)
      if (_locations.isEmpty) {
        final locSnap = await FirebaseFirestore.instance
            .collection('dutyLocations')
            .where('institutionId', isEqualTo: widget.institutionId)
            .get();
        var allLocations = locSnap.docs.map((d) {
          final data = d.data();
          data['id'] = d.id;
          return DutyLocation.fromMap(data);
        }).toList();

        // Alt dönem ayarlarını kontrol et (varsayılan kapalı; sadece isEnabled == true olanlar takvime gelir)
        if (widget.periodId.isNotEmpty) {
          final periodDoc = await FirebaseFirestore.instance
              .collection('workPeriods')
              .doc(widget.periodId)
              .get();
          if (periodDoc.exists) {
            final pData = periodDoc.data();
            final pStart = (pData?['startDate'] as Timestamp?)?.toDate();
            final pEnd = (pData?['endDate'] as Timestamp?)?.toDate();
            if (pStart != null && pEnd != null) {
              _periodStartDate = pStart;
              _periodEndDate = pEnd;
              if (!_customStatsDateRangePicked) {
                _statsStartDate = pStart;
                _statsEndDate = pEnd;
                _updateStatsForSelectedRange();
              }
            }
            final locConfigs = (periodDoc.data()?['dutyLocationConfigs'] as Map<String, dynamic>?) ?? {};

            allLocations = allLocations.where((loc) {
              final cfg = locConfigs[loc.id] as Map<String, dynamic>?;
              return cfg != null && cfg['isEnabled'] == true;
            }).map((loc) {
              final cfg = locConfigs[loc.id] as Map<String, dynamic>?;
              if (cfg != null) {
                final ovDays = cfg['activeDays'] != null
                    ? List<int>.from(cfg['activeDays'])
                    : loc.activeDays;
                final ovStart = cfg['startTime'] ?? loc.startTime;
                final ovEnd = cfg['endTime'] ?? loc.endTime;
                final ovOrder = (cfg['order'] as num?)?.toInt() ?? loc.order;
                final ovGroup = (cfg['group'] ?? loc.group ?? '').toString().trim();
                return DutyLocation(
                  id: loc.id,
                  institutionId: loc.institutionId,
                  name: loc.name,
                  activeDays: ovDays,
                  startTime: ovStart,
                  endTime: ovEnd,
                  description: loc.description,
                  checkOtherDays: loc.checkOtherDays,
                  order: ovOrder,
                  group: ovGroup,
                  eligibilities: loc.eligibilities,
                );
              }
              return loc;
            }).toList();
          } else {
            allLocations = [];
          }
        }

        allLocations.sort((a, b) {
          final cmp = a.order.compareTo(b.order);
          if (cmp != 0) return cmp;
          return a.name.compareTo(b.name);
        });
        _locations = allLocations;
      } else {
        _locations.sort((a, b) {
          final cmp = a.order.compareTo(b.order);
          if (cmp != 0) return cmp;
          return a.name.compareTo(b.name);
        });
      }

      // 3. Load Items for Selected Week
      final weekStr = _selectedWeekStart.toIso8601String();
      final itemsSnap = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('periodId', isEqualTo: widget.periodId)
          .where('weekStart', isEqualTo: weekStr)
          .get();

      _matrix.clear();
      for (var doc in itemsSnap.docs) {
        final item = DutyScheduleItem.fromMap(doc.data(), doc.id);
        final key = '${item.locationId}_${item.dayOfWeek}';
        _matrix[key] = item;
      }
    } catch (e) {
      debugPrint('Error loading calendar data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Stats Loading ---
  Future<void> _loadStatsData() async {
    if (mounted) setState(() => _isStatsLoading = true);
    try {
      // Query items where weekStart is within range
      // Query items where weekStart is within range
      // NOTE: We filter by date CLIENT-SIDE to avoid creating a Composite Index
      // for (periodId + weekStart). This ensures immediate functionality.
      final itemsSnap = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('periodId', isEqualTo: widget.periodId)
          .get();

      final filterEnd = _statsEndDate.add(const Duration(days: 1));
      final allItems = <DutyScheduleItem>[];
      final statsList = <DutyScheduleItem>[];

      for (var d in itemsSnap.docs) {
        final item = DutyScheduleItem.fromMap(d.data(), d.id);
        allItems.add(item);
        if (item.weekStart != null) {
          if (item.weekStart!.compareTo(_statsStartDate) >= 0 &&
              item.weekStart!.compareTo(filterEnd) < 0) {
            statsList.add(item);
          }
        }
      }

      _allPeriodDutyItems = allItems;
      _statsItems = statsList;
    } catch (e) {
      debugPrint('Error loading stats data: $e');
    } finally {
      if (mounted) setState(() => _isStatsLoading = false);
    }
  }

  /// Firestore'daki dutyScheduleItems değişikliklerini anlık (real-time) dinler.
  /// Bir öğretmene nöbet yazıldığında, silindiğinde veya değiştirildiğinde
  /// hem takvim hem de istatistikler 0ms içinde anlık güncellenir.
  void _initDutyItemsStream() {
    _dutyItemsSub?.cancel();
    _dutyItemsSub = FirebaseFirestore.instance
        .collection('dutyScheduleItems')
        .where('periodId', isEqualTo: widget.periodId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final allItems = <DutyScheduleItem>[];
      final newMatrix = <String, DutyScheduleItem>{};
      final statsList = <DutyScheduleItem>[];
      final startDay = DateTime(_statsStartDate.year, _statsStartDate.month, _statsStartDate.day);
      final endDay = DateTime(_statsEndDate.year, _statsEndDate.month, _statsEndDate.day, 23, 59, 59);

      for (var doc in snapshot.docs) {
        final item = DutyScheduleItem.fromMap(doc.data(), doc.id);
        allItems.add(item);

        // Seçili haftadaki nöbetler
        if (item.weekStart != null &&
            item.weekStart!.year == _selectedWeekStart.year &&
            item.weekStart!.month == _selectedWeekStart.month &&
            item.weekStart!.day == _selectedWeekStart.day) {
          final key = '${item.locationId}_${item.dayOfWeek}';
          newMatrix[key] = item;
        }

        // İstatistik tarih aralığındaki nöbetler
        if (item.weekStart != null) {
          final d = DateTime(item.weekStart!.year, item.weekStart!.month, item.weekStart!.day);
          if (!d.isBefore(startDay) && !d.isAfter(endDay)) {
            statsList.add(item);
          }
        }
      }

      setState(() {
        _allPeriodDutyItems = allItems;
        _matrix = newMatrix;
        _statsItems = statsList;
        _isStatsLoading = false;
      });
    }, onError: (e) {
      debugPrint('Duty items stream error: $e');
    });
  }

  void _updateMatrixForSelectedWeek() {
    final newMatrix = <String, DutyScheduleItem>{};
    for (var item in _allPeriodDutyItems) {
      if (item.weekStart != null &&
          item.weekStart!.year == _selectedWeekStart.year &&
          item.weekStart!.month == _selectedWeekStart.month &&
          item.weekStart!.day == _selectedWeekStart.day) {
        final key = '${item.locationId}_${item.dayOfWeek}';
        newMatrix[key] = item;
      }
    }
    setState(() {
      _matrix = newMatrix;
    });
  }

  void _updateStatsForSelectedRange() {
    final startDay = DateTime(_statsStartDate.year, _statsStartDate.month, _statsStartDate.day);
    final endDay = DateTime(_statsEndDate.year, _statsEndDate.month, _statsEndDate.day, 23, 59, 59);
    final statsList = _allPeriodDutyItems.where((item) {
      if (item.weekStart == null) return false;
      final d = DateTime(item.weekStart!.year, item.weekStart!.month, item.weekStart!.day);
      return !d.isBefore(startDay) && !d.isAfter(endDay);
    }).toList();
    setState(() {
      _statsItems = statsList;
    });
  }

  void _changeWeek(int weeks) {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.add(Duration(days: weeks * 7));
    });
    _updateMatrixForSelectedWeek();
    _loadData();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedWeekStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('tr', 'TR'),
    );
    if (picked != null) {
      setState(() {
        _selectedWeekStart = picked.subtract(
          Duration(days: picked.weekday - 1),
        );
        _selectedWeekStart = DateTime(
          _selectedWeekStart.year,
          _selectedWeekStart.month,
          _selectedWeekStart.day,
        );
      });
      _updateMatrixForSelectedWeek();
      _loadData();
    }
  }

  // Pick Range for Stats
  Future<void> _selectStatsDateRange() async {
    final firstAllowed = _periodStartDate ?? DateTime(2020);
    final lastAllowed = _periodEndDate ?? DateTime(2030);

    final initialStart = _statsStartDate.isBefore(firstAllowed)
        ? firstAllowed
        : (_statsStartDate.isAfter(lastAllowed) ? firstAllowed : _statsStartDate);
    final initialEnd = _statsEndDate.isAfter(lastAllowed)
        ? lastAllowed
        : (_statsEndDate.isBefore(firstAllowed) ? lastAllowed : _statsEndDate);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstAllowed,
      lastDate: lastAllowed,
      initialDateRange: DateTimeRange(
        start: initialStart,
        end: initialEnd.isBefore(initialStart) ? initialStart : initialEnd,
      ),
      locale: const Locale('tr', 'TR'),
      saveText: 'Seç',
      helpText: '${widget.periodName} Tarih Aralığı',
    );
    if (picked != null) {
      setState(() {
        _customStatsDateRangePicked = true;
        _statsStartDate = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        );
        _statsEndDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
        );
      });
      _updateStatsForSelectedRange();
      _loadStatsData();
    }
  }

  Future<void> _printReport() async {
    // If we are on stats tab, print stats
    if (_tabController.index == 1) {
      await _printStatsReport();
      return;
    }

    final pdfService = PdfService();
    final dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
    final weekStartStr = dateFormat.format(_selectedWeekStart);
    final weekEndStr = dateFormat.format(
      _selectedWeekStart.add(const Duration(days: 6)),
    );

    // Okul türüne atalı müdürün adını otomatik çek
    final principalName = await _resolveSchoolPrincipalName();

    // Determine active days
    Set<int> activeDayIndices = {};
    for (var loc in _locations) {
      activeDayIndices.addAll(loc.activeDays);
    }
    List<int> sortedDays = activeDayIndices.toList()..sort();

    // Headers
    List<String> headers = ['NÖBET YERİ'];
    for (var d in sortedDays) {
      headers.add(_getDayName(d));
    }

    // Rows
    List<List<String>> rows = [];
    for (var loc in _locations) {
      List<String> row = [loc.name];
      for (var d in sortedDays) {
        final key = '${loc.id}_$d';
        final item = _matrix[key];
        row.add(item?.teacherName ?? '');
      }
      rows.add(row);
    }

    final pdfData = await pdfService.generateDutySchedulePdf(
      periodName: widget.periodName,
      weekRange: '$weekStartStr - $weekEndStr',
      days: headers,
      rows: rows,
      schoolName: widget.schoolTypeName,
      principalName: principalName,
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdfData,
      name: 'Nobet_Cizelgesi_$weekStartStr',
      format: PdfPageFormat.a4,
    );
  }

  Future<String?> _resolveSchoolPrincipalName() async {
    try {
      // 1. schoolTypes dokümanında atanmış müdür adı var mı kontrol et
      if (widget.schoolTypeId != null && widget.schoolTypeId!.isNotEmpty) {
        final stDoc = await FirebaseFirestore.instance
            .collection('schoolTypes')
            .doc(widget.schoolTypeId)
            .get();
        if (stDoc.exists) {
          final stData = stDoc.data();
          final pName = stData?['principalName'] ??
              stData?['managerName'] ??
              stData?['mudurName'] ??
              stData?['mudur'] ??
              stData?['directorName'];
          if (pName != null && pName.toString().trim().isNotEmpty) {
            return pName.toString().trim();
          }
        }
      }

      // 2. users koleksiyonundan bu kuruma ve bu okul türüne ait müdürü bul
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('isActive', isEqualTo: true)
          .get();

      final schoolPrincipals = <Map<String, dynamic>>[];
      final generalPrincipals = <Map<String, dynamic>>[];

      for (var doc in usersSnap.docs) {
        final data = doc.data();
        if (_isPrincipalOrManager(data)) {
          final fullName =
              (data['fullName'] ?? data['name'] ?? '').toString().trim();
          if (fullName.isEmpty) continue;

          if (_isUserInSchoolType(
            data,
            widget.schoolTypeId,
            targetSchoolTypeName: widget.schoolTypeName,
          )) {
            schoolPrincipals.add(data);
          } else {
            generalPrincipals.add(data);
          }
        }
      }

      if (schoolPrincipals.isNotEmpty) {
        final exactMudur = schoolPrincipals.firstWhere(
          (u) {
            final role = (u['role'] ?? '').toString().toLowerCase();
            return role == 'mudur' || role == 'okul_muduru';
          },
          orElse: () => schoolPrincipals.first,
        );
        return (exactMudur['fullName'] ?? exactMudur['name'] ?? '')
            .toString()
            .trim();
      }

      if (generalPrincipals.isNotEmpty) {
        final exactMudur = generalPrincipals.firstWhere(
          (u) {
            final role = (u['role'] ?? '').toString().toLowerCase();
            return role == 'mudur' ||
                role == 'genel_mudur' ||
                role == 'okul_muduru';
          },
          orElse: () => generalPrincipals.first,
        );
        return (exactMudur['fullName'] ?? exactMudur['name'] ?? '')
            .toString()
            .trim();
      }
    } catch (e) {
      debugPrint('Error resolving school principal: $e');
    }
    return null;
  }

  Future<void> _printStatsReport() async {
    final pdfService = PdfService();
    final dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
    final rangeStr =
        '${dateFormat.format(_statsStartDate)} - ${dateFormat.format(_statsEndDate)}';

    // Prepare Data
    final selectedTermId = await TermService().getSelectedTermId();
    final activeTermId = await TermService().getActiveTermId();
    final effectiveTermId = selectedTermId ?? activeTermId;

    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('institutionId', isEqualTo: widget.institutionId)
        .where('type', whereIn: ['teacher', 'staff', 'admin'])
        .get();

    final teachers = userSnap.docs
        .where((d) => _isUserActive(
              d.data(),
              termId: effectiveTermId,
              schoolTypeId: widget.schoolTypeId,
              schoolTypeName: widget.schoolTypeName,
            ))
        .toList();
    List<Map<String, dynamic>> stats = [];

    for (var t in teachers) {
      final tid = t.id;
      final tData = t.data();
      final tName = tData['fullName'] ?? tData['name'] ?? 'İsimsiz';
      final branch = _getUserDisplayTitle(tData);

      int total = 0;
      Map<String, int> locCounts = {};
      for (var l in _locations) locCounts[l.id] = 0;

      for (var item in _statsItems) {
        if (item.teacherId == tid) {
          total++;
          locCounts[item.locationId] = (locCounts[item.locationId] ?? 0) + 1;
        }
      }

      stats.add({'name': tName, 'branch': branch, 'total': total, 'locCounts': locCounts});
    }

    stats.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

    // Pdf Headers (Öğretmen branşı kaldırıldı)
    List<String> headers = ['Öğretmen', 'Toplam'];
    for (var l in _locations) headers.add(l.name);

    // Pdf Rows
    List<List<String>> rows = [];
    for (var s in stats) {
      List<String> row = [s['name'], s['total'].toString()];
      final locs = s['locCounts'] as Map<String, int>;
      for (var l in _locations) {
        final count = locs[l.id] ?? 0;
        row.add(count > 0 ? count.toString() : '-');
      }
      rows.add(row);
    }

    final pdfData = await pdfService.generateDutyStatsPdf(
      periodName: widget.periodName,
      dateRange: rangeStr,
      headers: headers,
      rows: rows,
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdfData,
      format: PdfPageFormat.a4.landscape,
      name: 'Nobet_Istatistikleri_$rangeStr',
    );
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
    final dateFormat = DateFormat('dd MMM yyyy', 'tr_TR');
    final dateRangeStr =
        '${dateFormat.format(_selectedWeekStart)} - ${dateFormat.format(weekEnd)}';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: 'Nöbet Programı',
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF64748B)),
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DutySettingsScreen(
                        institutionId: widget.institutionId,
                        periodId: widget.periodId,
                        schoolTypeId: widget.schoolTypeId,
                        schoolTypeName: widget.schoolTypeName,
                      ),
                    ),
                  ).then((_) {
                    _locations.clear();
                    _loadData();
                  });
                  break;
                case 'print':
                  _printReport();
                  break;
                case 'date':
                  if (_tabController.index == 0) {
                    _selectDate();
                  } else {
                    _selectStatsDateRange();
                  }
                  break;
                case 'clear':
                  _showClearAllDialog();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, size: 18, color: Color(0xFF64748B)),
                    SizedBox(width: 10),
                    Text('Nöbet Ayarları'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'print',
                child: Row(
                  children: [
                    Icon(Icons.print_outlined, size: 18, color: Color(0xFF64748B)),
                    SizedBox(width: 10),
                    Text('Yazdır'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'date',
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, size: 18, color: Color(0xFF4F46E5)),
                    SizedBox(width: 10),
                    Text('Tarih Seç'),
                  ],
                ),
              ),
              if (_tabController.index == 0)
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep, size: 18, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Haftayı Temizle',
                          style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              // Week Navigator
              if (_tabController.index == 0)
                Container(
                  height: 40,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Color(0xFF64748B),
                        ),
                        onPressed: () => _changeWeek(-1),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          dateRangeStr,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_right,
                          color: Color(0xFF64748B),
                        ),
                        onPressed: () => _changeWeek(1),
                      ),
                    ],
                  ),
                ),
              // Tabs
              TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF4F46E5),
                unselectedLabelColor: const Color(0xFF94A3B8),
                indicatorColor: const Color(0xFF4F46E5),
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                onTap: (index) => setState(() {}),
                tabs: const [
                  Tab(text: 'Nöbet Atamaları'),
                  Tab(text: 'İstatistikler'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_isFabMenuOpen) setState(() => _isFabMenuOpen = false);
        },
        child: TabBarView(
          controller: _tabController,
          children: [
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildCalendarView(),
            _buildStatisticsView(),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? _buildExpandableFab()
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Calendar View
  // ---------------------------------------------------------------------------
  Widget _buildCalendarView() {
    if (_locations.isEmpty) {
      return const Center(
        child: Text(
          'Tanımlı nöbet yeri bulunamadı. Ayarlardan nöbet yeri ekleyiniz.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 900) {
          return _buildDesktopTable();
        } else {
          return _buildMobileList();
        }
      },
    );
  }

  // Desktop Table
  Widget _buildDesktopTable() {
    final dayNames = [
      '',
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];

    // Determine which days need to be shown (if ANY location uses it)
    Set<int> activeDayIndices = {};
    for (var loc in _locations) {
      activeDayIndices.addAll(loc.activeDays);
    }
    List<int> visibleDays = activeDayIndices.toList()..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter, // Center table horizontally
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF1F5F9),
                ),
                dataRowHeight: 72,
                columnSpacing: 24,
                horizontalMargin: 32,
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                  fontSize: 13,
                ),
                columns: [
                  const DataColumn(label: Text('NÖBET YERİ')),
                  ...visibleDays.map(
                    (i) => DataColumn(label: Text(dayNames[i].toUpperCase())),
                  ),
                ],
                rows: _locations.asMap().entries.map((entry) {
                  final index = entry.key;
                  final loc = entry.value;
                  final isEven = index % 2 == 0;

                  return DataRow(
                    color: WidgetStateProperty.all(
                      isEven ? Colors.white : const Color(0xFFF8FAFC),
                    ),
                    cells: [
                      DataCell(
                        Container(
                          constraints: const BoxConstraints(minWidth: 170, maxWidth: 220),
                          child: Row(
                            children: [
                              // Sıralama Butonları (Yukarı / Aşağı)
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: index > 0
                                          ? () => _moveLocationRow(index, -1)
                                          : null,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(7),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        child: Icon(
                                          Icons.keyboard_arrow_up_rounded,
                                          size: 16,
                                          color: index > 0
                                              ? const Color(0xFF4F46E5)
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      height: 1,
                                      width: 18,
                                      color: Colors.grey.shade200,
                                    ),
                                    InkWell(
                                      onTap: index < _locations.length - 1
                                          ? () => _moveLocationRow(index, 1)
                                          : null,
                                      borderRadius: const BorderRadius.vertical(
                                        bottom: Radius.circular(7),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 1,
                                        ),
                                        child: Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          size: 16,
                                          color: index < _locations.length - 1
                                              ? const Color(0xFF4F46E5)
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Yer Adı ve Saatler
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      loc.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                        fontSize: 13,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (loc.startTime.isNotEmpty ||
                                        loc.endTime.isNotEmpty)
                                      Text(
                                        '${loc.startTime} - ${loc.endTime}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade500,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ...visibleDays.map((day) {
                        if (!loc.activeDays.contains(day)) {
                          return DataCell(
                            Container(
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.block,
                                size: 16,
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                          );
                        }
                        return _buildCell(loc, day);
                      }),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Mobile List
  Widget _buildMobileList() {
    final dayNames = [
      '',
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 7,
      itemBuilder: (context, index) {
        final day = index + 1;
        final activeLocs = _locations
            .where((l) => l.activeDays.contains(day))
            .toList();
        if (activeLocs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                dayNames[day],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4F46E5),
                  fontSize: 16,
                ),
              ),
            ),
            ...activeLocs.map((loc) {
              final item = _matrix['${loc.id}_$day'];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  title: Text(
                    loc.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: loc.startTime.isNotEmpty
                      ? Text(
                          '${loc.startTime} - ${loc.endTime}',
                          style: const TextStyle(fontSize: 12),
                        )
                      : null,
                  trailing: item != null
                      ? Chip(
                          label: Text(
                            item.teacherName,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: const Color(0xFFEEF2FF),
                        )
                      : const Icon(
                          Icons.add_circle_outline,
                          color: Colors.grey,
                        ),
                  onTap: () => _showAssignDialog(loc, day, item?.teacherId),
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  DataCell _buildCell(DutyLocation loc, int day) {
    final item = _matrix['${loc.id}_$day'];
    return DataCell(
      InkWell(
        onTap: () => _showAssignDialog(loc, day, item?.teacherId),
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(8),
          child: item != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(0xFF4F46E5),
                      child: Text(
                        item.teacherName.isNotEmpty ? item.teacherName[0] : '?',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.teacherName,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                )
              : const Icon(Icons.add, color: Color(0xFFCBD5E1)),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Statistics View
  // ---------------------------------------------------------------------------
  Widget _buildStatisticsView() {
    if (_isStatsLoading || (_teachers.isEmpty && _isLoading)) {
      return const Center(child: CircularProgressIndicator());
    }

    final dateFormat = DateFormat('dd MMM yyyy', 'tr_TR');

    // Prepare Data
    List<Map<String, dynamic>> stats = [];

    for (var t in _teachers) {
      final tid = t.id;
      final tData = t.data() as Map<String, dynamic>;
      final tName = tData['fullName'] ?? tData['name'] ?? 'İsimsiz';
      final branch = _getUserDisplayTitle(tData);

      int total = 0;
      Map<String, int> locCounts = {};
      Map<String, List<DateTime>> locDates = {};
      for (var l in _locations) {
        locCounts[l.id] = 0;
      }

      for (var item in _statsItems) {
        if (item.teacherId == tid) {
          total++;
          locCounts[item.locationId] = (locCounts[item.locationId] ?? 0) + 1;
          DateTime? date = item.dutyDate != null
              ? DateTime.tryParse(item.dutyDate!)
              : null;
          if (date == null && item.weekStart != null) {
            date = item.weekStart!.add(Duration(days: item.dayOfWeek - 1));
          }
          if (date != null) {
            locDates.putIfAbsent(item.locationId, () => []).add(date);
          }
        }
      }
      for (final list in locDates.values) {
        list.sort();
      }

      stats.add({
        'name': tName,
        'branch': branch,
        'total': total,
        'locCounts': locCounts,
        'locDates': locDates,
      });
    }

    // Sort by Total Descending
    stats.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

    // Öğretmen adına göre filtre
    final searchQ = _normalizeTr(_statsSearch);
    if (searchQ.isNotEmpty) {
      stats = stats
          .where((s) => _normalizeTr(s['name']?.toString() ?? '')
              .contains(searchQ))
          .toList();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Filters Row
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    // Date Range - Flexible ile overflow önleniyor
                    Flexible(
                      child: InkWell(
                        onTap: _selectStatsDateRange,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 14,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${dateFormat.format(_statsStartDate)} - ${dateFormat.format(_statsEndDate)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Color(0xFF334155),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.arrow_drop_down,
                                size: 18,
                                color: Color(0xFF64748B),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_customStatsDateRangePicked &&
                        _periodStartDate != null &&
                        _periodEndDate != null)
                      IconButton(
                        tooltip: 'Dönem Tarihlerine Sıfırla',
                        icon: const Icon(Icons.restart_alt_rounded,
                            size: 20, color: Color(0xFF4F46E5)),
                        onPressed: () {
                          setState(() {
                            _customStatsDateRangePicked = false;
                            _statsStartDate = _periodStartDate!;
                            _statsEndDate = _periodEndDate!;
                          });
                          _updateStatsForSelectedRange();
                        },
                      ),
                    IconButton(
                      tooltip: 'Raporu Yazdır',
                      icon: const Icon(Icons.print_outlined, size: 20),
                      onPressed: _printStatsReport,
                    ),
                  ],
                ),
              ),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 48,
                            child: Center(
                              child: Text(
                                'DETAY',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ),

                          Expanded(
                            flex: 3,
                            child: _statsSearchOpen
                                ? SizedBox(
                                    height: 34,
                                    child: TextField(
                                      controller: _statsSearchCtrl,
                                      autofocus: true,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: 'Öğretmen ara...',
                                        prefixIcon: const Icon(
                                          Icons.search_rounded,
                                          size: 18,
                                        ),
                                        prefixIconConstraints:
                                            const BoxConstraints(minWidth: 32),
                                        suffixIcon: IconButton(
                                          tooltip: 'Aramayı kapat',
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                          ),
                                          onPressed: () => setState(() {
                                            _statsSearchOpen = false;
                                            _statsSearch = '';
                                            _statsSearchCtrl.clear();
                                          }),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      onChanged: (v) =>
                                          setState(() => _statsSearch = v),
                                    ),
                                  )
                                : InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () => setState(
                                      () => _statsSearchOpen = true,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            'ÖĞRETMEN',
                                            style: TextStyle(
                                              color: const Color(0xFF64748B),
                                              fontWeight: FontWeight.bold,
                                              fontSize: isMobile ? 11 : 12,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.search_rounded,
                                            size: 15,
                                            color: Color(0xFF64748B),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),

                          Expanded(
                            child: Center(
                              child: Text(
                                'TOPLAM',
                                style: TextStyle(
                                  color: const Color(0xFF64748B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: isMobile ? 11 : 12,
                                ),
                              ),
                            ),
                          ),

                          if (!isMobile)
                            ..._locations.map(
                              (l) => Expanded(
                                child: Center(
                                  child: Tooltip(
                                    message: l.name,
                                    child: Text(
                                      l.name.length > 5
                                          ? '${l.name.substring(0, 4)}..'
                                          : l.name.toUpperCase(),
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Arama sonucu yoksa
                    if (stats.isEmpty && searchQ.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '"$_statsSearch" ile eşleşen öğretmen bulunamadı.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),

                    // Rows
                    ...stats.map((s) {
                      final total = s['total'] as int;
                      final locs = s['locCounts'] as Map<String, int>;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFF1F5F9)),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 48,
                              child: IconButton(
                                tooltip: 'Nöbet detayı',
                                icon: const Icon(
                                  Icons.info_outline_rounded,
                                  color: Color(0xFF64748B),
                                  size: 20,
                                ),
                                onPressed: () => _showMobileStatDetail(
                                  s['name'],
                                  locs,
                                  s['locDates']
                                      as Map<String, List<DateTime>>,
                                  branch: s['branch']?.toString(),
                                  total: total,
                                ),
                              ),
                            ),

                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    s['name'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF334155),
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    s['branch'] ?? 'Öğretmen',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Expanded(
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: total > 0
                                        ? const Color(0xFFDCFCE7)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    total.toString(),
                                    style: TextStyle(
                                      color: total > 0
                                          ? const Color(0xFF166534)
                                          : Colors.grey.shade400,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            if (!isMobile)
                              ..._locations.map((l) {
                                final count = locs[l.id] ?? 0;
                                return Expanded(
                                  child: Center(
                                    child: Text(
                                      count > 0 ? count.toString() : '-',
                                      style: TextStyle(
                                        color: count > 0
                                            ? const Color(0xFF334155)
                                            : Colors.grey.shade300,
                                        fontWeight: count > 0
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMobileStatDetail(
    String name,
    Map<String, int> locCounts,
    Map<String, List<DateTime>> locDates, {
    String? branch,
    int? total,
  }) {
    final dayFormat = DateFormat('dd MMMM yyyy, EEEE', 'tr_TR');
    final visibleLocs =
        _locations.where((l) => (locCounts[l.id] ?? 0) > 0).toList();
    final totalCount =
        total ?? locCounts.values.fold<int>(0, (acc, c) => acc + c);

    // Kronolojik liste (tarih • nöbet yeri)
    final listDateFormat = DateFormat('dd MMMM yyyy EEEE', 'tr_TR');
    final locNameById = {for (final l in _locations) l.id: l.name};
    final chronological = <MapEntry<DateTime, String>>[];
    locDates.forEach((locId, dates) {
      for (final d in dates) {
        chronological.add(MapEntry(d, locNameById[locId] ?? 'Nöbet Yeri'));
      }
    });
    chronological.sort((a, b) => a.key.compareTo(b.key));
    bool sortByDate = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Tutamaç
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Başlık
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor:
                          const Color(0xFF4F46E5).withValues(alpha: 0.1),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Color(0xFF4F46E5),
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          if (branch != null && branch.isNotEmpty)
                            Text(
                              branch,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Toplam $totalCount',
                        style: const TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(c),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // İçerik
              Expanded(
                child: StatefulBuilder(
                  builder: (context, setSheetState) => Column(
                    children: [
                      // Sıralama anahtarı
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
                        child: Row(
                          children: [
                            Icon(
                              sortByDate
                                  ? Icons.event_note_rounded
                                  : Icons.place_outlined,
                              size: 18,
                              color: const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Tarihe göre sırala',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ),
                            Switch(
                              value: sortByDate,
                              activeThumbColor: const Color(0xFF4F46E5),
                              onChanged: (v) =>
                                  setSheetState(() => sortByDate = v),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                child: visibleLocs.isEmpty
                    ? const Center(child: Text('Henüz nöbet atanmamış.'))
                    : sortByDate
                    ? ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: chronological.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (context, i) {
                          final e = chronological[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 4,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 26,
                                  height: 26,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4F46E5)
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF4F46E5),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: listDateFormat.format(e.key),
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        const TextSpan(
                                          text: '  •  ',
                                          style: TextStyle(
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ),
                                        TextSpan(
                                          text: e.value,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF334155),
                                          ),
                                        ),
                                      ],
                                    ),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: visibleLocs.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final l = visibleLocs[i];
                          final count = locCounts[l.id] ?? 0;
                          final dates = locDates[l.id] ?? const <DateTime>[];
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: count > 1
                                    ? const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.5)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.place_outlined,
                                      size: 18,
                                      color: Color(0xFF4F46E5),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${l.name} ($count)',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...dates.map(
                                  (d) => Padding(
                                    padding: const EdgeInsets.only(
                                      left: 24,
                                      bottom: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.event_rounded,
                                          size: 14,
                                          color: Colors.grey.shade500,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          dayFormat.format(d),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Logic: Assignments & Auto Distribute
  // ---------------------------------------------------------------------------
  // 3. Logic: Assignments & Auto Distribute
  // ---------------------------------------------------------------------------
  Future<void> _showAssignDialog(
    DutyLocation loc,
    int day,
    String? currentId,
  ) async {
    final eligibleIds = loc.eligibilities[day.toString()] ?? [];

    // Get all assigned teachers for this day (excluding current location)
    final assignedTeachers = <String>{};
    for (var location in _locations) {
      if (location.id != loc.id) {
        final key = '${location.id}_$day';
        final assignment = _matrix[key];
        if (assignment != null) {
          assignedTeachers.add(assignment.teacherId);
        }
      }
    }

    // Ensure teachers are loaded
    if (_teachers.isEmpty) {
      final selectedTermId = await TermService().getSelectedTermId();
      final activeTermId = await TermService().getActiveTermId();
      final effectiveTermId = selectedTermId ?? activeTermId;

      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('type', whereIn: ['teacher', 'staff', 'admin'])
          .get();
      _teachers = userSnap.docs
          .where((d) => _isUserActive(
                d.data(),
                termId: effectiveTermId,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
              ))
          .toList();
    }

    String searchQuery = '';
    final TextEditingController searchCtrl = TextEditingController();

    String normalizeTr(String text) {
      return text
          .toLowerCase()
          .replaceAll('ı', 'i')
          .replaceAll('İ', 'i')
          .replaceAll('I', 'i')
          .replaceAll('ş', 's')
          .replaceAll('Ş', 's')
          .replaceAll('ğ', 'g')
          .replaceAll('Ğ', 'g')
          .replaceAll('ü', 'u')
          .replaceAll('Ü', 'u')
          .replaceAll('ö', 'o')
          .replaceAll('Ö', 'o')
          .replaceAll('ç', 'c')
          .replaceAll('Ç', 'c');
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final normQ = normalizeTr(searchQuery.trim());

          // Sort teachers:
          // 1. Currently selected teacher first
          // 2. Eligible teachers (in pool)
          // 3. Alphabetical by name
          List<QueryDocumentSnapshot> sorted = List.from(_teachers);
          sorted.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final nameA = (aData['fullName'] ?? aData['name'] ?? '').toString();
            final nameB = (bData['fullName'] ?? bData['name'] ?? '').toString();

            final isCurrentA = a.id == currentId;
            final isCurrentB = b.id == currentId;
            if (isCurrentA && !isCurrentB) return -1;
            if (!isCurrentA && isCurrentB) return 1;

            final ae = eligibleIds.contains(a.id);
            final be = eligibleIds.contains(b.id);
            if (ae && !be) return -1;
            if (!ae && be) return 1;

            return nameA.compareTo(nameB);
          });

          // Filter by search
          final filtered = sorted.where((t) {
            if (normQ.isEmpty) return true;
            final tData = t.data() as Map<String, dynamic>;
            final name = normalizeTr(
              (tData['fullName'] ?? tData['name'] ?? '').toString(),
            );
            final branch = _getUserDisplayTitle(tData);
            final normB = normalizeTr(branch);
            return name.contains(normQ) || normB.contains(normQ);
          }).toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollController) {
              return Material(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // Handle bar
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${loc.name} - ${_getDayName(day)}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                if (loc.startTime.isNotEmpty || loc.endTime.isNotEmpty)
                                  Text(
                                    '${loc.startTime} - ${loc.endTime}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Search box
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Öğretmen veya branş ara...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Color(0xFF64748B),
                          ),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    searchCtrl.clear();
                                    setSheetState(() {
                                      searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                          ),
                        ),
                        onChanged: (val) {
                          setSheetState(() {
                            searchQuery = val;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Görevi Kaldır Butonu
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          Navigator.pop(ctx);
                          _removeItem(loc.id, day);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.remove_circle_outline_rounded,
                                color: Colors.red.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Nöbet Görevini Kaldır',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              if (currentId != null && currentId.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Mevcut Görevli Var',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    // Teacher List
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Text(
                                  '"$searchQuery" ile eşleşen öğretmen bulunamadı.',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final t = filtered[i];
                                final tId = t.id;
                                final tData = t.data() as Map<String, dynamic>;
                                final tName =
                                    tData['fullName'] ?? tData['name'] ?? '';
                                final isElig = eligibleIds.contains(tId);
                                final isSelected = currentId == tId;
                                final isAssignedElsewhere =
                                    assignedTeachers.contains(tId);

                                final branch = _getUserDisplayTitle(tData);

                                final dutyCount = _allPeriodDutyItems
                                    .where((it) => it.teacherId == tId)
                                    .length;
                                final subtitle = '$branch • $dutyCount nöbet';

                                Color avatarBgColor;
                                Color avatarTextColor;
                                Color tileColor;

                                if (isSelected) {
                                  avatarBgColor = const Color(0xFF4F46E5);
                                  avatarTextColor = Colors.white;
                                  tileColor = const Color(0xFF4F46E5).withValues(alpha: 0.06);
                                } else if (isAssignedElsewhere) {
                                  avatarBgColor = Colors.orange.shade100;
                                  avatarTextColor = Colors.orange.shade800;
                                  tileColor = Colors.orange.shade50;
                                } else if (isElig) {
                                  avatarBgColor = const Color(0xFFDCFCE7);
                                  avatarTextColor = Colors.green.shade800;
                                  tileColor = Colors.white;
                                } else {
                                  avatarBgColor = Colors.grey.shade100;
                                  avatarTextColor = Colors.grey.shade600;
                                  tileColor = Colors.white;
                                }

                                return Material(
                                  color: tileColor,
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: avatarBgColor,
                                      child: Text(
                                        tName.isNotEmpty
                                            ? tName.substring(0, 1).toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          color: avatarTextColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            tName,
                                            style: TextStyle(
                                              fontWeight: isSelected ||
                                                      isAssignedElsewhere
                                                  ? FontWeight.bold
                                                  : FontWeight.w600,
                                              color: const Color(0xFF1E293B),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF6FF),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: const Color(0xFFBFDBFE)),
                                          ),
                                          child: Text(
                                            '$dutyCount Nöbet',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1D4ED8),
                                            ),
                                          ),
                                        ),
                                        if (isElig) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFDCFCE7),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'Havuzda',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF166534),
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (isAssignedElsewhere) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Başka Yerde Nöbetçi',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange.shade800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    subtitle: Text(
                                      subtitle,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isAssignedElsewhere
                                            ? Colors.orange.shade800
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                    trailing: isSelected
                                        ? const Icon(
                                            Icons.check_circle_rounded,
                                            color: Color(0xFF4F46E5),
                                          )
                                        : null,
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _saveItem(
                                        loc.id,
                                        day,
                                        tId,
                                        tName,
                                      );
                                    },
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
      ),
    );
    searchCtrl.dispose();
  }

  Future<void> _saveItem(
    String locId,
    int day,
    String tid,
    String tName,
  ) async {
    final key = '${locId}_$day';
    final current = _matrix[key];
    final weekStr = _selectedWeekStart.toIso8601String();

    // Eğer öğretmen bu gün zaten başka bir yerde nöbetçiyse, eski nöbet yerinden tamamen kaldır
    final otherLocationsWithSameTeacher = <String>[];
    for (var entry in _matrix.entries) {
      if (entry.key != key && entry.value.dayOfWeek == day && entry.value.teacherId == tid) {
        otherLocationsWithSameTeacher.add(entry.value.locationId);
      }
    }
    for (final otherLocId in otherLocationsWithSameTeacher) {
      _removeItem(otherLocId, day);
    }

    final locName = _locations
        .firstWhere(
          (l) => l.id == locId,
          orElse: () => DutyLocation(
            id: locId,
            institutionId: widget.institutionId,
            name: 'Nöbet Yeri',
            activeDays: [],
            eligibilities: {},
          ),
        )
        .name;

    final dutyDate = _selectedWeekStart.add(Duration(days: day - 1));
    final isSameTeacherNotified = (current != null && current.teacherId == tid && current.notificationSent == true);

    // 1. Optimistic Local Update (0ms anlık tepki - tablo ve istatistikler anında güncellenir)
    final tempId = current?.id ?? 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticItem = DutyScheduleItem(
      id: tempId,
      institutionId: widget.institutionId,
      periodId: widget.periodId,
      termId: _termId,
      locationId: locId,
      locationName: locName,
      dayOfWeek: day,
      teacherId: tid,
      teacherName: tName,
      weekStart: _selectedWeekStart,
      dutyDate: dutyDate.toIso8601String(),
      notificationSent: isSameTeacherNotified,
      notifiedTeacherId: isSameTeacherNotified ? tid : null,
    );

    setState(() {
      _matrix[key] = optimisticItem;
      _allPeriodDutyItems.removeWhere((it) =>
          it.locationId == locId &&
          it.dayOfWeek == day &&
          it.weekStart != null &&
          it.weekStart!.year == _selectedWeekStart.year &&
          it.weekStart!.month == _selectedWeekStart.month &&
          it.weekStart!.day == _selectedWeekStart.day);
      _allPeriodDutyItems.add(optimisticItem);
      _updateStatsForSelectedRange();
    });

    final data = {
      'institutionId': widget.institutionId,
      'periodId': widget.periodId,
      'termId': _termId,
      'scopeType': widget.scopeType, // Kapsam modu kaydediliyor
      'locationId': locId,
      'locationName': locName,
      'dayOfWeek': day,
      'teacherId': tid,
      'teacherName': tName,
      'weekStart': weekStr,
      'dutyDate': dutyDate.toIso8601String(),
      'sendNotification': false, // Anlık bildirim gönderilmez
      'notificationSent': isSameTeacherNotified,
      'notifiedTeacherId': isSameTeacherNotified ? tid : null,
    };

    try {
      String realDocId = (current != null && !current.id.startsWith('temp_')) ? current.id : '';
      if (realDocId.isEmpty) {
        final querySnap = await FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .where('periodId', isEqualTo: widget.periodId)
            .where('locationId', isEqualTo: locId)
            .where('dayOfWeek', isEqualTo: day)
            .where('weekStart', isEqualTo: weekStr)
            .limit(1)
            .get();
        if (querySnap.docs.isNotEmpty) {
          realDocId = querySnap.docs.first.id;
        }
      }

      if (realDocId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .doc(realDocId)
            .update(data);
        if (mounted) {
          setState(() {
            final updatedItem = optimisticItem.copyWith(id: realDocId);
            _matrix[key] = updatedItem;
            final idx = _allPeriodDutyItems.indexWhere((it) => it.id == optimisticItem.id || it.id == realDocId);
            if (idx != -1) {
              _allPeriodDutyItems[idx] = updatedItem;
            } else {
              _allPeriodDutyItems.add(updatedItem);
            }
          });
        }
      } else {
        final docRef = await FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .add(data);
        if (mounted) {
          setState(() {
            final realItem = optimisticItem.copyWith(id: docRef.id);
            _matrix[key] = realItem;
            final idx = _allPeriodDutyItems.indexWhere((it) => it.id == optimisticItem.id);
            if (idx != -1) {
              _allPeriodDutyItems[idx] = realItem;
            } else {
              _allPeriodDutyItems.add(realItem);
            }
          });
        }
      }

      // Aynı öğretmenin BU HAFTAKI bu günde başka bir yerde kalmış olası eski kaydı varsa sil
      try {
        final sameDaySnap = await FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .where('periodId', isEqualTo: widget.periodId)
            .where('teacherId', isEqualTo: tid)
            .where('dayOfWeek', isEqualTo: day)
            .where('weekStart', isEqualTo: weekStr) // ← SADECE BU HAFTA
            .get();
        for (var doc in sameDaySnap.docs) {
          // Yeni kaydedilen konumdan FARKLI olan eski kayıtları sil
          if (doc.id != realDocId && doc.data()['locationId'] != locId) {
            await doc.reference.delete();
          }
        }
      } catch (silentError) { debugPrint('[duty_program_detail_screen] hata yutuldu: $silentError'); }
    } catch (e) {
      debugPrint('Error saving duty item: $e');
    }
  }

  Future<void> _removeItem(String locId, int day) async {
    final key = '${locId}_$day';
    final current = _matrix[key];
    if (current == null) return;

    // 1. Optimistic Local Update (0ms anlık tepki - tablodan ve istatistikten anında silinir)
    setState(() {
      _matrix.remove(key);
      _allPeriodDutyItems.removeWhere((it) =>
          it.locationId == locId &&
          it.dayOfWeek == day &&
          it.weekStart != null &&
          it.weekStart!.year == _selectedWeekStart.year &&
          it.weekStart!.month == _selectedWeekStart.month &&
          it.weekStart!.day == _selectedWeekStart.day);
      _updateStatsForSelectedRange();
    });

    try {
      // 1. Doğrudan doküman ID'si ile sil
      if (!current.id.startsWith('temp_')) {
        await FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .doc(current.id)
            .delete();
      }

      // 2. Garanti Silme: weekStart veya dutyDate formatı ne olursa olsun (ISO veya yyyy-MM-dd) tüm eşleşenleri sil
      final isoWeek = _selectedWeekStart.toIso8601String();
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedWeekStart);
      final dutyDate = _selectedWeekStart.add(Duration(days: day - 1));
      final dutyDateIso = dutyDate.toIso8601String();
      final dutyDateStr = DateFormat('yyyy-MM-dd').format(dutyDate);

      final snaps = await Future.wait([
        FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .where('periodId', isEqualTo: widget.periodId)
            .where('locationId', isEqualTo: locId)
            .where('dayOfWeek', isEqualTo: day)
            .where('weekStart', isEqualTo: isoWeek)
            .get(),
        FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .where('periodId', isEqualTo: widget.periodId)
            .where('locationId', isEqualTo: locId)
            .where('dayOfWeek', isEqualTo: day)
            .where('weekStart', isEqualTo: dateStr)
            .get(),
        FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .where('periodId', isEqualTo: widget.periodId)
            .where('locationId', isEqualTo: locId)
            .where('dayOfWeek', isEqualTo: day)
            .where('dutyDate', isEqualTo: dutyDateIso)
            .get(),
        FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .where('periodId', isEqualTo: widget.periodId)
            .where('locationId', isEqualTo: locId)
            .where('dayOfWeek', isEqualTo: day)
            .where('dutyDate', isEqualTo: dutyDateStr)
            .get(),
      ]);

      final toDelete = <DocumentReference>{};
      for (final s in snaps) {
        for (final d in s.docs) {
          toDelete.add(d.reference);
        }
      }

      if (toDelete.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final ref in toDelete) {
          batch.delete(ref);
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error deleting duty item: $e');
    }
  }

  Future<void> _showClearAllDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Haftayı Temizle'),
        content: const Text(
          'Bu haftaya ait tüm nöbet atamaları silinecek. Emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: const Text('Temizle'),
          ),
        ],
      ),
    );

    if (confirm == true) await _clearAllDuties();
  }

  Future<void> _clearAllDuties() async {
    // 1. Optimistic Local Update (0ms anlık tepki)
    setState(() {
      _matrix.clear();
      _allPeriodDutyItems.removeWhere((it) =>
          it.weekStart != null &&
          it.weekStart!.year == _selectedWeekStart.year &&
          it.weekStart!.month == _selectedWeekStart.month &&
          it.weekStart!.day == _selectedWeekStart.day);
      _updateStatsForSelectedRange();
      _isLoading = true;
    });

    try {
      final isoWeek = _selectedWeekStart.toIso8601String();
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedWeekStart);

      final snaps = await Future.wait([
        FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .where('periodId', isEqualTo: widget.periodId)
            .where('weekStart', isEqualTo: isoWeek)
            .get(),
        FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .where('periodId', isEqualTo: widget.periodId)
            .where('weekStart', isEqualTo: dateStr)
            .get(),
      ]);

      final toDelete = <DocumentReference>{};
      for (final s in snaps) {
        for (final d in s.docs) {
          toDelete.add(d.reference);
        }
      }

      if (toDelete.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final ref in toDelete) {
          batch.delete(ref);
        }
        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tüm nöbetler temizlendi.')),
        );
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

  // --- Bildirim Gönderimi ve Expandable FAB Menüsü ---

  List<DutyScheduleItem> get _pendingNotificationItems {
    return _matrix.values.where((it) {
      if (it.teacherId.isEmpty) return false;
      return it.notificationSent != true || it.notifiedTeacherId != it.teacherId;
    }).toList();
  }

  Future<void> _showSendNotificationDialog() async {
    final allAssigned = _matrix.values.where((it) => it.teacherId.isNotEmpty).toList();

    if (allAssigned.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu haftaya ait nöbet ataması bulunmuyor.')),
      );
      return;
    }

    final pending = _pendingNotificationItems;
    bool forceSendAll = false;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final itemsToPreview = forceSendAll ? allAssigned : pending;
          final count = itemsToPreview.length;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.notifications_active_rounded, color: Color(0xFFF59E0B), size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Nöbet Bildirimi Gönder',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pending.isEmpty && !forceSendAll) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Bu haftadaki tüm nöbetçilere daha önce bildirim gönderilmiştir.',
                              style: TextStyle(fontSize: 13, color: Colors.green.shade900, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Text(
                      forceSendAll
                          ? 'Bu haftadaki tüm nöbetçilere (${allAssigned.length} kişi) bildirim gönderilecek:'
                          : 'Henüz bildirim gitmemiş veya nöbetçisi değişmiş $count öğretmen bulundu:',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (int idx = 0; idx < itemsToPreview.length; idx++) ...[
                              if (idx > 0) const Divider(height: 1),
                              Builder(
                                builder: (_) {
                                  final it = itemsToPreview[idx];
                                  final locName = _locations.firstWhere(
                                    (l) => l.id == it.locationId,
                                    orElse: () => DutyLocation(id: '', institutionId: '', name: 'Nöbet Yeri', activeDays: []),
                                  ).name;
                                  final dayName = (it.dayOfWeek >= 1 && it.dayOfWeek <= 7) ? _getDayName(it.dayOfWeek) : '';
                                  return ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                                      child: Text(
                                        it.teacherName.isNotEmpty ? it.teacherName.substring(0, 1).toUpperCase() : '?',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                                      ),
                                    ),
                                    title: Text(it.teacherName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                    subtitle: Text('$dayName · $locName', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                    trailing: (it.notificationSent == true && it.notifiedTeacherId == it.teacherId)
                                        ? const Icon(Icons.done_all, size: 16, color: Colors.green)
                                        : Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade100,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Yeni / Değişen',
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                            ),
                                          ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  // Tümüne gönder checkbox seçeneği
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: forceSendAll,
                    activeColor: const Color(0xFF4F46E5),
                    title: Text(
                      'Tüm haftadaki nöbetçilere tekrar gönder (${allAssigned.length} kişi)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    onChanged: (val) => setDlgState(() => forceSendAll = val ?? false),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('İptal'),
              ),
              ElevatedButton.icon(
                onPressed: (pending.isEmpty && !forceSendAll)
                    ? null
                    : () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.send_rounded, size: 16),
                label: Text(forceSendAll
                    ? 'Tümüne Gönder (${allAssigned.length})'
                    : 'Bildirim Gönder ($count)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirm != true) return;

    final targetItems = forceSendAll ? allAssigned : pending;
    if (targetItems.isEmpty) return;

    // Donma ve tablonun kaybolmasını önlemek için _isLoading yerine SnackBar ile bilgilendirme
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Bildirimler iletiliyor...'),
            ],
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }

    try {
      final dateFormat = DateFormat('yyyy-MM-dd');
      final weekStr = dateFormat.format(_selectedWeekStart);

      // 1. Henüz temp_ id'de kalmış olan kayıtların gerçek Firestore id'lerini çöz
      final resolvedItems = <DutyScheduleItem>[];
      for (var it in targetItems) {
        if (it.id.isNotEmpty && !it.id.startsWith('temp_')) {
          resolvedItems.add(it);
        } else {
          try {
            final q = await FirebaseFirestore.instance
                .collection('dutyScheduleItems')
                .where('periodId', isEqualTo: widget.periodId)
                .where('locationId', isEqualTo: it.locationId)
                .where('dayOfWeek', isEqualTo: it.dayOfWeek)
                .where('weekStart', isEqualTo: weekStr)
                .limit(1)
                .get();

            if (q.docs.isNotEmpty) {
              final realId = q.docs.first.id;
              final updatedItem = it.copyWith(id: realId);
              resolvedItems.add(updatedItem);
              final key = '${it.locationId}_${it.dayOfWeek}';
              _matrix[key] = updatedItem;
            } else {
              final docRef = await FirebaseFirestore.instance.collection('dutyScheduleItems').add({
                'institutionId': widget.institutionId,
                'periodId': widget.periodId,
                'termId': _termId,
                'scopeType': widget.scopeType,
                'locationId': it.locationId,
                'locationName': it.locationName,
                'dayOfWeek': it.dayOfWeek,
                'teacherId': it.teacherId,
                'teacherName': it.teacherName,
                'weekStart': weekStr,
                'dutyDate': it.dutyDate,
                'sendNotification': false,
                'notificationSent': false,
                'notifiedTeacherId': null,
              });
              final updatedItem = it.copyWith(id: docRef.id);
              resolvedItems.add(updatedItem);
              final key = '${it.locationId}_${it.dayOfWeek}';
              _matrix[key] = updatedItem;
            }
          } catch (e) {
            debugPrint('Doc ID resolve hatası: $e');
            resolvedItems.add(it);
          }
        }
      }

      // 2. Firestore güncellemesi (dutyScheduleItems üzerinden tekil, garantili bildirim tetikleyici)
      final batch = FirebaseFirestore.instance.batch();

      for (var it in resolvedItems) {
        if (it.id.isNotEmpty && !it.id.startsWith('temp_')) {
          final docRef = FirebaseFirestore.instance.collection('dutyScheduleItems').doc(it.id);
          batch.update(docRef, {
            'sendNotification': true,
            'notificationSent': true,
            'notifiedTeacherId': it.teacherId,
            'notificationRequestedAt': FieldValue.serverTimestamp(),
          });
        }

        final key = '${it.locationId}_${it.dayOfWeek}';
        if (_matrix.containsKey(key)) {
          _matrix[key] = _matrix[key]!.copyWith(
            id: it.id,
            notificationSent: true,
            notifiedTeacherId: it.teacherId,
          );
        }
        final allIdx = _allPeriodDutyItems.indexWhere((x) =>
            x.id == it.id ||
            (x.locationId == it.locationId && x.dayOfWeek == it.dayOfWeek && x.weekStart == it.weekStart));
        if (allIdx != -1) {
          _allPeriodDutyItems[allIdx] = _allPeriodDutyItems[allIdx].copyWith(
            id: it.id,
            notificationSent: true,
            notifiedTeacherId: it.teacherId,
          );
        }
      }

      // Nöbet dokümanlarını güncelle — Bu işlem sunucu tarafındaki onDutyAssigned tetikleyicisini TEK BİR KEZ çalıştırır
      await batch.commit();

      if (mounted) {
        setState(() {}); // FAB rozetini ve durumları anında güncelle
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${resolvedItems.length} öğretmene nöbet bildirimi başarıyla gönderildi.'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bildirim gönderilirken hata oluştu: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildExpandableFab() {
    final pendingCount = _pendingNotificationItems.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_isFabMenuOpen) ...[
          // 1. Yeni Dağılım Yap (En üstteki buton)
          _buildSpeedDialItem(
            label: 'Yeni Dağılım Yap',
            icon: Icons.autorenew_rounded,
            color: const Color(0xFF10B981),
            onTap: () {
              setState(() => _isFabMenuOpen = false);
              _showAutoDistributeCall();
            },
          ),
          const SizedBox(height: 10),

          // 2. Bildirim Gönder (Ortadaki buton)
          _buildSpeedDialItem(
            label: pendingCount > 0
                ? 'Bildirim Gönder ($pendingCount)'
                : 'Bildirim Gönder',
            icon: Icons.notifications_active_rounded,
            color: const Color(0xFFF59E0B),
            badgeCount: pendingCount,
            onTap: () {
              setState(() => _isFabMenuOpen = false);
              _showSendNotificationDialog();
            },
          ),
          const SizedBox(height: 10),

          // 3. Haftayı Temizle (En alttaki buton)
          _buildSpeedDialItem(
            label: 'Haftayı Temizle',
            icon: Icons.delete_sweep_rounded,
            color: const Color(0xFFEF4444),
            onTap: () {
              setState(() => _isFabMenuOpen = false);
              _showClearAllDialog();
            },
          ),
          const SizedBox(height: 12),
        ],

        // Ana FAB Butonu (3 Çizgi Menü İkonu)
        FloatingActionButton(
          heroTag: 'duty_speed_dial_main_fab',
          backgroundColor: _isFabMenuOpen
              ? Colors.grey.shade800
              : const Color(0xFF4F46E5),
          foregroundColor: Colors.white,
          elevation: 6,
          tooltip: _isFabMenuOpen ? 'Kapat' : 'Nöbet İşlemleri',
          onPressed: () {
            setState(() {
              _isFabMenuOpen = !_isFabMenuOpen;
            });
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isFabMenuOpen
                ? const Icon(Icons.close_rounded, key: ValueKey('close'), size: 26)
                : Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.menu_rounded, key: ValueKey('menu'), size: 26),
                      if (pendingCount > 0)
                        Positioned(
                          top: -3,
                          right: -3,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedDialItem({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  if (badgeCount != null && badgeCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FloatingActionButton.small(
          heroTag: null,
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 4,
          onPressed: onTap,
          child: Icon(icon, size: 19),
        ),
      ],
    );
  }

  String _getDayName(int d) => [
    '',
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ][d];

  Future<void> _moveLocationRow(int currentIndex, int direction) async {
    final targetIndex = currentIndex + direction;
    if (targetIndex < 0 || targetIndex >= _locations.length) return;

    setState(() {
      final item = _locations.removeAt(currentIndex);
      _locations.insert(targetIndex, item);
      for (int i = 0; i < _locations.length; i++) {
        _locations[i] = _locations[i].copyWith(order: i);
      }
    });

    try {
      // 1. Alt döneme özel sıra kaydı (dutyLocationConfigs.{locId}.order)
      if (widget.periodId.isNotEmpty) {
        final periodRef = FirebaseFirestore.instance
            .collection('workPeriods')
            .doc(widget.periodId);
        final periodSnap = await periodRef.get();
        final pData = periodSnap.data() ?? {};
        final currentConfigs = Map<String, dynamic>.from(
            pData['dutyLocationConfigs'] as Map? ?? {});

        for (int i = 0; i < _locations.length; i++) {
          final locId = _locations[i].id;
          final locCfg = Map<String, dynamic>.from(
              currentConfigs[locId] as Map? ?? {});
          locCfg['order'] = i;
          currentConfigs[locId] = locCfg;
        }

        await periodRef.set({
          'dutyLocationConfigs': currentConfigs,
        }, SetOptions(merge: true));
      }

      // 2. Genel dutyLocations koleksiyonundaki sıra numarasını da güncelle
      final batch = FirebaseFirestore.instance.batch();
      final col = FirebaseFirestore.instance.collection('dutyLocations');
      for (int i = 0; i < _locations.length; i++) {
        batch.update(col.doc(_locations[i].id), {'order': i});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Nöbet satır sıralama güncelleme hatası: $e');
    }
  }

  Future<void> _showAutoDistributeCall() async {
    final dateFormat = DateFormat('dd MMM', 'tr_TR');
    final weekStr = dateFormat.format(_selectedWeekStart);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Otomatik Dağıt'),
        content: Text(
          '$weekStr haftasın nöbet dağıtım yapılacak. Mevcut haftalık atamalar silinebilir. Onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Dağıt'),
          ),
        ],
      ),
    );
    if (confirm == true) _distributeDuties();
  }

  Future<void> _distributeDuties() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch Teachers (only active and matching current term)
      final selectedTermId = await TermService().getSelectedTermId();
      final activeTermId = await TermService().getActiveTermId();
      final effectiveTermId = selectedTermId ?? activeTermId;

      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('type', whereIn: ['teacher', 'staff', 'admin'])
          .get();
      final teachers = userSnap.docs
          .where((d) => _isUserActive(
                d.data(),
                termId: effectiveTermId,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
              ))
          .map((d) => d.data()..['id'] = d.id)
          .toList();
      if (teachers.isEmpty) throw 'Hiçbir aktif personel bulunamadı.';

      // 2. Nöbet yerlerinin kullanıcının belirlediği sıralamasını koru
      if (_locations.isEmpty) throw 'Hiçbir nöbet yeri yok.';
      _locations.sort((a, b) {
        final cmp = a.order.compareTo(b.order);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });

      // 3. Clear Existing for THIS Week
      final weekStr = _selectedWeekStart.toIso8601String();
      final exist = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('periodId', isEqualTo: widget.periodId)
          .where('weekStart', isEqualTo: weekStr)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var d in exist.docs) {
        batch.delete(d.reference);
      }

      // 4. Calculate weekIndex for cyclical rotation
      int weekIndex = 0;
      if (_periodStartDate != null) {
        final diffDays = _selectedWeekStart.difference(_periodStartDate!).inDays;
        weekIndex = (diffDays ~/ 7);
        if (weekIndex < 0) weekIndex = 0;
      } else {
        final diffDays = _selectedWeekStart
            .difference(DateTime(_selectedWeekStart.year, 1, 1))
            .inDays;
        weekIndex = (diffDays ~/ 7);
      }

      // ------------------------------------------------------------------
      // GEÇMİŞ (İSTATİSTİK) YÜKLEME
      // Sadece seçili haftadan ÖNCEKİ haftalar dikkate alınır. İleri tarihli
      // haftalarda kayıt olsa bile rotasyon hesabını bozmaz. Elle yapılan
      // müdahaleler de bu geçmişin parçasıdır; algoritma onları baz alır.
      // ------------------------------------------------------------------
      final historySnap = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('periodId', isEqualTo: widget.periodId)
          .get();

      DateTime? parseDate(dynamic v) {
        if (v == null) return null;
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        return DateTime.tryParse(v.toString());
      }

      final selDay = DateTime(
        _selectedWeekStart.year,
        _selectedWeekStart.month,
        _selectedWeekStart.day,
      );

      final pastHistory = <Map<String, dynamic>>[];
      for (final d in historySnap.docs) {
        final data = d.data();
        final ws = parseDate(data['weekStart']) ?? parseDate(data['dutyDate']);
        if (ws == null) continue;
        if (DateTime(ws.year, ws.month, ws.day).isBefore(selDay)) {
          pastHistory.add(data);
        }
      }
      // Tarihe göre sırala (en son tutulan yeri doğru tespit etmek için)
      pastHistory.sort((a, b) {
        final da = parseDate(a['dutyDate']) ?? parseDate(a['weekStart']);
        final db = parseDate(b['dutyDate']) ?? parseDate(b['weekStart']);
        if (da == null || db == null) return 0;
        return da.compareTo(db);
      });

      // ------------------------------------------------------------------
      // ROTASYON GRUPLARI
      // Aynı rotasyon grubundaki yerler için kural: Öğretmen, grubun
      // (havuzunda bulunduğu) TÜM yerlerini tutmadan hiçbir yeri 2. kez
      // tutmaz.
      //  - Aynı "grup" adı yazılmış yerler aynı gruptur.
      //  - Grup adı yazılmamış yerler, personel havuzları büyük oranda
      //    örtüşüyorsa (Jaccard >= %50) otomatik olarak aynı gruba alınır.
      //    Böylece havuzlarda 1-2 kişilik fark olsa bile kat nöbetleri
      //    tek rotasyon olarak değerlendirilir; 50 kişilik tek yerli havuz
      //    ise 9-10 kişilik kat havuzuyla birleşmez.
      // ------------------------------------------------------------------
      final Map<String, Set<String>> locPools = {
        for (final l in _locations)
          l.id: l.eligibilities.values
              .expand((e) => e)
              .map((x) => x.toString())
              .toSet(),
      };

      // Union-Find
      final Map<String, String> uf = {for (final l in _locations) l.id: l.id};
      String find(String x) {
        while (uf[x] != x) {
          uf[x] = uf[uf[x]!]!;
          x = uf[x]!;
        }
        return x;
      }

      void union(String a, String b) {
        final ra = find(a), rb = find(b);
        if (ra != rb) uf[ra] = rb;
      }

      for (int i = 0; i < _locations.length; i++) {
        for (int j = i + 1; j < _locations.length; j++) {
          final a = _locations[i], b = _locations[j];
          final ga = a.group.trim(), gb = b.group.trim();
          if (ga.isNotEmpty && gb.isNotEmpty) {
            if (ga == gb) union(a.id, b.id);
            continue; // farklı açık gruplar asla birleşmez
          }
          final pa = locPools[a.id]!, pb = locPools[b.id]!;
          if (pa.isEmpty || pb.isEmpty) continue;
          final inter = pa.intersection(pb).length;
          final uni = pa.union(pb).length;
          if (uni > 0 && inter / uni >= 0.5) union(a.id, b.id);
        }
      }

      final Map<String, String> locToGroup = {
        for (final l in _locations) l.id: find(l.id),
      };

      // Her gruba ait sıralı nöbet yerleri (kullanıcının belirlediği sırada)
      final Map<String, List<DutyLocation>> groupLocationsMap = {};
      for (final l in _locations) {
        groupLocationsMap.putIfAbsent(locToGroup[l.id]!, () => []).add(l);
      }

      // ------------------------------------------------------------------
      // SAYAÇLAR
      // ------------------------------------------------------------------
      final Map<String, int> totalLoad = {};
      final Map<String, Map<String, int>> locHistoryCounts = {};
      final Map<String, Map<String, int>> groupTotalLoad = {};
      final Map<String, Map<String, String>> teacherLastLocInGroup = {};
      final Map<String, int> teacherBaseIndex = {};

      for (int i = 0; i < teachers.length; i++) {
        final tid = teachers[i]['id']?.toString() ?? '';
        teacherBaseIndex[tid] = i;
        totalLoad[tid] = 0;
        locHistoryCounts[tid] = {};
        groupTotalLoad[tid] = {};
        teacherLastLocInGroup[tid] = {};
      }

      for (final data in pastHistory) {
        final tid = data['teacherId']?.toString();
        final lid = data['locationId']?.toString();
        if (tid == null || lid == null) continue;
        if (!locHistoryCounts.containsKey(tid)) continue; // pasif personel

        totalLoad[tid] = (totalLoad[tid] ?? 0) + 1;
        locHistoryCounts[tid]![lid] = (locHistoryCounts[tid]![lid] ?? 0) + 1;
        final g = locToGroup[lid];
        if (g != null) {
          groupTotalLoad[tid]![g] = (groupTotalLoad[tid]![g] ?? 0) + 1;
          teacherLastLocInGroup[tid]![g] = lid;
        }
      }

      // Öğretmenin bir gruptaki "rotasyon seti": o gruptaki, havuzunda
      // bulunduğu nöbet yerleri (sıralı).
      List<DutyLocation> rotationSetOf(String tid, String g) {
        return (groupLocationsMap[g] ?? const <DutyLocation>[])
            .where((gl) => locPools[gl.id]?.contains(tid) ?? false)
            .toList();
      }

      // TUR FAZLASI: Öğretmenin bu yerdeki sayısı - rotasyon setindeki
      // en düşük sayısı. 0 => bu yeri mevcut turunda henüz tutmamış.
      // >0 => tüm yerleri gezmeden aynı yere tekrar geliyor (ihlal).
      int excessOf(String tid, String locId, List<DutyLocation> rotSet) {
        if (rotSet.isEmpty) return 0;
        int minC = 1 << 30;
        for (final gl in rotSet) {
          final c = locHistoryCounts[tid]?[gl.id] ?? 0;
          if (c < minC) minC = c;
        }
        final own = locHistoryCounts[tid]?[locId] ?? 0;
        final ex = own - minC;
        return ex < 0 ? 0 : ex;
      }

      // Döngüsel kaydırmada "sıradaki" yer: son tuttuğu yerden sonra gelen
      // ve bu turda henüz tutmadığı İLK yer (tuttuysa bir basamak daha kayar).
      String? preferredNextLoc(String tid, String g, List<DutyLocation> rotSet) {
        if (rotSet.isEmpty) return null;
        final last = teacherLastLocInGroup[tid]?[g];
        int startIdx;
        if (last == null) {
          final base = teacherBaseIndex[tid] ?? 0;
          startIdx = (base + weekIndex) % rotSet.length;
        } else {
          final li = rotSet.indexWhere((l) => l.id == last);
          startIdx = li == -1 ? 0 : (li + 1) % rotSet.length;
        }
        for (int k = 0; k < rotSet.length; k++) {
          final cand = rotSet[(startIdx + k) % rotSet.length];
          if (excessOf(tid, cand.id, rotSet) == 0) return cand.id;
        }
        return rotSet[startIdx].id;
      }

      // Puan ağırlıkları (küçük = daha iyi)
      const double kRepeatBeforeCycle = 1e9; // tüm yerleri gezmeden tekrar
      // Haftada 2. nöbet, tur ihlalinden daha ağır cezalandırılır
      const double kWeekly = 2e9; // haftada k. nöbet: (k-1) * kWeekly
      const double kGroupTotal = 5e4; // grup içi toplam adalet
      const double kCyclicBonus = 5000; // tam sıradaki yer
      const double kTotal = 100; // genel toplam yük
      // BÜYÜK HAVUZ SIRA KURALI: Havuzdaki herkes tutmadan kimse 2. kez
      // tutmaz. Haftada 2. nöbetten (kWeekly) daha ağırdır.
      const double kPoolQueue = 3e9;

      // ------------------------------------------------------------------
      // BÜYÜK HAVUZLU GRUPLAR (örn. Aziz Sancar: 1 yer, ~50 kişi)
      // Havuzdaki aktif kişi sayısı, gruptaki yer sayısının 2 katından
      // fazlaysa "sıra kuralı" uygulanır: öğretmenin bu gruptaki nöbet
      // sayısı, havuzdaki en az tutan kişinin sayısını geçemez.
      // (Kat nöbetleri gibi 9 yer / 9-12 kişi gruplarda tur kuralı yeterli.)
      // ------------------------------------------------------------------
      final Map<String, int> groupPoolMin = {};
      groupLocationsMap.forEach((g, locs) {
        final pool = <String>{};
        for (final l in locs) {
          pool.addAll(locPools[l.id] ?? const <String>{});
        }
        pool.removeWhere((id) => !teacherBaseIndex.containsKey(id));
        if (pool.isEmpty || pool.length < locs.length * 2) return;
        int minC = 1 << 30;
        for (final id in pool) {
          final c = groupTotalLoad[id]?[g] ?? 0;
          if (c < minC) minC = c;
        }
        groupPoolMin[g] = minC;
      });

      int poolExcessOf(String tid, String g) {
        final minC = groupPoolMin[g];
        if (minC == null) return 0;
        final ex = (groupTotalLoad[tid]?[g] ?? 0) - minC;
        return ex < 0 ? 0 : (ex > 10 ? 10 : ex);
      }

      // ------------------------------------------------------------------
      // HAFTALIK SLOTLAR (yer + gün)
      // ------------------------------------------------------------------
      final slotLocs = <DutyLocation>[];
      final slotDays = <int>[];
      final slotElig = <Set<String>>[];
      for (int day = 1; day <= 7; day++) {
        for (final loc in _locations.where((l) => l.activeDays.contains(day))) {
          final specific = loc.eligibilities[day.toString()];
          final Set<String> ids = (specific != null && specific.isNotEmpty)
              ? specific.map((x) => x.toString()).toSet()
              : (locPools[loc.id] ?? <String>{});
          final elig =
              ids.where((id) => teacherBaseIndex.containsKey(id)).toSet();
          if (elig.isEmpty) continue;
          slotLocs.add(loc);
          slotDays.add(day);
          slotElig.add(elig);
        }
      }

      // Slot maliyeti (öğretmen, slot)
      double slotCost(String tid, int s) {
        final loc = slotLocs[s];
        final day = slotDays[s];
        final g = locToGroup[loc.id]!;
        final rotSet = rotationSetOf(tid, g);
        double c = kCyclicBonus; // negatif olmaması için taban
        int ex = excessOf(tid, loc.id, rotSet);
        if (ex > 50) ex = 50;
        c += ex * kRepeatBeforeCycle;
        c += poolExcessOf(tid, g) * kPoolQueue;
        c += (groupTotalLoad[tid]?[g] ?? 0) * kGroupTotal;
        if (preferredNextLoc(tid, g, rotSet) == loc.id) c -= kCyclicBonus;
        c += (totalLoad[tid] ?? 0) * kTotal;
        final rot =
            ((teacherBaseIndex[tid] ?? 0) + weekIndex + day) % teachers.length;
        c += rot / (teachers.length + 1);
        return c;
      }

      // ------------------------------------------------------------------
      // HAFTALIK OPTİMAL DAĞITIM (Min-Cost Max-Flow)
      // Tüm haftanın tüm yerleri TEK SEFERDE değerlendirilir. Böylece bir
      // öğretmen, tutmadığı yerin bulunduğu güne yerleştirilir; günler arası
      // sıralı (açgözlü) seçimden kaynaklanan tekrarlar oluşmaz.
      //   Kaynak -> Öğretmen (haftalık k. nöbet maliyeti artan)
      //   Öğretmen -> Öğretmen-Gün (kapasite 1: günde en fazla 1 nöbet)
      //   Öğretmen-Gün -> Slot (maliyet = slotCost)
      //   Slot -> Hedef (kapasite 1)
      // ------------------------------------------------------------------
      final flow = _MinCostFlow();
      final src = flow.addNode();
      final sink = flow.addNode();
      final teacherNode = <String, int>{};
      final teacherDayNode = <String, int>{};
      final slotNode = <int>[];
      for (int s = 0; s < slotLocs.length; s++) {
        final node = flow.addNode();
        slotNode.add(node);
        flow.addEdge(node, sink, 1, 0);
      }
      final distinctDays = slotDays.toSet().length;
      // (edgeIndex -> (tid, slot)) eşlemesi
      final assignEdges = <int, MapEntry<String, int>>{};
      for (int s = 0; s < slotLocs.length; s++) {
        final day = slotDays[s];
        for (final tid in slotElig[s]) {
          final tn = teacherNode.putIfAbsent(tid, () {
            final n = flow.addNode();
            for (int k = 1; k <= distinctDays; k++) {
              flow.addEdge(src, n, 1, (k - 1) * kWeekly);
            }
            return n;
          });
          final tdKey = '$tid|$day';
          final tdn = teacherDayNode.putIfAbsent(tdKey, () {
            final n = flow.addNode();
            flow.addEdge(tn, n, 1, 0);
            return n;
          });
          final e = flow.addEdge(tdn, slotNode[s], 1, slotCost(tid, s));
          assignEdges[e] = MapEntry(tid, s);
        }
      }
      flow.run(src, sink);

      int assignedCount = 0;
      final violations = <String>[];
      final teacherById = {
        for (final t in teachers) t['id']?.toString() ?? '': t,
      };

      assignEdges.forEach((edgeIdx, pair) {
        if (!flow.isUsed(edgeIdx)) return;
        final tId = pair.key;
        final s = pair.value;
        final loc = slotLocs[s];
        final day = slotDays[s];
        final selectedTeacher = teacherById[tId]!;
        final tName = selectedTeacher['fullName'] ?? selectedTeacher['name'];

        final g = locToGroup[loc.id]!;
        if (excessOf(tId, loc.id, rotationSetOf(tId, g)) > 0) {
          violations.add('$tName → ${loc.name} (tüm yerleri gezmeden tekrar)');
        } else if (poolExcessOf(tId, g) > 0) {
          violations.add(
              '$tName → ${loc.name} (havuzda henüz tutmayanlar varken tekrar)');
        }
        assignedCount++;

        final ref = FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .doc();

        batch.set(ref, {
          'institutionId': widget.institutionId,
          'periodId': widget.periodId,
          'termId': _termId,
          'locationId': loc.id,
          'locationName': loc.name,
          'dayOfWeek': day,
          'teacherId': tId,
          'teacherName': tName,
          'weekStart': weekStr,
          'dutyDate': _selectedWeekStart
              .add(Duration(days: day - 1))
              .toIso8601String(),
          'sendNotification': false,
          'notificationSent': false,
          'notifiedTeacherId': null,
        });
      });

      await batch.commit();
      if (!mounted) return;
      if (assignedCount > 0 && violations.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Dağıtım tamamlandı (uyarı)'),
            content: SingleChildScrollView(
              child: Text(
                '$assignedCount atama yapıldı.\n\n'
                'Aşağıdaki atamalarda öğretmen, grubundaki tüm yerleri '
                'tutmadan aynı yere tekrar yazıldı. Havuz/gün kısıtları '
                'nedeniyle başka geçerli bir kombinasyon bulunamadı:\n\n'
                '${violations.map((v) => '• $v').join('\n')}',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      } else if (assignedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Otomatik dağıtım tamamlandı. $assignedCount atama yapıldı. Tur kuralı ihlali yok.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Hiçbir atama yapılamadı. Nöbet yerlerinin uygunluk havuzlarının boş olmadığından emin olun.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      _loadData();
      _loadStatsData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }
}

/// Basit Min-Cost Max-Flow (SPFA tabanlı) çözücü.
/// Haftalık nöbet dağıtımında tüm (yer, gün) slotlarını tek seferde
/// optimal şekilde doldurmak için kullanılır.
class _MinCostFlow {
  final List<int> _to = [];
  final List<int> _cap = [];
  final List<double> _cost = [];
  final List<List<int>> _adj = [];

  int addNode() {
    _adj.add(<int>[]);
    return _adj.length - 1;
  }

  /// İleri kenarın indeksini döner.
  int addEdge(int u, int v, int cap, double cost) {
    final e = _to.length;
    _to.add(v);
    _cap.add(cap);
    _cost.add(cost);
    _adj[u].add(e);
    _to.add(u);
    _cap.add(0);
    _cost.add(-cost);
    _adj[v].add(e + 1);
    return e;
  }

  /// İleri kenar akış taşıyor mu?
  bool isUsed(int edge) => _cap[edge] == 0 && _cap[edge ^ 1] > 0;

  void run(int s, int t) {
    final n = _adj.length;
    while (true) {
      final dist = List<double>.filled(n, double.infinity);
      final inQueue = List<bool>.filled(n, false);
      final prevEdge = List<int>.filled(n, -1);
      dist[s] = 0;
      final queue = <int>[s];
      int head = 0;
      inQueue[s] = true;
      while (head < queue.length) {
        final u = queue[head++];
        inQueue[u] = false;
        for (final e in _adj[u]) {
          if (_cap[e] <= 0) continue;
          final v = _to[e];
          final nd = dist[u] + _cost[e];
          if (nd < dist[v] - 1e-6) {
            dist[v] = nd;
            prevEdge[v] = e;
            if (!inQueue[v]) {
              inQueue[v] = true;
              queue.add(v);
            }
          }
        }
      }
      if (dist[t] == double.infinity) break;
      // Tüm kapasiteler 1 olduğu için her seferinde 1 birim akış
      int v = t;
      while (v != s) {
        final e = prevEdge[v];
        _cap[e] -= 1;
        _cap[e ^ 1] += 1;
        v = _to[e ^ 1];
      }
    }
  }
}
