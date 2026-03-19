import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../services/payroll_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PayrollScreen extends StatefulWidget {
  static const routeName = '/hr/payroll';
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PayrollService _service = PayrollService();
  
  String? _myInstitutionId;
  bool _isLoading = true;
  
  // Filters & State
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _staffList = [];
  List<Map<String, dynamic>> _payrollList = [];
  Map<String, Map<String, dynamic>> _salaryDefinitions = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.email != null) {
        final email = user.email!;
        if (email.contains('@')) {
           _myInstitutionId = email.split('@')[1].split('.')[0].toUpperCase();
           await _loadData();
        }
      }
    } catch (e) {
      debugPrint('Payroll initialization error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadData() async {
    if (_myInstitutionId == null) return;
    
    try {
      // Load ALL Users for this institution to ensure we get all staff roles
      final usersSnap = await FirebaseFirestore.instance.collection('users')
          .where('institutionId', isEqualTo: _myInstitutionId)
          .get();
          
      _staffList = usersSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).where((u) {
        // Filter out non-staff roles
        final role = (u['role'] ?? '').toString().toLowerCase();
        final type = (u['type'] ?? '').toString().toLowerCase();
        return role != 'öğrenci' && role != 'veli' && (type == 'staff' || type == 'personel' || role != '');
      }).toList();

      // Load Salary Definitions
      final salaries = await _service.getAllSalaries(_myInstitutionId!);
      _salaryDefinitions = { for (var s in salaries) s['staffId']: s };

      // Load Payrolls for selected month
      _payrollList = await _service.getPayrolls(
        institutionId: _myInstitutionId!,
        month: _selectedDate.month,
        year: _selectedDate.year,
      );
      
      // Client-side sort
      _payrollList.sort((a, b) {
        final dateA = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        final dateB = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        return dateB.compareTo(dateA);
      });
      
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Data loading error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veri yüklenirken bir hata oluştu: $e'))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Maaş ve Bordro Yönetimi', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Bordrolar'),
            Tab(text: 'Maaş Tanımları'),
            Tab(text: 'Bordro Oluştur'),
            Tab(text: 'Raporlar'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPayrollListTab(),
              _buildSalaryDefinitionsTab(),
              _buildGenerateTab(),
              _buildReportsTab(),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2).format(amount);
  }

  // --- TAB 2: SALARY DEFINITIONS ---

  String _searchQuery = '';
  String? _depFilter;
  String? _schoolTypeFilter;

  Widget _buildSalaryDefinitionsTab() {
    final filtered = _staffList.where((s) {
      final name = (s['fullName'] ?? (s['name'] ?? '')).toString().toLowerCase();
      final dep = (s['department'] ?? '').toString();
      final schoolType = (s['schoolType'] ?? '').toString();
      
      final matchesSearch = name.contains(_searchQuery.toLowerCase());
      final matchesDep = _depFilter == null || _depFilter == 'Tümü' || dep == _depFilter;
      final matchesType = _schoolTypeFilter == null || _schoolTypeFilter == 'Tümü' || schoolType == _schoolTypeFilter;
      
      return matchesSearch && matchesDep && matchesType;
    }).toList();

    return Column(
      children: [
        _buildSalaryFilters(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final s = filtered[i];
              final def = _salaryDefinitions[s['id']];
              final hasDef = def != null;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: hasDef ? Colors.indigo.shade100 : Colors.red.shade100, width: 1),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: hasDef ? Colors.indigo : Colors.grey.shade300, 
                    child: const Icon(Icons.person, color: Colors.white, size: 28)
                  ),
                  title: Text(s['fullName'] ?? (s['username'] ?? '...'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${s['role'] ?? 'Personel'} - ${s['department'] ?? 'Birimi Belirtilmedi'}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        hasDef 
                          ? 'Maaş: ${_formatCurrency((def['baseSalary'] as num).toDouble())} (${def['salaryType'] == 'monthly' ? 'Aylık' : 'Saatlik'})' 
                          : 'Maaş tanımlanmamış', 
                        style: TextStyle(color: hasDef ? Colors.indigo.shade700 : Colors.red.shade600, fontWeight: hasDef ? FontWeight.bold : FontWeight.normal, fontSize: 13)
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasDef) IconButton(
                        icon: const Icon(Icons.add_task_rounded, color: Colors.green, size: 28),
                        tooltip: 'Bordro Oluştur',
                        onPressed: () => _showIndividualGenerateDialog(s, def),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.edit_note_rounded, color: Colors.indigo, size: 24)
                        ),
                        tooltip: 'Tanımı Düzenle',
                        onPressed: () => _showSalaryEditDialog(s, def),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSalaryFilters() {
    final deps = ['Tümü', ..._staffList.map((e) => (e['department'] ?? '').toString()).where((e) => e.isNotEmpty).toSet().toList()];
    // schoolType often exists in workLocation or schoolType field
    final types = ['Tümü', ..._staffList.map((e) => (e['schoolType'] ?? '').toString()).where((e) => e.isNotEmpty).toSet().toList()];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Personel ara...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _depFilter ?? 'Tümü',
                  items: deps.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) => setState(() => _depFilter = v),
                  decoration: const InputDecoration(labelText: 'Departman', isDense: true),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _schoolTypeFilter ?? 'Tümü',
                  items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => _schoolTypeFilter = v),
                  decoration: const InputDecoration(labelText: 'Okul Türü', isDense: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _updateBulkStatus(String newStatus) async {
    final targetStatus = newStatus == 'approved' ? 'draft' : 'approved';
    final targets = _payrollList.where((p) => p['status'] == targetStatus).toList();
    
    bool confirm = await showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        title: Text(newStatus == 'approved' ? 'Toplu Onay' : 'Toplu Ödeme'),
        content: Text('${targets.length} bordro için durum güncellemesi yapılacaktır. Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('VAZGEÇ')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('EVET')),
        ],
      )
    ) ?? false;

    if (confirm) {
      setState(() => _isLoading = true);
      for (var p in targets) {
        await _service.updatePayrollStatus(p['id'], newStatus);
      }
      await _loadData();
      setState(() => _isLoading = false);
    }
  }

  Widget _buildPayrollCard(Map<String, dynamic> payroll) {
    final staff = _staffList.firstWhere((s) => s['id'] == payroll['staffId'], orElse: () => {});
    final name = staff['fullName'] ?? 'Bilinmeyen Personel';
    final net = (payroll['netSalary'] as num).toDouble();
    final status = payroll['status'] ?? 'draft';
    
    Color statusColor = Colors.grey;
    String statusText = 'Taslak';
    if (status == 'approved') { statusColor = Colors.blue; statusText = 'Onaylandı'; }
    if (status == 'paid') { statusColor = Colors.green; statusText = 'Ödendi'; }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Text('Brüt: ${payroll['baseSalary']} ₺', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${NumberFormat.currency(symbol: '', locale: 'tr_TR').format(net)} ₺', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.indigo)),
            const Text('NET ÖDEME', style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
        onTap: () => _showPayrollDetails(payroll, staff),
      ),
    );
  }

  // --- TAB 1: PAYROLL LIST ---

  Widget _buildPayrollListTab() {
    final draftCount = _payrollList.where((p) => p['status'] == 'draft').length;
    final approvedCount = _payrollList.where((p) => p['status'] == 'approved').length;

    return Column(
      children: [
        _buildMonthPicker(),
        if (_payrollList.isNotEmpty) 
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                if (draftCount > 0)
                  Expanded(child: ElevatedButton.icon(
                    onPressed: () => _updateBulkStatus('approved'),
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: Text('$draftCount TASLAĞI ONAYLA', style: const TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, elevation: 2, padding: const EdgeInsets.symmetric(vertical: 16)),
                  )),
                if (draftCount > 0 && approvedCount > 0) const SizedBox(width: 16),
                if (approvedCount > 0)
                  Expanded(child: ElevatedButton.icon(
                    onPressed: () => _updateBulkStatus('paid'),
                    icon: const Icon(Icons.payments_outlined, size: 20),
                    label: Text('$approvedCount ÖDEMEYİ YAP', style: const TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, elevation: 2, padding: const EdgeInsets.symmetric(vertical: 16)),
                  )),
              ],
            ),
          ),
        Expanded(
          child: _payrollList.isEmpty 
            ? _buildEmptyState('Seçili ay için bordro bulunamadı.')
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                itemCount: _payrollList.length,
                itemBuilder: (ctx, i) => _buildPayrollCard(_payrollList[i]),
              ),
        ),
      ],
    );
  }

  // --- TAB 3: GENERATE PAYROLL ---

  Widget _buildGenerateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bordro Oluşturma Sihirbazı', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Seçili personeller için otomatik maaş, mesai ve izin hesaplamaları yapılarak bordrolar oluşturulur.', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 32),
          
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildMonthPicker(showAsHeader: true),
                  const Divider(height: 40),
                  const Text('İşlem yapmak istediğiniz personeli seçin ve bordroları oluşturun.', textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: _showGenerateBulkDialog,
                      icon: const Icon(Icons.bolt_rounded, color: Colors.white),
                      label: const Text('SEÇİLİ AY İÇİN BÖRDRO OLUŞTUR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 4: REPORTS ---

  Widget _buildReportsTab() {
    double totalNet = _payrollList.fold(0.0, (sum, p) => sum + (p['netSalary'] as num).toDouble());
    double totalBase = _payrollList.fold(0.0, (sum, p) => sum + (p['baseSalary'] as num).toDouble());
    double totalEarnings = _payrollList.fold(0.0, (sum, p) => sum + (p['totalEarnings'] as num).toDouble());
    double totalDeductions = _payrollList.fold(0.0, (sum, p) => sum + (p['totalDeductions'] as num).toDouble());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMonthPicker(),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildStatCard('Toplam Gider', _formatCurrency(totalEarnings), Colors.orange)),
              const SizedBox(width: 16),
              Expanded(child: _buildStatCard('Net Ödemeler', _formatCurrency(totalNet), Colors.green)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatCard('Temel Maaşlar', _formatCurrency(totalBase), Colors.blue)),
              const SizedBox(width: 16),
              Expanded(child: _buildStatCard('Kesintiler', _formatCurrency(totalDeductions), Colors.red)),
            ],
          ),
          const SizedBox(height: 32),
          const Text('Personel Dağılımı (Net)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          ..._payrollList.map((p) {
             final staff = _staffList.firstWhere((s) => s['id'] == p['staffId'], orElse: () => {});
             return ListTile(
               leading: CircleAvatar(backgroundColor: Colors.indigo.withOpacity(0.1), child: const Icon(Icons.person, color: Colors.indigo, size: 20)),
               title: Text(staff['fullName'] ?? '...', style: const TextStyle(fontSize: 14)),
               trailing: Text(_formatCurrency((p['netSalary'] as num).toDouble()), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
             );
          }).toList(),
        ],
      ),
    );
  }

  // --- UTILS ---

  Widget _buildMonthPicker({bool showAsHeader = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: showAsHeader ? Colors.transparent : Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(onPressed: () { setState(() => _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1)); _loadData(); }, icon: const Icon(Icons.chevron_left)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
            child: Text(DateFormat('MMMM yyyy', 'tr_TR').format(_selectedDate).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.indigo)),
          ),
          IconButton(onPressed: () { setState(() => _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1)); _loadData(); }, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.2), width: 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.payments_outlined, size: 60, color: Colors.grey), const SizedBox(height: 16), Text(msg, style: const TextStyle(color: Colors.grey))]));
  }

  // --- DIALOGS ---

  Future<void> _showSalaryEditDialog(Map<String, dynamic> staff, Map<String, dynamic>? def) async {
    final isMobile = MediaQuery.of(context).size.width < 800;
    
    if (isMobile) {
      // Mobile full screen
      await Navigator.push(context, MaterialPageRoute(builder: (_) => _SalaryEditScreen(
        staff: staff, 
        def: def, 
        service: _service, 
        institutionId: _myInstitutionId!,
        onSaved: _loadData,
      )));
    } else {
      // Desktop spacious modal
      final baseController = TextEditingController(text: def?['baseSalary']?.toString() ?? '');
      final extraController = TextEditingController(text: def?['extraHourRate']?.toString() ?? '');
      String type = def?['salaryType'] ?? 'monthly';

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: Text('${staff['fullName']} Maaş Tanımı', style: const TextStyle(fontWeight: FontWeight.bold)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Maaş Bilgileri', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: type,
                    items: const [DropdownMenuItem(value: 'monthly', child: Text('Aylık Sabit Maaş')), DropdownMenuItem(value: 'hourly', child: Text('Saatlik Ücret Bazlı'))],
                    onChanged: (v) => setS(() => type = v!),
                    decoration: const InputDecoration(labelText: 'Maaş Hesaplama Tipi', filled: true),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: baseController, 
                    decoration: const InputDecoration(labelText: 'Temel Maaş (Net ₺)', prefixText: '₺ ', filled: true), 
                    keyboardType: TextInputType.number
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: extraController, 
                    decoration: const InputDecoration(labelText: 'Ek Ders / Mesai Saat Ücreti', prefixText: '₺ ', filled: true), 
                    keyboardType: TextInputType.number
                  ),
                  const SizedBox(height: 12),
                  const Text('Not: Bu personelin branşına göre saat başı ek kazançları bu oran üzerinden hesaplanacaktır.', style: TextStyle(color: Colors.blue, fontSize: 11)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('VAZGEÇ', style: TextStyle(color: Colors.grey))),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  await _service.upsertSalaryDefinition(
                    staffId: staff['id'],
                    institutionId: _myInstitutionId!,
                    baseSalary: double.tryParse(baseController.text.replaceAll(',', '.')) ?? 0.0,
                    salaryType: type,
                    extraHourRate: double.tryParse(extraController.text.replaceAll(',', '.')) ?? 0.0,
                    overtimeHourRate: double.tryParse(extraController.text.replaceAll(',', '.')) ?? 0.0,
                  );
                  Navigator.pop(ctx);
                  _loadData();
                },
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                child: const Text('DEĞİŞİKLİKLERİ KAYDET'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _showGenerateBulkDialog() async {
    final List<String> selectedIds = _staffList.where((s) => _salaryDefinitions.containsKey(s['id'])).map((s) => s['id'] as String).toList();
    
    if (selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maaş tanımı yapılmış personel bulunamadı.')));
      return;
    }

    bool confirmed = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Toplu Bordro Oluştur'),
        content: Text('${selectedIds.length} personel için ${_selectedDate.month}/${_selectedDate.year} dönemi bordroları oluşturulacaktır. Emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('VAZGEÇ')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OLUŞTUR')),
        ],
      ),
    ) ?? false;

    if (confirmed) {
      setState(() => _isLoading = true);
      int count = 0;
      int errors = 0;
      for (var id in selectedIds) {
        try {
          await _service.generatePayroll(
            staffId: id,
            institutionId: _myInstitutionId!,
            month: _selectedDate.month,
            year: _selectedDate.year,
          );
          count++;
        } catch (e) {
          errors++;
        }
      }
      setState(() => _isLoading = false);
      _loadData();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count bordro oluşturuldu. $errors hata.')));
    }
  }

  Future<void> _showIndividualGenerateDialog(Map<String, dynamic> staff, Map<String, dynamic> def) async {
    final extraLController = TextEditingController(text: '0');
    final bonusController = TextEditingController(text: '0');
    final deducController = TextEditingController(text: '0');
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${staff['fullName']} - Bordro Oluştur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_selectedDate.month}/${_selectedDate.year} dönemi için ek kalemleri giriniz.'),
            const SizedBox(height: 16),
            TextField(controller: extraLController, decoration: const InputDecoration(labelText: 'Ek Ders Saati', hintText: 'Sadece öğretmenler için'), keyboardType: TextInputType.number),
            TextField(controller: bonusController, decoration: const InputDecoration(labelText: 'Ek Prim / Bonus (₺)'), keyboardType: TextInputType.number),
            TextField(controller: deducController, decoration: const InputDecoration(labelText: 'Diğer Kesintiler (₺)'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('VAZGEÇ')),
          ElevatedButton(
            onPressed: () async {
              try {
                await _service.generatePayroll(
                  staffId: staff['id'],
                  institutionId: _myInstitutionId!,
                  month: _selectedDate.month,
                  year: _selectedDate.year,
                  extraLectures: double.tryParse(extraLController.text) ?? 0.0,
                  customBonus: double.tryParse(bonusController.text) ?? 0.0,
                  customDeduction: double.tryParse(deducController.text) ?? 0.0,
                );
                Navigator.pop(ctx);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bordro başarıyla oluşturuldu.')));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: ${e.toString()}')));
              }
            },
            child: const Text('OLUŞTUR'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPayrollDetails(Map<String, dynamic> payroll, Map<String, dynamic> staff) async {
    final items = await _service.getPayrollItems(payroll['id']);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(staff['fullName'] ?? '...', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    Text('${payroll['month']}/${payroll['year']} Dönemi Bordrosu', style: const TextStyle(color: Colors.grey)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.indigo, size: 32), onPressed: () => _generatePdf(payroll, staff, items)),
              ],
            ),
            const Divider(height: 48),
            Expanded(
              child: ListView(
                children: [
                  const Text('KAZANÇLAR', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13)),
                  ...items.where((i) => i['type'] == 'earning').map((i) => ListTile(
                    dense: true, 
                    title: Text(i['title'], style: const TextStyle(fontSize: 14)), 
                    trailing: Text('+${_formatCurrency((i['amount'] as num).toDouble())}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                  )),
                  const SizedBox(height: 16),
                  const Text('KESİNTİLER', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13)),
                  ...items.where((i) => i['type'] == 'deduction').map((i) => ListTile(
                    dense: true, 
                    title: Text(i['title'], style: const TextStyle(fontSize: 14)), 
                    trailing: Text('-${_formatCurrency((i['amount'] as num).toDouble())}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
                  )),
                  const Divider(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('NET ÖDENECEK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(_formatCurrency((payroll['netSalary'] as num).toDouble()), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.indigo)),
                    ],
                  ),
                ],
              ),
            ),
            if (payroll['status'] == 'draft') ...[
               const SizedBox(height: 16),
               SizedBox(
                 width: double.infinity,
                 height: 55,
                 child: ElevatedButton(
                   onPressed: () async { await _service.updatePayrollStatus(payroll['id'], 'approved'); Navigator.pop(ctx); _loadData(); },
                   style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                   child: const Text('BORDROYU ONAYLA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                 ),
               ),
            ],
            if (payroll['status'] == 'approved') ...[
               const SizedBox(height: 16),
               SizedBox(
                 width: double.infinity,
                 height: 55,
                 child: ElevatedButton(
                   onPressed: () async { await _service.updatePayrollStatus(payroll['id'], 'paid'); Navigator.pop(ctx); _loadData(); },
                   style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                   child: const Text('ÖDEMEYİ TAMAMLA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                 ),
               ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                bool confirm = await showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Bordroyu Sil'), content: const Text('Bu işlem geri alınamaz.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('VAZGEÇ')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SİL', style: TextStyle(color: Colors.red)))])) ?? false;
                if (confirm) { await _service.deletePayroll(payroll['id']); Navigator.pop(ctx); _loadData(); }
              },
              child: const Text('Bordroyu Sil', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generatePdf(Map<String, dynamic> p, Map<String, dynamic> s, List<Map<String, dynamic>> items) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Header(level: 0, child: pw.Text('MAAŞ BORDROSU (PAYSLIP)', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Kurum: ${p['institutionId']}'),
                  pw.Text('Personel: ${s['fullName'] ?? '...'}'),
                  pw.Text('Dönem: ${p['month']}/${p['year']}'),
                ]),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text('Tarih: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}'),
                  pw.Text('Durum: ${p['status']}'),
                ]),
              ],
            ),
            pw.Divider(thickness: 2),
            pw.SizedBox(height: 20),
            pw.Text('KAZANÇLAR', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
            pw.TableHelper.fromTextArray(
              context: context,
              data: items.where((i) => i['type'] == 'earning').map((i) => [i['title'], _formatCurrency((i['amount'] as num).toDouble())]).toList(),
            ),
            pw.SizedBox(height: 15),
            pw.Text('KESİNTİLER', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
            pw.TableHelper.fromTextArray(
              context: context,
              data: items.where((i) => i['type'] == 'deduction').map((i) => [i['title'], _formatCurrency((i['amount'] as num).toDouble())]).toList(),
            ),
            pw.SizedBox(height: 30),
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('TOPLAM KAZANÇ: ${_formatCurrency((p['totalEarnings'] as num).toDouble())}', style: const pw.TextStyle(fontSize: 10)),
                pw.Text('TOPLAM KESİNTİ: ${_formatCurrency((p['totalDeductions'] as num).toDouble())}', style: const pw.TextStyle(fontSize: 10)),
                pw.Divider(color: PdfColors.grey400),
                pw.Text('NET ÖDENECEK: ${_formatCurrency((p['netSalary'] as num).toDouble())}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo)),
              ]),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }
}

// --- Mobile Support Widgets ---

class _SalaryEditScreen extends StatefulWidget {
  final Map<String, dynamic> staff;
  final Map<String, dynamic>? def;
  final PayrollService service;
  final String institutionId;
  final VoidCallback onSaved;

  const _SalaryEditScreen({required this.staff, this.def, required this.service, required this.institutionId, required this.onSaved});

  @override
  State<_SalaryEditScreen> createState() => _SalaryEditScreenState();
}

class _SalaryEditScreenState extends State<_SalaryEditScreen> {
  late TextEditingController _base;
  late TextEditingController _extra;
  late String _type;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _base = TextEditingController(text: widget.def?['baseSalary']?.toString() ?? '');
    _extra = TextEditingController(text: widget.def?['extraHourRate']?.toString() ?? '');
    _type = widget.def?['salaryType'] ?? 'monthly';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Maaş Tanımı Düzenle')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.staff['fullName'] ?? '...', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(widget.staff['department'] ?? 'Departman Belirtilmedi', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 32),
            DropdownButtonFormField<String>(
              value: _type,
              items: const [DropdownMenuItem(value: 'monthly', child: Text('Aylık Sabit Maaş')), DropdownMenuItem(value: 'hourly', child: Text('Saatlik Ücret Bazlı'))],
              onChanged: (v) => setState(() => _type = v!),
              decoration: const InputDecoration(labelText: 'Maaş Hesaplama Tipi', filled: true),
            ),
            const SizedBox(height: 20),
            TextField(controller: _base, decoration: const InputDecoration(labelText: 'Temel Maaş (Net ₺)', prefixText: '₺ ', filled: true), keyboardType: TextInputType.number),
            const SizedBox(height: 20),
            TextField(controller: _extra, decoration: const InputDecoration(labelText: 'Ek Ders / Mesai Saat Ücreti', prefixText: '₺ ', filled: true), keyboardType: TextInputType.number),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _saving ? null : () async {
                  setState(() => _saving = true);
                  await widget.service.upsertSalaryDefinition(
                    staffId: widget.staff['id'],
                    institutionId: widget.institutionId,
                    baseSalary: double.tryParse(_base.text.replaceAll(',', '.')) ?? 0.0,
                    salaryType: _type,
                    extraHourRate: double.tryParse(_extra.text.replaceAll(',', '.')) ?? 0.0,
                    overtimeHourRate: double.tryParse(_extra.text.replaceAll(',', '.')) ?? 0.0,
                  );
                  widget.onSaved();
                  Navigator.pop(context);
                },
                child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text('KAYDET'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
