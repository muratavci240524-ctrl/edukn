import 'dart:typed_data';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'pdf_service.dart';

class FinancialReportService {
  static final NumberFormat _currencyFormat =
      NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('dd.MM.yyyy HH:mm');

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. PDF RAPORLARI
  // ═══════════════════════════════════════════════════════════════════════════

  /// 1.1 Genel Finans ve Tahsilat Özeti PDF
  static Future<void> printGeneralSummaryPdf({
    required String institutionName,
    required double totalContract,
    required double totalCollected,
    required double totalRemaining,
    required double totalOverdue,
    required double totalCash,
    required List<Map<String, dynamic>> cashes,
    required List<Map<String, dynamic>> plans,
    required List<Map<String, dynamic>> transactions,
    DateTimeRange? dateRange,
  }) async {
    final pdf = pw.Document();
    final font = await PdfService.getFont();
    final fontBold = await PdfService.getFontBold();

    final dateRangeStr = dateRange != null
        ? '${_dateFormat.format(dateRange.start)} - ${_dateFormat.format(dateRange.end)}'
        : 'Tüm Zamanlar (${_dateFormat.format(DateTime.now())})';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (context) => _buildPdfHeader(
          fontBold: fontBold,
          institutionName: institutionName,
          title: 'GENEL FİNANS VE TAHSİLAT ÖZET RAPORU',
          subtitle: 'Dönem Aralığı: $dateRangeStr',
        ),
        footer: (context) => _buildPdfFooter(context, font),
        build: (context) => [
          pw.SizedBox(height: 12),
          // 4'lü Metrik Kutuları
          pw.Row(
            children: [
              _buildPdfStatBox('Toplam Sözleşme', _currencyFormat.format(totalContract), PdfColors.indigo900, PdfColors.indigo50, font, fontBold),
              pw.SizedBox(width: 8),
              _buildPdfStatBox('Tahsil Edilen', _currencyFormat.format(totalCollected), PdfColors.green800, PdfColors.green50, font, fontBold),
              pw.SizedBox(width: 8),
              _buildPdfStatBox('Kalan Alacak', _currencyFormat.format(totalRemaining), PdfColors.blue800, PdfColors.blue50, font, fontBold),
              pw.SizedBox(width: 8),
              _buildPdfStatBox('Geciken Tutar', _currencyFormat.format(totalOverdue), PdfColors.red800, PdfColors.red50, font, fontBold),
            ],
          ),
          pw.SizedBox(height: 18),

          // Kasa Durumları Tablosu
          pw.Text('KASA VE BANKA HESAP DURUMU (Toplam: ${_currencyFormat.format(totalCash)})', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.indigo900)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Hesap / Kasa Adı', 'Hesap Türü', 'Güncel Bakiye'],
            data: cashes.map((k) => [
              k['name'] ?? 'Kasa',
              k['type'] == 'bank' ? 'Banka / POS' : 'Nakit Kasa',
              _currencyFormat.format((k['balance'] as num?)?.toDouble() ?? 0),
            ]).toList(),
            headerStyle: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo800),
            rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {2: pw.Alignment.centerRight},
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            cellStyle: pw.TextStyle(font: font, fontSize: 9),
          ),
          pw.SizedBox(height: 18),

          // Öğrenci Sözleşmeleri Özet Listesi
          pw.Text('ÖĞRENCİ SÖZLEŞME VE TAHSİLAT DURUMLARI (${plans.length} Kayıt)', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.indigo900)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Öğrenci', 'No', 'Sözleşme Tutarı', 'Peşinat', 'Kalan Borç', 'Durum'],
            data: plans.take(30).map((p) {
              final net = (p['netTotal'] ?? p['totalAmount'] ?? 0).toDouble();
              final dp = (p['downPayment'] ?? 0).toDouble();
              final rem = (p['_remaining'] ?? 0).toDouble();
              final hasOverdue = p['_hasOverdue'] == true;
              final status = rem <= 0 ? 'ÖDENDİ' : (hasOverdue ? 'GECİKMEDE' : 'DEVAM EDİYOR');

              return [
                p['studentName'] ?? '-',
                p['studentNo'] ?? '-',
                _currencyFormat.format(net),
                _currencyFormat.format(dp),
                _currencyFormat.format(rem),
                status,
              ];
            }).toList(),
            headerStyle: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo800),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight, 5: pw.Alignment.center},
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            cellStyle: pw.TextStyle(font: font, fontSize: 8),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Genel_Finans_Ozeti_${_dateFormat.format(DateTime.now())}.pdf',
    );
  }

  /// 1.2 Geciken Taksitler Raporu PDF
  static Future<void> printOverdueInstallmentsPdf({
    required String institutionName,
    required List<Map<String, dynamic>> overdueList,
    required double totalOverdue,
  }) async {
    final pdf = pw.Document();
    final font = await PdfService.getFont();
    final fontBold = await PdfService.getFontBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (context) => _buildPdfHeader(
          fontBold: fontBold,
          institutionName: institutionName,
          title: 'VADESİ GEÇMİŞ TAKSİTLER & BORÇLULAR LİSTESİ',
          subtitle: 'Rapor Tarihi: ${_dateTimeFormat.format(DateTime.now())}',
        ),
        footer: (context) => _buildPdfFooter(context, font),
        build: (context) => [
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.red50,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.red200),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOPLAM GECİKEN TAKSİT SAYISI: ${overdueList.length}', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.red900)),
                pw.Text('TOPLAM GECİKEN ALACAK: ${_currencyFormat.format(totalOverdue)}', style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.red900)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['#', 'Öğrenci Adı Soyadı', 'No', 'Taksit Kalemi', 'Vade Tarihi', 'Gecikme', 'Taksit Tutarı'],
            data: overdueList.asMap().entries.map((e) {
              final idx = e.key + 1;
              final item = e.value;
              final amount = (item['amount'] ?? 0).toDouble();
              final days = item['overdueDays'] ?? 0;

              return [
                '$idx',
                item['studentName'] ?? '-',
                item['studentNo'] ?? '-',
                item['installment']?['title'] ?? 'Taksit',
                item['dueDate'] ?? '-',
                '$days Gün',
                _currencyFormat.format(amount),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.red800),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {0: pw.Alignment.center, 5: pw.Alignment.center, 6: pw.Alignment.centerRight},
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            cellStyle: pw.TextStyle(font: font, fontSize: 8.5),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Geciken_Taksitler_${_dateFormat.format(DateTime.now())}.pdf',
    );
  }

  /// 1.3 Kasa & Banka Hareketleri PDF
  static Future<void> printTransactionsPdf({
    required String institutionName,
    required List<Map<String, dynamic>> transactions,
    DateTimeRange? dateRange,
  }) async {
    final pdf = pw.Document();
    final font = await PdfService.getFont();
    final fontBold = await PdfService.getFontBold();

    double totalIncome = 0;
    double totalExpense = 0;
    for (var t in transactions) {
      final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
      if (t['type'] == 'income') {
        totalIncome += amt;
      } else {
        totalExpense += amt;
      }
    }

    final dateRangeStr = dateRange != null
        ? '${_dateFormat.format(dateRange.start)} - ${_dateFormat.format(dateRange.end)}'
        : 'Tüm Kayıtlar (${_dateFormat.format(DateTime.now())})';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (context) => _buildPdfHeader(
          fontBold: fontBold,
          institutionName: institutionName,
          title: 'KASA VE BANKA HAREKET DÖKÜMÜ',
          subtitle: 'Dönem Aralığı: $dateRangeStr',
        ),
        footer: (context) => _buildPdfFooter(context, font),
        build: (context) => [
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              _buildPdfStatBox('Toplam Gelir Girişi', _currencyFormat.format(totalIncome), PdfColors.green800, PdfColors.green50, font, fontBold),
              pw.SizedBox(width: 12),
              _buildPdfStatBox('Toplam Gider Çıkışı', _currencyFormat.format(totalExpense), PdfColors.red800, PdfColors.red50, font, fontBold),
              pw.SizedBox(width: 12),
              _buildPdfStatBox('Net Fark / Bakiye', _currencyFormat.format(totalIncome - totalExpense), (totalIncome >= totalExpense) ? PdfColors.blue800 : PdfColors.orange800, PdfColors.blue50, font, fontBold),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['Tarih / Saat', 'Kasa / Hesap', 'Tür / Kategori', 'Açıklama', 'Giriş (+₺)', 'Çıkış (-₺)'],
            data: transactions.map((t) {
              final isIncome = t['type'] == 'income';
              final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
              DateTime date = DateTime.now();
              if (t['date'] != null) {
                if (t['date'] is Timestamp) date = (t['date'] as Timestamp).toDate();
              }

              return [
                _dateTimeFormat.format(date),
                t['kasaName'] ?? 'Kasa',
                t['category'] ?? (isIncome ? 'Gelir' : 'Gider'),
                t['description'] ?? '',
                isIncome ? _currencyFormat.format(amt) : '-',
                !isIncome ? _currencyFormat.format(amt) : '-',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {4: pw.Alignment.centerRight, 5: pw.Alignment.centerRight},
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            cellStyle: pw.TextStyle(font: font, fontSize: 8),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Kasa_Hareketleri_${_dateFormat.format(DateTime.now())}.pdf',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. EXCEL (.XLSX) RAPORLARI
  // ═══════════════════════════════════════════════════════════════════════════

  /// 2.1 Genel Finans Özeti Excel
  static Future<void> exportGeneralSummaryExcel({
    required String institutionName,
    required double totalContract,
    required double totalCollected,
    required double totalRemaining,
    required double totalOverdue,
    required List<Map<String, dynamic>> plans,
    required List<Map<String, dynamic>> cashes,
    required List<Map<String, dynamic>> transactions,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Finans Özeti'];
    excel.delete('Sheet1');

    // Başlık
    sheet.appendRow([TextCellValue(institutionName.toUpperCase()), TextCellValue(''), TextCellValue(''), TextCellValue('')]);
    sheet.appendRow([TextCellValue('GENEL FİNANS VE TAHSİLAT ÖZETİ'), TextCellValue(''), TextCellValue(''), TextCellValue('')]);
    sheet.appendRow([TextCellValue('Rapor Tarihi: ${_dateTimeFormat.format(DateTime.now())}'), TextCellValue(''), TextCellValue(''), TextCellValue('')]);
    sheet.appendRow([TextCellValue('')]);

    // İstatistikler
    sheet.appendRow([TextCellValue('METRİK'), TextCellValue('TUTAR (TL)')]);
    sheet.appendRow([TextCellValue('Toplam Sözleşme / Tahakkuk'), DoubleCellValue(totalContract)]);
    sheet.appendRow([TextCellValue('Toplam Tahsil Edilen'), DoubleCellValue(totalCollected)]);
    sheet.appendRow([TextCellValue('Kalan Öğrenci Borcu'), DoubleCellValue(totalRemaining)]);
    sheet.appendRow([TextCellValue('Geciken Taksit Tutarı'), DoubleCellValue(totalOverdue)]);
    sheet.appendRow([TextCellValue('')]);

    // Kasalar
    sheet.appendRow([TextCellValue('KASA VE BANKA HESAPLARI')]);
    sheet.appendRow([TextCellValue('Kasa / Hesap Adı'), TextCellValue('Tür'), TextCellValue('Bakiye (TL)')]);
    for (var k in cashes) {
      sheet.appendRow([
        TextCellValue(k['name'] ?? ''),
        TextCellValue(k['type'] == 'bank' ? 'Banka / POS' : 'Nakit Kasa'),
        DoubleCellValue((k['balance'] as num?)?.toDouble() ?? 0.0),
      ]);
    }
    sheet.appendRow([TextCellValue('')]);

    // Öğrenci Planları
    sheet.appendRow([TextCellValue('ÖĞRENCİ SÖZLEŞME VE BORÇ LİSTESİ')]);
    sheet.appendRow([
      TextCellValue('Öğrenci Adı Soyadı'),
      TextCellValue('Öğrenci No'),
      TextCellValue('Sözleşme Adı'),
      TextCellValue('Net Bedel (TL)'),
      TextCellValue('Peşinat (TL)'),
      TextCellValue('Kalan Borç (TL)'),
      TextCellValue('Durum'),
    ]);

    for (var p in plans) {
      final net = (p['netTotal'] ?? p['totalAmount'] ?? 0).toDouble();
      final dp = (p['downPayment'] ?? 0).toDouble();
      final rem = (p['_remaining'] ?? 0).toDouble();
      final hasOverdue = p['_hasOverdue'] == true;
      final status = rem <= 0 ? 'Ödendi' : (hasOverdue ? 'Gecikmede' : 'Devam Ediyor');

      sheet.appendRow([
        TextCellValue(p['studentName'] ?? ''),
        TextCellValue(p['studentNo'] ?? ''),
        TextCellValue(p['name'] ?? ''),
        DoubleCellValue(net),
        DoubleCellValue(dp),
        DoubleCellValue(rem),
        TextCellValue(status),
      ]);
    }

    final fileBytes = excel.save();
    if (fileBytes != null) {
      await FileSaver.instance.saveFile(
        name: 'Genel_Finans_Ozeti_${_dateFormat.format(DateTime.now())}.xlsx',
        bytes: Uint8List.fromList(fileBytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  /// 2.2 Geciken Taksitler Excel
  static Future<void> exportOverdueExcel({
    required String institutionName,
    required List<Map<String, dynamic>> overdueList,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Geciken Taksitler'];
    excel.delete('Sheet1');

    sheet.appendRow([TextCellValue(institutionName.toUpperCase())]);
    sheet.appendRow([TextCellValue('VADESİ GEÇMİŞ TAKSİTLER LİSTESİ')]);
    sheet.appendRow([TextCellValue('Tarih: ${_dateTimeFormat.format(DateTime.now())}')]);
    sheet.appendRow([TextCellValue('')]);

    sheet.appendRow([
      TextCellValue('#'),
      TextCellValue('Öğrenci Adı Soyadı'),
      TextCellValue('Öğrenci No'),
      TextCellValue('Taksit Başlığı'),
      TextCellValue('Vade Tarihi'),
      TextCellValue('Gecikme (Gün)'),
      TextCellValue('Taksit Tutarı (TL)'),
    ]);

    for (int i = 0; i < overdueList.length; i++) {
      final item = overdueList[i];
      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(item['studentName'] ?? ''),
        TextCellValue(item['studentNo'] ?? ''),
        TextCellValue(item['installment']?['title'] ?? 'Taksit'),
        TextCellValue(item['dueDate'] ?? ''),
        IntCellValue(item['overdueDays'] ?? 0),
        DoubleCellValue((item['amount'] ?? 0).toDouble()),
      ]);
    }

    final fileBytes = excel.save();
    if (fileBytes != null) {
      await FileSaver.instance.saveFile(
        name: 'Geciken_Taksitler_${_dateFormat.format(DateTime.now())}.xlsx',
        bytes: Uint8List.fromList(fileBytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  /// 2.3 Kasa & Hareketler Excel
  static Future<void> exportTransactionsExcel({
    required String institutionName,
    required List<Map<String, dynamic>> transactions,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Kasa Hareketleri'];
    excel.delete('Sheet1');

    sheet.appendRow([TextCellValue(institutionName.toUpperCase())]);
    sheet.appendRow([TextCellValue('KASA VE BANKA HAREKET DÖKÜMÜ')]);
    sheet.appendRow([TextCellValue('Tarih: ${_dateTimeFormat.format(DateTime.now())}')]);
    sheet.appendRow([TextCellValue('')]);

    sheet.appendRow([
      TextCellValue('İşlem Tarihi'),
      TextCellValue('Kasa / Hesap'),
      TextCellValue('Tür'),
      TextCellValue('Kategori'),
      TextCellValue('Açıklama'),
      TextCellValue('Tutar (TL)'),
      TextCellValue('Ödeme Şekli'),
      TextCellValue('Makbuz No'),
    ]);

    for (var t in transactions) {
      final isIncome = t['type'] == 'income';
      final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
      DateTime date = DateTime.now();
      if (t['date'] != null && t['date'] is Timestamp) {
        date = (t['date'] as Timestamp).toDate();
      }

      sheet.appendRow([
        TextCellValue(_dateTimeFormat.format(date)),
        TextCellValue(t['kasaName'] ?? ''),
        TextCellValue(isIncome ? 'Gelir (+)' : 'Gider (-)'),
        TextCellValue(t['category'] ?? ''),
        TextCellValue(t['description'] ?? ''),
        DoubleCellValue(isIncome ? amt : -amt),
        TextCellValue(t['paymentMethod'] ?? '-'),
        TextCellValue(t['receiptNo'] ?? '-'),
      ]);
    }

    final fileBytes = excel.save();
    if (fileBytes != null) {
      await FileSaver.instance.saveFile(
        name: 'Kasa_Hareketleri_${_dateFormat.format(DateTime.now())}.xlsx',
        bytes: Uint8List.fromList(fileBytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  // ─── YARDIMCI PDF WIDGETLARI ───────────────────────────────────────────────

  static pw.Widget _buildPdfHeader({
    required pw.Font fontBold,
    required String institutionName,
    required String title,
    required String subtitle,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(institutionName.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.indigo900)),
            pw.Text('eduKN Finans Yönetimi', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(title, style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.black)),
        pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 1, color: PdfColors.indigo900),
      ],
    );
  }

  static pw.Widget _buildPdfFooter(pw.Context context, pw.Font font) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('eduKN Kurumsal Okul Yönetim Sistemi', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
          pw.Text('Sayfa ${context.pageNumber} / ${context.pagesCount}', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600)),
        ],
      ),
    );
  }

  static pw.Widget _buildPdfStatBox(
    String title,
    String value,
    PdfColor textColor,
    PdfColor bgColor,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: bgColor,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: textColor, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 11, color: textColor)),
          ],
        ),
      ),
    );
  }
}
