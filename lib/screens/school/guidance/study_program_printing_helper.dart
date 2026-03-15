import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bir sonraki Flutter frame'ini bekler → animasyon dondurulmaz.
Future<void> _yieldFrame() {
  final completer = Completer<void>();
  SchedulerBinding.instance.addPostFrameCallback((_) => completer.complete());
  return completer.future;
}

// Top-level function for compute (ZIP encoding in isolate)
Uint8List _encodeZipIsolate(Map<String, Uint8List> files) {
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  final encoder = ZipEncoder();
  // level: 0 = STORE (no compression) — PDFs already compressed, very fast
  final zipped = encoder.encode(archive, level: 0);
  if (zipped == null) return Uint8List(0);
  return Uint8List.fromList(zipped);
}

class StudyProgramPrintingHelper {
  static pw.Font? _pdfFont;
  static pw.Font? _pdfFontBold;
  static pw.Font? _pdfFontItalic;
  static pw.Font? _pdfFontIcons;
  static pw.MemoryImage? _pdfLogo;

  static Future<void> _loadAssets() async {
    _pdfFont ??= await PdfGoogleFonts.openSansRegular();
    _pdfFontBold ??= await PdfGoogleFonts.openSansBold();
    _pdfFontItalic ??= await PdfGoogleFonts.openSansItalic();
    _pdfFontIcons ??= await PdfGoogleFonts.materialIcons();

    if (_pdfLogo == null) {
      try {
        final logoData = await rootBundle.load('assets/images/logo.png');
        _pdfLogo = pw.MemoryImage(logoData.buffer.asUint8List());
      } catch (e) {
        debugPrint('Logo load error: $e');
      }
    }
  }

  static bool _cancelled = false;

  // ─── Toplu PDF ─────────────────────────────────────────────────────────────
  static Future<void> generateBulkPdf(
    BuildContext context,
    List<Map<String, dynamic>> programs, {
    bool includeSchedule = true,
    bool includeAnalysis = true,
    bool showPriority1 = true,
    bool showPriority2 = true,
  }) async {
    final progress = ValueNotifier<double>(0);
    final status = ValueNotifier<String>('Hazırlanıyor...');
    _cancelled = false;

    _showProgress(context, progress, status, onCancel: () => _cancelled = true);
    // Dialog animasyonu render edilsin (120ms = ~7 frame)
    await _yieldFrame();

    try {
      status.value = 'Kaynaklar yükleniyor...';
      await _yieldFrame();
      await _loadAssets();
      // Fontlar yüklendikten sonra bir frame daha ver
      await _yieldFrame();
      final pdf = pw.Document();

      for (var i = 0; i < programs.length; i++) {
        if (_cancelled) break;

        status.value = 'PDF Hazırlanıyor (${i + 1} / ${programs.length})';
        // Her program öncesi animasyona nefes ver (bir frame)
        await _yieldFrame();
        await _addProgramToDocument(
          pdf,
          programs[i],
          _pdfFont!,
          _pdfFontBold!,
          _pdfFontItalic!,
          _pdfFontIcons!,
          logo: _pdfLogo,
          includeSchedule: includeSchedule,
          includeAnalysis: includeAnalysis,
          showPriority1: showPriority1,
          showPriority2: showPriority2,
        );

        progress.value = (i + 1) / programs.length;
        // İlerleme güncellendikten sonra bir frame yield
        await _yieldFrame();
      }

      if (_cancelled) {
        if (context.mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        return;
      }

      status.value = 'Dosya kaydediliyor...';
      final bytes = await pdf.save();

      if (context.mounted && Navigator.canPop(context)) Navigator.pop(context);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: 'toplu-calisma-programi.pdf',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF Hazırlandı. Yazdırma penceresi açılıyor...'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata (Toplu PDF): $e')));
      }
    }
  }

  // ─── Toplu ZIP ─────────────────────────────────────────────────────────────
  static Future<void> generateBulkZip(
    BuildContext context,
    List<Map<String, dynamic>> programs, {
    bool includeSchedule = true,
    bool includeAnalysis = true,
    bool showPriority1 = true,
    bool showPriority2 = true,
  }) async {
    final progress = ValueNotifier<double>(0);
    final status = ValueNotifier<String>('Hazırlanıyor...');
    _cancelled = false;

    _showProgress(context, progress, status, onCancel: () => _cancelled = true);
    // Dialog animasyonu render edilsin (120ms = ~7 frame)
    await _yieldFrame();

    try {
      status.value = 'Kaynaklar yükleniyor...';
      await _yieldFrame();
      await _loadAssets();
      await _yieldFrame();
      final Map<String, Uint8List> pdfFiles = {};

      // Web'de Future.wait paralel DEĞİL — tek thread bloke eder.
      // Sıralı işlem + 4ms yield = animasyon akışkan kalır.
      for (int i = 0; i < programs.length; i++) {
        if (_cancelled) break;

        status.value = 'Dosya Hazırlanıyor (${i + 1} / ${programs.length})';
        await _yieldFrame();

        final program = programs[i];
        final pdf = pw.Document();
        await _addProgramToDocument(
          pdf,
          program,
          _pdfFont!,
          _pdfFontBold!,
          _pdfFontItalic!,
          _pdfFontIcons!,
          logo: _pdfLogo,
          includeSchedule: includeSchedule,
          includeAnalysis: includeAnalysis,
          showPriority1: showPriority1,
          showPriority2: showPriority2,
        );

        await _yieldFrame();
        final bytes = await pdf.save();
        pdfFiles['program-${program['studentName']}.pdf'] = bytes;

        progress.value = (i + 1) / programs.length;
        await _yieldFrame();
      }

      if (_cancelled) {
        if (context.mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        return;
      }

      status.value = 'Dosyalar sıkıştırılıyor...';
      progress.value = 1.0;

      final zipData = await compute(_encodeZipIsolate, pdfFiles);

      if (context.mounted && Navigator.canPop(context)) Navigator.pop(context);

      if (zipData.isNotEmpty) {
        await Printing.sharePdf(
          bytes: zipData,
          filename: 'calisma-programlari.zip',
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ZIP Dosyası İndiriliyor/Paylaşılıyor...'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata (ZIP): $e')));
      }
    }
  }

  // ─── Progress Dialog Launcher ───────────────────────────────────────────────
  static void _showProgress(
    BuildContext context,
    ValueNotifier<double> progress,
    ValueNotifier<String> status, {
    VoidCallback? onCancel,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => _PdfProgressDialog(
        progress: progress,
        status: status,
        onCancel: () {
          onCancel?.call();
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  // ─── Ders adı kısaltıcı ────────────────────────────────────────────────────
  static String _shortenSub(String sub) {
    if (sub == 'İlköğretim Matematik') return 'Matematik';
    return sub;
  }

  // ─── PDF Oluşturucu ────────────────────────────────────────────────────────
  static Future<void> _addProgramToDocument(
    pw.Document pdf,
    Map<String, dynamic> program,
    pw.Font font,
    pw.Font fontBold,
    pw.Font fontItalic,
    pw.Font fontIcons, {
    pw.MemoryImage? logo,
    required bool includeSchedule,
    required bool includeAnalysis,
    required bool showPriority1,
    required bool showPriority2,
  }) async {
    final studentName = program['studentName'] ?? 'Öğrenci';

    // Safe casting for schedule
    final Map<String, List<String>> schedule = {};
    if (program['schedule'] is Map) {
      (program['schedule'] as Map).forEach((key, value) {
        if (value is Iterable) {
          schedule[key.toString()] = value.map((e) => e.toString()).toList();
        } else {
          schedule[key.toString()] = [];
        }
      });
    }

    // Safe casting for topicAnalysis
    final List<Map<String, dynamic>> analysisList = [];
    if (program['topicAnalysis'] is List) {
      for (var item in (program['topicAnalysis'] as List)) {
        if (item is Map) {
          analysisList.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final Map<String, int> thresholds = {};
    if (program['thresholds'] is Map) {
      (program['thresholds'] as Map).forEach((k, v) {
        if (v is num) thresholds[k.toString()] = v.toInt();
      });
    }

    // Statik AI mesajı (kullanıcı isteği)
    String aiReportContent =
        'Selam $studentName, senin için hazırladığımız bu program, son deneme sınavındaki eksiklerini kapatmaya yönelik özel bir yol haritasıdır. Bu çalışmaları aksatmadan yürütürken, öğretmenlerinin verdiği ödevleri de programa dahil ederek disiplinli bir şekilde ilerlemeni bekliyoruz. Başarılar dileriz!';

    // Her sayfa eklemesi öncesi yield — animasyon için kritik
    await _yieldFrame();

    // Sayfa 1: Analiz (Dikey)
    if (includeAnalysis && analysisList.isNotEmpty) {
      final priority1List = analysisList.where((item) {
        int t = thresholds[item['subject']] ?? 70;
        double s = (item['success'] as num?)?.toDouble() ?? 0;
        int wrong = (item['wrong'] as int?) ?? 0;
        return (s < t || wrong > 0);
      }).toList();

      final priority2List = analysisList.where((item) {
        int t = thresholds[item['subject']] ?? 70;
        double s = (item['success'] as num?)?.toDouble() ?? 0;
        int wrong = (item['wrong'] as int?) ?? 0;
        return (s >= t && wrong == 0);
      }).toList();

      if ((showPriority1 && priority1List.isNotEmpty) ||
          (showPriority2 && priority2List.isNotEmpty)) {
        pdf.addPage(
          pw.MultiPage(
            pageTheme: pw.PageTheme(
              pageFormat: PdfPageFormat.a4,
              theme: pw.ThemeData.withFont(
                base: font,
                bold: fontBold,
                italic: fontItalic,
                icons: fontIcons,
              ),
              buildBackground: (context) => logo == null
                  ? pw.SizedBox()
                  : pw.Center(
                      child: pw.Opacity(
                        opacity: 0.07,
                        child: pw.Image(logo, width: 150),
                      ),
                    ),
            ),
            build: (pw.Context context) {
              return [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'KİŞİSELLEŞTİRİLMİŞ KAZANIM ANALİZİ',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo900,
                      ),
                    ),
                    pw.Text(
                      '$studentName',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),
                if (showPriority1 && priority1List.isNotEmpty) ...[
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.red50,
                      border: pw.Border(
                        left: pw.BorderSide(color: PdfColors.red, width: 3),
                      ),
                    ),
                    child: pw.Text(
                      '1. Öncelikli Konu Listesi (Çalışılması Gerekenler)',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red900,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  _buildAnalysisListTable(priority1List, true),
                  pw.SizedBox(height: 16),
                ],
                if (showPriority2 && priority2List.isNotEmpty) ...[
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue50,
                      border: pw.Border(
                        left: pw.BorderSide(color: PdfColors.blue, width: 3),
                      ),
                    ),
                    child: pw.Text(
                      '2. Öncelikli Konu Listesi (Pekiştirilecekler)',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  _buildAnalysisListTable(priority2List, false),
                ],
              ];
            },
          ),
        );
      }
    }

    // Sayfa 1 ve 2 arasında animasyona nefes ver
    await _yieldFrame();

    // Sayfa 2: Program Tablosu (Yatay)
    if (includeSchedule) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          theme: pw.ThemeData.withFont(
            base: font,
            bold: fontBold,
            italic: fontItalic,
            icons: fontIcons,
          ),
          build: (pw.Context context) {
            return pw.Stack(
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Bireysel Analiz Temelli Gelişim Programı',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.indigo900,
                          ),
                        ),
                        pw.Text(
                          '$studentName - ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey300),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(1),
                        1: const pw.FlexColumnWidth(1),
                        2: const pw.FlexColumnWidth(1),
                        3: const pw.FlexColumnWidth(1),
                        4: const pw.FlexColumnWidth(1),
                        5: const pw.FlexColumnWidth(1),
                        6: const pw.FlexColumnWidth(1),
                      },
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.grey200,
                          ),
                          children:
                              [
                                    'Pazartesi',
                                    'Salı',
                                    'Çarşamba',
                                    'Perşembe',
                                    'Cuma',
                                    'Cumartesi',
                                    'Pazar',
                                  ]
                                  .map(
                                    (day) => pw.Container(
                                      padding: const pw.EdgeInsets.all(8),
                                      alignment: pw.Alignment.center,
                                      child: pw.Text(
                                        day,
                                        style: pw.TextStyle(
                                          fontWeight: pw.FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                        pw.TableRow(
                          children:
                              [
                                'Pazartesi',
                                'Salı',
                                'Çarşamba',
                                'Perşembe',
                                'Cuma',
                                'Cumartesi',
                                'Pazar',
                              ].map((day) {
                                final lessons = schedule[day] ?? [];
                                return pw.Container(
                                  padding: const pw.EdgeInsets.all(5),
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.stretch,
                                    children: lessons.map((taskStr) {
                                      final lines = taskStr.split('\n');
                                      final subject = lines.isNotEmpty
                                          ? lines[0]
                                          : '';
                                      String content = lines.length > 1
                                          ? lines.sublist(1).join('\n')
                                          : '';
                                      content = content
                                          .replaceAll(
                                            RegExp(
                                              r'[^\u0000-\u007F\u00C0-\u017F\s₺]',
                                              unicode: true,
                                            ),
                                            '',
                                          )
                                          .trim();
                                      final style = _getSubjectStyle(subject);
                                      return pw.Container(
                                        margin: const pw.EdgeInsets.only(
                                          bottom: 5,
                                        ),
                                        padding: const pw.EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 4,
                                        ),
                                        decoration: pw.BoxDecoration(
                                          color: style['bg'] as PdfColor,
                                          border: pw.Border(
                                            left: pw.BorderSide(
                                              color:
                                                  style['accent'] as PdfColor,
                                              width: 3,
                                            ),
                                            top: const pw.BorderSide(
                                              color: PdfColors.grey200,
                                              width: 0.5,
                                            ),
                                            right: const pw.BorderSide(
                                              color: PdfColors.grey200,
                                              width: 0.5,
                                            ),
                                            bottom: const pw.BorderSide(
                                              color: PdfColors.grey200,
                                              width: 0.5,
                                            ),
                                          ),
                                        ),
                                        child: pw.Column(
                                          crossAxisAlignment:
                                              pw.CrossAxisAlignment.start,
                                          children: [
                                            pw.Row(
                                              children: [
                                                if (style['icon'] != null)
                                                  pw.Icon(
                                                    style['icon']
                                                        as pw.IconData,
                                                    color:
                                                        style['accent']
                                                            as PdfColor,
                                                    size: 8,
                                                    font: fontIcons,
                                                  ),
                                                pw.SizedBox(width: 2),
                                                pw.Expanded(
                                                  child: pw.Text(
                                                    _shortenSub(subject),
                                                    style: pw.TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          pw.FontWeight.bold,
                                                      color:
                                                          style['accent']
                                                              as PdfColor,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (content.isNotEmpty)
                                              pw.Text(
                                                content,
                                                style: const pw.TextStyle(
                                                  fontSize: 8,
                                                  color: PdfColors.black,
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                );
                              }).toList(),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 5),
                    // AI Footer
                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.circular(4),
                        border: pw.Border.all(color: PdfColors.grey300),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.all(3),
                            decoration: const pw.BoxDecoration(
                              color: PdfColors.purple100,
                              shape: pw.BoxShape.circle,
                            ),
                            child: pw.Text(
                              'AI',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 8,
                                color: PdfColors.purple,
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Expanded(
                            child: pw.Text(
                              aiReportContent
                                  .replaceAll(
                                    RegExp(
                                      r'[^\u0000-\u007F\u00C0-\u017F\s₺]',
                                      unicode: true,
                                    ),
                                    '',
                                  )
                                  .trim(),
                              style: pw.TextStyle(
                                fontSize: 8,
                                fontStyle: pw.FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    // Günlük Yaptıklarım
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(5),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey300),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'GÜNLÜK YAPTIKLARIM',
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.indigo900,
                              ),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Expanded(
                              child: pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.stretch,
                                children:
                                    [
                                          'Pazartesi',
                                          'Salı',
                                          'Çarşamba',
                                          'Perşembe',
                                          'Cuma',
                                          'Cumartesi',
                                          'Pazar',
                                        ]
                                        .map(
                                          (day) => pw.Expanded(
                                            child: pw.Container(
                                              decoration: pw.BoxDecoration(
                                                border: pw.Border.all(
                                                  color: PdfColors.grey200,
                                                ),
                                              ),
                                              padding: const pw.EdgeInsets.all(
                                                2,
                                              ),
                                              child: pw.Text(
                                                day,
                                                style: const pw.TextStyle(
                                                  fontSize: 7,
                                                  color: PdfColors.grey600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (logo != null)
                  pw.Center(
                    child: pw.Opacity(
                      opacity: 0.02,
                      child: pw.Image(logo, width: 220),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }
  }

  // ─── Analiz Tablosu ────────────────────────────────────────────────────────
  static pw.Widget _buildAnalysisListTable(
    List<Map<String, dynamic>> items,
    bool isPriority1,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FixedColumnWidth(25),
        1: const pw.FixedColumnWidth(80),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FixedColumnWidth(40),
        4: const pw.FixedColumnWidth(60),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: ['#', 'Ders', 'Konu', 'Başarı', 'Durum']
              .map(
                (t) => pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    t,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final double success = (item['success'] as num?)?.toDouble() ?? 0;
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: index % 2 == 0 ? PdfColors.white : PdfColors.grey50,
            ),
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  '${index + 1}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  _shortenSub(item['subject'] ?? ''),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  ((item['topic'] ?? '') as String)
                      .replaceAll(
                        RegExp(
                          r'[^\u0000-\u007F\u00C0-\u017F\s₺]',
                          unicode: true,
                        ),
                        '',
                      )
                      .trim(),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  '%${success.toStringAsFixed(0)}',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: success < 50
                        ? PdfColors.red
                        : (success < 70 ? PdfColors.orange : PdfColors.green),
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  isPriority1 ? 'Tekrar Et' : 'Pekiştir',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: isPriority1 ? PdfColors.red : PdfColors.green,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  // ─── Konu Stili ────────────────────────────────────────────────────────────
  static const Map<String, String> _trMap = {
    'İ': 'i',
    'I': 'i',
    'ı': 'i',
    'Ğ': 'g',
    'ğ': 'g',
    'Ü': 'u',
    'ü': 'u',
    'Ş': 's',
    'ş': 's',
    'Ö': 'o',
    'ö': 'o',
    'Ç': 'c',
    'ç': 'c',
  };

  static String _normalizeTurkish(String input) {
    if (input.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      buffer.write(_trMap[char] ?? char.toLowerCase());
    }
    return buffer.toString();
  }

  static Map<String, dynamic> _getSubjectStyle(String subject) {
    final sRaw = subject.trim();
    final sNorm = _normalizeTurkish(sRaw);

    if (sRaw.contains('Matematik') ||
        sNorm.contains('matematik') ||
        sNorm.contains('geometri')) {
      return {
        'bg': PdfColor.fromInt(0xFFE3F2FD),
        'accent': PdfColor.fromInt(0xFF1565C0),
        'icon': const pw.IconData(0xe96f),
      };
    }
    if (sRaw.contains('Fen') ||
        sNorm.contains('fen') ||
        sNorm.contains('fizik') ||
        sNorm.contains('kimya') ||
        sNorm.contains('biyoloji')) {
      return {
        'bg': PdfColor.fromInt(0xFFE8F5E9),
        'accent': PdfColor.fromInt(0xFF2E7D32),
        'icon': const pw.IconData(0xea46),
      };
    }
    if (sRaw.contains('Sosyal') ||
        sNorm.contains('sosyal') ||
        sNorm.contains('inkilap') ||
        sNorm.contains('tarih') ||
        sNorm.contains('cografya') ||
        sNorm.contains('felsefe')) {
      return {
        'bg': PdfColor.fromInt(0xFFFFF3E0),
        'accent': PdfColor.fromInt(0xFFEF6C00),
        'icon': const pw.IconData(0xe80b),
      };
    }
    if (sRaw.contains('Türkçe') ||
        sNorm.contains('turkce') ||
        sNorm.contains('edebiyat') ||
        sNorm.contains('okuma')) {
      return {
        'bg': PdfColor.fromInt(0xFFF3E5F5),
        'accent': PdfColor.fromInt(0xFF7B1FA2),
        'icon': const pw.IconData(0xe865),
      };
    }
    if (sRaw.contains('İngilizce') ||
        sNorm.contains('ingilizce') ||
        sNorm.contains('yabanci') ||
        sNorm.contains('dil') ||
        sNorm.contains('almanca')) {
      return {
        'bg': PdfColor.fromInt(0xFFE0F7FA),
        'accent': PdfColor.fromInt(0xFF0097A7),
        'icon': const pw.IconData(0xe894),
      };
    }
    if (sRaw.contains('Din') || sNorm.contains('din')) {
      return {
        'bg': PdfColor.fromInt(0xFFFCE4EC),
        'accent': PdfColor.fromInt(0xFFC2185B),
        'icon': const pw.IconData(0xea40),
      };
    }
    return {
      'bg': PdfColor.fromInt(0xFFFAFAFA),
      'accent': PdfColors.indigo,
      'icon': const pw.IconData(0xe896),
    };
  }
}

// ─── Premium PDF İlerleme Dialogu ─────────────────────────────────────────────
class _PdfProgressDialog extends StatefulWidget {
  final ValueNotifier<double> progress;
  final ValueNotifier<String> status;
  final VoidCallback onCancel;

  const _PdfProgressDialog({
    required this.progress,
    required this.status,
    required this.onCancel,
  });

  @override
  State<_PdfProgressDialog> createState() => _PdfProgressDialogState();
}

class _PdfProgressDialogState extends State<_PdfProgressDialog> {
  // AnimationController YOK — wall-clock zamanı baz al
  // Dart ağır iş yaparken bile saat doğru akar, bir sonraki
  // frame'de spinner doğru açıda görünür ("doğru konuma zıplar").
  late final DateTime _startTime;
  late final StreamSubscription<dynamic> _tickSub;
  double _angle = 0.0;

  static const double _rotSpeed = 2 * math.pi / 2000; // 2 saniyede tam tur

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    // 8ms tick (hedef ~120fps) — her yieldFrame sonrasında birkaç tick gelir.
    _tickSub = Stream.periodic(const Duration(milliseconds: 8)).listen((_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(_startTime).inMilliseconds;
      setState(() => _angle = (elapsed * _rotSpeed) % (2 * math.pi));
    });
  }

  @override
  void dispose() {
    _tickSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        width: 340,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFF1565C0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A237E).withValues(alpha: 0.5),
              blurRadius: 40,
              spreadRadius: 4,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              // Dekor daireler
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Positioned(
                bottom: -20,
                left: -20,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
              // İçerik
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dönen icon — wall-clock tabanlı Transform.rotate
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Dönen sweep gradient — her setState'de doğru açı
                          Transform.rotate(
                            angle: _angle,
                            child: Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: SweepGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0.0),
                                    Colors.white.withValues(alpha: 0.85),
                                  ],
                                  stops: const [0.55, 1.0],
                                ),
                              ),
                            ),
                          ),
                          // İç daire + ikon (statik)
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                            child: const Icon(
                              Icons.picture_as_pdf_rounded,
                              size: 32,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Durum mesajı: AnimatedSwitcher ile smooth
                    ValueListenableBuilder<String>(
                      valueListenable: widget.status,
                      builder: (_, val, __) => AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.25),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: anim,
                              curve: Curves.easeOut,
                            )),
                            child: child,
                          ),
                        ),
                        child: Text(
                          val,
                          key: ValueKey(val),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Glassmorphic ilerleme çubuğu
                    ValueListenableBuilder<double>(
                      valueListenable: widget.progress,
                      builder: (_, val, __) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: AnimatedFractionallySizedBox(
                                  duration: const Duration(milliseconds: 500),
                                  curve: Curves.easeInOut,
                                  widthFactor: val,
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white.withValues(alpha: 0.95),
                                          const Color(0xFF82B1FF),
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.white
                                              .withValues(alpha: 0.4),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: val > 0
                                  ? Text(
                                      '%${(val * 100).toInt()}',
                                      key: ValueKey((val * 100).toInt()),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : Text(
                                      'Lütfen bekleyiniz...',
                                      key: const ValueKey('waiting'),
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    // İptal butonu
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: widget.onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'İptal Et',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

