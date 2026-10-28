import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/school/butterfly_exam_model.dart';
import '../models/school/seating_plan_model.dart';

/// Kelebek Sınav Sistemi PDF Servisi (Krokiler, Kapı Listeleri, Yoklama Listeleri, Genel Alfabetik Liste)
class ButterflyPdfService {
  /// ===========================================================================
  /// 0. YOKLAMA RAPORU (SALON ÖZETİ + GELMEYEN ÖĞRENCİLER)
  /// ===========================================================================
  static Future<Uint8List> generateAttendanceReportPdf({
    required ExamDistribution distribution,
    required Map<String, Map<String, bool>> attendance,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    Map<String, bool> getMapForRoom(ExamRoom r, int i) {
      final base1 = r.id;
      final base2 = r.classroomId;
      final base3 = 'room_$i';
      final candidates = [base1, base2, base3].where((s) => s.isNotEmpty).toList();
      for (final c in candidates) {
        if (attendance.containsKey(c)) {
          return attendance[c]!;
        }
      }
      final merged = <String, bool>{};
      for (final entry in attendance.entries) {
        for (final c in candidates) {
          if (entry.key == c || entry.key.startsWith('${c}_s')) {
            merged.addAll(entry.value);
            break;
          }
        }
      }
      return merged;
    }

    final rows = <Map<String, dynamic>>[];
    final absentees = <Map<String, dynamic>>[];
    var total = 0, present = 0, absent = 0;

    for (int i = 0; i < distribution.rooms.length; i++) {
      final room = distribution.rooms[i];
      final map = getMapForRoom(room, i);
      final seats = room.seats.where((s) => s.student != null).toList()
        ..sort((a, b) => a.seatNumber.compareTo(b.seatNumber));
      var p = 0, a = 0;
      for (final s in seats) {
        final v = map[s.student!.id];
        if (v == true) p++;
        if (v == false) {
          a++;
          absentees.add({'room': room.classroomName, 'seat': s.seatNumber, 'student': s.student!});
        }
      }
      rows.add({'room': room, 'total': seats.length, 'present': p, 'absent': a});
      total += seats.length;
      present += p;
      absent += a;
    }
    final pending = total - present - absent;
    final dateStr = DateFormat('dd.MM.yyyy').format(distribution.examDate);
    final examTitle = _getExamTitle(distribution);

    pw.Widget kpi(String label, int value, PdfColor c) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 8),
            margin: const pw.EdgeInsets.symmetric(horizontal: 3),
            decoration: pw.BoxDecoration(
              color: _tint(c, 0.12),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(children: [
              pw.Text('$value', style: pw.TextStyle(font: fontBold, fontSize: 20, color: c)),
              pw.Text(label, style: pw.TextStyle(font: fontBold, fontSize: 8, color: c)),
            ]),
          ),
        );

    pw.Widget cell(String t, {bool bold = false, pw.TextAlign align = pw.TextAlign.left, PdfColor? color}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text(t,
              textAlign: align,
              style: pw.TextStyle(font: bold ? fontBold : font, fontSize: 9, color: color ?? PdfColors.grey900)),
        );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}  •  ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: pw.BoxDecoration(
              gradient: const pw.LinearGradient(colors: [PdfColors.indigo900, PdfColors.indigo600]),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('SINAV YOKLAMA RAPORU',
                    style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.amber300, letterSpacing: 1.2)),
                pw.SizedBox(height: 3),
                pw.Text('${distribution.schoolTypeName} • $examTitle',
                    style: pw.TextStyle(font: fontBold, fontSize: 15, color: PdfColors.white)),
                pw.SizedBox(height: 3),
                pw.Text('Tarih: $dateStr   •   Saat: ${distribution.examTime}',
                    style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.indigo100)),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Row(children: [
            kpi('TOPLAM', total, PdfColors.indigo700),
            kpi('GELDİ', present, PdfColors.green700),
            kpi('GELMEDİ', absent, PdfColors.red600),
            kpi('İŞARETLENMEDİ', pending, PdfColors.orange700),
          ]),
          pw.SizedBox(height: 12),
          pw.Text('Salon Bazlı Özet', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.indigo900)),
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.2),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(1),
              3: pw.FlexColumnWidth(1),
              4: pw.FlexColumnWidth(1),
              5: pw.FlexColumnWidth(1.3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.indigo100),
                children: [
                  cell('SALON', bold: true),
                  cell('GÖZETMEN', bold: true),
                  cell('MEVCUT', bold: true, align: pw.TextAlign.center),
                  cell('GELDİ', bold: true, align: pw.TextAlign.center),
                  cell('GELMEDİ', bold: true, align: pw.TextAlign.center),
                  cell('İŞARETLENMEDİ', bold: true, align: pw.TextAlign.center),
                ],
              ),
              for (int i = 0; i < rows.length; i++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: i.isOdd ? PdfColors.grey50 : PdfColors.white),
                  children: [
                    cell((rows[i]['room'] as ExamRoom).classroomName, bold: true),
                    cell(((rows[i]['room'] as ExamRoom).supervisorName ?? '').trim() == 'Gözetmen Öğretmen'
                        ? '-'
                        : (((rows[i]['room'] as ExamRoom).supervisorName ?? '').trim().isEmpty
                            ? '-'
                            : (rows[i]['room'] as ExamRoom).supervisorName!.trim())),
                    cell('${rows[i]['total']}', align: pw.TextAlign.center),
                    cell('${rows[i]['present']}', align: pw.TextAlign.center, color: PdfColors.green800, bold: true),
                    cell('${rows[i]['absent']}', align: pw.TextAlign.center, color: PdfColors.red700, bold: true),
                    cell('${(rows[i]['total'] as int) - (rows[i]['present'] as int) - (rows[i]['absent'] as int)}',
                        align: pw.TextAlign.center, color: PdfColors.orange800),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text('Gelmeyen Öğrenciler (${absentees.length})',
              style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.red800)),
          pw.SizedBox(height: 4),
          if (absentees.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.green50,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text('Gelmeyen öğrenci bulunmuyor.',
                  style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.green800)),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
              columnWidths: const {
                0: pw.FixedColumnWidth(26),
                1: pw.FlexColumnWidth(1.1),
                2: pw.FlexColumnWidth(0.8),
                3: pw.FlexColumnWidth(3.4),
                4: pw.FlexColumnWidth(1),
                5: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.red100),
                  children: [
                    cell('#', bold: true, align: pw.TextAlign.center),
                    cell('SALON', bold: true),
                    cell('SIRA', bold: true, align: pw.TextAlign.center),
                    cell('ÖĞRENCİ ADI SOYADI', bold: true),
                    cell('ŞUBE', bold: true, align: pw.TextAlign.center),
                    cell('NO', bold: true, align: pw.TextAlign.center),
                  ],
                ),
                for (int i = 0; i < absentees.length; i++)
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: i.isOdd ? PdfColors.grey50 : PdfColors.white),
                    children: [
                      cell('${i + 1}', align: pw.TextAlign.center),
                      cell(absentees[i]['room'] as String, bold: true),
                      cell('${absentees[i]['seat']}', align: pw.TextAlign.center),
                      cell((absentees[i]['student'] as ExamStudent).fullName, bold: true),
                      cell((absentees[i]['student'] as ExamStudent).className, align: pw.TextAlign.center),
                      cell((absentees[i]['student'] as ExamStudent).studentNumber, align: pw.TextAlign.center),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Sınav başlığını kullanıcı tercihine göre döndürür
  static String _getExamTitle(ExamDistribution distribution) {
    if (!distribution.showExamTitleOnPdf) {
      return 'Deneme Sınavı';
    }
    return distribution.title.isNotEmpty ? distribution.title : 'Deneme Sınavı';
  }

  /// ===========================================================================
  /// 1. KAPI LİSTESİ PDF (SIRA NUMARASINA GÖRE SIRALI - A4 PORTRAIT)
  /// ===========================================================================
  static Future<Uint8List> generateGateListPdf({
    required ExamDistribution distribution,
    required ExamRoom room,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    // Koltuk / Sıra Numarasına Göre (1, 2, 3... 24) Sıralı Liste
    final occupiedSeats = room.seats.where((s) => s.student != null).toList();
    occupiedSeats.sort((a, b) => a.seatNumber.compareTo(b.seatNumber));

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildGateListHeader(distribution, room, font, fontBold),
              pw.SizedBox(height: 12),
              _buildRoomInfoBanner(distribution, room, font, fontBold),
              pw.SizedBox(height: 10),
              _buildGateListTable(occupiedSeats, font, fontBold),
              pw.Spacer(), // Alt bilgiyi sayfanın en altına sabitler
              _buildGateListFooter(distribution, occupiedSeats.length, font, fontBold),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Tüm Salonların Kapı Listelerini Tek Bir PDF Dosyasında Birleştirme
  static Future<Uint8List> generateAllGateListsPdf({
    required ExamDistribution distribution,
    pw.Document? into,
  }) async {
    final pdf = into ?? pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    for (final room in distribution.rooms) {
      final occupiedSeats = room.seats.where((s) => s.student != null).toList();
      occupiedSeats.sort((a, b) => a.seatNumber.compareTo(b.seatNumber));

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildGateListHeader(distribution, room, font, fontBold),
                pw.SizedBox(height: 12),
                _buildRoomInfoBanner(distribution, room, font, fontBold),
                pw.SizedBox(height: 10),
                _buildGateListTable(occupiedSeats, font, fontBold),
                pw.Spacer(), // Alt bilgiyi sayfanın en altına sabitler
                _buildGateListFooter(distribution, occupiedSeats.length, font, fontBold),
              ],
            );
          },
        ),
      );
    }

    return into != null ? Uint8List(0) : pdf.save();
  }

  /// ===========================================================================
  /// 2. SALON SINAV YOKLAMA LİSTESİ (SIRA NUMARASINA GÖRE SIRALI - A4)
  /// ===========================================================================
  static Future<Uint8List> generateAttendanceListPdf({
    required ExamDistribution distribution,
    required ExamRoom room,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    // Koltuk / Sıra Numarasına Göre (1, 2, 3... 24) Sıralı Liste
    final occupiedSeats = room.seats.where((s) => s.student != null).toList();
    occupiedSeats.sort((a, b) => a.seatNumber.compareTo(b.seatNumber));

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildAttendanceHeader(distribution, room, font, fontBold),
              pw.SizedBox(height: 12),
              _buildRoomInfoBanner(distribution, room, font, fontBold, isAttendance: true),
              pw.SizedBox(height: 10),
              _buildAttendanceTable(occupiedSeats, font, fontBold),
              pw.Spacer(), // Alt bilgiyi sayfanın en altına sabitler
              _buildAttendanceFooter(distribution, room, occupiedSeats.length, font, fontBold),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Tüm Salonların Yoklama Listelerini Tek Bir PDF Dosyasında Birleştirme
  static Future<Uint8List> generateAllAttendanceListsPdf({
    required ExamDistribution distribution,
    pw.Document? into,
  }) async {
    final pdf = into ?? pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    for (final room in distribution.rooms) {
      final occupiedSeats = room.seats.where((s) => s.student != null).toList();
      occupiedSeats.sort((a, b) => a.seatNumber.compareTo(b.seatNumber));

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildAttendanceHeader(distribution, room, font, fontBold),
                pw.SizedBox(height: 12),
                _buildRoomInfoBanner(distribution, room, font, fontBold, isAttendance: true),
                pw.SizedBox(height: 10),
                _buildAttendanceTable(occupiedSeats, font, fontBold),
                pw.Spacer(), // Alt bilgiyi sayfanın en altına sabitler
                _buildAttendanceFooter(distribution, room, occupiedSeats.length, font, fontBold),
              ],
            );
          },
        ),
      );
    }

    return into != null ? Uint8List(0) : pdf.save();
  }

  /// ===========================================================================
  /// 3. GENEL ALFABETİK ÖĞRENCİ YERLEŞİM LİSTESİ (TÜM OKUL / OTURUM - A-Z)
  /// ===========================================================================
  static Future<Uint8List> generateMasterAlphabeticalListPdf({
    required ExamDistribution distribution,
    pw.Document? into,
  }) async {
    final pdf = into ?? pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final List<Map<String, dynamic>> allSeated = [];

    for (final room in distribution.rooms) {
      for (final seat in room.seats) {
        if (seat.student != null) {
          allSeated.add({
            'student': seat.student!,
            'roomName': room.classroomName,
            'seatNumber': seat.seatNumber,
          });
        }
      }
    }

    allSeated.sort((a, b) {
      final sA = (a['student'] as ExamStudent).fullName.toLowerCase();
      final sB = (b['student'] as ExamStudent).fullName.toLowerCase();
      return sA.compareTo(sB);
    });

    // Satırlar sayfa dolana kadar akar; taşan satırlar bir sonraki sayfada devam eder.
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (ctx.pageNumber == 1) ...[
              _buildMasterHeader(distribution, font, fontBold, allSeated.length),
              pw.SizedBox(height: 10),
            ],
            _buildMasterTable(const [], 0, font, fontBold),
          ],
        ),
        footer: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Toplam Sınava Giren Öğrenci: ${allSeated.length}',
                style: pw.TextStyle(font: fontBold, fontSize: 8.5),
              ),
              pw.Text(
                'Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}',
                style: pw.TextStyle(font: font, fontSize: 8),
              ),
            ],
          ),
        ),
        build: (ctx) => [
          for (int i = 0; i < allSeated.length; i++)
            _buildMasterTable([allSeated[i]], i, font, fontBold, includeHeader: false),
        ],
      ),
    );

    return into != null ? Uint8List(0) : pdf.save();
  }

  /// ===========================================================================
  /// 4. GÖZETMEN SINAV KROKİSİ PDF (ÖĞRENCİ İMZASIZ - TEMİZ DÜZEN - A4)
  /// ===========================================================================
  static Future<Uint8List> generateSupervisorSeatingPlanPdf({
    required ExamDistribution distribution,
    required ExamRoom room,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final layout = room.layoutSnapshot;
    final isLandscape = layout.cols >= 4 || layout.rows <= 3;
    final pageFormat = isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _buildSupervisorHeader(distribution, room, font, fontBold),
              pw.SizedBox(height: 8),
              _buildTeacherBoard(fontBold),
              pw.SizedBox(height: 10),
              pw.Expanded(
                child: _buildSupervisorGrid(room, font, fontBold),
              ),
              pw.SizedBox(height: 8),
              _buildSupervisorFooter(distribution, room, font, fontBold),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Tüm Salonların Gözetmen Krokilerini Tek Bir PDF Dosyasında Birleştirme
  static Future<Uint8List> generateAllSupervisorPlansPdf({
    required ExamDistribution distribution,
    pw.Document? into,
  }) async {
    final pdf = into ?? pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    for (final room in distribution.rooms) {
      final layout = room.layoutSnapshot;
      final isLandscape = layout.cols >= 4 || layout.rows <= 3;
      final pageFormat = isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildSupervisorHeader(distribution, room, font, fontBold),
                pw.SizedBox(height: 8),
                _buildTeacherBoard(fontBold),
                pw.SizedBox(height: 10),
                pw.Expanded(
                  child: _buildSupervisorGrid(room, font, fontBold),
                ),
                pw.SizedBox(height: 8),
                _buildSupervisorFooter(distribution, room, font, fontBold),
              ],
            );
          },
        ),
      );
    }

    return into != null ? Uint8List(0) : pdf.save();
  }

  /// ===========================================================================
  /// 5. SINAV DAVRANIŞLARI GÖZLEM FORMU (A4 YATAY - SALON BAŞINA 25 ÖĞRENCİ)
  /// ===========================================================================
  static const List<String> _observationBehaviors = [
    'Süreyi yetiştiremiyor.',
    'Kopyaya  yelteniyor.',
    'Dikkati çabuk dağılıyor.',
    'Kodlamayı sona bırakıyor.',
    'Blok kodlama yapıyor.',
    'Hatalı kodlama(taşırarak,silik vb.)yapıyor.',
    'Aşırı endişeli, telaşlı bir hali var.',
    'Sınav sırasında fiziksel rahatsızlıklar yaşıyor.(Baş ağrısı, mide bulantısı vb.)',
    'Etrafla çok ilgileniyor.',
    'Sınav gereçleri eksik.',
    'Dalgın, düşünceli bir hali var.',
    'İşlem yapmıyor.',
    'Sınavı erken bitiriyor.',
    'Sık sık süreyi soruyor.',
  ];

  /// ===========================================================================
  /// 6. TÜM SINAV PAKETİ (TEK PDF): alfabetik liste, kapı, yoklama, kroki, gözlem formu
  /// ===========================================================================
  static Future<Uint8List> generateFullExamPackagePdf({
    required ExamDistribution distribution,
  }) async {
    final pdf = pw.Document();
    await generateMasterAlphabeticalListPdf(distribution: distribution, into: pdf);
    await generateAllGateListsPdf(distribution: distribution, into: pdf);
    await generateAllAttendanceListsPdf(distribution: distribution, into: pdf);
    await generateAllSupervisorPlansPdf(distribution: distribution, into: pdf);
    await generateAllObservationFormsPdf(distribution: distribution, into: pdf);
    return pdf.save();
  }

  static Future<Uint8List> generateObservationFormPdf({
    required ExamDistribution distribution,
    required ExamRoom room,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    _addObservationPages(pdf, distribution, room, font, fontBold);
    return pdf.save();
  }

  static Future<Uint8List> generateAllObservationFormsPdf({
    required ExamDistribution distribution,
    pw.Document? into,
  }) async {
    final pdf = into ?? pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    for (final room in distribution.rooms) {
      _addObservationPages(pdf, distribution, room, font, fontBold);
    }
    return into != null ? Uint8List(0) : pdf.save();
  }

  static PdfColor _tint(PdfColor c, double t) =>
      PdfColor(1 - (1 - c.red) * t, 1 - (1 - c.green) * t, 1 - (1 - c.blue) * t);

  static const List<PdfColor> _obsColors = [
    PdfColors.red600,
    PdfColors.deepOrange600,
    PdfColors.amber800,
    PdfColors.green700,
    PdfColors.teal600,
    PdfColors.cyan700,
    PdfColors.blue600,
    PdfColors.indigo600,
    PdfColors.purple600,
    PdfColors.pink600,
    PdfColors.brown500,
    PdfColors.blueGrey600,
    PdfColors.lightGreen800,
    PdfColors.deepPurple500,
  ];

  static void _addObservationPages(
    pw.Document pdf,
    ExamDistribution distribution,
    ExamRoom room,
    pw.Font font,
    pw.Font fontBold,
  ) {
    const rowsPerPage = 25;
    const headerH = 124.0;
    const rowH = 14.2;
    final seated = room.seats.where((s) => s.student != null).toList()
      ..sort((a, b) => a.seatNumber.compareTo(b.seatNumber));
    final pageCount = (seated.length / rowsPerPage).ceil().clamp(1, 99);
    final dateStr = DateFormat('dd.MM.yyyy').format(distribution.examDate);
    final examTitle = _getExamTitle(distribution);
    const navy = PdfColors.indigo900;

    pw.Widget cell(pw.Widget child, {double? h, pw.Alignment align = pw.Alignment.center}) => pw.Container(
          height: h,
          alignment: align,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4),
          child: child,
        );

    for (int p = 0; p < pageCount; p++) {
      final chunk = seated.skip(p * rowsPerPage).take(rowsPerPage).toList();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          build: (ctx) {
            return pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: navy, width: 1.2),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.ClipRRect(
                horizontalRadius: 6,
                verticalRadius: 6,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    // Başlık
                    pw.Container(
                      height: 38,
                      padding: const pw.EdgeInsets.symmetric(horizontal: 14),
                      decoration: const pw.BoxDecoration(
                        gradient: pw.LinearGradient(colors: [PdfColors.indigo900, PdfColors.indigo600]),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.amber400,
                              borderRadius: pw.BorderRadius.circular(6),
                            ),
                            child: pw.Text(room.classroomName,
                                style: pw.TextStyle(font: fontBold, fontSize: 13, color: navy)),
                          ),
                          pw.SizedBox(width: 12),
                          pw.Expanded(
                            child: pw.Column(
                              mainAxisAlignment: pw.MainAxisAlignment.center,
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text('Sınav Davranışları Gözlem Formu',
                                    style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.white)),
                                pw.SizedBox(height: 1),
                                pw.Text(
                                  '$examTitle   •   Tarih: $dateStr   •   Saat: ${distribution.examTime}',
                                  style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.indigo100),
                                ),
                              ],
                            ),
                          ),
                          if (pageCount > 1)
                            pw.Text('Sayfa ${p + 1}/$pageCount',
                                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.indigo100)),
                        ],
                      ),
                    ),
                    // Tablo
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
                      columnWidths: {
                        0: const pw.FixedColumnWidth(26),
                        1: const pw.FixedColumnWidth(140),
                        for (int i = 0; i < _observationBehaviors.length; i++) 2 + i: const pw.FixedColumnWidth(38),
                        2 + _observationBehaviors.length: const pw.FlexColumnWidth(1),
                      },
                      children: [
                        pw.TableRow(
                          children: [
                            pw.Container(
                              color: navy,
                              height: headerH,
                              alignment: pw.Alignment.center,
                              child: pw.Text('SR', style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white)),
                            ),
                            pw.Container(
                              color: navy,
                              height: headerH,
                              alignment: pw.Alignment.center,
                              child: pw.Text('ÖĞRENCİNİN\nADI / SOYADI',
                                  textAlign: pw.TextAlign.center,
                                  style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.white)),
                            ),
                            for (int i = 0; i < _observationBehaviors.length; i++)
                              pw.Container(
                                height: headerH,
                                color: _tint(_obsColors[i % _obsColors.length], 0.16),
                                alignment: pw.Alignment.center,
                                child: pw.Transform.rotateBox(
                                  angle: 3.14159265 / 2,
                                  unconstrained: true,
                                  child: pw.SizedBox(
                                    width: headerH - 10,
                                    child: pw.Text(
                                      _observationBehaviors[i],
                                      textAlign: pw.TextAlign.center,
                                      style: pw.TextStyle(
                                        font: fontBold,
                                        fontSize: 8,
                                        lineSpacing: 2.2,
                                        color: _obsColors[i % _obsColors.length],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            pw.Container(
                              color: navy,
                              height: headerH,
                              alignment: pw.Alignment.center,
                              padding: const pw.EdgeInsets.symmetric(horizontal: 6),
                              child: pw.Text('VARSA SINAVDA GÖZLEMLENEN\nDİĞER DAVRANIŞLAR:',
                                  textAlign: pw.TextAlign.center,
                                  style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white)),
                            ),
                          ],
                        ),
                        for (int i = 0; i < rowsPerPage; i++)
                          pw.TableRow(
                            decoration: pw.BoxDecoration(
                              color: i.isOdd ? PdfColors.indigo50 : PdfColors.white,
                            ),
                            children: [
                              cell(
                                pw.Text('${p * rowsPerPage + i + 1}',
                                    style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: PdfColors.indigo700)),
                                h: rowH,
                              ),
                              cell(
                                pw.Text(
                                  i < chunk.length ? chunk[i].student!.fullName : '',
                                  maxLines: 1,
                                  overflow: pw.TextOverflow.clip,
                                  style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey900),
                                ),
                                h: rowH,
                                align: pw.Alignment.centerLeft,
                              ),
                              for (int k = 0; k < _observationBehaviors.length; k++) pw.SizedBox(height: rowH),
                              pw.SizedBox(height: rowH),
                            ],
                          ),
                      ],
                    ),
                    pw.Spacer(),
                    pw.Container(
                      padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 4),
                      color: PdfColors.amber50,
                      child: pw.Text(
                        'Öğrencilerimizin sınav sırasındaki gözlemlenebilen davranışları başarılarını önemli derecede etkileyen ipuçları taşır. '
                        'Daha etkili bir rehberlik için; öğrencilerimizin sınav sonuçlarının değerlendirilmesinde katkısı olacak değerli gözlemlerinizi '
                        'titizlikle paylaşacağınıza inanıyor, şimdiden çok teşekkür ediyoruz.',
                        style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: PdfColors.grey800),
                      ),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 5),
                      color: navy,
                      child: pw.Text(
                        'GÖZETMEN ÖĞRETMENİN ADI SOYADI - İMZASI: ${(room.supervisorName ?? '').trim() == 'Gözetmen Öğretmen' ? '' : (room.supervisorName ?? '').trim()}',
                        style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
  }

  // ===========================================================================
  // WIDGET BİLEŞENLERİ: KAPI LİSTESİ & YOKLAMA LİSTESİ
  // ===========================================================================

  static pw.Widget _buildGateListHeader(
    ExamDistribution distribution,
    ExamRoom room,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final dateStr = DateFormat('dd.MM.yyyy').format(distribution.examDate);
    final examTitle = _getExamTitle(distribution);

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.indigo900,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                distribution.schoolTypeName.toUpperCase(),
                style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.indigo200),
              ),
              pw.Text(
                examTitle,
                style: pw.TextStyle(font: fontBold, fontSize: 15, color: PdfColors.white),
              ),
              pw.Text(
                'Ders: ${distribution.lessonName}',
                style: pw.TextStyle(font: font, fontSize: 10.5, color: PdfColors.indigo100),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'KAPI LİSTESİ',
                  style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.indigo900),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '$dateStr • ${distribution.examTime}',
                style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildAttendanceHeader(
    ExamDistribution distribution,
    ExamRoom room,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final dateStr = DateFormat('dd.MM.yyyy').format(distribution.examDate);
    final examTitle = _getExamTitle(distribution);

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey900,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                distribution.schoolTypeName.toUpperCase(),
                style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.blueGrey200),
              ),
              pw.Text(
                examTitle,
                style: pw.TextStyle(font: fontBold, fontSize: 15, color: PdfColors.white),
              ),
              pw.Text(
                'Ders: ${distribution.lessonName}',
                style: pw.TextStyle(font: font, fontSize: 10.5, color: PdfColors.blueGrey100),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.amber400,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  'SALON YOKLAMA LİSTESİ',
                  style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.black),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '$dateStr • ${distribution.examTime}',
                style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildMasterHeader(
    ExamDistribution distribution,
    pw.Font font,
    pw.Font fontBold,
    int totalStudents,
  ) {
    final dateStr = DateFormat('dd.MM.yyyy').format(distribution.examDate);
    final examTitle = _getExamTitle(distribution);

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.indigo900,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${distribution.schoolTypeName.toUpperCase()} • $examTitle',
                style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.white),
              ),
              pw.Text(
                'GENEL ÖĞRENCİ ALFABETİK YERLEŞİM LİSTESİ (A - Z)',
                style: pw.TextStyle(font: fontBold, fontSize: 10.5, color: PdfColors.amber300),
              ),
              pw.Text(
                'Ders: ${distribution.lessonName} • Tarih: $dateStr • Saat: ${distribution.examTime}',
                style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.indigo100),
              ),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              'Toplam $totalStudents öğrenci',
              style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.indigo900),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildRoomInfoBanner(
    ExamDistribution distribution,
    ExamRoom room,
    pw.Font font,
    pw.Font fontBold, {
    bool isAttendance = false,
  }) {
    final hasCustomSupervisor = room.supervisorName != null &&
        room.supervisorName!.trim().isNotEmpty &&
        room.supervisorName != 'Gözetmen Öğretmen';

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Text('SINAV SALONU: ', style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey800)),
              pw.Text(room.classroomName, style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.indigo900)),
            ],
          ),
          if (hasCustomSupervisor)
            pw.Row(
              children: [
                pw.Text('GÖZETMEN: ', style: pw.TextStyle(font: font, fontSize: 10.5, color: PdfColors.grey800)),
                pw.Text(room.supervisorName!, style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.black)),
              ],
            ),
          pw.Row(
            children: [
              pw.Text('TOPLAM ÖĞRENCİ: ', style: pw.TextStyle(font: font, fontSize: 10.5, color: PdfColors.grey800)),
              pw.Text('${room.seatedStudentCount} Öğrenci', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.indigo900)),
            ],
          ),
        ],
      ),
    );
  }

  /// Kapı Listesi Tablosu (Sıra Numarasına Göre 1, 2, 3... Sıralı)
  static pw.Widget _buildGateListTable(
    List<SeatCoordinate> seats,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.7),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(3.8),
        3: pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _buildTableHeaderCell('SIRA NO', fontBold),
            _buildTableHeaderCell('ÖĞRENCİ NO', fontBold),
            _buildTableHeaderCell('ÖĞRENCİ ADI SOYADI', fontBold),
            _buildTableHeaderCell('ŞUBE', fontBold),
          ],
        ),
        ...seats.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final seat = entry.value;
          final s = seat.student!;
          final isEven = (idx % 2 == 0);

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? PdfColors.grey50 : PdfColors.white,
            ),
            children: [
              _buildTableCell('${seat.seatNumber}', fontBold, align: pw.TextAlign.center),
              _buildTableCell(s.studentNumber, fontBold, align: pw.TextAlign.center),
              _buildTableCell('  ${s.fullName}', fontBold),
              _buildTableCell(s.className, font, align: pw.TextAlign.center),
            ],
          );
        }),
      ],
    );
  }

  /// Yoklama Listesi Tablosu (Sıra Numarasına Göre 1, 2, 3... Sıralı)
  static pw.Widget _buildAttendanceTable(
    List<SeatCoordinate> seats,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.7),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.0),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(3.5),
        3: pw.FlexColumnWidth(1.1),
        4: pw.FlexColumnWidth(1.5),
        5: pw.FlexColumnWidth(1.8),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
          children: [
            _buildTableHeaderCell('SIRA NO', fontBold),
            _buildTableHeaderCell('ÖĞRENCİ NO', fontBold),
            _buildTableHeaderCell('ÖĞRENCİ ADI SOYADI', fontBold),
            _buildTableHeaderCell('ŞUBE', fontBold),
            _buildTableHeaderCell('KATILIM (+/-)', fontBold),
            _buildTableHeaderCell('İMZA', fontBold),
          ],
        ),
        ...seats.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final seat = entry.value;
          final s = seat.student!;
          final isEven = (idx % 2 == 0);

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? PdfColors.grey50 : PdfColors.white,
            ),
            children: [
              _buildTableCell('${seat.seatNumber}', fontBold, align: pw.TextAlign.center),
              _buildTableCell(s.studentNumber, fontBold, align: pw.TextAlign.center),
              _buildTableCell('  ${s.fullName}', fontBold),
              _buildTableCell(s.className, font, align: pw.TextAlign.center),
              _buildTableCell('[   ]', font, align: pw.TextAlign.center),
              _buildTableCell('', font),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildMasterTable(
    List<Map<String, dynamic>> items,
    int startIndex,
    pw.Font font,
    pw.Font fontBold, {
    bool includeHeader = true,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.7),
      columnWidths: const {
        0: pw.FlexColumnWidth(0.8),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(3.8),
        3: pw.FlexColumnWidth(1.2),
        4: pw.FlexColumnWidth(2.5),
        5: pw.FlexColumnWidth(1.2),
      },
      children: [
        if (includeHeader)
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.indigo100),
          children: [
            _buildTableHeaderCell('SIRA', fontBold),
            _buildTableHeaderCell('NO', fontBold),
            _buildTableHeaderCell('ÖĞRENCİ ADI SOYADI', fontBold),
            _buildTableHeaderCell('ŞUBE', fontBold),
            _buildTableHeaderCell('SINAV SALONU', fontBold),
            _buildTableHeaderCell('SIRA NO', fontBold),
          ],
        ),
        ...items.asMap().entries.map((entry) {
          final idx = startIndex + entry.key + 1;
          final item = entry.value;
          final s = item['student'] as ExamStudent;
          final roomName = item['roomName'] as String;
          final seatNo = item['seatNumber'] as int;
          final isEven = (idx % 2 == 0);

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? PdfColors.grey50 : PdfColors.white,
            ),
            children: [
              _buildTableCell('$idx', font, align: pw.TextAlign.center),
              _buildTableCell(s.studentNumber, fontBold, align: pw.TextAlign.center),
              _buildTableCell('  ${s.fullName}', fontBold),
              _buildTableCell(s.className, font, align: pw.TextAlign.center),
              _buildTableCell(roomName, fontBold, align: pw.TextAlign.center),
              _buildTableCell('$seatNo', fontBold, align: pw.TextAlign.center),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTableHeaderCell(String text, pw.Font fontBold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.black),
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text,
    pw.Font font, {
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.2, horizontal: 3),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.black),
      ),
    );
  }

  static pw.Widget _buildGateListFooter(
    ExamDistribution distribution,
    int studentCount,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final nowStr = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '• Sınav salonuna giriş yaparken lütfen sıranıza oturun ve kimliğinizi masada bulundurun.',
            style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey700),
          ),
          pw.Text(
            'Oluşturulma: $nowStr',
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildAttendanceFooter(
    ExamDistribution distribution,
    ExamRoom room,
    int studentCount,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final hasSupervisor = room.supervisorName != null &&
        room.supervisorName!.trim().isNotEmpty &&
        room.supervisorName != 'Gözetmen Öğretmen';

    final supervisorText = hasSupervisor
        ? 'Gözetmen: ${room.supervisorName!.trim()}'
        : 'Gözetmen: _____________________________';

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Katılan Öğrenci Sayısı: [ ____ ]', style: pw.TextStyle(font: fontBold, fontSize: 9)),
              pw.SizedBox(height: 2),
              pw.Text('Katılmayan Öğrenci Sayısı: [ ____ ]', style: pw.TextStyle(font: fontBold, fontSize: 9)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(supervisorText, style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.indigo900)),
              pw.SizedBox(height: 6),
              pw.Text('İmza: _____________________________', style: pw.TextStyle(font: font, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // WIDGET BİLEŞENLERİ: GÖZETMEN KROKİSİ
  // ===========================================================================

  static const List<PdfColor> _classPalette = [
    PdfColors.indigo600,
    PdfColors.teal600,
    PdfColors.deepOrange500,
    PdfColors.purple500,
    PdfColors.blue600,
    PdfColors.green700,
    PdfColors.pink500,
    PdfColors.amber800,
    PdfColors.cyan700,
    PdfColors.brown500,
  ];

  /// Şube adından her zaman aynı rengi üretir (kroki üzerinde şubeleri ayırt etmek için).
  static PdfColor _classColor(String className) {
    var h = 0;
    for (final u in className.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return _classPalette[h % _classPalette.length];
  }

  static pw.Widget _buildSupervisorHeader(
    ExamDistribution distribution,
    ExamRoom room,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final examTitle = _getExamTitle(distribution);
    final pct = room.totalCapacity == 0 ? 0.0 : (room.seatedStudentCount / room.totalCapacity).clamp(0.0, 1.0);

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 9, 14, 9),
      decoration: pw.BoxDecoration(
        gradient: const pw.LinearGradient(colors: [PdfColors.indigo900, PdfColors.indigo600]),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 62,
            height: 42,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: PdfColors.amber400,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              room.classroomName,
              maxLines: 1,
              style: pw.TextStyle(font: fontBold, fontSize: 17, color: PdfColors.indigo900),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SALON OTURMA KROKİSİ',
                  style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.amber300, letterSpacing: 1.2),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '${distribution.schoolTypeName} • $examTitle',
                  maxLines: 1,
                  style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.white),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                '${room.seatedStudentCount}',
                style: pw.TextStyle(font: fontBold, fontSize: 22, color: PdfColors.white),
              ),
              pw.Text(
                'öğrenci / ${room.totalCapacity} kapasite',
                style: pw.TextStyle(font: font, fontSize: 7.5, color: PdfColors.indigo100),
              ),
              pw.SizedBox(height: 3),
              pw.Container(
                width: 90,
                height: 4,
                decoration: pw.BoxDecoration(
                  color: PdfColors.indigo300,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
                child: pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Container(
                    width: 90 * pct,
                    height: 4,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.amber400,
                      borderRadius: pw.BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTeacherBoard(pw.Font fontBold) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.symmetric(horizontal: 60),
      decoration: pw.BoxDecoration(
        gradient: const pw.LinearGradient(colors: [PdfColors.grey800, PdfColors.grey700, PdfColors.grey800]),
        borderRadius: const pw.BorderRadius.only(
          bottomLeft: pw.Radius.circular(14),
          bottomRight: pw.Radius.circular(14),
          topLeft: pw.Radius.circular(3),
          topRight: pw.Radius.circular(3),
        ),
      ),
      child: pw.Text(
        'ÖĞRETMEN KÜRSÜSÜ  •  YAZI TAHTASI',
        style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white, letterSpacing: 1.5),
      ),
    );
  }

  static pw.Widget _buildSupervisorGrid(
    ExamRoom room,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final layout = room.layoutSnapshot;
    final Map<String, SeatCoordinate> seatMap = {
      for (final s in room.seats) '${s.row}-${s.col}-${s.slotIndex}': s,
    };

    return pw.Column(
      children: List.generate(layout.rows, (r) {
        return pw.Expanded(
          child: pw.Row(
            children: List.generate(layout.cols, (c) {
              final cell = layout.cells.firstWhere(
                (cl) => cl.row == r && cl.col == c,
                orElse: () => DeskCell(
                  row: r,
                  col: c,
                  cellType: CellType.aisle,
                  deskType: DeskType.single,
                ),
              );

              return pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.all(2.5),
                  child: _buildLayoutCellWidget(cell, seatMap, font, fontBold),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  static pw.Widget _buildLayoutCellWidget(
    DeskCell cell,
    Map<String, SeatCoordinate> seatMap,
    pw.Font font,
    pw.Font fontBold,
  ) {
    if (cell.cellType == CellType.aisle) {
      return pw.Center(
        child: pw.Text(
          'KORİDOR',
          style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey400),
        ),
      );
    }

    if (cell.cellType != CellType.desk) {
      return pw.SizedBox();
    }

    if (cell.deskType == DeskType.single) {
      final seat = seatMap['${cell.row}-${cell.col}-0'];
      return _buildSeatBox(seat, font, fontBold);
    } else if (cell.deskType == DeskType.double) {
      final seatLeft = seatMap['${cell.row}-${cell.col}-0'];
      final seatRight = seatMap['${cell.row}-${cell.col}-1'];

      return pw.Row(
        children: [
          pw.Expanded(child: _buildSeatBox(seatLeft, font, fontBold)),
          pw.SizedBox(width: 3),
          pw.Expanded(child: _buildSeatBox(seatRight, font, fontBold)),
        ],
      );
    }

    return pw.SizedBox();
  }

  static pw.Widget _buildSeatBox(
    SeatCoordinate? seat,
    pw.Font font,
    pw.Font fontBold,
  ) {
    if (seat == null) {
      return pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          color: PdfColors.grey100,
        ),
      );
    }

    final s = seat.student;
    if (s == null) {
      return pw.Container(
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text('${seat.seatNumber}',
                  style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.grey500)),
              pw.Text('BOŞ', style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey500)),
            ],
          ),
        ),
      );
    }

    final accent = _classColor(s.className);
    final firstName = s.name.trim();
    final surname = s.surname.trim();

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: _tint(accent, 0.45), width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Üst şerit: sıra no + şube
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
            decoration: pw.BoxDecoration(
              color: _tint(accent, 0.16),
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(5),
                topRight: pw.Radius.circular(5),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Container(
                  width: 16,
                  height: 16,
                  alignment: pw.Alignment.center,
                  decoration: pw.BoxDecoration(color: accent, shape: pw.BoxShape.circle),
                  child: pw.Text(
                    '${seat.seatNumber}',
                    style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white),
                  ),
                ),
                pw.Text(
                  s.className,
                  style: pw.TextStyle(font: fontBold, fontSize: 8, color: accent),
                ),
              ],
            ),
          ),
          // İsim (üstte) / Soyisim (altta) - ortalı
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 3),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    firstName,
                    textAlign: pw.TextAlign.center,
                    maxLines: 2,
                    style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey800),
                  ),
                  pw.SizedBox(height: 1.5),
                  pw.Text(
                    surname.toUpperCase(),
                    textAlign: pw.TextAlign.center,
                    maxLines: 2,
                    style: pw.TextStyle(font: fontBold, fontSize: 11.5, color: PdfColors.black),
                  ),
                ],
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Text(
              'No: ${s.studentNumber}',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: font, fontSize: 6.5, color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSupervisorFooter(
    ExamDistribution distribution,
    ExamRoom room,
    pw.Font font,
    pw.Font fontBold,
  ) {
    final nowStr = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());
    final hasSupervisor = room.supervisorName != null &&
        room.supervisorName!.trim().isNotEmpty &&
        room.supervisorName != 'Gözetmen Öğretmen';

    final supervisorText = hasSupervisor
        ? 'Gözetmen: ${room.supervisorName!.trim()}'
        : 'Gözetmen: _____________________________';

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '• Öğrencilerin krokide belirtilen masalara oturmalarını kontrol ediniz.',
            style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700),
          ),
          pw.Text(
            supervisorText,
            style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.indigo900),
          ),
          pw.Text(
            'Tarih: $nowStr',
            style: pw.TextStyle(font: font, fontSize: 7.5, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  /// ===========================================================================
  /// 7. SINAV UYGULAMA YÖNERGESİ VE GÖZETMEN KURALLARI (A4 PORTRAIT)
  /// ===========================================================================
  static Future<Uint8List> generateInstructionPdf({
    required ExamDistribution distribution,
    required List<String> instructions,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final dateStr = DateFormat('dd.MM.yyyy').format(distribution.examDate);
    final examTitle = _getExamTitle(distribution);
    final parsedSessions = _extractSessions(distribution);

    final sessionWidgets = <pw.Widget>[];
    for (int i = 0; i < parsedSessions.length; i++) {
      final session = parsedSessions[i];
      sessionWidgets.add(
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.indigo100, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      session.title,
                      style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: PdfColors.indigo900),
                    ),
                    if (session.durationMinutes > 0)
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.indigo50,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          '${session.durationMinutes} dk',
                          style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: PdfColors.indigo800),
                        ),
                      ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  children: [
                    pw.Text('Başlama: ', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
                    pw.Text(session.startTime, style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.black)),
                    if (session.endTime.isNotEmpty) ...[
                      pw.SizedBox(width: 8),
                      pw.Text('Bitiş: ', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)),
                      pw.Text(session.endTime, style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.black)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (session.breakMinutesAfter > 0) {
        sessionWidgets.add(pw.SizedBox(width: 6));
        sessionWidgets.add(
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColors.amber50,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.amber300, width: 0.8),
            ),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  'ARA',
                  style: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.amber900),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  '${session.breakMinutesAfter} dk',
                  style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.amber900),
                ),
              ],
            ),
          ),
        );
        sessionWidgets.add(pw.SizedBox(width: 6));
      } else if (i < parsedSessions.length - 1) {
        sessionWidgets.add(pw.SizedBox(width: 6));
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        footer: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Tüm salon görevlileri ve gözetmen öğretmenler bu yönergeye uymakla yükümlüdür.',
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700),
              ),
              pw.Text(
                'Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}  •  ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
                style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        build: (ctx) => [
          // Başlık Bandı
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: pw.BoxDecoration(
              gradient: const pw.LinearGradient(colors: [PdfColors.indigo900, PdfColors.indigo700]),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'SINAV UYGULAMA YÖNERGESİ & GÖZETMEN KURALLARI',
                      style: pw.TextStyle(font: fontBold, fontSize: 12.5, color: PdfColors.white),
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.indigo500,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(
                        '${instructions.length} Madde',
                        style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    // Sol Taraf: Sınav Başlığı ve Dersi
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            examTitle,
                            style: pw.TextStyle(font: fontBold, fontSize: 15, color: PdfColors.white),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            '${distribution.lessonName} • ${distribution.schoolTypeName}',
                            style: pw.TextStyle(font: font, fontSize: 9.5, color: PdfColors.indigo100),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 14),
                    // Sağ Alt Taraf: Sınav Tarihi, Saat ve Toplam Öğrenci
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(0x28FFFFFF),
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(color: PdfColor.fromInt(0x40FFFFFF), width: 0.5),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Row(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              pw.Text('Sınav Tarihi: ', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.indigo100)),
                              pw.Text(dateStr, style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white)),
                            ],
                          ),
                          pw.SizedBox(height: 2.5),
                          pw.Row(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              pw.Text('Sınav Saati: ', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.indigo100)),
                              pw.Text(distribution.examTime, style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white)),
                            ],
                          ),
                          pw.SizedBox(height: 2.5),
                          pw.Row(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              pw.Text('Toplam Öğrenci: ', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.indigo100)),
                              pw.Text('${distribution.totalStudents} Öğrenci', style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // Sınav Oturumları ve Zaman Çizelgesi Kartı
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Row(
                      children: [
                        pw.Container(
                          width: 6,
                          height: 6,
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.indigo900,
                            shape: pw.BoxShape.circle,
                          ),
                        ),
                        pw.SizedBox(width: 5),
                        pw.Text(
                          'SINAV OTURUM VE ZAMAN ÇİZELGESİ',
                          style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.indigo900),
                        ),
                        pw.SizedBox(width: 6),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.indigo50,
                            borderRadius: pw.BorderRadius.circular(4),
                            border: pw.Border.all(color: PdfColors.indigo200, width: 0.5),
                          ),
                          child: pw.Text(
                            parsedSessions.length <= 1 ? 'Tek Oturum' : '${parsedSessions.length} Oturum',
                            style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: PdfColors.indigo900),
                          ),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(4),
                        border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
                      ),
                      child: pw.Text(
                        'Derslik / Salon: ${distribution.rooms.length} Salon',
                        style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.grey800),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: sessionWidgets,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          pw.Text('Uygulama Esasları ve Talimatlar', style: pw.TextStyle(font: fontBold, fontSize: 11.5, color: PdfColors.indigo900)),
          pw.SizedBox(height: 8),

          // Yönerge Maddeleri
          for (int i = 0; i < instructions.length; i++) ...[
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: i.isEven ? PdfColors.white : PdfColors.grey50,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 22,
                    height: 22,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.indigo900,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      '${i + 1}',
                      style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Text(
                      instructions[i],
                      style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey900, lineSpacing: 2),
                    ),
                  ),
                ],
              ),
            ),
          ],

          pw.SizedBox(height: 20),

          // Onay ve İmza Alanı
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Bina Sınav Komisyon Başkanı', style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.grey800)),
                    pw.SizedBox(height: 25),
                    pw.Text('İmza / Mühür: .......................................', style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Sınav Yürütme ve Güvenlik', style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.grey800)),
                    pw.SizedBox(height: 25),
                    pw.Text('İmza: .......................................', style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Yönerge ve krokiler için oturumları zaman ve ara süreleriyle ayrıştırır
  static List<_ParsedPdfSession> _extractSessions(ExamDistribution distribution) {
    if (distribution.sessionSlots.isEmpty) {
      String start = distribution.examTime;
      String end = '';
      if (distribution.examTime.contains('-')) {
        final parts = distribution.examTime.split('-');
        start = parts[0].trim();
        end = parts[1].trim();
      }
      return [
        _ParsedPdfSession(
          sessionIndex: 0,
          title: '1. Oturum',
          startTime: start,
          endTime: end,
          durationMinutes: 0,
          breakMinutesAfter: 0,
        ),
      ];
    }

    final Map<int, List<Map<String, dynamic>>> bySession = {};
    for (int i = 0; i < distribution.sessionSlots.length; i++) {
      final slot = distribution.sessionSlots[i];
      final sIdx = (slot['sessionIndex'] as int?) ?? (slot['slotIndex'] as int?) ?? i;
      bySession.putIfAbsent(sIdx, () => []).add(slot);
    }

    final sortedKeys = bySession.keys.toList()..sort();
    final List<_ParsedPdfSession> result = [];

    for (int i = 0; i < sortedKeys.length; i++) {
      final sIdx = sortedKeys[i];
      final slots = bySession[sIdx]!;
      final firstSlot = slots.first;
      final lastSlot = slots.last;

      final title = firstSlot['sessionTitle']?.toString() ??
          firstSlot['label']?.toString() ??
          '${i + 1}. Oturum';

      final startTime = firstSlot['startTime']?.toString() ?? distribution.examTime;
      final endTime = lastSlot['endTime']?.toString() ?? '';

      int totalDuration = slots.fold<int>(
        0,
        (sum, s) => sum + ((s['durationMinutes'] as int?) ?? 0),
      );
      if (totalDuration == 0 && startTime.isNotEmpty && endTime.isNotEmpty) {
        try {
          final sParts = startTime.split(':');
          final eParts = endTime.split(':');
          if (sParts.length == 2 && eParts.length == 2) {
            final sMin = int.parse(sParts[0]) * 60 + int.parse(sParts[1]);
            final eMin = int.parse(eParts[0]) * 60 + int.parse(eParts[1]);
            if (eMin > sMin) {
              totalDuration = eMin - sMin;
            }
          }
        } catch (_) {}
      }

      final breakMinutes = (lastSlot['breakMinutes'] as int?) ?? 0;

      result.add(_ParsedPdfSession(
        sessionIndex: sIdx,
        title: title,
        startTime: startTime,
        endTime: endTime,
        durationMinutes: totalDuration,
        breakMinutesAfter: (i < sortedKeys.length - 1) ? breakMinutes : 0,
      ));
    }

    return result;
  }
}

class _ParsedPdfSession {
  final int sessionIndex;
  final String title;
  final String startTime;
  final String endTime;
  final int durationMinutes;
  final int breakMinutesAfter;

  _ParsedPdfSession({
    required this.sessionIndex,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.breakMinutesAfter,
  });
}
