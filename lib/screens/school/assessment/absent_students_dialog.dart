import 'package:excel/excel.dart' as xl;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../models/assessment/trial_exam_model.dart';
import 'evaluation_models.dart';

/// Sınava katılmayan öğrencileri listeler (alttan açılan menü içeriği).
/// Liste yazdırılabilir, PDF ve Excel olarak indirilebilir.
class AbsentStudentsDialog extends StatefulWidget {
  final Map<String, dynamic> systemStudentsMap;
  final List<StudentResult> results;
  final List<TrialExamSession> sessions;
  final String examName;

  const AbsentStudentsDialog({
    Key? key,
    required this.systemStudentsMap,
    required this.results,
    required this.sessions,
    this.examName = '',
  }) : super(key: key);

  /// Öğrencinin ad soyadını tekrarsız döndürür.
  /// `fullName` zaten soyadı içerdiği için soyadı tekrar eklenmez.
  static String studentFullName(Map<String, dynamic> s) {
    final full = (s['fullName'] ?? '').toString().trim();
    final name = (s['name'] ?? '').toString().trim();
    final surname = (s['surname'] ?? '').toString().trim();

    final base = full.isNotEmpty ? full : name;
    if (surname.isEmpty) return base.isEmpty ? 'İsimsiz' : base;
    if (base.isEmpty) return surname;

    final baseLower = _trLower(base);
    final surnameLower = _trLower(surname);
    if (baseLower.contains(surnameLower)) return base;
    return '$base $surname';
  }

  static String _trLower(String s) =>
      s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

  @override
  _AbsentStudentsDialogState createState() => _AbsentStudentsDialogState();
}

class _AbsentTab {
  final String label;
  final String fileSuffix;
  final List<Map<String, dynamic>> students;
  _AbsentTab(this.label, this.fileSuffix, this.students);
}

class _AbsentStudentsDialogState extends State<AbsentStudentsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<_AbsentTab> _tabs;
  String _query = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = _buildTabs();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Veri
  // ---------------------------------------------------------------------------

  Map<String, StudentResult> get _matchedBySystemId {
    final map = <String, StudentResult>{};
    for (final r in widget.results) {
      if (r.isMatched && r.systemStudentId != null) {
        map[r.systemStudentId!] = r;
      }
    }
    return map;
  }

  List<_AbsentTab> _buildTabs() {
    final matched = _matchedBySystemId;
    final tabs = <_AbsentTab>[];

    List<Map<String, dynamic>> collect(bool Function(StudentResult? r) isAbsent) {
      final list = <Map<String, dynamic>>[];
      widget.systemStudentsMap.forEach((id, data) {
        if (data is! Map) return;
        final m = Map<String, dynamic>.from(data);
        m['id'] ??= id;
        if (isAbsent(matched[id])) list.add(m);
      });
      list.sort(_compareStudents);
      return list;
    }

    if (widget.sessions.length > 1) {
      // Hiçbir oturuma girmeyenler (istatistikteki sayı ile aynı)
      tabs.add(_AbsentTab('Tümü', 'Tumu', collect((r) => r == null)));
      for (final s in widget.sessions) {
        tabs.add(
          _AbsentTab(
            '${s.sessionNumber}. Oturum',
            '${s.sessionNumber}_Oturum',
            collect(
              (r) => r == null || !r.participatedSessions.contains(s.sessionNumber),
            ),
          ),
        );
      }
    } else {
      tabs.add(_AbsentTab('Katılmayanlar', 'Liste', collect((r) => r == null)));
    }
    return tabs;
  }

  int _compareStudents(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ca = _trKey(_branchOf(a));
    final cb = _trKey(_branchOf(b));
    final c = ca.compareTo(cb);
    if (c != 0) return c;
    return _trKey(AbsentStudentsDialog.studentFullName(a))
        .compareTo(_trKey(AbsentStudentsDialog.studentFullName(b)));
  }

  static String _trKey(String s) {
    const map = {'ç': 'c{', 'ğ': 'g{', 'ı': 'h{', 'ö': 'o{', 'ş': 's{', 'ü': 'u{'};
    final lower = s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      b.write(map[ch] ?? ch);
    }
    return b.toString();
  }

  String _noOf(Map<String, dynamic> s) =>
      (s['studentNo'] ?? s['studentNumber'] ?? '').toString();

  String _branchOf(Map<String, dynamic> s) =>
      (s['className'] ?? s['branch'] ?? s['classLevel'] ?? '').toString();

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> list) {
    if (_query.isEmpty) return list;
    final q = _trKey(_query);
    return list.where((s) {
      return _trKey(AbsentStudentsDialog.studentFullName(s)).contains(q) ||
          _noOf(s).toLowerCase().contains(q) ||
          _trKey(_branchOf(s)).contains(q);
    }).toList();
  }

  _AbsentTab get _currentTab => _tabs[_tabController.index];

  String get _examTitle =>
      widget.examName.trim().isEmpty ? 'Sınav' : widget.examName.trim();

  String get _fileBaseName {
    final safe = _examTitle
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    return 'Katilmayanlar_${safe}_${_currentTab.fileSuffix}';
  }

  // ---------------------------------------------------------------------------
  // Dışa aktarma
  // ---------------------------------------------------------------------------

  Future<Uint8List> _buildPdf(_AbsentTab tab) async {
    pw.Font font;
    pw.Font fontBold;
    try {
      font = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
      fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    } catch (_) {
      font = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
    }

    final list = tab.students;
    final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());
    final doc = pw.Document();

    pw.Widget cell(String t, pw.Font f,
        {pw.TextAlign align = pw.TextAlign.left, PdfColor? color}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(
          t,
          textAlign: align,
          style: pw.TextStyle(font: f, fontSize: 9.5, color: color),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          margin: const pw.EdgeInsets.only(bottom: 14),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.red700, width: 2),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _examTitle.toUpperCase(),
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 13,
                        color: PdfColors.red900,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'SINAVA KATILMAYAN ÖĞRENCİLER'
                      '${_tabs.length > 1 ? ' - ${tab.label.toUpperCase()}' : ''}',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 10,
                        color: PdfColors.grey800,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Toplam: ${list.length} öğrenci',
                    style: pw.TextStyle(font: fontBold, fontSize: 9),
                  ),
                  pw.Text(
                    dateStr,
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
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => [
          if (list.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.all(24),
              child: pw.Center(
                child: pw.Text(
                  'Katılmayan öğrenci bulunmuyor.',
                  style: pw.TextStyle(font: font, fontSize: 11),
                ),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(32),
                1: pw.FixedColumnWidth(70),
                2: pw.FlexColumnWidth(4),
                3: pw.FlexColumnWidth(1.6),
                4: pw.FlexColumnWidth(2.2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.red50),
                  repeat: true,
                  children: [
                    cell('Sıra', fontBold, align: pw.TextAlign.center),
                    cell('Öğrenci No', fontBold),
                    cell('Adı Soyadı', fontBold),
                    cell('Şube', fontBold),
                    cell('İmza / Açıklama', fontBold),
                  ],
                ),
                ...List.generate(list.length, (i) {
                  final s = list[i];
                  return pw.TableRow(
                    decoration: i.isOdd
                        ? const pw.BoxDecoration(color: PdfColors.grey100)
                        : null,
                    children: [
                      cell('${i + 1}', font, align: pw.TextAlign.center),
                      cell(_noOf(s), font),
                      cell(AbsentStudentsDialog.studentFullName(s), font),
                      cell(_branchOf(s), font),
                      cell('', font),
                    ],
                  );
                }),
              ],
            ),
        ],
      ),
    );

    return doc.save();
  }

  Future<void> _runExport(Future<void> Function() action, String okMsg) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && okMsg.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(okMsg), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Katılmayanlar dışa aktarma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() => _runExport(() async {
        final tab = _currentTab;
        final bytes = await _buildPdf(tab);
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: '$_fileBaseName.pdf',
        );
      }, '');

  Future<void> _downloadPdf() => _runExport(() async {
        final bytes = await _buildPdf(_currentTab);
        await FileSaver.instance.saveFile(
          name: _fileBaseName,
          bytes: bytes,
          ext: 'pdf',
          mimeType: MimeType.pdf,
        );
      }, 'PDF indirildi.');

  Future<void> _downloadExcel() => _runExport(() async {
        final tab = _currentTab;
        final excel = xl.Excel.createExcel();
        const sheetName = 'Katılmayanlar';
        final sheet = excel[sheetName];
        excel.setDefaultSheet(sheetName);

        final titleStyle = xl.CellStyle(
          bold: true,
          fontSize: 14,
          fontColorHex: xl.ExcelColor.fromHexString('#B71C1C'),
        );
        final subStyle = xl.CellStyle(
          fontColorHex: xl.ExcelColor.fromHexString('#6B7280'),
        );
        final headStyle = xl.CellStyle(
          bold: true,
          horizontalAlign: xl.HorizontalAlign.Center,
          backgroundColorHex: xl.ExcelColor.fromHexString('#C62828'),
          fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        );

        xl.Data c(int col, int row) =>
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));

        sheet.merge(
          xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
          xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0),
        );
        c(0, 0)
          ..value = xl.TextCellValue('$_examTitle - Sınava Katılmayan Öğrenciler')
          ..cellStyle = titleStyle;

        sheet.merge(
          xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
          xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1),
        );
        c(0, 1)
          ..value = xl.TextCellValue(
            '${_tabs.length > 1 ? '${tab.label} • ' : ''}'
            'Toplam ${tab.students.length} öğrenci • '
            '${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
          )
          ..cellStyle = subStyle;

        const headers = ['Sıra', 'Öğrenci No', 'Adı Soyadı', 'Şube'];
        for (var i = 0; i < headers.length; i++) {
          c(i, 3)
            ..value = xl.TextCellValue(headers[i])
            ..cellStyle = headStyle;
        }

        for (var i = 0; i < tab.students.length; i++) {
          final s = tab.students[i];
          final row = 4 + i;
          c(0, row)
            ..value = xl.IntCellValue(i + 1)
            ..cellStyle = xl.CellStyle(horizontalAlign: xl.HorizontalAlign.Center);
          c(1, row).value = xl.TextCellValue(_noOf(s));
          c(2, row).value =
              xl.TextCellValue(AbsentStudentsDialog.studentFullName(s));
          c(3, row).value = xl.TextCellValue(_branchOf(s));
        }

        sheet.setColumnWidth(0, 8);
        sheet.setColumnWidth(1, 14);
        sheet.setColumnWidth(2, 36);
        sheet.setColumnWidth(3, 14);

        if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

        // encode(): web'de otomatik indirme tetiklemez (save() tetikler)
        final bytes = excel.encode();
        if (bytes == null) throw Exception('Excel oluşturulamadı');
        await FileSaver.instance.saveFile(
          name: _fileBaseName,
          bytes: Uint8List.fromList(bytes),
          ext: 'xlsx',
          mimeType: MimeType.microsoftExcel,
        );
      }, 'Excel indirildi.');

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final current = _currentTab;
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.person_off_rounded, color: Colors.red.shade700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Katılmayan Öğrenciler',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${current.students.length} öğrenci sınava katılmadı',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.grey.shade500),
                  onPressed: () => Navigator.pop(context),
                  splashRadius: 20,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Dışa aktarma butonları
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: _exportButton(
                    icon: Icons.print_rounded,
                    label: 'Yazdır',
                    color: Colors.blueGrey.shade700,
                    onTap: _print,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _exportButton(
                    icon: Icons.picture_as_pdf_rounded,
                    label: 'PDF',
                    color: Colors.red.shade700,
                    onTap: _downloadPdf,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _exportButton(
                    icon: Icons.table_chart_rounded,
                    label: 'Excel',
                    color: Colors.green.shade700,
                    onTap: _downloadExcel,
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: 12),

          // Arama
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'İsim, numara veya şube ile ara...',
                prefixIcon: Icon(Icons.search, color: Colors.red.shade400),
                isDense: true,
                filled: true,
                fillColor: Colors.grey.shade50,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.red.shade200, width: 2),
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),

          if (_tabs.length > 1)
            TabBar(
              controller: _tabController,
              isScrollable: _tabs.length > 4,
              labelColor: Colors.red.shade700,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.red.shade600,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              tabs: _tabs
                  .map((t) => Tab(text: '${t.label} (${t.students.length})'))
                  .toList(),
            ),
          const SizedBox(height: 4),
          Divider(height: 1, color: Colors.grey.shade200),

          Expanded(
            child: Container(
              color: Colors.grey.shade50,
              child: TabBarView(
                controller: _tabController,
                children: _tabs.map((t) => _buildList(_filtered(t.students))).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        backgroundColor: color.withValues(alpha: 0.06),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: Colors.green.shade300),
            const SizedBox(height: 12),
            Text(
              _query.isEmpty ? 'Katılmayan öğrenci yok.' : 'Sonuç bulunamadı.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final s = list[index];
        final no = _noOf(s);
        final branch = _branchOf(s);
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.red.shade50,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              AbsentStudentsDialog.studentFullName(s),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'No: ${no.isNotEmpty ? no : '-'}  •  Şube: ${branch.isNotEmpty ? branch : '-'}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
        );
      },
    );
  }
}
