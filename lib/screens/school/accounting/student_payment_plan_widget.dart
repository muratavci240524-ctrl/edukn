import 'package:flutter/material.dart';
import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:ui';
import '../../../widgets/custom_date_range_picker.dart';

/// Türk Lirası Canlı Para Formatlayıcı (2000 -> 2.000, 2000,50 -> 2.000,50)
class TurkishCurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    String clean = newValue.text.replaceAll('.', '').replaceAll(' ', '');

    String integerPart = clean;
    String? decimalPart;

    if (clean.contains(',')) {
      final parts = clean.split(',');
      integerPart = parts[0];
      if (parts.length > 1) {
        decimalPart = parts[1];
        if (decimalPart.length > 2) decimalPart = decimalPart.substring(0, 2);
      }
    }

    integerPart = integerPart.replaceAll(RegExp(r'[^0-9]'), '');
    if (integerPart.isEmpty && decimalPart == null) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }

    String formattedInt = '';
    if (integerPart.isNotEmpty) {
      final val = int.tryParse(integerPart) ?? 0;
      formattedInt = NumberFormat('#,###', 'tr_TR').format(val);
    } else {
      formattedInt = '0';
    }

    String result = formattedInt;
    if (decimalPart != null) {
      result = '$formattedInt,$decimalPart';
    }

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}

double parseCurrency(String? text) {
  if (text == null || text.trim().isEmpty) return 0.0;
  String clean = text.replaceAll('.', '').replaceAll(',', '.').replaceAll('₺', '').replaceAll(' ', '').trim();
  return double.tryParse(clean) ?? 0.0;
}

String formatCurrencyText(double amt) {
  return NumberFormat('#,##0.00', 'tr_TR').format(amt);
}

class StudentPaymentPlanWidget extends StatefulWidget {
  final String studentId;
  final Map<String, dynamic>? studentData;
  final String? institutionId;

  const StudentPaymentPlanWidget({
    Key? key,
    required this.studentId,
    this.studentData,
    this.institutionId,
  }) : super(key: key);

  @override
  _StudentPaymentPlanWidgetState createState() =>
      _StudentPaymentPlanWidgetState();
}

class _StudentPaymentPlanWidgetState extends State<StudentPaymentPlanWidget> {
  final NumberFormat _currencyFormat =
      NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');

  bool _isCreatingPlan = false;
  Map<String, dynamic>? _preRegSettings;
  bool _isLoadingSettings = false;

  @override
  void initState() {
    super.initState();
    _loadPreRegistrationSettings();
  }

  Future<void> _loadPreRegistrationSettings() async {
    final instId = widget.institutionId ?? widget.studentData?['institutionId'];
    if (instId == null || instId.isEmpty) return;

    setState(() => _isLoadingSettings = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('preRegistrationSettings')
          .doc(instId)
          .get();

      if (doc.exists && doc.data() != null) {
        setState(() {
          _preRegSettings = doc.data();
        });
      }
    } catch (e) {
      debugPrint('PreReg settings load error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingSettings = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCreatingPlan) {
      return _FullOfferPaymentPlanBuilder(
        studentId: widget.studentId,
        studentData: widget.studentData,
        institutionId: widget.institutionId ?? widget.studentData?['institutionId'],
        preRegSettings: _preRegSettings,
        onCancel: () => setState(() => _isCreatingPlan = false),
        onSaved: () {
          setState(() => _isCreatingPlan = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Ödeme planı ve sözleşme başarıyla kaydedildi'),
              backgroundColor: Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
    }

    final isDesktop = MediaQuery.of(context).size.width >= 750;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('payment_plans')
          .where('studentId', isEqualTo: widget.studentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('❌ payment_plans Stream error: ${snapshot.error}');
          return _buildPlansDashboard([], isDesktop);
        }

        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40.0),
              child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
            ),
          );
        }

        final plans = snapshot.data!.docs;
        return _buildPlansDashboard(plans, isDesktop);
      },
    );
  }

  Widget _buildPlansDashboard(List<QueryDocumentSnapshot> plans, bool isDesktop) {
    if (plans.isEmpty) {
      return _buildEmptyStateView(isDesktop);
    }

    double totalContract = 0;
    double totalCollected = 0;
    double totalOverdue = 0;
    int totalInstallments = 0;
    int paidInstallments = 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (var doc in plans) {
      final data = doc.data() as Map<String, dynamic>;
      final netAmount = (data['netTotal'] ?? data['totalAmount'] ?? 0).toDouble();
      totalContract += netAmount;

      final downPayment = (data['downPayment'] ?? 0).toDouble();
      if (data['downPaymentPaid'] == true) {
        totalCollected += downPayment;
      }

      final installments = List<Map<String, dynamic>>.from(
          (data['installments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));

      totalInstallments += installments.length;

      for (var inst in installments) {
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
          totalCollected += amount;
          paidInstallments++;
        } else if (dueDate != null && dueDate.isBefore(today)) {
          totalOverdue += amount;
        }
      }
    }

    final remainingDebt = (totalContract - totalCollected).clamp(0.0, double.infinity);
    final progress = totalContract > 0 ? (totalCollected / totalContract).clamp(0.0, 1.0) : 0.0;

    final isMobileView = MediaQuery.of(context).size.width < 500;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobileView ? 10 : 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Responsive Header
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 780;
              return Container(
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 14 : 20, vertical: isCompact ? 14 : 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E1B4B), Color(0xFF3730A3), Color(0xFF4F46E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withOpacity(0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(isCompact ? 10 : 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: isCompact ? 22 : 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Öğrenci Muhasebe & Taksit Takip',
                            style: GoogleFonts.inter(
                              fontSize: isCompact ? 15 : 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ön Kayıt standartlarında fiyatlandırma, burs/indirim ve tahsilat dökümleri',
                            style: GoogleFonts.inter(fontSize: isCompact ? 11 : 12, color: Colors.indigo.shade100),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (isCompact)
                      Tooltip(
                        message: 'Yeni Plan / Sözleşme Oluştur',
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openPlanBuilder(isDesktop),
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(Icons.add_rounded, color: Color(0xFF312E81), size: 22),
                            ),
                          ),
                        ),
                      )
                    else
                      Tooltip(
                        message: 'Yeni Plan / Sözleşme Oluştur',
                        child: ElevatedButton.icon(
                          onPressed: () => _openPlanBuilder(isDesktop),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('Yeni Plan / Sözleşme Oluştur'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF312E81),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                            textStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          // Overview Dashboard Card
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 850;
              final contractCard = _buildMetricCard('Toplam Sözleşme', _currencyFormat.format(totalContract), Icons.receipt_long_rounded, const Color(0xFF4F46E5), const Color(0xFFEEF2FF));
              final collectedCard = _buildMetricCard('Tahsil Edilen', _currencyFormat.format(totalCollected), Icons.check_circle_rounded, const Color(0xFF10B981), const Color(0xFFECFDF5));
              final remainingCard = _buildMetricCard('Kalan Bakiye', _currencyFormat.format(remainingDebt), Icons.hourglass_top_rounded, const Color(0xFF0284C7), const Color(0xFFF0F9FF));
              final overdueCard = _buildMetricCard('Geciken Taksitler', _currencyFormat.format(totalOverdue), Icons.error_outline_rounded, totalOverdue > 0 ? const Color(0xFFEF4444) : const Color(0xFF64748B), totalOverdue > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC));

              return Container(
                padding: EdgeInsets.all(isNarrow ? 12 : 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    if (isNarrow) ...[
                      Row(
                        children: [
                          Expanded(child: contractCard),
                          const SizedBox(width: 8),
                          Expanded(child: collectedCard),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: remainingCard),
                          const SizedBox(width: 8),
                          Expanded(child: overdueCard),
                        ],
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(child: contractCard),
                          const SizedBox(width: 14),
                          Expanded(child: collectedCard),
                          const SizedBox(width: 14),
                          Expanded(child: remainingCard),
                          const SizedBox(width: 14),
                          Expanded(child: overdueCard),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Tahsilat: %${(progress * 100).toStringAsFixed(1)}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF334155),
                          ),
                        ),
                        Text(
                          '$paidInstallments / $totalInstallments Taksit',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Plan Cards
          ...plans.map((doc) => _buildPlanRecordCard(doc.id, doc.data() as Map<String, dynamic>)).toList(),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  void _openPlanBuilder(bool isDesktop) {
    if (isDesktop) {
      setState(() => _isCreatingPlan = true);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: EduknAppBar(title: 'Ödeme Planı & Sözleşme'),
            body: _FullOfferPaymentPlanBuilder(
              studentId: widget.studentId,
              studentData: widget.studentData,
              institutionId: widget.institutionId ?? widget.studentData?['institutionId'],
              preRegSettings: _preRegSettings,
              onCancel: () => Navigator.pop(context),
              onSaved: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✓ Ödeme planı ve sözleşme kaydedildi'),
                    backgroundColor: Color(0xFF10B981),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
  }

  Widget _buildEmptyStateView(bool isDesktop) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 550),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFC7D2FE), width: 2),
              ),
              child: const Icon(Icons.calculate_rounded, size: 54, color: Color(0xFF4F46E5)),
            ),
            const SizedBox(height: 24),
            Text(
              'Henüz Ödeme Planı Bulunmuyor',
              style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 10),
            Text(
              'Ön Kayıt sistemindeki standart sınıf ücretleri, çoklu indirim/burs seçenekleri ve bağımsız kalem taksit robotunu kullanarak öğrenciye özel resmi ödeme planı ve sözleşme oluşturun.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), height: 1.6),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => _openPlanBuilder(isDesktop),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('Ödeme Planı Robotunu Başlat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanRecordCard(String planId, Map<String, dynamic> data) {
    final name = data['name'] ?? 'Ödeme Sözleşmesi';
    final netTotal = (data['netTotal'] ?? data['totalAmount'] ?? 0).toDouble();
    final downPayment = (data['downPayment'] ?? 0).toDouble();
    final downPaymentPaid = data['downPaymentPaid'] == true;
    final isUnified = data['isUnifiedPlan'] == true;
    final items = List<Map<String, dynamic>>.from((data['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
    final discounts = List<Map<String, dynamic>>.from((data['appliedDiscounts'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
    final installments = List<Map<String, dynamic>>.from((data['installments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));

    double collected = downPaymentPaid ? downPayment : 0;
    for (var inst in installments) {
      if (inst['status'] == 'paid') collected += (inst['amount'] ?? 0).toDouble();
    }
    final remaining = (netTotal - collected).clamp(0.0, double.infinity);

    // Taksitleri kategorilere göre grupla
    final Map<String, List<Map<String, dynamic>>> groupedInstallments = {};
    if (isUnified) {
      groupedInstallments['Ortak / Birleşik Taksit Planı'] = installments;
    } else {
      for (var inst in installments) {
        final cat = (inst['category'] ?? 'Genel').toString();
        groupedInstallments.putIfAbsent(cat, () => []).add(inst);
      }
    }

    final isMobile = MediaQuery.of(context).size.width < 500;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
          childrenPadding: EdgeInsets.all(isMobile ? 12 : 20),
          leading: isMobile ? null : Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.description_rounded, color: Color(0xFF4F46E5), size: 24),
          ),
          title: Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: isMobile ? 14 : 16, color: const Color(0xFF1E293B)), maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Net: ${_currencyFormat.format(netTotal)}  •  Kalan: ${_currencyFormat.format(remaining)}',
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: remaining <= 0 ? const Color(0xFF10B981) : const Color(0xFF4F46E5)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (isMobile) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => _printContractPdf(data),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.print_rounded, color: Color(0xFF4F46E5), size: 18),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _confirmDelete(planId, name),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          trailing: isMobile ? null : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.print_rounded, color: Color(0xFF4F46E5)),
                tooltip: 'Sözleşme & Ödeme Planı PDF İndir',
                onPressed: () => _printContractPdf(data),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                tooltip: 'Planı Sil',
                onPressed: () => _confirmDelete(planId, name),
              ),
            ],
          ),
          children: [
            // Kalemler ve İndirimler
            if (items.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Hizmet Kalemleri ve Seçilen Ödeme Şekilleri', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF1E293B))),
              ),
              const SizedBox(height: 10),
              ...items.map((it) {
                final itAmt = (it['amount'] ?? 0).toDouble();
                final pType = it['paymentType'] == 'cash' ? 'Peşin' : 'Taksitli';
                final instCount = it['installmentCount'];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Icon(_getIconForPriceType(it['name']), size: 16, color: const Color(0xFF4F46E5)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${it['name']}:', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: const Color(0xFF334155)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      Text(_currencyFormat.format(itAmt), style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF1E293B))),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: pType == 'Peşin' ? const Color(0xFFFEF3C7) : const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          pType == 'Peşin' ? 'Peşin' : (instCount != null ? '$instCount T' : 'Taksit'),
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: pType == 'Peşin' ? const Color(0xFFB45309) : const Color(0xFF4338CA)),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 16),
            ],

            // Uygulanan İndirimler
            if (discounts.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Uygulanan Burs & İndirimler', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF1E293B))),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: discounts.map((d) {
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF059669)),
                          const SizedBox(width: 4),
                          Text('${d['name']} (%${d['percentage'] ?? 0})', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 11, color: const Color(0xFF065F46))),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Peşinat
            if (downPayment > 0) ...[
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: downPaymentPaid ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: downPaymentPaid ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 400;
                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(downPaymentPaid ? Icons.check_circle_rounded : Icons.pending_actions_rounded, color: downPaymentPaid ? const Color(0xFF10B981) : const Color(0xFFD97706), size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Peşin Alınacak Tutar', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
                                    Text(_currencyFormat.format(downPayment), style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _toggleDownPayment(planId, data, !downPaymentPaid),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: downPaymentPaid ? Colors.white : const Color(0xFF10B981),
                                foregroundColor: downPaymentPaid ? const Color(0xFF334155) : Colors.white,
                                elevation: 0,
                                side: downPaymentPaid ? const BorderSide(color: Color(0xFFCBD5E1)) : BorderSide.none,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(downPaymentPaid ? 'Tahsilatı İptal Et' : 'Ödendi İşaretle', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Icon(downPaymentPaid ? Icons.check_circle_rounded : Icons.pending_actions_rounded, color: downPaymentPaid ? const Color(0xFF10B981) : const Color(0xFFD97706), size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Peşin Alınacak Tutar / Peşinat', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF475569))),
                              Text(_currencyFormat.format(downPayment), style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => _toggleDownPayment(planId, data, !downPaymentPaid),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: downPaymentPaid ? Colors.white : const Color(0xFF10B981),
                            foregroundColor: downPaymentPaid ? const Color(0xFF334155) : Colors.white,
                            elevation: 0,
                            side: downPaymentPaid ? const BorderSide(color: Color(0xFFCBD5E1)) : BorderSide.none,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(downPaymentPaid ? 'Tahsilatı İptal Et' : 'Ödendi İşaretle', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],

            // Taksit Tabloları (Kalem Bazlı Ayrı Kartlar veya Ortak Tablo)
            ...groupedInstallments.entries.map((group) {
              final groupName = group.key;
              final groupInsts = group.value;
              double groupTotal = 0;
              for (var gi in groupInsts) groupTotal += (gi['amount'] ?? 0).toDouble();

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Grup Başlığı
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15)),
                        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: Row(
                        children: [
                          Icon(_getIconForPriceType(groupName), size: 18, color: const Color(0xFF4F46E5)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$groupName Taksit Planı', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF1E293B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text('${groupInsts.length} Taksit • Toplam: ${_currencyFormat.format(groupTotal)}', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11, color: const Color(0xFF64748B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Taksit Satırları
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: groupInsts.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      itemBuilder: (context, gIdx) {
                        final inst = groupInsts[gIdx];
                        final globalIdx = installments.indexOf(inst);
                        final isPaid = inst['status'] == 'paid';
                        final amount = (inst['amount'] ?? 0).toDouble();
                        final dueDate = inst['dueDate']?.toString() ?? '-';
                        final title = inst['title'] ?? '${gIdx + 1}. Taksit';

                        return LayoutBuilder(
                          builder: (context, rowConstraints) {
                            final isNarrowRow = rowConstraints.maxWidth < 450;
                            if (isNarrowRow) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 13,
                                          backgroundColor: isPaid ? const Color(0xFFD1FAE5) : const Color(0xFFEEF2FF),
                                          child: Text('${gIdx + 1}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: isPaid ? const Color(0xFF059669) : const Color(0xFF4F46E5))),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF1E293B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                              Text('Vade: $dueDate', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(_currencyFormat.format(amount), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: isPaid ? const Color(0xFF059669) : const Color(0xFF1E293B))),
                                        isPaid
                                            ? ElevatedButton.icon(
                                                onPressed: () => _cancelPayment(planId, data, globalIdx >= 0 ? globalIdx : gIdx),
                                                icon: const Icon(Icons.check_rounded, size: 13),
                                                label: const Text('Ödendi'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFFECFDF5),
                                                  foregroundColor: const Color(0xFF059669),
                                                  elevation: 0,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                              )
                                            : ElevatedButton(
                                                onPressed: () => _openCollectDialog(planId, data, globalIdx >= 0 ? globalIdx : gIdx, inst),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF4F46E5),
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                                child: Text('Tahsil Et', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700)),
                                              ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 13,
                                    backgroundColor: isPaid ? const Color(0xFFD1FAE5) : const Color(0xFFEEF2FF),
                                    child: Text('${gIdx + 1}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: isPaid ? const Color(0xFF059669) : const Color(0xFF4F46E5))),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF1E293B))),
                                        Text('Vade: $dueDate', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                                      ],
                                    ),
                                  ),
                                  Text(_currencyFormat.format(amount), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: isPaid ? const Color(0xFF059669) : const Color(0xFF1E293B))),
                                  const SizedBox(width: 14),
                                  isPaid
                                      ? ElevatedButton.icon(
                                          onPressed: () => _cancelPayment(planId, data, globalIdx >= 0 ? globalIdx : gIdx),
                                          icon: const Icon(Icons.check_rounded, size: 13),
                                          label: const Text('Ödendi'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFECFDF5),
                                            foregroundColor: const Color(0xFF059669),
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        )
                                      : ElevatedButton(
                                          onPressed: () => _openCollectDialog(planId, data, globalIdx >= 0 ? globalIdx : gIdx, inst),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF4F46E5),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          child: Text('Tahsil Et', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700)),
                                        ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getOrInitCashes(String instId) async {
    try {
      final cashQuery = await FirebaseFirestore.instance
          .collection('cashes')
          .where('institutionId', isEqualTo: instId)
          .get();

      if (cashQuery.docs.isEmpty) {
        final doc1 = await FirebaseFirestore.instance.collection('cashes').add({
          'institutionId': instId,
          'name': 'Ana Kasa',
          'balance': 0.0,
          'type': 'cash',
          'createdAt': FieldValue.serverTimestamp(),
        });
        final doc2 = await FirebaseFirestore.instance.collection('cashes').add({
          'institutionId': instId,
          'name': 'Banka / POS Hesabı',
          'balance': 0.0,
          'type': 'bank',
          'createdAt': FieldValue.serverTimestamp(),
        });
        return [
          {'id': doc1.id, 'name': 'Ana Kasa', 'balance': 0.0, 'type': 'cash'},
          {'id': doc2.id, 'name': 'Banka / POS Hesabı', 'balance': 0.0, 'type': 'bank'},
        ];
      }

      return cashQuery.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('Error getting cashes: $e');
      return [];
    }
  }

  void _openCollectDialog(String planId, Map<String, dynamic> planData, int idx, Map<String, dynamic> inst) async {
    final instId = widget.institutionId ?? widget.studentData?['institutionId'] ?? planData['institutionId'] ?? '';
    final cashes = await _getOrInitCashes(instId);

    final scheduledAmount = (inst['amount'] ?? 0).toDouble();
    final amountCtrl = TextEditingController(text: formatCurrencyText(scheduledAmount));
    String method = 'Kredi Kartı';
    String? selectedKasaId = cashes.isNotEmpty ? cashes.firstWhere((k) => k['type'] == 'bank', orElse: () => cashes.first)['id'] : null;
    final receiptCtrl = TextEditingController();
    DateTime payDate = DateTime.now();

    if (!mounted) return;

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sürükleme Çubuğu
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(10)),
                  ),
                ),

                // Başlık
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF059669), size: 24),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Taksit Tahsilatı Al', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
                            const SizedBox(height: 2),
                            Text('${inst['title'] ?? '${idx + 1}. Taksit'} • Vade: ${inst['dueDate'] ?? '-'}', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                          ],
                        ),
                      ],
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B))),
                  ],
                ),
                const SizedBox(height: 20),

                // Esnek Tahsilat Tutarı ve Otomatik Dengeleme Paneli
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Tahsil Edilecek Tutar (₺)', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF166534))),
                          Text('Planlanan: ${_currencyFormat.format(scheduledAmount)}', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: const Color(0xFF15803D))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [TurkishCurrencyInputFormatter()],
                        style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFF15803D)),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          suffixText: '₺',
                          suffixStyle: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF166534)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF86EFAC))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF86EFAC))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF16A34A), width: 2)),
                        ),
                        onChanged: (_) => setModal(() {}),
                      ),
                      Builder(
                        builder: (context) {
                          final paidAmount = parseCurrency(amountCtrl.text);
                          final diff = scheduledAmount - paidAmount;
                          final isUnified = planData['isUnifiedPlan'] == true;
                          final category = inst['category'];

                          final insts = List<Map<String, dynamic>>.from(
                              (planData['installments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));

                          final remainingIndices = <int>[];
                          for (int i = idx + 1; i < insts.length; i++) {
                            final item = insts[i];
                            if (item['status'] != 'paid' && (isUnified || item['category'] == category)) {
                              remainingIndices.add(i);
                            }
                          }

                          if (diff.abs() > 0.01) {
                            if (remainingIndices.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  diff > 0 ? '⚠️ Son taksit olduğu için eksik kalan tutar dağıtılamaz.' : 'ℹ️ Fazla ödeme alındı.',
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                                ),
                              );
                            }
                            final perInstDiff = diff / remainingIndices.length;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: diff > 0 ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.auto_awesome_rounded, size: 14, color: diff > 0 ? const Color(0xFFD97706) : const Color(0xFF059669)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        diff > 0
                                            ? 'Eksik kalan ${_currencyFormat.format(diff)}, sonraki ${remainingIndices.length} taksite eşit dağıtılacak (+${_currencyFormat.format(perInstDiff)}/ay)'
                                            : 'Fazla ödenen ${_currencyFormat.format(-diff)}, sonraki ${remainingIndices.length} taksitten eşit düşülecek (-${_currencyFormat.format(-perInstDiff)}/ay)',
                                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: diff > 0 ? const Color(0xFFB45309) : const Color(0xFF047857)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Ödeme Şekli
                Text('Ödeme Yöntemi', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Kredi Kartı', child: Text('Kredi Kartı / POS')),
                    DropdownMenuItem(value: 'Nakit', child: Text('Nakit Para')),
                    DropdownMenuItem(value: 'Havale/EFT', child: Text('Banka Havale / EFT')),
                    DropdownMenuItem(value: 'Çek/Senet', child: Text('Çek / Senet')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setModal(() {
                        method = v;
                        if (v == 'Nakit') {
                          final cashKasa = cashes.firstWhere((k) => k['type'] == 'cash', orElse: () => cashes.isNotEmpty ? cashes.first : {});
                          if (cashKasa.isNotEmpty) selectedKasaId = cashKasa['id'];
                        } else {
                          final bankKasa = cashes.firstWhere((k) => k['type'] == 'bank', orElse: () => cashes.isNotEmpty ? cashes.first : {});
                          if (bankKasa.isNotEmpty) selectedKasaId = bankKasa['id'];
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Paranın Giriş Yapacağı Kasa / Banka Hesabı
                Text('Paranın Giriş Yapacağı Kasa / Hesap', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedKasaId,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  items: cashes.map((k) => DropdownMenuItem(
                    value: k['id'] as String,
                    child: Row(
                      children: [
                        Icon(k['type'] == 'bank' ? Icons.account_balance_rounded : Icons.payments_rounded, size: 18, color: const Color(0xFF4F46E5)),
                        const SizedBox(width: 10),
                        Text(k['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(width: 8),
                        Text('(${_currencyFormat.format((k['balance'] as num?)?.toDouble() ?? 0)})', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                      ],
                    ),
                  )).toList(),
                  onChanged: (v) => setModal(() => selectedKasaId = v),
                ),
                const SizedBox(height: 16),

                // Makbuz / Dekont No
                Text('Makbuz / Dekont / Slip No (Opsiyonel)', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
                const SizedBox(height: 6),
                TextField(
                  controller: receiptCtrl,
                  decoration: InputDecoration(
                    hintText: 'Örn: DKT-849204',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                ),
                const SizedBox(height: 24),

                // Onay Butonu
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final paidAmount = parseCurrency(amountCtrl.text);
                      if (paidAmount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Lütfen geçerli bir tahsilat tutarı giriniz.')),
                        );
                        return;
                      }

                      Navigator.pop(ctx);
                      final studentName = planData['studentName'] ?? widget.studentData?['fullName'] ?? 'Öğrenci';
                      final kasaName = cashes.firstWhere((k) => k['id'] == selectedKasaId, orElse: () => {'name': 'Ana Kasa'})['name'];

                      // 1. Transaction Ekle
                      DocumentReference? transRef;
                      if (selectedKasaId != null) {
                        transRef = await FirebaseFirestore.instance.collection('transactions').add({
                          'institutionId': instId,
                          'type': 'income',
                          'category': 'Öğrenci Taksit Tahsilatı',
                          'description': '$studentName - ${inst['title'] ?? '${idx + 1}. Taksit'} Tahsilatı',
                          'amount': paidAmount,
                          'kasaId': selectedKasaId,
                          'kasaName': kasaName,
                          'paymentMethod': method,
                          'receiptNo': receiptCtrl.text.trim(),
                          'date': FieldValue.serverTimestamp(),
                          'userId': FirebaseAuth.instance.currentUser?.uid,
                          'planId': planId,
                          'studentId': widget.studentId,
                          'installmentIndex': idx,
                        });

                        // 2. Kasa Bakiyesini Güncelle
                        final kasaDoc = FirebaseFirestore.instance.collection('cashes').doc(selectedKasaId);
                        await FirebaseFirestore.instance.runTransaction((tx) async {
                          final snap = await tx.get(kasaDoc);
                          if (snap.exists) {
                            final oldBal = (snap['balance'] as num?)?.toDouble() ?? 0.0;
                            tx.update(kasaDoc, {'balance': oldBal + paidAmount});
                          }
                        });
                      }

                      // 3. Plan Belgesini ve Kalan Taksitleri Güncelle
                      final diff = scheduledAmount - paidAmount;
                      final isUnified = planData['isUnifiedPlan'] == true;
                      final category = inst['category'];

                      final insts = List<Map<String, dynamic>>.from(
                          (planData['installments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));

                      if (idx < insts.length) {
                        insts[idx]['amount'] = paidAmount;
                        insts[idx]['status'] = 'paid';
                        insts[idx]['paidDate'] = _dateFormat.format(payDate);
                        insts[idx]['paymentMethod'] = method;
                        insts[idx]['receiptNo'] = receiptCtrl.text.trim();
                        insts[idx]['kasaId'] = selectedKasaId;
                        insts[idx]['kasaName'] = kasaName;
                        if (transRef != null) insts[idx]['transactionId'] = transRef.id;
                      }

                      // Kalan taksitlere farkı dağıt
                      if (diff.abs() > 0.01) {
                        final remainingIndices = <int>[];
                        for (int i = idx + 1; i < insts.length; i++) {
                          final item = insts[i];
                          if (item['status'] != 'paid' && (isUnified || item['category'] == category)) {
                            remainingIndices.add(i);
                          }
                        }

                        if (remainingIndices.isNotEmpty) {
                          final perInst = (diff / remainingIndices.length);
                          double distributed = 0;
                          for (int j = 0; j < remainingIndices.length; j++) {
                            final rIdx = remainingIndices[j];
                            final oldAmt = (insts[rIdx]['amount'] ?? 0).toDouble();
                            if (j == remainingIndices.length - 1) {
                              final lastDelta = diff - distributed;
                              insts[rIdx]['amount'] = (oldAmt + lastDelta).clamp(0.0, double.infinity);
                            } else {
                              final roundedDelta = (perInst * 100).round() / 100;
                              distributed += roundedDelta;
                              insts[rIdx]['amount'] = (oldAmt + roundedDelta).clamp(0.0, double.infinity);
                            }
                          }
                        }
                      }

                      await FirebaseFirestore.instance.collection('payment_plans').doc(planId).update({
                        'installments': insts,
                        'updatedAt': FieldValue.serverTimestamp(),
                      });

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✓ ${_currencyFormat.format(paidAmount)} tutarındaki tahsilat $kasaName hesabına işlendi.'),
                            backgroundColor: const Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.check_circle_rounded, size: 20),
                    label: Text('TAHSİLATI ONAYLA VE KASAYA İŞLE', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
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
      ),
    );
  }

  Future<void> _cancelPayment(String planId, Map<String, dynamic> planData, int idx) async {
    final insts = List<Map<String, dynamic>>.from(
        (planData['installments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));

    if (idx < insts.length) {
      final inst = insts[idx];
      final amount = (inst['amount'] ?? 0).toDouble();
      final transId = inst['transactionId'] as String?;
      final kasaId = inst['kasaId'] as String?;

      // İşlemi transactions tablosundan sil veya ters bakiye yaz
      if (transId != null) {
        try {
          await FirebaseFirestore.instance.collection('transactions').doc(transId).delete();
        } catch (_) {}
      }

      // Kasa bakiyesini geri düş
      if (kasaId != null && amount > 0) {
        try {
          final kasaDoc = FirebaseFirestore.instance.collection('cashes').doc(kasaId);
          await FirebaseFirestore.instance.runTransaction((tx) async {
            final snap = await tx.get(kasaDoc);
            if (snap.exists) {
              final oldBal = (snap['balance'] as num?)?.toDouble() ?? 0.0;
              tx.update(kasaDoc, {'balance': (oldBal - amount).clamp(0.0, double.infinity)});
            }
          });
        } catch (_) {}
      }

      inst['status'] = 'unpaid';
      inst['paidDate'] = null;
      inst['paymentMethod'] = null;
      inst['receiptNo'] = null;
      inst['transactionId'] = null;
      inst['kasaId'] = null;
      inst['kasaName'] = null;
    }

    await FirebaseFirestore.instance.collection('payment_plans').doc(planId).update({
      'installments': insts,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Tahsilat kaydı iptal edildi ve kasa bakiyesi güncellendi.'),
          backgroundColor: Color(0xFF64748B),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleDownPayment(String planId, Map<String, dynamic> planData, bool isPaid) async {
    final instId = widget.institutionId ?? widget.studentData?['institutionId'] ?? planData['institutionId'] ?? '';
    final downPayment = (planData['downPayment'] ?? 0).toDouble();

    String? transId = planData['downPaymentTransactionId'] as String?;
    String? kasaId = planData['downPaymentKasaId'] as String?;

    if (isPaid && downPayment > 0) {
      final cashes = await _getOrInitCashes(instId);
      final defaultKasa = cashes.firstWhere((k) => k['type'] == 'cash', orElse: () => cashes.isNotEmpty ? cashes.first : {'id': null, 'name': 'Ana Kasa'});
      kasaId = defaultKasa['id'] as String?;
      final kasaName = defaultKasa['name'] ?? 'Ana Kasa';

      if (kasaId != null) {
        final transRef = await FirebaseFirestore.instance.collection('transactions').add({
          'institutionId': instId,
          'type': 'income',
          'category': 'Öğrenci Peşinat Tahsilatı',
          'description': '${planData['studentName'] ?? widget.studentData?['fullName'] ?? 'Öğrenci'} - Peşinat Tahsilatı',
          'amount': downPayment,
          'kasaId': kasaId,
          'kasaName': kasaName,
          'paymentMethod': 'Nakit / Peşin',
          'date': FieldValue.serverTimestamp(),
          'userId': FirebaseAuth.instance.currentUser?.uid,
          'planId': planId,
          'studentId': widget.studentId,
        });
        transId = transRef.id;

        final kasaDoc = FirebaseFirestore.instance.collection('cashes').doc(kasaId);
        await FirebaseFirestore.instance.runTransaction((tx) async {
          final snap = await tx.get(kasaDoc);
          if (snap.exists) {
            final oldBal = (snap['balance'] as num?)?.toDouble() ?? 0.0;
            tx.update(kasaDoc, {'balance': oldBal + downPayment});
          }
        });
      }
    } else if (!isPaid && downPayment > 0) {
      if (transId != null) {
        try {
          await FirebaseFirestore.instance.collection('transactions').doc(transId).delete();
        } catch (_) {}
      }
      if (kasaId != null) {
        try {
          final kasaDoc = FirebaseFirestore.instance.collection('cashes').doc(kasaId);
          await FirebaseFirestore.instance.runTransaction((tx) async {
            final snap = await tx.get(kasaDoc);
            if (snap.exists) {
              final oldBal = (snap['balance'] as num?)?.toDouble() ?? 0.0;
              tx.update(kasaDoc, {'balance': (oldBal - downPayment).clamp(0.0, double.infinity)});
            }
          });
        } catch (_) {}
      }
      transId = null;
      kasaId = null;
    }

    await FirebaseFirestore.instance.collection('payment_plans').doc(planId).update({
      'downPaymentPaid': isPaid,
      'downPaymentDate': isPaid ? _dateFormat.format(DateTime.now()) : null,
      'downPaymentTransactionId': transId,
      'downPaymentKasaId': kasaId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _confirmDelete(String planId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Planı Sil'),
        content: Text('"$name" ödeme sözleşmesini silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('payment_plans').doc(planId).delete();
    }
  }

  Future<void> _printContractPdf(Map<String, dynamic> planData) async {
    final pdf = pw.Document();
    final studentName = widget.studentData?['fullName'] ?? widget.studentData?['name'] ?? 'Öğrenci';
    final studentNo = widget.studentData?['studentNo'] ?? '-';
    final guardianName = widget.studentData?['guardianName'] ?? widget.studentData?['parentName'] ?? 'Veli';
    final guardianPhone = widget.studentData?['guardianPhone'] ?? widget.studentData?['phone'] ?? '-';
    final planName = planData['name'] ?? 'Öğrenci Kayıt ve Ödeme Sözleşmesi';
    final netTotal = (planData['netTotal'] ?? planData['totalAmount'] ?? 0).toDouble();
    final items = List<Map<String, dynamic>>.from((planData['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
    final discounts = List<Map<String, dynamic>>.from((planData['appliedDiscounts'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
    final installments = List<Map<String, dynamic>>.from((planData['installments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('ÖĞRENCİ KAYIT VE ÖDEME PLANI SÖZLEŞMESİ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                pw.Text(_dateFormat.format(DateTime.now()), style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), color: PdfColors.grey100),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Öğrenci: $studentName (No: $studentNo)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('Veli: $guardianName (Tel: $guardianPhone)', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Sözleşme Adı: $planName', style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('Net Sözleşme Tutarı: ${_currencyFormat.format(netTotal)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.indigo900)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text('HİZMET VE ÜCRET KALEMLERİ:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Hizmet Türü', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Ödeme Şekli', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Tutar', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                ],
              ),
              ...items.map((it) => pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(it['name'] ?? '', style: const pw.TextStyle(fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(it['paymentType'] == 'cash' ? 'Peşin' : (it['installmentCount'] != null ? '${it['installmentCount']} Taksit' : 'Taksitli'), style: const pw.TextStyle(fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_currencyFormat.format((it['amount'] ?? 0).toDouble()), style: const pw.TextStyle(fontSize: 8))),
                ],
              )),
            ],
          ),
          if (discounts.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text('UYGULANAN BURS & İNDİRİMLER:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.SizedBox(height: 4),
            ...discounts.map((d) => pw.Text('- ${d['name']} (%${d['percentage'] ?? 0})', style: const pw.TextStyle(fontSize: 8))),
          ],
          pw.SizedBox(height: 12),
          pw.Text('ÖDEME VE TAKSİT TAKVİMİ:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Taksit Başlığı', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Vade Tarihi', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Taksit Tutarı', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Ödeme Durumu', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                ],
              ),
              ...installments.asMap().entries.map((e) {
                final inst = e.value;
                final isPaid = inst['status'] == 'paid';
                return pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${inst['title'] ?? '${e.key + 1}. Taksit'}', style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(inst['dueDate'] ?? '-', style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_currencyFormat.format((inst['amount'] ?? 0).toDouble()), style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(isPaid ? 'ÖDENDİ (${inst['paidDate'] ?? ''})' : 'BEKLİYOR', style: pw.TextStyle(fontSize: 8, fontWeight: isPaid ? pw.FontWeight.bold : pw.FontWeight.normal))),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text('GENEL SÖZLEŞME HÜKÜMLERİ:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          pw.Text('1. Veli, yukarıda belirtilen takvim doğrultusunda taksitleri zamanında ödemeyi kabul ve taahhüt eder.\n2. Vadesi geçen ödemelerde kurumun yasal gecikme faizi ve işlem hakkı saklıdır.\n3. Kayıt iptal ve iade süreçleri ilgili MEB mevzuatı ve kurum yönetmeliğine tabidir.', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.SizedBox(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                children: [
                  pw.Text('Öğrenci Velisi', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.SizedBox(height: 24),
                  pw.Text('İmza', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
              pw.Column(
                children: [
                  pw.Text('Kurum Yetkilisi / Muhasebe', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.SizedBox(height: 24),
                  pw.Text('İmza / Kaşe', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${studentName}_Odeme_Sozlesmesi.pdf',
    );
  }

  IconData _getIconForPriceType(String? name) {
    if (name == null) return Icons.category_rounded;
    final n = name.toLowerCase();
    if (n.contains('eğitim')) return Icons.school_rounded;
    if (n.contains('yemek')) return Icons.restaurant_rounded;
    if (n.contains('kitap')) return Icons.menu_book_rounded;
    if (n.contains('servis')) return Icons.directions_bus_rounded;
    if (n.contains('kıyafet') || n.contains('üniforma')) return Icons.checkroom_rounded;
    return Icons.payments_rounded;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ÖN KAYIT BİREBİR TASARIMLI, KALEM BAZLI VE BİRLEŞİK TAKSİT ROBOTU
// ═══════════════════════════════════════════════════════════════════════════

class _FullOfferPaymentPlanBuilder extends StatefulWidget {
  final String studentId;
  final Map<String, dynamic>? studentData;
  final String? institutionId;
  final Map<String, dynamic>? preRegSettings;
  final VoidCallback onCancel;
  final VoidCallback onSaved;

  const _FullOfferPaymentPlanBuilder({
    Key? key,
    required this.studentId,
    this.studentData,
    this.institutionId,
    this.preRegSettings,
    required this.onCancel,
    required this.onSaved,
  }) : super(key: key);

  @override
  __FullOfferPaymentPlanBuilderState createState() =>
      __FullOfferPaymentPlanBuilderState();
}

class __FullOfferPaymentPlanBuilderState
    extends State<_FullOfferPaymentPlanBuilder> {
  final NumberFormat _currencyFormat =
      NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');

  final TextEditingController _planNameCtrl =
      TextEditingController(text: '2024-2025 Eğitim & Hizmet Sözleşmesi');
  final TextEditingController _manualDownPaymentCtrl =
      TextEditingController(text: '0,00');

  List<String> _priceTypes = ['Eğitim', 'Yemek'];
  Map<String, TextEditingController> _priceControllers = {};
  Map<String, String> _perTypePaymentMethod = {}; // 'Eğitim': 'cash' / 'installment'
  
  // Kalem bazlı taksit ayarları (Her kalem için taksit sayısı ve başlangıç tarihi)
  Map<String, int> _perTypeInstallmentCount = {}; // 'Eğitim': 10, 'Yemek': 8
  Map<String, DateTime> _perTypeFirstDueDate = {}; // 'Eğitim': DateTime...

  // Mod Seçimi: Kalem Bazlı Ayrı Taksit Planları vs. Tüm Kalemleri Birleştir (Konsolide)
  bool _isUnifiedPlan = false;
  int _unifiedInstallmentCount = 10;
  DateTime _unifiedFirstDueDate = DateTime.now().add(const Duration(days: 15));

  List<Map<String, dynamic>> _discounts = [];
  List<String> _selectedDiscountIds = [];
  Map<String, double> _customDiscountPercentages = {};
  Map<String, String> _customDiscountReasons = {};

  // Kalem bazlı üretilen taksit haritası (Kalem Adı -> Taksit Listesi)
  Map<String, List<Map<String, dynamic>>> _perCategoryInstallments = {};
  // Konsolide taksit listesi
  List<Map<String, dynamic>> _unifiedInstallmentsList = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadFromPreRegSettings();
  }

  void _loadFromPreRegSettings() {
    final settings = widget.preRegSettings ?? {};
    final rawTypes = settings['priceTypes'] as List<dynamic>? ?? ['Eğitim', 'Yemek'];
    _priceTypes = rawTypes.map((e) => e.toString()).toList();

    final pricesMap = settings['prices'] as Map<dynamic, dynamic>? ?? {};
    final currentMonth = DateTime.now().month;
    final schoolTypeId = widget.studentData?['schoolTypeId'] ?? '';
    final classLevel = widget.studentData?['classLevel']?.toString() ?? '';
    final standardKey = '${currentMonth}_${schoolTypeId}_${classLevel}';
    final standardPrices = pricesMap[standardKey] as Map<dynamic, dynamic>? ?? {};

    _priceControllers = {};
    _perTypePaymentMethod = {};
    _perTypeInstallmentCount = {};
    _perTypeFirstDueDate = {};

    final defaultDue = DateTime.now().add(const Duration(days: 15));

    for (var type in _priceTypes) {
      final defaultAmt = (standardPrices[type] as num?)?.toDouble() ??
          (type.contains('Eğitim') ? 150000.0 : (type.contains('Yemek') ? 35000.0 : 15000.0));
      _priceControllers[type] = TextEditingController(text: formatCurrencyText(defaultAmt));
      _perTypePaymentMethod[type] = 'installment';
      _perTypeInstallmentCount[type] = type.contains('Eğitim') ? 10 : (type.contains('Yemek') ? 8 : 4);
      _perTypeFirstDueDate[type] = defaultDue;
    }

    final rawDiscounts = settings['discounts'] as List<dynamic>? ?? [];
    if (rawDiscounts.isNotEmpty) {
      _discounts = rawDiscounts.map((d) => Map<String, dynamic>.from(d as Map)).toList();
    } else {
      _discounts = [
        {'id': 'early', 'name': 'Erken Kayıt', 'percentage': 10, 'enabled': true},
        {'id': 'sibling', 'name': 'Kardeş İndirimi', 'percentage': 12, 'enabled': true},
        {'id': 'teacher', 'name': 'Öğretmen İndirimi', 'percentage': 5, 'enabled': true},
        {'id': 'success', 'name': 'Başarı Bursu', 'percentage': 20, 'enabled': true},
      ];
    }

    _recomputeInstallments();
  }

  double get _subtotal {
    double sum = 0;
    for (var type in _priceTypes) {
      final ctrl = _priceControllers[type];
      if (ctrl != null) {
        sum += parseCurrency(ctrl.text);
      }
    }
    return sum;
  }

  double get _totalDiscountAmount {
    double total = 0;
    for (var dId in _selectedDiscountIds) {
      final d = _discounts.firstWhere((e) => e['id'] == dId, orElse: () => {});
      if (d.isNotEmpty) {
        final perc = _customDiscountPercentages[dId] ?? (d['percentage'] as num?)?.toDouble() ?? 0.0;
        final dApplyToRaw = d['applyTo'] as List<dynamic>?;
        double baseForD = 0;
        if (dApplyToRaw == null || dApplyToRaw.isEmpty) {
          baseForD = _subtotal;
        } else {
          for (var type in _priceTypes) {
            final tL = type.toLowerCase();
            for (var a in dApplyToRaw) {
              if (tL.contains(a.toString().toLowerCase())) {
                final ctrl = _priceControllers[type];
                if (ctrl != null) baseForD += parseCurrency(ctrl.text);
              }
            }
          }
        }
        total += baseForD * (perc / 100);
      }
    }
    return total.clamp(0.0, _subtotal);
  }

  bool _isBursOrCustomDiscount(Map<String, dynamic> d) {
    final name = (d['name'] ?? '').toString().toLowerCase();
    return name.contains('burs') || name.contains('özel') || d['isCustom'] == true;
  }

  Future<void> _openBursEditDialog(Map<String, dynamic> d) async {
    final dId = d['id'] as String;
    final currentPerc = _customDiscountPercentages[dId] ?? (d['percentage'] as num?)?.toDouble() ?? 20.0;
    final currentReason = _customDiscountReasons[dId] ?? '';
    final isSelected = _selectedDiscountIds.contains(dId);

    final percCtrl = TextEditingController(text: currentPerc.toInt().toString());
    final reasonCtrl = TextEditingController(text: currentReason);

    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFF4F46E5), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${d['name']} Oranı Belirle', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Öğrenciye tanımlanacak burs oranını (%) girin:', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
            const SizedBox(height: 12),
            TextField(
              controller: percCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Burs Oranı (%)',
                suffixText: '%',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              style: GoogleFonts.inter(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Burs Gerekçesi / Notu (İsteğe Bağlı)',
                hintText: 'Örn: Başarı bursu, Yönetim kurulu kararı',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          if (isSelected)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: const Text('Bursu Kaldır', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white),
            child: const Text('Uygula'),
          ),
        ],
      ),
    );

    if (res == 'save') {
      final p = double.tryParse(percCtrl.text.replaceAll(',', '.').trim()) ?? currentPerc;
      setState(() {
        if (!isSelected) _selectedDiscountIds.add(dId);
        _customDiscountPercentages[dId] = p;
        _customDiscountReasons[dId] = reasonCtrl.text.trim();
      });
      _recomputeInstallments();
    } else if (res == 'remove') {
      setState(() {
        _selectedDiscountIds.remove(dId);
      });
      _recomputeInstallments();
    }
  }

  double get _netContractTotal {
    return (_subtotal - _totalDiscountAmount).clamp(0.0, double.infinity);
  }

  double get _discountRatio {
    return _subtotal > 0 ? (_totalDiscountAmount / _subtotal) : 0.0;
  }

  double _getItemNetAmount(String type) {
    final ctrl = _priceControllers[type];
    if (ctrl == null) return 0.0;
    final amt = parseCurrency(ctrl.text);
    return (amt * (1 - _discountRatio)).clamp(0.0, double.infinity);
  }

  double get _cashTotal {
    double sum = 0;
    for (var type in _priceTypes) {
      if (_perTypePaymentMethod[type] == 'cash') {
        sum += _getItemNetAmount(type);
      }
    }
    final extraDown = parseCurrency(_manualDownPaymentCtrl.text);
    return (sum + extraDown).clamp(0.0, _netContractTotal);
  }

  double get _amountToInstallment {
    return (_netContractTotal - _cashTotal).clamp(0.0, double.infinity);
  }

  List<Map<String, dynamic>> get _allActiveInstallmentsList {
    if (_isUnifiedPlan) {
      return _unifiedInstallmentsList;
    }
    final List<Map<String, dynamic>> all = [];
    _perCategoryInstallments.forEach((_, list) {
      all.addAll(list);
    });
    return all;
  }

  double get _enteredInstallmentsSum {
    double s = 0;
    for (var inst in _allActiveInstallmentsList) {
      final ctrl = inst['controller'] as TextEditingController?;
      if (ctrl != null) {
        s += parseCurrency(ctrl.text);
      }
    }
    return s;
  }

  final Map<String, int> _lastEditedInstallmentIndex = {};

  void _distributeRemainderToSubsequentInstallments({
    required List<Map<String, dynamic>> list,
    required double targetTotal,
    required String key,
    int? fromIndex,
  }) {
    if (list.isEmpty) return;

    int splitIndex = fromIndex ?? _lastEditedInstallmentIndex[key] ?? 0;
    if (splitIndex >= list.length - 1) {
      splitIndex = list.length - 2;
    }
    if (splitIndex < 0) splitIndex = 0;

    double sumEntered = 0;
    for (int i = 0; i <= splitIndex; i++) {
      final ctrl = list[i]['controller'] as TextEditingController?;
      if (ctrl != null) {
        sumEntered += parseCurrency(ctrl.text);
      }
    }

    final double remainingTotal = (targetTotal - sumEntered).clamp(0.0, double.infinity);
    final int remainingCount = list.length - (splitIndex + 1);

    if (remainingCount > 0) {
      final double rawMonthly = remainingTotal / remainingCount;
      final double roundedMonthly = (rawMonthly * 100).round() / 100;
      double accum = 0;

      for (int i = splitIndex + 1; i < list.length; i++) {
        final ctrl = list[i]['controller'] as TextEditingController?;
        if (ctrl != null) {
          double amt = roundedMonthly;
          if (i == list.length - 1) {
            amt = ((remainingTotal - accum) * 100).round() / 100;
          } else {
            accum += amt;
          }
          ctrl.text = formatCurrencyText(amt);
        }
      }
    }
    setState(() {});
  }

  void _recomputeInstallments() {
    if (_isUnifiedPlan) {
      // ═══════════════════════════════════════════════════════════════════════
      // 1. KONSOLİDE TEK PLAN
      // ═══════════════════════════════════════════════════════════════════════
      final target = _amountToInstallment;
      final count = _unifiedInstallmentCount.clamp(1, 24);
      final List<Map<String, dynamic>> list = [];

      if (target > 0) {
        final double rawMonthly = target / count;
        final double roundedMonthly = (rawMonthly * 100).round() / 100;
        double accum = 0;

        for (int i = 0; i < count; i++) {
          DateTime due = DateTime(
            _unifiedFirstDueDate.year,
            _unifiedFirstDueDate.month + i,
            _unifiedFirstDueDate.day,
          );
          double amt = roundedMonthly;
          if (i == count - 1) {
            amt = ((target - accum) * 100).round() / 100;
          } else {
            accum += amt;
          }

          list.add({
            'no': i + 1,
            'title': '${i + 1}. Taksit (Konsolide)',
            'category': 'Genel',
            'amount': amt,
            'controller': TextEditingController(text: formatCurrencyText(amt)),
            'dueDate': _dateFormat.format(due),
            'status': 'unpaid',
          });
        }
      }
      setState(() {
        _unifiedInstallmentsList = list;
      });
    } else {
      // ═══════════════════════════════════════════════════════════════════════
      // 2. HER KALEM İÇİN BAĞIMSIZ AYRI TAKVİM & TABLO
      // ═══════════════════════════════════════════════════════════════════════
      final Map<String, List<Map<String, dynamic>>> map = {};
      int globalNo = 1;

      for (var type in _priceTypes) {
        final pType = _perTypePaymentMethod[type] ?? 'installment';
        if (pType == 'cash') continue;

        final typeNetAmt = _getItemNetAmount(type);
        final count = (_perTypeInstallmentCount[type] ?? 10).clamp(1, 24);
        final firstDue = _perTypeFirstDueDate[type] ?? DateTime.now().add(const Duration(days: 15));

        final List<Map<String, dynamic>> catList = [];

        if (typeNetAmt > 0) {
          final double rawMonthly = typeNetAmt / count;
          final double roundedMonthly = (rawMonthly * 100).round() / 100;
          double accum = 0;

          for (int i = 0; i < count; i++) {
            DateTime due = DateTime(firstDue.year, firstDue.month + i, firstDue.day);
            double amt = roundedMonthly;
            if (i == count - 1) {
              amt = ((typeNetAmt - accum) * 100).round() / 100;
            } else {
              accum += amt;
            }

            catList.add({
              'no': globalNo++,
              'title': '$type ${i + 1}. Taksit',
              'category': type,
              'amount': amt,
              'controller': TextEditingController(text: formatCurrencyText(amt)),
              'dueDate': _dateFormat.format(due),
              'status': 'unpaid',
            });
          }
        }
        map[type] = catList;
      }

      setState(() {
        _perCategoryInstallments = map;
      });
    }
  }

  void _addNewPriceCategory() {
    final nameCtrl = TextEditingController();
    final amtCtrl = TextEditingController(text: '10.000,00');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Yeni Kalem Ekle', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Kalem Adı (örn: Kırtasiye, Gezi, Servis)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [TurkishCurrencyInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Tutar (₺)',
                suffixText: '₺',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                final name = nameCtrl.text.trim();
                setState(() {
                  _priceTypes.add(name);
                  _priceControllers[name] = TextEditingController(text: amtCtrl.text.trim());
                  _perTypePaymentMethod[name] = 'installment';
                  _perTypeInstallmentCount[name] = 4;
                  _perTypeFirstDueDate[name] = DateTime.now().add(const Duration(days: 15));
                });
                _recomputeInstallments();
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final diff = (_enteredInstallmentsSum - _amountToInstallment).abs();
    final hasDiff = diff > 0.5 && _allActiveInstallmentsList.isNotEmpty;
    final isOverflow = _enteredInstallmentsSum > _amountToInstallment + 0.5;

    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          // Top Action Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: const Color(0xFFE2E8F0))),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Plan Listesine Dön'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.auto_awesome_rounded, color: Color(0xFF4F46E5), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ödeme Planı & Sözleşme Robotu',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveOfferAsPlan,
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(_isSaving ? 'Kaydediliyor...' : 'Planı & Sözleşmeyi Kaydet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),

          // Main Interactive Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Üçlü Fiyat Kartları (Kare & Geniş Okunabilir Tasarım)
                  Row(
                    children: [
                      Expanded(child: _buildPriceCard('TOPLAM BRÜT', _subtotal, const Color(0xFF4F46E5), Icons.receipt_long_rounded)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildPriceCard('TOPLAM İNDİRİM', _totalDiscountAmount, const Color(0xFFF59E0B), Icons.discount_rounded)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildPriceCard('NET SÖZLEŞME', _netContractTotal, const Color(0xFF10B981), Icons.verified_rounded)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Plan Title
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: TextField(
                      controller: _planNameCtrl,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
                      decoration: InputDecoration(
                        labelText: 'Sözleşme / Plan Başlığı',
                        prefixIcon: const Icon(Icons.edit_document, color: Color(0xFF4F46E5)),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 2. Fiyat Giriş Kartı & Kalem Bazlı Taksit Ayarları
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('1. Hizmet Kalemleri ve Fiyatlar', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
                      TextButton.icon(
                        onPressed: _addNewPriceCategory,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Yeni Kalem Ekle', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: _priceTypes.asMap().entries.map((entry) {
                        final type = entry.value;
                        final ctrl = _priceControllers[type]!;
                        final isLast = entry.key == _priceTypes.length - 1;
                        final pType = _perTypePaymentMethod[type] ?? 'installment';

                        return Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(12)),
                                  child: Icon(_getIconForPriceType(type), color: const Color(0xFF4F46E5), size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(type, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: const Color(0xFF1E293B))),
                                ),
                                // Canlı Para Formatlı Tutar Kutusu (2000 -> 2.000,00)
                                SizedBox(
                                  width: 160,
                                  child: TextField(
                                    controller: ctrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [TurkishCurrencyInputFormatter()],
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14),
                                    decoration: InputDecoration(
                                      suffixText: ' ₺',
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                    ),
                                    onChanged: (_) {
                                      setState(() {});
                                      _recomputeInstallments();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 14),
                                // Ödeme Türü Seçici (Peşin / Taksit)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: pType,
                                      isDense: true,
                                      items: const [
                                        DropdownMenuItem(value: 'installment', child: Text('Taksitli', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                        DropdownMenuItem(value: 'cash', child: Text('Peşin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD97706)))),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _perTypePaymentMethod[type] = val);
                                          _recomputeInstallments();
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!isLast) const Divider(height: 24, color: Color(0xFFF1F5F9)),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 3. Çoklu İndirim / Burs Seçim Baloncukları (Ön Kayıt Ayarlarından)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('2. Kullanılabilir İndirimler & Burslar (Birden Çok Seçilebilir)', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Sabit indirimler tek tıkla uygulanır; Burs ve özel indirimlere tıklayarak istediğiniz oranı (%) serbestçe belirleyebilirsiniz.', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _discounts.map((d) {
                      final dId = d['id'] as String;
                      final isSelected = _selectedDiscountIds.contains(dId);
                      final isBurs = _isBursOrCustomDiscount(d);
                      final currentPerc = _customDiscountPercentages[dId] ?? (d['percentage'] as num?)?.toDouble() ?? 0.0;

                      return GestureDetector(
                        onTap: () {
                          if (isBurs) {
                            _openBursEditDialog(d);
                          } else {
                            setState(() {
                              if (isSelected) {
                                _selectedDiscountIds.remove(dId);
                              } else {
                                _selectedDiscountIds.add(dId);
                              }
                            });
                            _recomputeInstallments();
                          }
                        },
                        onLongPress: () => _openBursEditDialog(d),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected
                                ? [BoxShadow(color: const Color(0xFF4F46E5).withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 4))]
                                : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected ? Icons.check_circle_rounded : (isBurs ? Icons.workspace_premium_rounded : Icons.add_circle_outline_rounded),
                                color: isSelected ? const Color(0xFF4F46E5) : (isBurs ? const Color(0xFFD97706) : const Color(0xFF94A3B8)),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                d['name'] ?? '',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: isSelected ? const Color(0xFF312E81) : const Color(0xFF334155),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF4F46E5) : (isBurs ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9)),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '%${currentPerc.toInt()}',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                        color: isSelected ? Colors.white : (isBurs ? const Color(0xFFB45309) : const Color(0xFF64748B)),
                                      ),
                                    ),
                                    if (isBurs) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.edit_rounded, size: 11, color: isSelected ? Colors.white70 : const Color(0xFFB45309)),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),

                  // 4. Mod Seçimi & Peşinat Paneli
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('3. Taksitlendirme Modu & Peşinat', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
                      // BİRLEŞTİR / AYRI TUT SWITCH'İ
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _isUnifiedPlan ? const Color(0xFFEEF2FF) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _isUnifiedPlan ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_isUnifiedPlan ? Icons.merge_type_rounded : Icons.call_split_rounded, size: 18, color: const Color(0xFF4F46E5)),
                            const SizedBox(width: 8),
                            Text(
                              _isUnifiedPlan ? 'Tüm Kalemleri Tek Planda Birleştir' : 'Kalemler Ayrı Ayrı Taksitli (Bağımsız)',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
                            ),
                            const SizedBox(width: 8),
                            Switch(
                              value: _isUnifiedPlan,
                              activeColor: const Color(0xFF4F46E5),
                              onChanged: (val) {
                                setState(() => _isUnifiedPlan = val);
                                _recomputeInstallments();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        if (_isUnifiedPlan) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Ortak Taksit Sayısı', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF475569))),
                                    const SizedBox(height: 6),
                                    DropdownButtonFormField<int>(
                                      value: _unifiedInstallmentCount,
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: const Color(0xFFF8FAFC),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      ),
                                      items: List.generate(12, (i) => i + 1)
                                          .map((n) => DropdownMenuItem(value: n, child: Text('$n Taksit (Ortak)', style: GoogleFonts.inter(fontWeight: FontWeight.w600))))
                                          .toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _unifiedInstallmentCount = val);
                                          _recomputeInstallments();
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Ortak Vade Başlangıç Tarihi', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF475569))),
                                    const SizedBox(height: 6),
                                    InkWell(
                                      onTap: () async {
                                        final picked = await CustomDateRangePicker.showSingle(
                                          context,
                                          initialDate: _unifiedFirstDueDate,
                                        );
                                        if (picked != null) {
                                          setState(() => _unifiedFirstDueDate = picked);
                                          _recomputeInstallments();
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(_dateFormat.format(_unifiedFirstDueDate), style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
                                            const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF4F46E5)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Manuel Ek Peşinat (₺)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF475569))),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _manualDownPaymentCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [TurkishCurrencyInputFormatter()],
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                                    decoration: InputDecoration(
                                      suffixText: '₺',
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                    ),
                                    onChanged: (_) => _recomputeInstallments(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Peşin Alınacak Tutar: ${_currencyFormat.format(_cashTotal)}', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF312E81))),
                              Text('Taksitlendirilecek Toplam: ${_currencyFormat.format(_amountToInstallment)}', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, color: const Color(0xFF4F46E5))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // 5. AYRI AYRI VEYA BİRLEŞİK TAKSİT TABLOLARI
                  Text(
                    _isUnifiedPlan
                        ? '4. Birleşik Ortak Taksit Tablosu (${_unifiedInstallmentsList.length} Taksit)'
                        : '4. Kalem Bazlı Bağımsız Taksit Tabloları (Ayrı Başlangıç Tarihleri & Vadeler)',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 10),

                  if (hasDiff)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isOverflow ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isOverflow ? const Color(0xFFFECACA) : const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          Icon(isOverflow ? Icons.error_rounded : Icons.warning_amber_rounded, color: isOverflow ? const Color(0xFFEF4444) : const Color(0xFFD97706)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isOverflow
                                  ? 'Taksitler toplamı borçtan ${_currencyFormat.format(diff)} FAZLA! Lütfen kontrol edin.'
                                  : 'Taksitler toplamında ${_currencyFormat.format(diff)} EKSİK var! "Kalan Aylara Eşit Dağıt" butonuna basabilirsiniz.',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: isOverflow ? const Color(0xFF991B1B) : const Color(0xFF92400E)),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ═══════════════════════════════════════════════════════════
                  // EĞER BİRLEŞİK İSE: TEK TABLO
                  // ═══════════════════════════════════════════════════════════
                  if (_isUnifiedPlan) ...[
                    _buildInstallmentTableCard(
                      title: 'Ortak Konsolide Taksit Tablosu',
                      category: 'Genel',
                      totalAmount: _amountToInstallment,
                      installments: _unifiedInstallmentsList,
                      onBalance: () {
                        _distributeRemainderToSubsequentInstallments(
                          list: _unifiedInstallmentsList,
                          targetTotal: _amountToInstallment,
                          key: 'Genel',
                        );
                      },
                    ),
                  ] else ...[
                    // ═════════════════════════════════════════════════════════
                    // EĞER AYRI İSE: HER KALEM İÇİN KENDİ BAĞIMSIZ TABLOSU
                    // ═════════════════════════════════════════════════════════
                    ..._perCategoryInstallments.entries.map((entry) {
                      final catName = entry.key;
                      final catInsts = entry.value;
                      final catNet = _getItemNetAmount(catName);
                      final instCount = _perTypeInstallmentCount[catName] ?? 10;
                      final firstDue = _perTypeFirstDueDate[catName] ?? DateTime.now().add(const Duration(days: 15));

                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Kaleme Özel Ayar Başlığı (Ayrı Vade Başlangıcı ve Taksit Sayısı)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.only(topLeft: Radius.circular(19), topRight: Radius.circular(19)),
                                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(10)),
                                    child: Icon(_getIconForPriceType(catName), color: const Color(0xFF4F46E5), size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('$catName Taksit Planı', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: const Color(0xFF1E293B))),
                                        Text('Net Bedel: ${_currencyFormat.format(catNet)}', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: const Color(0xFF4F46E5))),
                                      ],
                                    ),
                                  ),
                                  // Taksit Sayısı Seçici
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<int>(
                                        value: instCount,
                                        isDense: true,
                                        items: List.generate(12, (i) => i + 1)
                                            .map((n) => DropdownMenuItem(value: n, child: Text('$n Taksit', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF334155)))))
                                            .toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() => _perTypeInstallmentCount[catName] = val);
                                            _recomputeInstallments();
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Kaleme Özel Başlangıç Tarihi
                                  InkWell(
                                    onTap: () async {
                                      final picked = await CustomDateRangePicker.showSingle(
                                        context,
                                        initialDate: firstDue,
                                      );
                                      if (picked != null) {
                                        setState(() => _perTypeFirstDueDate[catName] = picked);
                                        _recomputeInstallments();
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFFCBD5E1)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF4F46E5)),
                                          const SizedBox(width: 6),
                                          Text(_dateFormat.format(firstDue), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _distributeRemainderToSubsequentInstallments(
                                      list: catInsts,
                                      targetTotal: catNet,
                                      key: catName,
                                    ),
                                    icon: const Icon(Icons.auto_awesome_rounded, size: 14),
                                    label: const Text('Kalan Aylara Eşit Dağıt'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFEEF2FF),
                                      foregroundColor: const Color(0xFF4F46E5),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                      textStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Kaleme Ait Taksit Listesi
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: catInsts.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              itemBuilder: (context, cIdx) {
                                final inst = catInsts[cIdx];
                                final ctrl = inst['controller'] as TextEditingController;
                                final isNotLast = cIdx < catInsts.length - 1;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 13,
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        child: Text('${cIdx + 1}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF4F46E5))),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(inst['title'] ?? '${cIdx + 1}. Taksit', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF1E293B))),
                                      ),
                                      // Vade Seçimi
                                      InkWell(
                                        onTap: () async {
                                          DateTime initDate = DateTime.now();
                                          try {
                                            final parts = (inst['dueDate'] as String).split('.');
                                            if (parts.length == 3) {
                                              initDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                                            }
                                          } catch (_) {}
                                          final picked = await CustomDateRangePicker.showSingle(
                                            context,
                                            initialDate: initDate,
                                          );
                                          if (picked != null) {
                                            setState(() => inst['dueDate'] = _dateFormat.format(picked));
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF8FAFC),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFFE2E8F0)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.event, size: 14, color: Color(0xFF4F46E5)),
                                              const SizedBox(width: 6),
                                              Text(inst['dueDate'] ?? '-', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      // Tutar Kutusu (Türk Lirası Canlı Maske Formatter)
                                      SizedBox(
                                        width: 140,
                                        child: TextField(
                                          controller: ctrl,
                                          textAlign: TextAlign.right,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [TurkishCurrencyInputFormatter()],
                                          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
                                          decoration: InputDecoration(
                                            suffixText: ' ₺',
                                            filled: true,
                                            fillColor: const Color(0xFFF8FAFC),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                          ),
                                          onChanged: (_) {
                                            _lastEditedInstallmentIndex[catName] = cIdx;
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                      if (isNotLast) ...[
                                        const SizedBox(width: 6),
                                        IconButton(
                                          icon: const Icon(Icons.keyboard_double_arrow_down_rounded, size: 18, color: Color(0xFF4F46E5)),
                                          tooltip: 'Bu tutarı baz al, kalan eksik/fazlayı sonraki aylara eşit dağıt',
                                          onPressed: () {
                                            _distributeRemainderToSubsequentInstallments(
                                              list: catInsts,
                                              targetTotal: catNet,
                                              key: catName,
                                              fromIndex: cIdx,
                                            );
                                          },
                                        ),
                                      ] else ...[
                                        const SizedBox(width: 46),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],

                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallmentTableCard({
    required String title,
    required String category,
    required double totalAmount,
    required List<Map<String, dynamic>> installments,
    required VoidCallback onBalance,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(19), topRight: Radius.circular(19)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: const Color(0xFF1E293B))),
                Row(
                  children: [
                    Text('Toplam: ${_currencyFormat.format(totalAmount)}', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF4F46E5))),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: onBalance,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 14),
                      label: const Text('Kalan Aylara Eşit Dağıt'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEEF2FF),
                        foregroundColor: const Color(0xFF4F46E5),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: installments.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (context, idx) {
              final inst = installments[idx];
              final ctrl = inst['controller'] as TextEditingController;
              final isNotLast = idx < installments.length - 1;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: const Color(0xFFEEF2FF),
                      child: Text('${idx + 1}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF4F46E5))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(inst['title'] ?? '${idx + 1}. Taksit', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF1E293B))),
                    ),
                    InkWell(
                      onTap: () async {
                        DateTime initDate = DateTime.now();
                        try {
                          final parts = (inst['dueDate'] as String).split('.');
                          if (parts.length == 3) {
                            initDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                          }
                        } catch (_) {}
                        final picked = await CustomDateRangePicker.showSingle(
                          context,
                          initialDate: initDate,
                        );
                        if (picked != null) {
                          setState(() => inst['dueDate'] = _dateFormat.format(picked));
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event, size: 14, color: Color(0xFF4F46E5)),
                            const SizedBox(width: 6),
                            Text(inst['dueDate'] ?? '-', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: ctrl,
                        textAlign: TextAlign.right,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [TurkishCurrencyInputFormatter()],
                        style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
                        decoration: InputDecoration(
                          suffixText: ' ₺',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        onChanged: (_) {
                          _lastEditedInstallmentIndex['Genel'] = idx;
                          setState(() {});
                        },
                      ),
                    ),
                    if (isNotLast) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.keyboard_double_arrow_down_rounded, size: 18, color: Color(0xFF4F46E5)),
                        tooltip: 'Bu tutarı baz al, kalan eksik/fazlayı sonraki aylara eşit dağıt',
                        onPressed: () {
                          _distributeRemainderToSubsequentInstallments(
                            list: installments,
                            targetTotal: totalAmount,
                            key: 'Genel',
                            fromIndex: idx,
                          );
                        },
                      ),
                    ] else ...[
                      const SizedBox(width: 46),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPriceCard(String label, double amount, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _currencyFormat.format(amount),
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveOfferAsPlan() async {
    final planName = _planNameCtrl.text.trim();
    if (planName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen sözleşme başlığı girin'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_subtotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir hizmet kalemine tutar girin'), backgroundColor: Colors.red),
      );
      return;
    }

    final diff = (_enteredInstallmentsSum - _amountToInstallment).abs();
    if (diff > 1.0 && _allActiveInstallmentsList.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Taksit tutarları ile borç tutarı uyuşmuyor! Lütfen kontrol edin.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final activeItems = _priceTypes.map((type) {
        final ctrl = _priceControllers[type];
        final amt = parseCurrency(ctrl?.text);
        return {
          'name': type,
          'amount': amt,
          'paymentType': _perTypePaymentMethod[type] ?? 'installment',
          'installmentCount': _perTypePaymentMethod[type] == 'cash' ? null : (_isUnifiedPlan ? _unifiedInstallmentCount : _perTypeInstallmentCount[type]),
        };
      }).toList();

      final appliedDiscs = _selectedDiscountIds.map((dId) {
        final d = _discounts.firstWhere((e) => e['id'] == dId, orElse: () => {});
        return {
          'id': dId,
          'name': d['name'] ?? '',
          'percentage': _customDiscountPercentages[dId] ?? d['percentage'],
          'reason': _customDiscountReasons[dId] ?? '',
        };
      }).toList();

      final cleanInsts = _allActiveInstallmentsList.map((inst) {
        final ctrl = inst['controller'] as TextEditingController;
        final amt = parseCurrency(ctrl.text);
        return {
          'no': inst['no'],
          'title': inst['title'],
          'category': inst['category'],
          'amount': amt,
          'dueDate': inst['dueDate'],
          'status': 'unpaid',
        };
      }).toList();

      final doc = {
        'studentId': widget.studentId,
        'studentName': widget.studentData?['fullName'] ?? widget.studentData?['name'] ?? '',
        'studentNo': widget.studentData?['studentNo'] ?? '',
        'institutionId': widget.institutionId ?? widget.studentData?['institutionId'],
        'name': planName,
        'items': activeItems,
        'appliedDiscounts': appliedDiscs,
        'grossTotal': _subtotal,
        'totalDiscount': _totalDiscountAmount,
        'netTotal': _netContractTotal,
        'downPayment': _cashTotal,
        'downPaymentPaid': false,
        'isUnifiedPlan': _isUnifiedPlan,
        'installmentCount': cleanInsts.length,
        'installments': cleanInsts,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('payment_plans').add(doc);
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  IconData _getIconForPriceType(String? name) {
    if (name == null) return Icons.category_rounded;
    final n = name.toLowerCase();
    if (n.contains('eğitim')) return Icons.school_rounded;
    if (n.contains('yemek')) return Icons.restaurant_rounded;
    if (n.contains('kitap')) return Icons.menu_book_rounded;
    if (n.contains('servis')) return Icons.directions_bus_rounded;
    if (n.contains('kıyafet') || n.contains('üniforma')) return Icons.checkroom_rounded;
    return Icons.payments_rounded;
  }
}
