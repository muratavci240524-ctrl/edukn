import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/user_permission_service.dart';
import '../../../services/financial_report_service.dart';
import '../../../widgets/custom_date_range_picker.dart';
import '../../../widgets/edukn_back_button.dart';
import 'student_payment_plan_widget.dart';

class AccountingDashboardScreen extends StatefulWidget {
  final int initialTabIndex;
  const AccountingDashboardScreen({Key? key, this.initialTabIndex = 0}) : super(key: key);

  @override
  _AccountingDashboardScreenState createState() =>
      _AccountingDashboardScreenState();
}

class _AccountingDashboardScreenState extends State<AccountingDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final NumberFormat _currencyFormat =
      NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');

  bool _isLoading = true;
  String? _institutionId;
  Map<String, dynamic>? userData;

  // Kasalar ve Genel İstatistikler
  List<Map<String, dynamic>> _cashes = [];
  double _totalCashBalance = 0.0;
  List<Map<String, dynamic>> _recentTransactions = [];

  // Öğrenci Mali İstatistikleri
  List<Map<String, dynamic>> _allPaymentPlans = [];
  double _totalStudentContract = 0.0;
  double _totalStudentCollected = 0.0;
  double _totalStudentRemaining = 0.0;
  double _totalStudentOverdue = 0.0;
  List<Map<String, dynamic>> _overdueInstallmentsList = [];
  List<Map<String, dynamic>> _upcomingInstallmentsList = [];

  // Filtreleme
  final TextEditingController _searchCtrl = TextEditingController();
  String _studentSearchQuery = '';
  String _studentStatusFilter = 'all'; // 'all', 'has_debt', 'overdue', 'paid'
  String? _selectedStudentIdForDetail;
  Map<String, dynamic>? _selectedStudentDataForDetail;
  final Set<int> _selectedOverdueIndices = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
    );
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final data = await UserPermissionService.loadUserData();
      if (mounted) setState(() => userData = data);

      final email = user.email ?? '';
      _institutionId =
          await UserPermissionService.resolveInstitutionId(email, userData: userData);

      await _refreshData();
    } catch (e) {
      debugPrint('Accounting Dashboard Init Error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshData() async {
    if (_institutionId == null) return;

    try {
      // 1. Kasaları Yükle
      final cashQuery = await FirebaseFirestore.instance
          .collection('cashes')
          .where('institutionId', isEqualTo: _institutionId)
          .get();

      if (cashQuery.docs.isEmpty) {
        await FirebaseFirestore.instance.collection('cashes').add({
          'institutionId': _institutionId,
          'name': 'Ana Kasa (Nakit)',
          'balance': 0.0,
          'type': 'cash',
          'createdAt': FieldValue.serverTimestamp(),
        });
        await FirebaseFirestore.instance.collection('cashes').add({
          'institutionId': _institutionId,
          'name': 'Banka / POS Hesabı',
          'balance': 0.0,
          'type': 'bank',
          'createdAt': FieldValue.serverTimestamp(),
        });
        _refreshData();
        return;
      }

      double cashTotal = 0;
      final cashesList = cashQuery.docs.map((doc) {
        final b = (doc['balance'] as num?)?.toDouble() ?? 0.0;
        cashTotal += b;
        return {'id': doc.id, ...doc.data()};
      }).toList();

      // 2. Son İşlemler (Transactions)
      final transQuery = await FirebaseFirestore.instance
          .collection('transactions')
          .where('institutionId', isEqualTo: _institutionId)
          .orderBy('date', descending: true)
          .limit(100)
          .get();

      final transList =
          transQuery.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();

      // 3. Tüm Öğrenci Ödeme Planları (Payment Plans)
      final plansQuery = await FirebaseFirestore.instance
          .collection('payment_plans')
          .where('institutionId', isEqualTo: _institutionId)
          .get();

      double totalContract = 0.0;
      double totalCollected = 0.0;
      double totalOverdue = 0.0;
      final List<Map<String, dynamic>> overdueList = [];
      final List<Map<String, dynamic>> upcomingList = [];

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final in30Days = today.add(const Duration(days: 30));

      final plans = plansQuery.docs.map((doc) {
        final data = doc.data();
        final planId = doc.id;
        final net = (data['netTotal'] ?? data['totalAmount'] ?? 0).toDouble();
        final downPayment = (data['downPayment'] ?? 0).toDouble();
        final downPaymentPaid = data['downPaymentPaid'] == true;

        totalContract += net;
        double thisPlanCollected = downPaymentPaid ? downPayment : 0.0;

        final installments = List<Map<String, dynamic>>.from(
            (data['installments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));

        for (int i = 0; i < installments.length; i++) {
          final inst = installments[i];
          final amount = (inst['amount'] ?? 0).toDouble();
          final isPaid = inst['status'] == 'paid';
          final dueDateStr = inst['dueDate']?.toString() ?? '';
          DateTime? dueDate;
          try {
            if (dueDateStr.contains('.')) {
              final parts = dueDateStr.split('.');
              if (parts.length == 3) {
                dueDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
              }
            }
          } catch (_) {}

          if (isPaid) {
            thisPlanCollected += amount;
          } else {
            if (dueDate != null) {
              if (dueDate.isBefore(today)) {
                totalOverdue += amount;
                overdueList.add({
                  'planId': planId,
                  'planName': data['name'] ?? 'Ödeme Planı',
                  'studentId': data['studentId'],
                  'studentName': data['studentName'] ?? 'Öğrenci',
                  'studentNo': data['studentNo'] ?? '',
                  'installmentIndex': i,
                  'installment': inst,
                  'amount': amount,
                  'dueDate': dueDateStr,
                  'dueDateTime': dueDate,
                  'overdueDays': today.difference(dueDate).inDays,
                });
              } else if (dueDate.isBefore(in30Days)) {
                upcomingList.add({
                  'planId': planId,
                  'planName': data['name'] ?? 'Ödeme Planı',
                  'studentId': data['studentId'],
                  'studentName': data['studentName'] ?? 'Öğrenci',
                  'studentNo': data['studentNo'] ?? '',
                  'installmentIndex': i,
                  'installment': inst,
                  'amount': amount,
                  'dueDate': dueDateStr,
                  'dueDateTime': dueDate,
                  'daysLeft': dueDate.difference(today).inDays,
                });
              }
            }
          }
        }

        totalCollected += thisPlanCollected;
        final thisRemaining = (net - thisPlanCollected).clamp(0.0, double.infinity);

        return {
          'id': planId,
          ...data,
          '_collected': thisPlanCollected,
          '_remaining': thisRemaining,
          '_isCompleted': thisRemaining <= 0,
          '_hasOverdue': installments.any((inst) {
            if (inst['status'] == 'paid') return false;
            final dStr = inst['dueDate']?.toString() ?? '';
            try {
              if (dStr.contains('.')) {
                final parts = dStr.split('.');
                if (parts.length == 3) {
                  final d = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                  return d.isBefore(today);
                }
              }
            } catch (_) {}
            return false;
          }),
        };
      }).toList();

      overdueList.sort((a, b) => (b['overdueDays'] as int).compareTo(a['overdueDays'] as int));
      upcomingList.sort((a, b) => (a['dueDateTime'] as DateTime).compareTo(b['dueDateTime'] as DateTime));

      if (mounted) {
        setState(() {
          _cashes = cashesList;
          _totalCashBalance = cashTotal;
          _recentTransactions = transList;
          _allPaymentPlans = plans;
          _totalStudentContract = totalContract;
          _totalStudentCollected = totalCollected;
          _totalStudentRemaining = (totalContract - totalCollected).clamp(0.0, double.infinity);
          _totalStudentOverdue = totalOverdue;
          _overdueInstallmentsList = overdueList;
          _upcomingInstallmentsList = upcomingList;
        });
      }
    } catch (e) {
      debugPrint('Refresh data error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
        ),
      );
    }

    final isMobileScreen = MediaQuery.of(context).size.width < 768;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: EduknAppBar(
        title: isMobileScreen ? 'Mali İşler' : 'Mali İşler & Öğrenci Finans Merkezi',
        subtitle: '${_overdueInstallmentsList.length}',
        actions: [
          Container(
            margin: EdgeInsets.only(right: isMobileScreen ? 4 : 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF6366F1)]),
              borderRadius: BorderRadius.circular(isMobileScreen ? 10 : 12),
              boxShadow: [
                BoxShadow(color: const Color(0xFF4F46E5).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: IconButton(
              icon: Icon(Icons.add_card_rounded, color: Colors.white, size: isMobileScreen ? 18 : 22),
              onPressed: () => _openAddKasaDialog(),
              tooltip: 'Yeni Kasa / Hesap Tanımla',
              padding: isMobileScreen ? const EdgeInsets.all(8) : const EdgeInsets.all(8),
              constraints: isMobileScreen ? const BoxConstraints(minWidth: 36, minHeight: 36) : null,
            ),
          ),
          Container(
            margin: EdgeInsets.only(right: isMobileScreen ? 8 : 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF6366F1)]),
              borderRadius: BorderRadius.circular(isMobileScreen ? 10 : 12),
              boxShadow: [
                BoxShadow(color: const Color(0xFF4F46E5).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: IconButton(
              icon: Icon(Icons.print_rounded, color: Colors.white, size: isMobileScreen ? 18 : 22),
              onPressed: () => _openReportingCenterDialog(),
              tooltip: 'Finans ve Muhasebe Raporları (PDF & Excel)',
              padding: isMobileScreen ? const EdgeInsets.all(8) : const EdgeInsets.all(8),
              constraints: isMobileScreen ? const BoxConstraints(minWidth: 36, minHeight: 36) : null,
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: const Color(0xFF4F46E5),
          unselectedLabelColor: const Color(0xFF64748B),
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: isMobileScreen ? 11 : 13),
          unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: isMobileScreen ? 11 : 13),
          labelPadding: EdgeInsets.symmetric(horizontal: isMobileScreen ? 10 : 16),
          indicatorColor: const Color(0xFF4F46E5),
          indicatorWeight: 3,
          tabs: [
            Tab(icon: Icon(Icons.dashboard_rounded, size: isMobileScreen ? 16 : 18), text: 'Genel Finans Özeti'),
            Tab(
              icon: Icon(Icons.school_rounded, size: isMobileScreen ? 16 : 18),
              text: 'Öğrenci Taksit Takibi (${_allPaymentPlans.length})',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: _overdueInstallmentsList.isNotEmpty,
                label: Text('${_overdueInstallmentsList.length}'),
                backgroundColor: const Color(0xFFEF4444),
                child: Icon(Icons.warning_amber_rounded, size: isMobileScreen ? 16 : 18),
              ),
              text: 'Geciken Taksitler',
            ),
            Tab(icon: Icon(Icons.account_balance_wallet_rounded, size: isMobileScreen ? 16 : 18), text: 'Kasa & Hareketler'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGeneralDashboardTab(),
          _buildStudentAccountingTab(),
          _buildOverdueInstallmentsTab(),
          _buildCashAndTransactionsTab(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. SEKME: GENEL FİNANS ÖZETİ
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildGeneralDashboardTab() {
    final progress = _totalStudentContract > 0 ? (_totalStudentCollected / _totalStudentContract).clamp(0.0, 1.0) : 0.0;
    final isMobile = MediaQuery.of(context).size.width < 900;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          Container(
            padding: EdgeInsets.all(isMobile ? 18 : 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF4338CA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: const Color(0xFF312E81).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMobile)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Öğrenci Sözleşme ve Tahsilat Durumu', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text('Kurum geneli aktif sözleşmeler ve alacak durumu', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFC7D2FE))),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Text(
                          'Tahsilat Oranı: %${(progress * 100).toStringAsFixed(1)}',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Öğrenci Sözleşme ve Tahsilat Durumu', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text('Kurum geneli aktif sözleşmeler, nakit akışı ve alacak durumu', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFC7D2FE))),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Text(
                          'Tahsilat Oranı: %${(progress * 100).toStringAsFixed(1)}',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 4 Ana Metrik Kartı
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 900;
              final isVeryNarrow = constraints.maxWidth < 500;
              final cards = [
                _buildStatCard(
                  title: 'Toplam Sözleşme',
                  value: _currencyFormat.format(_totalStudentContract),
                  icon: Icons.assignment_turned_in_rounded,
                  color: const Color(0xFF4F46E5),
                  bgColor: const Color(0xFFEEF2FF),
                  subtitle: '${_allPaymentPlans.length} Öğrenci Sözleşmesi',
                ),
                _buildStatCard(
                  title: 'Tahsil Edilen Tutar',
                  value: _currencyFormat.format(_totalStudentCollected),
                  icon: Icons.check_circle_rounded,
                  color: const Color(0xFF10B981),
                  bgColor: const Color(0xFFECFDF5),
                  subtitle: 'Nakit, POS ve Havale',
                ),
                _buildStatCard(
                  title: 'Kalan Alacak / Bakiye',
                  value: _currencyFormat.format(_totalStudentRemaining),
                  icon: Icons.hourglass_top_rounded,
                  color: const Color(0xFF0284C7),
                  bgColor: const Color(0xFFF0F9FF),
                  subtitle: 'Gelecek Taksitler',
                ),
                _buildStatCard(
                  title: 'Vadesi Geçen Taksitler',
                  value: _currencyFormat.format(_totalStudentOverdue),
                  icon: Icons.warning_rounded,
                  color: const Color(0xFFEF4444),
                  bgColor: const Color(0xFFFEF2F2),
                  subtitle: '${_overdueInstallmentsList.length} Taksit Gecikmede',
                ),
              ];

              if (isVeryNarrow) {
                return Column(
                  children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: c)).toList(),
                );
              }

              if (isNarrow) {
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  children: cards,
                );
              }

              return Row(
                children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: c))).toList(),
              );
            },
          ),
          const SizedBox(height: 24),

          // Alt Paneller: Kasa Durumu & Yaklaşan Taksitler
          if (isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCashBalanceCard(),
                const SizedBox(height: 16),
                _buildUpcomingInstallmentsCard(),
              ],
            )
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: _buildCashBalanceCard()),
                  const SizedBox(width: 20),
                  Expanded(flex: 4, child: _buildUpcomingInstallmentsCard()),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCashBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Kasa & Banka Bakiyeleri', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: const Color(0xFF1E293B))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                child: Text('Toplam: ${_currencyFormat.format(_totalCashBalance)}', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12, color: const Color(0xFF059669))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_cashes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('Tanımlı kasa bulunamadı', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13)),
              ),
            )
          else
            ..._cashes.map((k) {
              final bal = (k['balance'] as num?)?.toDouble() ?? 0.0;
              final isBank = k['type'] == 'bank';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isBank ? const Color(0xFFEEF2FF) : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(isBank ? Icons.account_balance_rounded : Icons.payments_rounded, color: isBank ? const Color(0xFF4F46E5) : const Color(0xFFD97706), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(k['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text(isBank ? 'Banka / POS Hesabı' : 'Nakit Kasa', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    Text(_currencyFormat.format(bal), style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, color: const Color(0xFF1E293B))),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildUpcomingInstallmentsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Yaklaşan Taksitler (30 Gün)', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: const Color(0xFF1E293B))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                child: Text('${_upcomingInstallmentsList.length} Taksit', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: const Color(0xFF64748B))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_upcomingInstallmentsList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Önümüzdeki 30 gün içinde vadesi gelen taksit bulunmuyor.', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13)),
              ),
            )
          else
            ..._upcomingInstallmentsList.take(5).map((item) {
              final daysLeft = item['daysLeft'] as int;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFFEEF2FF),
                      child: Text('${daysLeft}g', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 11, color: const Color(0xFF4F46E5))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['studentName'], style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text('${item['installment']['title']} • Vade: ${item['dueDate']}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    Text(_currencyFormat.format(item['amount']), style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: const Color(0xFF1E293B))),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 22),
              ),
              Flexible(
                child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11, color: const Color(0xFF64748B))),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: const Color(0xFF64748B))),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: const Color(0xFF1E293B))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. SEKME: ÖĞRENCİ BAZLI TAKSİT TAKİBİ VE DETAY MODÜLÜ (MOBİL & WEB UYUMLU)
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStudentAccountingTab() {
    final isMobile = MediaQuery.of(context).size.width < 900;

    if (isMobile) {
      if (_selectedStudentIdForDetail != null) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              setState(() => _selectedStudentIdForDetail = null);
            }
          },
          child: _buildStudentDetailView(isMobile: true),
        );
      }
      return _buildStudentListView(isMobile: true);
    }

    return Row(
      children: [
        // Sol Liste Paneli: 360px Genişlik
        SizedBox(
          width: 360,
          child: _buildStudentListView(isMobile: false),
        ),

        // Sağ Detay Paneli: Geriye Kalan Tüm Alan
        Expanded(
          child: _selectedStudentIdForDetail == null
              ? _buildEmptyStudentDetailPlaceholder()
              : _buildStudentDetailView(isMobile: false),
        ),
      ],
    );
  }

  Widget _buildStudentListView({required bool isMobile}) {
    final filteredPlans = _allPaymentPlans.where((plan) {
      final name = (plan['studentName'] ?? '').toString().toLowerCase();
      final no = (plan['studentNo'] ?? '').toString().toLowerCase();
      final q = _studentSearchQuery.toLowerCase();
      final matchesQuery = q.isEmpty || name.contains(q) || no.contains(q);

      if (!matchesQuery) return false;

      if (_studentStatusFilter == 'has_debt') return (plan['_remaining'] as double) > 0;
      if (_studentStatusFilter == 'overdue') return plan['_hasOverdue'] == true;
      if (_studentStatusFilter == 'paid') return (plan['_remaining'] as double) <= 0;

      return true;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: isMobile ? null : const Border(right: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        children: [
          // Ultra Premium Arama ve Filtre Çubuğu
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Öğrenci adı veya no ile ara...',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4F46E5), size: 20),
                      suffixIcon: _studentSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _studentSearchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                    onChanged: (val) => setState(() => _studentSearchQuery = val),
                  ),
                ),
                const SizedBox(height: 12),
                ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                      PointerDeviceKind.stylus,
                    },
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'Tümü (${_allPaymentPlans.length})'),
                        const SizedBox(width: 6),
                        _buildFilterChip('has_debt', 'Borcu Olan'),
                        const SizedBox(width: 6),
                        _buildFilterChip('overdue', 'Geciken'),
                        const SizedBox(width: 6),
                        _buildFilterChip('paid', 'Biten'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Öğrenci Plan Listesi
          Expanded(
            child: filteredPlans.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search_off_rounded, size: 44, color: Color(0xFFCBD5E1)),
                          const SizedBox(height: 12),
                          Text('Öğrenci bulunamadı', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                          const SizedBox(height: 4),
                          Text('Farklı bir arama terimi veya filtre deneyebilirsiniz.', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredPlans.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final plan = filteredPlans[idx];
                      final studentId = plan['studentId'] as String;
                      final isSelected = !isMobile && _selectedStudentIdForDetail == studentId;
                      final remaining = (plan['_remaining'] as double);
                      final hasOverdue = plan['_hasOverdue'] == true;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedStudentIdForDetail = studentId;
                            _selectedStudentDataForDetail = {
                              'id': studentId,
                              'fullName': plan['studentName'],
                              'studentNo': plan['studentNo'],
                              'institutionId': _institutionId,
                            };
                          });
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)],
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFF1F5F9),
                                child: Icon(Icons.person_rounded, color: isSelected ? Colors.white : const Color(0xFF64748B), size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            plan['studentName'] ?? 'Öğrenci',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
                                          ),
                                        ),
                                        if (plan['studentNo'] != null && plan['studentNo'].toString().isNotEmpty) ...[
                                          const SizedBox(width: 4),
                                          Text('(${plan['studentNo']})', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      plan['name'] ?? 'Ödeme Sözleşmesi',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(_currencyFormat.format(plan['netTotal']), style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF1E293B))),
                                  const SizedBox(height: 2),
                                  if (remaining <= 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(4)),
                                      child: Text('ÖDENDİ', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF059669))),
                                    )
                                  else if (hasOverdue)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(4)),
                                      child: Text('GECİKMEDE', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFFDC2626))),
                                    )
                                  else
                                    Text('Kalan: ${_currencyFormat.format(remaining)}', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF4F46E5))),
                                ],
                              ),
                              if (isMobile) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                              ],
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
  }

  Widget _buildStudentDetailView({required bool isMobile}) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Detay Başlık Çubuğu
          Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                if (isMobile) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.indigo),
                    onPressed: () => setState(() => _selectedStudentIdForDetail = null),
                    tooltip: 'Listeye Geri Dön',
                  ),
                  const SizedBox(width: 4),
                ],
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, size: 18, color: Color(0xFF4F46E5)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedStudentDataForDetail?['fullName'] ?? 'Öğrenci Finans Kartı',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: const Color(0xFF1E293B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Öğrenci No: ${_selectedStudentDataForDetail?['studentNo'] ?? '-'} • Taksit & Tahsilat Dökümü',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!isMobile)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                    onPressed: () => setState(() => _selectedStudentIdForDetail = null),
                    tooltip: 'Kapat',
                  ),
              ],
            ),
          ),
          Expanded(
            child: StudentPaymentPlanWidget(
              studentId: _selectedStudentIdForDetail!,
              studentData: _selectedStudentDataForDetail,
              institutionId: _institutionId,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStudentDetailPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(color: Color(0xFFEEF2FF), shape: BoxShape.circle),
              child: const Icon(Icons.touch_app_rounded, size: 48, color: Color(0xFF4F46E5)),
            ),
            const SizedBox(height: 16),
            Text('Öğrenci Finans Kartını Görüntüleyin', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
            const SizedBox(height: 6),
            Text('Taksit dökümünü incelemek, tahsilat almak veya sözleşme yazdırmak için sol listeden bir öğrenci seçiniz.', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _studentStatusFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _studentStatusFilter = key);
      },
      selectedColor: const Color(0xFFEEF2FF),
      labelStyle: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
        color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. SEKME: GECİKEN TAKSİTLER & VELİ BİLDİRİMİ
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildOverdueInstallmentsTab() {
    if (_overdueInstallmentsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(color: Color(0xFFECFDF5), shape: BoxShape.circle),
              child: const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 48),
            ),
            const SizedBox(height: 16),
            Text('Harika! Vadesi Geçmiş Taksit Yok', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18, color: const Color(0xFF1E293B))),
            const SizedBox(height: 6),
            Text('Kurumdaki tüm öğrencilerin ödeme planları güncel durumdadır.', style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13)),
          ],
        ),
      );
    }

    final isAllSelected = _selectedOverdueIndices.length == _overdueInstallmentsList.length;

    final isMobile = MediaQuery.of(context).size.width < 900;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vadesi Geçmiş Taksitler & Veli Bildirimi', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: const Color(0xFF1E293B))),
                const SizedBox(height: 4),
                Text('Toplam ${_overdueInstallmentsList.length} adet taksitte gecikme bulunmaktadır.', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFECACA))),
                      child: Text('Toplam: ${_currencyFormat.format(_totalStudentOverdue)}', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFFDC2626))),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        final itemsToSend = _selectedOverdueIndices.isEmpty
                            ? _overdueInstallmentsList
                            : _selectedOverdueIndices.map((i) => _overdueInstallmentsList[i]).toList();
                        _openSendOverdueNotificationDialog(itemsToSend);
                      },
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: Text(
                        _selectedOverdueIndices.isEmpty
                            ? 'Tümüne Bildirim / SMS'
                            : 'Seçilenlere (${_selectedOverdueIndices.length}) Gönder',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vadesi Geçmiş Taksitler & Veli Bildirimi', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18, color: const Color(0xFF1E293B))),
                    const SizedBox(height: 4),
                    Text('Toplam ${_overdueInstallmentsList.length} adet taksitte gecikme bulunmaktadır.', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFECACA))),
                      child: Text('Toplam Geciken: ${_currencyFormat.format(_totalStudentOverdue)}', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: const Color(0xFFDC2626))),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        final itemsToSend = _selectedOverdueIndices.isEmpty
                            ? _overdueInstallmentsList
                            : _selectedOverdueIndices.map((i) => _overdueInstallmentsList[i]).toList();
                        _openSendOverdueNotificationDialog(itemsToSend);
                      },
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _selectedOverdueIndices.isEmpty
                            ? 'Tüm Velilere Bildirim / SMS Gönder'
                            : 'Seçilenlere (${_selectedOverdueIndices.length}) Bildirim / SMS Gönder',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 20),

          // Liste Kartı
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                // Başlık & Toplu Seçim Çubuğu
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isAllSelected,
                        activeColor: const Color(0xFF4F46E5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedOverdueIndices.clear();
                              for (int i = 0; i < _overdueInstallmentsList.length; i++) {
                                _selectedOverdueIndices.add(i);
                              }
                            } else {
                              _selectedOverdueIndices.clear();
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isAllSelected ? 'Tümünü Kaldır' : 'Tümünü Seç (${_overdueInstallmentsList.length})',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155)),
                      ),
                      const Spacer(),
                      Text(
                        'Seçilen: ${_selectedOverdueIndices.length} / ${_overdueInstallmentsList.length}',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),

                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _overdueInstallmentsList.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (context, idx) {
                    final item = _overdueInstallmentsList[idx];
                    final overdueDays = item['overdueDays'] as int;
                    final isSelected = _selectedOverdueIndices.contains(idx);

                    if (isMobile) {
                      return InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedOverdueIndices.remove(idx);
                            } else {
                              _selectedOverdueIndices.add(idx);
                            }
                          });
                        },
                        child: Container(
                          color: isSelected ? const Color(0xFFEEF2FF).withOpacity(0.5) : Colors.transparent,
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: isSelected,
                                    activeColor: const Color(0xFF4F46E5),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedOverdueIndices.add(idx);
                                        } else {
                                          _selectedOverdueIndices.remove(idx);
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item['studentName'], style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14)),
                                        Text('${item['installment']['title']} • Vade: ${item['dueDate']}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(6)),
                                    child: Text('$overdueDays Gün Gecikti', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 10, color: const Color(0xFFDC2626))),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_currencyFormat.format(item['amount']), style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 15, color: const Color(0xFF1E293B))),
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: () => _openSendOverdueNotificationDialog([item]),
                                        icon: const Icon(Icons.send_rounded, color: Color(0xFF4F46E5), size: 18),
                                        tooltip: 'SMS / Bildirim',
                                        style: IconButton.styleFrom(backgroundColor: const Color(0xFFEEF2FF)),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: () {
                                          setState(() {
                                            _selectedStudentIdForDetail = item['studentId'];
                                            _selectedStudentDataForDetail = {
                                              'id': item['studentId'],
                                              'fullName': item['studentName'],
                                              'studentNo': item['studentNo'],
                                              'institutionId': _institutionId,
                                            };
                                            _tabController.animateTo(1);
                                          });
                                        },
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                        child: const Text('Detay'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return InkWell(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedOverdueIndices.remove(idx);
                          } else {
                            _selectedOverdueIndices.add(idx);
                          }
                        });
                      },
                      child: Container(
                        color: isSelected ? const Color(0xFFEEF2FF).withOpacity(0.5) : Colors.transparent,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Checkbox(
                              value: isSelected,
                              activeColor: const Color(0xFF4F46E5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedOverdueIndices.add(idx);
                                  } else {
                                    _selectedOverdueIndices.remove(idx);
                                  }
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['studentName'], style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text('${item['installment']['title']} • Vade: ${item['dueDate']}', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8)),
                              child: Text('$overdueDays Gün Gecikti', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 11, color: const Color(0xFFDC2626))),
                            ),
                            const SizedBox(width: 20),
                            Text(_currencyFormat.format(item['amount']), style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 15, color: const Color(0xFF1E293B))),
                            const SizedBox(width: 12),
                            IconButton(
                              onPressed: () => _openSendOverdueNotificationDialog([item]),
                              icon: const Icon(Icons.send_rounded, color: Color(0xFF4F46E5), size: 20),
                              tooltip: 'Bu Veliye Bildirim / SMS Gönder',
                              style: IconButton.styleFrom(backgroundColor: const Color(0xFFEEF2FF)),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _selectedStudentIdForDetail = item['studentId'];
                                  _selectedStudentDataForDetail = {
                                    'id': item['studentId'],
                                    'fullName': item['studentName'],
                                    'studentNo': item['studentNo'],
                                    'institutionId': _institutionId,
                                  };
                                  _tabController.animateTo(1); // Öğrenci sekmesine geç
                                });
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, elevation: 0),
                              child: const Text('Öğrenciye Git'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openSendOverdueNotificationDialog(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen bildirim göndermek için en az bir geciken taksit seçiniz.')));
      return;
    }

    final templateCtrl = TextEditingController(
      text: 'Sayın Velimiz, {ogrenci_adi} isimli öğrencimizin {vade_tarihi} vadeli {tutar} tutarındaki taksit ödemesi {gecikme_gunu} gündür gecikmededir. Ödemenizi gerçekleştirmenizi veya kurumumuz muhasebe birimi ile iletişime geçmenizi rica ederiz.',
    );
    bool sendAppNotification = true;
    bool sendSms = true;
    bool isSending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 30, offset: Offset(0, -10))],
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 12,
            left: 24,
            right: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(10)),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: const Icon(Icons.notifications_active_rounded, color: Color(0xFFDC2626), size: 24),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Veliye Gecikme Bildirimi & SMS Gönder', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
                          const SizedBox(height: 2),
                          Text('${items.length} adet geciken taksit velisine hatırlatma gönderilecek', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                        ],
                      ),
                    ],
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B))),
                ],
              ),
              const SizedBox(height: 20),

              // Gönderim Kanalları
              Text('Gönderim Kanalları (Sadece Veli Hesabına Gider)', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SwitchListTile(
                      value: sendAppNotification,
                      activeColor: const Color(0xFF4F46E5),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: sendAppNotification ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0))),
                      title: Text('Mobil & Web Bildirimi', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                      subtitle: Text('Veli hesabına düşer', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                      onChanged: (v) => setModal(() => sendAppNotification = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SwitchListTile(
                      value: sendSms,
                      activeColor: const Color(0xFF10B981),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: sendSms ? const Color(0xFF10B981) : const Color(0xFFE2E8F0))),
                      title: Text('SMS Hatırlatması', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                      subtitle: Text('Veli telefonuna SMS', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                      onChanged: (v) => setModal(() => sendSms = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Mesaj Şablonu
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Mesaj Metni & Şablonu', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
                  Text('Etiketler: {ogrenci_adi}, {tutar}, {vade_tarihi}, {gecikme_gunu}', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: templateCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Mesaj metnini düzenleyiniz...',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2)),
                ),
              ),
              const SizedBox(height: 24),

              // Gönder Butonu
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: isSending
                      ? null
                      : () async {
                          if (!sendAppNotification && !sendSms) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen en az bir gönderim kanalı seçiniz.')));
                            return;
                          }
                          setModal(() => isSending = true);

                          int count = 0;
                          final rawTemplate = templateCtrl.text.trim();

                          for (final item in items) {
                            final studentName = item['studentName'] ?? 'Öğrenci';
                            final dueDateStr = item['dueDate'] ?? '';
                            final amountStr = _currencyFormat.format(item['amount']);
                            final overdueDays = item['overdueDays']?.toString() ?? '0';

                            final msgBody = rawTemplate
                                .replaceAll('{ogrenci_adi}', studentName)
                                .replaceAll('{vade_tarihi}', dueDateStr)
                                .replaceAll('{tutar}', amountStr)
                                .replaceAll('{gecikme_gunu}', overdueDays);

                            // 1. Veliye Bildirim Kaydı Ekle (notifications koleksiyonu)
                            if (sendAppNotification) {
                              await FirebaseFirestore.instance.collection('notifications').add({
                                'institutionId': _institutionId,
                                'studentId': item['studentId'],
                                'studentName': studentName,
                                'targetRole': 'parent',
                                'type': 'overdue_payment_reminder',
                                'title': '⚠️ Geciken Taksit Ödeme Hatırlatması',
                                'body': msgBody,
                                'amount': item['amount'],
                                'dueDate': dueDateStr,
                                'overdueDays': item['overdueDays'],
                                'createdAt': FieldValue.serverTimestamp(),
                                'isRead': false,
                              });
                            }

                            // 2. SMS Kaydı Ekle (sms_queue koleksiyonu)
                            if (sendSms) {
                              await FirebaseFirestore.instance.collection('sms_queue').add({
                                'institutionId': _institutionId,
                                'studentId': item['studentId'],
                                'studentName': studentName,
                                'targetRole': 'parent',
                                'type': 'overdue_payment_reminder',
                                'message': msgBody,
                                'status': 'queued',
                                'createdAt': FieldValue.serverTimestamp(),
                              });
                            }

                            count++;
                          }

                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✓ Toplam $count adet veliye gecikme bildirimi başarıyla iletildi.'),
                              backgroundColor: const Color(0xFF10B981),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                  icon: isSending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send_rounded, size: 20),
                  label: Text(
                    isSending ? 'BİLDİRİMLER GÖNDERİLİYOR...' : 'BİLDİRİMLERİ VE SMS\'LERİ GÖNDER (${items.length} VELİ)',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. SEKME: KASA VE GENEL GELİR/GİDER HAREKETLERİ
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildCashAndTransactionsTab() {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kasa & Genel Hareketler', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: const Color(0xFF1E293B))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _openTransactionDialog('income'),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Gelir Ekle'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, elevation: 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _openTransactionDialog('expense'),
                        icon: const Icon(Icons.remove_rounded, size: 18),
                        label: const Text('Gider Ekle'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white, elevation: 0),
                      ),
                    ),
                  ],
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Kasa & Genel Hareketler', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18, color: const Color(0xFF1E293B))),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _openTransactionDialog('income'),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Gelir Ekle'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, elevation: 0),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openTransactionDialog('expense'),
                      icon: const Icon(Icons.remove_rounded, size: 18),
                      label: const Text('Gider Ekle'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white, elevation: 0),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 20),

          // Kasalar Listesi
          LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _cashes.map((k) {
                  final bal = (k['balance'] as num?)?.toDouble() ?? 0.0;
                  final isBank = k['type'] == 'bank';

                  return Container(
                    width: constraints.maxWidth > 800 ? (constraints.maxWidth - 24) / 3 : constraints.maxWidth,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6)],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isBank ? const Color(0xFFEEF2FF) : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(isBank ? Icons.account_balance_rounded : Icons.payments_rounded, color: isBank ? const Color(0xFF4F46E5) : const Color(0xFFD97706), size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(k['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF64748B))),
                              const SizedBox(height: 4),
                              Text(_currencyFormat.format(bal), style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 18, color: const Color(0xFF1E293B))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),

          // İşlem Listesi
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2E8F0))),
            child: _recentTransactions.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(40), child: Text('Henüz gelir/gider hareketi bulunmuyor.')))
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _recentTransactions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final t = _recentTransactions[idx];
                      final isIncome = t['type'] == 'income';
                      final date = t['date'] is Timestamp ? (t['date'] as Timestamp).toDate() : DateTime.now();

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isIncome ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                          child: Icon(isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444), size: 18),
                        ),
                        title: Text(t['description'] ?? 'İşlem', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                        subtitle: Text('${DateFormat('dd.MM.yyyy HH:mm').format(date)} • ${t['kasaName'] ?? ''}', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                        trailing: Text(
                          (isIncome ? '+ ' : '- ') + _currencyFormat.format(t['amount']),
                          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openAddKasaDialog() {
    final nameCtrl = TextEditingController();
    final balCtrl = TextEditingController(text: '0,00');
    String selectedType = 'cash'; // 'cash' or 'bank'

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 30, offset: Offset(0, -10))],
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 12,
            left: 24,
            right: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(10)),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFC7D2FE)),
                    ),
                    child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF4F46E5), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Yeni Kasa / Hesap Tanımla', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('Farklı birim veya banka POS hesabı ekleyin', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 20)),
                ],
              ),
              const SizedBox(height: 24),

              // Kasa / Hesap Adı
              Text('Kasa / Hesap Adı', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                decoration: InputDecoration(
                  hintText: 'Örn: Ziraat Bankası POS, Kantin Kasası, vb.',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2)),
                ),
              ),
              const SizedBox(height: 16),

              // Hesap Türü
              Text('Hesap Türü', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2)),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'cash',
                    child: Row(
                      children: [
                        Icon(Icons.payments_rounded, color: Color(0xFFD97706), size: 18),
                        SizedBox(width: 8),
                        Text('Nakit Kasa (Elden Tahsilat)'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'bank',
                    child: Row(
                      children: [
                        Icon(Icons.account_balance_rounded, color: Color(0xFF4F46E5), size: 18),
                        SizedBox(width: 8),
                        Text('Banka / POS / Havale Hesabı'),
                      ],
                    ),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setModal(() => selectedType = v);
                },
              ),
              const SizedBox(height: 16),

              // Açılış Bakiyesi
              Text('Açılış / Mevcut Bakiye (₺)', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
              const SizedBox(height: 6),
              TextField(
                controller: balCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [TurkishCurrencyInputFormatter()],
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF4F46E5)),
                decoration: InputDecoration(
                  hintText: '0,00',
                  suffixText: '₺',
                  suffixStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF64748B)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2)),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lütfen kasa/hesap adını giriniz.')));
                      return;
                    }
                    final cleanText = balCtrl.text.replaceAll('.', '').replaceAll(',', '.').replaceAll(' ', '').trim();
                    final initialBal = double.tryParse(cleanText) ?? 0.0;

                    await FirebaseFirestore.instance.collection('cashes').add({
                      'institutionId': _institutionId,
                      'name': name,
                      'type': selectedType,
                      'balance': initialBal,
                      'createdAt': FieldValue.serverTimestamp(),
                    });

                    Navigator.pop(ctx);
                    _refreshData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('✓ "$name" hesabı başarıyla tanımlandı.'), backgroundColor: const Color(0xFF10B981)),
                    );
                  },
                  icon: const Icon(Icons.check_circle_rounded, size: 20),
                  label: Text('KASAYI OLUŞTUR VE KAYDET', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openReportingCenterDialog() {
    String selectedReportType = 'general'; // 'general', 'student_plans', 'overdue', 'transactions'
    DateTimeRange? selectedDateRange;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 30, offset: Offset(0, -10))],
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 12,
            left: 24,
            right: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(10)),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF6366F1)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.print_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Finans & Muhasebe Rapor Merkezi', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('PDF veya Excel formatında resmi ve detaylı finansal raporlar', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 20)),
                ],
              ),
              const SizedBox(height: 20),

              // Tarih Aralığı Seçimi
              Text('Rapor Tarih Aralığı', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  final range = await CustomDateRangePicker.showRange(
                    context,
                    initialRange: selectedDateRange ?? DateTimeRange(
                      start: DateTime.now().subtract(const Duration(days: 30)),
                      end: DateTime.now(),
                    ),
                  );
                  if (range != null) {
                    setModal(() => selectedDateRange = range);
                  }
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, color: Color(0xFF4F46E5), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          selectedDateRange != null
                              ? '${_dateFormat.format(selectedDateRange!.start)} - ${_dateFormat.format(selectedDateRange!.end)}'
                              : 'Tüm Zamanlar / Tüm Kayıtlar (Tarih Seçmek İçin Tıklayın)',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: selectedDateRange != null ? const Color(0xFF1E293B) : const Color(0xFF64748B)),
                        ),
                      ),
                      if (selectedDateRange != null)
                        IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => setModal(() => selectedDateRange = null),
                        )
                      else
                        const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Rapor Türü Seçimi
              Text('Rapor Türü', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
              const SizedBox(height: 10),
              _buildReportTypeOption(
                value: 'general',
                selected: selectedReportType,
                title: 'Genel Finans ve Tahsilat Özeti',
                desc: 'Tüm sözleşmeler, tahsilat oranı, kasa bakiyeleri ve mali özet tablosu',
                icon: Icons.dashboard_customize_rounded,
                onTap: () => setModal(() => selectedReportType = 'general'),
              ),
              const SizedBox(height: 8),
              _buildReportTypeOption(
                value: 'overdue',
                selected: selectedReportType,
                title: 'Vadesi Geçmiş Taksitler & Borçlular Listesi',
                desc: 'Gecikmede olan taksitler, gecikme günleri ve veli borç bakiyeleri',
                icon: Icons.warning_amber_rounded,
                onTap: () => setModal(() => selectedReportType = 'overdue'),
              ),
              const SizedBox(height: 8),
              _buildReportTypeOption(
                value: 'transactions',
                selected: selectedReportType,
                title: 'Kasa & Banka Gelir/Gider Hareket Dökümü',
                desc: 'Seçilen aralıktaki tüm para giriş-çıkışları, makbuzlar ve kasa akışı',
                icon: Icons.receipt_long_rounded,
                onTap: () => setModal(() => selectedReportType = 'transactions'),
              ),
              const SizedBox(height: 24),

              // İndirme ve Yazdırma Aksiyonları (PDF / Excel)
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final instName = userData?['schoolName'] ?? userData?['institutionName'] ?? 'eduKN Eğitim Kurumları';

                          if (selectedReportType == 'general') {
                            await FinancialReportService.printGeneralSummaryPdf(
                              institutionName: instName,
                              totalContract: _totalStudentContract,
                              totalCollected: _totalStudentCollected,
                              totalRemaining: _totalStudentRemaining,
                              totalOverdue: _totalStudentOverdue,
                              totalCash: _totalCashBalance,
                              cashes: _cashes,
                              plans: _allPaymentPlans,
                              transactions: _recentTransactions,
                              dateRange: selectedDateRange,
                            );
                          } else if (selectedReportType == 'overdue') {
                            await FinancialReportService.printOverdueInstallmentsPdf(
                              institutionName: instName,
                              overdueList: _overdueInstallmentsList,
                              totalOverdue: _totalStudentOverdue,
                            );
                          } else if (selectedReportType == 'transactions') {
                            await FinancialReportService.printTransactionsPdf(
                              institutionName: instName,
                              transactions: _recentTransactions,
                              dateRange: selectedDateRange,
                            );
                          }
                        },
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                        label: Text('PDF Yazdır', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final instName = userData?['schoolName'] ?? userData?['institutionName'] ?? 'eduKN Eğitim Kurumları';

                          if (selectedReportType == 'general') {
                            await FinancialReportService.exportGeneralSummaryExcel(
                              institutionName: instName,
                              totalContract: _totalStudentContract,
                              totalCollected: _totalStudentCollected,
                              totalRemaining: _totalStudentRemaining,
                              totalOverdue: _totalStudentOverdue,
                              plans: _allPaymentPlans,
                              cashes: _cashes,
                              transactions: _recentTransactions,
                            );
                          } else if (selectedReportType == 'overdue') {
                            await FinancialReportService.exportOverdueExcel(
                              institutionName: instName,
                              overdueList: _overdueInstallmentsList,
                            );
                          } else if (selectedReportType == 'transactions') {
                            await FinancialReportService.exportTransactionsExcel(
                              institutionName: instName,
                              transactions: _recentTransactions,
                            );
                          }

                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✓ Excel (.xlsx) raporu başarıyla oluşturuldu ve indirildi.'),
                                backgroundColor: Color(0xFF10B981),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.table_view_rounded, size: 18),
                        label: Text('Excel İndir', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportTypeOption({
    required String value,
    required String selected,
    required String title,
    required String desc,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isSelected = selected == value;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0), width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: isSelected ? Colors.white : const Color(0xFF64748B), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF1E293B))),
                  const SizedBox(height: 2),
                  Text(desc, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: selected,
              onChanged: (_) => onTap(),
              activeColor: const Color(0xFF4F46E5),
            ),
          ],
        ),
      ),
    );
  }

  void _openTransactionDialog(String type) {
    final isIncome = type == 'income';
    final descCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    String? selectedKasaId = _cashes.isNotEmpty ? _cashes.first['id'] : null;
    final incomeCategories = ['Öğrenci Kayıt / Kurs', 'Yemek / Kantin', 'Servis / Ulaşım', 'Kitap & Kırtasiye', 'Etkinlik / Organizasyon', 'Diğer Gelir'];
    final expenseCategories = ['Personel & Maaş', 'Kira / Bina Gideri', 'Elektrik, Su, Doğalgaz', 'Kırtasiye & Malzeme', 'Yemek & Mutfak', 'Servis & Yakıt', 'Bakım & Onarım', 'Reklam & Tanıtım', 'Vergi / Resmi Harç', 'Genel Gider', 'Diğer Gider'];
    String selectedCategory = isIncome ? incomeCategories.first : expenseCategories.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 30, offset: Offset(0, -10)),
            ],
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 12,
            left: 24,
            right: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst Sürükleme Çubuğu
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Başlık & İkon
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isIncome ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isIncome ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                          ),
                        ),
                        child: Icon(
                          isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          color: isIncome ? const Color(0xFF059669) : const Color(0xFFDC2626),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isIncome ? 'Yeni Gelir Hareketi Ekle' : 'Yeni Gider Hareketi Ekle',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isIncome ? 'Kasaya veya banka hesabına para girişi işleyin' : 'Kasadan veya banka hesabından harcama/çıkış işleyin',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Tutar Alanı
              Text('İşlem Tutarı (₺)', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
              const SizedBox(height: 6),
              TextField(
                controller: amtCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [TurkishCurrencyInputFormatter()],
                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w900, color: isIncome ? const Color(0xFF059669) : const Color(0xFFDC2626)),
                decoration: InputDecoration(
                  hintText: '0,00',
                  suffixText: '₺',
                  suffixStyle: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF64748B)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444), width: 2)),
                ),
              ),
              const SizedBox(height: 16),

              // Kasa / Banka Seçimi
              Text('Hedef Kasa / Hesap', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: selectedKasaId,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
                items: _cashes.map((k) => DropdownMenuItem(
                  value: k['id'] as String,
                  child: Row(
                    children: [
                      Icon(k['type'] == 'bank' ? Icons.account_balance_rounded : Icons.payments_rounded, size: 18, color: const Color(0xFF4F46E5)),
                      const SizedBox(width: 10),
                      Text(k['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(width: 10),
                      Text('(${_currencyFormat.format((k['balance'] as num?)?.toDouble() ?? 0)})', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                    ],
                  ),
                )).toList(),
                onChanged: (v) => setModal(() => selectedKasaId = v),
              ),
              const SizedBox(height: 16),

              // Kategori Seçimi
              Text('Kategori / İşlem Türü', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
                items: (isIncome ? incomeCategories : expenseCategories).map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                )).toList(),
                onChanged: (v) {
                  if (v != null) setModal(() => selectedCategory = v);
                },
              ),
              const SizedBox(height: 16),

              // Açıklama
              Text('Açıklama / Not', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
              const SizedBox(height: 6),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  hintText: 'İşlem ile ilgili detaylı bilgi girin...',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
              ),
              const SizedBox(height: 24),

              // Kaydet Butonu
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final cleanText = amtCtrl.text.replaceAll('.', '').replaceAll(',', '.').replaceAll(' ', '').trim();
                    final amt = double.tryParse(cleanText) ?? 0.0;
                    if (amt <= 0 || selectedKasaId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Lütfen geçerli bir tutar ve kasa seçiniz.')),
                      );
                      return;
                    }

                    final data = {
                      'institutionId': _institutionId,
                      'type': type,
                      'category': selectedCategory,
                      'description': descCtrl.text.trim().isEmpty ? selectedCategory : descCtrl.text.trim(),
                      'amount': amt,
                      'kasaId': selectedKasaId,
                      'kasaName': _cashes.firstWhere((k) => k['id'] == selectedKasaId)['name'],
                      'date': FieldValue.serverTimestamp(),
                      'userId': FirebaseAuth.instance.currentUser?.uid,
                    };

                    await FirebaseFirestore.instance.collection('transactions').add(data);
                    final kasaRef = FirebaseFirestore.instance.collection('cashes').doc(selectedKasaId);
                    await FirebaseFirestore.instance.runTransaction((tx) async {
                      final snap = await tx.get(kasaRef);
                      final oldBal = (snap['balance'] as num?)?.toDouble() ?? 0.0;
                      tx.update(kasaRef, {'balance': isIncome ? oldBal + amt : oldBal - amt});
                    });

                    Navigator.pop(ctx);
                    _refreshData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✓ ${isIncome ? 'Gelir' : 'Gider'} kaydı başarıyla eklendi.'),
                        backgroundColor: isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: Icon(isIncome ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded, size: 20),
                  label: Text(
                    isIncome ? 'GELİR HAREKETİNİ KAYDET' : 'GİDER HAREKETİNİ KAYDET',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
