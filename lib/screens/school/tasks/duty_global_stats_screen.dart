import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import '../../../models/school/duty_model.dart';
import '../../../services/pdf_service.dart';

class DutyGlobalStatsScreen extends StatefulWidget {
  final String institutionId;
  final String? currentTermId;
  final List<Map<String, dynamic>> periods;
  final String? schoolTypeId;
  final String? schoolTypeName;

  const DutyGlobalStatsScreen({
    Key? key,
    required this.institutionId,
    this.currentTermId,
    required this.periods,
    this.schoolTypeId,
    this.schoolTypeName,
  }) : super(key: key);

  @override
  State<DutyGlobalStatsScreen> createState() => _DutyGlobalStatsScreenState();
}

class _DutyGlobalStatsScreenState extends State<DutyGlobalStatsScreen> {
  bool _isLoading = true;
  String _selectedPeriodFilter = 'all'; // 'all' or periodId
  DateTime? _startDate;
  DateTime? _endDate;
  String _searchQuery = '';

  Map<String, Map<String, dynamic>> _periodLocationConfigs = {};
  List<DutyLocation> _locations = [];
  List<QueryDocumentSnapshot> _teachers = [];
  List<DutyScheduleItem> _allItems = [];
  StreamSubscription<QuerySnapshot>? _itemsSub;

  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');

  @override
  void initState() {
    super.initState();
    _initDateRange();
    _loadAllData();
    _initItemsStream();
  }

  @override
  void dispose() {
    _itemsSub?.cancel();
    super.dispose();
  }

  void _initItemsStream() {
    _itemsSub?.cancel();
    final periodIds = widget.periods.map((p) => p['id'] as String).toSet();
    if (periodIds.isEmpty) return;

    _itemsSub = FirebaseFirestore.instance
        .collection('dutyScheduleItems')
        .where('institutionId', isEqualTo: widget.institutionId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final loadedItems = <DutyScheduleItem>[];
      for (var doc in snapshot.docs) {
        final item = DutyScheduleItem.fromMap(doc.data(), doc.id);
        if (periodIds.contains(item.periodId)) {
          loadedItems.add(item);
        }
      }
      setState(() {
        _allItems = loadedItems;
      });
    }, onError: (e) {
      debugPrint('DutyGlobalStats stream error: $e');
    });
  }

  DateTime? _extractDate(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) return DateTime.tryParse(val);
    return null;
  }

  void _initDateRange() {
    // Alt dönemlerin tarih aralığını bul
    DateTime? minDate;
    DateTime? maxDate;
    for (var p in widget.periods) {
      final s = _extractDate(p['startDate']);
      final e = _extractDate(p['endDate']);
      if (s != null && (minDate == null || s.isBefore(minDate))) {
        minDate = s;
      }
      if (e != null && (maxDate == null || e.isAfter(maxDate))) {
        maxDate = e;
      }
    }
    _startDate = minDate ?? DateTime.now().subtract(const Duration(days: 30));
    _endDate = maxDate ?? DateTime.now().add(const Duration(days: 90));
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

    // 2. Dönem kontrolü
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

  Future<void> _loadAllData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      // 1. Nöbet Yerlerini Yükle
      final locSnap = await FirebaseFirestore.instance
          .collection('dutyLocations')
          .where('institutionId', isEqualTo: widget.institutionId)
          .get();
      _locations = locSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return DutyLocation.fromMap(data);
      }).toList();
      _locations.sort((a, b) {
        final cmp = a.order.compareTo(b.order);
        if (cmp != 0) return cmp;
        return a.name.compareTo(b.name);
      });

      // 1b. Alt Dönem Nöbet Yeri Konfigürasyonlarını Al
      final configs = <String, Map<String, dynamic>>{};
      for (var p in widget.periods) {
        final pid = p['id']?.toString();
        if (pid != null && p['dutyLocationConfigs'] is Map) {
          configs[pid] = Map<String, dynamic>.from(p['dutyLocationConfigs'] as Map);
        }
      }
      for (var p in widget.periods) {
        final pid = p['id']?.toString();
        if (pid != null && !configs.containsKey(pid)) {
          try {
            final pDoc = await FirebaseFirestore.instance.collection('workPeriods').doc(pid).get();
            if (pDoc.exists && pDoc.data()?['dutyLocationConfigs'] is Map) {
              configs[pid] = Map<String, dynamic>.from(pDoc.data()!['dutyLocationConfigs'] as Map);
            }
          } catch (_) {}
        }
      }
      _periodLocationConfigs = configs;

      // 2. Öğretmenleri Yükle (sadece aktif ve mevcut okul türünde olanlar)
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: widget.institutionId)
          .where('type', whereIn: ['teacher', 'staff', 'admin'])
          .get();
      _teachers = userSnap.docs
          .where((d) => _isUserActive(
                d.data(),
                termId: widget.currentTermId,
                schoolTypeId: widget.schoolTypeId,
                schoolTypeName: widget.schoolTypeName,
              ))
          .toList();

      // 3. Mevcut dönemdeki alt dönemlerin ID'leri
      final periodIds = widget.periods.map((p) => p['id'] as String).toList();

      if (periodIds.isEmpty) {
        _allItems = [];
      } else {
        // Firestore whereIn en fazla 30 eleman alabilir
        List<DutyScheduleItem> loadedItems = [];
        for (var i = 0; i < periodIds.length; i += 30) {
          final chunk = periodIds.sublist(
            i,
            i + 30 > periodIds.length ? periodIds.length : i + 30,
          );
          final itemsSnap = await FirebaseFirestore.instance
              .collection('dutyScheduleItems')
              .where('periodId', whereIn: chunk)
              .get();

          for (var doc in itemsSnap.docs) {
            loadedItems.add(DutyScheduleItem.fromMap(doc.data(), doc.id));
          }
        }
        _allItems = loadedItems;
      }
    } catch (e) {
      debugPrint('Genel istatistik veri yükleme hatası: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(
        start: _startDate ?? DateTime.now(),
        end: _endDate ?? DateTime.now(),
      ),
      locale: const Locale('tr', 'TR'),
      saveText: 'Seç',
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  List<DutyScheduleItem> get _filteredItems {
    return _allItems.where((item) {
      // 1. Alt dönem filtresi
      if (_selectedPeriodFilter != 'all' &&
          item.periodId != _selectedPeriodFilter) {
        return false;
      }
      // 2. Tarih aralığı filtresi
      if (item.weekStart != null && _startDate != null && _endDate != null) {
        final filterEnd = _endDate!.add(const Duration(days: 1));
        if (item.weekStart!.isBefore(_startDate!) ||
            item.weekStart!.isAfter(filterEnd)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<DutyLocation> get _currentLocations {
    if (_selectedPeriodFilter == 'all') {
      return _locations;
    }

    final configs = _periodLocationConfigs[_selectedPeriodFilter];
    final assignedLocationIds = _filteredItems.map((i) => i.locationId).toSet();

    if (configs == null || configs.isEmpty) {
      if (assignedLocationIds.isNotEmpty) {
        return _locations.where((l) => assignedLocationIds.contains(l.id)).toList();
      }
      return _locations;
    }

    final filtered = _locations.where((loc) {
      final cfg = configs[loc.id] as Map<String, dynamic>?;
      final isEnabled = cfg != null && cfg['isEnabled'] == true;
      return isEnabled || assignedLocationIds.contains(loc.id);
    }).map((loc) {
      final cfg = configs[loc.id] as Map<String, dynamic>?;
      if (cfg != null) {
        final ovDays = cfg['activeDays'] != null
            ? List<int>.from(cfg['activeDays'])
            : loc.activeDays;
        final ovStart = cfg['startTime'] ?? loc.startTime;
        final ovEnd = cfg['endTime'] ?? loc.endTime;
        final ovOrder = (cfg['order'] as num?)?.toInt() ?? loc.order;
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
          eligibilities: loc.eligibilities,
        );
      }
      return loc;
    }).toList();

    filtered.sort((a, b) {
      final cmp = a.order.compareTo(b.order);
      if (cmp != 0) return cmp;
      return a.name.compareTo(b.name);
    });

    return filtered;
  }

  List<Map<String, dynamic>> _computeTeacherStats() {
    final filtered = _filteredItems;
    final currentLocs = _currentLocations;

    List<Map<String, dynamic>> stats = [];

    for (var t in _teachers) {
      final tid = t.id;
      final tData = t.data() as Map<String, dynamic>;
      final tName = tData['fullName'] ?? tData['name'] ?? 'İsimsiz';

      final branch = _getUserDisplayTitle(tData);

      // Arama filtresi
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchName = tName.toLowerCase().contains(q);
        final matchBranch = branch.toLowerCase().contains(q);
        if (!matchName && !matchBranch) continue;
      }

      int total = 0;
      Map<String, int> locCounts = {};
      for (var l in currentLocs) {
        locCounts[l.id] = 0;
      }

      Map<String, int> periodCounts = {};
      for (var p in widget.periods) {
        periodCounts[p['id'] as String] = 0;
      }

      for (var item in filtered) {
        if (item.teacherId == tid) {
          total++;
          if (locCounts.containsKey(item.locationId)) {
            locCounts[item.locationId] = (locCounts[item.locationId] ?? 0) + 1;
          }
          periodCounts[item.periodId] = (periodCounts[item.periodId] ?? 0) + 1;
        }
      }

      stats.add({
        'id': tid,
        'name': tName,
        'branch': branch,
        'total': total,
        'locCounts': locCounts,
        'periodCounts': periodCounts,
      });
    }

    // Toplam nöbete göre çoktan aza sırala
    stats.sort((a, b) {
      final cmp = (b['total'] as int).compareTo(a['total'] as int);
      if (cmp != 0) return cmp;
      return (a['name'] as String).compareTo(b['name'] as String);
    });

    return stats;
  }

  Future<void> _printReport(List<Map<String, dynamic>> stats) async {
    final pdfService = PdfService();
    final rangeStr = _startDate != null && _endDate != null
        ? '${_dateFormat.format(_startDate!)} - ${_dateFormat.format(_endDate!)}'
        : 'Tüm Dönem';

    String filterTitle = 'Tüm Alt Dönemler (Kümülatif)';
    if (_selectedPeriodFilter != 'all') {
      final p = widget.periods.firstWhere(
        (e) => e['id'] == _selectedPeriodFilter,
        orElse: () => {},
      );
      filterTitle = p['periodName'] ?? 'Alt Dönem';
    }

    final title = '${widget.schoolTypeName ?? "Okul"} - Nöbet İstatistikleri ($filterTitle)';
    final currentLocs = _currentLocations;

    List<String> headers = ['Öğretmen', 'Branş', 'Toplam'];
    for (var l in currentLocs) {
      headers.add(l.name);
    }

    List<List<String>> rows = [];
    for (var s in stats) {
      List<String> row = [
        s['name'].toString(),
        s['branch'].toString(),
        s['total'].toString(),
      ];
      final locs = s['locCounts'] as Map<String, int>;
      for (var l in currentLocs) {
        row.add((locs[l.id] ?? 0).toString());
      }
      rows.add(row);
    }

    final pdfData = await pdfService.generateDutyStatsPdf(
      periodName: title,
      dateRange: rangeStr,
      headers: headers,
      rows: rows,
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdfData,
      name: 'Genel_Nobet_Istatistikleri_$rangeStr',
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _computeTeacherStats();
    final totalAssignedDuties = _filteredItems.length;
    final activeTeacherCount = stats.where((s) => (s['total'] as int) > 0).length;
    final avgDuties = activeTeacherCount > 0
        ? (totalAssignedDuties / activeTeacherCount).toStringAsFixed(1)
        : '0';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: EduknAppBar(
        title: 'Genel Nöbet İstatistikleri',
        subtitle: widget.schoolTypeName ?? 'Konsolide Alt Dönem Analizi',
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined, color: Color(0xFF4F46E5)),
            tooltip: 'İstatistikleri Yazdır (PDF)',
            onPressed: stats.isEmpty ? null : () => _printReport(stats),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
            tooltip: 'Yenile',
            onPressed: _loadAllData,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Filtre Barı
                  _buildFilterBar(),
                  const SizedBox(height: 16),

                  // 2. Özet Bilgi Kartları
                  _buildSummaryCards(
                    totalDuties: totalAssignedDuties,
                    activeTeachers: activeTeacherCount,
                    totalTeachers: _teachers.length,
                    avgDuties: avgDuties,
                    totalLocations: _currentLocations.length,
                  ),
                  const SizedBox(height: 20),

                  // 3. Tablo / Kart Listesi
                  _buildStatsTable(stats),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Alt Dönem Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedPeriodFilter,
                icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF4F46E5)),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    _selectedPeriodFilter = val;
                    if (val == 'all') {
                      _initDateRange();
                    } else {
                      final p = widget.periods.firstWhere(
                        (e) => e['id'] == val,
                        orElse: () => <String, dynamic>{},
                      );
                      final s = _extractDate(p['startDate']);
                      final e = _extractDate(p['endDate']);
                      if (s != null) _startDate = s;
                      if (e != null) _endDate = e;
                    }
                  });
                },
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.layers_rounded, size: 18, color: Color(0xFF4F46E5)),
                        SizedBox(width: 8),
                        Text('Tüm Alt Dönemler (Kümülatif)'),
                      ],
                    ),
                  ),
                  ...widget.periods.map((p) {
                    return DropdownMenuItem(
                      value: p['id'] as String,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_view_week, size: 18, color: Color(0xFF0891B2)),
                          const SizedBox(width: 8),
                          Text(p['periodName'] ?? 'İsimsiz Dönem'),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          // Tarih Aralığı Seçici
          InkWell(
            onTap: _selectDateRange,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.date_range, size: 18, color: Color(0xFF4F46E5)),
                  const SizedBox(width: 8),
                  Text(
                    _startDate != null && _endDate != null
                        ? '${_dateFormat.format(_startDate!)} - ${_dateFormat.format(_endDate!)}'
                        : 'Tarih Aralığı Seç',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Öğretmen / Branş Arama Kutusu
          SizedBox(
            width: 220,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Öğretmen / Branş ara...',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards({
    required int totalDuties,
    required int activeTeachers,
    required int totalTeachers,
    required String avgDuties,
    required int totalLocations,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 700;

        if (isSmall) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _statTile('Toplam Nöbet', '$totalDuties Görev', Icons.security_rounded, const Color(0xFF4F46E5)),
              _statTile('Nöbet Tutan', '$activeTeachers / $totalTeachers Öğrt.', Icons.people_alt_rounded, const Color(0xFF0891B2)),
              _statTile('Ortalama Nöbet', '$avgDuties / Öğrt.', Icons.analytics_outlined, const Color(0xFF16A34A)),
              _statTile('Nöbet Yeri', '$totalLocations Alan', Icons.place_outlined, const Color(0xFFD97706)),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: _statTile('Toplam Nöbet', '$totalDuties Görev', Icons.security_rounded, const Color(0xFF4F46E5))),
            const SizedBox(width: 12),
            Expanded(child: _statTile('Nöbet Tutan', '$activeTeachers / $totalTeachers Öğrt.', Icons.people_alt_rounded, const Color(0xFF0891B2))),
            const SizedBox(width: 12),
            Expanded(child: _statTile('Ortalama Nöbet', '$avgDuties / Öğrt.', Icons.analytics_outlined, const Color(0xFF16A34A))),
            const SizedBox(width: 12),
            Expanded(child: _statTile('Nöbet Yeri', '$totalLocations Alan', Icons.place_outlined, const Color(0xFFD97706))),
          ],
        );
      },
    );
  }

  Widget _statTile(String label, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                Text(
                  val,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsTable(List<Map<String, dynamic>> stats) {
    if (stats.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(Icons.bar_chart_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text(
              'Görüntülenecek nöbet istatistiği bulunamadı.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 4),
            Text(
              'Seçilen filtrelere göre henüz nöbet ataması yapılmamış.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    const headerStyle = TextStyle(
      color: Color(0xFF64748B),
      fontWeight: FontWeight.bold,
      fontSize: 12,
      letterSpacing: 0.5,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık Bilgi Satırı
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                  child: Row(
                    children: [
                      const Icon(Icons.table_chart_outlined, color: Color(0xFF4F46E5), size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Öğretmen Nöbet Dağılım Tablosu',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F46E5).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Toplam ${stats.length} öğretmen',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF4F46E5),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Yatay Kaydırılabilir Tablo (Alt Dönem İstatistiğindeki gibi sütunlu)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Column(
                      children: [
                        // Tablo Başlığı (Headers)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 44,
                                child: Center(
                                  child: Text('#', style: headerStyle),
                                ),
                              ),
                              const SizedBox(
                                width: 220,
                                child: Text('ÖĞRETMEN', style: headerStyle),
                              ),
                              const SizedBox(
                                width: 90,
                                child: Center(
                                  child: Text('TOPLAM', style: headerStyle),
                                ),
                              ),
                              ..._currentLocations.map(
                                (l) => SizedBox(
                                  width: 130,
                                  child: Center(
                                    child: Tooltip(
                                      message: l.name,
                                      child: Text(
                                        _formatLocationHeader(l.name.toUpperCase()),
                                        textAlign: TextAlign.center,
                                        style: headerStyle.copyWith(
                                          fontSize: 10.5,
                                          height: 1.25,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Tablo Satırları (Rows)
                        ...stats.asMap().entries.map((entry) {
                          final index = entry.key;
                          final s = entry.value;
                          final total = s['total'] as int;
                          final name = s['name'] as String;
                          final branch = s['branch'] as String;
                          final locCounts = s['locCounts'] as Map<String, int>;
                          final isEven = index % 2 == 0;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isEven ? Colors.white : const Color(0xFFF8FAFC).withOpacity(0.5),
                              border: const Border(
                                bottom: BorderSide(color: Color(0xFFF1F5F9)),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Sıra No
                                SizedBox(
                                  width: 44,
                                  child: Center(
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: index < 3
                                            ? const Color(0xFF4F46E5).withOpacity(0.1)
                                            : Colors.grey.shade100,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: index < 3
                                              ? const Color(0xFF4F46E5)
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Öğretmen Adı ve Branşı
                                SizedBox(
                                  width: 220,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1E293B),
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        branch,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),

                                // Toplam Nöbet Rozeti
                                SizedBox(
                                  width: 90,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: total > 0
                                            ? const Color(0xFFDCFCE7)
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: total > 0
                                              ? const Color(0xFF86EFAC)
                                              : Colors.grey.shade300,
                                        ),
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

                                // Her Nöbet Yeri Sütunu (Sayı veya '-')
                                ..._currentLocations.map((loc) {
                                  final count = locCounts[loc.id] ?? 0;
                                  return SizedBox(
                                    width: 130,
                                    child: Center(
                                      child: count > 0
                                          ? Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF4F46E5).withOpacity(0.08),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '$count',
                                                style: const TextStyle(
                                                  color: Color(0xFF4F46E5),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            )
                                          : Text(
                                              '-',
                                              style: TextStyle(
                                                color: Colors.grey.shade300,
                                                fontSize: 13,
                                              ),
                                            ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatLocationHeader(String name) {
    final trimmed = name.trim();

    // 1. Parantez varsa parantezden önce ve sonrasını böl (Örn: "0. KAT\n(U KORİDOR)" veya "BAHÇE\n(ORTA ALAN)")
    if (trimmed.contains('(')) {
      final idx = trimmed.indexOf('(');
      final first = trimmed.substring(0, idx).trim();
      final second = trimmed.substring(idx).trim();
      if (first.isNotEmpty && second.isNotEmpty) {
        return '$first\n$second';
      }
    }

    // 2. " KAT " veya " KATI " ifadesi varsa (Örn: "0. KAT U KORİDOR" -> "0. KAT\nU KORİDOR")
    final katMatch = RegExp(r'^(.*?\bKAT[I]?\b)\s+(.+)$', caseSensitive: false).firstMatch(trimmed);
    if (katMatch != null) {
      final first = katMatch.group(1)?.trim() ?? '';
      final second = katMatch.group(2)?.trim() ?? '';
      if (first.isNotEmpty && second.isNotEmpty) {
        return '$first\n$second';
      }
    }

    // 3. Çok kelimeli ise iki satıra uygun şekilde böl
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length == 2) {
      return '${words[0]}\n${words[1]}';
    } else if (words.length == 3) {
      // Örn: "2 NUMARALI KAT" -> "2 NUMARALI\nKAT"
      if (words.last.toUpperCase() == 'KAT' || words.last.toUpperCase() == 'KATI') {
        return '${words[0]} ${words[1]}\n${words[2]}';
      }
      // Örn: "NÖBETÇİ MÜDÜR YARDIMCISI" -> "NÖBETÇİ\nMÜDÜR YARDIMCISI"
      return '${words[0]}\n${words[1]} ${words[2]}';
    } else if (words.length >= 4) {
      final mid = (words.length / 2).ceil();
      final first = words.sublist(0, mid).join(' ');
      final second = words.sublist(mid).join(' ');
      return '$first\n$second';
    }

    return trimmed;
  }
}
