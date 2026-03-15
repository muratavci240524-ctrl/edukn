import 'package:flutter/material.dart';
import 'attendance/attendance_dashboard.dart';
import 'shifts/shift_management_screen.dart';

class AttendanceScreen extends StatelessWidget {
  static const routeName = '/hr/attendance';
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devam – Mesai – İzin Yönetimi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMenuCard(
            context,
            title: 'Puantaj ve Devam Takibi',
            subtitle: 'Giriş/Çıkış yap, çalışma süreni gör',
            icon: Icons.access_time,
            color: Colors.blue,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AttendanceDashboard()),
            ),
          ),
          const SizedBox(height: 16),
          _buildMenuCard(
            context,
            title: 'Mesai ve Vardiya',
            subtitle: 'Vardiya planı ve fazla mesai',
            icon: Icons.calendar_month,
            color: Colors.orange,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ShiftManagementScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _buildMenuCard(
            context,
            title: 'İzin Yönetimi',
            subtitle: 'İzin talebi ve bakiye sorgulama',
            icon: Icons.beach_access,
            color: Colors.green,
            onTap: () {
              // TODO: İzin ekranına git
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Bu modül henüz aktif değil.')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
