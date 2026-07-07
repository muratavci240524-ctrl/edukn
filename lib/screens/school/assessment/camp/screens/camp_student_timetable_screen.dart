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

class CampStudentTimetableScreen extends StatefulWidget {
  final CampCycle cycle;
  final List<CampGroup> groups;
  final Map<String, List<CampAssignment>> assignmentsByGroup;

  const CampStudentTimetableScreen({
    Key? key,
    required this.cycle,
    required this.groups,
    required this.assignmentsByGroup,
  }) : super(key: key);

  @override
  State<CampStudentTimetableScreen> createState() => _CampStudentTimetableScreenState();
}

class _CampStudentTimetableScreenState extends State<CampStudentTimetableScreen> {
  String? _selectedStudentId;
  String? _selectedStudentName;
  String _searchQuery = '';
  List<Map<String, dynamic>> _students = [];
  List<_TimetableEntry> _entries = [];

  final List<String> _gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
  final List<Color> _renkPaleti = [Colors.blue, Colors.green, Colors.purple, Colors.teal, Colors.indigo, Colors.pink, Colors.orange, Colors.cyan];

  @override
  void initState() {
    super.initState();
    _buildStudentList();
  }

  void _buildStudentList() {
    final Map<String, Map<String, dynamic>> studentMap = {};
    for (final entry in widget.assignmentsByGroup.entries) {
      for (final a in entry.value) {
        if (!studentMap.containsKey(a.ogrenciId)) {
          studentMap[a.ogrenciId] = {'id': a.ogrenciId, 'name': a.ogrenciAdi, 'count': 1};
        } else {
          studentMap[a.ogrenciId]!['count']++;
        }
      }
    }
    _students = studentMap.values.toList()..sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
  }

  void _loadStudentTimetable(String studentId) {
    final entries = <_TimetableEntry>[];
    for (final entry in widget.assignmentsByGroup.entries) {
      final groupId = entry.key;
      final assignments = entry.value;
      final studentAssignment = assignments.firstWhere((a) => a.ogrenciId == studentId, orElse: () => CampAssignment(id: '', cycleId: '', groupId: '', groupName: '', ogrenciId: '', ogrenciAdi: ''));
      if (studentAssignment.id.isEmpty) continue;
      
      final group = widget.groups.firstWhere((g) => g.id == groupId, orElse: () => widget.groups.first); // Safely handle missing groups
      
      final groupAssigns = widget.assignmentsByGroup[groupId] ?? [];
      final double avg = groupAssigns.isEmpty 
          ? 0.0 
          : groupAssigns.fold(0.0, (sum, a) => sum + a.basariOrani) / groupAssigns.length;
      final bool isHighPercentSuccess = (avg * 100).round() >= 95;
      final String? resolvedKazanim = isHighPercentSuccess 
          ? 'Soru Çözümü' 
          : (group.kazanimlar.isNotEmpty ? group.kazanimlar.first : null);

      entries.add(_TimetableEntry(
        gun: group.gun.trim(), 
        baslangicSaat: group.baslangicSaat, 
        bitisSaat: group.bitisSaat, 
        dersAdi: group.dersAdi, 
        ogretmenAdi: group.ogretmenAdi, 
        derslikAdi: group.derslikAdi,
        kazanim: resolvedKazanim, 
        renk: _renkPaleti[entries.length % _renkPaleti.length],
        basariOrani: studentAssignment.basariOrani,
      ));
    }
    
    entries.sort((a, b) {
      int idxA = _gunler.indexWhere((g) => g.toLowerCase() == a.gun.toLowerCase());
      int idxB = _gunler.indexWhere((g) => g.toLowerCase() == b.gun.toLowerCase());
      if (idxA == -1) idxA = 99;
      if (idxB == -1) idxB = 99;
      int dayCompare = idxA.compareTo(idxB);
      if (dayCompare != 0) return dayCompare;
      return a.baslangicSaat.compareTo(b.baslangicSaat);
    });

    setState(() { 
      _selectedStudentId = studentId; 
      _selectedStudentName = _students.firstWhere((s) => s['id'] == studentId)['name']; 
      _entries = entries; 
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Öğrenci Haftalık Takvim', style: TextStyle(color: Colors.white, fontSize: 16)), 
        backgroundColor: Colors.orange.shade700, 
        foregroundColor: Colors.white, 
        centerTitle: true, 
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              final allSelected = _selectedStudentId == null;
              switch (value) {
                case 'excel':
                  _exportExcel(allStudents: allSelected);
                  break;
                case 'print':
                  _showPrintOptionsDialog(context, allStudents: allSelected, isShare: false);
                  break;
                case 'share':
                  _showPrintOptionsDialog(context, allStudents: allSelected, isShare: true);
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
      body: Column(children: [_buildSearchSelector(), Expanded(child: _selectedStudentId == null ? _buildNoStudentState() : _buildTimetable())]),
    );
  }

  Widget _buildSearchSelector() {
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
            Expanded(child: Text(_selectedStudentId == null ? 'Öğrenci Ara ve Seç...' : '$_selectedStudentName (${_entries.length} etüt)', style: TextStyle(color: _selectedStudentId == null ? Colors.grey.shade600 : Colors.black87, fontWeight: _selectedStudentId == null ? FontWeight.normal : FontWeight.bold))),
            Icon(Icons.arrow_drop_down, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }

  void _showSearchSheet() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) => DraggableScrollableSheet(initialChildSize: 0.8, builder: (ctx, ctrl) => StatefulBuilder(builder: (ctx, setSS) {
      final filtered = _students.where((s) => s['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase())).toList();
      return Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          const SizedBox(height: 12), Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.all(16), child: TextField(autofocus: true, onChanged: (v) => setSS(() => _searchQuery = v), decoration: InputDecoration(hintText: 'İsim ile ara...', prefixIcon: const Icon(Icons.search, color: Colors.orange), filled: true, fillColor: Colors.grey.shade50, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
          Expanded(child: ListView.builder(controller: ctrl, itemCount: filtered.length, itemBuilder: (ctx, i) {
            final s = filtered[i];
            return ListTile(leading: CircleAvatar(backgroundColor: Colors.orange.shade50, child: const Icon(Icons.person, color: Colors.orange)), title: Text(s['name']), subtitle: Text('${s['count']} etüt'), onTap: () { _loadStudentTimetable(s['id']); Navigator.pop(ctx); });
          })),
        ]),
      );
    })));
  }

  Widget _buildNoStudentState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calendar_today, size: 56, color: Colors.grey.shade300), const SizedBox(height: 12), Text('Öğrenci seçin', style: TextStyle(color: Colors.grey.shade500))]));

  Widget _buildTimetable() {
    final Map<String, List<_TimetableEntry>> byDay = {};
    for (final e in _entries) byDay.putIfAbsent(e.gun, () => []).add(e);
    
    // Sort keys based on _gunler index
    final sortedDayKeys = byDay.keys.toList()..sort((a, b) {
      int idxA = _gunler.indexWhere((g) => g.toLowerCase() == a.toLowerCase());
      int idxB = _gunler.indexWhere((g) => g.toLowerCase() == b.toLowerCase());
      if (idxA == -1) idxA = 99;
      if (idxB == -1) idxB = 99;
      return idxA.compareTo(idxB);
    });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: sortedDayKeys.map((gun) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)), child: Text(gun, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade700))),
        ...byDay[gun]!.map((e) => _buildEntryCard(e)),
        const SizedBox(height: 12),
      ])).toList(),
    );
  }

  Widget _buildEntryCard(_TimetableEntry e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: e.renk.withOpacity(0.3))),
      child: Row(children: [
        Container(width: 4, height: 44, decoration: BoxDecoration(color: e.renk, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.dersAdi, style: TextStyle(fontWeight: FontWeight.bold, color: e.renk, fontSize: 14)),
          if (e.kazanim != null) ...[
            const SizedBox(height: 2),
            Text(e.kazanim!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text('${e.baslangicSaat} – ${e.bitisSaat}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 12),
              Icon(Icons.person, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  e.derslikAdi != null && e.derslikAdi!.isNotEmpty ? '${e.ogretmenAdi} - ${e.derslikAdi}' : e.ogretmenAdi, 
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)
                ),
              ),
            ],
          ),
        ])),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: e.basariOrani >= 0.7 ? Colors.green.shade50 : (e.basariOrani >= 0.5 ? Colors.orange.shade50 : Colors.red.shade50),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: e.basariOrani >= 0.7 ? Colors.green.shade200 : (e.basariOrani >= 0.5 ? Colors.orange.shade200 : Colors.red.shade200)),
          ),
          child: Text(
            '%${(e.basariOrani * 100).toStringAsFixed(0)} Başarı',
            style: TextStyle(
              fontSize: 11, 
              fontWeight: FontWeight.bold, 
              color: e.basariOrani >= 0.7 ? Colors.green.shade700 : (e.basariOrani >= 0.5 ? Colors.orange.shade700 : Colors.red.shade700)
            ),
          ),
        ),
      ]),
    );
  }

  void _showPrintOptionsDialog(BuildContext context, {bool allStudents = false, bool isShare = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isShare ? 'Paylaşım Seçenekleri' : 'Yazdırma Seçenekleri'),
        content: const Text('Öğrenci programlarını nasıl formatlamak istersiniz?\n\n• Ayrı Sayfalar: Her öğrenci için yeni bir sayfa.\n• 8 Öğrenci/Sayfa: Bir sayfaya 8 öğrenci kartı sığdırılır (ekonomik).'),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); _printPDF(allStudents: allStudents, gridMode: false, isShare: isShare); }, child: const Text('AYRI SAYFALAR')),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); _printPDF(allStudents: allStudents, gridMode: true, isShare: isShare); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700),
            child: const Text('8 ÖĞRENCİ / SAYFA', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _norm(String t) {
    if (t.isEmpty) return t;
    return t.replaceAll('u\u0308', 'ü').replaceAll('U\u0308', 'Ü').replaceAll('o\u0308', 'ö').replaceAll('O\u0308', 'Ö').replaceAll('c\u0327', 'ç').replaceAll('C\u0327', 'Ç').replaceAll('s\u0327', 'ş').replaceAll('S\u0327', 'Ş').replaceAll('g\u0306', 'ğ').replaceAll('G\u0306', 'Ğ').replaceAll('I\u0307', 'İ').replaceAll('i\u0307', 'i');
  }

  Future<void> _printPDF({bool allStudents = false, bool gridMode = false, bool isShare = false}) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final studentsToPrint = allStudents ? _students : [{'id': _selectedStudentId, 'name': _selectedStudentName}];

    if (gridMode) {
      for (int i = 0; i < studentsToPrint.length; i += 8) {
        final currentBatch = studentsToPrint.skip(i).take(8).toList();
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(20),
            build: (pw.Context context) {
              return pw.GridView(
                crossAxisCount: 2, childAspectRatio: 0.65, crossAxisSpacing: 10, mainAxisSpacing: 10,
                children: currentBatch.map((s) {
                  final sId = s['id'];
                  final sName = s['name'];
                  final sEntries = _getStudentEntries(sId);
                  return pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(sName != null ? _norm(sName) : '', style: pw.TextStyle(font: fontBold, fontSize: 10), maxLines: 1),
                        pw.Divider(thickness: 0.5, height: 6),
                        ...sEntries.take(6).map((e) => pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 2),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('${_norm(e.gun)} | ${e.baslangicSaat}-${e.bitisSaat}', style: pw.TextStyle(font: font, fontSize: 7)),
                              pw.Text('${_norm(e.dersAdi)} (${_norm(e.ogretmenAdi)}) | %${(e.basariOrani * 100).toStringAsFixed(0)} Başarı', style: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.orange700), maxLines: 1),
                            ],
                          ),
                        )),
                        if (sEntries.length > 6) pw.Text('...', style: pw.TextStyle(font: fontBold, fontSize: 7)),
                        if (sEntries.isEmpty) pw.Text('Program yok', style: pw.TextStyle(font: font, fontSize: 7, fontStyle: pw.FontStyle.italic)),
                        pw.Spacer(),
                        pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('eduKN KAMP', style: pw.TextStyle(font: font, fontSize: 5, color: PdfColors.grey500))),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        );
      }
    } else {
      for (final s in studentsToPrint) {
        final sId = s['id'];
        final sName = s['name'];
        final sEntries = _getStudentEntries(sId);

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: double.infinity, padding: const pw.EdgeInsets.all(12),
                    decoration: const pw.BoxDecoration(color: PdfColors.orange700),
                    child: pw.Text('ÖĞRENCİ KAMP HAFTALIK PROGRAMI', style: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 18)),
                  ),
                  pw.SizedBox(height: 15),
                  pw.Text('Öğrenci: ${sName != null ? _norm(sName) : ''}', style: pw.TextStyle(font: fontBold, fontSize: 16)),
                  pw.SizedBox(height: 20),
                  pw.Table.fromTextArray(
                    headers: ['Gün', 'Saat', 'Ders', 'Öğretmen', 'Derslik', 'Başarı %', 'Kazanım'],
                    headerStyle: pw.TextStyle(font: fontBold, color: PdfColors.white),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.orange400),
                    cellStyle: pw.TextStyle(font: font, fontSize: 10),
                    data: sEntries.map((e) => [_norm(e.gun), '${e.baslangicSaat}-${e.bitisSaat}', _norm(e.dersAdi), _norm(e.ogretmenAdi), e.derslikAdi != null ? _norm(e.derslikAdi!) : '-', '%${(e.basariOrani * 100).toStringAsFixed(0)}', e.kazanim != null ? _norm(e.kazanim!) : '-']).toList(),
                  ),
                  pw.Spacer(),
                  pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('eduKN Eğitim Yönetim Sistemi', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500))),
                ],
              );
            },
          ),
        );
      }
    }

    final bytes = await doc.save();
    if (isShare) {
      if (kIsWeb && !allStudents && _selectedStudentId != null) {
        _showWebShareDialog(bytes);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: 'kamp_ogrenci_programlari.pdf');
      }
    } else {
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => bytes);
    }
  }

  void _showWebShareDialog(Uint8List pdfBytes) {
    showDialog(
      context: context,
      builder: (context) {
        return AgmWebShareDialog(
          pdfBytes: pdfBytes,
          fileName: 'kamp_ogrenci_programlari.pdf',
          targetUserId: _selectedStudentId!,
          title: 'Kamp Öğrenci Programı Paylaşımı',
          messageBody: 'Haftalık KAMP bireysel programınız belirlendi.',
        );
      },
    );
  }

  List<_TimetableEntry> _getStudentEntries(String studentId) {
    final entries = <_TimetableEntry>[];
    for (final entry in widget.assignmentsByGroup.entries) {
      final assignments = entry.value;
      final studentAssignment = assignments.firstWhere((a) => a.ogrenciId == studentId, orElse: () => CampAssignment(id: '', cycleId: '', groupId: '', groupName: '', ogrenciId: '', ogrenciAdi: ''));
      if (studentAssignment.id.isNotEmpty) {
        final group = widget.groups.firstWhere((g) => g.id == entry.key, orElse: () => widget.groups.first);
        
        final double avg = assignments.isEmpty 
            ? 0.0 
            : assignments.fold(0.0, (sum, a) => sum + a.basariOrani) / assignments.length;
        final bool isHighPercentSuccess = (avg * 100).round() >= 95;
        final String? resolvedKazanim = isHighPercentSuccess 
            ? 'Soru Çözümü' 
            : (group.kazanimlar.isNotEmpty ? group.kazanimlar.first : null);

        entries.add(
          _TimetableEntry(
            gun: group.gun, baslangicSaat: group.baslangicSaat, bitisSaat: group.bitisSaat, dersAdi: group.dersAdi, ogretmenAdi: group.ogretmenAdi, derslikAdi: group.derslikAdi,
            kazanim: resolvedKazanim, renk: Colors.orange,
            basariOrani: studentAssignment.basariOrani,
          ),
        );
      }
    }
    entries.sort((a, b) {
      int idxA = _gunler.indexWhere((g) => g.toLowerCase() == a.gun.toLowerCase());
      int idxB = _gunler.indexWhere((g) => g.toLowerCase() == b.gun.toLowerCase());
      if (idxA == -1) idxA = 99;
      if (idxB == -1) idxB = 99;
      int dayCompare = idxA.compareTo(idxB);
      if (dayCompare != 0) return dayCompare;
      return a.baslangicSaat.compareTo(b.baslangicSaat);
    });
    return entries;
  }

  Future<void> _exportExcel({bool allStudents = false}) async {
    final excel = Excel.createExcel();
    final sheet = excel['Rapor'];

    final studentsToExport = allStudents ? _students : [{'id': _selectedStudentId, 'name': _selectedStudentName}];

    for (final s in studentsToExport) {
      final sId = s['id'];
      final sName = s['name'];
      final sEntries = _getStudentEntries(sId);

      sheet.appendRow([TextCellValue('KAMP Öğrenci Programı - $sName')]);
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([TextCellValue('Gün'), TextCellValue('Saat'), TextCellValue('Ders'), TextCellValue('Öğretmen'), TextCellValue('Derslik'), TextCellValue('Başarı %'), TextCellValue('Konu/Kazanım')]);

      for (final e in sEntries) {
        sheet.appendRow([TextCellValue(e.gun), TextCellValue('${e.baslangicSaat}-${e.bitisSaat}'), TextCellValue(e.dersAdi), TextCellValue(e.ogretmenAdi), TextCellValue(e.derslikAdi ?? '-'), TextCellValue('%${(e.basariOrani * 100).toStringAsFixed(0)}'), TextCellValue(e.kazanim ?? '-')]);
      }
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([TextCellValue('')]);
    }

    final bytes = excel.save();
    if (bytes != null) {
      await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: 'kamp_ogrenci_raporlari.xlsx');
    }
  }
}

class _TimetableEntry {
  final String gun, baslangicSaat, bitisSaat, dersAdi, ogretmenAdi;
  final String? derslikAdi;
  final String? kazanim;
  final Color renk;
  final double basariOrani;
  _TimetableEntry({required this.gun, required this.baslangicSaat, required this.bitisSaat, required this.dersAdi, required this.ogretmenAdi, this.derslikAdi, this.kazanim, required this.renk, required this.basariOrani});
}
