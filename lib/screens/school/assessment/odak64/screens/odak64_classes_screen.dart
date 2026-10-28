import 'package:edukn/widgets/edukn_app_bar.dart';
import 'package:flutter/material.dart';

import '../models/odak_models.dart';
import '../services/odak_engine.dart';
import '../services/odak_pdf_service.dart';
import '../services/odak_excel_service.dart';
import '../widgets/odak_class_report_card.dart';
import '../widgets/odak_export_bar.dart';
import '../widgets/odak_print_dialog.dart';

/// ODAK-64: Oluşturulan sınıflar ve her sınıf için ders bazlı raporlar.
class Odak64ClassesScreen extends StatelessWidget {
  final List<OdakClassGroup> groups;
  final OdakAnalyzer analyzer;
  final List<String> subjects;
  final String examName;
  final String? schoolTypeName;
  final String title;
  final String heading;
  final String brand;

  const Odak64ClassesScreen({
    super.key,
    required this.groups,
    required this.analyzer,
    required this.subjects,
    required this.examName,
    this.schoolTypeName,
    this.title = 'ODAK-64 • Sınıflar',
    this.heading = 'Oluşturulan Sınıflar',
    this.brand = 'ODAK-64',
  });

  @override
  Widget build(BuildContext context) {
    final total = OdakClassGroup.visibleGroups(groups).fold<int>(0, (a, g) => a + g.students.length);
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: EduknAppBar(
          title: title,
          subtitle: schoolTypeName,
          actions: [
            Builder(
              builder: (ctx) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  onPressed: () => showOdakPrintDialog(
                    ctx,
                    groups: groups,
                    analyzer: analyzer,
                    subjects: subjects,
                    examName: examName,
                    schoolName: schoolTypeName,
 brand: brand,
                  ),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('Yazdır'),
                ),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.teal.shade700,
                          Colors.cyan.shade800,
                          Colors.blue.shade900,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          heading,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$examName • ${OdakClassGroup.visibleGroups(groups).length} sınıf • $total öğrenci\n'
                          'Dersler: ${subjects.join(', ')}',
                          style: const TextStyle(color: Colors.white70, height: 1.4),
                        ),
                        const SizedBox(height: 14),
                        OdakExportBar(
                          dark: true,
                          fileName: '${OdakPdfService.fileBase(brand)}_Tum_Siniflar.pdf',
                          title: '$brand Sınıf Raporları',
                          shareText:
                              '$brand sınıf raporları ($examName) ektedir.',
                          doorExcel: () => OdakExcelService.saveDoorList(
                            groups: groups,
                            examName: examName,
                            schoolName: schoolTypeName,
                            fileName: 'Kapi_Listesi_Tum_Siniflar',
                          ),
                          buildDoorList: brand != 'ODAK-64' ? null : () => OdakPdfService.buildDoorList(
                            groups: groups,
                            examName: examName,
                            schoolName: schoolTypeName,
                            brand: brand,
                          ),
                          buildPdf: () => OdakPdfService.build(
                            groups: groups,
                            analyzer: analyzer,
                            subjects: subjects,
                            examName: examName,
                            schoolName: schoolTypeName,
 brand: brand,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final g in OdakClassGroup.visibleGroups(groups))
                    OdakClassReportCard(
                      key: ValueKey('odak-class-${g.id}'),
                      group: g,
                      analyzer: analyzer,
                      subjects: subjects,
                      examName: examName,
                      schoolName: schoolTypeName,
 brand: brand,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
