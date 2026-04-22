import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as ex;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../services/leave_service.dart';

class LeaveManagementScreen extends StatefulWidget {
  final String? institutionId;
  final bool isTeacherMode;
  final String? forceUserId;

  const LeaveManagementScreen({
    super.key,
    this.institutionId,
    this.isTeacherMode = false,
    this.forceUserId,
  });

  @override
  State<LeaveManagementScreen> createState() => _LeaveManagementScreenState();
}

class _LeaveManagementScreenState extends State<LeaveManagementScreen> with TickerProviderStateMixin {
  final LeaveService _service = LeaveService();
  TabController? _tabController;
  
  String? _myInstitutionId;
  String? _myUserId;
  String _myRole = 'staff';
  bool _isLoading = true;
  DateTime _calendarMonth = DateTime.now();

  List<Map<String, dynamic>> _myRequests = [];
  List<Map<String, dynamic>> _allRequests = [];
  Map<String, dynamic>? _myBalance;
  List<Map<String, dynamic>> _allStaff = [];

  bool _hasError = false;
  String _errorMessage = '';
  String _statusFilter = 'Hepsi';
  String _deptFilter = 'T├╝m Departmanlar';
  String _schoolFilter = 'T├╝m Okullar';
  String _searchQuery = '';
  bool _showFilters = false;
  String? _selectedCalendarStaffId;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Oturum a├ğ─▒lmad─▒.';
        });
        return;
      }
      _myUserId = widget.forceUserId ?? user.uid;

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(_myUserId).get().timeout(const Duration(seconds: 10));
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        _myInstitutionId = widget.institutionId ?? userData['institutionId'];
        if (widget.isTeacherMode) {
          _myRole = 'teacher';
        } else {
          _myRole = (userData['role'] ?? 'staff').toString().toLowerCase();
        }
      }

      if (mounted) {
        final bool isAdmin = _isAdminRole(_myRole);
        _tabController = TabController(length: isAdmin ? 4 : 2, vsync: this);
        _tabController!.addListener(_onTabChanged);
      }

      await _loadData().timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Error initializing LeaveManagementScreen: $e');
      setState(() {
        _hasError = true;
        _errorMessage = 'Y├╝kleme s─▒ras─▒nda bir hata olu┼ştu: $e';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isAdminRole(String role) {
    return role == 'admin' || role == 'manager' || role == 'hr' || role.contains('mudur') || role.contains('m├╝d├╝r');
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_myInstitutionId == null) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final requests = await _service.getLeaveRequests(institutionId: _myInstitutionId!);
      
      if (_allStaff.isEmpty) {
        final staffDocs = await FirebaseFirestore.instance.collection('users').where('institutionId', isEqualTo: _myInstitutionId!).get();
        _allStaff = staffDocs.docs.map((d) {
          final data = d.data();
          String dept = data['department'] ?? data['departmentName'] ?? 'Genel';
          String roleStr = (data['role'] ?? 'Personel').toString();
          if (roleStr.toLowerCase().contains('teacher') || roleStr.toLowerCase().contains('ogretmen')) roleStr = '├û─şretmen';
          else if (roleStr.toLowerCase().contains('mudur') || roleStr.toLowerCase().contains('admin')) roleStr = 'M├╝d├╝r/Y├Ânetici';

          // Smart School Type Detection
          String school = '';
          if (data['schoolTypeName'] != null && data['schoolTypeName'].toString().isNotEmpty) {
            school = data['schoolTypeName'];
          } else if (data['workLocations'] is List && (data['workLocations'] as List).isNotEmpty) {
            school = (data['workLocations'] as List).first.toString();
          } else if (data['schoolType'] != null && data['schoolType'].toString().isNotEmpty) {
            school = data['schoolType'];
          } else if (data['school'] != null && data['school'].toString().isNotEmpty) {
            school = data['school'];
          }
          
          if (school == 'Belirtilmemi┼ş') school = '';
          
          return {
            'id': d.id, 
            'name': data['fullName'] ?? data['name'] ?? '─░simsiz',
            'role': roleStr,
            'department': dept,
            'schoolType': school,
          };
        }).toList();
      }

      final balance = await _service.getLeaveBalance(_myUserId!, _myInstitutionId!);

      if (mounted) {
        setState(() {
          _allRequests = requests;
          _myRequests = requests.where((r) => (r['staffId'] ?? r['userId']) == _myUserId).toList();
          _myBalance = balance;
        });
      }
    } catch (e) {
      print('Error loading leave data: $e');
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return '?';
    if (date is Timestamp) {
      return DateFormat('dd/MM/yyyy').format(date.toDate());
    }
    if (date is String) {
      if (date.contains('-') && date.length >= 10) {
        try {
          final parsed = DateTime.parse(date.substring(0, 10));
          return DateFormat('dd/MM/yyyy').format(parsed);
        } catch (_) {}
      }
      return date;
    }
    return date.toString();
  }

  int _calculateDays(dynamic start, dynamic end) {
    try {
      DateTime s;
      DateTime e;
      if (start is Timestamp) s = start.toDate();
      else s = DateTime.parse(start.toString().substring(0, 10));
      
      if (end is Timestamp) e = end.toDate();
      else e = DateTime.parse(end.toString().substring(0, 10));
      
      s = DateTime(s.year, s.month, s.day);
      e = DateTime(e.year, e.month, e.day);
      
      return e.difference(s).inDays + 1;
    } catch (_) {
      return 0;
    }
  }

  String _toIsoDate(dynamic d) {
    if (d == null) return '';
    try {
      if (d is Timestamp) return DateFormat('yyyy-MM-dd').format(d.toDate());
      if (d is String) {
        if (d.contains('/')) {
          final parts = d.split('/');
          if (parts.length == 3) {
            final day = parts[0].padLeft(2, '0');
            final mon = parts[1].padLeft(2, '0');
            return '${parts[2]}-$mon-$day';
          }
        }
        return d.substring(0, 10);
      }
      return '';
    } catch (_) { return ''; }
  }

  String _getStaffName(String? id) {
    if (id == null) return 'Bilinmeyen Personel';
    if (id == _myUserId) return 'Ben';
    final s = _allStaff.firstWhere((s) => s['id'] == id, orElse: () => {'name': 'Bilinmeyen ($id)'});
    return s['name'];
  }

  Map<String, dynamic>? _getStaffInfo(String? id) {
    if (id == null) return null;
    final results = _allStaff.where((s) => s['id'] == id).toList();
    return results.isEmpty ? null : results.first;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    if (_hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('─░zin Y├Ânetimi')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _initialize, child: const Text('Tekrar Dene')),
            ],
          ),
        ),
      );
    }

    final isAdmin = _isAdminRole(_myRole);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('─░zin Y├Ânetimi', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          if (isAdmin) IconButton(onPressed: _exportToExcel, icon: const Icon(Icons.file_download_outlined, color: Colors.green)),
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded)),
        ],
        bottom: _tabController == null ? null : TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF6366F1),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF6366F1),
          indicatorWeight: 3,
          isScrollable: false,
          tabs: [
            const Tab(text: '─░zinlerim'),
            const Tab(text: 'Bakiye'),
            if (isAdmin) const Tab(text: 'Talep Listesi'),
            if (isAdmin) const Tab(text: 'Takvim'),
          ],
        ),
      ),
      body: _tabController == null ? const Center(child: CircularProgressIndicator()) : Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildMyRequestsTab(),
              _buildBalanceTab(),
              if (isAdmin) _buildApprovalTab(),
              if (isAdmin) _buildCalendarTab(),
            ],
          ),
        ),
      ),
      floatingActionButton: _tabController?.index != 0 ? null : FloatingActionButton.extended(
        onPressed: _showRequestDialog,
        elevation: 4,
        highlightElevation: 8,
        backgroundColor: const Color(0xFF6366F1),
        icon: const Icon(Icons.add_task_rounded, color: Colors.white, size: 24),
        label: Text(_isAdminRole(_myRole) ? 'PERSONEL ─░ZN─░ OLU┼ŞTUR' : 'YEN─░ ─░Z─░N TALEB─░', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
      ),
    );
  }

  Future<void> _printReport() async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(now);
    
    // Turkish Font Support
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    
    // Preparation: Data grouping
    final List<Map<String, dynamic>> reportRequests = _statusFilter == 'Hepsi' ? _allRequests : _allRequests.where((r) => r['status'] == _statusFilter.toLowerCase().replaceAll('bekliyor', 'pending').replaceAll('onayland─▒', 'approved').replaceAll('reddedildi', 'rejected')).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('─░zin Y├Ânetimi Genel Raporu', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: boldFont)),
                    pw.Text('Kurum ID: $_myInstitutionId', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey, font: font)),
                  ],
                ),
                pw.Text(dateStr, style: pw.TextStyle(fontSize: 10, font: font)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text('A├ğ─▒klama: Bu rapor, sistemde kay─▒tl─▒ olan personel izin taleplerini ve mevcut durumlar─▒n─▒ ├Âzetlemektedir.', style: pw.TextStyle(fontSize: 11, font: font)),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, font: boldFont),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
            cellAlignment: pw.Alignment.centerLeft,
            headers: ['Personel', 'T├╝r', 'Ba┼şlang─▒├ğ', 'Biti┼ş', 'G├╝n', 'Durum'],
            data: reportRequests.map((r) {
              final d1 = r['startDate'];
              final d2 = r['endDate'];
              final days = _calculateDays(d1, d2).toString();
              return [
                _getStaffName(r['staffId'] ?? r['userId']),
                r['leaveType'] ?? '─░zin',
                _formatDate(d1),
                _formatDate(d2),
                days,
                (r['status'] == 'approved' ? 'Onayland─▒' : (r['status'] == 'rejected' ? 'Reddedildi' : 'Bekliyor')),
              ];
            }).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  Future<void> _printIndividualReport(Map<String, dynamic> balance) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Bireysel ─░zin Durum Raporu', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, font: boldFont)),
                    pw.Text('Personel: ${_getStaffName(_myUserId)}', style: pw.TextStyle(fontSize: 12, font: font)),
                  ],
                ),
                pw.Text(DateFormat('dd/MM/yyyy').format(now), style: pw.TextStyle(font: font)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildPdfStatCard('Toplam Hak', (balance['total'] ?? 0).toString(), font, boldFont),
              _buildPdfStatCard('Kullan─▒lan', (balance['used'] ?? 0).toString(), font, boldFont),
              _buildPdfStatCard('Kalan', (balance['remaining'] ?? 0).toString(), font, boldFont),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.Text('─░zin Ge├ğmi┼şi', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, font: boldFont)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: boldFont),
            headers: ['T├╝r', 'Tarihler', 'G├╝n', 'Durum'],
            data: _myRequests.map((r) {
              final days = (r['totalDays'] != null && (r['totalDays'] as num) > 0) ? r['totalDays'].toString() : _calculateDays(r['startDate'], r['endDate']).toString();
              return [
                r['leaveType'] ?? '─░zin',
                '${_formatDate(r['startDate'])} - ${_formatDate(r['endDate'])}',
                days,
                (r['status'] == 'approved' ? 'Onayland─▒' : (r['status'] == 'rejected' ? 'Reddedildi' : 'Bekliyor')),
              ];
            }).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  pw.Widget _buildPdfStatCard(String label, String value, pw.Font font, pw.Font boldFont) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
      child: pw.Column(
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700, font: font)),
          pw.Text(value, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: boldFont)),
        ],
      ),
    );
  }

  Widget _buildMyRequestsTab() {
    if (_myRequests.isEmpty) return _buildEmptyState('Hen├╝z bir izin talebiniz bulunmuyor.');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _myRequests.length,
      itemBuilder: (context, index) => _buildLeaveCard(_myRequests[index]),
    );
  }

  Widget _buildBalanceTab() {
    if (_myBalance == null) return const Center(child: CircularProgressIndicator());
    final b = _myBalance!;
    final bool isTeacher = b['isTeacher'] ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (isTeacher)
            _buildInfoCard('├û─şretmen ─░stisnas─▒', '├û─şretmenler yaz tatilinde izinli say─▒ld─▒─ş─▒ i├ğin manuel y─▒ll─▒k izin bakiyesi tan─▒mlanmaz.', Icons.school_outlined)
          else ...[
            _buildBalanceHeader(b['remaining'].toInt(), b['total'].toInt()),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: _buildBalanceDetailRow('K─▒dem S├╝resi', '${b['tenureYears']} Y─▒l', Icons.work_outline)),
              const SizedBox(width: 12),
              Expanded(child: _buildBalanceDetailRow('Kullan─▒lan', '${b['used']} G├╝n', Icons.event_busy)),
            ]),
            const SizedBox(height: 12),
            _buildBalanceDetailRow('Y─▒ll─▒k ─░zin Hakk─▒', '${b['total']} G├╝n', Icons.event_available),
          ],
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('─░zin Hareketleri', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              IconButton(
                onPressed: () => _printIndividualReport(b),
                icon: const Icon(Icons.print_outlined, color: Colors.indigo),
                tooltip: 'Bireysel Rapor Yazd─▒r',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_myRequests.isEmpty) 
            const Text('Hen├╝z bir izin kayd─▒ bulunmuyor.', style: TextStyle(color: Colors.grey, fontSize: 13))
          else 
            ..._myRequests.map((r) => _buildLeaveCard(r)).toList(),
          const SizedBox(height: 30),
          if (!isTeacher) _buildSimplePolicyTable(),
        ],
      ),
    );
  }

  Widget _buildApprovalTab() {
    final filtered = _allRequests.where((r) {
      final s = r['status']?.toString().toLowerCase() ?? 'pending';
      final staffInfo = _getStaffInfo(r['staffId'] ?? r['userId']);
      final staffName = _getStaffName(r['staffId'] ?? r['userId']).toLowerCase();
      
      // Search Filter
      if (_searchQuery.isNotEmpty && !staffName.contains(_searchQuery.toLowerCase())) return false;

      // Status Filter
      bool matchStatus = _statusFilter == 'Hepsi';
      if (!matchStatus) {
        final f = _statusFilter.toLowerCase().replaceAll('bekliyor', 'pending').replaceAll('onayland─▒', 'approved').replaceAll('reddedildi', 'rejected');
        matchStatus = (s == f);
      }
      
      // Dept Filter
      bool matchDept = _deptFilter == 'T├╝m Departmanlar' || (staffInfo != null && staffInfo['department'] == _deptFilter);
      
      // School Filter
      bool matchSchool = _schoolFilter == 'T├╝m Okullar' || (staffInfo != null && staffInfo['schoolType'] == _schoolFilter);
      
      return matchStatus && matchDept && matchSchool;
    }).toList();
    
    if (_allRequests.isEmpty) return _buildEmptyState('Hen├╝z talep bulunmuyor.');
    return Column(
      children: [
        _buildAdvancedFilterBar(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final r = filtered[index];
              return _buildLeaveCard(r, canAction: r['status'] == 'pending', showStaffName: true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedFilterBar() {
    final depts = ['T├╝m Departmanlar', ..._allStaff.map((s) => s['department'] as String).toSet()];
    final schools = ['T├╝m Okullar', ..._allStaff.map((s) => s['schoolType'] as String).where((s) => s.isNotEmpty).toSet()];

    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Personel ara...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      isDense: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => setState(() => _showFilters = !_showFilters),
                  icon: Icon(_showFilters ? Icons.filter_list_off_rounded : Icons.filter_list_rounded, color: _showFilters ? const Color(0xFF6366F1) : Colors.grey),
                  tooltip: 'Filtreleri G├Âster/Gizle',
                ),
                IconButton(
                  onPressed: _printReport,
                  icon: const Icon(Icons.print_rounded, color: Colors.blue),
                  tooltip: 'Rapor Yazd─▒r',
                ),
              ],
            ),
          ),
          if (_showFilters) ...[
            _buildStatusFilterBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade100)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _deptFilter,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                          items: depts.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (v) => setState(() => _deptFilter = v!),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade100)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _schoolFilter,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                          items: schools.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (v) => setState(() => _schoolFilter = v!),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusFilterBar() {
    final filters = ['Hepsi', 'Bekliyor', 'Onayland─▒', 'Reddedildi'];
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (ctx, i) {
          final f = filters[i];
          final isSel = _statusFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f, style: TextStyle(color: isSel ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 13)),
              selected: isSel,
              onSelected: (v) => setState(() => _statusFilter = f),
              selectedColor: const Color(0xFF6366F1),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12), 
                side: BorderSide(color: isSel ? Colors.transparent : Colors.grey.shade200)
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalendarTab() {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => _StaffPicker(
                        staff: _allStaff,
                        selectedIds: _selectedCalendarStaffId != null ? [_selectedCalendarStaffId!] : [],
                        onSelected: (ids) {
                          setState(() => _selectedCalendarStaffId = ids.isEmpty ? null : ids.first);
                        },
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50, 
                      borderRadius: BorderRadius.circular(12), 
                      border: Border.all(color: Colors.grey.shade200)
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_search_rounded, color: Colors.indigo),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_selectedCalendarStaffId == null ? 'B├£T├£N PERSONEL TAKV─░M─░' : _getStaffName(_selectedCalendarStaffId), style: const TextStyle(fontWeight: FontWeight.bold))),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
              ),
              _buildCalendarHeader(),
              _buildCalendarGrid(),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(onPressed: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1)), icon: const Icon(Icons.chevron_left)),
          Text(DateFormat('MMMM yyyy', 'tr_TR').format(_calendarMonth), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          IconButton(onPressed: () => setState(() => _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1)), icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final lastDay = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0);
    final daysInMonth = lastDay.day;
    final firstWeekday = firstDay.weekday;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.8),
      itemCount: daysInMonth + (firstWeekday - 1),
      itemBuilder: (ctx, idx) {
        if (idx < firstWeekday - 1) return const SizedBox.shrink();
        final day = idx - (firstWeekday - 2);
        final date = DateTime(_calendarMonth.year, _calendarMonth.month, day);
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        
        final leavesOnDay = _allRequests.where((r) {
          final sDStr = _toIsoDate(r['startDate']);
          final eDStr = _toIsoDate(r['endDate']);
          
          final isMatch = r['status'] == 'approved' && sDStr.isNotEmpty && eDStr.isNotEmpty && sDStr.compareTo(dateStr) <= 0 && eDStr.compareTo(dateStr) >= 0;
          if (_selectedCalendarStaffId != null) {
            return isMatch && (r['staffId'] ?? r['userId']) == _selectedCalendarStaffId;
          }
          return isMatch;
        }).toList();

        return Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade100), borderRadius: BorderRadius.circular(8)),
          child: Column(
            children: [
              Padding(padding: const EdgeInsets.all(4), child: Text('$day', style: TextStyle(fontWeight: FontWeight.bold, color: date.weekday > 5 ? Colors.red.shade300 : Colors.black87))),
              Expanded(child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: leavesOnDay.length > 2 ? 2 : leavesOnDay.length,
                itemBuilder: (c, i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(_getStaffName(leavesOnDay[i]['staffId'] ?? leavesOnDay[i]['userId']).split(' ')[0], style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF6366F1)), overflow: TextOverflow.ellipsis),
                ),
              )),
              if (leavesOnDay.length > 2) Text('+${leavesOnDay.length - 2}', style: const TextStyle(fontSize: 8, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeaveCard(Map<String, dynamic> req, {bool canAction = false, bool showStaffName = false}) {
    final status = req['status'] ?? 'pending';
    Color statusColor = Colors.orange;
    String statusText = 'Bekliyor';
    if (status == 'approved') {
      statusColor = Colors.green;
      statusText = 'Onayland─▒';
    } else if (status == 'rejected') {
      statusColor = Colors.red;
      statusText = 'Reddedildi';
    }

    final leaveType = (req['leaveType'] ?? req['type'] ?? 'Genel ─░zin').toString();
    final startDateFormatted = _formatDate(req['startDate']);
    final endDateFormatted = _formatDate(req['endDate']);
    
    int totalDays = (req['totalDays'] ?? 0).toInt();
    if (totalDays <= 0) {
      totalDays = _calculateDays(req['startDate'], req['endDate']);
    }
    
    final note = (req['note'] ?? req['reason'] ?? '').toString();
    final staffInfo = showStaffName ? _getStaffInfo(req['staffId'] ?? req['userId']) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text(statusText.toUpperCase(), style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
                Text(leaveType, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF6366F1), fontSize: 11)),
              ],
            ),
            const SizedBox(height: 14),
            if (showStaffName) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_getStaffName(req['staffId'] ?? req['userId']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF1E293B))),
                        if (staffInfo != null) 
                          Text('${staffInfo['role']}${staffInfo['department'].isNotEmpty ? ' ÔÇó ${staffInfo['department']}' : ''}${staffInfo['schoolType'].isNotEmpty ? ' ÔÇó ${staffInfo['schoolType']}' : ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.event_note_rounded, size: 20, color: Color(0xFF6366F1)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('─░Z─░N D├ûNEM─░', style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      Text('$startDateFormatted ÔÇö $endDateFormatted', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF334155))),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [const Color(0xFF6366F1).withOpacity(0.8), const Color(0xFF6366F1)]), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.2), blurRadius: 8)]),
                  child: Text('$totalDays G├£N', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white)),
                ),
              ],
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF1F5F9))),
                child: Text(note, style: const TextStyle(color: Color(0xFF475569), fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)),
              ),
            ],
            if (canAction) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => _updateStatus(req['id'], 'rejected'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red, 
                        padding: const EdgeInsets.symmetric(vertical: 14), 
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12), 
                          side: const BorderSide(color: Color(0xFFFFE4E6))
                        )
                      ),
                      child: const Text('REDDET', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _updateStatus(req['id'], 'approved'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('ONAYLA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceHeader(int remaining, int total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        children: [
          const Text('Kalan Y─▒ll─▒k ─░zin Hakk─▒', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text('$remaining', style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w900, height: 1)),
          const SizedBox(height: 8),
          Text('G├£N / TOPLAM $total', style: const TextStyle(color: Colors.white60, fontSize: 13, letterSpacing: 1, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBalanceDetailRow(String label, String value, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: const Color(0xFF6366F1), size: 18),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1E293B), fontSize: 16)),
      ]),
    );
  }

  Widget _buildSimplePolicyTable() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Y─▒ll─▒k ─░zin Politikas─▒', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
        const SizedBox(height: 16),
        _policyRow('0 ÔÇô 5 Y─▒l', '14 G├╝n'),
        const Divider(),
        _policyRow('5 ÔÇô 10 Y─▒l', '21 G├╝n'),
        const Divider(),
        _policyRow('10+ Y─▒l', '26 G├╝n'),
      ]),
    );
  }

  Widget _policyRow(String label, String val) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: Colors.grey)), Text(val, style: const TextStyle(fontWeight: FontWeight.bold))]));
  }

  Widget _buildInfoCard(String title, String msg, IconData icon) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.blue.shade100)), child: Row(children: [Icon(icon, color: Colors.blue.shade700, size: 28), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)), const SizedBox(height: 4), Text(msg, style: TextStyle(color: Colors.blue.shade800, fontSize: 13))]))]));
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.layers_clear_outlined, size: 64, color: Colors.grey), const SizedBox(height: 16), Text(msg, style: const TextStyle(color: Colors.grey))]));
  }

  Future<void> _updateStatus(String id, String status) async {
    final noteController = TextEditingController();
    final bool confirmed = await showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(status == 'approved' ? '─░zni Onayla' : '─░zni Reddet'), content: TextField(controller: noteController, decoration: const InputDecoration(hintText: 'Yorumunuz (Opsiyonel)')), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('VAZGE├ç')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(status == 'approved' ? 'ONAYLA' : 'REDDET', style: TextStyle(color: status == 'approved' ? Colors.green : Colors.red)))])) ?? false;
    if (confirmed) { await _service.updateLeaveStatus(leaveId: id, status: status, managerNote: noteController.text); _loadData(); }
  }

  Future<void> _exportToExcel() async {
    var excel = ex.Excel.createExcel();
    var sheet = excel['─░zin Raporu'];
    sheet.appendRow([ex.TextCellValue('Personel'), ex.TextCellValue('T├╝r'), ex.TextCellValue('Ba┼şlang─▒├ğ'), ex.TextCellValue('Biti┼ş'), ex.TextCellValue('G├╝n'), ex.TextCellValue('Durum')]);
    for (var r in _allRequests) {
      sheet.appendRow([ex.TextCellValue(_getStaffName(r['staffId'] ?? r['userId'])), ex.TextCellValue(r['leaveType'] ?? r['type'] ?? '─░zin'), ex.TextCellValue(_formatDate(r['startDate'])), ex.TextCellValue(_formatDate(r['endDate'])), ex.IntCellValue((r['totalDays'] ?? 0).toInt()), ex.TextCellValue(r['status'] ?? 'pending')]);
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/izin_raporu_${_myInstitutionId}.xlsx');
    await file.writeAsBytes(excel.save()!);
    Share.shareXFiles([XFile(file.path)], text: '─░zin Y├Ânetimi Raporu');
  }

  Future<void> _showRequestDialog() async {
    String selectedType = 'Y─▒ll─▒k ─░zin';
    final isAdmin = _isAdminRole(_myRole);
    List<String> selectedStaffIds = isAdmin ? [] : [_myUserId!];
    DateTime start = DateTime.now();
    DateTime end = DateTime.now();
    final noteController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 24, right: 24, top: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Text(isAdmin ? 'Personel ─░zni Olu┼ştur' : 'Yeni ─░zin Talebi', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
                const SizedBox(height: 24),
                
                if (isAdmin) ...[
                  const Text('─░zinli Personel(ler)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (pickerCtx) => _StaffPicker(
                          staff: _allStaff,
                          selectedIds: selectedStaffIds,
                          onSelected: (ids) => setModalState(() => selectedStaffIds = ids),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
                      child: Row(children: [
                        const Icon(Icons.group_outlined, color: Color(0xFF6366F1), size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(selectedStaffIds.isEmpty ? 'Personel Se├ğiniz' : (selectedStaffIds.length == 1 ? _getStaffName(selectedStaffIds.first) : '${selectedStaffIds.length} Personel Se├ğildi'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: selectedStaffIds.isEmpty ? Colors.grey : Colors.black))),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                const Text('─░zin Detaylar─▒', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: InputDecoration(labelText: '─░zin T├╝r├╝', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
                  items: ['Y─▒ll─▒k ─░zin', 'Hastal─▒k ─░zni', 'Mazeret ─░zni', '├£cretsiz ─░zin'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setModalState(() => selectedType = v!),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: InkWell(onTap: () async { final picked = await showDatePicker(context: ctx, initialDate: start, firstDate: DateTime.now().subtract(const Duration(days: 90)), lastDate: DateTime.now().add(const Duration(days: 365))); if (picked != null) setModalState(() { start = picked; if (end.isBefore(start)) end = start; }); }, child: InputDecorator(decoration: InputDecoration(labelText: 'Ba┼şlang─▒├ğ', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)), child: Text(DateFormat('dd MMMM yyyy', 'tr_TR').format(start), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))))),
                  const SizedBox(width: 12),
                  Expanded(child: InkWell(onTap: () async { final picked = await showDatePicker(context: ctx, initialDate: end, firstDate: start, lastDate: DateTime.now().add(const Duration(days: 365))); if (picked != null) setModalState(() => end = picked); }, child: InputDecorator(decoration: InputDecoration(labelText: 'Biti┼ş', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)), child: Text(DateFormat('dd MMMM yyyy', 'tr_TR').format(end), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))))),
                ]),
                const SizedBox(height: 16),
                TextField(controller: noteController, maxLines: 3, decoration: InputDecoration(labelText: 'A├ğ─▒klama / Sebep', hintText: 'Durumu k─▒saca belirtiniz...', filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
                const SizedBox(height: 32),
                SizedBox(width: double.infinity, height: 60, child: ElevatedButton(
                  onPressed: selectedStaffIds.isEmpty ? null : () async {
                    for (var id in selectedStaffIds) {
                      await _service.requestLeave(staffId: id, institutionId: _myInstitutionId!, leaveType: selectedType, startDate: start, endDate: end, note: noteController.text, role: _myRole);
                    }
                    Navigator.pop(ctx);
                    _loadData();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 0),
                  child: Text(isAdmin ? 'PERSONEL ─░ZN─░N─░ KAYDET' : 'TALEB─░ G├ûNDER', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),
                )),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StaffPicker extends StatefulWidget {
  final List<Map<String, dynamic>> staff;
  final List<String> selectedIds;
  final Function(List<String>) onSelected;
  const _StaffPicker({required this.staff, required this.selectedIds, required this.onSelected});

  @override State<_StaffPicker> createState() => _StaffPickerState();
}

class _StaffPickerState extends State<_StaffPicker> {
  String _search = '';
  String _activeCategory = 'Hepsi';
  late List<String> _tempSelected;

  @override void initState() {
    super.initState();
    _tempSelected = List.from(widget.selectedIds);
  }

  @override Widget build(BuildContext context) {
    final categories = ['Hepsi', '├û─şretmen', 'M├╝d├╝r/Y├Ânetici', ...{...widget.staff.map((s) => s['department'] as String)}];
    final filtered = widget.staff.where((s) {
      final nameCheck = (s['name'] ?? '').toLowerCase().contains(_search.toLowerCase());
      final catCheck = _activeCategory == 'Hepsi' || s['role'] == _activeCategory || s['department'] == _activeCategory;
      return nameCheck && catCheck;
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Personel Se├ğ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
          TextButton(onPressed: () { widget.onSelected(_tempSelected); Navigator.pop(context); }, child: const Text('Tamamla', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF6366F1)))),
        ])),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: TextField(
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(hintText: 'Personel ara...', prefixIcon: const Icon(Icons.search_rounded), filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)),
        )),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: categories.length,
            itemBuilder: (ctx, i) {
              final c = categories[i];
              final isSel = _activeCategory == c;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c, style: TextStyle(fontSize: 12, color: isSel ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                  selected: isSel,
                  onSelected: (v) => setState(() => _activeCategory = c),
                  selectedColor: const Color(0xFF6366F1),
                  backgroundColor: Colors.grey.shade100,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide.none),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (ctx, i) {
            final s = filtered[i];
            final isSel = _tempSelected.contains(s['id']);
            return CheckboxListTile(
              value: isSel,
              onChanged: (v) => setState(() { v! ? _tempSelected.add(s['id']) : _tempSelected.remove(s['id']); }),
              activeColor: const Color(0xFF6366F1),
              checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              title: Text(s['name'] ?? '...', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              subtitle: Text('${s['role']} ÔÇó ${s['department']} ÔÇó ${s['schoolType']}', style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            );
          },
        )),
      ]),
    );
  }
}
