import 'package:flutter/material.dart';

import 'single_exam_results_screen.dart';
import 'combined_exam_results_screen.dart';
import 'reinforcement/reinforcement_dashboard_screen.dart';
import 'agm/screens/agm_dashboard_screen.dart';

class AssessmentReportsScreen extends StatelessWidget {
  final String institutionId;
  final String schoolTypeId;

  const AssessmentReportsScreen({
    Key? key,
    required this.institutionId,
    required this.schoolTypeId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Raporlar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildMenuCard(
                  context,
                  title: 'Tekil Sınav Raporları',
                  subtitle: 'Tek bir sınavın detaylı analiz ve raporları',
                  icon: Icons.description,
                  color: Colors.blue,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SingleExamResultsScreen(
                          institutionId: institutionId,
                          schoolTypeId: schoolTypeId,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildMenuCard(
                  context,
                  title: 'Birleştirilmiş Sınav Raporları',
                  subtitle: 'Birden fazla sınavın karşılaştırmalı raporları',
                  icon: Icons.library_books,
                  color: Colors.purple,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CombinedExamResultsScreen(
                          institutionId: institutionId,
                          schoolTypeId: schoolTypeId,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildMenuCard(
                  context,
                  title: 'Güçlendirme Programları',
                  subtitle: 'Öğrenci eksiklerine göre çalışma programları',
                  icon: Icons.trending_up,
                  color: Colors.teal,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ReinforcementDashboardScreen(
                          institutionId: institutionId,
                          schoolTypeId: schoolTypeId,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildMenuCard(
                  context,
                  title: 'AGM – Akademik Güçlendirme',
                  subtitle: 'Otomatik etüt grubu yerleştirme sistemi',
                  icon: Icons.model_training,
                  color: Colors.deepOrange,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AgmDashboardScreen(
                          institutionId: institutionId,
                          schoolTypeId: schoolTypeId,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
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
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.grey[300], size: 16),
          ],
        ),
      ),
    );
  }
}
