import 'package:flutter/material.dart';
import 'staff/staff_list_screen.dart';
import 'attendance_screen.dart';
import 'payroll_screen.dart';
import 'performance_screen.dart';
import 'training_screen.dart';
import 'contracts_screen.dart';
import 'reports_screen.dart';
import 'notifications_screen.dart';

class HrHomeScreen extends StatelessWidget {
  static const routeName = '/hr';

  const HrHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      _HrItem('Personel Bilgi Yönetimi', 'Personel listesi ve detaylar', Icons.badge, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StaffListScreen()),
        );
      }),
      _HrItem('Devam – Mesai – İzin', 'Vardiya, izin ve yoklama', Icons.schedule, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AttendanceScreen()),
        );
      }),
      _HrItem('Maaş ve Bordro', 'Maaş kalemleri ve bordro', Icons.payments, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PayrollScreen()),
        );
      }),
      _HrItem('Performans', 'Hedefler ve değerlendirme', Icons.assessment, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PerformanceScreen()),
        );
      }),
      _HrItem('Eğitim ve Gelişim', 'PD / Hizmet içi eğitim', Icons.school, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TrainingScreen()),
        );
      }),
      _HrItem('Sözleşme ve Evrak', 'Sözleşmeler ve evrak', Icons.description, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContractsScreen()),
        );
      }),
      _HrItem('Raporlama', 'Analitik ve raporlar', Icons.pie_chart, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReportsScreen()),
        );
      }),
      _HrItem('Bildirimler', 'Uyarılar ve hatırlatmalar', Icons.notifications_active, () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
      }),
    ];

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.pushReplacementNamed(context, '/school-dashboard');
            }
          },
        ),
        title: const Text('İnsan Kaynakları'),
        elevation: 1,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1400),
          padding: const EdgeInsets.all(16),
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _HrHorizontalCard(item: items[i]),
          ),
        ),
      ),
    );
  }
}

class _HrItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  _HrItem(this.title, this.subtitle, this.icon, this.onTap);
}

class _HrHorizontalCard extends StatelessWidget {
  final _HrItem item;
  const _HrHorizontalCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, size: 28, color: Colors.indigo),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
