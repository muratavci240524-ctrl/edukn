import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/school/official_document_model.dart';
import 'pdf_service.dart';

class OfficialDocumentPdfService {
  static final PdfColor _navy = PdfColor.fromHex('#1E293B');
  static final PdfColor _indigo = PdfColor.fromHex('#312E81');
  static final PdfColor _slate = PdfColor.fromHex('#475569');
  static final PdfColor _border = PdfColor.fromHex('#CBD5E1');
  static final PdfColor _lightBg = PdfColor.fromHex('#F8FAFC');
  static final PdfColor _zebraBg = PdfColor.fromHex('#F1F5F9');

  static String _trUpper(String s) =>
      s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  static Future<Uint8List> generate({
    required OfficialDocTemplate template,
    required SchoolDocContext ctx,
    required DocHeaderStyle headerStyle,
    required String customProvince,
    required String customDistrict,
    required String customSchoolName,
    required String documentTitle,
    required Map<String, dynamic> answers,
    required String composedBody,
    required List<DocSigner> signers,
    required List<DocStudentItem> students,
    required List<DocStaffItem> signatureStaff,
  }) async {
    final fonts = await Future.wait([
      PdfService.getFont(),
      PdfService.getFontBold(),
    ]);
    final font = fonts[0];
    final fontBold = fonts[1];

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
    );

    final effectiveSchoolName = customSchoolName.trim().isNotEmpty
        ? customSchoolName.trim()
        : ctx.schoolName;

    switch (template.layoutKind) {
      case DocLayoutKind.bulkParentSlip:
        _buildBulkParentSlips(
          pdf: pdf,
          headerStyle: headerStyle,
          province: customProvince,
          district: customDistrict,
          schoolName: effectiveSchoolName,
          academicYear: ctx.academicYear,
          documentTitle: documentTitle,
          answers: answers,
          rawBodyTemplate: composedBody,
          students: students,
        );
        break;

      case DocLayoutKind.dynamicChecklist:
        _buildDynamicChecklist(
          pdf: pdf,
          headerStyle: headerStyle,
          province: customProvince,
          district: customDistrict,
          schoolName: effectiveSchoolName,
          academicYear: ctx.academicYear,
          answers: answers,
          students: students,
          staff: signatureStaff.isNotEmpty ? signatureStaff : ctx.allStaff,
        );
        break;

      case DocLayoutKind.badgeGrid:
        _buildBadgeOrDoorList(
          pdf: pdf,
          schoolName: effectiveSchoolName,
          academicYear: ctx.academicYear,
          answers: answers,
          students: students,
        );
        break;

      case DocLayoutKind.circularSignatureTable:
        _buildCircularWithTable(
          pdf: pdf,
          template: template,
          ctx: ctx,
          headerStyle: headerStyle,
          province: customProvince,
          district: customDistrict,
          schoolName: effectiveSchoolName,
          documentTitle: documentTitle,
          answers: answers,
          composedBody: composedBody,
          signers: signers,
          students: students,
          signatureStaff: signatureStaff,
        );
        break;

      case DocLayoutKind.officialLetter:
      case DocLayoutKind.meetingMinutes:
      case DocLayoutKind.incidentForm:
        _buildStandardOfficialDocument(
          pdf: pdf,
          template: template,
          ctx: ctx,
          headerStyle: headerStyle,
          province: customProvince,
          district: customDistrict,
          schoolName: effectiveSchoolName,
          documentTitle: documentTitle,
          answers: answers,
          composedBody: composedBody,
          signers: signers,
          signatureStaff: signatureStaff,
        );
        break;
    }

    return pdf.save();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOPLU ÖDDK / ÖĞRENCİ DİSİPLİN SORUŞTURMA VAKA DOSYASI (TEK PDF BİRLEŞTİRİCİ)
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<Uint8List> generateDossierBundle({
    required SchoolDocContext ctx,
    required DocHeaderStyle headerStyle,
    required String customProvince,
    required String customDistrict,
    required String customSchoolName,
    required String dossierTitle,
    required String fileNo,
    required String boardName,
    required String studentDisplay,
    required String className,
    required String parentDisplay,
    required String incidentDate,
    required String incidentLocation,
    required String incidentSummary,
    required String finalVerdict,
    required bool includeCoverAndIndex,
    required List<DocSigner> coverSigners,
    required List<DossierBundleItem> items,
    List<DocStudentItem> students = const [],
  }) async {
    final fonts = await Future.wait([
      PdfService.getFont(),
      PdfService.getFontBold(),
    ]);
    final font = fonts[0];
    final fontBold = fonts[1];

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
    );

    final effectiveSchoolName = customSchoolName.trim().isNotEmpty
        ? customSchoolName.trim()
        : ctx.schoolName;
    final redAccent = PdfColor.fromHex('#991B1B');
    final redBg = PdfColor.fromHex('#FEF2F2');
    final redBorder = PdfColor.fromHex('#FECACA');

    final footerLabel = fileNo.trim().isNotEmpty
        ? '$effectiveSchoolName • Dosya No: ${fileNo.trim()} (GİZLİ)'
        : '$effectiveSchoolName • ÖDDK / Disiplin Vaka Dosyası';

    // 1) KAPAK SAYFASI VE KRONOLOJİK EVRAK DİZİ PUSULASI
    if (includeCoverAndIndex) {
      final coverMetaRows = <MapEntry<String, String>>[
        MapEntry('Soruşturma / İnceleme Dosya No', fileNo),
        MapEntry('İlgili Kurul Başkanlığı', boardName),
        MapEntry(
          'Eğitim-Öğretim Yılı / Dönem',
          '${ctx.academicYear} — ${ctx.activeTermLabel}',
        ),
        MapEntry(
          'İlgili Öğrenci / Şube',
          className.trim().isNotEmpty
              ? '$studentDisplay ($className)'
              : studentDisplay,
        ),
        if (parentDisplay.trim().isNotEmpty)
          MapEntry('Veli Adı Soyadı ve İletişim', parentDisplay),
        MapEntry(
          'Olay Tarihi ve Yeri',
          [
            incidentDate.trim(),
            incidentLocation.trim(),
          ].where((e) => e.isNotEmpty).join(' — '),
        ),
        if (incidentSummary.trim().isNotEmpty)
          MapEntry('Dosya / Olay Konusu Özeti', incidentSummary.trim()),
        if (finalVerdict.trim().isNotEmpty)
          MapEntry('Kurul Değerlendirme / Sonuç Özeti', finalVerdict.trim()),
        MapEntry(
          'Dosyadaki Toplam Evrak Adedi',
          '${items.length} Adet Resmi Tutanak / Yazı / Ek Belge',
        ),
      ];

      final indexRows = List.generate(items.length, (i) {
        final it = items[i];
        return [
          '${i + 1}',
          it.template.code,
          it.documentTitle,
          it.stepDateLabel.trim().isNotEmpty
              ? it.stepDateLabel.trim()
              : DateFormat('dd.MM.yyyy').format(DateTime.now()),
          'Dosyada Mevcut',
        ];
      });

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(38, 32, 38, 32),
          footer: (context) => _buildFooter(context, footerLabel),
          build: (context) => [
            _buildHeader(
              style: headerStyle,
              province: customProvince,
              district: customDistrict,
              schoolName: effectiveSchoolName,
              academicYear: ctx.academicYear,
              docCode: fileNo,
            ),
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: redBg,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(5),
                  ),
                  border: pw.Border.all(color: redBorder, width: 0.8),
                ),
                child: pw.Text(
                  'HİZMETE ÖZEL / GİZLİ — ÖĞRENCİ DAVRANIŞ DEĞERLENDİRME VE DİSİPLİN VAKA DOSYASI',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 8.5,
                    color: redAccent,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                _trUpper(dossierTitle),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12.5,
                  color: _navy,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 10),
            _buildMetaTable(coverMetaRows),
            pw.SizedBox(height: 12),
            pw.Text(
              'DOSYA MUHTEVİYATI VE KRONOLOJİK EVRAK DİZİ PUSULASI',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
                color: _indigo,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Dizi No',
                'Kod',
                'Resmi Evrak / Tutanak Başlığı',
                'Tarih',
                'Durum',
              ],
              data: indexRows,
              border: pw.TableBorder.all(color: _border, width: 0.6),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 8.3,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: _indigo),
              cellStyle: pw.TextStyle(fontSize: 8.3, color: _navy),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 5,
              ),
              oddRowDecoration: pw.BoxDecoration(color: _zebraBg),
              columnWidths: const {
                0: pw.FixedColumnWidth(36),
                1: pw.FixedColumnWidth(50),
                2: pw.FlexColumnWidth(3.2),
                3: pw.FixedColumnWidth(72),
                4: pw.FixedColumnWidth(66),
              },
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'İşbu vaka/soruşturma dosyasında yukarıdaki dizi pusulasında sıra numarası, kodu ve başlığı yazılı toplam ${items.length} (${items.length}) adet resmi evrak eksiksiz olarak yer almakta olup MEB ilgili Kurum Yönetmeliği hükümleri doğrultusunda gizlilik esaslarına uygun biçimde tanzim edilmiştir.',
              style: pw.TextStyle(
                fontSize: 9.2,
                color: _navy,
                lineSpacing: 2.5,
              ),
              textAlign: pw.TextAlign.justify,
            ),
            pw.SizedBox(height: 18),
            ..._buildSignersWidgets(coverSigners),
          ],
        ),
      );
    }

    // 2) SEÇİLEN TÜM ADIMLARIN SIRALI RESMİ EVRAK SAYFALARI
    for (int idx = 0; idx < items.length; idx++) {
      final item = items[idx];
      final template = item.template;
      final metaRows =
          template.buildMetaRows?.call(item.answers, ctx) ?? const [];
      final diziTag =
          'Dizi S.No: ${idx + 1}/${items.length} • ${template.code}';

      if (template.layoutKind == DocLayoutKind.circularSignatureTable) {
        final tableWidget = (template.customStudentTableHeaders != null &&
                template.customStudentRowBuilder != null)
            ? _buildStudentTable(
                students: students,
                headers: template.customStudentTableHeaders!,
                rowBuilder: (i, s) =>
                    template.customStudentRowBuilder!(i, s, item.answers),
              )
            : _buildStaffSignatureTable(item.signatureStaff);

        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
            footer: (context) => _buildFooter(context, footerLabel),
            build: (context) => [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                    diziTag,
                    style: pw.TextStyle(
                      fontSize: 7.8,
                      fontWeight: pw.FontWeight.bold,
                      color: _slate,
                    ),
                  ),
                ),
              ),
              _buildHeader(
                style: headerStyle,
                province: customProvince,
                district: customDistrict,
                schoolName: effectiveSchoolName,
                academicYear: ctx.academicYear,
                docCode: template.code,
              ),
              pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Text(
                    _trUpper(item.documentTitle),
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 11.5,
                      color: _navy,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ),
              if (metaRows.isNotEmpty) ...[
                _buildMetaTable(metaRows),
                pw.SizedBox(height: 10),
              ],
              ..._renderFormattedParagraphs(item.composedBody),
              pw.SizedBox(height: 12),
              tableWidget,
              pw.SizedBox(height: 18),
              ..._buildSignersWidgets(item.signers),
            ],
          ),
        );
      } else {
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 34),
            footer: (context) => _buildFooter(context, footerLabel),
            build: (context) => [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                    diziTag,
                    style: pw.TextStyle(
                      fontSize: 7.8,
                      fontWeight: pw.FontWeight.bold,
                      color: _slate,
                    ),
                  ),
                ),
              ),
              _buildHeader(
                style: headerStyle,
                province: customProvince,
                district: customDistrict,
                schoolName: effectiveSchoolName,
                academicYear: ctx.academicYear,
                docCode: template.code,
              ),
              pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 10),
                  child: pw.Text(
                    _trUpper(item.documentTitle),
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 12,
                      color: _navy,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ),
              if (metaRows.isNotEmpty) ...[
                _buildMetaTable(metaRows),
                pw.SizedBox(height: 12),
              ],
              ..._renderFormattedParagraphs(item.composedBody),
              pw.SizedBox(height: 22),
              ..._buildSignersWidgets(item.signers),
            ],
          ),
        );
      }
    }

    return pdf.save();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ORTAK ÜST ANTET BİLEŞENİ (MEB RESMİ YAZI VEYA KURUMSAL ANTET)
  // ═══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildHeader({
    required DocHeaderStyle style,
    required String province,
    required String district,
    required String schoolName,
    required String academicYear,
    String? docCode,
  }) {
    if (style == DocHeaderStyle.mebOfficial) {
      final upperProvince = province.trim().isNotEmpty ? '${_trUpper(province.trim())} VALİLİĞİ' : '';
      final upperDistrict = district.trim().isNotEmpty
          ? '${_trUpper(district.trim())} KAYMAKAMLIĞI'
          : '';
      final subLine = [upperProvince, upperDistrict].where((s) => s.isNotEmpty).join(' / ');
      final schoolUpper = _trUpper(schoolName).contains('MÜDÜRLÜĞÜ')
          ? _trUpper(schoolName)
          : '${_trUpper(schoolName)} MÜDÜRLÜĞÜ';

      return pw.Column(
        children: [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text('T.C.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: _navy)),
                if (subLine.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text(
                      subLine,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5, color: _navy),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text(
                    schoolUpper,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: _navy),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Divider(color: _navy, thickness: 1),
          pw.SizedBox(height: 8),
        ],
      );
    }

    // Kurumsal Antet
    return pw.Column(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: pw.BoxDecoration(
            color: _lightBg,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            border: pw.Border.all(color: _border, width: 0.8),
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
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: _indigo),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      '$academicYear Eğitim ve Öğretim Yılı Resmi Evrak Sistemi',
                      style: pw.TextStyle(fontSize: 8.5, color: _slate),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Tarih: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: _navy),
                  ),
                  if (docCode != null && docCode.isNotEmpty)
                    pw.Text(
                      'Şablon Kodu: $docCode',
                      style: pw.TextStyle(fontSize: 8, color: _slate),
                    ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. STANDART RESMİ YAZI / KURUL TUTANAĞI / OLAY & GÖRÜŞME FORMU
  // ═══════════════════════════════════════════════════════════════════════════
  static void _buildStandardOfficialDocument({
    required pw.Document pdf,
    required OfficialDocTemplate template,
    required SchoolDocContext ctx,
    required DocHeaderStyle headerStyle,
    required String province,
    required String district,
    required String schoolName,
    required String documentTitle,
    required Map<String, dynamic> answers,
    required String composedBody,
    required List<DocSigner> signers,
    required List<DocStaffItem> signatureStaff,
  }) {
    final metaRows = template.buildMetaRows?.call(answers, ctx) ?? const [];
    final isSokTemplate =
        template.id == 'sok_toplanti_tutanagi' ||
        template.id == 'ilkogretim_sinif_gecme_tekrar_tutanagi';
    final includeSokTable =
        isSokTemplate && (answers['includeSokSignatureTable'] != false);
    final includeStaffTable =
        !isSokTemplate && (answers['includeStaffSignatureTable'] == true);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 34),
        footer: (context) => _buildFooter(context, schoolName),
        build: (context) => [
          _buildHeader(
            style: headerStyle,
            province: province,
            district: district,
            schoolName: schoolName,
            academicYear: ctx.academicYear,
            docCode: template.code,
          ),
          // Evrak Başlığı
          pw.Center(
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Text(
                _trUpper(documentTitle),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: _navy),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ),
          // Meta Künye Tablosu
          if (metaRows.isNotEmpty) ...[
            _buildMetaTable(metaRows),
            pw.SizedBox(height: 12),
          ],
          // Ana Metin Paragrafları
          ..._renderFormattedParagraphs(composedBody),
          // ŞÖK Raporlarında: Öğretmenler İmza Sirküsü Tablosu + Altında Yalnızca Müdür/Yetkili Onay Bloğu
          if (includeSokTable && signatureStaff.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              'ŞUBE ÖĞRETMENLER KURULU KATILIMCI İMZA SİRKÜSÜ',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
                color: _navy,
              ),
            ),
            pw.SizedBox(height: 6),
            _buildStaffSignatureTable(signatureStaff),
          ],
          pw.SizedBox(height: 22),
          // İmza Blokları (ŞÖK'te yalnızca Müdür / Kurul Başkanı / Yetkili)
          ..._buildSignersWidgets(signers),
          // Opsiyonel: Öğretmenler Kurulu İmza Sirküsü (Tüm Okul)
          if (includeStaffTable &&
              (signatureStaff.isNotEmpty || ctx.allStaff.isEmpty)) ...[
            pw.NewPage(),
            _buildHeader(
              style: headerStyle,
              province: province,
              district: district,
              schoolName: schoolName,
              academicYear: ctx.academicYear,
              docCode: template.code,
            ),
            pw.Center(
              child: pw.Text(
                '$documentTitle — KATILIMCI İMZA SİRKÜSÜ',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: _navy),
              ),
            ),
            pw.SizedBox(height: 10),
            _buildStaffSignatureTable(signatureStaff),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. TEBLİĞ-TEBELLÜĞ / GEZİ KAFİLE / VELİ TOPLANTISI / PROJE İMZA LİSTELİ EVRAK
  // ═══════════════════════════════════════════════════════════════════════════
  static void _buildCircularWithTable({
    required pw.Document pdf,
    required OfficialDocTemplate template,
    required SchoolDocContext ctx,
    required DocHeaderStyle headerStyle,
    required String province,
    required String district,
    required String schoolName,
    required String documentTitle,
    required Map<String, dynamic> answers,
    required String composedBody,
    required List<DocSigner> signers,
    required List<DocStudentItem> students,
    required List<DocStaffItem> signatureStaff,
  }) {
    final metaRows = template.buildMetaRows?.call(answers, ctx) ?? const [];
    final isStaffCircular =
        template.usesStaffSignatureSelector ||
        template.id == 'genel_teblig_imza_sirkusu' ||
        template.id == 'nobet_gorev_teblig_cizelgesi';
    final isTripList =
        template.id == 'okul_gezisi_kafile_onay_paketi' ||
        template.id == 'sosyal_sportif_yarisma_onay';
    final isParentMeeting = template.id == 'veli_toplantisi_paketi';
    final isProjectDist = template.id == 'proje_odevi_dagitim_cizelgesi';
    final isPracticalExam =
        template.id == 'uygulamali_sinav_degerlendirme_tutanagi';
    final isExamHallRoll =
        template.id == 'sinav_salonu_uygulama_yoklama_tutanagi';

    pw.Widget tableWidget;
    if (template.customStudentTableHeaders != null &&
        template.customStudentRowBuilder != null) {
      tableWidget = _buildStudentTable(
        students: students,
        headers: template.customStudentTableHeaders!,
        rowBuilder: (i, s) =>
            template.customStudentRowBuilder!(i, s, answers),
      );
    } else if (isStaffCircular) {
      tableWidget = _buildStaffSignatureTable(signatureStaff);
    } else if (isTripList) {
      tableWidget = _buildStudentTable(
        students: students,
        headers: const ['S.No', 'Şube / No', 'Öğrenci Adı Soyadı', 'T.C. Kimlik No', 'Veli İletişim Tel', 'Kontrol'],
        rowBuilder: (i, s) => [
          '${i + 1}',
          '${s.className} / ${s.studentNo}',
          s.fullName,
          s.tcNo,
          s.parentPhone,
          '',
        ],
      );
    } else if (isParentMeeting) {
      tableWidget = _buildStudentTable(
        students: students,
        headers: const ['S.No', 'No / Şube', 'Öğrenci Adı Soyadı', 'Veli Adı Soyadı', 'İletişim Tel', 'Veli İmzası'],
        rowBuilder: (i, s) => [
          '${i + 1}',
          '${s.studentNo} (${s.className})',
          s.fullName,
          s.parentName,
          s.parentPhone,
          '',
        ],
      );
    } else if (isProjectDist) {
      final dueDate = (answers['dueDate'] ?? '').toString();
      tableWidget = _buildStudentTable(
        students: students,
        headers: const ['S.No', 'No / Şube', 'Öğrenci Adı Soyadı', 'Proje / Performans Konusu', 'Teslim Tarihi', 'Öğrenci İmzası'],
        rowBuilder: (i, s) => [
          '${i + 1}',
          '${s.studentNo} (${s.className})',
          s.fullName,
          '',
          dueDate,
          '',
        ],
      );
    } else if (isPracticalExam) {
      tableWidget = _buildStudentTable(
        students: students,
        headers: const [
          'S.No',
          'No / Şube',
          'Öğrenci Adı Soyadı',
          '1. Ölçüt (25p)',
          '2. Ölçüt (25p)',
          '3. Ölçüt (25p)',
          '4. Ölçüt (25p)',
          'Toplam (100)',
        ],
        rowBuilder: (i, s) => [
          '${i + 1}',
          '${s.studentNo} (${s.className})',
          s.fullName,
          '',
          '',
          '',
          '',
          '',
        ],
      );
    } else if (isExamHallRoll) {
      tableWidget = _buildStudentTable(
        students: students,
        headers: const [
          'S.No',
          'Şube / No',
          'Öğrenci Adı Soyadı',
          'Kitapçık / Grup',
          'Katılım Durumu',
          'Öğrenci İmzası',
        ],
        rowBuilder: (i, s) => [
          '${i + 1}',
          '${s.className} / ${s.studentNo}',
          s.fullName,
          '',
          'Sınava Girdi',
          '',
        ],
      );
    } else {
      tableWidget = _buildStaffSignatureTable(signatureStaff);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
        footer: (context) => _buildFooter(context, schoolName),
        build: (context) => [
          _buildHeader(
            style: headerStyle,
            province: province,
            district: district,
            schoolName: schoolName,
            academicYear: ctx.academicYear,
            docCode: template.code,
          ),
          pw.Center(
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                _trUpper(documentTitle),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11.5, color: _navy),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ),
          if (metaRows.isNotEmpty) ...[
            _buildMetaTable(metaRows),
            pw.SizedBox(height: 10),
          ],
          ..._renderFormattedParagraphs(composedBody),
          pw.SizedBox(height: 12),
          tableWidget,
          pw.SizedBox(height: 18),
          ..._buildSignersWidgets(signers),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. TOPLU VELİ İZİN BELGESİ / MUVAFAKATNAME (1 VEYA 2 KESİMLİ A4)
  // ═══════════════════════════════════════════════════════════════════════════
  static void _buildBulkParentSlips({
    required pw.Document pdf,
    required DocHeaderStyle headerStyle,
    required String province,
    required String district,
    required String schoolName,
    required String academicYear,
    required String documentTitle,
    required Map<String, dynamic> answers,
    required String rawBodyTemplate,
    required List<DocStudentItem> students,
  }) {
    final effectiveStudents = students.isNotEmpty
        ? students
        : const [
            DocStudentItem(
              id: 'sample',
              fullName: '........................................',
              studentNo: '......',
              className: '......',
              parentName: '........................................',
            ),
          ];

    final twoPerPage = (answers['slipsPerPage'] ?? '').toString().contains('2');
    final eventDate = (answers['eventDate'] ?? DateFormat('dd.MM.yyyy').format(DateTime.now())).toString();

    pw.Widget buildSingleSlip(DocStudentItem s, {required bool compact}) {
      final filledText = rawBodyTemplate
          .replaceAll('{{OGRENCI_ADI}}', s.fullName)
          .replaceAll('{{SINIF}}', s.className.isNotEmpty ? s.className : '......')
          .replaceAll('{{NO}}', s.studentNo.isNotEmpty ? s.studentNo : '......');

      return pw.Container(
        padding: pw.EdgeInsets.all(compact ? 14 : 22),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _border, width: 0.9),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    '${schoolName.toUpperCase()} — VELİ İZİN / MUVAFAKAT BELGESİ',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: compact ? 10 : 11.5, color: _indigo),
                  ),
                ),
                pw.Text(
                  'Tarih: $eventDate',
                  style: pw.TextStyle(fontSize: compact ? 8.5 : 9.5, color: _slate),
                ),
              ],
            ),
            pw.Divider(color: _border, height: compact ? 10 : 16),
            pw.Text(
              filledText,
              style: pw.TextStyle(fontSize: compact ? 9.3 : 10.5, lineSpacing: compact ? 2.5 : 4, color: _navy),
              textAlign: pw.TextAlign.justify,
            ),
            pw.SizedBox(height: compact ? 10 : 18),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(color: _lightBg, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6))),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Öğrenci: ${s.fullName} (${s.className} - No: ${s.studentNo})',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: compact ? 8.5 : 9.5)),
                        pw.SizedBox(height: 3),
                        pw.Text('Varsa Sağlık / Alerji Notu: .................................................................',
                            style: pw.TextStyle(fontSize: compact ? 8 : 9, color: _slate)),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Acil Durum Veli Tel: ${s.parentPhone.isNotEmpty ? s.parentPhone : "0(5....) ..........................."}',
                          style: pw.TextStyle(fontSize: compact ? 8 : 9, color: _slate),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 14),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('VELİ ADI SOYADI VE İMZASI',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: compact ? 8.5 : 9.5, color: _navy)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        s.parentName.isNotEmpty ? s.parentName : '....................................',
                        style: pw.TextStyle(fontSize: compact ? 8.5 : 9.5),
                      ),
                      pw.SizedBox(height: compact ? 18 : 26),
                      pw.Text('İmza: ..........................', style: pw.TextStyle(fontSize: 8, color: _slate)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (twoPerPage) {
      for (int i = 0; i < effectiveStudents.length; i += 2) {
        final first = effectiveStudents[i];
        final second = (i + 1 < effectiveStudents.length) ? effectiveStudents[i + 1] : null;
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.fromLTRB(32, 26, 32, 26),
            build: (_) => pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                buildSingleSlip(first, compact: true),
                pw.Row(
                  children: [
                    pw.Expanded(child: pw.Divider(color: _border, borderStyle: pw.BorderStyle.dashed)),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                      child: pw.Text('KESİNİZ', style: pw.TextStyle(fontSize: 7.5, color: _slate)),
                    ),
                    pw.Expanded(child: pw.Divider(color: _border, borderStyle: pw.BorderStyle.dashed)),
                  ],
                ),
                if (second != null)
                  buildSingleSlip(second, compact: true)
                else
                  pw.SizedBox(height: 220),
              ],
            ),
          ),
        );
      }
    } else {
      for (final s in effectiveStudents) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(38),
            build: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeader(
                  style: headerStyle,
                  province: province,
                  district: district,
                  schoolName: schoolName,
                  academicYear: academicYear,
                ),
                pw.SizedBox(height: 12),
                buildSingleSlip(s, compact: false),
              ],
            ),
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. DİNAMİK PDF KONTROL & İMZA ÇİZELGESİ
  // ═══════════════════════════════════════════════════════════════════════════
  static void _buildDynamicChecklist({
    required pw.Document pdf,
    required DocHeaderStyle headerStyle,
    required String province,
    required String district,
    required String schoolName,
    required String academicYear,
    required Map<String, dynamic> answers,
    required List<DocStudentItem> students,
    required List<DocStaffItem> staff,
  }) {
    final isStaffTarget = (answers['listTarget'] ?? '').toString().contains('Öğretmen');
    final chartTitle = (answers['chartTitle'] ?? 'KONTROL VE İMZA ÇİZELGESİ').toString();
    final isLandscape = (answers['orientation'] ?? '').toString().contains('Yatay');
    final rawCols = (answers['customColumns'] ?? '1. Kontrol, 2. Kontrol, İmza').toString();
    final extraCols = rawCols
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final headers = <String>[
      'S.No',
      isStaffTarget ? 'Branş / Görev' : 'Şube / No',
      'Adı Soyadı',
      ...extraCols,
    ];

    final List<List<String>> rows = [];
    if (isStaffTarget) {
      for (int i = 0; i < staff.length; i++) {
        final p = staff[i];
        rows.add([
          '${i + 1}',
          p.groupLabel,
          p.fullName,
          ...List.filled(extraCols.length, ''),
        ]);
      }
    } else {
      for (int i = 0; i < students.length; i++) {
        final s = students[i];
        rows.add([
          '${i + 1}',
          '${s.className} / ${s.studentNo}',
          s.fullName,
          ...List.filled(extraCols.length, ''),
        ]);
      }
    }

    if (rows.isEmpty) {
      for (int i = 0; i < 25; i++) {
        rows.add(['${i + 1}', '', '', ...List.filled(extraCols.length, '')]);
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 26),
        footer: (context) => _buildFooter(context, schoolName),
        build: (context) => [
          _buildHeader(
            style: headerStyle,
            province: province,
            district: district,
            schoolName: schoolName,
            academicYear: academicYear,
          ),
          pw.Center(
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pw.Text(
                chartTitle.toUpperCase(),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: _navy),
              ),
            ),
          ),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            border: pw.TableBorder.all(color: _border, width: 0.6),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: _indigo),
            cellStyle: pw.TextStyle(fontSize: 8.5, color: _navy),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5.5),
            oddRowDecoration: pw.BoxDecoration(color: _zebraBg),
            columnWidths: {
              0: const pw.FixedColumnWidth(28),
              1: const pw.FixedColumnWidth(68),
              2: const pw.FlexColumnWidth(2.2),
              for (int c = 0; c < extraCols.length; c++) c + 3: const pw.FlexColumnWidth(1.1),
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. QR YAKA KARTI / SIRA ETİKETİ / KAPI LİSTESİ ÜRETİCİ
  // ═══════════════════════════════════════════════════════════════════════════
  static void _buildBadgeOrDoorList({
    required pw.Document pdf,
    required String schoolName,
    required String academicYear,
    required Map<String, dynamic> answers,
    required List<DocStudentItem> students,
  }) {
    final badgeType = (answers['badgeType'] ?? '').toString();
    final subLabel = (answers['badgeSubLabel'] ?? 'Öğrenci Kartı').toString();
    final showQr = answers['showQr'] != false;

    if (badgeType.contains('Kapı')) {
      // Şube bazlı tam sayfa şık Kapı Listesi
      final byClass = <String, List<DocStudentItem>>{};
      for (final s in students) {
        byClass.putIfAbsent(s.className.isEmpty ? 'GENEL' : s.className, () => []).add(s);
      }
      if (byClass.isEmpty) {
        byClass['ÖRNEK ŞUBE'] = const [];
      }
      byClass.forEach((clsName, list) {
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            footer: (c) => _buildFooter(c, schoolName),
            build: (_) => [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                decoration: pw.BoxDecoration(
                  color: _indigo,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      schoolName.toUpperCase(),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.white),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '$clsName ŞUBESİ SINIF ÖĞRENCİ LİSTESİ ($academicYear)',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.amber200),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              _buildStudentTable(
                students: list,
                headers: const ['Sıra', 'Okul No', 'Öğrenci Adı Soyadı', 'Şube'],
                rowBuilder: (i, s) => ['${i + 1}', s.studentNo, s.fullName, s.className],
              ),
            ],
          ),
        );
      });
      return;
    }

    // Yaka Kartı (8'li: 2x4) veya Dolap Etiketi (10'lu: 2x5)
    final bool isDeskLabel = badgeType.contains('Etiket');
    final int perPage = isDeskLabel ? 10 : 8;
    final double cardHeight = isDeskLabel ? 135 : 172;
    final effectiveList = students.isNotEmpty
        ? students
        : List.generate(
            perPage,
            (i) => DocStudentItem(
              id: 'sample_$i',
              fullName: 'Örnek Öğrenci ${i + 1}',
              studentNo: '${100 + i}',
              className: '5-A',
            ),
          );

    for (int offset = 0; offset < effectiveList.length; offset += perPage) {
      final slice = effectiveList.skip(offset).take(perPage).toList();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (_) => pw.Wrap(
            spacing: 12,
            runSpacing: 12,
            children: slice.map((s) {
              final qrPayload = 'EDUKN|${s.className}|${s.studentNo}|${s.fullName}';
              return pw.Container(
                width: 265,
                height: cardHeight,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _border, width: 1),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: pw.BoxDecoration(
                        color: _indigo,
                        borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(9)),
                      ),
                      child: pw.Text(
                        schoolName.toUpperCase(),
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
                        maxLines: 1,
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.all(10),
                        child: pw.Row(
                          children: [
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                mainAxisAlignment: pw.MainAxisAlignment.center,
                                children: [
                                  pw.Text(
                                    subLabel.toUpperCase(),
                                    style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _slate),
                                  ),
                                  pw.SizedBox(height: 4),
                                  pw.Text(
                                    s.fullName,
                                    style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: _navy),
                                    maxLines: 2,
                                  ),
                                  pw.SizedBox(height: 6),
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: pw.BoxDecoration(
                                      color: _zebraBg,
                                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                                    ),
                                    child: pw.Text(
                                      'Sınıf: ${s.className}   •   No: ${s.studentNo}',
                                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _indigo),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (showQr) ...[
                              pw.SizedBox(width: 8),
                              pw.BarcodeWidget(
                                barcode: pw.Barcode.qrCode(),
                                data: qrPayload,
                                width: isDeskLabel ? 54 : 66,
                                height: isDeskLabel ? 54 : 66,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // YARDIMCI TABLO, METİN VE İMZA BİLEŞENLERİ
  // ═══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildMetaTable(List<MapEntry<String, String>> rows) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: 0.7),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Table(
        border: pw.TableBorder.symmetric(inside: pw.BorderSide(color: _border, width: 0.5)),
        columnWidths: const {
          0: pw.FixedColumnWidth(135),
          1: pw.FlexColumnWidth(),
        },
        children: rows
            .where((r) => r.value.trim().isNotEmpty)
            .map(
              (r) => pw.TableRow(
                children: [
                  pw.Container(
                    color: _lightBg,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: pw.Text(
                      r.key,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: _navy),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: pw.Text(r.value, style: pw.TextStyle(fontSize: 9, color: _navy)),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  static List<pw.Widget> _renderFormattedParagraphs(String text) {
    final cleanText = text.replaceAll('✂', '[KESİNİZ]');
    final lines = cleanText.split('\n');
    final widgets = <pw.Widget>[];

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        widgets.add(pw.SizedBox(height: 6));
        continue;
      }
      final trimmed = line.trim();
      final isCutLine = trimmed.contains('KESİNİZ');
      if (isCutLine) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 8),
            child: pw.Divider(color: _slate, borderStyle: pw.BorderStyle.dashed),
          ),
        );
        continue;
      }
      final isSectionHeader = trimmed == trimmed.toUpperCase() &&
          trimmed.length > 4 &&
          trimmed.length < 85 &&
          !trimmed.startsWith('...') &&
          !RegExp(r'^\d').hasMatch(trimmed);

      widgets.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(bottom: isSectionHeader ? 4 : 3.5, top: isSectionHeader ? 4 : 0),
          child: pw.Text(
            trimmed,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: isSectionHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: _navy,
              lineSpacing: 3,
            ),
            textAlign: isSectionHeader ? pw.TextAlign.left : pw.TextAlign.justify,
          ),
        ),
      );
    }
    return widgets;
  }

  static List<pw.Widget> _buildSignersWidgets(List<DocSigner> signers) {
    if (signers.isEmpty) return const [];

    final regular = signers.where((s) => !s.isApproval).toList();
    final approvals = signers.where((s) => s.isApproval).toList();

    pw.Widget signerBox(DocSigner s, {bool showApprovalHeader = false}) {
      return pw.Container(
        width: 155,
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (showApprovalHeader) ...[
              pw.Text(
                DateFormat('dd.MM.yyyy').format(DateTime.now()),
                style: pw.TextStyle(fontSize: 9, color: _slate),
              ),
              pw.SizedBox(height: 2),
            ],
            pw.Text(
              s.title,
              style: pw.TextStyle(fontSize: 8.8, fontWeight: pw.FontWeight.bold, color: _slate),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              s.name,
              style: pw.TextStyle(fontSize: 9.3, fontWeight: pw.FontWeight.bold, color: _navy),
              textAlign: pw.TextAlign.center,
            ),
            pw.Text('İmza', style: pw.TextStyle(fontSize: 8, color: _slate)),
          ],
        ),
      );
    }

    final List<pw.Widget> widgets = [];

    // 3'lü satırlar halinde bölerek pw.MultiPage içinde çok sayıda (12-25+) ŞÖK öğretmeninin
    // taşmadan ve sayfa kesilmelerine takılmadan akıcı şekilde sayfalanmasını sağla
    for (int i = 0; i < regular.length; i += 3) {
      final chunk = regular.skip(i).take(3).toList();
      final align = (regular.length == 1)
          ? pw.MainAxisAlignment.end
          : (chunk.length == 3
              ? pw.MainAxisAlignment.spaceBetween
              : pw.MainAxisAlignment.spaceAround);

      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            mainAxisAlignment: align,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: chunk.map((s) => signerBox(s)).toList(),
          ),
        ),
      );
    }

    if (approvals.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 10));
      widgets.add(
        pw.Center(
          child: pw.Wrap(
            spacing: 24,
            runSpacing: 12,
            alignment: pw.WrapAlignment.center,
            children: approvals
                .map((a) => signerBox(a, showApprovalHeader: true))
                .toList(),
          ),
        ),
      );
    }

    return widgets;
  }

  static pw.Widget _buildStaffSignatureTable(List<DocStaffItem> staff) {
    final rows = staff.isEmpty
        ? List.generate(15, (i) => ['${i + 1}', '', '', ''])
        : List.generate(
            staff.length,
            (i) => [
              '${i + 1}',
              staff[i].fullName,
              staff[i].groupLabel,
              '',
            ],
          );

    return pw.TableHelper.fromTextArray(
      headers: const ['S.No', 'Adı Soyadı', 'Branşı / Görevi', 'İmza'],
      data: rows,
      border: pw.TableBorder.all(color: _border, width: 0.6),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.8, color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(color: _indigo),
      cellStyle: pw.TextStyle(fontSize: 8.8, color: _navy),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      oddRowDecoration: pw.BoxDecoration(color: _zebraBg),
      columnWidths: const {
        0: pw.FixedColumnWidth(32),
        1: pw.FlexColumnWidth(2.2),
        2: pw.FlexColumnWidth(1.6),
        3: pw.FixedColumnWidth(95),
      },
    );
  }

  static pw.Widget _buildStudentTable({
    required List<DocStudentItem> students,
    required List<String> headers,
    required List<String> Function(int index, DocStudentItem s) rowBuilder,
  }) {
    final data = students.isEmpty
        ? List.generate(18, (i) => ['${i + 1}', ...List.filled(headers.length - 1, '')])
        : List.generate(students.length, (i) => rowBuilder(i, students[i]));

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: _border, width: 0.6),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(color: _indigo),
      cellStyle: pw.TextStyle(fontSize: 8.5, color: _navy),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5.5),
      oddRowDecoration: pw.BoxDecoration(color: _zebraBg),
    );
  }

  static pw.Widget _buildFooter(pw.Context context, String schoolName) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '$schoolName • eduKN Resmi Evrak Otomasyonu',
            style: pw.TextStyle(fontSize: 7.5, color: _slate),
          ),
          pw.Text(
            'Sayfa ${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 7.5, color: _slate),
          ),
        ],
      ),
    );
  }
}

