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

/// Haftalık Derslik Takvim Ekranı
/// Seçilen dersliğin programını gösterir, akordeon içinde öğretmen ve konu detayları sunar.
class AgmClassroomTimetableScreen extends StatefulWidget {
  final AgmCycle cycle;
  final List<AgmGroup> groups;
  final Map<String, List<AgmAssignment>> assignmentsByGroup;

  const AgmClassroomTimetableScreen({
    Key? key,
    required this.cycle,
    required this.groups,
    required this.assignmentsByGroup,
  }) : super(key: key);

  @override
  State<AgmClassroomTimetableScreen> createState() =>
      _AgmClassroomTimetableScreenState();
}

class _AgmClassroomTimetableScreenState
    extends State<AgmClassroomTimetableScreen> {
  String? _selectedClassroomId;
  String? _selectedClassroomName;
  String _searchQuery = '';

  List<Map<String, dynamic>> _classrooms = [];
  List<AgmGroup> _classroomGroups = [];

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
    _buildClassroomList();
  }

  void _buildClassroomList() {
    final Map<String, String> classroomMap = {};
    bool hasUndefined = false;
    for (final g in widget.groups) {
      final hasStudents = (widget.assignmentsByGroup[g.id] ?? []).isNotEmpty;
      if (!hasStudents) continue;

      if (g.derslikId != null && g.derslikId!.isNotEmpty) {
        classroomMap[g.derslikId!] = g.derslikAdi ?? 'İsimsiz Derslik';
      } else {
        hasUndefined = true;
      }
    }
    _classrooms =
        classroomMap.entries.map((e) => {'id': e.key, 'name': e.value}).toList()
          ..sort((a, b) => _compareNatural(a['name']!, b['name']!));

    if (hasUndefined) {
      _classrooms.add({'id': 'undefined', 'name': 'Derslik Tanımlanmamış'});
    }
  }

  void _loadClassroomTimetable(String classroomId, String classroomName) {
    setState(() {
      _selectedClassroomId = classroomId;
      _selectedClassroomName = classroomName;
      _classroomGroups = widget.groups.where((g) {
        bool matchesRoom;
        if (classroomId == 'undefined') {
          matchesRoom = g.derslikId == null || g.derslikId!.isEmpty;
        } else {
          matchesRoom = g.derslikId == classroomId;
        }
        final hasStudents = (widget.assignmentsByGroup[g.id] ?? []).isNotEmpty;
        return matchesRoom && hasStudents;
      }).toList()
        ..sort((a, b) {
          int dayCompare =
              _gunler.indexOf(a.gun).compareTo(_gunler.indexOf(b.gun));
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
        title: const Text('Derslik Haftalık Takvim'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              final allSelected = _selectedClassroomId == null;
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
                child: _selectedClassroomId == null
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
        onTap: _showClassroomSearchSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.meeting_room, color: Colors.deepOrange.shade400),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedClassroomId == null
                      ? 'Derslik Seçin...'
                      : _selectedClassroomName!,
                  style: TextStyle(
                    color: _selectedClassroomId == null
                        ? Colors.grey.shade600
                        : Colors.black87,
                    fontWeight: _selectedClassroomId == null
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

  void _showClassroomSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        builder: (context, scrollController) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              final filtered = _classrooms
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
                          hintText: 'Derslik ismi...',
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
                              _loadClassroomTimetable(t['id'], t['name']);
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
          Icon(
            Icons.meeting_room_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'Lütfen bir derslik seçin',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetable() {
    if (_classroomGroups.isEmpty) {
      return const Center(child: Text('Bu dersliğe ait program bulunamadı.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _classroomGroups.length,
      itemBuilder: (context, index) {
        final group = _classroomGroups[index];
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
            subtitle: Text('${group.dersAdi} - ${group.ogretmenAdi}'),
            leading: CircleAvatar(
              backgroundColor: Colors.deepOrange.shade50,
              child: const Icon(
                Icons.meeting_room,
                color: Colors.deepOrange,
                size: 20,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const Text(
                      'PROGRAM DETAYLARI:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _detailRow(Icons.person, 'Öğretmen:', group.ogretmenAdi),
                    _detailRow(Icons.book, 'Ders:', group.dersAdi),
                    if (group.kazanimlar.isNotEmpty)
                      _detailRow(
                        Icons.label_important,
                        'Kazanımlar:',
                        group.kazanimlar.join(', '),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'ÖĞRENCİ LİSTESİ (${students.length}):',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (students.isEmpty)
                      const Text(
                        'Bu grupta öğrenci yok.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      Column(
                        children: students
                            .map(
                              (s) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline,
                                      size: 14,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${s.ogrenciAdi} (${s.subeAdi})',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.deepOrange.shade300),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
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
    bool allClassrooms = false,
    bool isShare = false,
  }) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final roomsToPrint = allClassrooms
        ? _classrooms
        : [
            {'id': _selectedClassroomId, 'name': _selectedClassroomName},
          ];

    for (final room in roomsToPrint) {
      final rId = room['id'];
      final rName = room['name'];
      if (rId == null) continue;

      final rGroups = widget.groups.where((g) {
        bool matchesRoom;
        if (rId == 'undefined') {
          matchesRoom = g.derslikId == null || g.derslikId!.isEmpty;
        } else {
          matchesRoom = g.derslikId == rId;
        }
        final hasStudents = (widget.assignmentsByGroup[g.id] ?? []).isNotEmpty;
        return matchesRoom && hasStudents;
      }).toList()
        ..sort((a, b) {
          int dayCompare =
              _gunler.indexOf(a.gun).compareTo(_gunler.indexOf(b.gun));
          if (dayCompare != 0) return dayCompare;
          return a.baslangicSaat.compareTo(b.baslangicSaat);
        });

      // Eğer derslik tanımlanmamışsa, her grubu ayrı sayfaya bas (Kullanıcı talebi: Boş olanlar her sayfada tek tek olsun)
      // Normal dersliklerde ise o dersliğin tüm programını bir arada tut (MultiPage içinde).
      final bool isUndefined = rId == 'undefined';

      if (isUndefined) {
        // Her grup için yeni bir sayfa (tekli grup raporu)
        for (final g in rGroups) {
          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (context) => _buildGroupReport(g, rName!, font, fontBold),
            ),
          );
        }
      } else {
        // Normal derslik: MultiPage (tüm slotları listele)
        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            header: (context) => _buildHeader(rName!, fontBold),
            footer: (context) => _buildFooter(context, font),
            build: (pw.Context context) {
              return rGroups.map((g) => _buildGroupCardInPdf(g, rName!, font, fontBold)).toList();
            },
          ),
        );
      }
    }

    final bytes = await doc.save();
    if (isShare) {
      if (kIsWeb && !allClassrooms && _selectedClassroomId != null) {
        _showWebShareDialog(bytes);
      } else {
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'agm_derslik_programlari.pdf',
        );
      }
    } else {
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => bytes);
    }
  }

  void _showWebShareDialog(Uint8List pdfBytes) {
    // Derslik programında bir öğretmenin kimliğini bul (ilgili derslikteki herhangi bir grup)
    final rGroups = widget.groups
        .where((g) => g.derslikId == _selectedClassroomId)
        .toList();
    if (rGroups.isEmpty || rGroups.first.ogretmenId.isEmpty) {
      // Öğretmen bilgisi yoksa sadece indir
      Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'agm_derslik_programlari.pdf',
      );
      return;
    }

    final teacherId = rGroups.first.ogretmenId;

    showDialog(
      context: context,
      builder: (context) {
        return AgmWebShareDialog(
          pdfBytes: pdfBytes,
          fileName: 'agm_derslik_programlari.pdf',
          targetUserId: teacherId,
          title: 'Derslik Programı Paylaşımı',
          messageBody: 'Haftalık AGM derslik programı ektedir.',
        );
      },
    );
  }

  Future<void> _exportExcel({bool allClassrooms = false}) async {
    final excel = Excel.createExcel();
    final sheet = excel['Rapor'];

    final roomsToExport = allClassrooms
        ? _classrooms
        : [
            {'id': _selectedClassroomId, 'name': _selectedClassroomName},
          ];

    for (final room in roomsToExport) {
      final rId = room['id'];
      final rName = room['name'];
      if (rId == null) continue;

      final rGroups = widget.groups.where((g) {
        bool matchesRoom;
        if (rId == 'undefined') {
          matchesRoom = g.derslikId == null || g.derslikId!.isEmpty;
        } else {
          matchesRoom = g.derslikId == rId;
        }
        final hasStudents = (widget.assignmentsByGroup[g.id] ?? []).isNotEmpty;
        return matchesRoom && hasStudents;
      }).toList();

      sheet.appendRow([
        TextCellValue('AGM DERSLİK PROGRAMI - ${_norm(rName!)}'),
      ]);
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([
        TextCellValue('Gün'),
        TextCellValue('Saat'),
        TextCellValue('Öğretmen'),
        TextCellValue('Ders'),
        TextCellValue('Konu/Kazanım'),
        TextCellValue('Öğrenci Adı Soyadı'),
        TextCellValue('Şubesi'),
      ]);

      for (final group in rGroups) {
        final students = widget.assignmentsByGroup[group.id] ?? [];
        final gDersAdi = _norm(group.dersAdi);
        final gOgretmenAdi = _norm(group.ogretmenAdi);
        final gGun = _norm(group.gun);
        final gKazanimlar = group.kazanimlar.map((k) => _norm(k)).toList();
        final kazanimStr = gKazanimlar.join(', ');

        if (students.isEmpty) {
          sheet.appendRow([
            TextCellValue(gGun),
            TextCellValue('${group.baslangicSaat}-${group.bitisSaat}'),
            TextCellValue(gOgretmenAdi),
            TextCellValue(gDersAdi),
            TextCellValue(kazanimStr),
            TextCellValue('-'),
            TextCellValue('-'),
          ]);
        } else {
          for (final s in students) {
            sheet.appendRow([
              TextCellValue(gGun),
              TextCellValue('${group.baslangicSaat}-${group.bitisSaat}'),
              TextCellValue(gOgretmenAdi),
              TextCellValue(gDersAdi),
              TextCellValue(kazanimStr),
              TextCellValue(_norm(s.ogrenciAdi)),
              TextCellValue(_norm(s.subeAdi)),
            ]);
          }
        }
      }
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([TextCellValue('')]);
    }

    final bytes = excel.save();
    if (bytes != null) {
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: 'agm_derslik_raporlari.xlsx',
      );
    }
  }

  pw.Widget _buildHeader(String rName, pw.Font fontBold) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(color: PdfColors.deepOrange800),
      child: pw.Text(
        'AGM DERSLİK PROGRAMI: ${_norm(rName)}',
        style: pw.TextStyle(
          font: fontBold,
          color: PdfColors.white,
          fontSize: 16,
        ),
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context context, pw.Font font) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'Rapor Tarihi: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year} | Sayfa ${context.pageNumber}',
        style: pw.TextStyle(
          font: font,
          fontSize: 8,
          color: PdfColors.grey500,
        ),
      ),
    );
  }

  pw.Widget _buildGroupReport(
    AgmGroup g,
    String rName,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildHeader(rName, fontBold),
        pw.SizedBox(height: 10),
        _buildGroupCardInPdf(g, rName, font, fontBold),
      ],
    );
  }

  pw.Widget _buildGroupCardInPdf(
    AgmGroup g,
    String rName,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final students = widget.assignmentsByGroup[g.id] ?? [];
    final gDersAdi = _norm(g.dersAdi);
    final gOgretmenAdi = _norm(g.ogretmenAdi);
    final gGun = _norm(g.gun);
    final gKazanimlar = g.kazanimlar.map((k) => _norm(k)).toList();

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(
          pw.Radius.circular(8),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Derslik: ${_norm(rName)}',
                    style: pw.TextStyle(font: fontBold, fontSize: 13),
                  ),
                  pw.Text(
                    'Gün: $gGun',
                    style: pw.TextStyle(font: font, fontSize: 11),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Öğretmen: $gOgretmenAdi',
                    style: pw.TextStyle(font: fontBold, fontSize: 11),
                  ),
                  pw.Text(
                    'Ders: $gDersAdi',
                    style: pw.TextStyle(font: font, fontSize: 11),
                  ),
                  pw.Text(
                    'Saat: ${g.baslangicSaat}-${g.bitisSaat}',
                    style: pw.TextStyle(font: fontBold, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          pw.Divider(color: PdfColors.orange200),
          pw.Text(
            'Kazanım: ${gKazanimlar.isNotEmpty ? gKazanimlar.join(", ") : "-"}',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 10,
              color: PdfColors.deepOrange800,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Öğrenci Listesi (${students.length}):',
            style: pw.TextStyle(font: fontBold, fontSize: 10),
          ),
          pw.SizedBox(height: 5),
          // Öğrenci listesini 3 sütuna böl ve şube sırasına göre sırala
          _build3ColumnStudentTable(students, font),
        ],
      ),
    );
  }

  pw.Widget _build3ColumnStudentTable(List<AgmAssignment> students, pw.Font font) {
    if (students.isEmpty) {
      return pw.Text('• Bu grupta öğrenci yok.', style: pw.TextStyle(font: font, fontSize: 8));
    }

    final sortedStudents = students.toList()
      ..sort((a, b) {
        final sc = a.subeAdi.compareTo(b.subeAdi);
        if (sc != 0) return sc;
        return a.ogrenciAdi.compareTo(b.ogrenciAdi);
      });

    final List<pw.TableRow> rows = [];
    for (int i = 0; i < sortedStudents.length; i += 3) {
      rows.add(
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text(
                '• ${_norm(sortedStudents[i].ogrenciAdi)} (${_norm(sortedStudents[i].subeAdi)})',
                style: pw.TextStyle(font: font, fontSize: 8),
              ),
            ),
            if (i + 1 < sortedStudents.length)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Text(
                   '• ${_norm(sortedStudents[i + 1].ogrenciAdi)} (${_norm(sortedStudents[i + 1].subeAdi)})',
                   style: pw.TextStyle(font: font, fontSize: 8),
                ),
              )
            else
              pw.SizedBox(),
            if (i + 2 < sortedStudents.length)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Text(
                   '• ${_norm(sortedStudents[i + 2].ogrenciAdi)} (${_norm(sortedStudents[i + 2].subeAdi)})',
                   style: pw.TextStyle(font: font, fontSize: 8),
                ),
              )
            else
              pw.SizedBox(),
          ],
        ),
      );
    }

    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
      },
      children: rows,
    );
  }

  /// Alfanümerik metinleri "doğal" sırada karşılaştırır.
  int _compareNatural(String a, String b) {
    if (a == 'Derslik Tanımlanmamış') return 1; // Tanımlanmamış olan en sonda olsun
    if (b == 'Derslik Tanımlanmamış') return -1;
    
    final RegExp re = RegExp(r'(\d+)|\D+');
    final Iterable<Match> aMatch = re.allMatches(a.toLowerCase());
    final Iterable<Match> bMatch = re.allMatches(b.toLowerCase());

    final itA = aMatch.iterator;
    final itB = bMatch.iterator;

    while (itA.moveNext() && itB.moveNext()) {
      final aStr = itA.current.group(0)!;
      final bStr = itB.current.group(0)!;

      if (itA.current.group(1) != null && itB.current.group(1) != null) {
        final aNum = int.parse(aStr);
        final bNum = int.parse(bStr);
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else {
        final cmp = aStr.compareTo(bStr);
        if (cmp != 0) return cmp;
      }
    }
    return a.length.compareTo(b.length);
  }
}
