import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/financial_report_service.dart';

class ParentAccountingScreen extends StatefulWidget {
  final String institutionId;
  final String studentId;
  final String studentName;
  final String studentNo;

  const ParentAccountingScreen({
    Key? key,
    required this.institutionId,
    required this.studentId,
    required this.studentName,
    this.studentNo = '',
  }) : super(key: key);

  @override
  State<ParentAccountingScreen> createState() => _ParentAccountingScreenState();
}

class _ParentAccountingScreenState extends State<ParentAccountingScreen> {
  final NumberFormat _currencyFormat =
      NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');

  bool _isLoading = true;
  List<Map<String, dynamic>> _paymentPlans = [];
  double _totalContract = 0.0;
  double _totalPaid = 0.0;
  double _totalRemaining = 0.0;
  double _totalOverdue = 0.0;

  @override
  void initState() {
    super.initState();
    _loadStudentPaymentPlans();
  }

  Future<void> _loadStudentPaymentPlans() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('payment_plans')
          .where('studentId', isEqualTo: widget.studentId)
          .get();

      final plans = snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();

      double contract = 0;
      double paid = 0;
      double overdue = 0;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (final plan in plans) {
        final net = (plan['netTotal'] ?? plan['totalAmount'] ?? 0).toDouble();
        final downPayment = (plan['downPayment'] ?? 0).toDouble();
        final downPaymentPaid = plan['downPaymentPaid'] == true;

        contract += net;
        if (downPaymentPaid) paid += downPayment;

        final installments = List<Map<String, dynamic>>.from(
            (plan['installments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));

        for (final inst in installments) {
          final amt = (inst['amount'] ?? 0).toDouble();
          final isPaid = inst['status'] == 'paid';
          final dueDateStr = inst['dueDate']?.toString() ?? '';

          if (isPaid) {
            paid += amt;
          } else {
            DateTime? dueDate;
            try {
              if (dueDateStr.contains('.')) {
                final parts = dueDateStr.split('.');
                if (parts.length == 3) {
                  dueDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                }
              }
            } catch (_) {}

            if (dueDate != null && dueDate.isBefore(today)) {
              overdue += amt;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _paymentPlans = plans;
          _totalContract = contract;
          _totalPaid = paid;
          _totalRemaining = (contract - paid).clamp(0.0, double.infinity);
          _totalOverdue = overdue;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading parent payment plans: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalContract > 0 ? (_totalPaid / _totalContract).clamp(0.0, 1.0) : 0.0;
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Öğrenci Mali Durum & Taksit Takibi',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
            ),
            Text(
              widget.studentName + (widget.studentNo.isNotEmpty ? ' (${widget.studentNo})' : ''),
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: const Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF4F46E5)),
            onPressed: _loadStudentPaymentPlans,
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))
          : _paymentPlans.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: const BoxDecoration(color: Color(0xFFEEF2FF), shape: BoxShape.circle),
                        child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF4F46E5), size: 48),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Henüz Kayıtlı Bir Ödeme Planı Bulunmuyor',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Öğrencinize ait sözleşme ve taksit tanımlandığında burada görüntülenecektir.',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Özet Metrik Kartları
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final contractCard = _buildMetricCard(
                            'Toplam Sözleşme',
                            _currencyFormat.format(_totalContract),
                            Icons.receipt_long_rounded,
                            const Color(0xFF4F46E5),
                            const Color(0xFFEEF2FF),
                          );
                          final paidCard = _buildMetricCard(
                            'Ödenen Tutar',
                            _currencyFormat.format(_totalPaid),
                            Icons.check_circle_rounded,
                            const Color(0xFF10B981),
                            const Color(0xFFECFDF5),
                          );
                          final remainingCard = _buildMetricCard(
                            'Kalan Borç Bakiyesi',
                            _currencyFormat.format(_totalRemaining),
                            Icons.hourglass_top_rounded,
                            const Color(0xFF0284C7),
                            const Color(0xFFF0F9FF),
                          );
                          final overdueCard = _buildMetricCard(
                            'Vadesi Geçmiş Tutar',
                            _currencyFormat.format(_totalOverdue),
                            Icons.warning_amber_rounded,
                            _totalOverdue > 0 ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                            _totalOverdue > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                          );

                          if (isMobile) {
                            return Column(
                              children: [
                                Row(children: [Expanded(child: contractCard), const SizedBox(width: 12), Expanded(child: paidCard)]),
                                const SizedBox(height: 12),
                                Row(children: [Expanded(child: remainingCard), const SizedBox(width: 12), Expanded(child: overdueCard)]),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: contractCard),
                              const SizedBox(width: 12),
                              Expanded(child: paidCard),
                              const SizedBox(width: 12),
                              Expanded(child: remainingCard),
                              const SizedBox(width: 12),
                              Expanded(child: overdueCard),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // İlerleme Çubuğu
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Toplam Ödeme İlerlemesi',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155)),
                                ),
                                Text(
                                  '%${(progress * 100).toStringAsFixed(1)} Tamamlandı',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF10B981)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 10,
                                backgroundColor: const Color(0xFFF1F5F9),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Planlar ve Taksit Tabloları
                      ..._paymentPlans.map((plan) => _buildPlanCard(plan)).toList(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.all(16),
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
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11, color: const Color(0xFF64748B))),
                const SizedBox(height: 4),
                Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 15, color: const Color(0xFF1E293B))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final name = plan['name'] ?? 'Ödeme Sözleşmesi';
    final netTotal = (plan['netTotal'] ?? plan['totalAmount'] ?? 0).toDouble();
    final downPayment = (plan['downPayment'] ?? 0).toDouble();
    final downPaymentPaid = plan['downPaymentPaid'] == true;
    final installments = List<Map<String, dynamic>>.from(
        (plan['installments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF4F46E5), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: const Color(0xFF1E293B))),
                        const SizedBox(height: 2),
                        Text(
                          'Sözleşme Tutarı: ${_currencyFormat.format(netTotal)}',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Peşinat Satırı (varsa)
          if (downPayment > 0) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: downPaymentPaid ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      downPaymentPaid ? Icons.check_circle_rounded : Icons.pending_rounded,
                      color: downPaymentPaid ? const Color(0xFF10B981) : const Color(0xFFD97706),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Peşinat Ödemesi', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text('Kayıt Anında Peşin', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: downPaymentPaid ? const Color(0xFFECFDF5) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      downPaymentPaid ? 'ÖDENDİ' : 'ÖDENMEDİ',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: downPaymentPaid ? const Color(0xFF059669) : const Color(0xFFD97706),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(_currencyFormat.format(downPayment), style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14)),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
          ],

          // Taksitler Listesi
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: installments.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (context, idx) {
              final inst = installments[idx];
              final title = inst['title'] ?? '${idx + 1}. Taksit';
              final amt = (inst['amount'] ?? 0).toDouble();
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

              final isOverdue = !isPaid && dueDate != null && dueDate.isBefore(today);

              Color statusBg = const Color(0xFFF1F5F9);
              Color statusColor = const Color(0xFF64748B);
              String statusText = 'VADESİ GELMEDİ';
              IconData statusIcon = Icons.schedule_rounded;

              if (isPaid) {
                statusBg = const Color(0xFFECFDF5);
                statusColor = const Color(0xFF059669);
                statusText = 'ÖDENDİ';
                statusIcon = Icons.check_circle_rounded;
              } else if (isOverdue) {
                statusBg = const Color(0xFFFEF2F2);
                statusColor = const Color(0xFFDC2626);
                final days = today.difference(dueDate).inDays;
                statusText = '$days GÜN GECİKTİ';
                statusIcon = Icons.error_outline_rounded;
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(10)),
                      child: Icon(statusIcon, color: statusColor, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text('Vade: $dueDateStr', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        statusText,
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      _currencyFormat.format(amt),
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: isPaid ? const Color(0xFF059669) : (isOverdue ? const Color(0xFFDC2626) : const Color(0xFF1E293B)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
