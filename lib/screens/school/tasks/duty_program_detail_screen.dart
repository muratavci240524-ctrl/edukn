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
          } catch (_) {}
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
      print('Error loading calendar data: $e');
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
      print('Error loading stats data: $e');
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

    // Pdf Headers
    List<String> headers = ['Öğretmen', 'Branş/Görev', 'Toplam'];
    for (var l in _locations) headers.add(l.name);

    // Pdf Rows
    List<List<String>> rows = [];
    for (var s in stats) {
      List<String> row = [s['name'], s['branch'], s['total'].toString()];
      final locs = s['locCounts'] as Map<String, int>;
      for (var l in _locations) {
        row.add((locs[l.id] ?? 0).toString());
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
                color: Colors.black.withOpacity(0.04),
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
                headingRowColor: MaterialStateProperty.all(
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
                    color: MaterialStateProperty.all(
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
      for (var l in _locations) {
        locCounts[l.id] = 0;
      }

      for (var item in _statsItems) {
        if (item.teacherId == tid) {
          total++;
          locCounts[item.locationId] = (locCounts[item.locationId] ?? 0) + 1;
        }
      }

      stats.add({'name': tName, 'branch': branch, 'total': total, 'locCounts': locCounts});
    }

    // Sort by Total Descending
    stats.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

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
                      color: Colors.black.withOpacity(0.02),
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
                          if (isMobile)
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
                            child: Text(
                              'ÖRETMEN',
                              style: TextStyle(
                                color: const Color(0xFF64748B),
                                fontWeight: FontWeight.bold,
                                fontSize: isMobile ? 11 : 12,
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
                            if (isMobile)
                              SizedBox(
                                width: 48,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.info_outline_rounded,
                                    color: Color(0xFF64748B),
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _showMobileStatDetail(s['name'], locs),
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

  void _showMobileStatDetail(String name, Map<String, int> locCounts) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children:
              _locations
                  .where((l) => (locCounts[l.id] ?? 0) > 0)
                  .map((l) {
                    return ListTile(
                      dense: true,
                      title: Text(l.name),
                      trailing: CircleAvatar(
                        radius: 12,
                        backgroundColor: const Color(0xFFDCFCE7),
                        child: Text(
                          locCounts[l.id].toString(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF166534),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  })
                  .toList()
                  .isEmpty
              ? [const Text('Henüz nöbet atanmamış.')]
              : _locations
                    .where((l) => (locCounts[l.id] ?? 0) > 0)
                    .map(
                      (l) => ListTile(
                        dense: true,
                        title: Text(l.name),
                        trailing: Text(
                          '${locCounts[l.id]}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                    .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Tamam'),
          ),
        ],
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
                                  tileColor = const Color(0xFF4F46E5).withOpacity(0.06);
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
      if (!current.id.startsWith('temp_')) {
        await FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .doc(current.id)
            .delete();
      } else {
        final dateFormat = DateFormat('yyyy-MM-dd');
        final weekStr = dateFormat.format(_selectedWeekStart);
        final snap = await FirebaseFirestore.instance
            .collection('dutyScheduleItems')
            .where('periodId', isEqualTo: widget.periodId)
            .where('locationId', isEqualTo: locId)
            .where('dayOfWeek', isEqualTo: day)
            .where('weekStart', isEqualTo: weekStr)
            .get();
        for (var doc in snap.docs) {
          await doc.reference.delete();
        }
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
      await batch.commit();

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
                    color: const Color(0xFFF59E0B).withOpacity(0.15),
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
        final Map<String, dynamic> updates = {};
        for (int i = 0; i < _locations.length; i++) {
          updates['dutyLocationConfigs.${_locations[i].id}.order'] = i;
        }
        await FirebaseFirestore.instance
            .collection('workPeriods')
            .doc(widget.periodId)
            .update(updates);
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

      // 2. Sort Locations Deterministically (For Consistent Rotation)
      if (_locations.isEmpty) throw 'Hiçbir nöbet yeri yok.';
      _locations.sort((a, b) => a.name.compareTo(b.name));

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

      // 4. Load Previous Week Assignments (For Rotation)
      final prevWeekStr = _selectedWeekStart
          .subtract(const Duration(days: 7))
          .toIso8601String();

      final prevSnap = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('periodId', isEqualTo: widget.periodId)
          .where('weekStart', isEqualTo: prevWeekStr)
          .get();

      // Map: TeacherID -> Map<Day(int), LocationID>
      Map<String, Map<int, String>> prevTeacherLocs = {};
      for (var d in prevSnap.docs) {
        final tid = d['teacherId'];
        final day = d['dayOfWeek'];
        final locId = d['locationId'];
        if (!prevTeacherLocs.containsKey(tid)) prevTeacherLocs[tid] = {};
        prevTeacherLocs[tid]![day] = locId;
      }

      // Load Trackers (Grup Bazlı ve Lokasyon Bazlı Tarihçe)
      final historySnap = await FirebaseFirestore.instance
          .collection('dutyScheduleItems')
          .where('periodId', isEqualTo: widget.periodId)
          .get();

      Map<String, int> totalLoad = {};
      Map<String, int> currentLoad = {};
      Map<String, Map<String, int>> locHistoryCounts = {};
      Map<String, Map<String, int>> groupTotalLoad = {};
      Map<String, Map<String, int>> groupWeeklyLoad = {};

      // Lokasyonların grup haritası
      Map<String, String> locToGroup = {
        for (var l in _locations)
          l.id: (l.group.isNotEmpty ? l.group : '__default__'),
      };

      for (var t in teachers) {
        final tid = t['id'];
        totalLoad[tid] = 0;
        currentLoad[tid] = 0;
        locHistoryCounts[tid] = {};
        groupTotalLoad[tid] = {};
        groupWeeklyLoad[tid] = {};
        for (var l in _locations) {
          locHistoryCounts[tid]![l.id] = 0;
          final g = locToGroup[l.id] ?? '__default__';
          groupTotalLoad[tid]![g] = 0;
          groupWeeklyLoad[tid]![g] = 0;
        }
      }

      for (var d in historySnap.docs) {
        final tid = d['teacherId'];
        final lid = d['locationId'];
        totalLoad[tid] = (totalLoad[tid] ?? 0) + 1;
        if (locHistoryCounts.containsKey(tid) && locHistoryCounts[tid]!.containsKey(lid)) {
          locHistoryCounts[tid]![lid] = (locHistoryCounts[tid]![lid] ?? 0) + 1;
        }
        final g = locToGroup[lid];
        if (g != null && groupTotalLoad.containsKey(tid)) {
          groupTotalLoad[tid]![g] = (groupTotalLoad[tid]![g] ?? 0) + 1;
        }
      }

      int assignedCount = 0;
      // 5. Algorithm: Grup Bazlı ve Lokasyon Eşitlikli Rotasyon
      for (int day = 1; day <= 7; day++) {
        Set<String> assignedToday = {};

        // Active locations for this day
        final activeLocs = _locations
            .where((l) => l.activeDays.contains(day))
            .toList();

        // Helper: Get Effective Eligibility Pool
        List<String> getEffectiveIds(DutyLocation loc) {
          final specific = loc.eligibilities[day.toString()];
          if (specific != null && specific.isNotEmpty) {
            return List<String>.from(specific);
          }
          final all = loc.eligibilities.values
              .expand((e) => (e as List).map((x) => x.toString()))
              .toSet()
              .toList();
          return all;
        }

        // Sort by scarcity (Hardest to fill first)
        activeLocs.sort((a, b) {
          final countA = getEffectiveIds(a).length;
          final countB = getEffectiveIds(b).length;
          return countA.compareTo(countB);
        });

        if (activeLocs.isEmpty) continue;

        // Helper to find next location index
        String? getPrevLocId(int currentIndex) {
          int prevIndex = (currentIndex - 1);
          if (prevIndex < 0) prevIndex = activeLocs.length - 1;
          return activeLocs[prevIndex].id;
        }

        for (int i = 0; i < activeLocs.length; i++) {
          final loc = activeLocs[i];
          final eligibleIds = getEffectiveIds(loc);
          final g = locToGroup[loc.id] ?? '__default__';

          if (eligibleIds.isEmpty) continue;

          // 1. Filter Candidates (Eligible & Not assigned today)
          var candidates = teachers.where((t) {
            final tid = t['id'];
            return eligibleIds.contains(tid) && !assignedToday.contains(tid);
          }).toList();

          if (candidates.isEmpty) continue;

          final targetPrevLocId = getPrevLocId(i);

          candidates.sort((a, b) {
            final idA = a['id'];
            final idB = b['id'];

            double scoreA = 0;
            double scoreB = 0;

            // 1. HER NOKTADA EŞİT TUTMA (Location History - EN YÜKSEK ÖNCELİK)
            // Kural: 7 nöbet yeri varsa, 7 hafta sonunda herkes her noktada 1'er kez tutmuş olacak.
            // Bu nöbet yerinde daha önce kaç kez nöbet tuttuysa devasa ceza (100.000.000) alır.
            // Bu noktada henüz 0 nöbeti olan öğretmen doğrudan en öne geçer!
            final locLoadA = locHistoryCounts[idA]?[loc.id] ?? 0;
            final locLoadB = locHistoryCounts[idB]?[loc.id] ?? 0;
            scoreA += locLoadA * 100000000;
            scoreB += locLoadB * 100000000;

            // 2. GRUP İÇİ HAFTALIK KOTA (Herkes 1'er kez tutmadan 2. nöbet verilmez)
            // Kural: "Her noktaya 1'er nöbetçi ver, eğer yetmezse 2.ye geç ama tümüne vermeden birine 2.yi verme"
            // Bu grupta bu hafta nöbet tuttuysa 5.000.000 ceza ile sıranın arkasına atılır.
            final grpWeeklyA = groupWeeklyLoad[idA]?[g] ?? 0;
            final grpWeeklyB = groupWeeklyLoad[idB]?[g] ?? 0;
            if (grpWeeklyA >= 1) scoreA += grpWeeklyA * 5000000;
            if (grpWeeklyB >= 1) scoreB += grpWeeklyB * 5000000;

            // 3. GRUP İÇİ TOPLAM İSTATİSTİK (Az olandan devam etme)
            // Kural: "Diğer gruplar kendi içinde değerlendirilecek. İstatistiklere toplam bakılacak az olandan devam edecek."
            final grpTotalA = groupTotalLoad[idA]?[g] ?? 0;
            final grpTotalB = groupTotalLoad[idB]?[g] ?? 0;
            scoreA += grpTotalA * 10000;
            scoreB += grpTotalB * 10000;

            // 4. GENEL HAFTALIK YÜK (Aşırı yüklenme önleme)
            if ((currentLoad[idA] ?? 0) >= 2) scoreA += 50000;
            if ((currentLoad[idB] ?? 0) >= 2) scoreB += 50000;

            // 5. Genel Toplam Yük (Genel eşitlik için ince ayar)
            scoreA += (totalLoad[idA] ?? 0) * 100;
            scoreB += (totalLoad[idB] ?? 0) * 100;

            // 6. Aynı Nöbet Yerinde Peş Peşe Tutma Cezası
            if (prevTeacherLocs[idA]?.values.contains(loc.id) ?? false) {
              scoreA += 500;
            }
            if (prevTeacherLocs[idB]?.values.contains(loc.id) ?? false) {
              scoreB += 500;
            }

            // 7. Doğal Döngüsel Rotasyon Bonusu
            final prevLocA = prevTeacherLocs[idA]?[day];
            if (prevLocA == targetPrevLocId) scoreA -= 250;
            final prevLocB = prevTeacherLocs[idB]?[day];
            if (prevLocB == targetPrevLocId) scoreB -= 250;

            return scoreA.compareTo(scoreB);
          });

          final selectedTeacher = candidates.first;

          // Atama
          final tId = selectedTeacher['id'];
          final tName = selectedTeacher['fullName'] ?? selectedTeacher['name'];
          assignedToday.add(tId);
          totalLoad[tId] = (totalLoad[tId] ?? 0) + 1;
          currentLoad[tId] = (currentLoad[tId] ?? 0) + 1;
          groupTotalLoad[tId]?[g] = (groupTotalLoad[tId]?[g] ?? 0) + 1;
          groupWeeklyLoad[tId]?[g] = (groupWeeklyLoad[tId]?[g] ?? 0) + 1;
          assignedCount++;

          if (locHistoryCounts.containsKey(tId)) {
            locHistoryCounts[tId]![loc.id] =
                (locHistoryCounts[tId]![loc.id] ?? 0) + 1;
          }

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
            'dutyDate': _selectedWeekStart.add(Duration(days: day - 1)).toIso8601String(),
            'sendNotification': false,
            'notificationSent': false,
            'notifiedTeacherId': null,
          });
        }
      }

      await batch.commit();
      if (!mounted) return;
      if (assignedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Otomatik dağıtım (Döngüsel Rotasyon) tamamlandı. $assignedCount atama yapıldı.',
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
