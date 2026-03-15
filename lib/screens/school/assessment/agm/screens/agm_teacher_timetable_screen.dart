import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/agm_cycle_model.dart';
import '../models/agm_group_model.dart';
import '../models/agm_assignment_model.dart';
import '../widgets/agm_web_share_dialog.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' hide Border;

/// Haftalık Öğretmen Takvim Ekranı
/// Seçilen öğretmenin programını gösterir, akordeon içinde öğrenci detayları sunar.
class AgmTeacherTimetableScreen extends StatefulWidget {
  final AgmCycle cycle;
  final List<AgmGroup> groups;
  final Map<String, List<AgmAssignment>> assignmentsByGroup;

  const AgmTeacherTimetableScreen({
    Key? key,
    required this.cycle,
    required this.groups,
    required this.assignmentsByGroup,
  }) : super(key: key);

  @override
  State<AgmTeacherTimetableScreen> createState() =>
      _AgmTeacherTimetableScreenState();
}

class _AgmTeacherTimetableScreenState extends State<AgmTeacherTimetableScreen> {
  String? _selectedTeacherId;
  String? _selectedTeacherName;
  String _searchQuery = '';

  List<Map<String, dynamic>> _teachers = [];
  List<AgmGroup> _teacherGroups = [];

  final List<String> _gunler = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
  ];

  @override
  void initState() {
    super.initState();
    _buildTeacherList();
  }

  void _buildTeacherList() {
    final Map<String, String> teacherMap = {};
    for (final g in widget.groups) {
      if (g.ogretmenId.isNotEmpty) {
        teacherMap[g.ogretmenId] = g.ogretmenAdi;
      }
    }
    _teachers =
        teacherMap.entries.map((e) => {'id': e.key, 'name': e.value}).toList()
          ..sort((a, b) => a['name']!.compareTo(b['name']!));
  }

  void _loadTeacherTimetable(String teacherId, String teacherName) {
    setState(() {
      _selectedTeacherId = teacherId;
      _selectedTeacherName = teacherName;
      _teacherGroups =
          widget.groups.where((g) => g.ogretmenId == teacherId).toList()
            ..sort((a, b) {
              int dayCompare = _gunler
                  .indexOf(a.gun)
                  .compareTo(_gunler.indexOf(b.gun));
              if (dayCompare != 0) return dayCompare;
              return a.baslangicSaat.compareTo(b.baslangicSaat);
            });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Öğretmen Haftalık Takvim',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
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
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'excel',
                child: Row(
                  children: [
                    Icon(Icons.description, color: Colors.green, size: 20),
                    SizedBox(width: 12),
                    Text('Excel İndir'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'print',
                child: Row(
                  children: [
                    Icon(Icons.print, color: Colors.blue, size: 20),
                    SizedBox(width: 12),
                    Text('Yazdır (PDF)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share, color: Colors.deepOrange, size: 20),
                    SizedBox(width: 12),
                    Text('Paylaş'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              _buildSearchAndSelector(),
              Expanded(
                child: _selectedTeacherId == null
                    ? _buildNoSelectionState()
                    : _buildTimetable(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: InkWell(
        onTap: _showTeacherSearchSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.person_search, color: Colors.deepOrange.shade400),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedTeacherId == null
                      ? 'Öğretmen Seçin...'
                      : _selectedTeacherName!,
                  style: TextStyle(
                    color: _selectedTeacherId == null
                        ? Colors.grey.shade600
                        : Colors.black87,
                    fontWeight: _selectedTeacherId == null
                        ? FontWeight.normal
                        : FontWeight.bold,
                  ),
                ),
              ),
              Icon(Icons.arrow_drop_down, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  void _showTeacherSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        builder: (context, scrollController) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              final filtered = _teachers
                  .where(
                    (t) => t['name'].toString().toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    ),
                  )
                  .toList();
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        autofocus: true,
                        onChanged: (v) => setSheetState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Öğretmen ismi...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final t = filtered[index];
                          return ListTile(
                            title: Text(t['name']),
                            onTap: () {
                              _loadTeacherTimetable(t['id'], t['name']);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildNoSelectionState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.badge_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Lütfen bir öğretmen seçin',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetable() {
    if (_teacherGroups.isEmpty) {
      return const Center(child: Text('Bu öğretmene ait grup bulunamadı.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _teacherGroups.length,
      itemBuilder: (context, index) {
        final group = _teacherGroups[index];
        final students = widget.assignmentsByGroup[group.id] ?? [];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ExpansionTile(
            title: Text(
              '${group.gun} | ${group.baslangicSaat}-${group.bitisSaat}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${group.dersAdi} - ${group.derslikAdi ?? 'Derslik Belirtilmemiş'}',
            ),
            leading: CircleAvatar(
              backgroundColor: Colors.deepOrange.shade50,
              child: Text(
                group.dersAdi[0],
                style: const TextStyle(
                  color: Colors.deepOrange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            children: [
              if (students.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Bu grupta öğrenci yok.'),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(3),
                      1: FlexColumnWidth(1),
                    },
                    children: [
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Öğrenci Adı',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Şube',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      ...students
                          .map(
                            (a) => TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    a.ogrenciAdi,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    a.subeAdi,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _norm(String t) {
    if (t.isEmpty) return t;
    return t
        .replaceAll('u\u0308', 'ü')
        .replaceAll('U\u0308', 'Ü')
        .replaceAll('o\u0308', 'ö')
        .replaceAll('O\u0308', 'Ö')
        .replaceAll('c\u0327', 'ç')
        .replaceAll('C\u0327', 'Ç')
        .replaceAll('s\u0327', 'ş')
        .replaceAll('S\u0327', 'Ş')
        .replaceAll('g\u0306', 'ğ')
        .replaceAll('G\u0306', 'Ğ')
        .replaceAll('I\u0307', 'İ')
        .replaceAll('i\u0307', 'i');
  }

  Future<void> _printPDF({
    bool allTeachers = false,
    bool isShare = false,
  }) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final teachersToPrint = allTeachers
        ? _teachers
        : [
            {'id': _selectedTeacherId, 'name': _selectedTeacherName},
          ];

    for (final teacher in teachersToPrint) {
      final tId = teacher['id'];
      final tName = teacher['name'];
      if (tId == null) continue;

      final tGroups = widget.groups.where((g) => g.ogretmenId == tId).toList()
        ..sort((a, b) {
          int dayCompare = _gunler
              .indexOf(a.gun)
              .compareTo(_gunler.indexOf(b.gun));
          if (dayCompare != 0) return dayCompare;
          return a.baslangicSaat.compareTo(b.baslangicSaat);
        });

      for (final group in tGroups) {
        final students = widget.assignmentsByGroup[group.id] ?? [];
        final gDersAdi = _norm(group.dersAdi);
        final gGun = _norm(group.gun);
        final gDerslik = group.derslikAdi != null
            ? _norm(group.derslikAdi!)
            : null;
        final gKazanimlar = group.kazanimlar.map((k) => _norm(k)).toList();

        // Dinamik yazı boyutu belirle (Öğrenci sayısına göre)
        double fontSize = 10;
        double padding = 4;
        if (students.length > 25) {
          fontSize = 9;
          padding = 2.5;
        }
        if (students.length > 40) {
          fontSize = 8;
          padding = 1.5;
        }

        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            header: (pw.Context context) {
              return pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                margin: const pw.EdgeInsets.only(bottom: 12),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.deepOrange700,
                ),
                child: pw.Text(
                  'AGM ÖĞRETMEN PROGRAMI',
                  style: pw.TextStyle(
                    font: fontBold,
                    color: PdfColors.white,
                    fontSize: 16,
                  ),
                ),
              );
            },
            footer: (pw.Context context) {
              return pw.Container(
                alignment: pw.Alignment.centerRight,
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Column(
                  children: [
                    pw.Divider(color: PdfColors.grey300),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Sayfa ${context.pageNumber} / ${context.pagesCount}',
                          style: pw.TextStyle(
                            font: font,
                            fontSize: 8,
                            color: PdfColors.grey600,
                          ),
                        ),
                        pw.Text(
                          'eduKN AGM Sistemi | Rapor Tarihi: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
                          style: pw.TextStyle(
                            font: font,
                            fontSize: 8,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
            build: (pw.Context context) {
              return [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Öğretmen: ${_norm(tName)}',
                          style: pw.TextStyle(font: fontBold, fontSize: 13),
                        ),
                        pw.Text(
                          'Ders: $gDersAdi',
                          style: pw.TextStyle(font: font, fontSize: 11),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'Gün: $gGun',
                          style: pw.TextStyle(font: fontBold, fontSize: 11),
                        ),
                        pw.Text(
                          'Saat: ${group.baslangicSaat}-${group.bitisSaat}',
                          style: pw.TextStyle(font: font, fontSize: 11),
                        ),
                        if (gDerslik != null)
                          pw.Text(
                            'Derslik: $gDerslik',
                            style: pw.TextStyle(font: fontBold, fontSize: 11),
                          ),
                      ],
                    ),
                  ],
                ),
                if (gKazanimlar.isNotEmpty) ...[
                  pw.SizedBox(height: 10),
                  // Ana Kazanım
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.deepOrange50,
                      borderRadius: pw.BorderRadius.vertical(
                        top: pw.Radius.circular(8),
                      ),
                    ),
                    child: pw.Text(
                      'Ana Kazanım: ${gKazanimlar.first}',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 10,
                        color: PdfColors.deepOrange900,
                      ),
                    ),
                  ),
                  // Yardımcı Kazanımlar
                  if (gKazanimlar.length > 1)
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        border: pw.Border.all(color: PdfColors.grey200),
                        borderRadius: const pw.BorderRadius.vertical(
                          bottom: pw.Radius.circular(8),
                        ),
                      ),
                      child: pw.Text(
                        'Yardımcı: ${gKazanimlar.sublist(1).join(', ')}',
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 9,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ),
                ],
                pw.SizedBox(height: 16),
                pw.Table.fromTextArray(
                  headers: ['#', 'Şube', 'Öğrenci Adı Soyadı', 'Başarı %'],
                  headerStyle: pw.TextStyle(
                    font: fontBold,
                    color: PdfColors.white,
                    fontSize: fontSize,
                  ),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.deepOrange400,
                  ),
                  cellStyle: pw.TextStyle(font: font, fontSize: fontSize),
                  cellPadding: pw.EdgeInsets.all(padding),
                  cellAlignment: pw.Alignment.centerLeft,
                  headerAlignment: pw.Alignment.centerLeft,
                  columnWidths: {
                    0: const pw.FixedColumnWidth(30),
                    1: const pw.FixedColumnWidth(80),
                    2: const pw.FlexColumnWidth(),
                    3: const pw.FixedColumnWidth(60),
                  },
                  data: () {
                    int counter = 1;
                    return students.map((s) {
                      final basari = (1.0 - s.ihtiyacSkoru) * 100;
                      return [
                        '${counter++}',
                        _norm(s.subeAdi),
                        _norm(s.ogrenciAdi),
                        '% ${basari.toStringAsFixed(0)}',
                      ];
                    }).toList();
                  }(),
                ),
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
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'agm_ogretmen_programlari.pdf',
        );
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
          fileName: 'agm_ogretmen_programlari.pdf',
          targetUserId: _selectedTeacherId!,
          title: 'Öğretmen Programı Paylaşımı',
          messageBody: 'Haftalık AGM programınız belirlendi.',
        );
      },
    );
  }

  Future<void> _exportExcel({bool allTeachers = false}) async {
    final excel = Excel.createExcel();
    final sheet = excel['Rapor'];

    final teachersToExport = allTeachers
        ? _teachers
        : [
            {'id': _selectedTeacherId, 'name': _selectedTeacherName},
          ];

    for (final teacher in teachersToExport) {
      final tId = teacher['id'];
      final tName = teacher['name'];
      if (tId == null) continue;

      final tGroups = widget.groups.where((g) => g.ogretmenId == tId).toList();

      sheet.appendRow([TextCellValue('AGM ÖĞRETMEN PROGRAMI - $tName')]);
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([
        TextCellValue('Gün'),
        TextCellValue('Saat'),
        TextCellValue('Ders'),
        TextCellValue('Derslik'),
        TextCellValue('Şube'),
        TextCellValue('Öğrenci Adı Soyadı'),
        TextCellValue('Başarı %'),
      ]);

      for (final g in tGroups) {
        final students = widget.assignmentsByGroup[g.id] ?? [];
        if (students.isEmpty) {
          sheet.appendRow([
            TextCellValue(g.gun),
            TextCellValue('${g.baslangicSaat}-${g.bitisSaat}'),
            TextCellValue(g.dersAdi),
            TextCellValue(g.derslikAdi ?? '-'),
            TextCellValue('-'),
            TextCellValue('-'),
            TextCellValue('-'),
          ]);
        } else {
          for (final s in students) {
            final basari = (1.0 - s.ihtiyacSkoru) * 100;
            sheet.appendRow([
              TextCellValue(g.gun),
              TextCellValue('${g.baslangicSaat}-${g.bitisSaat}'),
              TextCellValue(g.dersAdi),
              TextCellValue(g.derslikAdi ?? '-'),
              TextCellValue(s.subeAdi),
              TextCellValue(s.ogrenciAdi),
              TextCellValue('% ${basari.toStringAsFixed(0)}'),
            ]);
          }
        }
      }
      sheet.appendRow([TextCellValue('')]); // Gruplar arası boşluk
      sheet.appendRow([TextCellValue('')]);
    }

    final bytes = excel.save();
    if (bytes != null) {
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: 'agm_ogretmen_raporlari.xlsx',
      );
    }
  }
}
