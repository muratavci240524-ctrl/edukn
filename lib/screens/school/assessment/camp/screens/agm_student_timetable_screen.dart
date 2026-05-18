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

/// Öğrenci Haftalık Takvim Ekranı
/// Seçilen öğrencinin tüm AGM etüt atamalarını haftalık görünümde sunar.
class AgmStudentTimetableScreen extends StatefulWidget {
  final AgmCycle cycle;
  final List<AgmGroup> groups;
  final Map<String, List<AgmAssignment>> assignmentsByGroup;

  const AgmStudentTimetableScreen({
    Key? key,
    required this.cycle,
    required this.groups,
    required this.assignmentsByGroup,
  }) : super(key: key);

  @override
  State<AgmStudentTimetableScreen> createState() =>
      _AgmStudentTimetableScreenState();
}

class _AgmStudentTimetableScreenState extends State<AgmStudentTimetableScreen> {
  String? _selectedStudentId;
  String? _selectedStudentName;
  String _searchQuery = '';

  // Tüm öğrenci listesi (assignment'lardan topla)
  List<Map<String, dynamic>> _students = [];

  // Seçili öğrencinin atamaları
  List<_TimetableEntry> _entries = [];

  final List<String> _gunler = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
  ];

  final Map<String, Color> _dersRenkleri = {};
  final List<Color> _renkPaleti = [
    Colors.blue,
    Colors.green,
    Colors.purple,
    Colors.teal,
    Colors.indigo,
    Colors.pink,
    Colors.orange,
    Colors.cyan,
  ];

  @override
  void initState() {
    super.initState();
    _buildStudentList();
  }

  void _buildStudentList() {
    final Map<String, Map<String, dynamic>> studentMap = {};
    for (final entry in widget.assignmentsByGroup.entries) {
      final assignments = entry.value;
      for (final a in assignments) {
        if (!studentMap.containsKey(a.ogrenciId)) {
          studentMap[a.ogrenciId] = {
            'id': a.ogrenciId,
            'name': a.ogrenciAdi,
            'count': 1,
          };
        } else {
          studentMap[a.ogrenciId]!['count']++;
        }
      }
    }
    _students = studentMap.values.toList()
      ..sort((a, b) => a['name']!.toString().compareTo(b['name']!.toString()));
  }

  void _loadStudentTimetable(String studentId) {
    final entries = <_TimetableEntry>[];
    int colorIdx = 0;

    for (final entry in widget.assignmentsByGroup.entries) {
      final groupId = entry.key;
      final assignments = entry.value;
      final hasStudent = assignments.any((a) => a.ogrenciId == studentId);
      if (!hasStudent) continue;

      final group = widget.groups.firstWhere(
        (g) => g.id == groupId,
        orElse: () {
          return widget.groups.first;
        },
      );

      if (!_dersRenkleri.containsKey(group.dersId)) {
        _dersRenkleri[group.dersId] =
            _renkPaleti[colorIdx % _renkPaleti.length];
        colorIdx++;
      }

      entries.add(
        _TimetableEntry(
          gun: group.gun,
          baslangicSaat: group.baslangicSaat,
          bitisSaat: group.bitisSaat,
          dersAdi: group.dersAdi,
          ogretmenAdi: group.ogretmenAdi,
          kazanim: group.kazanimlar.isNotEmpty ? group.kazanimlar.first : null,
          renk: _dersRenkleri[group.dersId]!,
        ),
      );
    }

    // Güne göre sırala
    entries.sort(
      (a, b) => _gunler.indexOf(a.gun).compareTo(_gunler.indexOf(b.gun)),
    );

    setState(() {
      _selectedStudentId = studentId;
      _selectedStudentName = _students.firstWhere(
        (s) => s['id'] == studentId,
      )['name'];
      _entries = entries;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Öğrenci Haftalık Takvim',
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
              final allSelected = _selectedStudentId == null;
              switch (value) {
                case 'excel':
                  _exportExcel(allStudents: allSelected);
                  break;
                case 'print':
                  _showPrintOptionsDialog(
                    context,
                    allStudents: allSelected,
                    isShare: false,
                  );
                  break;
                case 'share':
                  _showPrintOptionsDialog(
                    context,
                    allStudents: allSelected,
                    isShare: true,
                  );
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
                child: _selectedStudentId == null
                    ? _buildNoStudentState()
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
      child: Column(
        children: [
          InkWell(
            onTap: _showStudentSearchSheet,
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
                      _selectedStudentId == null
                          ? 'Öğrenci Ara ve Seç...'
                          : '$_selectedStudentName (${_students.firstWhere((s) => s['id'] == _selectedStudentId)['count']} etüt)',
                      style: TextStyle(
                        color: _selectedStudentId == null
                            ? Colors.grey.shade600
                            : Colors.black87,
                        fontWeight: _selectedStudentId == null
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
        ],
      ),
    );
  }

  void _showStudentSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              final filtered = _students.where((s) {
                final name = s['name'].toString().toLowerCase();
                final query = _searchQuery.toLowerCase();
                return name.contains(query);
              }).toList();

              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Text(
                            'Öğrenci Seçin',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        autofocus: true,
                        onChanged: (v) {
                          setSheetState(() => _searchQuery = v);
                        },
                        decoration: InputDecoration(
                          hintText: 'İsim ile ara...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.deepOrange,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'Öğrenci bulunamadı',
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final s = filtered[index];
                                final isSelected =
                                    s['id'] == _selectedStudentId;
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected
                                        ? Colors.deepOrange
                                        : Colors.deepOrange.shade50,
                                    child: Icon(
                                      Icons.person,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.deepOrange,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    s['name'] ?? '',
                                    style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? Colors.deepOrange
                                          : Colors.black87,
                                    ),
                                  ),
                                  subtitle: Text('${s['count']} etüt'),
                                  trailing: isSelected
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Colors.deepOrange,
                                        )
                                      : null,
                                  onTap: () {
                                    _loadStudentTimetable(s['id']);
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

  Widget _buildNoStudentState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'Öğrenci seçin',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetable() {
    if (_entries.isEmpty) {
      return const Center(child: Text('Bu öğrenciye atama yapılmamış.'));
    }

    // Güne göre grupla
    final Map<String, List<_TimetableEntry>> byDay = {};
    for (final e in _entries) {
      byDay.putIfAbsent(e.gun, () => []).add(e);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Özet
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.deepOrange.shade400,
                  Colors.deepOrange.shade600,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedStudentName ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_entries.length} etüt',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Haftalık program',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Gün bazlı liste
          ...(_gunler.where((g) => byDay.containsKey(g)).map((gun) {
            final daysEntries = byDay[gun]!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    gun,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange.shade700,
                    ),
                  ),
                ),
                ...daysEntries.map((e) => _buildEntryCard(e)),
                const SizedBox(height: 12),
              ],
            );
          })),
        ],
      ),
    );
  }

  Widget _buildEntryCard(_TimetableEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: entry.renk.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: entry.renk.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 44,
            decoration: BoxDecoration(
              color: entry.renk,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.dersAdi,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: entry.renk,
                    fontSize: 14,
                  ),
                ),
                if (entry.kazanim != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.kazanim!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  '${entry.baslangicSaat} – ${entry.bitisSaat}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.person_outline, size: 14, color: Colors.grey.shade400),
              const SizedBox(height: 2),
              Text(
                entry.ogretmenAdi,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPrintOptionsDialog(
    BuildContext context, {
    bool allStudents = false,
    bool isShare = false,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isShare ? 'Paylaşım Seçenekleri' : 'Yazdırma Seçenekleri'),
        content: const Text(
          'Öğrenci programlarını nasıl formatlamak istersiniz?\n\n'
          '• Ayrı Sayfalar: Her öğrenci için yeni bir sayfa.\n'
          '• 4 Öğrenci/Sayfa: Bir sayfaya 4 öğrenci kartı sığdırılır (ekonomik).',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _printPDF(
                allStudents: allStudents,
                gridMode: false,
                isShare: isShare,
              );
            },
            child: const Text('AYRI SAYFALAR'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _printPDF(
                allStudents: allStudents,
                gridMode: true,
                isShare: isShare,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: const Text(
              '8 ÖĞRENCİ / SAYFA',
              style: TextStyle(color: Colors.white),
            ),
          ),
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
    bool allStudents = false,
    bool gridMode = false,
    bool isShare = false,
  }) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final studentsToPrint = allStudents
        ? _students
        : [
            {'id': _selectedStudentId, 'name': _selectedStudentName},
          ];

    if (gridMode) {
      // 8'li Grid Modu (2 sütun x 4 satır)
      for (int i = 0; i < studentsToPrint.length; i += 8) {
        final currentBatch = studentsToPrint.skip(i).take(8).toList();
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(20),
            build: (pw.Context context) {
              return pw.GridView(
                crossAxisCount: 2,
                childAspectRatio: 0.65,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: currentBatch.map((s) {
                  final sId = s['id'];
                  final sName = s['name'];
                  final sEntries = _getStudentEntries(sId);

                  return pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey400,
                        width: 0.5,
                      ),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(6),
                      ),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          sName != null ? _norm(sName) : '',
                          style: pw.TextStyle(font: fontBold, fontSize: 10),
                          maxLines: 1,
                        ),
                        pw.Divider(thickness: 0.5, height: 6),
                        ...sEntries
                            .take(6)
                            .map(
                              (e) => pw.Padding(
                                padding: const pw.EdgeInsets.only(bottom: 2),
                                child: pw.Column(
                                  crossAxisAlignment:
                                      pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      '${_norm(e.gun)} | ${e.baslangicSaat}-${e.bitisSaat}',
                                      style: pw.TextStyle(
                                        font: font,
                                        fontSize: 7,
                                      ),
                                    ),
                                    pw.Text(
                                      '${_norm(e.dersAdi)} (${_norm(e.ogretmenAdi)})',
                                      style: pw.TextStyle(
                                        font: fontBold,
                                        fontSize: 7,
                                        color: PdfColors.deepOrange,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        if (sEntries.length > 6)
                          pw.Text(
                            '...',
                            style: pw.TextStyle(font: fontBold, fontSize: 7),
                          ),
                        if (sEntries.isEmpty)
                          pw.Text(
                            'Program yok',
                            style: pw.TextStyle(
                              font: font,
                              fontSize: 7,
                              fontStyle: pw.FontStyle.italic,
                            ),
                          ),
                        pw.Spacer(),
                        pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(
                            'eduKN AGM',
                            style: pw.TextStyle(
                              font: font,
                              fontSize: 5,
                              color: PdfColors.grey500,
                            ),
                          ),
                        ),
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
      // Her Öğrenci Ayrı Sayfa
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
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.deepOrange700,
                    ),
                    child: pw.Text(
                      'ÖĞRENCİ AGM HAFTALIK PROGRAMI',
                      style: pw.TextStyle(
                        font: fontBold,
                        color: PdfColors.white,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 15),
                  pw.Text(
                    'Öğrenci: ${sName != null ? _norm(sName) : ''}',
                    style: pw.TextStyle(font: fontBold, fontSize: 16),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Table.fromTextArray(
                    headers: ['Gün', 'Saat', 'Ders', 'Öğretmen', 'Kazanım'],
                    headerStyle: pw.TextStyle(
                      font: fontBold,
                      color: PdfColors.white,
                    ),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.deepOrange400,
                    ),
                    cellStyle: pw.TextStyle(font: font, fontSize: 10),
                    data: sEntries
                        .map(
                          (e) => [
                            _norm(e.gun),
                            '${e.baslangicSaat}-${e.bitisSaat}',
                            _norm(e.dersAdi),
                            _norm(e.ogretmenAdi),
                            e.kazanim != null ? _norm(e.kazanim!) : '-',
                          ],
                        )
                        .toList(),
                  ),
                  pw.Spacer(),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      'eduKN Eğitim Yönetim Sistemi',
                      style: pw.TextStyle(
                        font: font,
                        fontSize: 8,
                        color: PdfColors.grey500,
                      ),
                    ),
                  ),
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
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'agm_ogrenci_programlari.pdf',
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
          fileName: 'agm_ogrenci_programlari.pdf',
          targetUserId: _selectedStudentId!,
          title: 'Öğrenci Programı Paylaşımı',
          messageBody: 'Haftalık AGM bireysel programınız belirlendi.',
        );
      },
    );
  }

  List<_TimetableEntry> _getStudentEntries(String studentId) {
    final entries = <_TimetableEntry>[];
    for (final entry in widget.assignmentsByGroup.entries) {
      final assignments = entry.value;
      if (assignments.any((a) => a.ogrenciId == studentId)) {
        final group = widget.groups.firstWhere((g) => g.id == entry.key);
        entries.add(
          _TimetableEntry(
            gun: group.gun,
            baslangicSaat: group.baslangicSaat,
            bitisSaat: group.bitisSaat,
            dersAdi: group.dersAdi,
            ogretmenAdi: group.ogretmenAdi,
            kazanim: group.kazanimlar.isNotEmpty
                ? group.kazanimlar.first
                : null,
            renk: Colors.orange, // Sabit renk PDF için yeterli
          ),
        );
      }
    }
    entries.sort(
      (a, b) => _gunler.indexOf(a.gun).compareTo(_gunler.indexOf(b.gun)),
    );
    return entries;
  }

  Future<void> _exportExcel({bool allStudents = false}) async {
    final excel = Excel.createExcel();
    final sheet = excel['Rapor'];

    final studentsToExport = allStudents
        ? _students
        : [
            {'id': _selectedStudentId, 'name': _selectedStudentName},
          ];

    for (final s in studentsToExport) {
      final sId = s['id'];
      final sName = s['name'];
      final sEntries = _getStudentEntries(sId);

      sheet.appendRow([TextCellValue('AGM Öğrenci Programı - $sName')]);
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([
        TextCellValue('Gün'),
        TextCellValue('Saat'),
        TextCellValue('Ders'),
        TextCellValue('Öğretmen'),
        TextCellValue('Konu/Kazanım'),
      ]);

      for (final e in sEntries) {
        sheet.appendRow([
          TextCellValue(e.gun),
          TextCellValue('${e.baslangicSaat}-${e.bitisSaat}'),
          TextCellValue(e.dersAdi),
          TextCellValue(e.ogretmenAdi),
          TextCellValue(e.kazanim ?? '-'),
        ]);
      }
      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([TextCellValue('')]);
    }

    final bytes = excel.save();
    if (bytes != null) {
      await Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: 'agm_ogrenci_raporlari.xlsx',
      );
    }
  }
}

class _TimetableEntry {
  final String gun;
  final String baslangicSaat;
  final String bitisSaat;
  final String dersAdi;
  final String ogretmenAdi;
  final String? kazanim;
  final Color renk;

  _TimetableEntry({
    required this.gun,
    required this.baslangicSaat,
    required this.bitisSaat,
    required this.dersAdi,
    required this.ogretmenAdi,
    this.kazanim,
    required this.renk,
  });
}
