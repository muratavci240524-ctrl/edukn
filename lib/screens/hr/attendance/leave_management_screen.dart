import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:excel/excel.dart' as ex;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../../services/leave_service.dart';
import '../../../services/leave_conflict_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'leave_approval_screen.dart';

class LeaveManagementScreen extends StatefulWidget {
  final String? institutionId;
  final String? schoolTypeId;

  const LeaveManagementScreen({
    super.key,
    this.institutionId,
    this.schoolTypeId,
  });

  @override
  State<LeaveManagementScreen> createState() => _LeaveManagementScreenState();
}

class _LeaveManagementScreenState extends State<LeaveManagementScreen>
    with SingleTickerProviderStateMixin {
  final LeaveService _service = LeaveService();
  final LeaveConflictService _conflictService = LeaveConflictService();
  late TabController _tabController;

  Map<String, dynamic>? _currentUserData;
  List<Map<String, dynamic>> _pendingRequests = [];
  List<Map<String, dynamic>> _historyRequests = [];
  List<Map<String, dynamic>> _allStaff = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        _currentUserData = userDoc.data();
        if (_currentUserData != null) _currentUserData!['id'] = user.uid;
      }

      final instId = widget.institutionId ?? _currentUserData?['institutionId'];

      // Personel listesini çek (sadece kendi kurumundakiler)
      final staffQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: instId)
          .get();

      _allStaff = staffQuery.docs.map((e) {
        final data = e.data();
        data['id'] = e.id;
        return data;
      }).toList();

      // İzin taleplerini çek (Yönetici değilse sadece kendininkileri)
      final bool isManager =
          _currentUserData?['role'] == 'admin' ||
          _currentUserData?['role'] == 'manager' ||
          _currentUserData?['role'] == 'genel_mudur' ||
          _currentUserData?['role'] == 'mudur';
      final allRequests = await _service.getLeaveRequests(
        institutionId: instId ?? '',
        userId: isManager ? null : user?.uid,
      );

      if (mounted) {
        setState(() {
          _pendingRequests = allRequests
              .where(
                (r) =>
                    r['status'] == 'pending' ||
                    r['status'] == 'lessons_assigned' ||
                    r['status'] == 'duties_checked',
              )
              .toList();
          _historyRequests = allRequests
              .where(
                (r) => r['status'] == 'approved' || r['status'] == 'rejected',
              )
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF64748B),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Future<void> _showRequestDialog() async {
    final instId = widget.institutionId ?? _currentUserData?['institutionId'];
    String? selectedUserId;
    DateTime startDate = DateTime.now();
    DateTime endDate =
        DateTime.now(); // Start same as end by default for easier hourly test
    String type = 'Yıllık İzin';
    bool isFullDay = true;
    TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);
    final reasonController = TextEditingController();
    bool _loading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              children: [
                // Handle bar
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Yeni İzin Talebi',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey.shade100,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Form Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Personnel Selection Card
                        _buildSectionTitle('Personel'),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _showPersonnelSelectionSheet(
                            setDialogState,
                            (id) {
                              selectedUserId = id;
                            },
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(
                                    0xFF4F46E5,
                                  ).withOpacity(0.1),
                                  child: Icon(
                                    Icons.person_outline,
                                    color: const Color(0xFF4F46E5),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    selectedUserId == null
                                        ? 'Personel Seçiniz'
                                        : _getStaffName(selectedUserId),
                                    style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: selectedUserId == null
                                          ? Colors.grey
                                          : Colors.black87,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Type & Reason Card
                        _buildSectionTitle('İzin Detayları'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'İzin Türü',
                            fillColor: Colors.grey.shade50,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                          ),
                          value: type,
                          items:
                              [
                                    'Yıllık İzin',
                                    'Mazeret İzni',
                                    'Rapor',
                                    'Ücretsiz İzin',
                                  ]
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(t),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setDialogState(() => type = v!),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: reasonController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Gerekçe (Opsiyonel)',
                            hintText: 'İzin nedenini kısaca açıklayın...',
                            fillColor: Colors.grey.shade50,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Date range card
                        _buildSectionTitle('Tarih Aralığı'),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              ListTile(
                                leading: Icon(
                                  Icons.calendar_today_outlined,
                                  color: Colors.blue,
                                  size: 18,
                                ),
                                title: const Text(
                                  'Başlangıç',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                                subtitle: Text(
                                  DateFormat(
                                    'd MMMM yyyy (EEEE)',
                                    'tr_TR',
                                  ).format(startDate),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.black87,
                                  ),
                                ),
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: startDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                    locale: const Locale('tr', 'TR'),
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      startDate = picked;
                                      endDate = startDate; // Sync end date
                                    });
                                  }
                                },
                              ),
                              const Divider(indent: 50, height: 1),
                              ListTile(
                                leading: Icon(
                                  Icons.event_outlined,
                                  color: Colors.orange,
                                  size: 18,
                                ),
                                title: const Text(
                                  'Bitiş',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                                subtitle: Text(
                                  DateFormat(
                                    'd MMMM yyyy (EEEE)',
                                    'tr_TR',
                                  ).format(endDate),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.black87,
                                  ),
                                ),
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: endDate,
                                    firstDate: startDate,
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                    locale: const Locale('tr', 'TR'),
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      endDate = picked;
                                      if (startDate.day != endDate.day ||
                                          startDate.month != endDate.month ||
                                          startDate.year != endDate.year) {
                                        isFullDay = true;
                                      }
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Hourly configuration if same day
                        if (startDate.day == endDate.day &&
                            startDate.month == endDate.month &&
                            startDate.year == endDate.year) ...[
                          _buildSectionTitle('Günlük/Saatlik Ayarı'),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              children: [
                                SwitchListTile(
                                  title: const Text(
                                    'Tam Gün İzin',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  value: isFullDay,
                                  activeColor: const Color(0xFF4F46E5),
                                  onChanged: (val) =>
                                      setDialogState(() => isFullDay = val),
                                ),
                                if (!isFullDay) ...[
                                  const Divider(height: 1),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.access_time,
                                      size: 18,
                                      color: Colors.indigo,
                                    ),
                                    title: const Text(
                                      'Başlangıç Saati',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    subtitle: Text(
                                      startTime.format(context),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onTap: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: startTime,
                                        builder: (context, child) =>
                                            Localizations.override(
                                              context: context,
                                              locale: const Locale('tr', 'TR'),
                                              child: child,
                                            ),
                                      );
                                      if (picked != null)
                                        setDialogState(
                                          () => startTime = picked,
                                        );
                                    },
                                  ),
                                  const Divider(indent: 50, height: 1),
                                  ListTile(
                                    leading: const Icon(
                                      Icons.access_time_filled,
                                      size: 18,
                                      color: Colors.indigo,
                                    ),
                                    title: const Text(
                                      'Bitiş Saati',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    subtitle: Text(
                                      endTime.format(context),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onTap: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: endTime,
                                        builder: (context, child) =>
                                            Localizations.override(
                                              context: context,
                                              locale: const Locale('tr', 'TR'),
                                              child: child,
                                            ),
                                      );
                                      if (picked != null)
                                        setDialogState(() => endTime = picked);
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
                // Footer Buttons
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('İptal'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            if (selectedUserId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Personel seçiniz'),
                                ),
                              );
                              return;
                            }
                            try {
                              setDialogState(() => _loading = true);
                              final startStr = isFullDay
                                  ? null
                                  : '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
                              final endStr = isFullDay
                                  ? null
                                  : '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';

                              final lessonConflicts = await _conflictService
                                  .checkLessonConflicts(
                                    institutionId: instId ?? '',
                                    teacherId: selectedUserId!,
                                    startDate: startDate,
                                    endDate: endDate,
                                    isFullDay: isFullDay,
                                    startTime: startStr,
                                    endTime: endStr,
                                  );
                              final dutyConflicts = await _conflictService
                                  .checkDutyConflicts(
                                    institutionId: instId ?? '',
                                    teacherId: selectedUserId!,
                                    startDate: startDate,
                                    endDate: endDate,
                                    isFullDay: isFullDay,
                                    startTime: startStr,
                                    endTime: endStr,
                                  );

                              await _service.requestLeave(
                                institutionId: instId ?? '',
                                userId: selectedUserId!,
                                startDate: startDate,
                                endDate: endDate,
                                type: type,
                                lessonConflicts: lessonConflicts.length,
                                dutyConflicts: dutyConflicts.length,
                                isFullDay: isFullDay,
                                startTime: startStr,
                                endTime: endStr,
                                reason: reasonController.text,
                              );
                              if (mounted) {
                                Navigator.pop(context);
                                _loadData();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Talep oluşturuldu'),
                                  ),
                                );
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Hata: $e')),
                              );
                            } finally {
                              setDialogState(() => _loading = false);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4F46E5),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Talep Oluştur',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 3,
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverAppBar(
                    expandedHeight: 120.0,
                    floating: false,
                    pinned: true,
                    backgroundColor: Colors.white,
                    elevation: 0,
                    title: Text(
                      'İzin Yönetimi',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF0F172A),
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    centerTitle: false,
                    iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
                    actions: [
                      IconButton(
                        icon: const Icon(
                          Icons.file_download,
                          color: Color(0xFF64748B),
                        ),
                        onPressed: _exportToExcel,
                        tooltip: 'Excel Dışarı Aktar',
                      ),
                      const SizedBox(width: 8),
                    ],
                    bottom: TabBar(
                      controller: _tabController,
                      labelColor: const Color(0xFF4F46E5),
                      unselectedLabelColor: const Color(0xFF94A3B8),
                      indicatorColor: const Color(0xFF4F46E5),
                      indicatorWeight: 3,
                      tabs: const [
                        Tab(text: 'Bekleyenler'),
                        Tab(text: 'Geçmiş'),
                        Tab(text: 'İstatistik'),
                      ],
                    ),
                  ),
                ],
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRequestList(_pendingRequests, isPending: true),
                    _buildRequestList(_historyRequests, isPending: false),
                    _buildAnalyticsView(),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showRequestDialog,
        backgroundColor: const Color(0xFF4F46E5),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Yeni İzin',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildRequestList(
    List<Map<String, dynamic>> requests, {
    required bool isPending,
  }) {
    final instId = widget.institutionId ?? _currentUserData?['institutionId'];
    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Kayıt bulunamadı.',
              style: GoogleFonts.poppins(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final req = requests[index];
        final start = (req['startDate'] as Timestamp).toDate();
        final end = (req['endDate'] as Timestamp).toDate();
        final duration = end.difference(start).inDays + 1;
        final bool isManager =
            _currentUserData?['role'] == 'admin' ||
            _currentUserData?['role'] == 'manager' ||
            _currentUserData?['role'] == 'genel_mudur' ||
            _currentUserData?['role'] == 'mudur' ||
            _currentUserData?['type'] == 'admin' ||
            _currentUserData?['type'] == 'manager';

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: InkWell(
            onTap: isManager && isPending
                ? () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LeaveApprovalScreen(
                          request: {
                            ...req,
                            'id': req['id'],
                            'staffName': _getStaffName(req['userId']),
                          },
                          institutionId: instId ?? '',
                        ),
                      ),
                    );
                    if (result == true) _loadData();
                  }
                : null,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getStaffName(req['userId']),
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              req['type'],
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildStatusChip(req['status']),
                      if (isManager && isPending)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          onPressed: () => _confirmDelete(req),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${DateFormat('d MMM yyyy', 'tr_TR').format(start)} - ${DateFormat('d MMM yyyy', 'tr_TR').format(end)}",
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: const Color(0xFF334155),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "$duration gün",
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF4F46E5),
                        ),
                      ),
                    ],
                  ),
                  if (req['reason'] != null && req['reason'].isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      req['reason'],
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: const Color(0xFF64748B),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  if (isPending && isManager) ...[
                    const SizedBox(height: 12),
                    _buildConflictAlert(req),
                  ],
                  if (!isPending) ...[
                    const SizedBox(height: 12),
                    Divider(color: Colors.grey.shade100, height: 1),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _generateIndividualPdf(req),
                        icon: const Icon(Icons.picture_as_pdf, size: 16),
                        label: const Text(
                          'Rapor Al',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(String status) {
    Color bg = _getStatusColor(status).withOpacity(0.1);
    Color text = _getStatusColor(status);
    String label = _getStatusText(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: text,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildConflictAlert(Map<String, dynamic> req) {
    // This will be updated after conflict check
    int lessonCount = req['lessonConflicts'] ?? 0;
    int dutyCount = req['dutyConflicts'] ?? 0;

    if (lessonCount == 0 && dutyCount == 0) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              'Çakışma tespit edilmedi.',
              style: TextStyle(fontSize: 12, color: Colors.green.shade700),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning, size: 16, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$lessonCount Ders, $dutyCount Nöbet çakışması var. Çözmek için dokunun.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'approved':
        return 'Onaylandı';
      case 'rejected':
        return 'Reddedildi';
      case 'lessons_assigned':
        return 'Ders Atandı';
      case 'duties_checked':
        return 'Nöbet Kontrolü';
      default:
        return 'Bekliyor';
    }
  }

  Widget _buildAnalyticsView() {
    Map<String, int> typeCounts = {};
    for (var r in [..._pendingRequests, ..._historyRequests]) {
      final type = r['type'] ?? 'Diğer';
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCards(),
          const SizedBox(height: 24),
          Text(
            'İzin Dağılımı',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),
          _buildTypePieChart(typeCounts),
          const SizedBox(height: 32),
          Text(
            'Kullanım İstatistikleri',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),
          _buildUsageBarChart(),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Bekleyen',
            _pendingRequests.length.toString(),
            Colors.orange,
            Icons.pending_actions,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            'Onaylanan',
            _historyRequests
                .where((r) => r['status'] == 'approved')
                .length
                .toString(),
            Colors.green,
            Icons.check_circle_outline,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
          ),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypePieChart(Map<String, int> data) {
    if (data.isEmpty) return const Center(child: Text('Veri bulunamadı'));

    final colors = [
      Colors.indigo,
      Colors.teal,
      Colors.orange,
      Colors.red,
      Colors.purple,
    ];
    int colorIndex = 0;

    return Container(
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: PieChart(
        PieChartData(
          sections: data.entries.map((e) {
            final color = colors[colorIndex % colors.length];
            colorIndex++;
            return PieChartSectionData(
              value: e.value.toDouble(),
              title:
                  '${e.key}\n%${(e.value / data.values.reduce((a, b) => a + b) * 100).toStringAsFixed(0)}',
              color: color,
              radius: 70,
              titleStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildUsageBarChart() {
    Map<String, int> userCounts = {};
    for (var r in _historyRequests) {
      if (r['status'] == 'approved') {
        userCounts[r['userId']] = (userCounts[r['userId']] ?? 0) + 1;
      }
    }

    final sorted = userCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sorted.take(5).toList();

    if (top5.isEmpty) return const Center(child: Text('Veri bulunamadı'));

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: BarChart(
        BarChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() < top5.length) {
                    final name = _getStaffName(
                      top5[value.toInt()].key,
                    ).split(' ').first;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
          ),
          barGroups: top5.asMap().entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value.value.toDouble(),
                  color: Colors.white,
                  width: 25,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: top5.first.value.toDouble() + 1,
                    color: Colors.white.withOpacity(0.2),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _exportToExcel() async {
    try {
      var excel = ex.Excel.createExcel();
      var sheet = excel['İzin Listesi'];

      sheet.appendRow([
        ex.TextCellValue('Personel'),
        ex.TextCellValue('Tür'),
        ex.TextCellValue('Başlangıç'),
        ex.TextCellValue('Bitiş'),
        ex.TextCellValue('Durum'),
        ex.TextCellValue('Açıklama'),
      ]);

      for (var r in [..._pendingRequests, ..._historyRequests]) {
        sheet.appendRow([
          ex.TextCellValue(_getStaffName(r['userId'])),
          ex.TextCellValue(r['type']),
          ex.TextCellValue(
            DateFormat(
              'dd.MM.yyyy',
              'tr_TR',
            ).format((r['startDate'] as Timestamp).toDate()),
          ),
          ex.TextCellValue(
            DateFormat(
              'dd.MM.yyyy',
              'tr_TR',
            ).format((r['endDate'] as Timestamp).toDate()),
          ),
          ex.TextCellValue(_getStatusText(r['status'])),
          ex.TextCellValue(r['reason'] ?? ''),
        ]);
      }

      final directory = await getApplicationDocumentsDirectory();
      final file = File(
        '${directory.path}/izin_listesi_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
      await file.writeAsBytes(excel.save()!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel kaydedildi: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Excel hatası: $e')));
      }
    }
  }

  Future<void> _generateIndividualPdf(Map<String, dynamic> req) async {
    // This part can be implemented in PdfService later
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('PDF Raporu hazırlanıyor...')));
  }

  String _getDisplayName(Map<String, dynamic> data) {
    if (data['name'] != null && data['name'].toString().isNotEmpty) {
      return data['name'];
    }
    if (data['fullName'] != null && data['fullName'].toString().isNotEmpty) {
      return data['fullName'];
    }
    final first = data['firstName'] ?? '';
    final last = data['lastName'] ?? '';
    if (first.isNotEmpty || last.isNotEmpty) {
      return '${first} ${last}'.trim();
    }
    return 'İsimsiz Personel';
  }

  String _getStaffName(String? id) {
    if (id == null) return 'Bilinmeyen';
    final staff = _allStaff.firstWhere((s) => s['id'] == id, orElse: () => {});
    if (staff.isEmpty) return 'Bilinmeyen';
    return _getDisplayName(staff);
  }

  void _showPersonnelSelectionSheet(
    StateSetter setDialogState,
    Function(String) onSelect,
  ) {
    String search = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = _allStaff.where((s) {
            final name = _getDisplayName(s).toLowerCase();
            return name.contains(search.toLowerCase());
          }).toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Personel Seçin',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'İsim ile ara...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setSheetState(() => search = v),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final s = filtered[index];
                      final name = _getDisplayName(s);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade50,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.indigo),
                          ),
                        ),
                        title: Text(name),
                        subtitle: Text(s['branch'] ?? 'Branş Belirtilmemiş'),
                        onTap: () {
                          setDialogState(() {
                            onSelect(s['id']);
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Talebi Sil'),
        content: const Text(
          'Bu izin talebi tamamen silinecektir. Emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.deleteLeave(req['id']);
      _loadData();
    }
  }
}
