import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:ui';
import '../../../services/attendance_service.dart';
import 'attendance_qr_page.dart';
import 'manual_attendance_screen.dart';

class AttendanceDashboard extends StatefulWidget {
  const AttendanceDashboard({super.key});

  @override
  State<AttendanceDashboard> createState() => _AttendanceDashboardState();
}

class _AttendanceDashboardState extends State<AttendanceDashboard> with SingleTickerProviderStateMixin {
  final AttendanceService _service = AttendanceService();
  late TabController _tabController;

  // Tab 1: Daily
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _dailyRecords = [];
  List<Map<String, dynamic>> _allStaff = [];
  List<Map<String, dynamic>> _schoolTypes = [];
  bool _loadingDaily = true;
  String _myInstitutionId = '';
  StreamSubscription? _dailySubscription;

  // Filters
  String? _selectedDepartment;
  String? _selectedSchoolType;
  String _searchQuery = '';

  // Tab 2: History
  DateTime _historyStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _historyEnd = DateTime.now();
  List<Map<String, dynamic>> _historyRecords = [];
  bool _loadingHistory = false;
  String? _selectedStaffId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStaffAndDaily();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dailySubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadStaffAndDaily() async {
    setState(() => _loadingDaily = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email ?? '';
      if (!email.contains('@')) return;
      final domain = email.split('@')[1];
      if (!domain.contains('.')) return;
      final institutionId = domain.split('.')[0].toUpperCase();
      _myInstitutionId = institutionId;

      // Load Staff
      final staffQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: institutionId)
          .where('type', whereIn: ['staff', 'teacher'])
          .get();

      _allStaff = staffQuery.docs.map((e) {
        final data = e.data();
        data['id'] = e.id;
        return data;
      }).toList();

      // Load School Types
      final stQuery = await FirebaseFirestore.instance
          .collection('schoolTypes')
          .where('institutionId', isEqualTo: institutionId)
          .get();
      
      _schoolTypes = stQuery.docs.map((e) {
        final data = e.data();
        data['id'] = e.id;
        return data;
      }).toList();

      _initDailyStream();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingDaily = false);
      }
    }
  }

  void _initDailyStream() {
    _dailySubscription?.cancel();
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    
    _dailySubscription = FirebaseFirestore.instance
        .collection('attendance')
        .where('institutionId', isEqualTo: _myInstitutionId)
        .where('date', isEqualTo: dateStr)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _dailyRecords = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
        });
      }
    });
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final records = await _service.getHistory(
        startDate: _historyStart,
        endDate: _historyEnd,
        institutionId: _myInstitutionId,
        userId: _selectedStaffId,
      );
      setState(() => _historyRecords = records);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      setState(() => _loadingHistory = false);
    }
  }

  String _getStaffName(String userId) {
    final staff = _allStaff.firstWhere((s) => s['id'] == userId, orElse: () => {});
    if (staff.isNotEmpty) {
      return staff['fullName'] ?? "${staff['firstName']} ${staff['lastName']}";
    }
    return "Bilinmeyen Personel";
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFFEC4899),
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          centerTitle: false,
          title: Text(
            'Puantaj Yönetimi',
            style: TextStyle(
              color: const Color(0xFF0F172A), // slate-900
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF6366F1), size: 24),
                onPressed: _showQrCodeDialog,
                tooltip: 'Giriş/Çıkış QR Kodu',
              ),
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Center(
                child: Container(
                  height: 48,
                  constraints: const BoxConstraints(maxWidth: 1400),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9), // slate-100
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    padding: const EdgeInsets.all(4),
                    splashBorderRadius: BorderRadius.circular(12),
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    labelColor: const Color(0xFF6366F1),
                    unselectedLabelColor: const Color(0xFF64748B),
                    labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    tabs: const [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.today_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('GÜNLÜK'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('ARŞİV'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildDailyTab(),
            _buildHistoryTab(),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showManualEntryDialog,
          backgroundColor: const Color(0xFF6366F1),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('Manuel Kayıt', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          elevation: 4,
        ),
      ),
    );
  }

  Widget _buildDailyTab() {
    if (_loadingDaily) return const Center(child: CircularProgressIndicator());

    // Filter staff
    final List<Map<String, dynamic>> filteredStaff = _allStaff.where((s) {
      final nameMatches = s['fullName']?.toString().toLowerCase().contains(_searchQuery.toLowerCase()) ?? true;
      final deptMatches = _selectedDepartment == null || s['department'] == _selectedDepartment;
      
      bool typeMatches = _selectedSchoolType == null;
      if (!typeMatches && _selectedSchoolType != null) {
        if (s['workLocations'] != null && s['workLocations'] is List) {
          typeMatches = List<String>.from(s['workLocations']).contains(_selectedSchoolType);
        } else if (s['schoolTypes'] != null && s['schoolTypes'] is List) {
          typeMatches = List<String>.from(s['schoolTypes']).contains(_selectedSchoolType);
        }
      }
      
      return nameMatches && deptMatches && typeMatches;
    }).toList();

    final List<Map<String, dynamic>> combinedList = [];
    for (var staff in filteredStaff) {
      final attendance = _dailyRecords.firstWhere(
        (r) => r['userId'] == staff['id'],
        orElse: () => {},
      );
      combinedList.add({
        'staff': staff,
        'attendance': attendance.isNotEmpty ? attendance : null,
      });
    }

    final total = filteredStaff.length;
    final present = combinedList.where((e) => e['attendance'] != null).length;
    final absent = total - present;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Column(
          children: [
            // Header & Stats
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  // Date Selector
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF6366F1)),
                          onPressed: () {
                            setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
                            _initDailyStream();
                          },
                        ),
                        Text(
                          DateFormat('d MMMM yyyy', 'tr_TR').format(_selectedDate),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)), // slate-800
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF6366F1)),
                          onPressed: () {
                            setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
                            _initDailyStream();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Stats Row
                  Row(
                    children: [
                      _buildStatCard('Toplam', total.toString(), const Color(0xFF6366F1), Icons.people_outline),
                      const SizedBox(width: 12),
                      _buildStatCard('Gelen', present.toString(), const Color(0xFF10B981), Icons.check_circle_outline),
                      const SizedBox(width: 12),
                      _buildStatCard('Gelmeyen', absent.toString(), const Color(0xFFEF4444), Icons.error_outline),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Filters Row
                  Row(
                    children: [
                      Expanded(
                        child: _buildFilterBadge(
                          label: _selectedDepartment ?? 'Departman',
                          isActive: _selectedDepartment != null,
                          onTap: _showDepartmentFilter,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildFilterBadge(
                          label: _selectedSchoolType ?? 'Okul Türü',
                          isActive: _selectedSchoolType != null,
                          onTap: _showSchoolTypeFilter,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: (_selectedDepartment != null || _selectedSchoolType != null) ? Colors.orange.shade50 : const Color(0xFFF8FAFC), // slate-50
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.filter_list_off_rounded,
                            color: (_selectedDepartment != null || _selectedSchoolType != null) ? Colors.orange : const Color(0xFF94A3B8), // slate-400
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _selectedDepartment = null;
                              _selectedSchoolType = null;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Search Bar in list
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Personel ara...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)), // slate
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: combinedList.length,
                itemBuilder: (context, index) {
                  final item = combinedList[index];
                  return _buildStaffAttendanceCard(item);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF475569)), // slate-600
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBadge({required String label, required bool isActive, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF6366F1).withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? const Color(0xFF6366F1) : const Color(0xFF475569), // slate-600
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: isActive ? const Color(0xFF6366F1) : const Color(0xFF94A3B8), // slate-400
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffAttendanceCard(Map<String, dynamic> item) {
    final staff = item['staff'];
    final attendance = item['attendance'];
    final hasRecord = attendance != null;
    
    String statusText = 'Gelmedi';
    Color statusColor = const Color(0xFFEF4444);
    String timeText = '-';

    if (hasRecord) {
      statusText = 'İçeride';
      statusColor = const Color(0xFF10B981);
      final checkIn = (attendance['checkIn'] as Timestamp).toDate();
      timeText = DateFormat('HH:mm').format(checkIn);
      
      if (attendance['checkOut'] != null) {
        final checkOut = (attendance['checkOut'] as Timestamp).toDate();
        timeText += " - ${DateFormat('HH:mm').format(checkOut)}";
        statusText = 'Çıktı';
        statusColor = const Color(0xFF64748B);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        onTap: hasRecord ? () => _showEditEntryDialog(attendance, "${staff['firstName']} ${staff['lastName']}") : null,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF6366F1).withOpacity(0.8), const Color(0xFF6366F1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              (staff['fullName'] ?? staff['firstName'] ?? 'P').toString()[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ),
        title: Text(
          staff['fullName'] ?? "${staff['firstName']} ${staff['lastName']}",
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              staff['department'] ?? 'Departman Yok',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)), // slate-500
            ),
            if (staff['workLocations'] != null && (staff['workLocations'] as List).isNotEmpty)
              Text(
                (staff['workLocations'] as List).join(', '),
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)), // slate-400
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                statusText,
                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              timeText,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)), // slate-700
            ),
          ],
        ),
      ),
    );
  }

  void _showDepartmentFilter() {
    final depts = _allStaff
        .map((e) => e['department']?.toString())
        .where((e) => e != null && e.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    depts.sort();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _buildFilterSheet('Departman Seçin', depts, _selectedDepartment, (val) {
        setState(() => _selectedDepartment = val);
        Navigator.pop(context);
      }),
    );
  }

  void _showSchoolTypeFilter() {
    final Set<String> typesSet = {};
    
    // 1. Add from Firestore collection
    for (var e in _schoolTypes) {
      final name = e['schoolTypeName']?.toString() ?? e['name']?.toString() ?? e['typeName']?.toString();
      if (name != null) typesSet.add(name);
    }
    
    // 2. Add from staff records (as fallback or addition)
    for (var s in _allStaff) {
      if (s['workLocations'] != null && s['workLocations'] is List) {
        for (var loc in (s['workLocations'] as List)) {
          if (loc != null) typesSet.add(loc.toString());
        }
      } else if (s['schoolTypes'] != null && s['schoolTypes'] is List) {
        for (var st in (s['schoolTypes'] as List)) {
          if (st != null) typesSet.add(st.toString());
        }
      }
    }

    final types = typesSet.toList();
    types.sort();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _buildFilterSheet('Okul Türü Seçin', types, _selectedSchoolType, (val) {
        setState(() => _selectedSchoolType = val);
        Navigator.pop(context);
      }),
    );
  }

  Widget _buildFilterSheet(String title, List<String> items, String? selected, Function(String?) onSelect) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: const Text('Tümü'),
                  leading: Icon(selected == null ? Icons.radio_button_checked : Icons.radio_button_off, color: const Color(0xFF6366F1)),
                  onTap: () => onSelect(null),
                ),
                ...items.map((item) => ListTile(
                  title: Text(item),
                  leading: Icon(selected == item ? Icons.radio_button_checked : Icons.radio_button_off, color: const Color(0xFF6366F1)),
                  onTap: () => onSelect(item),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showManualEntryDialog() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManualAttendanceScreen(
          institutionId: _myInstitutionId,
          initialStaff: _allStaff,
        ),
      ),
    );

    if (result == true) {
      _initDailyStream();
    }
  }

  Future<void> _showEditEntryDialog(Map<String, dynamic> attendance, String staffName) async {
    final docId = attendance['id'];
    final dateStr = attendance['date'] as String;
    final date = DateTime.parse(dateStr);
    final checkInTs = attendance['checkIn'] as Timestamp;
    final checkOutTs = attendance['checkOut'] as Timestamp?;
    TimeOfDay checkInTime = TimeOfDay.fromDateTime(checkInTs.toDate());
    TimeOfDay? checkOutTime = checkOutTs != null ? TimeOfDay.fromDateTime(checkOutTs.toDate()) : null;
    final noteController = TextEditingController(text: attendance['notes'] ?? '');

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Düzenle: $staffName'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Tarih: ${DateFormat('d MMMM yyyy').format(date)}"),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Giriş Saati'),
                    subtitle: Text(checkInTime.format(context)),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: checkInTime);
                      if (picked != null) setDialogState(() => checkInTime = picked);
                    },
                  ),
                  ListTile(
                    title: const Text('Çıkış Saati'),
                    subtitle: Text(checkOutTime?.format(context) ?? 'Yok'),
                    trailing: IconButton(
                      icon: Icon(checkOutTime == null ? Icons.add_circle_outline : Icons.clear),
                      onPressed: () async {
                        if (checkOutTime == null) {
                          final picked = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 17, minute: 0));
                          if (picked != null) setDialogState(() => checkOutTime = picked);
                        } else {
                          setDialogState(() => checkOutTime = null);
                        }
                      },
                    ),
                  ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: 'Not'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
              ElevatedButton(
                onPressed: () async {
                  final checkInDateTime = DateTime(date.year, date.month, date.day, checkInTime.hour, checkInTime.minute);
                  DateTime? checkOutDateTime;
                  if (checkOutTime != null) {
                    checkOutDateTime = DateTime(date.year, date.month, date.day, checkOutTime!.hour, checkOutTime!.minute);
                  }
                  try {
                    await _service.updateAttendance(
                      docId: docId,
                      checkIn: checkInDateTime,
                      checkOut: checkOutDateTime,
                      note: noteController.text,
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      _initDailyStream();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kayıt güncellendi')));
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                  }
                },
                child: const Text('Güncelle'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Column(
          children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: DateTimeRange(start: _historyStart, end: _historyEnd),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(primary: Color(0xFF6366F1)),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null) {
                          setState(() {
                            _historyStart = picked.start;
                            _historyEnd = picked.end;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF6366F1)),
                            const SizedBox(width: 12),
                            Text(
                              "${DateFormat('dd.MM.yyyy').format(_historyStart)} - ${DateFormat('dd.MM.yyyy').format(_historyEnd)}",
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        labelText: 'Personel Filtrele',
                        labelStyle: const TextStyle(fontSize: 12),
                        prefixIcon: const Icon(Icons.person_rounded, size: 20, color: Color(0xFF6366F1)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      value: _selectedStaffId,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Tüm Personeller', style: TextStyle(fontSize: 13)),
                        ),
                        ..._allStaff.map((s) => DropdownMenuItem(
                          value: s['id'] as String,
                          child: Text(s['fullName'] ?? "${s['firstName']} ${s['lastName']}", style: const TextStyle(fontSize: 13)),
                        )),
                      ],
                      onChanged: (v) => setState(() => _selectedStaffId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _loadHistory,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Getir', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingHistory
              ? const Center(child: CircularProgressIndicator())
              : _historyRecords.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_rounded, size: 64, color: const Color(0xFFE2E8F0)), // slate-200
                          const SizedBox(height: 16),
                          Text('Kayıt bulunamadı', style: TextStyle(color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)), // slate-400
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _historyRecords.length,
                      itemBuilder: (context, index) {
                        final record = _historyRecords[index];
                        final userId = record['userId'] as String;
                        final staffName = _getStaffName(userId);
                        final date = DateTime.parse(record['date']);
                        final checkIn = (record['checkIn'] as Timestamp).toDate();
                        final checkOutTs = record['checkOut'] as Timestamp?;
                        String timeText = DateFormat('HH:mm').format(checkIn);
                        if (checkOutTs != null) {
                          timeText += " - ${DateFormat('HH:mm').format(checkOutTs.toDate())}";
                        }
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFF1F5F9)),
                          ),
                          child: ListTile(
                            onTap: () => _showEditEntryDialog(record, staffName),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  staffName.isNotEmpty ? staffName[0] : '?',
                                  style: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            title: Text(staffName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            subtitle: Text(
                              DateFormat('d MMMM yyyy, EEEE', 'tr_TR').format(date),
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)), // slate-500
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  timeText,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1E293B)),
                                ),
                                if (record['notes'] != null && record['notes'].isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Icon(Icons.sticky_note_2_rounded, size: 14, color: Colors.orange.shade400),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    ),),);
  }

  void _showQrCodeDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AttendanceQrPage()),
    );
  }
}
