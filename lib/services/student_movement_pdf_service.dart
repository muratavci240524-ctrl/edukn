import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/school/student_movement_model.dart';
import 'pdf_service.dart';

class StudentMovementPdfService {
  static final PdfColor _navy = PdfColor.fromHex('#0F172A');
  static final PdfColor _slate = PdfColor.fromHex('#475569');
  static final PdfColor _border = PdfColor.fromHex('#CBD5E1');
  static final PdfColor _lightBg = PdfColor.fromHex('#F8FAFC');

  static String _trUpper(String s) =>
      s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  static PdfColor _accentForType(StudentMovementType type) {
    switch (type) {
      case StudentMovementType.lateSlip:
        return PdfColor.fromHex('#D97706');
      case StudentMovementType.exitPermission:
        return PdfColor.fromHex('#0284C7');
      case StudentMovementType.earlyPickup:
        return PdfColor.fromHex('#0D9488');
      case StudentMovementType.infirmary:
        return PdfColor.fromHex('#E11D48');
      case StudentMovementType.interview:
        return PdfColor.fromHex('#7C3AED');
    }
  }

  /// Tekil Geç Kağıdı / Çıkış İzin Pusulası / Revir Sevk Kağıdı / Görüşme Pusulası üretir
  static Future<Uint8List> generateSlipPdf({
    required StudentMovementRecord record,
    required String schoolName,
  }) async {
    return generateBatchSlipsPdf(records: [record], schoolName: schoolName);
  }

  /// Tekli veya Çoklu Öğrenci Pusulası Üretir (Çoklu seçimde sayfa başına 2 kesimli pusula basar)
  static Future<Uint8List> generateBatchSlipsPdf({
    required List<StudentMovementRecord> records,
    required String schoolName,
  }) async {
    final fonts = await Future.wait([
      PdfService.getFont(),
      PdfService.getFontBold(),
    ]);
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts[0], bold: fonts[1]),
    );

    if (records.isEmpty) return pdf.save();

    final bool compact = records.length > 1;
    for (int i = 0; i < records.length; i += 2) {
      final first = records[i];
      final second = (i + 1 < records.length) ? records[i + 1] : null;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(compact ? 24 : 32),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildSlipBox(
                record: first,
                schoolName: schoolName,
                compact: compact,
              ),
              if (second != null) ...[
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 12),
                  child: pw.Row(
                    children: [
                      pw.Text(
                        '✂',
                        style: pw.TextStyle(fontSize: 10, color: _slate),
                      ),
                      pw.SizedBox(width: 6),
                      pw.Expanded(
                        child: pw.Container(
                          height: 0.7,
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              bottom: pw.BorderSide(
                                color: _border,
                                width: 0.8,
                                style: pw.BorderStyle.dashed,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildSlipBox(
                  record: second,
                  schoolName: schoolName,
                  compact: compact,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return pdf.save();
  }

  static pw.Widget _buildSlipBox({
    required StudentMovementRecord record,
    required String schoolName,
    required bool compact,
  }) {
    final accent = _accentForType(record.type);
    final timeStr = DateFormat('dd.MM.yyyy • HH:mm').format(record.createdAt);
    final qrData =
        'EDUKN-PUSULA|${record.type.firestoreKey}|${record.id}|${record.studentNo}|${record.dateStr}';

    final detailRows = <MapEntry<String, String>>[
      MapEntry(
        'Öğrenci Adı Soyadı / No',
        '${record.studentName}${record.studentNo.isNotEmpty ? " (No: ${record.studentNo})" : ""}',
      ),
      MapEntry('Sınıf / Şube', record.className),
      MapEntry(
        'İşlem Tarihi & Saati',
        '${DateFormat('dd.MM.yyyy').format(record.createdAt)} • Saat ${DateFormat('HH:mm').format(record.createdAt)}',
      ),
      MapEntry(
        'İlgili Ders Saati',
        '${record.lessonHour}. Ders${record.lessonTimeRangeLabel.isNotEmpty ? " (${record.lessonTimeRangeLabel})" : ""}${record.lessonName.isNotEmpty && record.lessonName != "${record.lessonHour}. Ders" ? " — ${record.lessonName}" : ""}',
      ),
      if (record.type == StudentMovementType.lateSlip) ...[
        if (record.targetTeacherNames.isNotEmpty)
          MapEntry('Ders Öğretmeni', record.targetTeacherNames.join(', ')),
        MapEntry(
          'Geç Kalma Nedeni',
          record.reason.isNotEmpty ? record.reason : 'Mazeret bildirildi',
        ),
      ],
      if (record.type == StudentMovementType.exitPermission ||
          record.type == StudentMovementType.earlyPickup) ...[
        MapEntry(
          record.type == StudentMovementType.earlyPickup
              ? 'Erken Alma Şekli'
              : 'Çıkış Şekli',
          record.exitMode.isNotEmpty
              ? record.exitMode
              : 'Veli Eşliğinde Erken Alma',
        ),
        if (record.receiverName.isNotEmpty)
          MapEntry(
            'Teslim Alan Veli / Yakın',
            '${record.receiverName}${record.receiverRelation.isNotEmpty ? " (${record.receiverRelation})" : ""}${record.receiverPhone.isNotEmpty ? " • ${record.receiverPhone}" : ""}',
          ),
        if (record.vehiclePlate.isNotEmpty)
          MapEntry('Araç Plaka / Kapı Bilgisi', record.vehiclePlate),
        MapEntry('Planlanan Alış / Çıkış Saati', record.plannedExitTime),
        if (record.parentArrivedAt != null)
          MapEntry(
            'Veli Okula Geliş Saati',
            DateFormat('HH:mm').format(record.parentArrivedAt!),
          ),
        MapEntry('Erken Alma / İzin Nedeni', record.reason),
        if (record.gateApprovedAt != null)
          MapEntry(
            'Güvenlik Kapı Teslim Onayı',
            '${DateFormat("HH:mm").format(record.gateApprovedAt!)} • ${record.gateApprovedByName}',
          ),
      ],
      if (record.type == StudentMovementType.infirmary) ...[
        MapEntry('Şikayet / Sevk Nedeni', record.reason),
        MapEntry('Öncelik Durumu', record.urgency),
        if (record.bloodType.isNotEmpty)
          MapEntry('Kan Grubu', record.bloodType),
        if (record.infirmaryTreatment.isNotEmpty)
          MapEntry('Yapılan Sağlık İşlemi', record.infirmaryTreatment),
        if (record.infirmaryOutcome.isNotEmpty)
          MapEntry('Sonuç / Karar', record.infirmaryOutcome),
      ],
      if (record.type == StudentMovementType.interview) ...[
        MapEntry('Görüşme Birimi', record.interviewUnit),
        MapEntry('Görüşmeyi Yapan', record.interviewerName),
        MapEntry(
          'Kapsanan Ders Saat(ler)i',
          record.coveredLessonHours.isNotEmpty
              ? '${record.coveredLessonHours.map((h) => "$h.").join(", ")} Ders (Yoklamada İzinli Korumalı)'
              : '${record.lessonHour}. Ders',
        ),
        if (record.reason.isNotEmpty)
          MapEntry('Görüşme Konusu / Not', record.reason),
      ],
      if (record.notes.isNotEmpty) MapEntry('Ek Açıklama', record.notes),
    ];

    String officialInstruction;
    switch (record.type) {
      case StudentMovementType.lateSlip:
        officialInstruction =
            'Yukarıda kimlik bilgileri yer alan öğrencinin okula geç geliş mazereti idaremizce incelenmiş olup ilgili ders öğretmenine sistem üzerinden bildirim gönderilmiştir. Öğrencinin derse kabul edilmesi hususunda bilgilerinizi rica ederim.';
        break;
      case StudentMovementType.exitPermission:
        officialInstruction =
            'Yukarıda kimlik bilgileri yazılı öğrencinin belirtilen mazeret kapsamında okuldan çıkış yapması uygun görülmüştür. Güvenlik birimi tarafından kapı çıkış kontrolü ve sistem onayı yapıldıktan sonra öğrenci kalan derslerde otomatik izinli sayılacaktır.';
        break;
      case StudentMovementType.earlyPickup:
        officialInstruction =
            'Yukarıda kimlik bilgileri yazılı öğrencinin velisi tarafından erken alma talebi oluşturulmuş olup dersi olan öğretmene ve güvenlik birimine bilgi verilmiştir. Güvenlik kapı teslim onayının ardından öğrenci kalan derslerde otomatik izinli sayılacaktır.';
        break;
      case StudentMovementType.infirmary:
        officialInstruction =
            'Yukarıda kimlik bilgileri yazılı öğrenci sağlık şikayeti nedeniyle okul revirine sevk edilmiştir. Revir görevlisi tarafından yapılan müdahalenin Sağlık İşlemleri ekranındaki açık dosyaya işlenerek tamamlanması rica olunur.';
        break;
      case StudentMovementType.interview:
        officialInstruction =
            'Yukarıda kimlik bilgileri yazılı öğrenci belirtilen ders saatinde birimimizde resmi görüşmede bulunduğundan derse katılamamıştır. Yoklamada yok yazılmaması hususunda bilgilerinize sunulur.';
        break;
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: accent, width: 1.4),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Üst Başlık Bandı
          pw.Container(
            padding: pw.EdgeInsets.symmetric(
              horizontal: 16,
              vertical: compact ? 9 : 12,
            ),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: const pw.BorderRadius.vertical(
                top: pw.Radius.circular(10.5),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _trUpper(schoolName),
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: compact ? 9 : 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        _trUpper(record.type.fullTitle),
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: compact ? 12 : 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Text(
                    record.type.shortLabel,
                    style: pw.TextStyle(
                      color: accent,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: compact ? 10 : 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // İçerik Gövdesi
          pw.Padding(
            padding: pw.EdgeInsets.all(compact ? 12 : 16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: _border, width: 0.7),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(6),
                          ),
                        ),
                        child: pw.Table(
                          border: pw.TableBorder.symmetric(
                            inside: pw.BorderSide(color: _border, width: 0.5),
                          ),
                          columnWidths: const {
                            0: pw.FixedColumnWidth(134),
                            1: pw.FlexColumnWidth(),
                          },
                          children: detailRows
                              .map(
                                (r) => pw.TableRow(
                                  children: [
                                    pw.Container(
                                      color: _lightBg,
                                      padding: pw.EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: compact ? 4 : 5.5,
                                      ),
                                      child: pw.Text(
                                        r.key,
                                        style: pw.TextStyle(
                                          fontSize: compact ? 8.2 : 8.8,
                                          fontWeight: pw.FontWeight.bold,
                                          color: _navy,
                                        ),
                                      ),
                                    ),
                                    pw.Padding(
                                      padding: pw.EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: compact ? 4 : 5.5,
                                      ),
                                      child: pw.Text(
                                        r.value,
                                        style: pw.TextStyle(
                                          fontSize: compact ? 8.4 : 9,
                                          color: _navy,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Column(
                      children: [
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: qrData,
                          width: compact ? 58 : 68,
                          height: compact ? 58 : 68,
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Dijital Doğrulama',
                          style: pw.TextStyle(fontSize: 6.8, color: _slate),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: compact ? 8 : 12),
                pw.Text(
                  officialInstruction,
                  style: pw.TextStyle(
                    fontSize: compact ? 8.4 : 9.2,
                    color: _navy,
                    lineSpacing: compact ? 1.8 : 2.5,
                  ),
                  textAlign: pw.TextAlign.justify,
                ),
                pw.SizedBox(height: compact ? 12 : 18),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          (record.type == StudentMovementType.exitPermission ||
                                  record.type ==
                                      StudentMovementType.earlyPickup)
                              ? 'Güvenlik / Veli Teslim Onayı'
                              : (record.type == StudentMovementType.infirmary
                                    ? 'Revir / Sağlık Görevlisi'
                                    : 'Ders Öğretmeni Bilgi / İmza'),
                          style: pw.TextStyle(
                            fontSize: 8.2,
                            fontWeight: pw.FontWeight.bold,
                            color: _slate,
                          ),
                        ),
                        pw.SizedBox(height: compact ? 16 : 22),
                        pw.Text(
                          record.gateApprovedByName.isNotEmpty
                              ? record.gateApprovedByName
                              : (record.handledByInfirmaryName.isNotEmpty
                                    ? record.handledByInfirmaryName
                                    : '................................'),
                          style: pw.TextStyle(
                            fontSize: 8.8,
                            fontWeight: pw.FontWeight.bold,
                            color: _navy,
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'Düzenleyen Yetkili',
                          style: pw.TextStyle(
                            fontSize: 8.2,
                            fontWeight: pw.FontWeight.bold,
                            color: _slate,
                          ),
                        ),
                        pw.SizedBox(height: compact ? 16 : 22),
                        pw.Text(
                          record.createdByName,
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: _navy,
                          ),
                        ),
                        pw.Text(
                          'İmza / Mühür',
                          style: pw.TextStyle(fontSize: 7.2, color: _slate),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Günlük Öğrenci Hareket İzleme Çizelgesi (Geç - İzin - Revir - Görüşme Toplu Raporu)
  static Future<Uint8List> generateDailyReportPdf({
    required List<StudentMovementRecord> records,
    required String schoolName,
    required String dateLabel,
  }) async {
    final fonts = await Future.wait([
      PdfService.getFont(),
      PdfService.getFontBold(),
    ]);
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts[0], bold: fonts[1]),
    );

    final rows = List.generate(records.length, (i) {
      final r = records[i];
      return [
        '${i + 1}',
        DateFormat('HH:mm').format(r.createdAt),
        r.type.shortLabel,
        '${r.studentName}${r.studentNo.isNotEmpty ? " (${r.studentNo})" : ""}',
        r.className,
        '${r.lessonHour}. Ders',
        r.reason.isNotEmpty ? r.reason : r.interviewUnit,
        r.liveLocationDescription,
        r.createdByName,
      ];
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(26),
        build: (_) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '${_trUpper(schoolName)} — GÜNLÜK ÖĞRENCİ HAREKET İZLEME RAPORU',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: _navy,
                ),
              ),
              pw.Text(
                'Tarih: $dateLabel  •  Toplam Kayıt: ${records.length}',
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _slate,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const [
              '#',
              'Saat',
              'Tür',
              'Öğrenci',
              'Şube',
              'Ders',
              'Neden / Konu',
              'Son Durum / Konum',
              'Düzenleyen',
            ],
            data: rows,
            border: pw.TableBorder.all(color: _border, width: 0.6),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#1E293B'),
            ),
            cellStyle: pw.TextStyle(fontSize: 8.2, color: _navy),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 4.5,
            ),
            columnWidths: const {
              0: pw.FixedColumnWidth(22),
              1: pw.FixedColumnWidth(36),
              2: pw.FixedColumnWidth(46),
              3: pw.FlexColumnWidth(1.8),
              4: pw.FixedColumnWidth(42),
              5: pw.FixedColumnWidth(42),
              6: pw.FlexColumnWidth(1.8),
              7: pw.FlexColumnWidth(2.1),
              8: pw.FlexColumnWidth(1.3),
            },
          ),
        ],
      ),
    );

    return pdf.save();
  }
}
