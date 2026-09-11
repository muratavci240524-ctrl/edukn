import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/school/dynamic_course_group_model.dart';
import 'pdf_service.dart';

class DynamicGroupPdfService {
  /// 1. DERSLİK / KAPI / ÖĞRETMEN YOKLAMA LİSTESİ PDF
  /// Kapıya asılacak ya da öğretmenin elinde yoklama alacağı liste.
  Future<Uint8List> generateSubGroupRosterPdf({
    required DynamicCourseGroup group,
    required DynamicSubGroup subGroup,
    required List<Map<String, dynamic>> students,
    String? schoolName,
  }) async {
    final pdf = pw.Document();

    final font = await PdfService.getFont();
    final fontBold = await PdfService.getFontBold();

    final isClub = group.type == DynamicCourseGroupType.club;
    final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (schoolName != null && schoolName.isNotEmpty)
                      pw.Text(
                        schoolName.toUpperCase(),
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 13,
                          color: PdfColors.grey700,
                        ),
                      ),
                    pw.Text(
                      isClub ? 'KULÜP ÖĞRENCİ VE YOKLAMA LİSTESİ' : 'KUR DERSLİK VE YOKLAMA LİSTESİ',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 15,
                        color: PdfColors.indigo900,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'Tarih: $dateStr',
                  style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            pw.TextSpan(text: isClub ? 'Kulüp Adı: ' : 'Kur Adı: ', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                            pw.TextSpan(text: subGroup.name, style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.indigo700)),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            pw.TextSpan(text: 'Ders / Kategori: ', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                            pw.TextSpan(text: group.name, style: pw.TextStyle(font: font, fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            pw.TextSpan(text: 'Öğretmen: ', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                            pw.TextSpan(
                              text: subGroup.teacherNames.isNotEmpty ? subGroup.teacherNames.join(', ') : 'Atanmadı',
                              style: pw.TextStyle(font: font, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            pw.TextSpan(text: 'Derslik / Yer: ', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                            pw.TextSpan(
                              text: subGroup.classroomName.isNotEmpty ? subGroup.classroomName : '-',
                              style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.grey800),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Öğrenci Sayısı: ${students.length}',
                        style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.blue800),
                      ),
                      if (subGroup.capacity != null && subGroup.capacity! > 0)
                        pw.Text(
                          'Kontenjan: ${subGroup.capacity}',
                          style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
          ],
        ),
        build: (context) {
          return [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(28),  // Sıra No
                1: pw.FixedColumnWidth(45),  // Okul No
                2: pw.FlexColumnWidth(3.5),  // Ad Soyad
                3: pw.FixedColumnWidth(55),  // Asıl Şube
                4: pw.FixedColumnWidth(40),  // Yoklama 1
                5: pw.FixedColumnWidth(40),  // Yoklama 2
                6: pw.FixedColumnWidth(40),  // Yoklama 3
                7: pw.FixedColumnWidth(40),  // Yoklama 4
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.indigo50),
                  children: [
                    _th('No', fontBold, align: pw.TextAlign.center),
                    _th('Öğr. No', fontBold, align: pw.TextAlign.center),
                    _th('Öğrenci Adı Soyadı', fontBold),
                    _th('Asıl Şube', fontBold, align: pw.TextAlign.center),
                    _th('.../...', fontBold, align: pw.TextAlign.center),
                    _th('.../...', fontBold, align: pw.TextAlign.center),
                    _th('.../...', fontBold, align: pw.TextAlign.center),
                    _th('.../...', fontBold, align: pw.TextAlign.center),
                  ],
                ),
                ...students.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final s = entry.value;
                  final fullName = '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim();
                  final studentNumber = (s['studentNumber'] ?? s['number'] ?? '').toString();
                  final className = (s['className'] ?? s['class'] ?? '-').toString();

                  final isEven = idx % 2 == 0;
                  final bg = isEven ? PdfColors.grey50 : PdfColors.white;

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: bg),
                    children: [
                      _td('$idx', font, align: pw.TextAlign.center),
                      _td(studentNumber, fontBold, align: pw.TextAlign.center),
                      _td(fullName, font),
                      _td(className, fontBold, align: pw.TextAlign.center),
                      _td('', font),
                      _td('', font),
                      _td('', font),
                      _td('', font),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('İmza: .......................................', style: pw.TextStyle(font: font, fontSize: 10)),
                pw.Text('Okul İdaresi Onayı', style: pw.TextStyle(font: fontBold, fontSize: 10)),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// 2. ŞUBE DAĞILIM ÇİZELGESİ (SINIF PANOSU PDF)
  /// 501 şubesinin panosuna asılacak; çocukların hangi kura/kulübe gideceğini gösteren liste.
  Future<Uint8List> generateClassDistributionPdf({
    required String className,
    required DynamicCourseGroup group,
    required List<Map<String, dynamic>> classStudents,
    String? schoolName,
  }) async {
    final pdf = pw.Document();

    final font = await PdfService.getFont();
    final fontBold = await PdfService.getFontBold();

    final isClub = group.type == DynamicCourseGroupType.club;
    final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());

    // Öğrenci ID -> SubGroup Map'i oluştur
    final Map<String, DynamicSubGroup> studentSubGroupMap = {};
    for (var sub in group.subGroups) {
      for (var sId in sub.studentIds) {
        studentSubGroupMap[sId] = sub;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (schoolName != null && schoolName.isNotEmpty)
                      pw.Text(
                        schoolName.toUpperCase(),
                        style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.grey700),
                      ),
                    pw.Text(
                      '$className ŞUBESİ ${isClub ? "KULÜP" : "KUR"} DAĞILIM ÇİZELGESİ',
                      style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.indigo900),
                    ),
                  ],
                ),
                pw.Text(
                  'Tarih: $dateStr',
                  style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const pw.BoxDecoration(
                color: PdfColors.indigo50,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Text(
                'Grup: ${group.name} | Bu çizelge $className şubesi öğrencilerinin ders saatindeki yerleşimini gösterir.',
                style: pw.TextStyle(font: font, fontSize: 9.5, color: PdfColors.indigo800),
              ),
            ),
            pw.SizedBox(height: 12),
          ],
        ),
        build: (context) {
          return [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(28),  // Sıra No
                1: pw.FixedColumnWidth(48),  // Okul No
                2: pw.FlexColumnWidth(3),    // Öğrenci Adı Soyadı
                3: pw.FlexColumnWidth(2.5),  // Atandığı Kur / Kulüp
                4: pw.FlexColumnWidth(2.5),  // Öğretmen
                5: pw.FlexColumnWidth(2),    // Derslik / Konum
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _th('No', fontBold, align: pw.TextAlign.center),
                    _th('Öğr. No', fontBold, align: pw.TextAlign.center),
                    _th('Öğrenci Adı Soyadı', fontBold),
                    _th(isClub ? 'Katıldığı Kulüp' : 'Atandığı Kur', fontBold),
                    _th('Sorumlu Öğretmen', fontBold),
                    _th('Derslik / Yer', fontBold),
                  ],
                ),
                ...classStudents.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final s = entry.value;
                  final sId = (s['id'] ?? '').toString();
                  final fullName = '${s['firstName'] ?? ''} ${s['lastName'] ?? ''}'.trim();
                  final studentNumber = (s['studentNumber'] ?? s['number'] ?? '-').toString();

                  final sub = studentSubGroupMap[sId];
                  final subName = sub != null ? sub.name : 'Atama Yapılmadı';
                  final teacherName = sub != null && sub.teacherNames.isNotEmpty ? sub.teacherNames.join(', ') : '-';
                  final classroom = sub != null && sub.classroomName.isNotEmpty ? sub.classroomName : '-';

                  final isEven = idx % 2 == 0;
                  final bg = isEven ? PdfColors.grey50 : PdfColors.white;

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: bg),
                    children: [
                      _td('$idx', font, align: pw.TextAlign.center),
                      _td(studentNumber, fontBold, align: pw.TextAlign.center),
                      _td(fullName, font),
                      _td(subName, fontBold, textColor: sub != null ? PdfColors.indigo800 : PdfColors.red800),
                      _td(teacherName, font),
                      _td(classroom, fontBold),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _th(String text, pw.Font font, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(font: font, fontSize: 9.5, color: PdfColors.grey900),
      ),
    );
  }

  static pw.Widget _td(String text, pw.Font font, {pw.TextAlign align = pw.TextAlign.left, PdfColor textColor = PdfColors.grey900}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(font: font, fontSize: 9, color: textColor),
      ),
    );
  }
}
