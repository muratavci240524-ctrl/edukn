import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/camp_cycle_model.dart';
import '../models/camp_group_model.dart';
import '../models/camp_assignment_model.dart';
import '../widgets/agm_web_share_dialog.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' hide Border;

class CampClassroomTimetableScreen extends StatefulWidget {
  final CampCycle cycle;
  final List<CampGroup> groups;
  final Map<String, List<CampAssignment>> assignmentsByGroup;

  const CampClassroomTimetableScreen({
    Key? key,
    required this.cycle,
    required this.groups,
    required this.assignmentsByGroup,
  }) : super(key: key);

  @override
  State<CampClassroomTimetableScreen> createState() => _CampClassroomTimetableScreenState();
}

class _CampClassroomTimetableScreenState extends State<CampClassroomTimetableScreen> {
  String? _selectedRoomId;
  String? _selectedRoomName;
  String _searchQuery = '';
  List<Map<String, dynamic>> _rooms = [];
  List<CampGroup> _roomGroups = [];

  final List<String> _gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

  @override
  void initState() {
    super.initState();
    _buildRoomList();
  }

  void _buildRoomList() {
    final Map<String, Map<String, dynamic>> roomMap = {};
    for (final g in widget.groups) {
      if (g.derslikId == null || g.derslikId!.isEmpty) continue;
      if (!roomMap.containsKey(g.derslikId)) {
        roomMap[g.derslikId!] = {'id': g.derslikId, 'name': g.derslikAdi, 'count': 1};
      } else {
        roomMap[g.derslikId!]!['count']++;
      }
    }
    _rooms = roomMap.values.toList()..sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
  }

  void _loadRoomTimetable(String roomId) {
    setState(() {
      _selectedRoomId = roomId;
      _selectedRoomName = _rooms.firstWhere((r) => r['id'] == roomId)['name'];
      _roomGroups = widget.groups.where((g) => g.derslikId == roomId).toList()
        ..sort((a, b) => _gunler.indexOf(a.gun).compareTo(_gunler.indexOf(b.gun)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Derslik Haftalık Takvim', style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              final allSelected = _selectedRoomId == null;
              switch (value) {
                case 'excel':
                  _exportExcel(allClassrooms: allSelected);
                  break;
                case 'print':
                  _printPDF(allClassrooms: allSelected, isShare: false);
                  break;
                case 'share':
                  _printPDF(allClassrooms: allSelected, isShare: true);
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
            ],
          ),
        ],
      ),
      body: Column(children: [_buildSelector(), Expanded(child: _selectedRoomId == null ? _buildNoState() : _buildTimetable())]),
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
            Icon(Icons.meeting_room, color: Colors.orange.shade400),
            const SizedBox(width: 12),
            Expanded(child: Text(_selectedRoomId == null ? 'Derslik Ara ve Seç...' : '$_selectedRoomName (${_roomGroups.length} grup)', style: TextStyle(color: _selectedRoomId == null ? Colors.grey.shade600 : Colors.black87, fontWeight: _selectedRoomId == null ? FontWeight.normal : FontWeight.bold))),
            Icon(Icons.arrow_drop_down, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }

  void _showSearchSheet() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => DraggableScrollableSheet(initialChildSize: 0.8, builder: (ctx, ctrl) => StatefulBuilder(builder: (ctx, setSS) {
      final filtered = _rooms.where((r) => r['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase())).toList();
      return Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          const SizedBox(height: 12), Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.all(16), child: TextField(autofocus: true, onChanged: (v) => setSS(() => _searchQuery = v), decoration: InputDecoration(hintText: 'Derslik ara...', prefixIcon: const Icon(Icons.search, color: Colors.orange), filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
          Expanded(child: ListView.builder(controller: ctrl, itemCount: filtered.length, itemBuilder: (ctx, i) {
            final r = filtered[i];
            return ListTile(leading: CircleAvatar(backgroundColor: Colors.orange.shade50, child: const Icon(Icons.meeting_room, color: Colors.orange)), title: Text(r['name']), subtitle: Text('${r['count']} grup'), onTap: () { _loadRoomTimetable(r['id']); Navigator.pop(ctx); });
          })),
        ]),
      );
    })));
  }

  Widget _buildNoState() => Center(child: Text('Derslik seçin', style: TextStyle(color: Colors.grey.shade500)));

  Widget _buildTimetable() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _roomGroups.length,
      itemBuilder: (ctx, i) {
        final g = _roomGroups[i];
        final assignments = widget.assignmentsByGroup[g.id] ?? [];
        
        final sortedAssignments = assignments.toList()
          ..sort((a, b) => b.basariOrani.compareTo(a.basariOrani));
          
        double avgSuccess = 0.0;
        if (assignments.isNotEmpty) {
          avgSuccess = assignments.map((a) => a.basariOrani).reduce((a, b) => a + b) / assignments.length;
        }

        return Card(
          clipBehavior: Clip.antiAlias,
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
                       Text('${g.dersAdi} • ${g.ogretmenAdi} (${assignments.length}/${g.kapasite})', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
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
                }),
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

  Future<void> _printPDF({bool allClassrooms = false, bool isShare = false}) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final roomsToPrint = allClassrooms ? _rooms : [{'id': _selectedRoomId, 'name': _selectedRoomName}];

    // Prepare Classroom Summary Page
    final allRoomGroups = <CampGroup>[];
    for (final room in roomsToPrint) {
      final rId = room['id'];
      if (rId == null) continue;
      final rGroups = widget.groups.where((g) => g.derslikId == rId).toList();
      allRoomGroups.addAll(rGroups);
    }

    allRoomGroups.sort((a, b) {
      int dayCompare = _gunler.indexOf(_getActualDayName(a.gun)).compareTo(_gunler.indexOf(_getActualDayName(b.gun)));
      if (dayCompare != 0) return dayCompare;
      int timeCompare = a.baslangicSaat.compareTo(b.baslangicSaat);
      if (timeCompare != 0) return timeCompare;
      return (a.derslikAdi ?? '').compareTo(b.derslikAdi ?? '');
    });

    if (allRoomGroups.isNotEmpty) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (pw.Context context) {
            return pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              margin: const pw.EdgeInsets.only(bottom: 12),
              decoration: const pw.BoxDecoration(color: PdfColors.orange800),
              child: pw.Text('KAMP DERSLİK PROGRAMLARI ÖZETİ', style: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 16)),
            );
          },
          footer: (pw.Context context) {
            return pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Rapor Tarihi: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year} | Özet Sayfa ${context.pageNumber}', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500)),
            );
          },
          build: (context) {
            return [
              pw.Text('Tüm dersliklerin haftalık kamp seans planlaması ve öğrenci katılım özet tablosu aşağıda listelenmiştir:', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey800)),
              pw.SizedBox(height: 12),
              pw.Table(
                border: const pw.TableBorder(
                  horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                  bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                  top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(1.2),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FixedColumnWidth(75),
                },
                defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _tableHeaderSummary('Seans', fontBold),
                      _tableHeaderSummary('Derslik Adı', fontBold),
                      _tableHeaderSummary('Öğretmen Adı', fontBold),
                      _tableHeaderSummary('Öğrenci Sayısı', fontBold, align: pw.Alignment.center),
                    ],
                  ),
                  ...List.generate(allRoomGroups.length, (idx) {
                    final g = allRoomGroups[idx];
                    final isEven = idx % 2 == 0;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: isEven ? PdfColors.white : PdfColors.grey50),
                      children: [
                        _tableCellSummary('${_getActualDayName(g.gun)} (${g.baslangicSaat}-${g.bitisSaat})', font),
                        _tableCellSummary(_norm(g.derslikAdi ?? ''), font),
                        _tableCellSummary(_norm(g.ogretmenAdi), font),
                        _tableCellSummary('${g.mevcutOgrenciSayisi} Öğrenci', fontBold, align: pw.Alignment.center),
                      ],
                    );
                  }),
                ],
              ),
            ];
          },
        ),
      );
    }

    for (final room in roomsToPrint) {
      final rId = room['id'];
      final rName = room['name'];
      if (rId == null) continue;

      final rGroups = widget.groups.where((g) => g.derslikId == rId).toList()
        ..sort((a, b) {
          int dayCompare = _gunler.indexOf(a.gun).compareTo(_gunler.indexOf(b.gun));
          if (dayCompare != 0) return dayCompare;
          return a.baslangicSaat.compareTo(b.baslangicSaat);
        });

      for (int i = 0; i < rGroups.length; i += 2) {
        final currentPair = rGroups.skip(i).take(2).toList();
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            build: (context) {
              return pw.Column(
                children: [
                  _buildHeader(rName!, fontBold),
                  pw.SizedBox(height: 10),
                  pw.Expanded(
                    child: _buildGroupCardInPdf(currentPair[0], rName!, font, fontBold),
                  ),
                  if (currentPair.length > 1) ...[
                    pw.SizedBox(height: 20),
                    pw.Expanded(
                      child: _buildGroupCardInPdf(currentPair[1], rName!, font, fontBold),
                    ),
                  ] else
                    pw.Expanded(child: pw.Container()),
                  pw.SizedBox(height: 10),
                  _buildFooter(context, font),
                ],
              );
            },
          ),
        );
      }
    }

    final bytes = await doc.save();
    if (isShare) {
      if (kIsWeb && !allClassrooms && _selectedRoomId != null) {
        _showWebShareDialog(bytes);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: 'kamp_derslik_programlari.pdf');
      }
    } else {
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => bytes);
    }
  }

  pw.Widget _buildHeader(String rName, pw.Font fontBold) {
    return pw.Container(
      width: double.infinity, padding: const pw.EdgeInsets.all(12), margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(color: PdfColors.orange800),
      child: pw.Text('KAMP DERSLİK PROGRAMI: ${_norm(rName)}', style: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 16)),
    );
  }

  pw.Widget _buildFooter(pw.Context context, pw.Font font) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Rapor Tarihi: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year} | Sayfa ${context.pageNumber}', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500)),
    );
  }

  pw.Widget _tableHeaderSummary(String text, pw.Font font, {pw.Alignment align = pw.Alignment.centerLeft}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: pw.Align(
        alignment: align,
        child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.black)),
      ),
    );
  }

  pw.Widget _tableCellSummary(String text, pw.Font font, {pw.Alignment align = pw.Alignment.centerLeft}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      child: pw.Align(
        alignment: align,
        child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 8.5)),
      ),
    );
  }

  pw.Widget _buildGroupCardInPdf(CampGroup g, String rName, pw.Font font, pw.Font fontBold) {
    final students = widget.assignmentsByGroup[g.id] ?? [];
    final gDersAdi = _norm(g.dersAdi);
    final gOgretmenAdi = _norm(g.ogretmenAdi);
    final gGun = _norm(g.gun);
    
    final double avg = students.isEmpty 
        ? 0.0 
        : students.fold(0.0, (sum, a) => sum + a.basariOrani) / students.length;
    final bool isHighSuccess = (avg * 100).round() >= 95;
    
    final gKazanimlar = isHighSuccess 
        ? ['Soru Çözümü'] 
        : g.kazanimlar.map((k) => _norm(k)).toList();

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Derslik: ${_norm(rName)}', style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.orange800)),
              if (_getActualDateString(g.gun).isNotEmpty)
                pw.Text('Tarih: ${_getActualDateString(g.gun)}', style: pw.TextStyle(font: font, fontSize: 11)),
              pw.Text('Gün: ${_getActualDayName(g.gun)}', style: pw.TextStyle(font: font, fontSize: 11)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('Öğretmen: $gOgretmenAdi', style: pw.TextStyle(font: fontBold, fontSize: 11)),
              pw.Text('Ders: $gDersAdi', style: pw.TextStyle(font: font, fontSize: 11)),
              pw.Text('Saat: ${g.baslangicSaat}-${g.bitisSaat}', style: pw.TextStyle(font: fontBold, fontSize: 11)),
            ]),
          ]),
          pw.Divider(color: PdfColors.orange200, thickness: 1, height: 15),
          if (gKazanimlar.isNotEmpty) ...[
            pw.Text('Kazanımlar: ${gKazanimlar.join(", ")}', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700), maxLines: 2),
            pw.SizedBox(height: 10),
          ],
          pw.Text('Öğrenci Listesi (${students.length}):', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.grey800)),
          pw.SizedBox(height: 5),
          pw.Expanded(child: _build3ColumnStudentTable(students, font)),
        ],
      ),
    );
  }

  pw.Widget _build3ColumnStudentTable(List<CampAssignment> students, pw.Font font) {
    if (students.isEmpty) return pw.Text('• Bu grupta öğrenci yok.', style: pw.TextStyle(font: font, fontSize: 8));
    final sortedStudents = students.toList()..sort((a, b) => a.ogrenciAdi.compareTo(b.ogrenciAdi));
    
    final List<pw.TableRow> rows = [];
    for (int i = 0; i < sortedStudents.length; i += 3) {
      final bool isEven = (i / 3).floor() % 2 == 0;
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: isEven ? PdfColors.white : PdfColors.grey50),
          children: [
            for (int j = 0; j < 3; j++)
              if (i + j < sortedStudents.length)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                  child: pw.Text(
                    '${i + j + 1}. ${_norm(sortedStudents[i + j].ogrenciAdi)} (${_norm(sortedStudents[i + j].sube ?? '')})',
                    style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey900),
                  ),
                )
              else
                pw.Container(),
          ],
        ),
      );
    }
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey100, width: 0.5),
      children: rows,
    );
  }

  void _showWebShareDialog(Uint8List pdfBytes) {
    final rGroups = widget.groups.where((g) => g.derslikId == _selectedRoomId).toList();
    if (rGroups.isEmpty || rGroups.first.ogretmenId.isEmpty) {
      Printing.sharePdf(bytes: pdfBytes, filename: 'kamp_derslik_programlari.pdf');
      return;
    }
    final teacherId = rGroups.first.ogretmenId;
    showDialog(
      context: context,
      builder: (context) {
        return AgmWebShareDialog(
          pdfBytes: pdfBytes, fileName: 'kamp_derslik_programlari.pdf',
          targetUserId: teacherId, title: 'Derslik Programı Paylaşımı',
          messageBody: 'Haftalık KAMP derslik programı ektedir.',
        );
      },
    );
  }

  Future<void> _exportExcel({bool allClassrooms = false}) async {
    final excel = Excel.createExcel();
    final sheet = excel['Rapor'];
    final roomsToExport = allClassrooms ? _rooms : [{'id': _selectedRoomId, 'name': _selectedRoomName}];

    for (final room in roomsToExport) {
      final rId = room['id'];
      final rName = room['name'];
      if (rId == null) continue;
      final rGroups = widget.groups.where((g) => g.derslikId == rId).toList();
      sheet.appendRow([TextCellValue('KAMP DERSLİK PROGRAMI - ${_norm(rName!)}')]);
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([TextCellValue('Gün'), TextCellValue('Saat'), TextCellValue('Öğretmen'), TextCellValue('Ders'), TextCellValue('Öğrenci Adı Soyadı'), TextCellValue('Şubesi')]);
      for (final group in rGroups) {
        final students = widget.assignmentsByGroup[group.id] ?? [];
        if (students.isEmpty) {
          sheet.appendRow([TextCellValue(group.gun), TextCellValue('${group.baslangicSaat}-${group.bitisSaat}'), TextCellValue(group.ogretmenAdi), TextCellValue(group.dersAdi), TextCellValue('-'), TextCellValue('-')]);
        } else {
          for (final s in students) {
            sheet.appendRow([TextCellValue(group.gun), TextCellValue('${group.baslangicSaat}-${group.bitisSaat}'), TextCellValue(group.ogretmenAdi), TextCellValue(group.dersAdi), TextCellValue(_norm(s.ogrenciAdi)), TextCellValue(_norm(s.sube ?? ''))]);
          }
        }
      }
      sheet.appendRow([TextCellValue('')]);
    }
    final bytes = excel.save();
    if (bytes != null) {
      await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: 'kamp_derslik_raporlari.xlsx');
    }
  }
}
