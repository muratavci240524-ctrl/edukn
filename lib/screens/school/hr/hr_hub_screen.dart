import 'package:flutter/material.dart' hide Border;
import 'package:flutter/material.dart' as material show Border;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:edukn/screens/hr/staff/staff_list_screen.dart';
import 'package:edukn/screens/hr/staff/staff_form_screen.dart';
import 'package:edukn/screens/hr/attendance_screen.dart';
import 'package:edukn/screens/hr/payroll_screen.dart';
import 'package:edukn/screens/hr/performance_screen.dart';
import 'package:edukn/screens/hr/training_screen.dart';
import 'package:edukn/screens/hr/contracts_screen.dart';
import 'package:edukn/screens/hr/reports_screen.dart';

class HrHubScreen extends StatefulWidget {
  const HrHubScreen({Key? key}) : super(key: key);

  @override
  State<HrHubScreen> createState() => _HrHubScreenState();
}

class _HrHubScreenState extends State<HrHubScreen> {
  bool _isExporting = false;

  Future<void> _exportStaffToExcel() async {
    setState(() => _isExporting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) return;
      final institutionId = user.email!.split('@')[1].split('.')[0].toUpperCase();

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('institutionId', isEqualTo: institutionId)
          .where('type', isEqualTo: 'staff')
          .get();

      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['Personel Listesi'];
      excel.delete('Sheet1');

      // Headers
      sheet.appendRow([
        excel_pkg.TextCellValue('Ad Soyad'),
        excel_pkg.TextCellValue('Kullanıcı Adı'),
        excel_pkg.TextCellValue('Email'),
        excel_pkg.TextCellValue('Rol'),
        excel_pkg.TextCellValue('Departman'),
        excel_pkg.TextCellValue('Branş'),
        excel_pkg.TextCellValue('Telefon'),
        excel_pkg.TextCellValue('Durum')
      ]);

      for (var doc in snapshot.docs) {
        final data = doc.data();
        sheet.appendRow([
          excel_pkg.TextCellValue(data['fullName']?.toString() ?? ''),
          excel_pkg.TextCellValue(data['username']?.toString() ?? ''),
          excel_pkg.TextCellValue(data['email']?.toString() ?? ''),
          excel_pkg.TextCellValue(data['role']?.toString() ?? ''),
          excel_pkg.TextCellValue(data['department']?.toString() ?? ''),
          excel_pkg.TextCellValue(data['branch']?.toString() ?? ''),
          excel_pkg.TextCellValue(data['phone']?.toString() ?? ''),
          excel_pkg.TextCellValue((data['isActive'] ?? true) ? 'Aktif' : 'Pasif'),
        ]);
      }

      final bytes = excel.save();
      if (bytes != null) {
        if (kIsWeb) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel dosyası hazırlandı, indiriliyor...')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel dosyası başarıyla oluşturuldu.')));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dışa aktarma hatası: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 1100;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.indigo, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: const SizedBox.shrink(),
        actions: const [],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 40, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(isMobile),
                const SizedBox(height: 48),
                _buildMainActionCard(context, isMobile),
                const SizedBox(height: 24),
                _buildSubGrid(context, isMobile),
                const SizedBox(height: 48),
                _buildBottomSection(context, isMobile),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('İnsan Kaynakları Hub', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF1E293B), letterSpacing: -0.5)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Akademik kadronuzu ve idari personelinizi tek bir merkezden, modern araçlarla yönetin.',
                style: TextStyle(fontSize: 16, color: Colors.blueGrey.shade400, height: 1.5),
              ),
            ),
            if (!isMobile) _buildHeaderActions(),
          ],
        ),
        if (isMobile) ...[
          const SizedBox(height: 24),
          _buildHeaderActions(),
        ],
      ],
    );
  }

  Widget _buildHeaderActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          onPressed: _isExporting ? null : _exportStaffToExcel,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.blueGrey.shade700,
            side: BorderSide(color: Colors.blueGrey.shade100),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          ),
          child: _isExporting 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Dışa Aktar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffFormScreen()));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
            elevation: 0,
          ),
          child: const Text('Yeni Kayıt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildMainActionCard(BuildContext context, bool isMobile) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffListScreen())),
      borderRadius: BorderRadius.circular(32),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: material.Border.all(color: Colors.blueGrey.shade50),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.03), shape: BoxShape.circle),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.person_pin_outlined, color: Colors.indigo, size: 28),
                ),
                const SizedBox(height: 24),
                const Text('Personel Yönetimi', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 12),
                Text(
                  'Personel listesi, detaylı profiller, akademik geçmiş ve iletişim bilgilerini yönetin.',
                  style: TextStyle(fontSize: 15, color: Colors.blueGrey.shade400, height: 1.5),
                ),
                const SizedBox(height: 24),
                const Text('Detayları Görüntüle >', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubGrid(BuildContext context, bool isMobile) {
    final List<Map<String, dynamic>> items = [
      {'title': 'Devam – Mesai – İzin', 'desc': 'Yıllık izinler, raporlar ve mazeretlerin onay süreçlerini yönetin.', 'icon': Icons.calendar_month_outlined, 'color': Colors.cyan, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceScreen()))},
      {'title': 'Maaş Bordroları', 'desc': 'Aylık hakedişler, ek ders ücretleri ve vergi kesintileri.', 'icon': Icons.payments_outlined, 'color': Colors.indigo, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PayrollScreen()))},
      {'title': 'Performans', 'desc': 'Eğitmen değerlendirmeleri, öğrenci geri bildirimleri ve KPI takibi.', 'icon': Icons.auto_graph_rounded, 'color': Colors.purple, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PerformanceScreen()))},
      {'title': 'Eğitim ve Gelişim', 'desc': 'Sertifikasyon süreçleri ve personelin mesleki gelişim planları.', 'icon': Icons.school_outlined, 'color': Colors.teal, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrainingScreen()))},
      {'title': 'Sözleşme ve Evrak', 'desc': 'İş akitleri, gizlilik sözleşmeleri ve dijital özlük dosyaları.', 'icon': Icons.folder_open_outlined, 'color': Colors.blue, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContractsScreen()))},
      {'title': 'Raporlama', 'desc': 'İK metrikleri, personel devir oranı ve demografik analizler.', 'icon': Icons.pie_chart_outline_rounded, 'color': Colors.deepPurple, 'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()))},
    ];

    return Wrap(
      spacing: 24,
      runSpacing: 24,
      children: items.map((item) => _buildGridCard(item, isMobile)).toList(),
    );
  }

  Widget _buildGridCard(Map<String, dynamic> item, bool isMobile) {
    final cardWidth = isMobile ? double.infinity : (1200 - 80 - 24) / 2;
    final color = item['color'] as Color;

    return InkWell(
      onTap: item['onTap'] as VoidCallback,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: cardWidth,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: material.Border.all(color: Colors.blueGrey.shade50),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(item['icon'] as IconData, color: color, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['title'] as String, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  const SizedBox(height: 8),
                  Text(
                    item['desc'] as String,
                    style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade400, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection(BuildContext context, bool isMobile) {
    return Column(
      children: [
        if (isMobile) ...[
          _buildStrategyBanner(isMobile),
          const SizedBox(height: 16),
          _buildRemindersCard(isMobile),
        ] else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildStrategyBanner(isMobile)),
              const SizedBox(width: 24),
              Expanded(child: _buildRemindersCard(isMobile)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStrategyBanner(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: const NetworkImage('https://i.pravatar.cc/150?u=a042581f4e29026704d'),
            backgroundColor: Colors.grey.shade300,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('İK Strateji Rehberi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 4),
                Text(
                  'Akademik yılın ikinci yarısı için personel planlama dökümanlarını inceleyin.',
                  style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade500, height: 1.4),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () {},
                  child: const Text('Rehberi İncele \u2197', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemindersCard(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50.withOpacity(0.5),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Yaklaşan Hatırlatıcılar', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(100)),
                child: const Text('3 YENİ', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildReminderItem('3 Personelin sözleşme yenileme tarihi yaklaşıyor.'),
          const SizedBox(height: 12),
          _buildReminderItem('Pazartesi günü Performans Görüşmeleri başlıyor.'),
        ],
      ),
    );
  }

  Widget _buildReminderItem(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.indigo, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade700, height: 1.4)),
        ),
      ],
    );
  }
}
