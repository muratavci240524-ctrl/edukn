import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:edukn/models/assessment/trial_exam_model.dart';
import '../models/camp_cycle_model.dart';
import '../models/camp_group_model.dart';
import '../models/camp_assignment_model.dart';
import '../widgets/agm_web_share_dialog.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' hide Border;

class CampTeacherTimetableScreen extends StatefulWidget {
  final CampCycle cycle;
  final List<CampGroup> groups;
  final Map<String, List<CampAssignment>> assignmentsByGroup;

  const CampTeacherTimetableScreen({
    Key? key,
    required this.cycle,
    required this.groups,
    required this.assignmentsByGroup,
  }) : super(key: key);

  @override
  State<CampTeacherTimetableScreen> createState() => _CampTeacherTimetableScreenState();
}

class _CampTeacherTimetableScreenState extends State<CampTeacherTimetableScreen> {
  String? _selectedTeacherId;
  String? _selectedTeacherName;
  String _searchQuery = '';
  List<Map<String, dynamic>> _teachers = [];
  List<CampGroup> _teacherGroups = [];
  bool _isGenerating = false;
  String _generationMessage = '';

  final List<String> _gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

  @override
  void initState() {
    super.initState();
    _buildTeacherList();
  }

  void _buildTeacherList() {
    final Map<String, Map<String, dynamic>> teacherMap = {};
    for (final g in widget.groups) {
      if (g.ogretmenId.isEmpty) continue;
      if (!teacherMap.containsKey(g.ogretmenId)) {
        teacherMap[g.ogretmenId] = {'id': g.ogretmenId, 'name': g.ogretmenAdi, 'count': 1};
      } else {
        teacherMap[g.ogretmenId]!['count']++;
      }
    }
    _teachers = teacherMap.values.toList()..sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
  }

  void _loadTeacherTimetable(String teacherId) {
    setState(() {
      _selectedTeacherId = teacherId;
      _selectedTeacherName = _teachers.firstWhere((t) => t['id'] == teacherId)['name'];
      _teacherGroups = widget.groups.where((g) => g.ogretmenId == teacherId).toList()
        ..sort((a, b) => _gunler.indexOf(a.gun).compareTo(_gunler.indexOf(b.gun)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.grey.shade50,
          appBar: AppBar(
            title: const Text('Öğretmen Haftalık Takvim', style: TextStyle(color: Colors.white, fontSize: 16)),
            backgroundColor: Colors.orange.shade700,
            foregroundColor: Colors.white,
            centerTitle: true,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) {
                  final allSelected = _selectedTeacherId == null;
                  switch (value) {
                    case 'excel':
                      _exportExcel(allTeachers: allSelected);
                      break;
                    case 'print':
                      _printPDF(allTeachers: allSelected, isShare: false);
                      break;
                    case 'share':
                      _printPDF(allTeachers: allSelected, isShare: true);
                      break;
                    case 'email':
                      _sendProgramEmail(allTeachers: allSelected);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'excel',
                    child: Row(
                      children: [Icon(Icons.description, color: Colors.green, size: 20), SizedBox(width: 12), Text('Excel İndir')],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'print',
                    child: Row(
                      children: [Icon(Icons.print, color: Colors.blue, size: 20), SizedBox(width: 12), Text('Yazdır (PDF)')],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [Icon(Icons.share, color: Colors.deepOrange, size: 20), SizedBox(width: 12), Text('Paylaş')],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'email',
                    child: Row(
                      children: [
                        const Icon(Icons.email, color: Colors.indigo, size: 20),
                        const SizedBox(width: 12),
                        Text(_selectedTeacherId == null 
                            ? 'E-Posta Gönder (Tümü)' 
                            : 'E-Posta Gönder'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(children: [_buildSelector(), Expanded(child: _selectedTeacherId == null ? _buildNoState() : _buildTimetable())]),
        ),
        if (_isGenerating)
          Container(
            color: Colors.black.withOpacity(0.3),
            child: Center(
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.orange, strokeWidth: 3),
                      const SizedBox(height: 20),
                      Text(
                        _generationMessage.isNotEmpty && _generationMessage.contains('\n')
                            ? _generationMessage.split('\n')[0]
                            : (_generationMessage.isNotEmpty ? _generationMessage : 'Rapor Hazırlanıyor...'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _generationMessage.isNotEmpty && _generationMessage.contains('\n')
                            ? _generationMessage.split('\n')[1]
                            : 'Veriler işleniyor, lütfen bekleyin.',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSelector() {
    return Container(
      padding: const EdgeInsets.all(16), color: Colors.white,
      child: InkWell(
        onTap: _showSearchSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Row(children: [
            Icon(Icons.person_search, color: Colors.orange.shade400),
            const SizedBox(width: 12),
            Expanded(child: Text(_selectedTeacherId == null ? 'Öğretmen Ara ve Seç...' : '$_selectedTeacherName (${_teacherGroups.length} grup)', style: TextStyle(color: _selectedTeacherId == null ? Colors.grey.shade600 : Colors.black87, fontWeight: _selectedTeacherId == null ? FontWeight.normal : FontWeight.bold))),
            Icon(Icons.arrow_drop_down, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }

  void _showSearchSheet() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => DraggableScrollableSheet(initialChildSize: 0.8, builder: (ctx, ctrl) => StatefulBuilder(builder: (ctx, setSS) {
      final filtered = _teachers.where((t) => t['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase())).toList();
      return Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          const SizedBox(height: 12), Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.all(16), child: TextField(autofocus: true, onChanged: (v) => setSS(() => _searchQuery = v), decoration: InputDecoration(hintText: 'Öğretmen ara...', prefixIcon: const Icon(Icons.search, color: Colors.orange), filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
          Expanded(child: ListView.builder(controller: ctrl, itemCount: filtered.length, itemBuilder: (ctx, i) {
            final t = filtered[i];
            return ListTile(leading: CircleAvatar(backgroundColor: Colors.orange.shade50, child: const Icon(Icons.person, color: Colors.orange)), title: Text(t['name']), subtitle: Text('${t['count']} grup'), onTap: () { _loadTeacherTimetable(t['id']); Navigator.pop(ctx); });
          })),
        ]),
      );
    })));
  }

  Widget _buildNoState() => Center(child: Text('Lütfen programını görüntülemek istediğiniz öğretmeni seçin.', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)));

  Widget _buildTimetable() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _teacherGroups.length,
      itemBuilder: (ctx, i) {
        final g = _teacherGroups[i];
        final assignments = widget.assignmentsByGroup[g.id] ?? [];
        
        final sortedAssignments = assignments.toList()
          ..sort((a, b) => b.basariOrani.compareTo(a.basariOrani));
          
        double avgSuccess = 0.0;
        if (assignments.isNotEmpty) {
          avgSuccess = assignments.map((a) => a.basariOrani).reduce((a, b) => a + b) / assignments.length;
        }

        return Card(
          clipBehavior: Clip.antiAlias, // FIX HOVER CORNERS OVERFLOW
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            backgroundColor: Colors.orange.shade50.withOpacity(0.4),
            collapsedBackgroundColor: Colors.white,
            iconColor: Colors.orange.shade700,
            collapsedIconColor: Colors.grey.shade600,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Row(
               crossAxisAlignment: CrossAxisAlignment.center,
               children: [
                 Expanded(
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Text(
                         '${g.gun} • ${g.baslangicSaat}-${g.bitisSaat}', 
                         style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)
                       ),
                       const SizedBox(height: 4),
                       Text('${g.dersAdi} • ${assignments.length} öğrenci', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                     ],
                   ),
                 ),
                 if (assignments.isNotEmpty)
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                     decoration: BoxDecoration(
                       color: avgSuccess >= 0.7 ? Colors.green.shade50 : (avgSuccess >= 0.5 ? Colors.orange.shade50 : Colors.red.shade50),
                       borderRadius: BorderRadius.circular(20),
                       border: Border.all(color: avgSuccess >= 0.7 ? Colors.green.shade200 : (avgSuccess >= 0.5 ? Colors.orange.shade200 : Colors.red.shade200)),
                     ),
                     child: Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         Icon(
                           avgSuccess >= 0.7 ? Icons.trending_up : (avgSuccess >= 0.5 ? Icons.trending_flat : Icons.trending_down),
                           size: 14, 
                           color: avgSuccess >= 0.7 ? Colors.green.shade700 : (avgSuccess >= 0.5 ? Colors.orange.shade700 : Colors.red.shade700)
                         ),
                         const SizedBox(width: 4),
                         Text(
                           '%${(avgSuccess * 100).toStringAsFixed(0)} Ort.', 
                           style: TextStyle(
                             fontSize: 12, 
                             fontWeight: FontWeight.bold,
                             color: avgSuccess >= 0.7 ? Colors.green.shade700 : (avgSuccess >= 0.5 ? Colors.orange.shade700 : Colors.red.shade700),
                           )
                         ),
                       ],
                     ),
                   )
               ]
            ),
            children: [
              const Divider(height: 1, thickness: 1),
              if (assignments.isEmpty) 
                Padding(
                  padding: const EdgeInsets.all(24), 
                  child: Center(child: Text('Bu derse kayıtlı öğrenci bulunmuyor.', style: TextStyle(color: Colors.grey.shade500)))
                )
              else 
                ...sortedAssignments.map((a) {
                  final successPercent = (a.basariOrani * 100).round();
                  return Container(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                      color: Colors.white,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.orange.shade100,
                        child: Icon(Icons.person_outline, size: 20, color: Colors.orange.shade800),
                      ), 
                      title: Text(a.ogrenciAdi, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87)), 
                      subtitle: Text('Şube: ${a.sube ?? '-'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      trailing: Container(
                         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                         decoration: BoxDecoration(
                           color: successPercent >= 70 ? Colors.green.shade50 : (successPercent >= 50 ? Colors.orange.shade50 : Colors.red.shade50),
                           borderRadius: BorderRadius.circular(8),
                         ),
                         child: Text(
                           '%$successPercent', 
                           style: TextStyle(
                             fontSize: 13, 
                             fontWeight: FontWeight.bold,
                             color: successPercent >= 70 ? Colors.green.shade700 : (successPercent >= 50 ? Colors.orange.shade700 : Colors.red.shade700),
                           )
                         ),
                      ),
                    ),
                  );
                }).toList(),
            ],
          ),
        );
      },
    );
  }

  String _norm(String t) {
    if (t.isEmpty) return t;
    return t.replaceAll('u\u0308', 'ü').replaceAll('U\u0308', 'Ü').replaceAll('o\u0308', 'ö').replaceAll('O\u0308', 'Ö').replaceAll('c\u0327', 'ç').replaceAll('C\u0327', 'Ç').replaceAll('s\u0327', 'ş').replaceAll('S\u0327', 'Ş').replaceAll('g\u0306', 'ğ').replaceAll('G\u0306', 'Ğ').replaceAll('I\u0307', 'İ').replaceAll('i\u0307', 'i');
  }

  String _getActualDateString(String gunString) {
    int? targetWeekday;
    final normalized = gunString.toUpperCase();
    if (normalized.contains('PZT') || normalized.contains('PAZARTESİ')) targetWeekday = 1;
    else if (normalized.contains('SAL')) targetWeekday = 2;
    else if (normalized.contains('ÇAR')) targetWeekday = 3;
    else if (normalized.contains('PER')) targetWeekday = 4;
    else if (normalized.contains('CUM') && !normalized.contains('CUMARTESİ')) targetWeekday = 5;
    else if (normalized.contains('CMT') || normalized.contains('CUMARTESİ')) targetWeekday = 6;
    else if (normalized.contains('PAZ') && !normalized.contains('PAZARTESİ')) targetWeekday = 7;
    
    if (targetWeekday == null) return '';
    
    final start = widget.cycle.baslangicTarihi;
    final end = widget.cycle.bitisTarihi;
    
    // Find the date between start and end that has the targetWeekday
    for (int i = 0; i <= end.difference(start).inDays + 1; i++) {
      final d = start.add(Duration(days: i));
      if (d.weekday == targetWeekday) {
        return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
      }
    }
    return '';
  }

  String _getActualDayName(String gunString) {
    final normalized = gunString.toUpperCase();
    if (normalized.contains('PZT') || normalized.contains('PAZARTESİ')) return 'Pazartesi';
    if (normalized.contains('SAL')) return 'Salı';
    if (normalized.contains('ÇAR') || normalized.contains('ÇARŞAMBA')) return 'Çarşamba';
    if (normalized.contains('PER') || normalized.contains('PERŞEMBE')) return 'Perşembe';
    if (normalized.contains('CUM') && !normalized.contains('CUMARTESİ')) return 'Cuma';
    if (normalized.contains('CMT') || normalized.contains('CUMARTESİ')) return 'Cumartesi';
    if (normalized.contains('PAZ') && !normalized.contains('PAZARTESİ')) return 'Pazar';
    return gunString;
  }

  Future<void> _printPDF({bool allTeachers = false, bool isShare = false}) async {
    setState(() => _isGenerating = true);
    try {
      final doc = pw.Document();
      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();

      // Load system logo
      pw.MemoryImage? logoImage;
      try {
        final logoBytes = await rootBundle.load('assets/images/logo.png');
        logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
      } catch (e) {
        debugPrint('Logo load error: $e');
      }

      final teachersToPrint = allTeachers ? _teachers : [{'id': _selectedTeacherId, 'name': _selectedTeacherName}];

      final examIds = widget.cycle.referansDenemeSinavIds.isNotEmpty 
          ? widget.cycle.referansDenemeSinavIds.take(3).toList() 
          : (widget.cycle.referansDenemeSinavId.isNotEmpty ? [widget.cycle.referansDenemeSinavId] : []);
      
      List<Map<String, dynamic>> loadedExams = [];
      for (var id in examIds) {
        final examDoc = await FirebaseFirestore.instance.collection('trial_exams').doc(id).get();
        if (examDoc.exists) {
          final refExam = TrialExam.fromMap(examDoc.data()!, examDoc.id);
          List<dynamic> results = [];
          if (refExam.resultsJson != null && refExam.resultsJson!.isNotEmpty) {
            try {
              results = jsonDecode(refExam.resultsJson!);
            } catch (_) {}
          }
          if (results.isNotEmpty) {
            loadedExams.add({'exam': refExam, 'results': results});
          }
        }
      }

      // Prepend Teacher Summary Page
      if (teachersToPrint.isNotEmpty) {
        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            header: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoImage != null) ...[
                    pw.Center(
                      child: pw.Image(logoImage, height: 45),
                    ),
                    pw.SizedBox(height: 12),
                  ],
                  pw.Center(
                    child: pw.Text(
                      'KAMP ÖĞRETMEN DERS SAATLERİ ÖZETİ',
                      style: pw.TextStyle(font: fontBold, color: PdfColors.grey900, fontSize: 18),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: pw.Text(
                      'Öğretmenlerin kamp süresince yapacağı toplam ders saatleri listesi aşağıda özetlenmiştir.',
                      style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic),
                    ),
                  ),
                  pw.SizedBox(height: 16),
                ],
              );
            },
            footer: (pw.Context context) {
              return pw.Container(
                alignment: pw.Alignment.centerRight,
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Column(children: [
                  pw.Divider(color: PdfColors.grey300),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                    pw.Text('Özet Sayfa ${context.pageNumber}', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                    pw.Text('eduKN KAMP Sistemi', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                  ]),
                ]),
              );
            },
            build: (context) {
              // Calculate total hours for each teacher in teachersToPrint
              final summaryData = teachersToPrint.map((teacher) {
                final tId = teacher['id'];
                final tName = teacher['name'] ?? '';
                final tGroups = widget.groups.where((g) => g.ogretmenId == tId).toList();
                return {
                  'name': tName,
                  'hours': tGroups.length,
                };
              }).toList()..sort((a, b) {
                final cmp = (b['hours'] as int).compareTo(a['hours'] as int);
                if (cmp != 0) return cmp;
                return (a['name'] as String).compareTo(b['name'] as String);
              });

              return [
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: pw.Container(
                    width: 420,
                    child: pw.Table(
                      border: const pw.TableBorder(
                        horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                        bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                        top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                      ),
                      columnWidths: {
                        0: const pw.FixedColumnWidth(40),
                        1: const pw.FlexColumnWidth(3),
                        2: const pw.FlexColumnWidth(1.5),
                      },
                      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                          children: [
                            _tableHeader('No', fontBold, align: pw.Alignment.center),
                            _tableHeader('Öğretmen Adı', fontBold),
                            _tableHeader('Toplam Ders Saati', fontBold, align: pw.Alignment.center),
                          ],
                        ),
                        ...List.generate(summaryData.length, (idx) {
                          final data = summaryData[idx];
                          final isEven = idx % 2 == 0;
                          return pw.TableRow(
                            decoration: pw.BoxDecoration(color: isEven ? PdfColors.white : PdfColors.grey50),
                            children: [
                              _tableCell('${idx + 1}', font, align: pw.Alignment.center),
                              _tableCell(_norm(data['name'] as String), font),
                              _tableCell('${data['hours']} Saat / Seans', fontBold, align: pw.Alignment.center),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ];
            },
          ),
        );
      }

      for (final teacher in teachersToPrint) {
        final tId = teacher['id'];
        final tName = teacher['name'];
        if (tId == null) continue;

        final tGroups = widget.groups.where((g) => g.ogretmenId == tId).toList()
          ..sort((a, b) {
            int dayCompare = _gunler.indexOf(a.gun).compareTo(_gunler.indexOf(b.gun));
            if (dayCompare != 0) return dayCompare;
            return a.baslangicSaat.compareTo(b.baslangicSaat);
          });

        for (final group in tGroups) {
          final assignments = widget.assignmentsByGroup[group.id] ?? [];
          final gDersAdi = _norm(group.dersAdi);
          final gGun = _norm(group.gun);
          final gDerslik = group.derslikAdi != null ? _norm(group.derslikAdi!) : null;
          
          final double avg = assignments.isEmpty 
              ? 0.0 
              : assignments.fold(0.0, (sum, a) => sum + a.basariOrani) / assignments.length;
          final bool isHighPercentSuccess = (avg * 100).round() >= 95;
          
          final gKazanimlar = isHighPercentSuccess 
              ? ['Soru Çözümü'] 
              : group.kazanimlar.map((k) => _norm(k)).toList();

          doc.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              header: (pw.Context context) {
                return pw.Container(
                  width: double.infinity, padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12), margin: const pw.EdgeInsets.only(bottom: 8),
                  decoration: const pw.BoxDecoration(color: PdfColors.orange700),
                  child: pw.Text('KAMP ÖĞRETMEN PROGRAMI', style: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 16)),
                );
              },
              footer: (pw.Context context) {
                return pw.Container(
                  alignment: pw.Alignment.centerRight, padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Column(children: [
                    pw.Divider(color: PdfColors.grey300),
                    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                      pw.Text('Sayfa ${context.pageNumber} / ${context.pagesCount}', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                      pw.Text('eduKN KAMP Sistemi', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                    ]),
                  ]),
                );
              },
              build: (pw.Context context) {
                final analysisWidgets = <pw.Widget>[];
                for (var data in loadedExams) {
                  final w = _buildAnalysisSection(data['exam'], data['results'], group, assignments, font, fontBold);
                  if (w != null) analysisWidgets.add(w);
                }

                return [
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text('Öğretmen: ${_norm(tName)}', style: pw.TextStyle(font: fontBold, fontSize: 13)),
                      pw.Text('Ders: $gDersAdi', style: pw.TextStyle(font: font, fontSize: 11)),
                      if (gDerslik != null) pw.Text('Derslik: $gDerslik', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                    ]),
                    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                      if (_getActualDateString(group.gun).isNotEmpty)
                        pw.Text('Tarih: ${_getActualDateString(group.gun)}', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                      pw.Text('Gün: ${_getActualDayName(group.gun)}', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                      pw.Text('Saat: ${group.baslangicSaat}-${group.bitisSaat}', style: pw.TextStyle(font: font, fontSize: 11)),
                    ]),
                  ]),
                  if (gKazanimlar.isNotEmpty) ...[
                    pw.SizedBox(height: 8),
                    pw.Container(
                      width: double.infinity, padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      decoration: pw.BoxDecoration(color: PdfColors.orange50, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
                      child: pw.Text('Kazanımlar: ${gKazanimlar.join(", ")}', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.orange900)),
                    ),
                  ],
                  pw.SizedBox(height: 10),
                  pw.Text('Öğrenci Listesi (${assignments.length}):', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                  pw.SizedBox(height: 3),
                  _buildStudentListLayout(assignments, font, fontBold),
                  if (analysisWidgets.isNotEmpty) ...[
                    pw.SizedBox(height: 5),
                    pw.Divider(color: PdfColors.grey300),
                    pw.SizedBox(height: 4),
                    ...analysisWidgets,
                    pw.Align(
                      alignment: pw.Alignment.center,
                      child: pw.Text('Sorulara verilen yanlış cevap sayısı (Grup Geneli)', style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey600)),
                    ),
                  ],
                ];
              },
            ),
          );
        }
      }

      final bytes = await doc.save();
      if (isShare) {
        if (kIsWeb && !allTeachers && _selectedTeacherId != null) {
          _showWebShareDialog(bytes);
        } else {
          await Printing.sharePdf(bytes: bytes, filename: 'kamp_ogretmen_programlari.pdf');
        }
      } else {
        await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => bytes);
      }
    } catch (e) {
      debugPrint('PDF Error: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _sendProgramEmail({bool allTeachers = false}) async {
    setState(() {
      _isGenerating = true;
      _generationMessage = 'Öğretmen e-posta adresleri kontrol ediliyor...';
    });

    try {
      final List<Map<String, dynamic>> teachersToSend = allTeachers
          ? _teachers
          : [
              {'id': _selectedTeacherId, 'name': _selectedTeacherName}
            ];

      if (teachersToSend.isEmpty || teachersToSend.first['id'] == null) {
        throw 'Gönderilecek öğretmen bulunamadı!';
      }

      final List<Map<String, dynamic>> readyTeachers = [];
      final List<String> missingEmailNames = [];

      for (final teacher in teachersToSend) {
        final tId = teacher['id'] as String;
        final tName = (teacher['name'] ?? '-').toString();

        final doc = await FirebaseFirestore.instance.collection('users').doc(tId).get();
        if (doc.exists) {
          final data = doc.data();
          final email = (data?['corporateEmail'] ?? data?['email'] ?? data?['personalEmail'] ?? '').toString().trim();
          if (email.isNotEmpty && email.contains('@')) {
            readyTeachers.add({
              'id': tId,
              'name': tName,
              'email': email,
            });
          } else {
            missingEmailNames.add(tName);
          }
        } else {
          missingEmailNames.add(tName);
        }
      }

      if (readyTeachers.isEmpty) {
        throw 'Seçilen öğretmenlerin hiçbirinin sistemde kayıtlı geçerli bir e-posta adresi bulunamadı!';
      }

      if (missingEmailNames.isNotEmpty) {
        if (mounted) {
          setState(() {
            _isGenerating = false;
            _generationMessage = '';
          });
        }
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
                const SizedBox(width: 12),
                const Text('E-Posta Adresi Eksik'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aşağıdaki öğretmenlerin e-posta adresi bulunmadığı için program gönderilemeyecektir:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: missingEmailNames.length,
                    itemBuilder: (c, idx) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('• ${missingEmailNames[idx]}', style: const TextStyle(color: Colors.redAccent)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Geri kalan ${readyTeachers.length} öğretmene göndermek istiyor musunuz?'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Gönder'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
        setState(() {
          _isGenerating = true;
        });
      }

      final font = await PdfGoogleFonts.robotoRegular();
      final fontBold = await PdfGoogleFonts.robotoBold();

      final examIds = widget.cycle.referansDenemeSinavIds.isNotEmpty
          ? widget.cycle.referansDenemeSinavIds.take(3).toList()
          : (widget.cycle.referansDenemeSinavId.isNotEmpty ? [widget.cycle.referansDenemeSinavId] : []);

      List<Map<String, dynamic>> loadedExams = [];
      for (var id in examIds) {
        final examDoc = await FirebaseFirestore.instance.collection('trial_exams').doc(id).get();
        if (examDoc.exists) {
          final refExam = TrialExam.fromMap(examDoc.data()!, examDoc.id);
          List<dynamic> results = [];
          if (refExam.resultsJson != null && refExam.resultsJson!.isNotEmpty) {
            try {
              results = jsonDecode(refExam.resultsJson!);
            } catch (_) {}
          }
          if (results.isNotEmpty) {
            loadedExams.add({'exam': refExam, 'results': results});
          }
        }
      }

      int successCount = 0;
      int errorCount = 0;
      int total = readyTeachers.length;

      for (int i = 0; i < total; i++) {
        final teacher = readyTeachers[i];
        final tId = teacher['id'] as String;
        final tName = teacher['name'] as String;
        final tEmail = teacher['email'] as String;

        setState(() {
          _generationMessage = 'E-Posta Gönderiliyor (${i + 1} / $total)\n$tName...';
        });

        try {
          final doc = pw.Document();
          final tGroups = widget.groups.where((g) => g.ogretmenId == tId).toList()
            ..sort((a, b) {
              int dayCompare = _gunler.indexOf(a.gun).compareTo(_gunler.indexOf(b.gun));
              if (dayCompare != 0) return dayCompare;
              return a.baslangicSaat.compareTo(b.baslangicSaat);
            });

          if (tGroups.isEmpty) {
            errorCount++;
            continue;
          }

          for (final group in tGroups) {
            final assignments = widget.assignmentsByGroup[group.id] ?? [];
            final gDersAdi = _norm(group.dersAdi);
            final gDerslik = group.derslikAdi != null ? _norm(group.derslikAdi!) : null;

            final double avg = assignments.isEmpty
                ? 0.0
                : assignments.fold(0.0, (sum, a) => sum + a.basariOrani) / assignments.length;
            final bool isHighPercentSuccess = (avg * 100).round() >= 95;

            final gKazanimlar = isHighPercentSuccess
                ? ['Soru Çözümü']
                : group.kazanimlar.map((k) => _norm(k)).toList();

            doc.addPage(
              pw.MultiPage(
                pageFormat: PdfPageFormat.a4,
                header: (pw.Context context) {
                  return pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    margin: const pw.EdgeInsets.only(bottom: 8),
                    decoration: const pw.BoxDecoration(color: PdfColors.orange700),
                    child: pw.Text('KAMP ÖĞRETMEN PROGRAMI', style: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 16)),
                  );
                },
                footer: (pw.Context context) {
                  return pw.Container(
                    alignment: pw.Alignment.centerRight,
                    padding: const pw.EdgeInsets.only(top: 8),
                    child: pw.Column(children: [
                      pw.Divider(color: PdfColors.grey300),
                      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                        pw.Text('Sayfa ${context.pageNumber} / ${context.pagesCount}', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                        pw.Text('eduKN KAMP Sistemi', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
                      ]),
                    ]),
                  );
                },
                build: (pw.Context context) {
                  final analysisWidgets = <pw.Widget>[];
                  for (var data in loadedExams) {
                    final w = _buildAnalysisSection(data['exam'], data['results'], group, assignments, font, fontBold);
                    if (w != null) analysisWidgets.add(w);
                  }

                  return [
                    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text('Öğretmen: ${_norm(tName)}', style: pw.TextStyle(font: fontBold, fontSize: 13)),
                        pw.Text('Ders: $gDersAdi', style: pw.TextStyle(font: font, fontSize: 11)),
                        if (gDerslik != null) pw.Text('Derslik: $gDerslik', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                      ]),
                      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                        if (_getActualDateString(group.gun).isNotEmpty)
                          pw.Text('Tarih: ${_getActualDateString(group.gun)}', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                        pw.Text('Gün: ${_getActualDayName(group.gun)}', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                        pw.Text('Saat: ${group.baslangicSaat}-${group.bitisSaat}', style: pw.TextStyle(font: font, fontSize: 11)),
                      ]),
                    ]),
                    if (gKazanimlar.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        decoration: pw.BoxDecoration(color: PdfColors.orange50, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
                        child: pw.Text('Kazanımlar: ${gKazanimlar.join(", ")}', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.orange900)),
                      ),
                    ],
                    pw.SizedBox(height: 10),
                    pw.Text('Öğrenci Listesi (${assignments.length}):', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                    pw.SizedBox(height: 3),
                    _buildStudentListLayout(assignments, font, fontBold),
                    if (analysisWidgets.isNotEmpty) ...[
                      pw.SizedBox(height: 5),
                      pw.Divider(color: PdfColors.grey300),
                      pw.SizedBox(height: 4),
                      ...analysisWidgets,
                      pw.Align(
                        alignment: pw.Alignment.center,
                        child: pw.Text('Sorulara verilen yanlış cevap sayısı (Grup Geneli)', style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey600)),
                      ),
                    ],
                  ];
                },
              ),
            );
          }

          final bytes = await doc.save();
          final base64Pdf = base64Encode(bytes);

          final dateStr = (() {
            final dt = widget.cycle.baslangicTarihi;
            final d = dt.day.toString().padLeft(2, '0');
            final m = dt.month.toString().padLeft(2, '0');
            final y = dt.year.toString();
            return '$d.$m.$y';
          })();

          // Firebase Callable fonksiyonumuzu tetikliyoruz
          final callable = FirebaseFunctions.instance.httpsCallable('sendCampProgramEmail');
          await callable.call({
            'email': tEmail,
            'teacherName': tName,
            'cycleName': widget.cycle.title ?? widget.cycle.referansDenemeSinavAdi,
            'cycleStartDate': dateStr,
            'pdfBase64': base64Pdf,
            'fileName': 'kamp_programim_${tName.replaceAll(' ', '_')}.pdf',
          });

          successCount++;
        } catch (e) {
          debugPrint('E-posta gönderim hatası ($tName): $e');
          errorCount++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorCount == 0
                  ? '✓ Tüm e-postalar başarıyla gönderildi ($successCount adet).'
                  : '✓ Gönderim tamamlandı. Başarılı: $successCount, Hatalı: $errorCount.',
            ),
            backgroundColor: errorCount == 0 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generationMessage = '';
        });
      }
    }
  }

  pw.Widget _buildStudentListLayout(List<CampAssignment> students, pw.Font font, pw.Font fontBold) {
    if (students.isEmpty) return pw.Text('• Bu grupta öğrenci yok.', style: pw.TextStyle(font: font, fontSize: 10));
    final sortedStudents = students.toList()
      ..sort((a, b) {
        final cmp = b.basariOrani.compareTo(a.basariOrani);
        if (cmp != 0) return cmp;
        return a.ogrenciAdi.compareTo(b.ogrenciAdi);
      });

    if (sortedStudents.length > 30) {
      // 30'u aşarsa 2 Sütunlu Mod
      final half = (sortedStudents.length / 2).ceil();
      final leftSide = sortedStudents.sublist(0, half);
      final rightSide = sortedStudents.sublist(half);

      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _buildStudentTable(leftSide, font, fontBold, startIndex: 0)),
          pw.SizedBox(width: 15),
          pw.Expanded(child: _buildStudentTable(rightSide, font, fontBold, startIndex: half)),
        ],
      );
    } else {
      // Tek Sütunlu Mod
      return _buildStudentTable(sortedStudents, font, fontBold);
    }
  }

  pw.Widget _buildStudentTable(List<CampAssignment> students, pw.Font font, pw.Font fontBold, {int startIndex = 0}) {
    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
        bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
        top: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
      ),
      columnWidths: {
        0: const pw.FixedColumnWidth(22),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FixedColumnWidth(40),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        // Stilize Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey800),
          children: [
            _tableHeader('No', fontBold, color: PdfColors.white),
            _tableHeader('Öğrenci Adı Soyadı', fontBold, color: PdfColors.white),
            _tableHeader('Şube', fontBold, color: PdfColors.white, align: pw.Alignment.center),
            _tableHeader('Başarı %', fontBold, color: PdfColors.white, align: pw.Alignment.center),
          ],
        ),
        // Zebra Striped Rows
        ...List.generate(students.length, (index) {
          final s = students[index];
          final bool isEven = index % 2 == 0;
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: isEven ? PdfColors.white : PdfColors.grey50),
            children: [
              _tableCell('${startIndex + index + 1}', font, align: pw.Alignment.center),
              _tableCell(_norm(s.ogrenciAdi), font),
              _tableCell(_norm(s.sube ?? ''), font, align: pw.Alignment.center),
              _tableCell('%${(s.basariOrani * 100).toStringAsFixed(0)}', font, align: pw.Alignment.center),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _tableHeader(String text, pw.Font font, {PdfColor color = PdfColors.grey800, pw.Alignment align = pw.Alignment.centerLeft}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Align(
        alignment: align,
        child: pw.Text(
          text,
          style: pw.TextStyle(font: font, fontSize: 8, color: color),
        ),
      ),
    );
  }

  pw.Widget _tableCell(String text, pw.Font font, {pw.Alignment align = pw.Alignment.centerLeft}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 4),
      child: pw.Align(
        alignment: align,
        child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey900)),
      ),
    );
  }

  void _showWebShareDialog(Uint8List pdfBytes) {
    showDialog(
      context: context,
      builder: (context) {
        return AgmWebShareDialog(
          pdfBytes: pdfBytes, fileName: 'kamp_ogretmen_programlari.pdf',
          targetUserId: _selectedTeacherId!, title: 'Öğretmen Programı Paylaşımı',
          messageBody: 'Haftalık KAMP programınız belirlendi.',
        );
      },
    );
  }

  Future<void> _exportExcel({bool allTeachers = false}) async {
    setState(() => _isGenerating = true);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Rapor'];
      final teachersToExport = allTeachers ? _teachers : [{'id': _selectedTeacherId, 'name': _selectedTeacherName}];

      for (final teacher in teachersToExport) {
        final tId = teacher['id'];
        final tName = teacher['name'];
        if (tId == null) continue;
        final tGroups = widget.groups.where((g) => g.ogretmenId == tId).toList();
        sheet.appendRow([TextCellValue('KAMP ÖĞRETMEN PROGRAMI - $tName')]);
        sheet.appendRow([TextCellValue('')]);
        sheet.appendRow([TextCellValue('Gün'), TextCellValue('Saat'), TextCellValue('Ders'), TextCellValue('Derslik'), TextCellValue('Öğrenci Adı Soyadı'), TextCellValue('Şube')]);
        for (final g in tGroups) {
          final students = widget.assignmentsByGroup[g.id] ?? [];
          if (students.isEmpty) {
            sheet.appendRow([TextCellValue(g.gun), TextCellValue('${g.baslangicSaat}-${g.bitisSaat}'), TextCellValue(g.dersAdi), TextCellValue(g.derslikAdi ?? '-'), TextCellValue('-'), TextCellValue('-')]);
          } else {
            for (final s in students) {
              sheet.appendRow([TextCellValue(g.gun), TextCellValue('${g.baslangicSaat}-${g.bitisSaat}'), TextCellValue(g.dersAdi), TextCellValue(g.derslikAdi ?? '-'), TextCellValue(s.ogrenciAdi), TextCellValue(s.sube ?? '')]);
            }
          }
        }
        sheet.appendRow([TextCellValue('')]);
      }
      final bytes = excel.save();
      if (bytes != null) {
        await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: 'kamp_ogretmen_raporlari.xlsx');
      }
    } catch (e) {
      debugPrint('Excel Error: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  pw.Widget? _buildAnalysisSection(TrialExam refExam, List<dynamic> examResults, CampGroup group, List<CampAssignment> assignments, pw.Font font, pw.Font fontBold) {
    if (examResults.isEmpty) return null;

    String? matchedSubject;
    if (refExam.answerKeys.isNotEmpty) {
      final subjects = refExam.answerKeys.values.first.keys;
      matchedSubject = subjects.firstWhere(
        (s) => s.toLowerCase() == group.dersAdi.toLowerCase(), 
        orElse: () => subjects.firstWhere(
          (s) => s.toLowerCase().contains(group.dersAdi.toLowerCase()) || group.dersAdi.toLowerCase().contains(s.toLowerCase()),
          orElse: () => ''
        )
      );
      if (matchedSubject?.isEmpty ?? true) matchedSubject = null;
    }

    if (matchedSubject == null) return null;

    Map<int, int> wrongCounts = {};
    int maxQuestion = 0;

    for (final assignment in assignments) {
      final studentResult = examResults.firstWhere(
        (res) => res['studentId'] == assignment.ogrenciId || res['name'] == assignment.ogrenciAdi, 
        orElse: () => null
      );
      
      if (studentResult != null) {
        final booklet = studentResult['booklet'] ?? studentResult['kitapcik'] ?? 'A';
        final answersMap = studentResult['answers'] ?? studentResult['cevaplar'] ?? {};
        final studentAnswers = (answersMap[matchedSubject] ?? '').toString();
        final refAnswers = refExam.answerKeys[booklet]?[matchedSubject] ?? '';
        
        if (refAnswers.length > maxQuestion) maxQuestion = refAnswers.length;
        
        for (int i = 0; i < refAnswers.length; i++) {
          final sChar = i < studentAnswers.length ? studentAnswers[i] : ' ';
          final rChar = refAnswers[i];
          
          if (TrialExam.evaluateAnswer(sChar, rChar) == AnswerStatus.wrong) {
            wrongCounts[i + 1] = (wrongCounts[i + 1] ?? 0) + 1;
          }
        }
      }
    }

    if (maxQuestion == 0) return null;

    List<pw.Widget> tables = [];
    for (int start = 1; start <= maxQuestion; start += 20) {
      int end = (start + 19).clamp(1, maxQuestion);
      tables.add(
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: Map.fromEntries(
            List.generate(end - start + 1, (index) => MapEntry(index, const pw.FlexColumnWidth(1)))
          ),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: List.generate(end - start + 1, (index) {
                return pw.Container(
                  padding: const pw.EdgeInsets.all(1),
                  child: pw.Center(child: pw.Text('${start + index}', style: pw.TextStyle(font: fontBold, fontSize: 7))),
                );
              }),
            ),
            pw.TableRow(
              children: List.generate(end - start + 1, (index) {
                final count = wrongCounts[start + index] ?? 0;
                final bool hasError = count > 0;
                return pw.Container(
                  padding: const pw.EdgeInsets.all(1),
                  decoration: hasError ? const pw.BoxDecoration(color: PdfColors.orange50) : null,
                  child: pw.Center(
                    child: pw.Text(
                      count == 0 ? '-' : '$count', 
                      style: pw.TextStyle(
                        font: hasError ? fontBold : font, 
                        fontSize: 7, 
                        color: hasError ? PdfColors.orange900 : PdfColors.black
                      )
                    )
                  ),
                );
              }),
            ),
          ],
        )
      );
      tables.add(pw.SizedBox(height: 2));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Hata Analizi (Baz Alınan Sınav: ${refExam.name})', style: pw.TextStyle(font: fontBold, fontSize: 8.5)),
        pw.SizedBox(height: 4),
        ...tables,
        pw.SizedBox(height: 6),
      ],
    );
  }
}
